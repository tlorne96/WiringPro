package com.timlorne.wiringpro.ui.screens.newconnector

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.timlorne.wiringpro.data.repository.WiringRepository
import com.timlorne.wiringpro.data.model.BuiltinParts
import com.timlorne.wiringpro.data.model.PartTemplate
import kotlinx.coroutines.launch

class NewConnectorViewModel(
    private val repository: WiringRepository,
    private val projectId: String
) : ViewModel() {
    fun createConnector(label: String, rows: List<Int>, part: PartTemplate?, onCreated: (String) -> Unit) {
        viewModelScope.launch {
            val id = repository.createConnector(
                projectId = projectId,
                label = label,
                rows = rows,
                partRef = part?.id,
                pinLabels = part?.pins?.map { it.note }.orEmpty()
            )
            onCreated(id)
        }
    }
}

/**
 * Asks how many rows a connector has and how many pins are in each row —
 * the camera-based version is deferred, this is the whole input flow for now.
 *
 * Row-count fields keep ordinary text-field cursor and deletion behavior.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NewConnectorScreen(
    viewModel: NewConnectorViewModel,
    onConnectorCreated: (String) -> Unit,
    onBack: () -> Unit
) {
    var label by remember { mutableStateOf("") }
    var selectedPart by remember { mutableStateOf<PartTemplate?>(null) }
    var showPartPicker by remember { mutableStateOf(false) }
    val rowCounts = remember { mutableStateListOf("6") }

    Scaffold(topBar = { TopAppBar(title = { Text("New connector") }) }) { padding ->
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(padding)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Button(onClick = { showPartPicker = true }) {
                Text(selectedPart?.name ?: "Choose a connector template")
            }

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
                            value = rowCounts[i],
                            onValueChange = { new -> rowCounts[i] = new.filter(Char::isDigit) },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                            modifier = Modifier.padding(end = 8.dp)
                        )
                        IconButton(onClick = { if (rowCounts.size > 1) rowCounts.removeAt(i) }) {
                            Text("✕")
                        }
                    }
                }
            }

            Row {
                Button(onClick = {
                    rowCounts.add(rowCounts.lastOrNull() ?: "6")
                }) {
                    Text("Add row")
                }
            }

            val totalPins = rowCounts.sumOf { it.toIntOrNull() ?: 0 }
            Text("Total pins: $totalPins")

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = onBack) { Text("Cancel") }
                Button(
                    enabled = label.isNotBlank() && rowCounts.isNotEmpty() &&
                        rowCounts.all { (it.toIntOrNull() ?: 0) > 0 },
                    onClick = {
                        val rows = rowCounts.map { (it.toIntOrNull() ?: 1).coerceAtLeast(1) }
                        val part = selectedPart?.takeIf { it.rows == rows }
                        viewModel.createConnector(label.trim(), rows, part, onConnectorCreated)
                    }
                ) { Text("Create") }
            }
        }
    }

    if (showPartPicker) {
        AlertDialog(
            onDismissRequest = { showPartPicker = false },
            title = { Text("Parts list") },
            text = {
                LazyColumn {
                    item { Text("Common connectors") }
                    items(BuiltinParts.ALL.filter { it.manufacturer == "Generic" }, key = { it.id }) { part ->
                        TextButton(
                            onClick = {
                                selectedPart = part
                                label = part.connectorLabel
                                rowCounts.clear()
                                part.rows.forEach { rowCounts.add(row.toString()) }
                                showPartPicker = false
                            },
                            modifier = Modifier.fillMaxWidth()
                        ) { Text(part.name) }
                    }
                    item { Text("Controller pinouts") }
                    items(BuiltinParts.ALL.filter { it.manufacturer != "Generic" }, key = { it.id }) { part ->
                        TextButton(
                            onClick = {
                                selectedPart = part
                                label = part.connectorLabel
                                rowCounts.clear()
                                part.rows.forEach { rowCounts.add(row.toString()) }
                                showPartPicker = false
                            },
                            modifier = Modifier.fillMaxWidth()
                        ) { Text(part.name) }
                    }
                    item {
                        TextButton(
                            onClick = {
                                selectedPart = null
                                label = ""
                                rowCounts.clear()
                                rowCounts.add("6")
                                showPartPicker = false
                            },
                            modifier = Modifier.fillMaxWidth()
                        ) { Text("Create a blank connector") }
                    }
                }
            },
            confirmButton = { TextButton(onClick = { showPartPicker = false }) { Text("Close") } }
        )
    }
}

