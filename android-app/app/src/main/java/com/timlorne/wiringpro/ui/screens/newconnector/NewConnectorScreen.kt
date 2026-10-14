package com.timlorne.wiringpro.ui.screens.newconnector

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.IconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.timlorne.wiringpro.data.repository.WiringRepository
import com.timlorne.wiringpro.data.model.BuiltinParts
import com.timlorne.wiringpro.data.model.PartTemplate
import com.timlorne.wiringpro.data.model.PlugFaceStyle
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

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

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("New connector") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Filled.ArrowBack, contentDescription = "Back to connectors")
                    }
                }
            )
        }
    ) { padding ->
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
                        PartTemplateOption(part) {
                            selectedPart = part
                            label = part.connectorLabel
                            rowCounts.clear()
                            part.rows.forEach { row -> rowCounts.add(row.toString()) }
                            showPartPicker = false
                        }
                    }
                    item { Text("Controller pinouts") }
                    items(BuiltinParts.ALL.filter { it.manufacturer != "Generic" }, key = { it.id }) { part ->
                        PartTemplateOption(part) {
                            selectedPart = part
                            label = part.connectorLabel
                            rowCounts.clear()
                            part.rows.forEach { row -> rowCounts.add(row.toString()) }
                            showPartPicker = false
                        }
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

@Composable
private fun PartTemplateOption(part: PartTemplate, onSelect: () -> Unit) {
    TextButton(onClick = onSelect, modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            ConnectorPlugDiagram(part, compact = true)
            Column {
                Text(part.name, style = MaterialTheme.typography.bodyMedium)
                part.partNumber?.let { partNumber ->
                    Text(
                        partNumber,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Text(
                    "${part.pins.size} pins - rows ${part.rows.joinToString(" / ")}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    part.pins.take(3).joinToString(", ") { it.name },
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

@Composable
private fun ConnectorPlugDiagram(part: PartTemplate, compact: Boolean) {
    if (part.faceStyle == PlugFaceStyle.CIRCULAR) {
        val faceSize = if (compact) 72.dp else 220.dp
        val pinSize = if (compact) 9.dp else 20.dp
        val center = faceSize / 2f
        val radius = faceSize * 0.32f
        Box(
            modifier = Modifier
                .size(faceSize)
                .background(Color(0xFF343B40), CircleShape)
                .border(1.dp, Color(0xFF8A969D), CircleShape)
        ) {
            part.pins.forEachIndexed { index, _ ->
                val angle = -PI / 2.0 + 2.0 * PI * index / part.pins.size
                Box(
                    modifier = Modifier
                        .offset(
                            x = center - pinSize / 2f + radius * cos(angle).toFloat(),
                            y = center - pinSize / 2f + radius * sin(angle).toFloat()
                        )
                        .size(pinSize)
                        .background(Color(0xFFD3A44D), CircleShape)
                        .border(1.dp, Color(0xFFFFD982), CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        (index + 1).toString(),
                        color = Color(0xFF262626),
                        fontSize = if (compact) 4.sp else 8.sp
                    )
                }
            }
        }
        return
    }

    val pinSize = if (compact) 10.dp else 24.dp
    val pinGap = if (compact) 2.dp else 4.dp
    val shellColor = Color(0xFF343B40)
    var pinIndex = 0

    Column(
        modifier = Modifier
            .width(if (compact) 124.dp else 300.dp)
            .background(shellColor, RoundedCornerShape(8.dp))
            .border(1.dp, Color(0xFF8A969D), RoundedCornerShape(8.dp))
            .padding(horizontal = 6.dp, vertical = if (compact) 6.dp else 10.dp),
        verticalArrangement = Arrangement.spacedBy(if (compact) 3.dp else 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        if (!compact) {
            Text("PLUG FACE", color = Color.White, fontSize = 9.sp)
        }
        part.rows.forEach { rowCount ->
            Row(horizontalArrangement = Arrangement.spacedBy(pinGap)) {
                repeat(rowCount) {
                    pinIndex++
                    Box(
                        modifier = Modifier
                            .size(pinSize)
                            .background(Color(0xFFD3A44D), CircleShape)
                            .border(1.dp, Color(0xFFFFD982), CircleShape),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            pinIndex.toString(),
                            color = Color(0xFF262626),
                            fontSize = if (compact) 5.sp else 9.sp
                        )
                    }
                }
            }
        }
    }
}

