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

