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

