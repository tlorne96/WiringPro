#!/bin/bash
# WiringPro: adds a Projects home screen (create/open harnesses — Room
# autosaves, so opening a project from this list IS the 'load a file'
# step) and makes the net picker show WHERE each existing net already
# connects (e.g. 'Main pin 1') instead of just its bare name.
# Run from inside the 'wiringpro' folder (the one containing android-app/).
set -e

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/data/db/Database.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/data/db/Database.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.data.db

import android.content.Context
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Delete
import androidx.room.Embedded
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Relation
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverter
import androidx.room.TypeConverters
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

// ---------------------------------------------------------------------
// Relations — convenience shapes for the UI, built on top of the plain
// entities above. Keep these separate from Entities.kt: entities are what
// Room persists, relations are what screens actually want to observe.
// ---------------------------------------------------------------------

data class ConnectorWithPins(
    @Embedded val connector: ConnectorEntity,
    @Relation(parentColumn = "id", entityColumn = "connectorId")
    val pins: List<PinEntity>
)

// Plain query result (not an entity) — one row per assigned pin, joined
// against its connector so the net picker can show "Main pin 1" instead of
// a bare pin id. Used to build the "already used in this project" list.
data class PinAssignmentRow(
    val connectorLabel: String,
    val pinIndex: Int,
    val netId: String
)

// ---------------------------------------------------------------------
// Converters
// ---------------------------------------------------------------------

class Converters {
    @TypeConverter
    fun fromRows(rows: List<Int>): String = rows.joinToString(",")

    @TypeConverter
    fun toRows(data: String): List<Int> =
        if (data.isBlank()) emptyList() else data.split(",").map { it.trim().toInt() }
}

// ---------------------------------------------------------------------
// DAOs
// ---------------------------------------------------------------------

@Dao
interface ProjectDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(project: ProjectEntity)

    @Query("SELECT * FROM projects WHERE id = :id")
    suspend fun getById(id: String): ProjectEntity?

    @Query("SELECT * FROM projects ORDER BY updatedAt DESC")
    fun observeAll(): Flow<List<ProjectEntity>>
}

@Dao
interface ConnectorDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(connector: ConnectorEntity)

    @Delete
    suspend fun delete(connector: ConnectorEntity)

    @Query("SELECT * FROM connectors WHERE projectId = :projectId")
    fun observeForProject(projectId: String): Flow<List<ConnectorEntity>>

    @androidx.room.Transaction
    @Query("SELECT * FROM connectors WHERE projectId = :projectId")
    fun observeWithPinsForProject(projectId: String): Flow<List<ConnectorWithPins>>

    @androidx.room.Transaction
    @Query("SELECT * FROM connectors WHERE id = :connectorId")
    fun observeWithPins(connectorId: String): Flow<ConnectorWithPins?>
}

@Dao
interface PinDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(pins: List<PinEntity>)

    @Query("UPDATE pins SET netId = :netId WHERE id = :pinId")
    suspend fun assignNet(pinId: String, netId: String?)

    @Query("UPDATE pins SET label = :label WHERE id = :pinId")
    suspend fun setLabel(pinId: String, label: String?)

    @Query(
        """
        SELECT c.label AS connectorLabel, p.`index` AS pinIndex, p.netId AS netId
        FROM pins p
        INNER JOIN connectors c ON p.connectorId = c.id
        WHERE c.projectId = :projectId AND p.netId IS NOT NULL
        """
    )
    fun observeAssignmentsForProject(projectId: String): Flow<List<PinAssignmentRow>>
}

@Dao
interface NetDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(net: NetEntity)

    @Query("SELECT * FROM nets WHERE projectId = :projectId")
    fun observeForProject(projectId: String): Flow<List<NetEntity>>

    @Query("SELECT * FROM nets WHERE projectId = :projectId AND name = :name LIMIT 1")
    suspend fun findByName(projectId: String, name: String): NetEntity?
}

// ---------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------

@Database(
    entities = [ProjectEntity::class, ConnectorEntity::class, PinEntity::class, NetEntity::class],
    version = 1,
    exportSchema = false
)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun projectDao(): ProjectDao
    abstract fun connectorDao(): ConnectorDao
    abstract fun pinDao(): PinDao
    abstract fun netDao(): NetDao

    companion object {
        @Volatile private var instance: AppDatabase? = null

        fun getInstance(context: Context): AppDatabase =
            instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "wiringpro.db"
                ).build().also { instance = it }
            }
    }
}

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/data/db/Database.kt"

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/data/repository/WiringRepository.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/data/repository/WiringRepository.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.data.repository

import com.timlorne.wiringpro.data.db.AppDatabase
import com.timlorne.wiringpro.data.db.ConnectorEntity
import com.timlorne.wiringpro.data.db.ConnectorWithPins
import com.timlorne.wiringpro.data.db.NetEntity
import com.timlorne.wiringpro.data.db.PinEntity
import com.timlorne.wiringpro.data.db.ProjectEntity
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import java.util.UUID

