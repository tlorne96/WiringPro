#!/bin/bash
# WiringPro: two fixes.
# 1) PDF export was reading net data from a StateFlow that nothing in
#    that screen actually subscribed to, so it silently stayed empty —
#    exported PDFs would show connectors/pins but no wires or net labels.
#    Now fetches fresh from the DB at export time instead.
# 2) PinGrid (the single-connector editor) now scrolls horizontally, so
#    a connector with a wide row (many pins on one line) doesn't run off
#    the edge of the screen with no way to reach the rest.
# Run from inside the 'wiringpro' folder (the one containing android-app/).
set -e

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/connectorlist/ConnectorListScreen.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/connectorlist/ConnectorListScreen.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.ui.screens.connectorlist

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AccountTree
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
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.io.File

class ConnectorListViewModel(
    private val repository: WiringRepository,
    private val projectId: String
) : ViewModel() {
    val connectors = repository.observeConnectorsWithPins(projectId)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val nets = repository.observeNets(projectId)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    fun exportPdf(context: Context, onReady: (File) -> Unit) {
        viewModelScope.launch {
            val project = repository.getProject(projectId) ?: return@launch
            // Fetch fresh from the DB rather than trusting the cached StateFlow
            // values — nets in particular was never guaranteed to be "warm"
            // (nothing in this screen was collecting it), so .value could
            // silently stay at its empty initial state forever.
            val currentConnectors = repository.observeConnectorsWithPins(projectId).first()
            val currentNets = repository.observeNets(projectId).first()
            val file = DiagramPdfGenerator.generate(context, project, currentConnectors, currentNets)
            onReady(file)
        }
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

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Connectors") },
                actions = {
                    IconButton(onClick = {
                        viewModel.exportPdf(context) { file ->
                            val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
                            val intent = Intent(Intent.ACTION_SEND).apply {
                                type = "application/pdf"
                                putExtra(Intent.EXTRA_STREAM, uri)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            context.startActivity(Intent.createChooser(intent, "Share wiring diagram"))
                        }
                    }) {
                        Icon(Icons.Filled.Share, contentDescription = "Export PDF")
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
                items(connectors) { cwp: ConnectorWithPins ->
                    val assignedCount = cwp.pins.count { it.netId != null }
                    Text(
                        text = "${cwp.connector.label} — ${cwp.pins.size} pins, $assignedCount assigned",
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onOpenConnector(cwp.connector.id) }
                            .padding(16.dp)
                    )
                }
            }
        }
    }
}

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/connectorlist/ConnectorListScreen.kt"

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/ui/components/PinGrid.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/ui/components/PinGrid.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.timlorne.wiringpro.data.db.ConnectorEntity
import com.timlorne.wiringpro.data.db.NetEntity
import com.timlorne.wiringpro.data.db.PinEntity

/**
 * Renders a connector as rows of tappable pin cells, honoring irregular
 * per-row pin counts (connector.rows). One cell per pin, laid out in the
 * same left-to-right/top-to-bottom order the pins were numbered in.
 * Horizontally scrollable: a wide row (a high pin-count connector on one
 * line) can run past the screen edge, so the whole grid slides sideways
 * rather than clipping content you can't reach otherwise.
 */
@Composable
fun PinGrid(
    connector: ConnectorEntity,
    pins: List<PinEntity>,
    nets: List<NetEntity>,
    onPinClick: (PinEntity) -> Unit,
    modifier: Modifier = Modifier
) {
    val netsById = nets.associateBy { it.id }
    val pinsByRow = pins.groupBy { it.row }
    val scrollState = rememberScrollState()

    Column(
        modifier = modifier.horizontalScroll(scrollState),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        for (rowIndex in connector.rows.indices) {
            val rowPins = (pinsByRow[rowIndex] ?: emptyList()).sortedBy { it.col }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (pin in rowPins) {
                    val net = pin.netId?.let { netsById[it] }
                    PinCell(pin = pin, net = net, onClick = { onPinClick(pin) })
                }
            }
        }
    }
}

@Composable
private fun PinCell(pin: PinEntity, net: NetEntity?, onClick: () -> Unit) {
    val assignedColor = net?.color?.let { runCatching { Color(android.graphics.Color.parseColor(it)) }.getOrNull() }
    val borderColor = assignedColor ?: MaterialTheme.colorScheme.outline

    Box(
        modifier = Modifier
            .size(width = 72.dp, height = 52.dp)
            .border(width = if (net != null) 2.dp else 1.dp, color = borderColor, shape = RoundedCornerShape(6.dp))
            .background(MaterialTheme.colorScheme.surface, RoundedCornerShape(6.dp))
            .clickable(onClick = onClick)
            .padding(4.dp),
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = pin.index.toString(),
                style = MaterialTheme.typography.labelLarge,
                textAlign = TextAlign.Center
            )
            Text(
                text = net?.name ?: "—",
                style = MaterialTheme.typography.labelSmall,
                textAlign = TextAlign.Center,
                color = if (net != null) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.outline
            )
        }
    }
}

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/ui/components/PinGrid.kt"

echo ""
echo "Done. No Gradle changes — just rebuild/Run."
