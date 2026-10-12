package com.timlorne.wiringpro.ui.components

import androidx.compose.foundation.clickable
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

/**
 * Shown when two pins with no existing net are tapped together on the loom
 * canvas — they need a name before they can be wired. Deliberately simpler
 * than NetPickerDialog: no "existing nets in project" browsing here, since
 * on the canvas you'd normally just tap the pin that already has the name
 * you want rather than typing it fresh.
 */
@Composable
fun NameNetDialog(
    onDismiss: () -> Unit,
    onConfirm: (name: String, netType: String, color: String?) -> Unit
) {
    var customName by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Name this connection") },
        text = {
            LazyColumn {
                item { Text("Standard signal types", style = MaterialTheme.typography.labelMedium) }
                items(StandardNetTypes.ALL.filter { it.type != "CUSTOM" }) { standard ->
                    Text(
                        text = standard.label,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 8.dp)
                            .clickable { onConfirm(standard.label, standard.type, standard.defaultColor) }
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
            TextButton(
                enabled = customName.isNotBlank(),
                onClick = { onConfirm(customName.trim(), "CUSTOM", null) }
            ) { Text("Connect") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        }
    )
}

