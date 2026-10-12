#!/bin/bash
# WiringPro: two fixes, both visually verified before shipping (rendered
# test PDFs with a busier multi-connector layout to confirm).
#
# 1) PDF wire routing switched from raw diagonal point-to-point lines to
#    orthogonal 'trunk' routing (vertical-horizontal-vertical, like real
#    schematics). Includes a minimum vertical drop so wires route below
#    the pins instead of cutting through them when connectors sit
#    side-by-side (same row), and staggers each net's trunk height so
#    different nets don't overlap each other.
# 2) The 'Headlight' standard net type used white (#FFFFFF) as its
#    default color, invisible against the light page/pin background.
#    Changed to a visible gray (#A9A9A9).
#
# Note: the color fix only affects NEWLY created 'Headlight' nets — any
# Headlight net you already made keeps the white it was created with,
# since color is stored per-net at creation time. There's no 'recolor an
# existing net' UI yet to fix that retroactively.
#
# Run from inside the 'wiringpro' folder (the one containing android-app/).
set -e

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/pdf/DiagramPdfGenerator.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/pdf/DiagramPdfGenerator.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.pdf

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.pdf.PdfDocument
import com.timlorne.wiringpro.data.db.ConnectorWithPins
import com.timlorne.wiringpro.data.db.NetEntity
import com.timlorne.wiringpro.data.db.ProjectEntity
import com.timlorne.wiringpro.ui.screens.loom.computeLoomLayout
import java.io.File
import java.io.FileOutputStream

private const val MARGIN = 30f
private const val TITLE_HEIGHT = 60f
private const val LEGEND_ROW_HEIGHT = 22f
private const val LEGEND_SWATCH_W = 28f
private const val LEGEND_ENTRY_GAP = 24f

private fun parseColorOrDefault(hex: String?, default: Int): Int =
    hex?.let { runCatching { Color.parseColor(it) }.getOrNull() } ?: default

/** Groups nets into legend rows that fit within contentWidth, for both sizing and drawing. */
private fun layoutLegendRows(nets: List<NetEntity>, contentWidth: Float, textPaint: Paint): List<List<NetEntity>> {
    val rows = mutableListOf<MutableList<NetEntity>>()
    var currentRow = mutableListOf<NetEntity>()
    var cursorX = 0f
    for (net in nets) {
        val entryWidth = LEGEND_SWATCH_W + 6f + textPaint.measureText(net.name) + LEGEND_ENTRY_GAP
        if (cursorX + entryWidth > contentWidth && currentRow.isNotEmpty()) {
            rows.add(currentRow)
            currentRow = mutableListOf()
            cursorX = 0f
        }
        currentRow.add(net)
        cursorX += entryWidth
    }
    if (currentRow.isNotEmpty()) rows.add(currentRow)
    return rows
}

/**
 * Renders every connector in the project onto one PDF page (reusing the
 * same flow-layout the loom canvas uses, so "all connectors together"
 * looks the same everywhere in the app), draws the actual wire between
 * every pair of connected pins — including fan-out, drawn as a shared
 * trunk line the way the original PDF-layout prototype did — and adds a
 * color legend. Known simplification carried over from that prototype:
 * wires are straight lines, not routed around other connectors, so a busy
 * loom will show real crossings rather than tidy right-angle paths.
 */
object DiagramPdfGenerator {

