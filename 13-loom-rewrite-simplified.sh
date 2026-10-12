#!/bin/bash
# WiringPro: full rewrite of the loom canvas screen. Two prior fix
# attempts on the custom Canvas-based implementation had zero effect on
# the flicker/vanish bug, which means the custom rendering/hit-testing
# approach itself was the problem, not a small bug within it.
#
# This replaces it with: connectors stacked in a LazyColumn, each one
# rendered by the SAME PinGrid composable already proven to work in the
# single-connector editor, wrapped in a standard pinch-zoom/pan Box (a
# well-established Compose pattern). No custom Canvas drawing, no
# TextMeasurer, no hand-rolled touch-to-world-coordinate hit-testing.
#
# Known tradeoff: connectors stack vertically instead of flowing into a
# 2D grid, and the tapped/pending pin has no visual highlight yet (PinGrid
# doesn't currently support that) — both fixable once this is confirmed
# actually stable.
#
# Run from inside the 'wiringpro' folder (the one containing android-app/).
set -e

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

echo ""
echo "Done. No Gradle changes — just rebuild/Run."
