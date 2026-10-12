#!/bin/bash
# WiringPro: adds PDF export. Lays every connector in the project out on
# one page (same flow-layout the loom canvas uses), draws the actual
# wire between every connected pin pair (including fan-out), adds a
# color legend, and opens the share sheet so you can save/print it.
#
# Adds a FileProvider + androidx.core dependency needed to share a file
# from app-private storage — both included below.
#
# Run from inside the 'wiringpro' folder (the one containing android-app/).
set -e

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/data/repository/WiringRepository.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/data/repository/WiringRepository.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.data.repository

import android.content.Context
import android.net.Uri
import com.timlorne.wiringpro.data.db.AppDatabase
import com.timlorne.wiringpro.data.db.ConnectorEntity
import com.timlorne.wiringpro.data.db.ConnectorWithPins
import com.timlorne.wiringpro.data.db.NetEntity
import com.timlorne.wiringpro.data.db.PinEntity
import com.timlorne.wiringpro.data.db.ProjectEntity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

// A net plus a human-readable list of where it's currently connected, e.g.
// ["Main pin 1", "Throttle pin 5"] — this is what lets the net picker show
// what a net already touches instead of just its bare name.
data class NetWithAssignments(val net: NetEntity, val assignmentLabels: List<String>)

class WiringRepository(private val db: AppDatabase) {

    // -------------------------------------------------------------
    // Projects
    // -------------------------------------------------------------

    fun observeProjects(): Flow<List<ProjectEntity>> = db.projectDao().observeAll()

    suspend fun createProject(name: String): String {
        val id = UUID.randomUUID().toString()
        val now = System.currentTimeMillis()
        db.projectDao().upsert(
            ProjectEntity(id = id, name = name, vehicle = null, notes = null, createdAt = now, updatedAt = now)
        )
        return id
    }

    suspend fun getProject(id: String): ProjectEntity? = db.projectDao().getById(id)

    /**
     * Copies the picked photo into app-private storage (so it survives even
     * if the original is deleted from the gallery) and records the path.
     * One file per project, overwritten on re-pick.
     */
    suspend fun setProjectImage(projectId: String, uri: Uri, context: Context) {
        withContext(Dispatchers.IO) {
            val dir = File(context.filesDir, "project_images").apply { mkdirs() }
            val dest = File(dir, "$projectId.jpg")
            context.contentResolver.openInputStream(uri)?.use { input ->
                dest.outputStream().use { output -> input.copyTo(output) }
            }
            db.projectDao().setImagePath(projectId, dest.absolutePath)
        }
    }

    // -------------------------------------------------------------
    // Connectors + pins
    // -------------------------------------------------------------

    /**
     * Creates a connector and generates its pins.
     *
     * Numbering rule (per project decision): pins are indexed left-to-right,
     * then top-to-bottom — reading like a book. Given rows = [8, 8, 8] for a
     * 24-pin connector, pin 1 is row 0/col 0, pin 8 is row 0/col 7, pin 9 is
     * row 1/col 0, and so on. This is the one place that numbering logic
     * lives — don't duplicate it in the UI layer.
     */
    suspend fun createConnector(projectId: String, label: String, rows: List<Int>): String {
        val connectorId = UUID.randomUUID().toString()
        db.connectorDao().upsert(
            ConnectorEntity(
                id = connectorId,
                projectId = projectId,
                label = label,
                rows = rows,
                partRef = null
            )
        )

        val pins = mutableListOf<PinEntity>()
        var pinIndex = 1
        for (row in rows.indices) {
            for (col in 0 until rows[row]) {
                pins.add(
                    PinEntity(
                        id = UUID.randomUUID().toString(),
                        connectorId = connectorId,
                        index = pinIndex,
                        row = row,
                        col = col,
                        netId = null,
                        label = null
                    )
                )
                pinIndex++
            }
        }
        db.pinDao().upsertAll(pins)
        return connectorId
    }

    fun observeConnectorsWithPins(projectId: String): Flow<List<ConnectorWithPins>> =
        db.connectorDao().observeWithPinsForProject(projectId)

    fun observeConnectorWithPins(connectorId: String): Flow<ConnectorWithPins?> =
        db.connectorDao().observeWithPins(connectorId)

    // -------------------------------------------------------------
    // Nets
    // -------------------------------------------------------------

