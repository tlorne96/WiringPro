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
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
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

/**
 * Asks how many rows a connector has and how many pins are in each row —
 * the camera-based version is deferred, this is the whole input flow for now.
 *
 * Row-count fields select their whole value on focus, so tapping straight
 * into typing a new number replaces it instead of requiring a manual
 * select-all/delete first.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NewConnectorScreen(
    viewModel: NewConnectorViewModel,
    onConnectorCreated: (String) -> Unit,
    onBack: () -> Unit
) {
    var label by remember { mutableStateOf("") }
    val rowCounts = remember { mutableStateListOf(TextFieldValue("6")) }

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
                            value = rowCounts[i],
                            onValueChange = { new -> rowCounts[i] = new },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                            modifier = Modifier
                                .padding(end = 8.dp)
                                .onFocusChanged { focusState ->
                                    if (focusState.isFocused) {
                                        rowCounts[i] = rowCounts[i].copy(
                                            selection = TextRange(0, rowCounts[i].text.length)
                                        )
                                    }
                                }
                        )
                        IconButton(onClick = { if (rowCounts.size > 1) rowCounts.removeAt(i) }) {
                            Text("✕")
                        }
                    }
                }
            }

            Row {
                Button(onClick = {
                    rowCounts.add(TextFieldValue(rowCounts.lastOrNull()?.text ?: "6"))
                }) {
                    Text("Add row")
                }
            }

            val totalPins = rowCounts.sumOf { it.text.toIntOrNull() ?: 0 }
            Text("Total pins: $totalPins")

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = onBack) { Text("Cancel") }
                Button(
                    enabled = label.isNotBlank() && rowCounts.isNotEmpty(),
                    onClick = {
                        val rows = rowCounts.map { (it.text.toIntOrNull() ?: 1).coerceAtLeast(1) }
                        viewModel.createConnector(label.trim(), rows, onConnectorCreated)
                    }
                ) { Text("Create") }
            }
        }
    }
}

