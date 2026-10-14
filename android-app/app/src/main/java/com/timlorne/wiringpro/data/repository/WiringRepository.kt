package com.timlorne.wiringpro.data.repository

import android.content.Context
import android.net.Uri
import com.timlorne.wiringpro.data.db.AppDatabase
import com.timlorne.wiringpro.data.db.ConnectorEntity
import com.timlorne.wiringpro.data.db.ConnectorWithPins
import com.timlorne.wiringpro.data.db.HarnessCableEntity
import com.timlorne.wiringpro.data.db.HarnessPlacementEntity
import com.timlorne.wiringpro.data.db.NetEntity
import com.timlorne.wiringpro.data.db.PinEntity
import com.timlorne.wiringpro.data.db.ProjectEntity
import com.timlorne.wiringpro.data.model.StandardNetTypes
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import kotlin.math.abs
import java.io.File
import java.util.UUID

// A net plus a human-readable list of where it's currently connected, e.g.
// ["Main pin 1", "Throttle pin 5"] — this is what lets the net picker show
// what a net already touches instead of just its bare name.
data class NetWithAssignments(val net: NetEntity, val assignmentLabels: List<String>)

private data class TemplateSignal(
    val key: String,
    val type: String,
    val name: String,
    val color: String?,
    val common: Boolean,
    val preferredControllerPin: Pair<Int, Int>?
)

private data class TemplateSignalPin(val signal: TemplateSignal, val pin: PinEntity)

private fun matchingLabelKey(label: String?): String? {
    val normalized = label
        ?.substringBefore('|')
        ?.filterNot { it.isWhitespace() || it == '+' }
        ?.uppercase()
        ?.takeIf { it.isNotEmpty() }
        ?: return null
    return when (normalized) {
        "GND", "GROUND", "0V" -> "GND"
        else -> normalized
    }
}