    fun observeNets(projectId: String): Flow<List<NetEntity>> =
        db.netDao().observeForProject(projectId)

    /**
     * Nets in the project alongside where each one is currently connected —
     * "Main pin 1", "Throttle pin 5", etc. Powers the net picker's
     * "already used in this project" list so assigning a pin shows what
     * you're actually about to join it to, not just a bare net name.
     */
    fun observeNetsWithAssignments(projectId: String): Flow<List<NetWithAssignments>> =
        combine(observeNets(projectId), db.pinDao().observeAssignmentsForProject(projectId)) { nets, rows ->
            val byNet = rows.groupBy { it.netId }
            nets.map { net ->
                val labels = byNet[net.id]?.map { "${it.connectorLabel} pin ${it.pinIndex}" } ?: emptyList()
                NetWithAssignments(net, labels)
            }
        }

    /**
     * Finds an existing net with this name in the project, or creates one.
     * This is what makes "ground fans out to five places" work: assigning
     * the same net name to five different pins reuses one NetEntity instead
     * of creating five disconnected ones.
     */
    suspend fun getOrCreateNet(projectId: String, name: String, netType: String, color: String?): String {
        db.netDao().findByName(projectId, name)?.let { return it.id }
        val id = UUID.randomUUID().toString()
        db.netDao().upsert(NetEntity(id = id, projectId = projectId, name = name, netType = netType, color = color))
        return id
    }

    suspend fun assignPinToNet(pinId: String, netId: String?) {
        db.pinDao().assignNet(pinId, netId)
    }

    suspend fun clearPinNet(pinId: String) {
        db.pinDao().assignNet(pinId, null)
    }
}

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/data/repository/WiringRepository.kt"

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
        for (net in nets) {
            val pinIds = pinsById.values.filter { it.netId == net.id }.map { it.id }
            val points = pinIds.mapNotNull { pinCenters[it] }
            if (points.size < 2) continue
            val color = parseColorOrDefault(net.color, Color.DKGRAY)
            val wirePaint = Paint().apply { this.color = color; strokeWidth = 2.5f; style = Paint.Style.STROKE }
            val source = points.first()
            for (target in points.drop(1)) {
                canvas.drawLine(source.x, source.y, target.x, target.y, wirePaint)
            }
            if (points.size > 2) {
                val dotPaint = Paint().apply { this.color = color; style = Paint.Style.FILL }
                canvas.drawCircle(source.x, source.y, 3f, dotPaint)
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

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/connectorlist/ConnectorListScreen.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/connectorlist/ConnectorListScreen.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.ui.screens.connectorlist

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AccountTree
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
import kotlinx.coroutines.flow.SharingStarted
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
            val file = DiagramPdfGenerator.generate(context, project, connectors.value, nets.value)
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
                            val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
                            val intent = Intent(Intent.ACTION_SEND).apply {
                                type = "application/pdf"
                                putExtra(Intent.EXTRA_STREAM, uri)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            context.startActivity(Intent.createChooser(intent, "Share wiring diagram"))
                        }
                    }) {
                        Icon(Icons.Filled.Share, contentDescription = "Export PDF")
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

mkdir -p "$(dirname "android-app/app/src/main/AndroidManifest.xml")"
cat > android-app/app/src/main/AndroidManifest.xml << 'XML_EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <application
        android:name=".WiringProApplication"
        android:allowBackup="true"
        android:label="WiringPro"
        android:theme="@android:style/Theme.Material.Light.NoActionBar">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:label="WiringPro">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/file_paths" />
        </provider>

    </application>

</manifest>

XML_EOF
echo "Wrote android-app/app/src/main/AndroidManifest.xml"

mkdir -p "$(dirname "android-app/app/src/main/res/xml/file_paths.xml")"
cat > android-app/app/src/main/res/xml/file_paths.xml << 'XML_EOF'
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <cache-path name="pdfs" path="." />
</paths>

XML_EOF
echo "Wrote android-app/app/src/main/res/xml/file_paths.xml"

cat > android-app/app/build.gradle.kts << 'GRADLE_EOF'
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
    implementation("androidx.core:core-ktx:1.12.0")
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

GRADLE_EOF
echo "Wrote android-app/app/build.gradle.kts"

echo ""
echo "Done. Sync Gradle (elephant icon) in Android Studio, then Run."
echo "New: tap the share icon (top-left of the two, on the Connectors screen) to export a PDF."
