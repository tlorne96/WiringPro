package com.timlorne.wiringpro.data.model

// Keep this in sync by hand with shared/net-types.json — it's the same list,
// duplicated here because the app doesn't parse JSON off disk for this yet.
data class StandardNetType(val type: String, val label: String, val defaultColor: String?)

object StandardNetTypes {
    val ALL = listOf(
        StandardNetType("GND", "Ground / common ground", "#000000"),
        StandardNetType("12V_SUPPLY", "12V battery supply", "#8B0000"),
        StandardNetType("36V_SUPPLY", "36V battery supply", "#7B1FA2"),
        StandardNetType("5V_SUPPLY", "5V sensor supply", "#FF0000"),
        StandardNetType("PWM_INPUT", "PWM IN", "#FF8C00"),
        StandardNetType("IGNITION_ON", "Ignition / key on", "#FFA500"),
        StandardNetType("THROTTLE_SIGNAL_A", "Throttle signal A", "#00AEEF"),
        StandardNetType("THROTTLE_SIGNAL_B", "Throttle signal B", "#7CFC00"),
        StandardNetType("BRAKE_SIGNAL", "Brake switch signal", "#FFFF00"),
        StandardNetType("HORN", "Horn", "#A0522D"),
        StandardNetType("TURN_SIGNAL_L", "Turn signal - left", "#008000"),
        StandardNetType("TURN_SIGNAL_R", "Turn signal - right", "#FF69B4"),
        StandardNetType("HEADLIGHT", "Headlight", "#A9A9A9"),
        StandardNetType("TAILLIGHT_BRAKE", "Taillight / brake light", "#DC143C"),
        StandardNetType("CAN_H", "CAN bus high", "#4B0082"),
        StandardNetType("CAN_L", "CAN bus low", "#9370DB"),
        StandardNetType("CAN2_H", "CAN 2 BUS High", "#6A1B9A"),
        StandardNetType("CAN2_L", "CAN 2 BUS Low", "#8E24AA"),
        StandardNetType("SPEED_SENSOR", "Speed sensor signal", "#40E0D0"),
        StandardNetType("DISPLAY_DATA", "Display data line", "#DAA520"),
        // Electric-drivetrain specific — added for e-bike/PEV builds (BLDC
        // hub/mid-drive motor, main pack, contactor, kill/sidestand switches).
        StandardNetType("MOTOR_PHASE_U", "Motor phase U", "#1E90FF"),
        StandardNetType("MOTOR_PHASE_V", "Motor phase V", "#FF7F50"),
        StandardNetType("MOTOR_PHASE_W", "Motor phase W", "#6A5ACD"),
        StandardNetType("MOTOR_HALL_A", "Motor hall sensor A", "#20B2AA"),
        StandardNetType("MOTOR_HALL_B", "Motor hall sensor B", "#BA55D3"),
        StandardNetType("MOTOR_HALL_C", "Motor hall sensor C", "#CD5C5C"),
        StandardNetType("MOTOR_TEMP_SENSOR", "Motor temperature sensor", "#556B2F"),
        StandardNetType("BATTERY_POSITIVE", "Battery pack positive", "#B22222"),
        StandardNetType("BATTERY_NEGATIVE", "Battery pack negative", "#2F4F4F"),
        StandardNetType("CONTACTOR_COIL", "Main contactor coil", "#DA70D6"),
        StandardNetType("KILL_SWITCH", "Kill switch", "#B03060"),
        StandardNetType("SIDESTAND_SWITCH", "Sidestand / kickstand switch", "#8FBC8F"),
        StandardNetType("REGEN_BRAKE_SIGNAL", "Regen brake signal", "#FFD700"),
        StandardNetType("CHARGE_PORT", "Charge port", "#32CD32"),
        StandardNetType("CUSTOM", "Custom / user-defined", null)
    )
}

