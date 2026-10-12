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

private const val CELL_W = 78f
private const val CELL_H = 52f
private const val CELL_GAP = 14f
private const val PAD = 18f
private const val HEADER_H = 30f
private const val CONNECTOR_SPACING = 64f
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