// A net plus a human-readable list of where it's currently connected, e.g.
// ["Main pin 1", "Throttle pin 5"] — this is what lets the net picker show
// what a net already touches instead of just its bare name.
data class NetWithAssignments(val net: NetEntity, val assignmentLabels: List<String>)

class WiringRepository(private val db: AppDatabase) {

    // -------------------------------------------------------------
    // Projects
    // -------------------------------------------------------------

    fun observeProjects(): Flow<List<ProjectEntity>> = db.projectDao().observeAll()

    suspend fun createProject(name: String): String {
        val id = UUID.randomUUID().toString()
        val now = System.currentTimeMillis()
        db.projectDao().upsert(
            ProjectEntity(id = id, name = name, vehicle = null, notes = null, createdAt = now, updatedAt = now)
        )
        return id
    }

    // -------------------------------------------------------------
    // Connectors + pins
    // -------------------------------------------------------------

    /**
     * Creates a connector and generates its pins.
     *
     * Numbering rule (per project decision): pins are indexed left-to-right,
     * then top-to-bottom — reading like a book. Given rows = [8, 8, 8] for a
     * 24-pin connector, pin 1 is row 0/col 0, pin 8 is row 0/col 7, pin 9 is
     * row 1/col 0, and so on. This is the one place that numbering logic
     * lives — don't duplicate it in the UI layer.
     */
    suspend fun createConnector(projectId: String, label: String, rows: List<Int>): String {
        val connectorId = UUID.randomUUID().toString()
        db.connectorDao().upsert(
            ConnectorEntity(
                id = connectorId,
                projectId = projectId,
                label = label,
                rows = rows,
                partRef = null
            )
        )

        val pins = mutableListOf<PinEntity>()
        var pinIndex = 1
        for (row in rows.indices) {
            for (col in 0 until rows[row]) {
                pins.add(
                    PinEntity(
                        id = UUID.randomUUID().toString(),
                        connectorId = connectorId,
                        index = pinIndex,
                        row = row,
                        col = col,
                        netId = null,
                        label = null
                    )
                )
                pinIndex++
            }
        }
        db.pinDao().upsertAll(pins)
        return connectorId
    }

    fun observeConnectorsWithPins(projectId: String): Flow<List<ConnectorWithPins>> =
        db.connectorDao().observeWithPinsForProject(projectId)

    fun observeConnectorWithPins(connectorId: String): Flow<ConnectorWithPins?> =
        db.connectorDao().observeWithPins(connectorId)

    // -------------------------------------------------------------
    // Nets
    // -------------------------------------------------------------

    fun observeNets(projectId: String): Flow<List<NetEntity>> =
        db.netDao().observeForProject(projectId)

    /**
     * Nets in the project alongside where each one is currently connected —
     * "Main pin 1", "Throttle pin 5", etc. Powers the net picker's
     * "already used in this project" list so assigning a pin shows what
     * you're actually about to join it to, not just a bare net name.
     */
    fun observeNetsWithAssignments(projectId: String): Flow<List<NetWithAssignments>> =
        combine(observeNets(projectId), db.pinDao().observeAssignmentsForProject(projectId)) { nets, rows ->
            val byNet = rows.groupBy { it.netId }
            nets.map { net ->
                val labels = byNet[net.id]?.map { "${it.connectorLabel} pin ${it.pinIndex}" } ?: emptyList()
                NetWithAssignments(net, labels)
            }
        }

    /**
     * Finds an existing net with this name in the project, or creates one.
     * This is what makes "ground fans out to five places" work: assigning
     * the same net name to five different pins reuses one NetEntity instead
     * of creating five disconnected ones.
     */
    suspend fun getOrCreateNet(projectId: String, name: String, netType: String, color: String?): String {
        db.netDao().findByName(projectId, name)?.let { return it.id }
        val id = UUID.randomUUID().toString()
        db.netDao().upsert(NetEntity(id = id, projectId = projectId, name = name, netType = netType, color = color))
        return id
    }

    suspend fun assignPinToNet(pinId: String, netId: String?) {
        db.pinDao().assignNet(pinId, netId)
    }

    suspend fun clearPinNet(pinId: String) {
        db.pinDao().assignNet(pinId, null)
    }
}

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/data/repository/WiringRepository.kt"

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

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/ui/components/NetPickerDialog.kt"

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

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/editor/PinGridEditorScreen.kt"

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/projectlist/ProjectListScreen.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/projectlist/ProjectListScreen.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.ui.screens.projectlist

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import com.timlorne.wiringpro.data.repository.WiringRepository
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class ProjectListViewModel(private val repository: WiringRepository) : ViewModel() {
    val projects = repository.observeProjects()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    fun createProject(name: String, onCreated: (String) -> Unit) {
        viewModelScope.launch {
            val id = repository.createProject(name)
            onCreated(id)
        }
    }
}

