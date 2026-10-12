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
import androidx.compose.material3.MaterialTheme
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
import com.timlorne.wiringpro.data.model.StandardNetTypes
import com.timlorne.wiringpro.data.repository.NetWithAssignments

/**
 * Pin was tapped -> pick what it's wired to. Three sources of options:
 * existing nets already used in this project — shown with WHERE they're
 * currently connected, so picking one is an informed choice, not a guess
 * from a bare name — the standard type list for starting a brand new net,
 * and a free-text fallback for anything custom.
 */
@Composable
fun NetPickerDialog(
    existingNets: List<NetWithAssignments>,
    onDismiss: () -> Unit,
    onSelectExisting: (NetWithAssignments) -> Unit,
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
                    item { Text("Already used in this project", style = MaterialTheme.typography.labelMedium) }
                    items(existingNets) { entry ->
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 8.dp)
                                .clickableCompat { onSelectExisting(entry) }
                        ) {
                            Text(entry.net.name, style = MaterialTheme.typography.bodyLarge)
                            val subtitle = if (entry.assignmentLabels.isEmpty()) {
                                "not connected yet"
                            } else {
                                entry.assignmentLabels.joinToString(", ")
                            }
                            Text(
                                subtitle,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                    item { Divider(modifier = Modifier.padding(vertical = 8.dp)) }
                }

                item { Text("Standard signal types", style = MaterialTheme.typography.labelMedium) }
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
                        Text("Custom", style = MaterialTheme.typography.labelMedium)
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

