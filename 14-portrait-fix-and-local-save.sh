#!/bin/bash
# WiringPro: three changes.
# 1) Fixes the portrait-only Loom flicker: PinGrid's own horizontal
#    scroll (needed for wide rows, 8+ pins) was fighting the Loom
#    screen's pinch-zoom gesture handler when both were active on the
#    same touch stream. PinGrid's scroll is now optional and turned off
#    when embedded in the Loom view, since the outer zoom/pan already
#    covers seeing a wide row.
# 2) Adds a 'Save' button (next to Share) on the Connectors screen that
#    writes the PDF straight to the Downloads folder — no share sheet.
# No changes needed for PDF wires — those were already fixed earlier;
# re-export and confirm.
# Run from inside the 'wiringpro' folder (the one containing android-app/).
set -e

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
 *
 * horizontalScrollEnabled controls whether a wide row (more pins than fit
 * on screen) gets its own horizontal scroll. Leave this on for standalone
 * use (the single-connector editor). Turn it OFF when this is embedded
 * inside something that already handles panning itself (e.g. the Loom
 * canvas's pinch-zoom wrapper) — two independent gesture handlers on the
 * same touch stream fight each other, which is what broke the Loom view
 * in portrait when a row needed to scroll.
 */
@Composable
fun PinGrid(
    connector: ConnectorEntity,
    pins: List<PinEntity>,
    nets: List<NetEntity>,
    onPinClick: (PinEntity) -> Unit,
    modifier: Modifier = Modifier,
    horizontalScrollEnabled: Boolean = true
) {
    val netsById = nets.associateBy { it.id }
    val pinsByRow = pins.groupBy { it.row }
    val scrollState = rememberScrollState()

    Column(
        modifier = if (horizontalScrollEnabled) modifier.horizontalScroll(scrollState) else modifier,
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

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/loom/LoomCanvasScreen.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/loom/LoomCanvasScreen.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.ui.screens.loom

import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CenterFocusStrong
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.timlorne.wiringpro.data.repository.WiringRepository
import com.timlorne.wiringpro.ui.components.NameNetDialog
import com.timlorne.wiringpro.ui.components.PinGrid
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class LoomCanvasViewModel(
    private val repository: WiringRepository,
    private val projectId: String
) : ViewModel() {

    val connectors = repository.observeConnectorsWithPins(projectId)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val nets = repository.observeNets(projectId)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    /**
     * Two pins were tapped in sequence. If either already belongs to a net,
     * the other joins it. If neither has one yet, onNeedsNaming fires so the
     * UI can ask what to call the new connection.
     *
     * Known simplification: if both pins already have DIFFERENT nets, this
     * just overwrites pin B onto pin A's net rather than asking whether you
     * meant to merge two named nets.
     */
    fun connectPins(pinAId: String, pinBId: String, onNeedsNaming: (String, String) -> Unit) {
        val pins = connectors.value.flatMap { it.pins }.associateBy { it.id }
        val pinA = pins[pinAId] ?: return
        val pinB = pins[pinBId] ?: return
        viewModelScope.launch {
            when {
                pinA.netId != null -> repository.assignPinToNet(pinB.id, pinA.netId)
                pinB.netId != null -> repository.assignPinToNet(pinA.id, pinB.netId)
                else -> onNeedsNaming(pinA.id, pinB.id)
            }
        }
    }

    fun createNetAndConnect(name: String, netType: String, color: String?, pinAId: String, pinBId: String) {
        viewModelScope.launch {
            val netId = repository.getOrCreateNet(projectId, name, netType, color)
            repository.assignPinToNet(pinAId, netId)
            repository.assignPinToNet(pinBId, netId)
        }
    }
}

/**
 * Whole-loom view: every connector in the project, stacked in a scrollable
 * list, wrapped in a standard pinch-zoom/pan box. Deliberately reuses the
 * same PinGrid composable the single-connector editor already uses — a
 * from-scratch Canvas + custom hit-testing version of this screen caused an
 * unreproducible flicker/vanish with no logged crash, so this trades a true
 * 2D grid layout for something built entirely out of already-proven pieces.
 * Tap a pin, tap a second pin to connect them; net names on each pin are how
 * you trace a connection (no wire lines drawn).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LoomCanvasScreen(viewModel: LoomCanvasViewModel) {
    val connectorsWithPins by viewModel.connectors.collectAsState()
    val nets by viewModel.nets.collectAsState()

    var scale by remember { mutableStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    var pendingPinId by remember { mutableStateOf<String?>(null) }
    var pendingNamingPins by remember { mutableStateOf<Pair<String, String>?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Loom") },
                actions = {
                    IconButton(onClick = {
                        scale = 1f
                        offset = Offset.Zero
                    }) {
                        Icon(Icons.Filled.CenterFocusStrong, contentDescription = "Reset view")
                    }
                }
            )
        }
    ) { padding ->
        if (connectorsWithPins.isEmpty()) {
            Text(
                "No connectors yet.",
                modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp)
            )
        } else {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .pointerInput(Unit) {
                        detectTransformGestures { _, pan, zoom, _ ->
                            scale = (scale * zoom).coerceIn(0.5f, 2.5f)
                            offset += pan
                        }
                    }
            ) {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .graphicsLayer(
                            scaleX = scale,
                            scaleY = scale,
                            translationX = offset.x,
                            translationY = offset.y,
                            transformOrigin = TransformOrigin(0f, 0f)
                        ),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(24.dp)
                ) {
                    items(connectorsWithPins, key = { it.connector.id }) { cwp ->
                        Column {
                            Text(cwp.connector.label, style = MaterialTheme.typography.titleMedium)
                            Spacer(Modifier.height(8.dp))
                            PinGrid(
                                connector = cwp.connector,
                                pins = cwp.pins,
                                nets = nets,
                                horizontalScrollEnabled = false,
                                onPinClick = { pin ->
                                    val current = pendingPinId
                                    when {
                                        current == null -> pendingPinId = pin.id
                                        current == pin.id -> pendingPinId = null
                                        else -> {
                                            val a = current
                                            val b = pin.id
                                            pendingPinId = null
                                            viewModel.connectPins(a, b) { pinAId, pinBId ->
                                                pendingNamingPins = pinAId to pinBId
                                            }
                                        }
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    pendingNamingPins?.let { (pinAId, pinBId) ->
        NameNetDialog(
            onDismiss = { pendingNamingPins = null },
            onConfirm = { name, netType, color ->
                viewModel.createNetAndConnect(name, netType, color, pinAId, pinBId)
                pendingNamingPins = null
            }
        )
    }
}

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/loom/LoomCanvasScreen.kt"

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/pdf/PdfSaver.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/pdf/PdfSaver.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.pdf

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

/**
 * Saves a generated PDF straight to the device's Downloads folder — no
 * share sheet, no picking an app to hand it off to. On Android 10+ this
 * goes through MediaStore so it lands in the real public Downloads folder
 * other apps (a file manager, etc) can see. Below that, scoped storage
 * doesn't apply yet but requesting WRITE_EXTERNAL_STORAGE just for this
 * felt like overkill, so older devices get the app's own external Downloads
 * folder instead — still on-device, just one level less discoverable.
 */
object PdfSaver {

    fun saveToDownloads(context: Context, sourceFile: File, displayName: String): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, displayName)
                    put(MediaStore.Downloads.MIME_TYPE, "application/pdf")
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
                val resolver = context.contentResolver
                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return false
                resolver.openOutputStream(uri)?.use { out ->
                    sourceFile.inputStream().use { input -> input.copyTo(out) }
                } ?: return false
                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                true
            } else {
                val dir = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: return false
                dir.mkdirs()
                sourceFile.copyTo(File(dir, displayName), overwrite = true)
                true
            }
        } catch (e: Exception) {
            false
        }
    }
}

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/pdf/PdfSaver.kt"

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/connectorlist/ConnectorListScreen.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/connectorlist/ConnectorListScreen.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.ui.screens.connectorlist

import android.content.Context
import android.content.Intent
import android.widget.Toast
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AccountTree
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
                            val ok = PdfSaver.saveToDownloads(context, file, file.name)
                            Toast.makeText(
                                context,
                                if (ok) "Saved to Downloads: ${file.name}" else "Save failed",
                                Toast.LENGTH_SHORT
                            ).show()
                        }
                    }) {
                        Icon(Icons.Filled.Save, contentDescription = "Save PDF to Downloads")
                    }
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

echo ""
echo "Done. No Gradle changes — just rebuild/Run."