private fun templateSignalForPin(label: String?): TemplateSignal? {
    val sections = label?.split('|') ?: return null
    fun normalize(value: String?): String = value.orEmpty()
        .filterNot { it.isWhitespace() || it == '+' || it == '/' }
        .uppercase()

    val pinName = normalize(sections.firstOrNull())
    val rawFunction = sections.getOrNull(1)
    val function = normalize(rawFunction)
    val preferredControllerPin = Regex("CONNECTOR(\\d+)PIN(\\d+)")
        .find(function)
        ?.let { match ->
            val connectorNumber = match.groupValues[1].toIntOrNull()
            val pinNumber = match.groupValues[2].toIntOrNull()
            if (connectorNumber != null && pinNumber != null) connectorNumber to pinNumber else null
        }
    val signal = when {
        pinName == "PWMIN" || pinName == "PWMOUT" -> Triple("PWM_INPUT", "PWM IN", false)
        pinName == "MTEMP" || pinName.contains("MOTORTEMP") || function.contains("MOTORTEMPERATURE") ->
            Triple("MOTOR_TEMP_SENSOR", "Motor Temp", false)
        pinName == "5V" -> Triple("5V_SUPPLY", "5V", true)
        pinName in setOf("12V", "12VOUTPUT", "OUTPUT12V") -> Triple("12V_SUPPLY", "12V", true)
        pinName == "GND" || pinName == "GROUND" || pinName.startsWith("0V") ->
            Triple("GND", "Ground", true)
        pinName in setOf("0VOUTPUT", "OUTPUT0V") -> Triple("GND", "Ground", true)
        pinName == "36V" -> Triple("36V_SUPPLY", "36V", false)
        pinName in setOf("BATTERYPOS", "BATTERYPOSITIVE", "B") ->
            Triple("36V_SUPPLY", "36V", false)
        pinName in setOf("BATTERYNEG", "BATTERYNEGATIVE", "B-") ->
            Triple("GND", "Ground", true)
        (pinName.startsWith("CAN2") && pinName.contains("LOW")) || function.contains("CAN2BUSLOW") ->
            Triple("CAN2_L", "CAN 2 BUS Low", false)
        (pinName.startsWith("CAN2") && pinName.contains("HIGH")) || function.contains("CAN2BUSHIGH") ->
            Triple("CAN2_H", "CAN 2 BUS High", false)
        pinName.startsWith("CAN") && pinName.contains("LOW") || function.contains("CANBUSLOW") ->
            Triple("CAN_L", "CAN Low", false)
        pinName.startsWith("CAN") && pinName.contains("HIGH") || function.contains("CANBUSHIGH") ->
            Triple("CAN_H", "CAN High", false)
        pinName.contains("IGNITION") || function == "IGNITION" ->
            Triple("IGNITION_ON", "Ignition", false)
        pinName == "NRST" -> Triple("CUSTOM", "NRST", false)
        pinName == "SWDIO" -> Triple("CUSTOM", "SWDIO", false)
        pinName == "SWCLK" || pinName == "SWDCLK" -> Triple("CUSTOM", "SWCLK", false)
        pinName == "TX1" -> Triple("CUSTOM", "TX1", false)
        pinName == "RX1" -> Triple("CUSTOM", "RX1", false)
        pinName.startsWith("DIN") && pinName.length > 3 && pinName.drop(3).all(Char::isDigit) ->
            Triple("CUSTOM", "DIN ${pinName.drop(3)}", false)
        pinName == "SENSOR1" || pinName.startsWith("THROTTLE1") || function.contains("THROTTLE1") ->
            Triple("THROTTLE_SIGNAL_A", "Sensor 1", false)
        pinName == "SENSOR2" || pinName.startsWith("THROTTLE2") || function.contains("THROTTLE2") ->
            Triple("THROTTLE_SIGNAL_B", "Sensor 2", false)
        pinName in setOf("ANALOGINPUTREGEN", "ANALOGUEINPUTREGEN") ->
            Triple("REGEN_BRAKE_SIGNAL", "Analog Input Regen", false)
        pinName.startsWith("HALLA") || function.contains("ENCODERA") ->
            Triple("MOTOR_HALL_A", "Hall A", false)
        pinName.startsWith("HALLB") || function.contains("ENCODERB") ->
            Triple("MOTOR_HALL_B", "Hall B", false)
        pinName.startsWith("HALLC") || pinName.startsWith("HALLZ") ||
            function.contains("ENCODERC") || function.contains("ENCODERZ") ->
            Triple("MOTOR_HALL_C", "Hall C", false)
        else -> return null
    }
    val (type, name, common) = signal
    val standardType = StandardNetTypes.ALL.firstOrNull { it.type == type }
    val matchingKey = if (type == "CUSTOM") name else type
    return TemplateSignal(matchingKey, type, name, standardType?.defaultColor, common, preferredControllerPin)
}

class WiringRepository(private val db: AppDatabase) {

    // -------------------------------------------------------------
    // Projects
    // -------------------------------------------------------------

    fun observeProjects(): Flow<List<ProjectEntity>> = db.projectDao().observeAll()

    suspend fun createProject(name: String): String {
        val id = UUID.randomUUID().toString()
        val now = System.currentTimeMillis()
        db.projectDao().upsert(
            ProjectEntity(id = id, name = name, vehicle = null, notes = null, createdAt = now, updatedAt = now)
        )
        return id
    }

    suspend fun getProject(id: String): ProjectEntity? = db.projectDao().getById(id)

    /**
     * Copies the picked photo into app-private storage (so it survives even
     * if the original is deleted from the gallery) and records the path.
     * One file per project, overwritten on re-pick.
     */
    suspend fun setProjectImage(projectId: String, uri: Uri, context: Context) {
        withContext(Dispatchers.IO) {
            val dir = File(context.filesDir, "project_images").apply { mkdirs() }
            val dest = File(dir, "$projectId.jpg")
            context.contentResolver.openInputStream(uri)?.use { input ->
                dest.outputStream().use { output -> input.copyTo(output) }
            }
            db.projectDao().setImagePath(projectId, dest.absolutePath)
        }
    }

    // -------------------------------------------------------------
    // Connectors + pins
    // -------------------------------------------------------------