/**
 * Home screen — every harness/project you're working on, in one list.
 * There's no separate "save" here: Room writes on every change, so opening
 * a project from this list is the whole "switch harness" workflow.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProjectListScreen(
    viewModel: ProjectListViewModel,
    onOpenProject: (String) -> Unit
) {
    val projects by viewModel.projects.collectAsState()
    var showCreateDialog by remember { mutableStateOf(false) }

    Scaffold(
        topBar = { TopAppBar(title = { Text("Projects") }) },
        floatingActionButton = {
            FloatingActionButton(onClick = { showCreateDialog = true }) {
                Icon(Icons.Filled.Add, contentDescription = "New project")
            }
        }
    ) { padding ->
        if (projects.isEmpty()) {
            Text(
                "No projects yet — tap + to start one.",
                modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp)
            )
        } else {
            LazyColumn(modifier = Modifier.fillMaxSize().padding(padding)) {
                items(projects) { project ->
                    Text(
                        text = project.name,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onOpenProject(project.id) }
                            .padding(16.dp)
                    )
                }
            }
        }
    }

    if (showCreateDialog) {
        var name by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { showCreateDialog = false },
            title = { Text("New project") },
            text = {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    placeholder = { Text("e.g. Surron Light Bee X") },
                    modifier = Modifier.fillMaxWidth().padding(top = 4.dp)
                )
            },
            confirmButton = {
                TextButton(
                    enabled = name.isNotBlank(),
                    onClick = {
                        viewModel.createProject(name.trim()) { id ->
                            showCreateDialog = false
                            onOpenProject(id)
                        }
                    }
                ) { Text("Create") }
            },
            dismissButton = {
                TextButton(onClick = { showCreateDialog = false }) { Text("Cancel") }
            }
        )
    }
}

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/projectlist/ProjectListScreen.kt"

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
import com.timlorne.wiringpro.ui.screens.projectlist.ProjectListScreen
import com.timlorne.wiringpro.ui.screens.projectlist.ProjectListViewModel

private class SimpleFactory(private val create: () -> ViewModel) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T = create() as T
}

/**
 * Route shape: project_list -> connector_list/{projectId} -> either
 * new_connector/{projectId} or editor/{projectId}/{connectorId}. projectId
 * rides in the route (not a fixed constructor arg) so the back stack can
 * hold more than one project and switching harnesses is just navigation.
 */
@Composable
fun WiringProNavHost(repository: WiringRepository) {
    val navController: NavHostController = rememberNavController()

    NavHost(navController = navController, startDestination = "project_list") {
        composable("project_list") {
            val vm: ProjectListViewModel = viewModel(
                factory = SimpleFactory { ProjectListViewModel(repository) }
            )
            ProjectListScreen(
                viewModel = vm,
                onOpenProject = { projectId -> navController.navigate("connector_list/$projectId") }
            )
        }

        composable(
            route = "connector_list/{projectId}",
            arguments = listOf(navArgument("projectId") { type = NavType.StringType })
        ) { backStackEntry ->
            val projectId = backStackEntry.arguments?.getString("projectId")!!
            val vm: ConnectorListViewModel = viewModel(
                factory = SimpleFactory { ConnectorListViewModel(repository, projectId) }
            )
            ConnectorListScreen(
                viewModel = vm,
                onAddConnector = { navController.navigate("new_connector/$projectId") },
                onOpenConnector = { connectorId -> navController.navigate("editor/$projectId/$connectorId") }
            )
        }

        composable(
            route = "new_connector/{projectId}",
            arguments = listOf(navArgument("projectId") { type = NavType.StringType })
        ) { backStackEntry ->
            val projectId = backStackEntry.arguments?.getString("projectId")!!
            val vm: NewConnectorViewModel = viewModel(
                factory = SimpleFactory { NewConnectorViewModel(repository, projectId) }
            )
            NewConnectorScreen(
                viewModel = vm,
                onConnectorCreated = { connectorId ->
                    navController.navigate("editor/$projectId/$connectorId") {
                        popUpTo("connector_list/$projectId")
                    }
                },
                onBack = { navController.popBackStack() }
            )
        }

        composable(
            route = "editor/{projectId}/{connectorId}",
            arguments = listOf(
                navArgument("projectId") { type = NavType.StringType },
                navArgument("connectorId") { type = NavType.StringType }
            )
        ) { backStackEntry ->
            val projectId = backStackEntry.arguments?.getString("projectId")!!
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

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/MainActivity.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/MainActivity.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import com.timlorne.wiringpro.ui.nav.WiringProNavHost

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val repository = (application as WiringProApplication).repository

        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    WiringProNavHost(repository = repository)
                }
            }
        }
    }
}

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/MainActivity.kt"

echo ""
echo "Done. Sync Gradle (elephant icon) in Android Studio, then Run."
echo "New flow: app now opens on a Projects list -> tap + to create/open a harness"
echo "-> its Connectors list -> pin editor. Any pre-existing default-project data"
echo "from before this change will still show up in the Projects list, named"
echo "\"Untitled project\"."
