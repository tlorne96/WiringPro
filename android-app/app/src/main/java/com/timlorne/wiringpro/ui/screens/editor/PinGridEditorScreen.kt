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
import com.timlorne.wiringpro.data.db.PinEntity
import com.timlorne.wiringpro.data.repository.NetWithAssignments
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

    val netsWithAssignments = repository.observeNetsWithAssignments(projectId)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    fun assignExisting(pinId: String, net: NetWithAssignments) {
        viewModelScope.launch { repository.assignPinToNet(pinId, net.net.id) }
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
    val netsWithAssignments by viewModel.netsWithAssignments.collectAsState()
    var tappedPin by remember { mutableStateOf<PinEntity?>(null) }

    Scaffold(topBar = { TopAppBar(title = { Text(connectorWithPins?.connector?.label ?: "Connector") }) }) { padding ->
        val cwp = connectorWithPins
        if (cwp == null) {
            Text("Loading…", modifier = Modifier.padding(padding).padding(16.dp))
        } else {
            PinGrid(
                connector = cwp.connector,
                pins = cwp.pins,
                nets = netsWithAssignments.map { it.net },
                onPinClick = { pin -> tappedPin = pin },
                modifier = Modifier.padding(padding).padding(16.dp)
            )
        }
    }

    tappedPin?.let { pin ->
        NetPickerDialog(
            existingNets = netsWithAssignments,
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