    fun generate(
        context: Context,
        project: ProjectEntity,
        connectors: List<ConnectorWithPins>,
        nets: List<NetEntity>
    ): File {
        val layouts = computeLoomLayout(connectors)

        val maxX = layouts.maxOfOrNull { it.position.x + it.size.width } ?: 400f
        val maxY = layouts.maxOfOrNull { it.position.y + it.size.height } ?: 300f
        val contentWidth = maxX + 2 * MARGIN

        val legendTextPaint = Paint().apply { textSize = 11f }
        val legendRows = layoutLegendRows(nets, contentWidth - 2 * MARGIN, legendTextPaint)
        val legendHeight = if (legendRows.isEmpty()) 0f else legendRows.size * LEGEND_ROW_HEIGHT + 20f

        val pageWidth = contentWidth.toInt().coerceAtLeast(400)
        val pageHeight = (TITLE_HEIGHT + maxY + legendHeight + 2 * MARGIN).toInt().coerceAtLeast(300)

        val document = PdfDocument()
        val pageInfo = PdfDocument.PageInfo.Builder(pageWidth, pageHeight, 1).create()
        val page = document.startPage(pageInfo)
        val canvas = page.canvas

        drawTitle(canvas, project)
        val contentTop = TITLE_HEIGHT

        // Pin id -> absolute page-space center, built once and reused for every net's wires.
        val pinCenters = HashMap<String, android.graphics.PointF>()
        for (layout in layouts) {
            val originX = MARGIN
            val originY = contentTop
            for ((pinId, rect) in layout.pinRects) {
                pinCenters[pinId] = android.graphics.PointF(rect.center.x + originX, rect.center.y + originY)
            }
        }
        val pinsById = connectors.flatMap { it.pins }.associateBy { it.id }
        val netsById = nets.associateBy { it.id }

        // Wires drawn first so connector boxes render on top of them.
        for ((netIndex, net) in nets.withIndex()) {
            val pointsByPin = pinsById.values
                .filter { it.netId == net.id }
                .mapNotNull { pin -> pinCenters[pin.id]?.let { pin.id to it } }
            if (pointsByPin.size < 2) continue

            val color = parseColorOrDefault(net.color, Color.DKGRAY)
            val wirePaint = Paint().apply { this.color = color; strokeWidth = 2.2f; style = Paint.Style.STROKE }

            // Orthogonal trunk routing rather than raw diagonal point-to-point
            // lines: the topmost pin is the source, a shared horizontal trunk
            // connects down to every other pin on the net. A minimum vertical
            // drop is enforced below — without it, pins on the same row (the
            // common case for side-by-side connectors) collapse the trunk to
            // zero height and the wire cuts straight through the pin boxes
            // instead of routing below them.
            val (_, source) = pointsByPin.minByOrNull { it.second.y }!!
            val targets = pointsByPin.filter { it.second !== source }.map { it.second }
            val minDrop = 24f + (netIndex % 5) * 14f
            val naturalTrunkY = source.y + (targets.minOf { it.y } - source.y) / 2f
            val trunkY = if (naturalTrunkY - source.y < minDrop) source.y + minDrop else naturalTrunkY
            val trunkXs = targets.map { it.x } + source.x

            canvas.drawLine(source.x, source.y, source.x, trunkY, wirePaint)
            canvas.drawLine(trunkXs.min(), trunkY, trunkXs.max(), trunkY, wirePaint)
            for (target in targets) {
                canvas.drawLine(target.x, trunkY, target.x, target.y, wirePaint)
            }
            if (targets.size > 1) {
                val dotPaint = Paint().apply { this.color = color; style = Paint.Style.FILL }
                canvas.drawCircle(source.x, trunkY, 3f, dotPaint)
            }
        }

        for (layout in layouts) {
            val originX = MARGIN
            val originY = contentTop
            val left = layout.position.x + originX
            val top = layout.position.y + originY

            val boxPaint = Paint().apply { color = Color.rgb(153, 153, 153); style = Paint.Style.STROKE; strokeWidth = 1.5f }
            canvas.drawRoundRect(RectF(left, top, left + layout.size.width, top + layout.size.height), 10f, 10f, boxPaint)

            val labelPaint = Paint().apply { color = Color.BLACK; textSize = 13f; isFakeBoldText = true }
            canvas.drawText(layout.label, left + 8f, top + 18f, labelPaint)

            val connector = connectors.first { it.connector.id == layout.connectorId }
            for (pin in connector.pins) {
                val rect = layout.pinRects[pin.id] ?: continue
                val pLeft = rect.left + originX
                val pTop = rect.top + originY
                val pRight = rect.right + originX
                val pBottom = rect.bottom + originY
                val net: NetEntity? = pin.netId?.let { netsById[it] }

                val fillPaint = Paint().apply { color = Color.rgb(250, 250, 248); style = Paint.Style.FILL }
                canvas.drawRoundRect(RectF(pLeft, pTop, pRight, pBottom), 4f, 4f, fillPaint)

                val borderColor = net?.let { parseColorOrDefault(it.color, Color.rgb(119, 119, 119)) } ?: Color.rgb(187, 187, 187)
                val borderPaint = Paint().apply { color = borderColor; style = Paint.Style.STROKE; strokeWidth = 1.5f }
                canvas.drawRoundRect(RectF(pLeft, pTop, pRight, pBottom), 4f, 4f, borderPaint)

                val indexPaint = Paint().apply { color = Color.BLACK; textSize = 11f; isFakeBoldText = true }
                canvas.drawText(pin.index.toString(), pLeft + 5f, pTop + 14f, indexPaint)

                if (net != null) {
                    val netPaint = Paint().apply { color = Color.DKGRAY; textSize = 8f }
                    canvas.drawText(net.name, pLeft + 5f, pBottom - 5f, netPaint)
                }
            }
        }

        if (legendRows.isNotEmpty()) {
            drawLegend(canvas, legendRows, contentTop + maxY + 30f)
        }

        document.finishPage(page)

        val safeName = project.name.replace(Regex("[^A-Za-z0-9-_]"), "_").ifBlank { "project" }
        val file = File(context.cacheDir, "wiringpro-$safeName.pdf")
        FileOutputStream(file).use { document.writeTo(it) }
        document.close()
        return file
    }

    private fun drawTitle(canvas: Canvas, project: ProjectEntity) {
        val titlePaint = Paint().apply { color = Color.BLACK; textSize = 20f; isFakeBoldText = true }
        canvas.drawText(project.name, MARGIN, 28f, titlePaint)
        project.vehicle?.let {
            val subPaint = Paint().apply { color = Color.DKGRAY; textSize = 12f }
            canvas.drawText(it, MARGIN, 46f, subPaint)
        }
    }

    private fun drawLegend(canvas: Canvas, rows: List<List<NetEntity>>, startY: Float) {
        var y = startY
        for (row in rows) {
            var x = MARGIN
            for (net in row) {
                val color = parseColorOrDefault(net.color, Color.DKGRAY)
                val swatchPaint = Paint().apply { this.color = color; strokeWidth = 3f }
                canvas.drawLine(x, y, x + LEGEND_SWATCH_W, y, swatchPaint)

                val textPaint = Paint().apply { this.color = Color.BLACK; textSize = 11f }
                canvas.drawText(net.name, x + LEGEND_SWATCH_W + 6f, y + 4f, textPaint)

                x += LEGEND_SWATCH_W + 6f + textPaint.measureText(net.name) + LEGEND_ENTRY_GAP
            }
            y += LEGEND_ROW_HEIGHT
        }
    }
}

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/pdf/DiagramPdfGenerator.kt"

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
    { "type": "CUSTOM",           "label": "Custom / user-defined",      "defaultColor": null }
  ]
}

JSON_EOF
echo "Wrote shared/net-types.json"

echo ""
echo "Done. No Gradle changes — just rebuild/Run."
