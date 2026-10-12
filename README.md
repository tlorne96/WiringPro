# WiringPro

Reverse-engineering tool for EV/PEV wiring looms: photograph/define connectors,
map pins to signals (nets), auto-detect shared nets (e.g. ground fan-out),
and generate a professional PDF wiring diagram. Projects sync to a
self-hosted server you run at home.

## Folders

- `android-app/` — the tablet app (Kotlin + Jetpack Compose). This is what
  you open in Android Studio.
- `server/` — the self-hosted sync server. Runs on your home machine,
  reachable at something like `wiringpro.timlorne.com`.
- `shared/` — JSON Schemas that define the project file format and the part
  library format. Both the app and the server treat these as the single
  source of truth for "what a project looks like" — if you ever add a
  field, add it here first, then update both sides.
- `part-library/` — starter part definitions (throttles, displays, brake
  sensors, ignition, 12V converters, etc). These ship with the app and are
  also what gets synced/shared across projects.

## Data model in one paragraph

A **Project** has a list of **Connectors**. Each Connector has a pin **grid**
(rows x columns, supports irregular/staggered layouts) and a list of **Pins**.
Instead of wiring pin-to-pin, every Pin is assigned to a **Net** (e.g. `GND`,
`5V_SUPPLY`, `THROTTLE_A`). A Net can hold any number of pins across any
number of connectors — that's how one ground pin on the main connector can
fan out to five different places on the harness. The PDF generator draws
each connector, then draws/labels each Net's connections.
