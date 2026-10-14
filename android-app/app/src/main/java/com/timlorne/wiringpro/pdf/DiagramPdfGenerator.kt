package com.timlorne.wiringpro.pdf

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.DashPathEffect
import android.graphics.RectF
import android.graphics.pdf.PdfDocument
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import com.timlorne.wiringpro.data.db.ConnectorWithPins
import com.timlorne.wiringpro.data.db.NetEntity
import com.timlorne.wiringpro.data.db.ProjectEntity
import com.timlorne.wiringpro.data.model.BuiltinParts
import com.timlorne.wiringpro.data.model.PlugFaceStyle
import com.timlorne.wiringpro.ui.screens.loom.ConnectorLayout
import com.timlorne.wiringpro.ui.screens.loom.computeLoomLayout
import java.io.File
import java.io.FileOutputStream
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

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
private const val TRUNK_PADDING = 14f
private const val TRUNK_WIRE_GAP = 6f
private const val SHEATH_HEIGHT = 24f
private const val ROUTING_TABLE_HEADER_HEIGHT = 30f
private const val ROUTING_TABLE_ROW_HEIGHT = 18f
private const val PLUG_PIN_SPACING = 26f

enum class PdfWireLayout {
    INDIVIDUAL,
    TRUNKED,
    SHEATHED
}

enum class PdfConnectorView {
    STANDARD,
    PLUG
}

private data class RoutingTableRow(val netName: String, val endpoint: String)

private data class PlugViewGeometry(
    val faceBounds: RectF,
    val calloutLeft: Float,
    val calloutTop: Float,
    val calloutRowHeight: Float,
    val circular: Boolean
)

private fun parseColorOrDefault(hex: String?, default: Int): Int =
    hex?.let { runCatching { Color.parseColor(it) }.getOrNull() } ?: default

