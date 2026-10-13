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
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
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

    @Query("UPDATE nets SET color = :color, stripeColor = :stripeColor WHERE id = :netId")
    suspend fun updateWireColors(netId: String, color: String?, stripeColor: String?)

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
    version = 3,
    exportSchema = false
)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun projectDao(): ProjectDao
    abstract fun connectorDao(): ConnectorDao
    abstract fun pinDao(): PinDao
    abstract fun netDao(): NetDao

    companion object {
        private val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE projects ADD COLUMN imagePath TEXT")
            }
        }

        private val MIGRATION_2_3 = object : Migration(2, 3) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE nets ADD COLUMN stripeColor TEXT")
            }
        }

        @Volatile private var instance: AppDatabase? = null

        fun getInstance(context: Context): AppDatabase =
            instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "wiringpro.db"
                )
                    .addMigrations(MIGRATION_1_2, MIGRATION_2_3)
                    // Retain the fallback for development builds with unknown older schemas.
                    .fallbackToDestructiveMigration()
                    .build().also { instance = it }
            }
    }
}

