#!/bin/bash
# WiringPro: four changes.
# 1) Drops the sync server idea from scope entirely — removes the
#    server/ folder if you have one (harmless if you don't).
# 2) Adds connector duplication — a copy icon next to each connector in
#    the Connectors list. Copies the label + row/pin shape onto a new
#    connector; pin NET ASSIGNMENTS are deliberately NOT copied (two
#    identical-looking connectors usually wire to different nets — e.g.
#    left vs right turn signal — so silently sharing net names across
#    the copy seemed more likely to cause an accidental shared
#    connection than to save real work).
# 3) Fixes the pin-count input UX when creating a connector — row fields
#    now select their whole value on focus, so typing immediately
#    replaces it instead of needing manual select-all/delete first.
# 4) Adds e-dirt-bike-specific standard net types: motor phases (U/V/W),
#    motor hall sensors (A/B/C), motor temp sensor, battery pack
#    positive/negative, main contactor coil, kill switch, sidestand
#    switch, regen brake signal, charge port.
#
# Run from inside the 'wiringpro' folder (the one containing android-app/).
set -e

rm -rf server
echo "Removed server/ (if it existed) — no longer part of the project."

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/data/repository/WiringRepository.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/data/repository/WiringRepository.kt << 'KOTLIN_EOF'
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
    suspend fun createConnector(projectId: String, label: String, rows: List<Int>): String {
        val connectorId = UUID.randomUUID().toString()
        db.connectorDao().upsert(
            ConnectorEntity(
                id = connectorId,
                projectId = projectId,
                label = label,
                rows = rows,
                partRef = null
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
                        label = null
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
    suspend fun getOrCreateNet(projectId: String, name: String, netType: String, color: String?): String {
        db.netDao().findByName(projectId, name)?.let { return it.id }
        val id = UUID.randomUUID().toString()
        db.netDao().upsert(NetEntity(id = id, projectId = projectId, name = name, netType = netType, color = color))
        return id
    }

    suspend fun assignPinToNet(pinId: String, netId: String?) {
        db.pinDao().assignNet(pinId, netId)
    }

    suspend fun clearPinNet(pinId: String) {
        db.pinDao().assignNet(pinId, null)
    }
}

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/data/repository/WiringRepository.kt"

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/connectorlist/ConnectorListScreen.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/connectorlist/ConnectorListScreen.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.ui.screens.connectorlist

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.weight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AccountTree
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.timlorne.wiringpro.data.db.ConnectorWithPins
import com.timlorne.wiringpro.data.repository.WiringRepository
import com.timlorne.wiringpro.pdf.DiagramPdfGenerator
import com.timlorne.wiringpro.pdf.PdfSaver
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class ConnectorListViewModel(
    private val repository: WiringRepository,
    private val projectId: String
) : ViewModel() {
    val connectors = repository.observeConnectorsWithPins(projectId)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val nets = repository.observeNets(projectId)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    private suspend fun generatePdf(context: Context): File {
        val project = repository.getProject(projectId) ?: error("Project not found")
        val currentConnectors = repository.observeConnectorsWithPins(projectId).first()
        val currentNets = repository.observeNets(projectId).first()
        return withContext(Dispatchers.IO) {
            DiagramPdfGenerator.generate(context, project, currentConnectors, currentNets)
        }
    }

    fun exportForShare(context: Context, onReady: (File) -> Unit, onError: (String) -> Unit) {
        viewModelScope.launch {
            try {
                onReady(generatePdf(context))
            } catch (e: Exception) {
                onError(e.message ?: e.toString())
            }
        }
    }

    /** Generates the PDF and copies it to a destination the user already picked via the system file picker. */
    fun exportAndSaveToUri(context: Context, destination: Uri, onResult: (success: Boolean, message: String) -> Unit) {
        viewModelScope.launch {
            try {
                val file = generatePdf(context)
                withContext(Dispatchers.IO) { PdfSaver.copyToUri(context, file, destination) }
                onResult(true, "Saved")
            } catch (e: Exception) {
                onResult(false, "Error: ${e.message ?: e.toString()}")
            }
        }
    }

    fun duplicateConnector(connectorId: String) {
        viewModelScope.launch { repository.duplicateConnector(connectorId) }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConnectorListScreen(
    viewModel: ConnectorListViewModel,
    onAddConnector: () -> Unit,
    onOpenConnector: (String) -> Unit,
    onViewLoom: () -> Unit
) {
    val connectors by viewModel.connectors.collectAsState()
    val context = LocalContext.current

    // System file picker for saving — the user chooses exactly where the
    // PDF goes, so there's no ambiguity about which "Downloads" folder a
    // given device/vendor actually means.
    val savePickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.CreateDocument("application/pdf")
    ) { uri ->
        if (uri != null) {
            viewModel.exportAndSaveToUri(context, uri) { _, message ->
                Toast.makeText(context, message, Toast.LENGTH_LONG).show()
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Connectors") },
                actions = {
                    IconButton(onClick = { savePickerLauncher.launch("wiringpro-diagram.pdf") }) {
                        Icon(Icons.Filled.Save, contentDescription = "Save PDF")
                    }
                    IconButton(onClick = {
                        viewModel.exportForShare(
                            context = context,
                            onReady = { file ->
                                val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
                                val intent = Intent(Intent.ACTION_SEND).apply {
                                    type = "application/pdf"
                                    putExtra(Intent.EXTRA_STREAM, uri)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                context.startActivity(Intent.createChooser(intent, "Share wiring diagram"))
                            },
                            onError = { message ->
                                Toast.makeText(context, "Export failed: $message", Toast.LENGTH_LONG).show()
                            }
                        )
                    }) {
                        Icon(Icons.Filled.Share, contentDescription = "Share PDF")
                    }
                    IconButton(onClick = onViewLoom) {
                        Icon(Icons.Filled.AccountTree, contentDescription = "View whole loom")
                    }
                }
            )
        },
        floatingActionButton = {
            FloatingActionButton(onClick = onAddConnector) {
                Icon(Icons.Filled.Add, contentDescription = "Add connector")
            }
        }
    ) { padding ->
        if (connectors.isEmpty()) {
            Text(
                "No connectors yet — tap + to add one.",
                modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp)
            )
        } else {
            LazyColumn(modifier = Modifier.fillMaxSize().padding(padding)) {
                items(connectors, key = { it.connector.id }) { cwp: ConnectorWithPins ->
                    val assignedCount = cwp.pins.count { it.netId != null }
                    androidx.compose.foundation.layout.Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically
                    ) {
                        Text(
                            text = "${cwp.connector.label} — ${cwp.pins.size} pins, $assignedCount assigned",
                            modifier = Modifier
                                .weight(1f)
                                .clickable { onOpenConnector(cwp.connector.id) }
                                .padding(16.dp)
                        )
                        IconButton(onClick = { viewModel.duplicateConnector(cwp.connector.id) }) {
                            Icon(Icons.Filled.ContentCopy, contentDescription = "Duplicate ${cwp.connector.label}")
                        }
                    }
                }
            }
        }
    }
}

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/connectorlist/ConnectorListScreen.kt"

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/newconnector/NewConnectorScreen.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/newconnector/NewConnectorScreen.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.ui.screens.newconnector

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.timlorne.wiringpro.data.repository.WiringRepository
import kotlinx.coroutines.launch

class NewConnectorViewModel(
    private val repository: WiringRepository,
    private val projectId: String
) : ViewModel() {
    fun createConnector(label: String, rows: List<Int>, onCreated: (String) -> Unit) {
        viewModelScope.launch {
            val id = repository.createConnector(projectId, label, rows)
            onCreated(id)
        }
    }
}

/**
 * Asks how many rows a connector has and how many pins are in each row —
 * the camera-based version is deferred, this is the whole input flow for now.
 *
 * Row-count fields select their whole value on focus, so tapping straight
 * into typing a new number replaces it instead of requiring a manual
 * select-all/delete first.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NewConnectorScreen(
    viewModel: NewConnectorViewModel,
    onConnectorCreated: (String) -> Unit,
    onBack: () -> Unit
) {
    var label by remember { mutableStateOf("") }
    val rowCounts = remember { mutableStateListOf(TextFieldValue("6")) }

    Scaffold(topBar = { TopAppBar(title = { Text("New connector") }) }) { padding ->
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(padding)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            OutlinedTextField(
                value = label,
                onValueChange = { label = it },
                label = { Text("Connector label") },
                placeholder = { Text("e.g. Main 24-pin, Throttle 6-pin") },
                modifier = Modifier.fillMaxWidth()
            )

            Text("Rows (top to bottom) — pins per row")
            LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(rowCounts.size) { i ->
                    Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                        Text("Row ${i + 1}:", modifier = Modifier.padding(end = 8.dp))
                        OutlinedTextField(
                            value = rowCounts[i],
                            onValueChange = { new -> rowCounts[i] = new },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                            modifier = Modifier
                                .padding(end = 8.dp)
                                .onFocusChanged { focusState ->
                                    if (focusState.isFocused) {
                                        rowCounts[i] = rowCounts[i].copy(
                                            selection = TextRange(0, rowCounts[i].text.length)
                                        )
                                    }
                                }
                        )
                        IconButton(onClick = { if (rowCounts.size > 1) rowCounts.removeAt(i) }) {
                            Text("✕")
                        }
                    }
                }
            }

            Row {
                Button(onClick = {
                    rowCounts.add(TextFieldValue(rowCounts.lastOrNull()?.text ?: "6"))
                }) {
                    Text("Add row")
                }
            }

            val totalPins = rowCounts.sumOf { it.text.toIntOrNull() ?: 0 }
            Text("Total pins: $totalPins")

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = onBack) { Text("Cancel") }
                Button(
                    enabled = label.isNotBlank() && rowCounts.isNotEmpty(),
                    onClick = {
                        val rows = rowCounts.map { (it.text.toIntOrNull() ?: 1).coerceAtLeast(1) }
                        viewModel.createConnector(label.trim(), rows, onConnectorCreated)
                    }
                ) { Text("Create") }
            }
        }
    }
}

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/newconnector/NewConnectorScreen.kt"

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/data/model/StandardNetTypes.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/data/model/StandardNetTypes.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.data.model

// Keep this in sync by hand with shared/net-types.json — it's the same list,
// duplicated here because the app doesn't parse JSON off disk for this yet.
data class StandardNetType(val type: String, val label: String, val defaultColor: String?)

object StandardNetTypes {
    val ALL = listOf(
        StandardNetType("GND", "Ground / common ground", "#000000"),
        StandardNetType("12V_SUPPLY", "12V battery supply", "#8B0000"),
        StandardNetType("5V_SUPPLY", "5V sensor supply", "#FF0000"),
        StandardNetType("IGNITION_ON", "Ignition / key on", "#FFA500"),
        StandardNetType("THROTTLE_SIGNAL_A", "Throttle signal A", "#00AEEF"),
        StandardNetType("THROTTLE_SIGNAL_B", "Throttle signal B", "#7CFC00"),
        StandardNetType("BRAKE_SIGNAL", "Brake switch signal", "#FFFF00"),
        StandardNetType("HORN", "Horn", "#A0522D"),
        StandardNetType("TURN_SIGNAL_L", "Turn signal - left", "#008000"),
        StandardNetType("TURN_SIGNAL_R", "Turn signal - right", "#FF69B4"),
        StandardNetType("HEADLIGHT", "Headlight", "#A9A9A9"),
        StandardNetType("TAILLIGHT_BRAKE", "Taillight / brake light", "#DC143C"),
        StandardNetType("CAN_H", "CAN bus high", "#4B0082"),
        StandardNetType("CAN_L", "CAN bus low", "#9370DB"),
        StandardNetType("SPEED_SENSOR", "Speed sensor signal", "#40E0D0"),
        StandardNetType("DISPLAY_DATA", "Display data line", "#DAA520"),
        // Electric-drivetrain specific — added for e-bike/PEV builds (BLDC
        // hub/mid-drive motor, main pack, contactor, kill/sidestand switches).
        StandardNetType("MOTOR_PHASE_U", "Motor phase U", "#1E90FF"),
        StandardNetType("MOTOR_PHASE_V", "Motor phase V", "#FF7F50"),
        StandardNetType("MOTOR_PHASE_W", "Motor phase W", "#6A5ACD"),
        StandardNetType("MOTOR_HALL_A", "Motor hall sensor A", "#20B2AA"),
        StandardNetType("MOTOR_HALL_B", "Motor hall sensor B", "#BA55D3"),
        StandardNetType("MOTOR_HALL_C", "Motor hall sensor C", "#CD5C5C"),
        StandardNetType("MOTOR_TEMP_SENSOR", "Motor temperature sensor", "#556B2F"),
        StandardNetType("BATTERY_POSITIVE", "Battery pack positive", "#B22222"),
        StandardNetType("BATTERY_NEGATIVE", "Battery pack negative", "#2F4F4F"),
        StandardNetType("CONTACTOR_COIL", "Main contactor coil", "#DA70D6"),
        StandardNetType("KILL_SWITCH", "Kill switch", "#B03060"),
        StandardNetType("SIDESTAND_SWITCH", "Sidestand / kickstand switch", "#8FBC8F"),
        StandardNetType("REGEN_BRAKE_SIGNAL", "Regen brake signal", "#FFD700"),
        StandardNetType("CHARGE_PORT", "Charge port", "#32CD32"),
        StandardNetType("CUSTOM", "Custom / user-defined", null)
    )
}

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/data/model/StandardNetTypes.kt"

mkdir -p "$(dirname "shared/net-types.json")"
cat > shared/net-types.json << 'JSON_EOF'
{
  "description": "Standard signal types selectable when assigning a pin to a net. Users can still type a custom net name — this list just pre-fills common ones so naming stays consistent across projects and part-library imports.",
  "standardTypes": [
    { "type": "GND",              "label": "Ground / Common Ground",     "defaultColor": "#000000" },
    { "type": "12V_SUPPLY",       "label": "12V Battery Supply",         "defaultColor": "#8B0000" },
    { "type": "5V_SUPPLY",        "label": "5V Sensor Supply",           "defaultColor": "#FF0000" },
    { "type": "IGNITION_ON",      "label": "Ignition / Key On",          "defaultColor": "#FFA500" },
    { "type": "THROTTLE_SIGNAL_A","label": "Throttle Signal A",          "defaultColor": "#00AEEF" },
    { "type": "THROTTLE_SIGNAL_B","label": "Throttle Signal B",          "defaultColor": "#7CFC00" },
    { "type": "BRAKE_SIGNAL",     "label": "Brake Switch Signal",        "defaultColor": "#FFFF00" },
    { "type": "HORN",             "label": "Horn",                        "defaultColor": "#A0522D" },
    { "type": "TURN_SIGNAL_L",    "label": "Turn Signal - Left",         "defaultColor": "#008000" },
    { "type": "TURN_SIGNAL_R",    "label": "Turn Signal - Right",        "defaultColor": "#FF69B4" },
    { "type": "HEADLIGHT",        "label": "Headlight",                   "defaultColor": "#A9A9A9" },
    { "type": "TAILLIGHT_BRAKE",  "label": "Taillight / Brake Light",    "defaultColor": "#DC143C" },
    { "type": "CAN_H",            "label": "CAN Bus High",                "defaultColor": "#4B0082" },
    { "type": "CAN_L",            "label": "CAN Bus Low",                 "defaultColor": "#9370DB" },
    { "type": "SPEED_SENSOR",     "label": "Speed Sensor Signal",        "defaultColor": "#40E0D0" },
    { "type": "DISPLAY_DATA",     "label": "Display Data Line",          "defaultColor": "#DAA520" },
    { "type": "MOTOR_PHASE_U",    "label": "Motor Phase U",              "defaultColor": "#1E90FF" },
    { "type": "MOTOR_PHASE_V",    "label": "Motor Phase V",              "defaultColor": "#FF7F50" },
    { "type": "MOTOR_PHASE_W",    "label": "Motor Phase W",              "defaultColor": "#6A5ACD" },
    { "type": "MOTOR_HALL_A",     "label": "Motor Hall Sensor A",        "defaultColor": "#20B2AA" },
    { "type": "MOTOR_HALL_B",     "label": "Motor Hall Sensor B",        "defaultColor": "#BA55D3" },
    { "type": "MOTOR_HALL_C",     "label": "Motor Hall Sensor C",        "defaultColor": "#CD5C5C" },
    { "type": "MOTOR_TEMP_SENSOR","label": "Motor Temperature Sensor",   "defaultColor": "#556B2F" },
    { "type": "BATTERY_POSITIVE", "label": "Battery Pack Positive",      "defaultColor": "#B22222" },
    { "type": "BATTERY_NEGATIVE", "label": "Battery Pack Negative",      "defaultColor": "#2F4F4F" },
    { "type": "CONTACTOR_COIL",   "label": "Main Contactor Coil",        "defaultColor": "#DA70D6" },
    { "type": "KILL_SWITCH",      "label": "Kill Switch",                "defaultColor": "#B03060" },
    { "type": "SIDESTAND_SWITCH", "label": "Sidestand / Kickstand Switch","defaultColor": "#8FBC8F" },
    { "type": "REGEN_BRAKE_SIGNAL","label": "Regen Brake Signal",        "defaultColor": "#FFD700" },
    { "type": "CHARGE_PORT",      "label": "Charge Port",                "defaultColor": "#32CD32" },
    { "type": "CUSTOM",           "label": "Custom / user-defined",      "defaultColor": null }
  ]
}

JSON_EOF
echo "Wrote shared/net-types.json"

echo ""
echo "Done. No Gradle changes — just rebuild/Run."
