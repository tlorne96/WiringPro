#!/bin/bash
# WiringPro: fixes the silent PDF-save failure. PdfSaver was catching
# its own exceptions and returning a bare 'false' with no detail, and
# the file copy was running on the main thread. Now the save runs on
# Dispatchers.IO, PdfSaver throws real exceptions instead of swallowing
# them, and the toast shows the ACTUAL error message so this is
# self-diagnosing if it fails again.
# Run from inside the 'wiringpro' folder (the one containing android-app/).
set -e

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/pdf/PdfSaver.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/pdf/PdfSaver.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.pdf

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.IOException

/**
 * Saves a generated PDF straight to the device's Downloads folder — no
 * share sheet, no picking an app to hand it off to. On Android 10+ this
 * goes through MediaStore so it lands in the real public Downloads folder
 * other apps (a file manager, etc) can see. Below that, scoped storage
 * doesn't apply yet but requesting WRITE_EXTERNAL_STORAGE just for this
 * felt like overkill, so older devices get the app's own external Downloads
 * folder instead — still on-device, just one level less discoverable.
 *
 * Throws rather than swallowing failures — the caller's catch block is
 * where the real error message should surface, not lost behind a bare
 * true/false.
 */
object PdfSaver {

    fun saveToDownloads(context: Context, sourceFile: File, displayName: String): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, displayName)
                put(MediaStore.Downloads.MIME_TYPE, "application/pdf")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = context.contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IOException("MediaStore refused to create an entry in Downloads")
            resolver.openOutputStream(uri)?.use { out ->
                sourceFile.inputStream().use { input -> input.copyTo(out) }
            } ?: throw IOException("Could not open an output stream for the new Downloads entry")
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return true
        } else {
            val dir = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
                ?: throw IOException("No external files directory available on this device")
            dir.mkdirs()
            sourceFile.copyTo(File(dir, displayName), overwrite = true)
            return true
        }
    }
}

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/pdf/PdfSaver.kt"

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/connectorlist/ConnectorListScreen.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/connectorlist/ConnectorListScreen.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.ui.screens.connectorlist

import android.content.Context
import android.content.Intent
import android.widget.Toast
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AccountTree
import androidx.compose.material.icons.filled.Save
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
import com.timlorne.wiringpro.pdf.PdfSaver
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class ConnectorListViewModel(
    private val repository: WiringRepository,
    private val projectId: String
) : ViewModel() {
    val connectors = repository.observeConnectorsWithPins(projectId)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val nets = repository.observeNets(projectId)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    private suspend fun generatePdf(context: Context): File {
        val project = repository.getProject(projectId) ?: error("Project not found")
        // Fetch fresh from the DB rather than trusting the cached StateFlow
        // values — nets in particular was never guaranteed to be "warm", so
        // .value could silently stay at its empty initial state forever.
        val currentConnectors = repository.observeConnectorsWithPins(projectId).first()
        val currentNets = repository.observeNets(projectId).first()
        return withContext(Dispatchers.IO) {
            DiagramPdfGenerator.generate(context, project, currentConnectors, currentNets)
        }
    }

    /** Generates the PDF and hands the file back for the caller to share. */
    fun exportForShare(context: Context, onReady: (File) -> Unit, onError: (String) -> Unit) {
        viewModelScope.launch {
            try {
                onReady(generatePdf(context))
            } catch (e: Exception) {
                onError(e.message ?: e.toString())
            }
        }
    }

    /** Generates the PDF and saves it straight to Downloads — no share sheet. */
    fun exportAndSave(context: Context, onResult: (success: Boolean, message: String) -> Unit) {
        viewModelScope.launch {
            try {
                val file = generatePdf(context)
                val ok = withContext(Dispatchers.IO) {
                    PdfSaver.saveToDownloads(context, file, file.name)
                }
                onResult(ok, if (ok) "Saved to Downloads: ${file.name}" else "Save failed — no error thrown, but the write didn't complete")
            } catch (e: Exception) {
                onResult(false, "Error: ${e.message ?: e.toString()}")
            }
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
                        viewModel.exportAndSave(context) { _, message ->
                            Toast.makeText(context, message, Toast.LENGTH_LONG).show()
                        }
                    }) {
                        Icon(Icons.Filled.Save, contentDescription = "Save PDF to Downloads")
                    }
                    IconButton(onClick = {
                        viewModel.exportForShare(
                            context = context,
                            onReady = { file ->
                                val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
                                val intent = Intent(Intent.ACTION_SEND).apply {
                                    type = "application/pdf"
                                    putExtra(Intent.EXTRA_STREAM, uri)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                context.startActivity(Intent.createChooser(intent, "Share wiring diagram"))
                            },
                            onError = { message ->
                                Toast.makeText(context, "Export failed: $message", Toast.LENGTH_LONG).show()
                            }
                        )
                    }) {
                        Icon(Icons.Filled.Share, contentDescription = "Share PDF")
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

echo ""
echo "Done. No Gradle changes — just rebuild/Run."
