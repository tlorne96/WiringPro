#!/bin/bash
# WiringPro: fixes the loom-canvas flicker/disappear issue. The captured
# logcat showed no crash at all — the process ends cleanly — so the most
# likely cause is a stray/residual touch (from the tap that opened the
# screen) being picked up as a large pan/zoom gesture, sending the whole
# diagram out of view. Two changes:
# 1) panOffset is now clamped to a bounded range, so a single bad gesture
#    can't send content arbitrarily far off-screen.
# 2) A 'Reset view' button (top-right) sets scale/pan back to defaults —
#    a guaranteed way back regardless of what actually caused it, so this
#    is never a dead end again even if the root cause turns out to be
#    something else entirely.
# Run from inside the 'wiringpro' folder (the one containing android-app/).
set -e

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/loom/LoomCanvasScreen.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/loom/LoomCanvasScreen.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.ui.screens.loom

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CenterFocusStrong
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Loom") },
                actions = {
                    IconButton(onClick = {
                        scale = 1f
                        panOffset = Offset.Zero
                    }) {
                        Icon(Icons.Filled.CenterFocusStrong, contentDescription = "Reset view")
                    }
                }
            )
        }
    ) { padding ->
        Canvas(
            modifier = Modifier
                .fillMaxSize()
                .pointerInput(Unit) {
                    detectTransformGestures { _, pan, zoom, _ ->
                        scale = (scale * zoom).coerceIn(0.3f, 3f)
                        // Clamped so a stray/mis-detected gesture (e.g. residual
                        // touch from the tap that opened this screen) can't fling
                        // the whole diagram out past where "Reset view" can reach.
                        val newOffset = panOffset + pan
                        panOffset = Offset(
                            newOffset.x.coerceIn(-4000f, 4000f),
                            newOffset.y.coerceIn(-4000f, 4000f)
                        )
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

echo ""
echo "Done. No Gradle changes — just rebuild/Run."
