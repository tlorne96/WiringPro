#!/bin/bash
# WiringPro core Android code — run AFTER setup.sh, from inside the
# 'wiringpro' folder it created (the one containing android-app/, server/, shared/).
# Adds: Room DB (entities/DAOs), repository, pin-grid UI, net picker, nav, MainActivity.
set -e

mkdir -p "$(dirname "android-app/app/src/main/AndroidManifest.xml")"
cat > android-app/app/src/main/AndroidManifest.xml << 'KOTLIN_EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <application
        android:name=".WiringProApplication"
        android:allowBackup="true"
        android:label="WiringPro"
        android:theme="@android:style/Theme.Material.Light.NoActionBar">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:label="WiringPro">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

    </application>

</manifest>

KOTLIN_EOF
echo "Wrote android-app/app/src/main/AndroidManifest.xml"

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/MainActivity.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/MainActivity.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.timlorne.wiringpro.ui.nav.WiringProNavHost

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val repository = (application as WiringProApplication).repository

        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    var projectId by remember { mutableStateOf<String?>(null) }

                    LaunchedEffect(Unit) {
                        projectId = repository.ensureDefaultProject()
                    }

                    val currentProjectId = projectId
                    if (currentProjectId == null) {
                        Text("Loading…")
                    } else {
                        WiringProNavHost(repository = repository, projectId = currentProjectId)
                    }
                }
            }
        }
    }
}

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/MainActivity.kt"

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/WiringProApplication.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/WiringProApplication.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro

import android.app.Application
import com.timlorne.wiringpro.data.db.AppDatabase
import com.timlorne.wiringpro.data.repository.WiringRepository

// Deliberately no DI framework (Hilt/Koin) yet — one repository singleton
// off the Application is enough at this stage and keeps the build simple.
// Worth revisiting once there's more than a couple of ViewModels to wire up.
class WiringProApplication : Application() {
    lateinit var repository: WiringRepository
        private set

    override fun onCreate() {
        super.onCreate()
        val db = AppDatabase.getInstance(this)
        repository = WiringRepository(db)
    }
}

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/WiringProApplication.kt"

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
    val updatedAt: Long
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

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/data/model/Project.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/data/model/Project.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.data.model

// Mirrors shared/project-schema.json — keep these in sync by hand for now.
data class Project(
    val id: String,
    val name: String,
    val vehicle: String? = null,
    val notes: String? = null,
    val connectors: List<Connector> = emptyList(),
    val nets: List<Net> = emptyList(),
    val createdAt: String,
    val updatedAt: String
)

data class Connector(
    val id: String,
    val label: String,
    val partRef: String? = null,
    val rows: List<Int>,       // pin count per physical row -> supports irregular connectors
    val pins: List<Pin>
)

data class Pin(
    val id: String,
    val index: Int,            // as printed on the connector
    val row: Int,
    val col: Int,
    val netId: String? = null,
    val label: String? = null
)

data class Net(
    val id: String,
    val name: String,          // e.g. "GND", "THROTTLE_A"
    val color: String? = null,
    val pinRefs: List<PinRef> = emptyList()
)

data class PinRef(
    val connectorId: String,
    val pinId: String
)

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/data/model/Project.kt"

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/data/model/StandardNetTypes.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/data/model/StandardNetTypes.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.data.model

// Keep this in sync by hand with shared/net-types.json — it's the same list,
// duplicated here because the app doesn't parse JSON off disk for this yet.
data class StandardNetType(val type: String, val label: String, val defaultColor: String?)

object StandardNetTypes {
    val ALL = listOf(
        StandardNetType("GND", "Ground / common ground", "#000000"),
        StandardNetType("12V_SUPPLY", "12V battery supply", "#8B0000"),
        StandardNetType("5V_SUPPLY", "5V sensor supply", "#FF0000"),
        StandardNetType("IGNITION_ON", "Ignition / key on", "#FFA500"),
        StandardNetType("THROTTLE_SIGNAL_A", "Throttle signal A", "#00AEEF"),
        StandardNetType("THROTTLE_SIGNAL_B", "Throttle signal B", "#7CFC00"),
        StandardNetType("BRAKE_SIGNAL", "Brake switch signal", "#FFFF00"),
        StandardNetType("HORN", "Horn", "#A0522D"),
        StandardNetType("TURN_SIGNAL_L", "Turn signal - left", "#008000"),
        StandardNetType("TURN_SIGNAL_R", "Turn signal - right", "#FF69B4"),
        StandardNetType("HEADLIGHT", "Headlight", "#FFFFFF"),
        StandardNetType("TAILLIGHT_BRAKE", "Taillight / brake light", "#DC143C"),
        StandardNetType("CAN_H", "CAN bus high", "#4B0082"),
        StandardNetType("CAN_L", "CAN bus low", "#9370DB"),
        StandardNetType("SPEED_SENSOR", "Speed sensor signal", "#40E0D0"),
        StandardNetType("DISPLAY_DATA", "Display data line", "#DAA520"),
        StandardNetType("CUSTOM", "Custom / user-defined", null)
    )
}

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/data/model/StandardNetTypes.kt"

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
import java.util.UUID

