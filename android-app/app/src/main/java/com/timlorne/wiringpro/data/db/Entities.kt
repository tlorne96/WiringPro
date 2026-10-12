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