private fun parseWireColorOrDefault(value: String?, default: Int): Int {
    val namedColor = when (value?.trim()?.substringBefore('/')?.trim()?.lowercase()) {
        "red" -> Color.rgb(220, 35, 35)
        "black" -> Color.rgb(35, 35, 35)
        "white" -> Color.rgb(210, 215, 218)
        "blue" -> Color.rgb(0, 120, 210)
        "green" -> Color.rgb(20, 145, 65)
        "yellow" -> Color.rgb(230, 175, 0)
        "purple" -> Color.rgb(125, 45, 165)
        "brown" -> Color.rgb(145, 80, 45)
        "orange" -> Color.rgb(235, 120, 20)
        "gray", "grey" -> Color.rgb(125, 130, 135)
        "tan" -> Color.rgb(180, 145, 100)
        else -> null
    }
    return namedColor ?: value?.let { runCatching { Color.parseColor(it.trim()) }.getOrNull() } ?: default
}

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
        nets: List<NetEntity>,
        wireLayout: PdfWireLayout = PdfWireLayout.INDIVIDUAL,
        includeRoutingTable: Boolean = false,
        connectorView: PdfConnectorView = PdfConnectorView.STANDARD
    ): File {
        val (layouts, plugGeometries) = computePdfConnectorLayouts(connectors, connectorView)

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
        val routingTableRows = if (includeRoutingTable) {
            nets.sortedBy { it.name.lowercase() }.flatMap { net ->
                connectors.flatMap { connector ->
                    connector.pins.filter { it.netId == net.id }.map { pin ->
                        val pinName = pin.label?.substringBefore('|')?.trim().orEmpty()
                        val pinSuffix = pinName.takeIf { it.isNotEmpty() }?.let { " ($it)" }.orEmpty()
                        RoutingTableRow(
                            netName = net.name,
                            endpoint = "${connector.connector.label} - pin ${pin.index}$pinSuffix"
                        )
                    }
                }
            }
        } else {
            emptyList()
        }
        val routeLabelPaint = Paint().apply { textSize = 10f }
        val routeLabelWidth = when (wireLayout) {
            PdfWireLayout.TRUNKED, PdfWireLayout.SHEATHED -> 36f
            PdfWireLayout.INDIVIDUAL ->
                (routedNets.maxOfOrNull { routeLabelPaint.measureText(it.first.name) } ?: 0f) + WIRE_LABEL_GAP
        }
        val pageWidth = maxOf(MIN_PAGE_WIDTH, maxX + 2 * MARGIN + routeLabelWidth).toInt()
        val trunkHeight = if (routedNets.isEmpty()) 0f else {
            TRUNK_PADDING * 2 + (routedNets.size - 1) * TRUNK_WIRE_GAP
        }
        val laneHeight = if (routedNets.isEmpty()) 0f else {
            WIRE_LANE_START + when (wireLayout) {
                PdfWireLayout.TRUNKED -> trunkHeight
                PdfWireLayout.SHEATHED -> SHEATH_HEIGHT
                PdfWireLayout.INDIVIDUAL -> routedNets.size * WIRE_LANE_GAP
            }
        }
        val legendTextPaint = Paint().apply { textSize = 11f }
        val legendRows = layoutLegendRows(nets, pageWidth - 2 * MARGIN, legendTextPaint)
        val legendHeight = if (legendRows.isEmpty()) 0f else legendRows.size * LEGEND_ROW_HEIGHT + 20f
        val routingTableHeight = if (routingTableRows.isEmpty()) {
            0f
        } else {
            ROUTING_TABLE_HEADER_HEIGHT + routingTableRows.size * ROUTING_TABLE_ROW_HEIGHT + 14f
        }
        val pageHeight = maxOf(
            MIN_PAGE_HEIGHT,
            TITLE_HEIGHT + maxY + laneHeight + legendHeight + routingTableHeight + 3 * MARGIN
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

        if (wireLayout == PdfWireLayout.TRUNKED && routedNets.isNotEmpty()) {
            val trunkTop = maxY + WIRE_LANE_START
            val trunkBottom = trunkTop + trunkHeight
            val trunkFill = Paint().apply { color = Color.rgb(242, 244, 245); style = Paint.Style.FILL }
            val trunkBorder = Paint().apply {
                color = Color.rgb(117, 126, 132)
                style = Paint.Style.STROKE
                strokeWidth = 1.5f
            }
            canvas.drawRoundRect(RectF(0f, trunkTop, maxX, trunkBottom), 8f, 8f, trunkFill)
            canvas.drawRoundRect(RectF(0f, trunkTop, maxX, trunkBottom), 8f, 8f, trunkBorder)
            val trunkLabel = Paint().apply { color = Color.DKGRAY; textSize = 9f; isFakeBoldText = true }
            canvas.drawText("TRUNKED CABLE BUNDLE", 8f, trunkTop - 6f, trunkLabel)
        }

        if (wireLayout == PdfWireLayout.SHEATHED && routedNets.isNotEmpty()) {
            val allPoints = routedNets.flatMap { it.second }
            val sheathY = maxY + WIRE_LANE_START + SHEATH_HEIGHT / 2f
            val minX = allPoints.minOf { it.x }
            val maxRouteX = allPoints.maxOf { it.x }
            val outerSheath = Paint().apply {
                color = Color.rgb(61, 68, 72)
                strokeWidth = 16f
                strokeCap = Paint.Cap.ROUND
                style = Paint.Style.STROKE
            }
            val innerSheath = Paint().apply {
                color = Color.rgb(179, 187, 191)
                strokeWidth = 10f
                strokeCap = Paint.Cap.ROUND
                style = Paint.Style.STROKE
            }
            canvas.drawLine(minX, sheathY, maxRouteX, sheathY, outerSheath)
            canvas.drawLine(minX, sheathY, maxRouteX, sheathY, innerSheath)

            val branchPaint = Paint().apply {
                color = Color.rgb(75, 82, 86)
                strokeWidth = 1.5f
                pathEffect = DashPathEffect(floatArrayOf(3f, 3f), 0f)
                style = Paint.Style.STROKE
            }
            val endpointPaint = Paint().apply {
                color = Color.rgb(61, 68, 72)
                style = Paint.Style.FILL
            }
            allPoints.forEach { point ->
                canvas.drawLine(point.x, point.y, point.x, sheathY, branchPaint)
                canvas.drawCircle(point.x, sheathY, 2.5f, endpointPaint)
            }
            val sheathLabel = Paint().apply { color = Color.DKGRAY; textSize = 9f; isFakeBoldText = true }
            canvas.drawText("SHEATHED HARNESS - circuits listed below", minX, sheathY + SHEATH_HEIGHT, sheathLabel)
        }

        // Draw one labeled lane per net so fan-out paths are easy to trace.
        for ((laneIndex, route) in routedNets.withIndex()) {
            if (wireLayout == PdfWireLayout.SHEATHED) continue
            val (net, points) = route
            val trunkY = if (wireLayout == PdfWireLayout.TRUNKED) {
                maxY + WIRE_LANE_START + TRUNK_PADDING + laneIndex * TRUNK_WIRE_GAP
            } else {
                maxY + WIRE_LANE_START + laneIndex * WIRE_LANE_GAP
            }
            val color = parseColorOrDefault(net.color, Color.DKGRAY)
            val wirePaint = Paint().apply {
                this.color = color
                strokeWidth = if (wireLayout == PdfWireLayout.TRUNKED) 2f else 2.8f
                style = Paint.Style.STROKE
            }
            val stripePaint = net.stripeColor?.let { stripe ->
                Paint().apply {
                    this.color = parseColorOrDefault(stripe, Color.WHITE)
                    strokeWidth = if (wireLayout == PdfWireLayout.TRUNKED) 0.8f else 1f
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
            if (wireLayout == PdfWireLayout.INDIVIDUAL) {
                val labelPaint = Paint().apply {
                    this.color = Color.BLACK
                    textSize = 10f
                    isFakeBoldText = true
                }
                canvas.drawText(net.name, maxX + WIRE_LABEL_GAP, trunkY + 4f, labelPaint)
            }
        }

        for (layout in layouts) {
            val left = layout.position.x
            val top = layout.position.y

            val boxPaint = Paint().apply { color = Color.rgb(153, 153, 153); style = Paint.Style.STROKE; strokeWidth = 1.5f }
            canvas.drawRoundRect(RectF(left, top, left + layout.size.width, top + layout.size.height), 10f, 10f, boxPaint)

            val labelPaint = Paint().apply { color = Color.BLACK; textSize = 13f; isFakeBoldText = true }
            canvas.drawText(layout.label, left + 8f, top + 18f, labelPaint)

            val connector = connectors.first { it.connector.id == layout.connectorId }
            val plugGeometry = plugGeometries[layout.connectorId]
            if (plugGeometry != null) {
                drawPlugConnector(canvas, connector, layout, plugGeometry)
                continue
            }
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
            drawLegend(canvas, legendRows, pageHeight - MARGIN - routingTableHeight - legendHeight + 14f)
        }
        if (routingTableRows.isNotEmpty()) {
            drawRoutingTable(canvas, routingTableRows, pageWidth, pageHeight - MARGIN - routingTableHeight)
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

    private fun computePdfConnectorLayouts(
        connectors: List<ConnectorWithPins>,
        connectorView: PdfConnectorView
    ): Pair<List<ConnectorLayout>, Map<String, PlugViewGeometry>> {
        if (connectorView == PdfConnectorView.STANDARD) {
            return computeLoomLayout(connectors) to emptyMap()
        }

        val templatesById = BuiltinParts.ALL.associateBy { it.id }
        val calloutMeasurePaint = Paint().apply { textSize = 9f }
        val layouts = mutableListOf<ConnectorLayout>()
        val geometries = mutableMapOf<String, PlugViewGeometry>()
        var cursorY = 12f

        for (connector in connectors) {
            val template = connector.connector.partRef?.let(templatesById::get)
            val rows = template?.rows ?: connector.connector.rows
            val isCircular = template?.faceStyle == PlugFaceStyle.CIRCULAR
            val orderedPins = connector.pins.sortedBy { it.index }
            val faceWidth = if (isCircular) 156f else {
                (rows.maxOrNull() ?: 1) * PLUG_PIN_SPACING + 20f
            }
            val faceHeight = if (isCircular) 156f else rows.size * PLUG_PIN_SPACING + 20f
            val faceLeft = 18f
            val faceTop = cursorY + 30f
            val calloutLeft = faceLeft + faceWidth + 18f
            val calloutTop = cursorY + 38f
            val calloutRowHeight = 15f
            val longestCallout = orderedPins.maxOfOrNull { pin ->
                val pinName = pin.label?.substringBefore('|')?.trim().orEmpty().ifBlank { "Pin ${pin.index}" }
                calloutMeasurePaint.measureText("${pin.index}. $pinName")
            } ?: 0f
            val panelWidth = calloutLeft + longestCallout + 20f
            val panelHeight = maxOf(
                faceHeight + 46f,
                calloutTop - cursorY + orderedPins.size * calloutRowHeight + 10f
            )
            val faceBounds = RectF(faceLeft, faceTop, faceLeft + faceWidth, faceTop + faceHeight)
            val pinRects = mutableMapOf<String, Rect>()

            if (isCircular) {
                val centerX = faceBounds.centerX()
                val centerY = faceBounds.centerY()
                val pinRadius = minOf(faceWidth, faceHeight) * 0.31f
                val cavitySize = if (orderedPins.size > 12) 10f else 14f
                orderedPins.forEachIndexed { index, pin ->
                    val angle = -PI / 2.0 + 2.0 * PI * index / orderedPins.size
                    val pinX = centerX + pinRadius * cos(angle).toFloat()
                    val pinY = centerY + pinRadius * sin(angle).toFloat()
                    pinRects[pin.id] = Rect(
                        Offset(pinX - cavitySize / 2f, pinY - cavitySize / 2f),
                        Size(cavitySize, cavitySize)
                    )
                }
            } else {
                for (pin in orderedPins) {
                    val rowCount = rows.getOrElse(pin.row) { 1 }
                    val rowWidth = rowCount * PLUG_PIN_SPACING
                    val rowLeft = faceBounds.left + (faceWidth - rowWidth) / 2f + PLUG_PIN_SPACING / 2f
                    val pinX = rowLeft + pin.col * PLUG_PIN_SPACING
                    val pinY = faceBounds.top + 10f + pin.row * PLUG_PIN_SPACING + PLUG_PIN_SPACING / 2f
                    pinRects[pin.id] = Rect(
                        Offset(pinX - 7f, pinY - 7f),
                        Size(14f, 14f)
                    )
                }
            }

            layouts.add(
                ConnectorLayout(
                    connectorId = connector.connector.id,
                    label = connector.connector.label,
                    position = Offset(0f, cursorY),
                    size = Size(panelWidth, panelHeight),
                    pinRects = pinRects
                )
            )
            geometries[connector.connector.id] = PlugViewGeometry(
                faceBounds = faceBounds,
                calloutLeft = calloutLeft,
                calloutTop = calloutTop,
                calloutRowHeight = calloutRowHeight,
                circular = isCircular
            )
            cursorY += panelHeight + 28f
        }
        return layouts to geometries
    }

    private fun drawPlugConnector(
        canvas: Canvas,
        connector: ConnectorWithPins,
        layout: ConnectorLayout,
        geometry: PlugViewGeometry
    ) {
        val left = layout.position.x
        val top = layout.position.y
        val panelBounds = RectF(left, top, left + layout.size.width, top + layout.size.height)
        val panelFill = Paint().apply { color = Color.rgb(250, 250, 248); style = Paint.Style.FILL }
        val panelBorder = Paint().apply {
            color = Color.rgb(153, 153, 153)
            style = Paint.Style.STROKE
            strokeWidth = 1.5f
        }
        canvas.drawRoundRect(panelBounds, 8f, 8f, panelFill)
        canvas.drawRoundRect(panelBounds, 8f, 8f, panelBorder)

        val titlePaint = Paint().apply { color = Color.BLACK; textSize = 12f; isFakeBoldText = true }
        canvas.drawText(layout.label, left + 10f, top + 17f, titlePaint)

        val faceFill = Paint().apply { color = Color.rgb(52, 59, 64); style = Paint.Style.FILL }
        val faceBorder = Paint().apply {
            color = Color.rgb(138, 150, 157)
            style = Paint.Style.STROKE
            strokeWidth = 1.5f
        }
        if (geometry.circular) {
            canvas.drawOval(geometry.faceBounds, faceFill)
            canvas.drawOval(geometry.faceBounds, faceBorder)
        } else {
            canvas.drawRoundRect(geometry.faceBounds, 8f, 8f, faceFill)
            canvas.drawRoundRect(geometry.faceBounds, 8f, 8f, faceBorder)
        }

        val pins = connector.pins.sortedBy { it.index }
        pins.forEach { pin ->
            val rect = layout.pinRects[pin.id] ?: return@forEach
            val cavity = RectF(rect.left, rect.top, rect.right, rect.bottom)
            val cavityPaint = Paint().apply { color = Color.rgb(211, 164, 77); style = Paint.Style.FILL }
            val cavityBorder = Paint().apply {
                color = Color.rgb(255, 217, 130)
                style = Paint.Style.STROKE
                strokeWidth = 1f
            }
            canvas.drawOval(cavity, cavityPaint)
            canvas.drawOval(cavity, cavityBorder)
            val numberPaint = Paint().apply { color = Color.rgb(38, 38, 38); textSize = 7f; isFakeBoldText = true }
            canvas.drawText(pin.index.toString(), cavity.centerX() - 2f, cavity.centerY() + 2.5f, numberPaint)
        }

        val calloutPaint = Paint().apply { color = Color.BLACK; textSize = 9f }
        pins.forEachIndexed { index, pin ->
            val pinName = pin.label?.substringBefore('|')?.trim().orEmpty().ifBlank { "Pin ${pin.index}" }
            val rowY = geometry.calloutTop + index * geometry.calloutRowHeight
            drawFittedText(
                canvas,
                "${pin.index}. $pinName",
                geometry.calloutLeft,
                rowY,
                layout.size.width - geometry.calloutLeft - 10f,
                calloutPaint
            )
        }
    }

    private fun drawRoutingTable(canvas: Canvas, rows: List<RoutingTableRow>, pageWidth: Int, top: Float) {
        val left = MARGIN
        val right = pageWidth - MARGIN
        val netColumnWidth = ((right - left) * 0.28f).coerceIn(90f, 190f)
        val background = Paint().apply { color = Color.rgb(248, 249, 250); style = Paint.Style.FILL }
        val border = Paint().apply {
            color = Color.rgb(120, 128, 132)
            style = Paint.Style.STROKE
            strokeWidth = 1f
        }
        val bottom = top + ROUTING_TABLE_HEADER_HEIGHT + rows.size * ROUTING_TABLE_ROW_HEIGHT + 8f
        canvas.drawRect(RectF(left, top, right, bottom), background)
        canvas.drawRect(RectF(left, top, right, bottom), border)

        val headingPaint = Paint().apply { color = Color.BLACK; textSize = 11f; isFakeBoldText = true }
        canvas.drawText("WIRE ROUTING", left + 8f, top + 13f, headingPaint)
        canvas.drawText("NET", left + 8f, top + 27f, headingPaint)
        canvas.drawText("CONNECTOR / PIN", left + netColumnWidth + 8f, top + 27f, headingPaint)
        canvas.drawLine(left, top + ROUTING_TABLE_HEADER_HEIGHT, right, top + ROUTING_TABLE_HEADER_HEIGHT, border)

        val netPaint = Paint().apply { color = Color.BLACK; textSize = 9f; isFakeBoldText = true }
        val endpointPaint = Paint().apply { color = Color.DKGRAY; textSize = 9f }
        rows.forEachIndexed { index, row ->
            val rowTop = top + ROUTING_TABLE_HEADER_HEIGHT + index * ROUTING_TABLE_ROW_HEIGHT
            if (index % 2 == 1) {
                val alternateFill = Paint().apply { color = Color.rgb(238, 241, 243); style = Paint.Style.FILL }
                canvas.drawRect(RectF(left, rowTop, right, rowTop + ROUTING_TABLE_ROW_HEIGHT), alternateFill)
            }
            drawFittedText(canvas, row.netName, left + 8f, rowTop + 12f, netColumnWidth - 16f, netPaint)
            drawFittedText(
                canvas,
                row.endpoint,
                left + netColumnWidth + 8f,
                rowTop + 12f,
                right - left - netColumnWidth - 16f,
                endpointPaint
            )
        }
    }

    private fun drawFittedText(canvas: Canvas, text: String, x: Float, y: Float, maxWidth: Float, paint: Paint) {
        if (paint.measureText(text) <= maxWidth) {
            canvas.drawText(text, x, y, paint)
            return
        }
        var fitted = text
        while (fitted.isNotEmpty() && paint.measureText("$fitted...") > maxWidth) {
            fitted = fitted.dropLast(1)
        }
        canvas.drawText("$fitted...", x, y, paint)
    }
}

