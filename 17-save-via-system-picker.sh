#!/bin/bash
# WiringPro: replaces the 'Save to Downloads' logic entirely. Several
# rounds of MediaStore / legacy-storage-path fixes behaved inconsistently
# on a Samsung Tab Active 2 (writes reported success but landed nowhere
# visible) — likely device/Knox-specific storage behavior that's hard to
# predict from app code.
#
# Now uses Android's system file picker (Storage Access Framework) —
# tapping Save opens the OS's own 'save as' dialog, you pick the
# location, Android handles the write. No permission needed, no
# guessing which Downloads folder a given device means. The
# WRITE_EXTERNAL_STORAGE permission added earlier is removed — no
# longer used by anything.
#
# Run from inside the 'wiringpro' folder (the one containing android-app/).
set -e

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/pdf/PdfSaver.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/pdf/PdfSaver.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.pdf

import android.content.Context
import android.net.Uri
import java.io.File
import java.io.IOException

/**
 * Copies an already-generated PDF into a destination the user picked
 * themselves via Android's system file picker (Storage Access Framework).
 *
 * This replaces an earlier version that tried to guess the right way to
 * write into "Downloads" directly (MediaStore on newer Android, legacy
 * external storage + a runtime permission on older Android). That worked
 * inconsistently on a Samsung Tab Active 2 — writes succeeded with no
 * error, but the file didn't show up where expected, most likely due to
 * Samsung/Knox-specific storage behavior that's hard to predict from app
 * code. Handing the destination choice to the system's own picker sidesteps
 * the whole problem: wherever Android's picker UI shows the file living
 * after you pick a spot is exactly where it lives — no guessing.
 */
object PdfSaver {
    fun copyToUri(context: Context, sourceFile: File, destination: Uri) {
        context.contentResolver.openOutputStream(destination)?.use { out ->
            sourceFile.inputStream().use { input -> input.copyTo(out) }
        } ?: throw IOException("Could not open an output stream for the chosen save location")
    }
}

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/pdf/PdfSaver.kt"

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/connectorlist/ConnectorListScreen.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/connectorlist/ConnectorListScreen.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.ui.screens.connectorlist

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
        val currentConnectors = repository.observeConnectorsWithPins(projectId).first()
        val currentNets = repository.observeNets(projectId).first()
        return withContext(Dispatchers.IO) {
            DiagramPdfGenerator.generate(context, project, currentConnectors, currentNets)
        }
    }

    fun exportForShare(context: Context, onReady: (File) -> Unit, onError: (String) -> Unit) {
        viewModelScope.launch {
            try {
                onReady(generatePdf(context))
            } catch (e: Exception) {
                onError(e.message ?: e.toString())
            }
        }
    }

    /** Generates the PDF and copies it to a destination the user already picked via the system file picker. */
    fun exportAndSaveToUri(context: Context, destination: Uri, onResult: (success: Boolean, message: String) -> Unit) {
        viewModelScope.launch {
            try {
                val file = generatePdf(context)
                withContext(Dispatchers.IO) { PdfSaver.copyToUri(context, file, destination) }
                onResult(true, "Saved")
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

    // System file picker for saving — the user chooses exactly where the
    // PDF goes, so there's no ambiguity about which "Downloads" folder a
    // given device/vendor actually means.
    val savePickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.CreateDocument("application/pdf")
    ) { uri ->
        if (uri != null) {
            viewModel.exportAndSaveToUri(context, uri) { _, message ->
                Toast.makeText(context, message, Toast.LENGTH_LONG).show()
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Connectors") },
                actions = {
                    IconButton(onClick = { savePickerLauncher.launch("wiringpro-diagram.pdf") }) {
                        Icon(Icons.Filled.Save, contentDescription = "Save PDF")
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

echo ""
echo "Done. Sync Gradle (elephant icon) in Android Studio — the manifest changed — then Run."
