#!/bin/bash
# WiringPro: adds the connector list/home screen (so you can add more than
# one connector without restarting), and re-writes a few files that had bugs
# fixed live in chat, so your project matches the corrected source.
# Run from inside the 'wiringpro' folder (the one containing android-app/).
set -e

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/connectorlist/ConnectorListScreen.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/connectorlist/ConnectorListScreen.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.ui.screens.connectorlist

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.timlorne.wiringpro.data.db.ConnectorWithPins
import com.timlorne.wiringpro.data.repository.WiringRepository
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.stateIn

class ConnectorListViewModel(
    repository: WiringRepository,
    projectId: String
) : ViewModel() {
    val connectors = repository.observeConnectorsWithPins(projectId)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConnectorListScreen(
    viewModel: ConnectorListViewModel,
    onAddConnector: () -> Unit,
    onOpenConnector: (String) -> Unit
) {
    val connectors by viewModel.connectors.collectAsState()

    Scaffold(
        topBar = { TopAppBar(title = { Text("Connectors") }) },
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

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/ui/nav/WiringProNavHost.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/ui/nav/WiringProNavHost.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.ui.nav

import androidx.compose.runtime.Composable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.timlorne.wiringpro.data.repository.WiringRepository
import com.timlorne.wiringpro.ui.screens.connectorlist.ConnectorListScreen
import com.timlorne.wiringpro.ui.screens.connectorlist.ConnectorListViewModel
import com.timlorne.wiringpro.ui.screens.editor.PinGridEditorScreen
import com.timlorne.wiringpro.ui.screens.editor.PinGridEditorViewModel
import com.timlorne.wiringpro.ui.screens.newconnector.NewConnectorScreen
import com.timlorne.wiringpro.ui.screens.newconnector.NewConnectorViewModel

private class SimpleFactory(private val create: () -> ViewModel) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = create() as T
}

@Composable
fun WiringProNavHost(repository: WiringRepository, projectId: String) {
    val navController: NavHostController = rememberNavController()

    NavHost(navController = navController, startDestination = "connector_list") {
        composable("connector_list") {
            val vm: ConnectorListViewModel = viewModel(
                factory = SimpleFactory { ConnectorListViewModel(repository, projectId) }
            )
            ConnectorListScreen(
                viewModel = vm,
                onAddConnector = { navController.navigate("new_connector") },
                onOpenConnector = { connectorId -> navController.navigate("editor/$connectorId") }
            )
        }

        composable("new_connector") {
            val vm: NewConnectorViewModel = viewModel(
                factory = SimpleFactory { NewConnectorViewModel(repository, projectId) }
            )
            NewConnectorScreen(
                viewModel = vm,
                onConnectorCreated = { connectorId ->
                    navController.navigate("editor/$connectorId") {
                        popUpTo("connector_list")
                    }
                },
                onBack = { navController.popBackStack() }
            )
        }

        composable(
            route = "editor/{connectorId}",
            arguments = listOf(navArgument("connectorId") { type = NavType.StringType })
        ) { backStackEntry ->
            val connectorId = backStackEntry.arguments?.getString("connectorId")!!
            val vm: PinGridEditorViewModel = viewModel(
                factory = SimpleFactory { PinGridEditorViewModel(repository, projectId, connectorId) }
            )
            PinGridEditorScreen(viewModel = vm)
        }
    }
}

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/ui/nav/WiringProNavHost.kt"

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/editor/PinGridEditorScreen.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/editor/PinGridEditorScreen.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.ui.screens.editor

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.timlorne.wiringpro.data.db.NetEntity
import com.timlorne.wiringpro.data.db.PinEntity
import com.timlorne.wiringpro.data.repository.WiringRepository
import com.timlorne.wiringpro.ui.components.NetPickerDialog
import com.timlorne.wiringpro.ui.components.PinGrid
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class PinGridEditorViewModel(
    private val repository: WiringRepository,
    private val projectId: String,
    private val connectorId: String
) : ViewModel() {

    val connectorWithPins = repository.observeConnectorWithPins(connectorId)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    val nets = repository.observeNets(projectId)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    fun assignExisting(pinId: String, net: NetEntity) {
        viewModelScope.launch { repository.assignPinToNet(pinId, net.id) }
    }

    fun assignNew(pinId: String, name: String, netType: String, color: String?) {
        viewModelScope.launch {
            val netId = repository.getOrCreateNet(projectId, name, netType, color)
            repository.assignPinToNet(pinId, netId)
        }
    }

    fun clear(pinId: String) {
        viewModelScope.launch { repository.clearPinNet(pinId) }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PinGridEditorScreen(viewModel: PinGridEditorViewModel) {
    val connectorWithPins by viewModel.connectorWithPins.collectAsState()
    val nets by viewModel.nets.collectAsState()
    var tappedPin by remember { mutableStateOf<PinEntity?>(null) }

    Scaffold(topBar = { TopAppBar(title = { Text(connectorWithPins?.connector?.label ?: "Connector") }) }) { padding ->
        val cwp = connectorWithPins
        if (cwp == null) {
            Text("Loading…", modifier = Modifier.padding(padding).padding(16.dp))
        } else {
            PinGrid(
                connector = cwp.connector,
                pins = cwp.pins,
                nets = nets,
                onPinClick = { pin -> tappedPin = pin },
                modifier = Modifier.padding(padding).padding(16.dp)
            )
        }
    }

    tappedPin?.let { pin ->
        NetPickerDialog(
            existingNets = nets,
            onDismiss = { tappedPin = null },
            onSelectExisting = { net ->
                viewModel.assignExisting(pin.id, net)
                tappedPin = null
            },
            onCreateNew = { name, netType, color ->
                viewModel.assignNew(pin.id, name, netType, color)
                tappedPin = null
            },
            onClearAssignment = {
                viewModel.clear(pin.id)
                tappedPin = null
            }
        )
    }
}

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/editor/PinGridEditorScreen.kt"

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/newconnector/NewConnectorScreen.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/newconnector/NewConnectorScreen.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.ui.screens.newconnector

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.timlorne.wiringpro.data.repository.WiringRepository
import kotlinx.coroutines.launch

class NewConnectorViewModel(
    private val repository: WiringRepository,
    private val projectId: String
) : ViewModel() {
    fun createConnector(label: String, rows: List<Int>, onCreated: (String) -> Unit) {
        viewModelScope.launch {
            val id = repository.createConnector(projectId, label, rows)
            onCreated(id)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NewConnectorScreen(
    viewModel: NewConnectorViewModel,
    onConnectorCreated: (String) -> Unit,
    onBack: () -> Unit
) {
    var label by remember { mutableStateOf("") }
    val rowCounts = remember { mutableStateListOf(6) }

    Scaffold(topBar = { TopAppBar(title = { Text("New connector") }) }) { padding ->
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(padding)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            OutlinedTextField(
                value = label,
                onValueChange = { label = it },
                label = { Text("Connector label") },
                placeholder = { Text("e.g. Main 24-pin, Throttle 6-pin") },
                modifier = Modifier.fillMaxWidth()
            )

            Text("Rows (top to bottom) — pins per row")
            LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(rowCounts.size) { i ->
                    Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                        Text("Row ${i + 1}:", modifier = Modifier.padding(end = 8.dp))
                        OutlinedTextField(
                            value = rowCounts[i].toString(),
                            onValueChange = { value ->
                                value.toIntOrNull()?.let { rowCounts[i] = it.coerceAtLeast(1) }
                            },
                            modifier = Modifier.padding(end = 8.dp)
                        )
                        IconButton(onClick = { if (rowCounts.size > 1) rowCounts.removeAt(i) }) {
                            Text("✕")
                        }
                    }
                }
            }

            Row {
                Button(onClick = { rowCounts.add(rowCounts.lastOrNull() ?: 6) }) {
                    Text("Add row")
                }
            }

            val totalPins = rowCounts.sum()
            Text("Total pins: $totalPins")

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = onBack) { Text("Cancel") }
                Button(
                    enabled = label.isNotBlank() && rowCounts.isNotEmpty(),
                    onClick = {
                        viewModel.createConnector(label.trim(), rowCounts.toList(), onConnectorCreated)
                    }
                ) { Text("Create") }
            }
        }
    }
}

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/newconnector/NewConnectorScreen.kt"

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/ui/components/NetPickerDialog.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/ui/components/NetPickerDialog.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Divider
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.timlorne.wiringpro.data.db.NetEntity
import com.timlorne.wiringpro.data.model.StandardNetTypes

/**
 * Pin was tapped -> pick what it's wired to. Two sources of options:
 * existing nets already used in this project (so a shared ground reuses the
 * same net instead of creating a duplicate), and the standard type list for
 * starting a brand new net, with a free-text fallback for anything custom.
 */
@Composable
fun NetPickerDialog(
    existingNets: List<NetEntity>,
    onDismiss: () -> Unit,
    onSelectExisting: (NetEntity) -> Unit,
    onCreateNew: (name: String, netType: String, color: String?) -> Unit,
    onClearAssignment: () -> Unit
) {
    var customName by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Assign pin to a net") },
        text = {
            LazyColumn(modifier = Modifier.fillMaxWidth()) {
                if (existingNets.isNotEmpty()) {
                    item { Text("Already used in this project", style = androidx.compose.material3.MaterialTheme.typography.labelMedium) }
                    items(existingNets) { net ->
                        Text(
                            text = net.name,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 8.dp)
                                .clickableCompat { onSelectExisting(net) }
                        )
                    }
                    item { Divider(modifier = Modifier.padding(vertical = 8.dp)) }
                }

                item { Text("Standard signal types", style = androidx.compose.material3.MaterialTheme.typography.labelMedium) }
                items(StandardNetTypes.ALL.filter { it.type != "CUSTOM" }) { standard ->
                    Text(
                        text = standard.label,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 8.dp)
                            .clickableCompat { onCreateNew(standard.label, standard.type, standard.defaultColor) }
                    )
                }

                item { Divider(modifier = Modifier.padding(vertical = 8.dp)) }
                item {
                    Column {
                        Text("Custom", style = androidx.compose.material3.MaterialTheme.typography.labelMedium)
                        OutlinedTextField(
                            value = customName,
                            onValueChange = { customName = it },
                            placeholder = { Text("e.g. Fan relay trigger") },
                            modifier = Modifier.fillMaxWidth().padding(top = 4.dp)
                        )
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                if (customName.isNotBlank()) onCreateNew(customName.trim(), "CUSTOM", null)
            }) { Text("Add custom net") }
        },
        dismissButton = {
            Column(horizontalAlignment = androidx.compose.ui.Alignment.End) {
                TextButton(onClick = onClearAssignment) { Text("Clear assignment") }
                TextButton(onClick = onDismiss) { Text("Cancel") }
            }
        }
    )
}

private fun Modifier.clickableCompat(onClick: () -> Unit): Modifier =
    this.clickable(onClick = onClick)

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/ui/components/NetPickerDialog.kt"

mkdir -p "$(dirname "android-app/app/build.gradle.kts")"
cat > android-app/app/build.gradle.kts << 'KOTLIN_EOF'
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
}

dependencies {
    implementation("androidx.compose.ui:ui:1.6.0")
    implementation("androidx.compose.material3:material3:1.2.0")
    implementation("androidx.compose.material:material-icons-extended:1.6.0")
    implementation("androidx.activity:activity-compose:1.8.0")
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

KOTLIN_EOF
echo "Wrote android-app/app/build.gradle.kts"

echo ""
echo "Done. Sync Gradle (elephant icon) in Android Studio, then Run."
echo "New flow: app opens on a Connectors list -> tap + to add a connector -> tap any"
echo "existing connector in the list to reopen its pin editor."
