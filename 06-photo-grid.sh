#!/bin/bash
# WiringPro: turns the Projects home screen into a photo grid — tap the
# camera icon on a tile to set/replace its photo (picked via the system
# photo picker, copied into app-private storage so it persists).
#
# WARNING: this adds a column to the projects table and there are no
# migrations written yet, so the local app database will be wiped on next
# launch (fallbackToDestructiveMigration). Any projects/connectors/pins you
# already created will be gone. Say so if you'd rather have a real
# migration written instead of running this.
#
# Run from inside the 'wiringpro' folder (the one containing android-app/).
set -e

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/data/db/Entities.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/data/db/Entities.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.data.db

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

// Mirrors shared/project-schema.json. rows is a List<Int> in Kotlin,
// stored as a comma-separated string via Converters — see Database.kt.

@Entity(tableName = "projects")
data class ProjectEntity(
    @PrimaryKey val id: String,
    val name: String,
    val vehicle: String?,
    val notes: String?,
    val createdAt: Long,
    val updatedAt: Long,
    val imagePath: String? = null  // absolute path to a copy of the picked photo in app-private storage
)

@Entity(
    tableName = "connectors",
    foreignKeys = [ForeignKey(
        entity = ProjectEntity::class,
        parentColumns = ["id"],
        childColumns = ["projectId"],
        onDelete = ForeignKey.CASCADE
    )],
    indices = [Index("projectId")]
)
data class ConnectorEntity(
    @PrimaryKey val id: String,
    val projectId: String,
    val label: String,
    val rows: List<Int>,       // pin count per physical row — supports irregular connectors
    val partRef: String?
)

@Entity(
    tableName = "nets",
    foreignKeys = [ForeignKey(
        entity = ProjectEntity::class,
        parentColumns = ["id"],
        childColumns = ["projectId"],
        onDelete = ForeignKey.CASCADE
    )],
    indices = [Index("projectId")]
)
data class NetEntity(
    @PrimaryKey val id: String,
    val projectId: String,
    val name: String,          // e.g. "GND", "Throttle A"
    val netType: String,       // one of StandardNetTypes, or "CUSTOM"
    val color: String?
)

@Entity(
    tableName = "pins",
    foreignKeys = [
        ForeignKey(
            entity = ConnectorEntity::class,
            parentColumns = ["id"],
            childColumns = ["connectorId"],
            onDelete = ForeignKey.CASCADE
        ),
        ForeignKey(
            entity = NetEntity::class,
            parentColumns = ["id"],
            childColumns = ["netId"],
            onDelete = ForeignKey.SET_NULL
        )
    ],
    indices = [Index("connectorId"), Index("netId")]
)
data class PinEntity(
    @PrimaryKey val id: String,
    val connectorId: String,
    val index: Int,             // 1-based, as printed on the connector
    val row: Int,                // 0-based
    val col: Int,                 // 0-based, position within that row
    val netId: String?,
    val label: String?
)

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/data/db/Entities.kt"

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

    @Query("UPDATE projects SET imagePath = :imagePath WHERE id = :id")
    suspend fun setImagePath(id: String, imagePath: String?)
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
                )
                    // No migrations written yet — this is a prototype-phase
                    // tradeoff, not an oversight. Once schema changes stop
                    // being frequent, replace this with real Migration
                    // objects so upgrades don't wipe local data.
                    .fallbackToDestructiveMigration()
                    .build().also { instance = it }
            }
    }
}

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/data/db/Database.kt"

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/data/repository/WiringRepository.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/data/repository/WiringRepository.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.data.repository

