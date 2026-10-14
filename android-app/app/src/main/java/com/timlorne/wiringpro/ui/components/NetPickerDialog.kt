package com.timlorne.wiringpro.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Divider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.timlorne.wiringpro.data.db.NetEntity
import com.timlorne.wiringpro.data.model.StandardNetTypes
import com.timlorne.wiringpro.data.repository.NetWithAssignments

private fun suggestedNetTypeForPin(pinLabel: String?): String? {
    val label = pinLabel
        ?.substringBefore('|')
        ?.filterNot { it.isWhitespace() || it == '+' || it == '/' }
        ?.uppercase()
        ?: return null
    return when (label) {
        "PWMIN" -> "PWM_INPUT"
        "MOTORTEMP", "MOTORTEMPERATURE" -> "MOTOR_TEMP_SENSOR"
        "5V" -> "5V_SUPPLY"
        "12V", "12VOUTPUT", "OUTPUT12V" -> "12V_SUPPLY"
        "36V", "BATTERYPOS", "BATTERYPOSITIVE", "B" -> "36V_SUPPLY"
        "GND", "GROUND", "0V", "BATTERYNEG", "BATTERYNEGATIVE", "B-" -> "GND"
        "CAN2BUSHIGH" -> "CAN2_H"
        "CAN2BUSLOW" -> "CAN2_L"
        "CANHIGH", "CANBUSHIGH" -> "CAN_H"
        "CANLOW", "CANBUSLOW" -> "CAN_L"
        "IGNITION", "IGNITIONSIGNAL", "KEYLOCKIGNITION" -> "IGNITION_ON"
        "SENSOR1", "THROTTLE1" -> "THROTTLE_SIGNAL_A"
        "SENSOR2", "THROTTLE2" -> "THROTTLE_SIGNAL_B"
        "ANALOGINPUTREGEN", "ANALOGUEINPUTREGEN" -> "REGEN_BRAKE_SIGNAL"
        "HALLA" -> "MOTOR_HALL_A"
        "HALLB" -> "MOTOR_HALL_B"
        "HALLC", "HALLZ" -> "MOTOR_HALL_C"
        else -> null
    }
}

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
    selectedNet: NetEntity?,
    pinLabel: String?,
    smartConnectMatchingLabels: Boolean,
    onSmartConnectMatchingLabelsChange: (Boolean) -> Unit,
    onDismiss: () -> Unit,
    onSelectExisting: (NetWithAssignments) -> Unit,
    onUpdateNetColors: (netId: String, color: String, stripeColor: String?) -> Unit,
    onCreateNew: (name: String, netType: String, color: String?) -> Unit,
    onClearAssignment: () -> Unit
) {
    var customName by remember { mutableStateOf("") }
    var editingColor by remember { mutableStateOf(false) }
    val standardTypes = StandardNetTypes.ALL.filter { it.type != "CUSTOM" }
    val suggestedStandardType = standardTypes.firstOrNull { it.type == suggestedNetTypeForPin(pinLabel) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Assign pin to a net") },
        text = {
            LazyColumn(modifier = Modifier.fillMaxWidth()) {
                if (!pinLabel.isNullOrBlank()) {
                    item {
                        Text(
                            pinLabel.replace(" | ", "\n"),
                            style = MaterialTheme.typography.bodySmall,
                            modifier = Modifier.padding(bottom = 8.dp)
                        )
                    }
                }
                item {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(
                            checked = smartConnectMatchingLabels,
                            onCheckedChange = onSmartConnectMatchingLabelsChange
                        )
                        Text("Smart-connect matching pin labels")
                    }
                }
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

                if (selectedNet != null) {
                    item {
                        TextButton(onClick = { editingColor = true }) {
                            Text("Change ${selectedNet.name} wire color")
                        }
                    }
                }

                item {
                    Text(
                        if (suggestedStandardType == null) "Standard signal types" else "Suggested for this pin",
                        style = MaterialTheme.typography.labelMedium
                    )
                }
                suggestedStandardType?.let { standard ->
                    item {
                        TextButton(
                            onClick = { onCreateNew(standard.label, standard.type, standard.defaultColor) }
                        ) { Text(standard.label) }
                    }
                    item { Text("Other signal types", style = MaterialTheme.typography.labelMedium) }
                }
                items(standardTypes.filterNot { it.type == suggestedStandardType?.type }) { standard ->
                    Text(
                        text = standard.label,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 8.dp)
                            .clickableCompat {
                                onCreateNew(standard.label, standard.type, standard.defaultColor)
                            }
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
                if (customName.isNotBlank()) {
                    onCreateNew(customName.trim(), "CUSTOM", null)
                }
            }) { Text("Add custom net") }
        },
        dismissButton = {
            Column(horizontalAlignment = androidx.compose.ui.Alignment.End) {
                TextButton(onClick = onClearAssignment) { Text("Clear assignment") }
                TextButton(onClick = onDismiss) { Text("Cancel") }
            }
        }
    )

    if (editingColor && selectedNet != null) {
        NetColorDialog(
            net = selectedNet,
            onDismiss = { editingColor = false },
            onSave = { color, stripeColor ->
                onUpdateNetColors(selectedNet.id, color, stripeColor)
                editingColor = false
            }
        )
    }
}

