#!/bin/bash
# WiringPro: adds the whole-loom canvas — every connector on one
# pan/pinch-zoomable surface, tap a pin then tap another to connect them
# (net names shown on each pin let you trace connections; no wire lines
# drawn, by design, to keep this version simple).
#
# ALSO re-writes app/build.gradle.kts to restore the compileOptions/
# kotlinOptions JVM-17 block — a previous script (04) had reverted it
# because that fix had only ever been applied to your file directly, not
# to the script's own template. If you hit the 'Inconsistent JVM-target'
# error again after an earlier script run, this fixes it for good.
#
# Run from inside the 'wiringpro' folder (the one containing android-app/).
set -e

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/loom/LoomLayout.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/loom/LoomLayout.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.ui.screens.loom

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import com.timlorne.wiringpro.data.db.ConnectorWithPins

// Pure layout math, deliberately kept framework-light (no Compose state
// here) so it's easy to reason about and reuse — this mirrors the same
// pin-grid math the PDF prototype uses, just flowing left-to-right with
// wrap instead of stacking, since the canvas pans/zooms rather than
// paginating.

private const val CELL_W = 70f
private const val CELL_H = 44f
private const val CELL_GAP = 10f
private const val PAD = 14f
private const val HEADER_H = 26f
private const val CONNECTOR_SPACING = 48f
private const val MAX_ROW_WIDTH = 1800f

data class ConnectorLayout(
    val connectorId: String,
    val label: String,
    val position: Offset,
    val size: Size,
    val pinRects: Map<String, Rect> // pinId -> absolute world-space rect
)

private fun connectorSize(rows: List<Int>): Size {
    val maxRowPins = rows.maxOrNull() ?: 1
    val width = maxRowPins * CELL_W + (maxRowPins - 1) * CELL_GAP + 2 * PAD
    val height = HEADER_H + rows.size * CELL_H + (rows.size - 1) * CELL_GAP + 2 * PAD
    return Size(width, height)
}

/**
 * Lays out every connector in the project on one shared canvas, wrapping to
 * a new row once MAX_ROW_WIDTH is exceeded. No manual repositioning yet —
 * order follows whatever the DB query returns connectors in.
 */
fun computeLoomLayout(connectors: List<ConnectorWithPins>): List<ConnectorLayout> {
    var cursorX = PAD
    var cursorY = PAD
    var rowMaxHeight = 0f
    val layouts = mutableListOf<ConnectorLayout>()

    for (cwp in connectors) {
        val connector = cwp.connector
        val size = connectorSize(connector.rows)

        if (cursorX + size.width > MAX_ROW_WIDTH && cursorX > PAD) {
            cursorX = PAD
            cursorY += rowMaxHeight + CONNECTOR_SPACING
            rowMaxHeight = 0f
        }

        val position = Offset(cursorX, cursorY)
        val pinRects = mutableMapOf<String, Rect>()
        for (pin in cwp.pins) {
            val rowPinCount = connector.rows.getOrElse(pin.row) { 1 }
            val rowWidth = rowPinCount * CELL_W + (rowPinCount - 1) * CELL_GAP
            val rowX0 = position.x + (size.width - rowWidth) / 2f
            val pinX = rowX0 + pin.col * (CELL_W + CELL_GAP)
            val pinY = position.y + HEADER_H + PAD + pin.row * (CELL_H + CELL_GAP)
            pinRects[pin.id] = Rect(Offset(pinX, pinY), Size(CELL_W, CELL_H))
        }

        layouts.add(ConnectorLayout(connector.id, connector.label, position, size, pinRects))

        cursorX += size.width + CONNECTOR_SPACING
        rowMaxHeight = maxOf(rowMaxHeight, size.height)
    }

    return layouts
}

/** First pin whose rect contains the given world-space point, if any. */
fun findPinAt(layouts: List<ConnectorLayout>, point: Offset): String? {
    for (layout in layouts) {
        for ((pinId, rect) in layout.pinRects) {
            if (rect.contains(point)) return pinId
        }
    }
    return null
}

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/loom/LoomLayout.kt"

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/loom/LoomCanvasScreen.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/loom/LoomCanvasScreen.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.ui.screens.loom

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.timlorne.wiringpro.data.db.NetEntity
import com.timlorne.wiringpro.data.repository.WiringRepository
import com.timlorne.wiringpro.ui.components.NameNetDialog
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
     * the other joins it — that's the "tap it, tap the matching pin" fast
     * path. If neither has a net yet, onNeedsNaming fires so the UI can ask
     * what to call the new connection.
     *
     * Known simplification: if both pins already have DIFFERENT nets, this
     * just overwrites pin B onto pin A's net rather than asking whether you
     * meant to merge two named nets — revisit if that turns out to matter.
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

