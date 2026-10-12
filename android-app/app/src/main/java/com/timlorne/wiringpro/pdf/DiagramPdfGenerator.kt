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
private const val WIRE_STAGGER_BASE = 32f
private const val WIRE_STAGGER_STEP = 20f
private const val WIRE_STAGGER_CYCLE = 8
// Deepest any wire trunk can extend below its source pin — reserved as
// clearance between the connector block and the legend so busy looms with
// many nets don't get their wires clipped or crowded against the legend.
private const val WIRE_CLEARANCE = WIRE_STAGGER_BASE + (WIRE_STAGGER_CYCLE - 1) * WIRE_STAGGER_STEP

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
        val pageHeight = (TITLE_HEIGHT + maxY + WIRE_CLEARANCE + legendHeight + 2 * MARGIN).toInt().coerceAtLeast(300)

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
            val minDrop = WIRE_STAGGER_BASE + (netIndex % WIRE_STAGGER_CYCLE) * WIRE_STAGGER_STEP
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
            drawLegend(canvas, legendRows, contentTop + maxY + WIRE_CLEARANCE)
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

