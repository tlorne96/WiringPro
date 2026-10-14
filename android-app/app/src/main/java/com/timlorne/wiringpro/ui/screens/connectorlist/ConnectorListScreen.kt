package com.timlorne.wiringpro.ui.screens.connectorlist

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AccountTree
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.timlorne.wiringpro.data.db.ConnectorWithPins
import com.timlorne.wiringpro.data.repository.WiringRepository
import com.timlorne.wiringpro.pdf.DiagramPdfGenerator
import com.timlorne.wiringpro.pdf.PdfConnectorView
import com.timlorne.wiringpro.pdf.PdfWireLayout
import com.timlorne.wiringpro.pdf.PdfSaver
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

private fun suggestedPdfFileName(projectName: String): String {
    val safeName = projectName.trim()
        .map { character -> if (character in charArrayOf('/', '\\', ':', '*', '?', '"', '<', '>', '|')) '_' else character }
        .joinToString("")
        .trimEnd('.')
        .ifBlank { "wiringpro" }
    return "$safeName.pdf"
}

class ConnectorListViewModel(
    private val repository: WiringRepository,
    private val projectId: String
) : ViewModel() {
    val connectors = repository.observeConnectorsWithPins(projectId)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val nets = repository.observeNets(projectId)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val projectName = repository.observeProjects()
        .map { projects -> projects.firstOrNull { it.id == projectId }?.name.orEmpty() }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), "")

    private suspend fun generatePdf(
        context: Context,
        wireLayout: PdfWireLayout,
        includeRoutingTable: Boolean,
        connectorView: PdfConnectorView
    ): File {
        val project = repository.getProject(projectId) ?: error("Project not found")
        val currentConnectors = repository.observeConnectorsWithPins(projectId).first()
        val currentNets = repository.observeNets(projectId).first()
        return withContext(Dispatchers.IO) {
            DiagramPdfGenerator.generate(
                context,
                project,
                currentConnectors,
                currentNets,
                wireLayout,
                includeRoutingTable,
                connectorView
            )
        }
    }

    fun exportForShare(
        context: Context,
        wireLayout: PdfWireLayout,
        includeRoutingTable: Boolean,
        connectorView: PdfConnectorView,
        onReady: (File) -> Unit,
        onError: (String) -> Unit
    ) {
        viewModelScope.launch {
            try {
                onReady(generatePdf(context, wireLayout, includeRoutingTable, connectorView))
            } catch (e: Exception) {
                onError(e.message ?: e.toString())
            }
        }
    }

    /** Generates the PDF and copies it to a destination the user already picked via the system file picker. */
    fun exportAndSaveToUri(
        context: Context,
        destination: Uri,
        wireLayout: PdfWireLayout,
        includeRoutingTable: Boolean,
        connectorView: PdfConnectorView,
        onResult: (success: Boolean, message: String) -> Unit
    ) {
        viewModelScope.launch {
            try {
                val file = generatePdf(context, wireLayout, includeRoutingTable, connectorView)
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

    fun deleteConnector(connectorId: String) {
        viewModelScope.launch { repository.deleteConnector(connectorId) }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConnectorListScreen(
    viewModel: ConnectorListViewModel,
    onBack: () -> Unit,
    onAddConnector: () -> Unit,
    onOpenConnector: (String) -> Unit,
    onViewLoom: () -> Unit
) {
    val connectors by viewModel.connectors.collectAsState()
    val projectName by viewModel.projectName.collectAsState()
    val context = LocalContext.current
    var connectorPendingDeletion by remember { mutableStateOf<ConnectorWithPins?>(null) }
    var showPdfOptions by remember { mutableStateOf(false) }
    var selectedPdfLayout by remember { mutableStateOf(PdfWireLayout.INDIVIDUAL) }
    var pendingSaveLayout by remember { mutableStateOf(PdfWireLayout.INDIVIDUAL) }
    var selectedConnectorView by remember { mutableStateOf(PdfConnectorView.STANDARD) }
    var pendingSaveConnectorView by remember { mutableStateOf(PdfConnectorView.STANDARD) }
    var includeRoutingTable by remember { mutableStateOf(false) }
    var pendingSaveRoutingTable by remember { mutableStateOf(false) }

    // System file picker for saving — the user chooses exactly where the
    // PDF goes, so there's no ambiguity about which "Downloads" folder a
    // given device/vendor actually means.
    val savePickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.CreateDocument("application/pdf")
    ) { uri ->
        if (uri != null) {
            viewModel.exportAndSaveToUri(
                context,
                uri,
                pendingSaveLayout,
                pendingSaveRoutingTable,
                pendingSaveConnectorView
            ) { _, message ->
                Toast.makeText(context, message, Toast.LENGTH_LONG).show()
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Connectors") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Filled.ArrowBack, contentDescription = "Back to projects")
                    }
                },
                actions = {
                    IconButton(onClick = { showPdfOptions = true }) {
                        Icon(Icons.Filled.Save, contentDescription = "Save PDF")
                    }
                    IconButton(onClick = { showPdfOptions = true }) {
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
                        IconButton(onClick = { connectorPendingDeletion = cwp }) {
                            Icon(Icons.Filled.Delete, contentDescription = "Delete ${cwp.connector.label}")
                        }
                    }
                }
            }
        }
    }

    connectorPendingDeletion?.let { connector ->
        AlertDialog(
            onDismissRequest = { connectorPendingDeletion = null },
            title = { Text("Delete connector?") },
            text = { Text("Delete ${connector.connector.label} and all of its pins? This cannot be undone.") },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.deleteConnector(connector.connector.id)
                    connectorPendingDeletion = null
                }) { Text("Delete") }
            },
            dismissButton = {
                TextButton(onClick = { connectorPendingDeletion = null }) { Text("Cancel") }
            }
        )
    }

    if (showPdfOptions) {
        AlertDialog(
            onDismissRequest = { showPdfOptions = false },
            title = { Text("PDF wire layout") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                        RadioButton(
                            selected = selectedPdfLayout == PdfWireLayout.INDIVIDUAL,
                            onClick = { selectedPdfLayout = PdfWireLayout.INDIVIDUAL }
                        )
                        Text("Individual wires")
                    }
                    Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                        RadioButton(
                            selected = selectedPdfLayout == PdfWireLayout.TRUNKED,
                            onClick = { selectedPdfLayout = PdfWireLayout.TRUNKED }
                        )
                        Text("Trunked cable bundle")
                    }
                    Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                        RadioButton(
                            selected = selectedPdfLayout == PdfWireLayout.SHEATHED,
                            onClick = { selectedPdfLayout = PdfWireLayout.SHEATHED }
                        )
                        Text("Single sheathed harness")
                    }
                    Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                        RadioButton(
                            selected = selectedConnectorView == PdfConnectorView.STANDARD,
                            onClick = { selectedConnectorView = PdfConnectorView.STANDARD }
                        )
                        Text("Standard connector blocks")
                    }
                    Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                        RadioButton(
                            selected = selectedConnectorView == PdfConnectorView.PLUG,
                            onClick = { selectedConnectorView = PdfConnectorView.PLUG }
                        )
                        Text("Plug view with pin callouts")
                    }
                    Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                        Checkbox(
                            checked = includeRoutingTable,
                            onCheckedChange = { includeRoutingTable = it }
                        )
                        Text("Include routing table at bottom")
                    }
                }
            },
            confirmButton = {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TextButton(onClick = {
                        showPdfOptions = false
                        viewModel.exportForShare(
                            context = context,
                            wireLayout = selectedPdfLayout,
                            includeRoutingTable = includeRoutingTable,
                            connectorView = selectedConnectorView,
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
                    }) { Text("Share") }
                    TextButton(onClick = {
                        pendingSaveLayout = selectedPdfLayout
                        pendingSaveRoutingTable = includeRoutingTable
                        pendingSaveConnectorView = selectedConnectorView
                        showPdfOptions = false
                        savePickerLauncher.launch(suggestedPdfFileName(projectName))
                    }) { Text("Save") }
                }
            },
            dismissButton = {
                TextButton(onClick = { showPdfOptions = false }) { Text("Cancel") }
            }
        )
    }
}