private fun parseColorOrDefault(hex: String?, default: Color): Color =
    hex?.let { runCatching { Color(android.graphics.Color.parseColor(it)) }.getOrNull() } ?: default

/**
 * Whole-loom view: every connector in the project on one pannable,
 * pinch-zoomable canvas. Tap a pin, tap a second pin, they're connected —
 * no wire lines are drawn (deliberately, for now): matching net-name labels
 * on the pins themselves is how you trace a connection here, the same way
 * some real wiring diagrams favor net labels over routed lines when a
 * harness gets busy.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LoomCanvasScreen(viewModel: LoomCanvasViewModel) {
    val connectorsWithPins by viewModel.connectors.collectAsState()
    val nets by viewModel.nets.collectAsState()

    var scale by remember { mutableStateOf(1f) }
    var panOffset by remember { mutableStateOf(Offset.Zero) }
    var pendingPinId by remember { mutableStateOf<String?>(null) }
    var pendingNamingPins by remember { mutableStateOf<Pair<String, String>?>(null) }

    val layouts = remember(connectorsWithPins) { computeLoomLayout(connectorsWithPins) }
    val pinsById = remember(connectorsWithPins) { connectorsWithPins.flatMap { it.pins }.associateBy { it.id } }
    val netsById = remember(nets) { nets.associateBy { it.id } }

    // Long-lived gesture coroutines (pointerInput(Unit) never restarts) need
    // these to stay fresh without tearing down the gesture detector itself.
    val latestLayouts by rememberUpdatedState(layouts)
    val latestPinsById by rememberUpdatedState(pinsById)

    val textMeasurer = rememberTextMeasurer()

    fun toScreen(world: Offset) = Offset(world.x * scale + panOffset.x, world.y * scale + panOffset.y)
    fun toWorld(screen: Offset) = Offset((screen.x - panOffset.x) / scale, (screen.y - panOffset.y) / scale)

    Scaffold(topBar = { TopAppBar(title = { Text("Loom") }) }) { padding ->
        Canvas(
            modifier = Modifier
                .fillMaxSize()
                .pointerInput(Unit) {
                    detectTransformGestures { _, pan, zoom, _ ->
                        scale = (scale * zoom).coerceIn(0.3f, 3f)
                        panOffset += pan
                    }
                }
                .pointerInput(Unit) {
                    detectTapGestures { screenPos ->
                        val world = toWorld(screenPos)
                        val hitPinId = findPinAt(latestLayouts, world)
                        if (hitPinId == null) {
                            pendingPinId = null
                            return@detectTapGestures
                        }
                        val currentPending = pendingPinId
                        when {
                            currentPending == null -> pendingPinId = hitPinId
                            currentPending == hitPinId -> pendingPinId = null
                            else -> {
                                val a = currentPending
                                val b = hitPinId
                                pendingPinId = null
                                viewModel.connectPins(a, b) { pinAId, pinBId ->
                                    pendingNamingPins = pinAId to pinBId
                                }
                            }
                        }
                    }
                }
        ) {
            for (layout in layouts) {
                val topLeft = toScreen(layout.position)
                val w = layout.size.width * scale
                val h = layout.size.height * scale

                drawRoundRect(
                    color = Color(0xFF999999),
                    topLeft = topLeft,
                    size = androidx.compose.ui.geometry.Size(w, h),
                    cornerRadius = CornerRadius(10f * scale),
                    style = Stroke(width = 1.5f)
                )
                drawText(
                    textMeasurer = textMeasurer,
                    text = layout.label,
                    topLeft = topLeft + Offset(8f * scale, 4f * scale),
                    style = TextStyle(fontSize = (13f * scale).coerceAtLeast(6f).sp, fontWeight = FontWeight.Medium)
                )

                val connectorPins = pinsById.values.filter { layout.pinRects.containsKey(it.id) }
                for (pin in connectorPins) {
                    val rect = layout.pinRects[pin.id] ?: continue
                    val screenTopLeft = toScreen(rect.topLeft)
                    val screenSize = androidx.compose.ui.geometry.Size(rect.width * scale, rect.height * scale)
                    val net: NetEntity? = pin.netId?.let { netsById[it] }
                    val isSelected = pin.id == pendingPinId

                    val borderColor = when {
                        isSelected -> Color(0xFF2196F3)
                        net != null -> parseColorOrDefault(net.color, Color(0xFF777777))
                        else -> Color(0xFFBBBBBB)
                    }

                    drawRoundRect(
                        color = Color(0xFFFAFAF8),
                        topLeft = screenTopLeft,
                        size = screenSize,
                        cornerRadius = CornerRadius(4f * scale)
                    )
                    drawRoundRect(
                        color = borderColor,
                        topLeft = screenTopLeft,
                        size = screenSize,
                        cornerRadius = CornerRadius(4f * scale),
                        style = Stroke(width = if (isSelected) 3f else 1.5f)
                    )

                    val indexFontSize = (12f * scale).coerceAtLeast(5f)
                    drawText(
                        textMeasurer = textMeasurer,
                        text = pin.index.toString(),
                        topLeft = screenTopLeft + Offset(6f * scale, 2f * scale),
                        style = TextStyle(fontSize = indexFontSize.sp, fontWeight = FontWeight.Bold)
                    )
                    if (net != null) {
                        val netFontSize = (9f * scale).coerceAtLeast(4f)
                        drawText(
                            textMeasurer = textMeasurer,
                            text = net.name,
                            topLeft = screenTopLeft + Offset(6f * scale, screenSize.height - 14f * scale),
                            style = TextStyle(fontSize = netFontSize.sp)
                        )
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

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/ui/components/NameNetDialog.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/ui/components/NameNetDialog.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Divider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.timlorne.wiringpro.data.model.StandardNetTypes

/**
 * Shown when two pins with no existing net are tapped together on the loom
 * canvas — they need a name before they can be wired. Deliberately simpler
 * than NetPickerDialog: no "existing nets in project" browsing here, since
 * on the canvas you'd normally just tap the pin that already has the name
 * you want rather than typing it fresh.
 */
