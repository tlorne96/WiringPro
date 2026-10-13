package com.timlorne.wiringpro.data.repository

import android.content.Context
import android.net.Uri
import com.timlorne.wiringpro.data.db.AppDatabase
import com.timlorne.wiringpro.data.db.ConnectorEntity
import com.timlorne.wiringpro.data.db.ConnectorWithPins
import com.timlorne.wiringpro.data.db.NetEntity
import com.timlorne.wiringpro.data.db.PinEntity
import com.timlorne.wiringpro.data.db.ProjectEntity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

// A net plus a human-readable list of where it's currently connected, e.g.
// ["Main pin 1", "Throttle pin 5"] — this is what lets the net picker show
// what a net already touches instead of just its bare name.
data class NetWithAssignments(val net: NetEntity, val assignmentLabels: List<String>)

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
        return connectorId
    }

    fun observeConnectorsWithPins(projectId: String): Flow<List<ConnectorWithPins>> =
        db.connectorDao().observeWithPinsForProject(projectId)

    fun observeConnectorWithPins(connectorId: String): Flow<ConnectorWithPins?> =
        db.connectorDao().observeWithPins(connectorId)

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

    suspend fun updateNetColors(netId: String, color: String?, stripeColor: String?) {
        db.netDao().updateWireColors(netId, color, stripeColor)
    }

    suspend fun clearPinNet(pinId: String) {
        db.pinDao().assignNet(pinId, null)
    }
}

