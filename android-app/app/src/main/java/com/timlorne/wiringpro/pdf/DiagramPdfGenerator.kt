package com.timlorne.wiringpro.pdf

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.DashPathEffect
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
private const val MIN_PAGE_WIDTH = 400f
private const val MIN_PAGE_HEIGHT = 300f
private const val WIRE_LANE_START = 48f
private const val WIRE_LANE_GAP = 28f
private const val WIRE_LABEL_GAP = 24f

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
 * Keeps connector cells at their native drawing size and gives each connected
 * net a labeled horizontal lane below the connectors. Page dimensions grow
 * with the map instead of shrinking a large project to fit a standard sheet.
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
        val pinCenters = HashMap<String, android.graphics.PointF>()
        for (layout in layouts) {
            for ((pinId, rect) in layout.pinRects) {
                pinCenters[pinId] = android.graphics.PointF(rect.center.x, rect.center.y)
            }
        }
        val pinsById = connectors.flatMap { it.pins }.associateBy { it.id }
        val routedNets = nets.sortedBy { it.name.lowercase() }.mapNotNull { net ->
            val points = pinsById.values
                .filter { it.netId == net.id }
                .mapNotNull { pin -> pinCenters[pin.id] }
            if (points.size < 2) null else net to points
        }
        val routeLabelPaint = Paint().apply { textSize = 10f }
        val routeLabelWidth = (routedNets.maxOfOrNull { routeLabelPaint.measureText(it.first.name) } ?: 0f) + WIRE_LABEL_GAP
        val pageWidth = maxOf(MIN_PAGE_WIDTH, maxX + 2 * MARGIN + routeLabelWidth).toInt()
        val laneHeight = if (routedNets.isEmpty()) 0f else {
            WIRE_LANE_START + routedNets.size * WIRE_LANE_GAP
        }
        val legendTextPaint = Paint().apply { textSize = 11f }
        val legendRows = layoutLegendRows(nets, pageWidth - 2 * MARGIN, legendTextPaint)
        val legendHeight = if (legendRows.isEmpty()) 0f else legendRows.size * LEGEND_ROW_HEIGHT + 20f
        val pageHeight = maxOf(
            MIN_PAGE_HEIGHT,
            TITLE_HEIGHT + maxY + laneHeight + legendHeight + 3 * MARGIN
        ).toInt()

        val document = PdfDocument()
        val pageInfo = PdfDocument.PageInfo.Builder(pageWidth, pageHeight, 1).create()
        val page = document.startPage(pageInfo)
        val canvas = page.canvas

        drawTitle(canvas, project)
        val contentTop = TITLE_HEIGHT
        canvas.save()
        canvas.translate(MARGIN, contentTop)

        val netsById = nets.associateBy { it.id }

        // Draw one labeled lane per net so fan-out paths are easy to trace.
        for ((laneIndex, route) in routedNets.withIndex()) {
            val (net, points) = route
            val trunkY = maxY + WIRE_LANE_START + laneIndex * WIRE_LANE_GAP
            val color = parseColorOrDefault(net.color, Color.DKGRAY)
            val wirePaint = Paint().apply { this.color = color; strokeWidth = 2.8f; style = Paint.Style.STROKE }
            val stripePaint = net.stripeColor?.let { stripe ->
                Paint().apply {
                    this.color = parseColorOrDefault(stripe, Color.WHITE)
                    strokeWidth = 1f
                    style = Paint.Style.STROKE
                    pathEffect = DashPathEffect(floatArrayOf(5f, 4f), 0f)
                }
            }
            fun drawWireSegment(startX: Float, startY: Float, endX: Float, endY: Float) {
                canvas.drawLine(startX, startY, endX, endY, wirePaint)
                stripePaint?.let { canvas.drawLine(startX, startY, endX, endY, it) }
            }

            val firstX = points.minOf { it.x }
            val lastX = points.maxOf { it.x }
            points.forEach { point -> drawWireSegment(point.x, point.y, point.x, trunkY) }
            drawWireSegment(firstX, trunkY, lastX, trunkY)

            val dotPaint = Paint().apply { this.color = color; style = Paint.Style.FILL }
            points.forEach { canvas.drawCircle(it.x, trunkY, 3f, dotPaint) }
            val labelPaint = Paint().apply {
                color = Color.BLACK
                textSize = 10f
                isFakeBoldText = true
            }
            canvas.drawText(net.name, maxX + WIRE_LABEL_GAP, trunkY + 4f, labelPaint)
        }

        for (layout in layouts) {
            val left = layout.position.x
            val top = layout.position.y

            val boxPaint = Paint().apply { color = Color.rgb(153, 153, 153); style = Paint.Style.STROKE; strokeWidth = 1.5f }
            canvas.drawRoundRect(RectF(left, top, left + layout.size.width, top + layout.size.height), 10f, 10f, boxPaint)

            val labelPaint = Paint().apply { color = Color.BLACK; textSize = 13f; isFakeBoldText = true }
            canvas.drawText(layout.label, left + 8f, top + 18f, labelPaint)

            val connector = connectors.first { it.connector.id == layout.connectorId }
            for (pin in connector.pins) {
                val rect = layout.pinRects[pin.id] ?: continue
                val pLeft = rect.left
                val pTop = rect.top
                val pRight = rect.right
                val pBottom = rect.bottom
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
                } else {
                    val pinDetails = pin.label?.split(" | ")
                    if (!pinDetails.isNullOrEmpty()) {
                        val pinNamePaint = Paint().apply { color = Color.DKGRAY; textSize = 7f }
                        canvas.drawText(pinDetails[0], pLeft + 5f, pTop + 30f, pinNamePaint)
                        if (pinDetails.size > 2) {
                            val wirePaint = Paint().apply { color = Color.DKGRAY; textSize = 6f }
                            canvas.drawText(pinDetails[2], pLeft + 5f, pBottom - 5f, wirePaint)
                        }
                    }
                }
            }
        }

        canvas.restore()

        if (legendRows.isNotEmpty()) {
            drawLegend(canvas, legendRows, pageHeight - MARGIN - legendHeight + 14f)
        }

        val borderPaint = Paint().apply {
            color = Color.rgb(70, 70, 70)
            style = Paint.Style.STROKE
            strokeWidth = 2f
        }
        canvas.drawRoundRect(
            RectF(12f, 12f, pageWidth - 12f, pageHeight - 12f),
            14f,
            14f,
            borderPaint
        )

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
                net.stripeColor?.let { stripe ->
                    val stripePaint = Paint().apply {
                        this.color = parseColorOrDefault(stripe, Color.WHITE)
                        strokeWidth = 1f
                        pathEffect = DashPathEffect(floatArrayOf(5f, 4f), 0f)
                    }
                    canvas.drawLine(x, y, x + LEGEND_SWATCH_W, y, stripePaint)
                }

                val textPaint = Paint().apply { this.color = Color.BLACK; textSize = 11f }
                canvas.drawText(net.name, x + LEGEND_SWATCH_W + 6f, y + 4f, textPaint)

                x += LEGEND_SWATCH_W + 6f + textPaint.measureText(net.name) + LEGEND_ENTRY_GAP
            }
            y += LEGEND_ROW_HEIGHT
        }
    }
}