@Composable
fun NameNetDialog(
    onDismiss: () -> Unit,
    onConfirm: (name: String, netType: String, color: String?) -> Unit
) {
    var customName by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Name this connection") },
        text = {
            LazyColumn {
                item { Text("Standard signal types", style = MaterialTheme.typography.labelMedium) }
                items(StandardNetTypes.ALL.filter { it.type != "CUSTOM" }) { standard ->
                    Text(
                        text = standard.label,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 8.dp)
                            .clickable { onConfirm(standard.label, standard.type, standard.defaultColor) }
                    )
                }
                item { Divider(modifier = Modifier.padding(vertical = 8.dp)) }
                item {
                    Column {
                        Text("Custom", style = MaterialTheme.typography.labelMedium)
                        OutlinedTextField(
                            value = customName,
                            onValueChange = { customName = it },
                            placeholder = { Text("e.g. Fan relay trigger") },
                            modifier = Modifier.fillMaxWidth().padding(top = 4.dp)
                        )
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                enabled = customName.isNotBlank(),
                onClick = { onConfirm(customName.trim(), "CUSTOM", null) }
            ) { Text("Connect") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        }
    )
}

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/ui/components/NameNetDialog.kt"

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/connectorlist/ConnectorListScreen.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/connectorlist/ConnectorListScreen.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.ui.screens.connectorlist

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AccountTree
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
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.timlorne.wiringpro.data.db.ConnectorWithPins
import com.timlorne.wiringpro.data.repository.WiringRepository
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.stateIn

class ConnectorListViewModel(
    repository: WiringRepository,
    projectId: String
) : ViewModel() {
    val connectors = repository.observeConnectorsWithPins(projectId)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
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

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Connectors") },
                actions = {
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

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/ui/nav/WiringProNavHost.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/ui/nav/WiringProNavHost.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.ui.nav

import androidx.compose.runtime.Composable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.timlorne.wiringpro.data.repository.WiringRepository
import com.timlorne.wiringpro.ui.screens.connectorlist.ConnectorListScreen
import com.timlorne.wiringpro.ui.screens.connectorlist.ConnectorListViewModel
import com.timlorne.wiringpro.ui.screens.editor.PinGridEditorScreen
import com.timlorne.wiringpro.ui.screens.editor.PinGridEditorViewModel
import com.timlorne.wiringpro.ui.screens.loom.LoomCanvasScreen
import com.timlorne.wiringpro.ui.screens.loom.LoomCanvasViewModel
import com.timlorne.wiringpro.ui.screens.newconnector.NewConnectorScreen
import com.timlorne.wiringpro.ui.screens.newconnector.NewConnectorViewModel
import com.timlorne.wiringpro.ui.screens.projectlist.ProjectListScreen
import com.timlorne.wiringpro.ui.screens.projectlist.ProjectListViewModel

private class SimpleFactory(private val create: () -> ViewModel) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = create() as T
}

/**
 * Route shape: project_list -> connector_list/{projectId} -> one of
 * new_connector/{projectId}, editor/{projectId}/{connectorId}, or
 * loom/{projectId} (the whole-loom canvas — every connector on one
 * pan/zoomable surface).
 */
@Composable
fun WiringProNavHost(repository: WiringRepository) {
    val navController: NavHostController = rememberNavController()

    NavHost(navController = navController, startDestination = "project_list") {
        composable("project_list") {
            val vm: ProjectListViewModel = viewModel(
                factory = SimpleFactory { ProjectListViewModel(repository) }
            )
            ProjectListScreen(
                viewModel = vm,
                onOpenProject = { projectId -> navController.navigate("connector_list/$projectId") }
            )
        }

        composable(
            route = "connector_list/{projectId}",
            arguments = listOf(navArgument("projectId") { type = NavType.StringType })
        ) { backStackEntry ->
            val projectId = backStackEntry.arguments?.getString("projectId")!!
            val vm: ConnectorListViewModel = viewModel(
                factory = SimpleFactory { ConnectorListViewModel(repository, projectId) }
            )
            ConnectorListScreen(
                viewModel = vm,
                onAddConnector = { navController.navigate("new_connector/$projectId") },
                onOpenConnector = { connectorId -> navController.navigate("editor/$projectId/$connectorId") },
                onViewLoom = { navController.navigate("loom/$projectId") }
            )
        }

        composable(
            route = "new_connector/{projectId}",
            arguments = listOf(navArgument("projectId") { type = NavType.StringType })
        ) { backStackEntry ->
            val projectId = backStackEntry.arguments?.getString("projectId")!!
            val vm: NewConnectorViewModel = viewModel(
                factory = SimpleFactory { NewConnectorViewModel(repository, projectId) }
            )
            NewConnectorScreen(
                viewModel = vm,
                onConnectorCreated = { connectorId ->
                    navController.navigate("editor/$projectId/$connectorId") {
                        popUpTo("connector_list/$projectId")
                    }
                },
                onBack = { navController.popBackStack() }
            )
        }

        composable(
            route = "editor/{projectId}/{connectorId}",
            arguments = listOf(
                navArgument("projectId") { type = NavType.StringType },
                navArgument("connectorId") { type = NavType.StringType }
            )
        ) { backStackEntry ->
            val projectId = backStackEntry.arguments?.getString("projectId")!!
            val connectorId = backStackEntry.arguments?.getString("connectorId")!!
            val vm: PinGridEditorViewModel = viewModel(
                factory = SimpleFactory { PinGridEditorViewModel(repository, projectId, connectorId) }
            )
            PinGridEditorScreen(viewModel = vm)
        }

        composable(
            route = "loom/{projectId}",
            arguments = listOf(navArgument("projectId") { type = NavType.StringType })
        ) { backStackEntry ->
            val projectId = backStackEntry.arguments?.getString("projectId")!!
            val vm: LoomCanvasViewModel = viewModel(
                factory = SimpleFactory { LoomCanvasViewModel(repository, projectId) }
            )
            LoomCanvasScreen(viewModel = vm)
        }
    }
}

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/ui/nav/WiringProNavHost.kt"

mkdir -p "$(dirname "android-app/app/build.gradle.kts")"
cat > android-app/app/build.gradle.kts << 'KOTLIN_EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.devtools.ksp") // for Room annotation processing
}

android {
    namespace = "com.timlorne.wiringpro"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.timlorne.wiringpro"
        minSdk = 26        // covers the Tab Active Pro 5 comfortably
        targetSdk = 34
        versionCode = 1
        versionName = "0.1"
    }

    buildFeatures {
        compose = true
    }

    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.8" // matches Kotlin 1.9.22 in the root build.gradle.kts
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.compose.ui:ui:1.6.0")
    implementation("androidx.compose.material3:material3:1.2.0")
    implementation("androidx.compose.material:material-icons-extended:1.6.0")
    implementation("io.coil-kt:coil-compose:2.6.0")
    implementation("androidx.activity:activity-compose:1.8.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.7.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")
    implementation("androidx.navigation:navigation-compose:2.7.6")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation("androidx.room:room-runtime:2.6.1")
    implementation("androidx.room:room-ktx:2.6.1")
    ksp("androidx.room:room-compiler:2.6.1")
    implementation("com.squareup.retrofit2:retrofit:2.9.0")
    implementation("com.squareup.retrofit2:converter-gson:2.9.0")
    // PDF generation: android.graphics.pdf.PdfDocument (built-in) is enough to start;
    // revisit iText/PdfBox only if diagram complexity outgrows it.
}

KOTLIN_EOF
echo "Wrote android-app/app/build.gradle.kts"

echo ""
echo "Done. Sync Gradle (elephant icon) in Android Studio, then Run."
echo "New: tap the tree icon (top-right) on the Connectors screen to open the loom view."