import android.content.Context
import android.net.Uri
import com.timlorne.wiringpro.data.db.AppDatabase
import com.timlorne.wiringpro.data.db.ConnectorEntity
import com.timlorne.wiringpro.data.db.ConnectorWithPins
import com.timlorne.wiringpro.data.db.NetEntity
import com.timlorne.wiringpro.data.db.PinEntity
import com.timlorne.wiringpro.data.db.ProjectEntity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.withContext
import java.io.File
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

    /**
     * Copies the picked photo into app-private storage (so it survives even
     * if the original is deleted from the gallery) and records the path.
     * One file per project, overwritten on re-pick.
     */
    suspend fun setProjectImage(projectId: String, uri: Uri, context: Context) {
        withContext(Dispatchers.IO) {
            val dir = File(context.filesDir, "project_images").apply { mkdirs() }
            val dest = File(dir, "$projectId.jpg")
            context.contentResolver.openInputStream(uri)?.use { input ->
                dest.outputStream().use { output -> input.copyTo(output) }
            }
            db.projectDao().setImagePath(projectId, dest.absolutePath)
        }
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

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/projectlist/ProjectListScreen.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/projectlist/ProjectListScreen.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.ui.screens.projectlist

import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.Image as ImageIcon
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import coil.compose.AsyncImage
import com.timlorne.wiringpro.data.db.ProjectEntity
import com.timlorne.wiringpro.data.repository.WiringRepository
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.io.File

class ProjectListViewModel(private val repository: WiringRepository) : ViewModel() {
    val projects = repository.observeProjects()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    fun createProject(name: String, onCreated: (String) -> Unit) {
        viewModelScope.launch {
            val id = repository.createProject(name)
            onCreated(id)
        }
    }

    fun setProjectImage(projectId: String, uri: Uri, context: Context) {
        viewModelScope.launch { repository.setProjectImage(projectId, uri, context) }
    }
}

/**
 * Home screen — a photo grid of every harness/project you're working on.
 * There's no separate "save" here: Room writes on every change, so tapping
 * a tile is the whole "switch harness" workflow. Tap the camera icon on a
 * tile to set or replace its photo.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProjectListScreen(
    viewModel: ProjectListViewModel,
    onOpenProject: (String) -> Unit
) {
    val projects by viewModel.projects.collectAsState()
    var showCreateDialog by remember { mutableStateOf(false) }
    var pendingImageProjectId by remember { mutableStateOf<String?>(null) }
    val context = LocalContext.current

    val photoPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickVisualMedia()
    ) { uri ->
        val projectId = pendingImageProjectId
        if (uri != null && projectId != null) {
            viewModel.setProjectImage(projectId, uri, context)
        }
        pendingImageProjectId = null
    }

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
            LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 160.dp),
                modifier = Modifier.fillMaxSize().padding(padding),
                contentPadding = PaddingValues(12.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                items(projects, key = { it.id }) { project ->
                    ProjectTile(
                        project = project,
                        onOpen = { onOpenProject(project.id) },
                        onChangePhoto = {
                            pendingImageProjectId = project.id
                            photoPickerLauncher.launch(
                                PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
                            )
                        }
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

@Composable
private fun ProjectTile(
    project: ProjectEntity,
    onOpen: () -> Unit,
    onChangePhoto: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .height(160.dp)
            .clickable(onClick = onOpen)
    ) {
        Box(modifier = Modifier.fillMaxSize()) {
            if (project.imagePath != null) {
                AsyncImage(
                    model = File(project.imagePath),
                    contentDescription = project.name,
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Crop
                )
            } else {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(MaterialTheme.colorScheme.surfaceVariant),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        ImageIcon,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .align(Alignment.BottomStart)
                    .background(
                        Brush.verticalGradient(
                            colors = listOf(Color.Transparent, Color.Black.copy(alpha = 0.65f))
                        )
                    )
                    .padding(8.dp)
            ) {
                Text(project.name, color = Color.White, style = MaterialTheme.typography.titleSmall)
            }

            IconButton(
                onClick = onChangePhoto,
                modifier = Modifier.align(Alignment.TopEnd).padding(4.dp)
            ) {
                Icon(Icons.Filled.PhotoCamera, contentDescription = "Change photo", tint = Color.White)
            }
        }
    }
}

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/ui/screens/projectlist/ProjectListScreen.kt"

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
    implementation("io.coil-kt:coil-compose:2.6.0")
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
echo "Reminder: local app data was reset by this schema change (see warning above)."