class WiringRepository(private val db: AppDatabase) {

    // -------------------------------------------------------------
    // Projects — single default project for now; a real project
    // picker screen is a straightforward follow-up on top of this.
    // -------------------------------------------------------------

    suspend fun ensureDefaultProject(): String {
        val existing = db.projectDao().observeAll()
        val id = "default-project"
        val now = System.currentTimeMillis()
        if (db.projectDao().getById(id) == null) {
            db.projectDao().upsert(
                ProjectEntity(
                    id = id,
                    name = "Untitled project",
                    vehicle = null,
                    notes = null,
                    createdAt = now,
                    updatedAt = now
                )
            )
        }
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
                                .let { it }
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

// Small local helper so this file doesn't need an extra import block for a
// one-off clickable modifier chain.
private fun Modifier.clickableCompat(onClick: () -> Unit): Modifier =
    this.then(androidx.compose.foundation.clickable(onClick = onClick))

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/ui/components/NetPickerDialog.kt"

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/ui/components/PinGrid.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/ui/components/PinGrid.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.timlorne.wiringpro.data.db.ConnectorEntity
import com.timlorne.wiringpro.data.db.NetEntity
import com.timlorne.wiringpro.data.db.PinEntity

/**
 * Renders a connector as rows of tappable pin cells, honoring irregular
 * per-row pin counts (connector.rows). One cell per pin, laid out in the
 * same left-to-right/top-to-bottom order the pins were numbered in.
 */
@Composable
fun PinGrid(
    connector: ConnectorEntity,
    pins: List<PinEntity>,
    nets: List<NetEntity>,
    onPinClick: (PinEntity) -> Unit,
    modifier: Modifier = Modifier
) {
    val netsById = nets.associateBy { it.id }
    val pinsByRow = pins.groupBy { it.row }

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for (rowIndex in connector.rows.indices) {
            val rowPins = (pinsByRow[rowIndex] ?: emptyList()).sortedBy { it.col }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (pin in rowPins) {
                    val net = pin.netId?.let { netsById[it] }
                    PinCell(pin = pin, net = net, onClick = { onPinClick(pin) })
                }
            }
        }
    }
}

@Composable
private fun PinCell(pin: PinEntity, net: NetEntity?, onClick: () -> Unit) {
    val assignedColor = net?.color?.let { runCatching { Color(android.graphics.Color.parseColor(it)) }.getOrNull() }
    val borderColor = assignedColor ?: MaterialTheme.colorScheme.outline

    Box(
        modifier = Modifier
            .size(width = 72.dp, height = 52.dp)
            .border(width = if (net != null) 2.dp else 1.dp, color = borderColor, shape = RoundedCornerShape(6.dp))
            .background(MaterialTheme.colorScheme.surface, RoundedCornerShape(6.dp))
            .clickable(onClick = onClick)
            .padding(4.dp),
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = pin.index.toString(),
                style = MaterialTheme.typography.labelLarge,
                textAlign = TextAlign.Center
            )
            Text(
                text = net?.name ?: "—",
                style = MaterialTheme.typography.labelSmall,
                textAlign = TextAlign.Center,
                color = if (net != null) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.outline
            )
        }
    }
}

KOTLIN_EOF
echo "Wrote android-app/app/src/main/java/com/timlorne/wiringpro/ui/components/PinGrid.kt"

mkdir -p "$(dirname "android-app/app/src/main/java/com/timlorne/wiringpro/ui/nav/WiringProNavHost.kt")"
cat > android-app/app/src/main/java/com/timlorne/wiringpro/ui/nav/WiringProNavHost.kt << 'KOTLIN_EOF'
package com.timlorne.wiringpro.ui.nav

import androidx.compose.runtime.Composable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import androidx.navigation.NavType
import com.timlorne.wiringpro.data.repository.WiringRepository
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

    NavHost(navController = navController, startDestination = "new_connector") {
        composable("new_connector") {
            val vm: NewConnectorViewModel = viewModel(
                factory = SimpleFactory { NewConnectorViewModel(repository, projectId) }
            )
            NewConnectorScreen(
                viewModel = vm,
                onConnectorCreated = { connectorId ->
                    navController.navigate("editor/$connectorId")
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
import androidx.lifecycle.viewmodel.compose.viewModel
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

/**
 * Asks how many rows a connector has and how many pins are in each row —
 * the camera-based version is deferred, this is the whole input flow for now.
 */
@Composable
fun NewConnectorScreen(
    viewModel: NewConnectorViewModel,
    onConnectorCreated: (String) -> Unit,
    onBack: () -> Unit
) {
    var label by remember { mutableStateOf("") }
    val rowCounts = remember { mutableStateListOf(6) } // default: one row of 6 pins

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

cat > android-app/app/build.gradle.kts << 'GRADLE_EOF'
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

GRADLE_EOF
echo "Updated android-app/app/build.gradle.kts with navigation/viewmodel/coroutines deps + composeOptions"

echo ""
echo "Done. Open android-app/ in Android Studio, let Gradle sync, and run on the tablet/emulator."