    /**
     * Creates a connector and generates its pins.
     *
     * Numbering rule (per project decision): pins are indexed left-to-right,
     * then top-to-bottom — reading like a book. Given rows = [8, 8, 8] for a
     * 24-pin connector, pin 1 is row 0/col 0, pin 8 is row 0/col 7, pin 9 is
     * row 1/col 0, and so on. This is the one place that numbering logic
     * lives — don't duplicate it in the UI layer.
     */
    suspend fun createConnector(
        projectId: String,
        label: String,
        rows: List<Int>,
        partRef: String? = null,
        pinLabels: List<String?> = emptyList()
    ): String {
        val connectorId = UUID.randomUUID().toString()
        db.connectorDao().upsert(
            ConnectorEntity(
                id = connectorId,
                projectId = projectId,
                label = label,
                rows = rows,
                partRef = partRef
            )
        )

        val pins = mutableListOf<PinEntity>()
        var pinIndex = 1
        for (row in rows.indices) {
            for (col in 0 until rows[row]) {
                pins.add(
                    PinEntity(
                        id = UUID.randomUUID().toString(),
                        connectorId = connectorId,
                        index = pinIndex,
                        row = row,
                        col = col,
                        netId = null,
                        label = pinLabels.getOrNull(pinIndex - 1)
                    )
                )
                pinIndex++
            }
        }
        db.pinDao().upsertAll(pins)
        if (partRef != null) autoConnectTemplatePins(projectId, connectorId)
        return connectorId
    }

    private suspend fun autoConnectTemplatePins(projectId: String, newConnectorId: String) {
        val connectorsById = db.connectorDao().observeForProject(projectId).first().associateBy { it.id }
        val matchingPins = db.pinDao().getForProject(projectId)
            .mapNotNull { pin -> templateSignalForPin(pin.label)?.let { TemplateSignalPin(it, pin) } }
            .groupBy({ it.signal.key }, { it })

        for (entries in matchingPins.values) {
            val newPins = entries.filter { it.pin.connectorId == newConnectorId }
            val peerPins = entries.filter { it.pin.connectorId != newConnectorId }
            if (newPins.isEmpty() || peerPins.isEmpty()) continue

            val signal = entries.first().signal
            if (signal.common) {
                val existingNetIds = entries.mapNotNull { it.pin.netId }.distinct()
                val closestAssignedPeer = newPins.firstOrNull()?.let { newPin ->
                    peerPins.filter { it.pin.netId != null }
                        .minByOrNull { abs(it.pin.index - newPin.pin.index) }
                }
                val netId = existingNetIds.singleOrNull()
                    ?: closestAssignedPeer?.pin?.netId
                    ?: getOrCreateNet(projectId, signal.name, signal.type, signal.color)
                entries.forEach { db.pinDao().assignNet(it.pin.id, netId) }
            } else {
                for (newPin in newPins.filter { it.pin.netId == null }) {
                    val preferredPeer = newPin.signal.preferredControllerPin?.let { (connectorNumber, pinIndex) ->
                        peerPins.firstOrNull {
                            it.pin.index == pinIndex &&
                                connectorsById[it.pin.connectorId]?.label?.contains(
                                    "Connector $connectorNumber",
                                    ignoreCase = true
                                ) == true
                        }
                    }
                    val nearestPeer = preferredPeer ?: peerPins.minByOrNull {
                        abs(it.pin.index - newPin.pin.index)
                    } ?: continue
                    val netId = nearestPeer.pin.netId
                        ?: getOrCreateNet(projectId, signal.name, signal.type, signal.color)
                    db.pinDao().assignNetIfUnassigned(nearestPeer.pin.id, netId)
                    db.pinDao().assignNetIfUnassigned(newPin.pin.id, netId)
                }
            }
        }
    }

    fun observeConnectorsWithPins(projectId: String): Flow<List<ConnectorWithPins>> =
        db.connectorDao().observeWithPinsForProject(projectId)

    fun observeConnectorWithPins(connectorId: String): Flow<ConnectorWithPins?> =
        db.connectorDao().observeWithPins(connectorId)

    fun observeHarnessPlacements(projectId: String): Flow<List<HarnessPlacementEntity>> =
        db.harnessDao().observePlacements(projectId)

    fun observeHarnessCables(projectId: String): Flow<List<HarnessCableEntity>> =
        db.harnessDao().observeCables(projectId)

    suspend fun saveHarnessPlacement(projectId: String, connectorId: String, xDp: Float, yDp: Float) {
        db.harnessDao().upsertPlacement(HarnessPlacementEntity(connectorId, projectId, xDp, yDp))
    }