@Composable
private fun NetColorDialog(
    net: NetEntity,
    onDismiss: () -> Unit,
    onSave: (color: String, stripeColor: String?) -> Unit
) {
    val colors = listOf(
        "#000000", "#FFFFFF", "#FF0000", "#00AEEF", "#008000", "#FFFF00",
        "#FFA500", "#800080", "#A0522D", "#808080", "#DC143C", "#1E90FF"
    )
    var colorHex by remember(net.id) { mutableStateOf(net.color ?: "#000000") }
    var stripeHex by remember(net.id) { mutableStateOf(net.stripeColor ?: "#FFFFFF") }
    var stripeEnabled by remember(net.id) { mutableStateOf(net.stripeColor != null) }
    var editingStripe by remember(net.id) { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Wire color: ${net.name}") },
        text = {
            Column {
                androidx.compose.foundation.layout.Row(verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(selected = !editingStripe, onClick = { editingStripe = false })
                    Text("Main color")
                    Checkbox(
                        checked = stripeEnabled,
                        onCheckedChange = { enabled ->
                            stripeEnabled = enabled
                            if (!enabled) editingStripe = false
                        }
                    )
                    Text("Stripe")
                }
                if (stripeEnabled) {
                    androidx.compose.foundation.layout.Row(verticalAlignment = Alignment.CenterVertically) {
                        RadioButton(selected = editingStripe, onClick = { editingStripe = true })
                        Text("Choose stripe color")
                    }
                }
                colors.chunked(6).forEach { rowColors ->
                    androidx.compose.foundation.layout.Row {
                        rowColors.forEach { colorHexOption ->
                            val color = runCatching { Color(android.graphics.Color.parseColor(colorHexOption)) }
                                .getOrDefault(Color.Gray)
                            androidx.compose.foundation.layout.Box(
                                modifier = Modifier
                                    .padding(4.dp)
                                    .size(36.dp)
                                    .background(color, androidx.compose.foundation.shape.CircleShape)
                                    .border(1.dp, MaterialTheme.colorScheme.outline, androidx.compose.foundation.shape.CircleShape)
                                    .clickable {
                                        if (editingStripe) stripeHex = colorHexOption else colorHex = colorHexOption
                                    }
                            )
                        }
                    }
                }
                OutlinedTextField(
                    value = colorHex,
                    onValueChange = { colorHex = it },
                    label = { Text("Main wire color") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp)
                )
                if (stripeEnabled) {
                    OutlinedTextField(
                        value = stripeHex,
                        onValueChange = { stripeHex = it },
                        label = { Text("Stripe color") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth().padding(top = 8.dp)
                    )
                }
            }
        },
        confirmButton = {
            TextButton(
                enabled = runCatching {
                    android.graphics.Color.parseColor(colorHex)
                    if (stripeEnabled) android.graphics.Color.parseColor(stripeHex)
                    true
                }.getOrDefault(false),
                onClick = { onSave(colorHex, stripeHex.takeIf { stripeEnabled }) }
            ) { Text("Save") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } }
    )
}

private fun Modifier.clickableCompat(onClick: () -> Unit): Modifier =
    this.clickable(onClick = onClick)