    suspend fun saveHarnessCableLength(projectId: String, connectorAId: String, connectorBId: String, lengthMm: Int) {
        require(connectorAId != connectorBId) { "A cable must connect two different connectors" }
        require(lengthMm > 0) { "Cable length must be greater than zero" }
        val (fromConnectorId, toConnectorId) = listOf(connectorAId, connectorBId).sorted()
        db.harnessDao().upsertCable(
            HarnessCableEntity(
                id = "$fromConnectorId:$toConnectorId",
                projectId = projectId,
                fromConnectorId = fromConnectorId,
                toConnectorId = toConnectorId,
                lengthMm = lengthMm
            )
        )
    }

    suspend fun deleteConnector(connectorId: String) {
        db.connectorDao().deleteById(connectorId)
    }

    /**
     * Duplicates a connector's shape (label + rows) as a new connector with
     * freshly generated, unassigned pins — deliberately does NOT copy net
     * assignments. Two identical-looking connectors (e.g. left/right turn
     * signal) usually wire to different nets, so silently reusing the same
     * net names across the copy would be more likely to create an
     * unintended shared connection than to save real work.
     */
    suspend fun duplicateConnector(connectorId: String): String {
        val original = db.connectorDao().observeWithPins(connectorId).first()
            ?: error("Connector not found")
        return createConnector(
            projectId = original.connector.projectId,
            label = "${original.connector.label} (copy)",
            rows = original.connector.rows
        )
    }

    // -------------------------------------------------------------
    // Nets
    // -------------------------------------------------------------

    fun observeNets(projectId: String): Flow<List<NetEntity>> =
        db.netDao().observeForProject(projectId)

    /**
     * Nets in the project alongside where each one is currently connected —
     * "Main pin 1", "Throttle pin 5", etc. Powers the net picker's
     * "already used in this project" list so assigning a pin shows what
     * you're actually about to join it to, not just a bare net name.
     */
    fun observeNetsWithAssignments(projectId: String): Flow<List<NetWithAssignments>> =
        combine(observeNets(projectId), db.pinDao().observeAssignmentsForProject(projectId)) { nets, rows ->
            val byNet = rows.groupBy { it.netId }
            nets.map { net ->
                val labels = byNet[net.id]?.map { "${it.connectorLabel} pin ${it.pinIndex}" } ?: emptyList()
                NetWithAssignments(net, labels)
            }
        }

    /**
     * Finds an existing net with this name in the project, or creates one.
     * This is what makes "ground fans out to five places" work: assigning
     * the same net name to five different pins reuses one NetEntity instead
     * of creating five disconnected ones.
     */
    suspend fun getOrCreateNet(
        projectId: String,
        name: String,
        netType: String,
        color: String?,
        stripeColor: String? = null
    ): String {
        db.netDao().findByName(projectId, name)?.let { return it.id }
        val id = UUID.randomUUID().toString()
        db.netDao().upsert(
            NetEntity(
                id = id,
                projectId = projectId,
                name = name,
                netType = netType,
                color = color,
                stripeColor = stripeColor
            )
        )
        return id
    }

    suspend fun assignPinToNet(pinId: String, netId: String?) {
        db.pinDao().assignNet(pinId, netId)
    }

    suspend fun assignPinToMatchingAssignedLabel(pinId: String, projectId: String): Boolean {
        val projectPins = db.pinDao().getForProject(projectId)
        val targetPin = projectPins.firstOrNull { it.id == pinId } ?: return false
        if (targetPin.netId != null) return false
        val targetKey = matchingLabelKey(targetPin.label) ?: return false
        val matchingNetIds = projectPins.asSequence()
            .filter { it.id != pinId && it.netId != null && matchingLabelKey(it.label) == targetKey }
            .mapNotNull { it.netId }
            .distinct()
            .toList()
        val matchingNetId = matchingNetIds.singleOrNull() ?: return false
        return db.pinDao().assignNetIfUnassigned(pinId, matchingNetId) > 0
    }

    suspend fun updateNetColors(netId: String, color: String?, stripeColor: String?) {
        db.netDao().updateWireColors(netId, color, stripeColor)
    }

    suspend fun clearPinNet(pinId: String) {
        db.pinDao().assignNet(pinId, null)
    }
}

