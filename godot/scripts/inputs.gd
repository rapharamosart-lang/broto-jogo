extends Node
## Input map built in code: keyboard + gamepad. Touch buttons (ui/touch.gd) press these same actions.
const MAP := {
	"left":  {"keys": [KEY_A, KEY_LEFT],  "joy": [JOY_BUTTON_DPAD_LEFT],  "axis": [JOY_AXIS_LEFT_X, -1.0]},
	"right": {"keys": [KEY_D, KEY_RIGHT], "joy": [JOY_BUTTON_DPAD_RIGHT], "axis": [JOY_AXIS_LEFT_X, 1.0]},
	"up":    {"keys": [KEY_W, KEY_UP],    "joy": [JOY_BUTTON_DPAD_UP],    "axis": [JOY_AXIS_LEFT_Y, -1.0]},
	"down":  {"keys": [KEY_S, KEY_DOWN],  "joy": [JOY_BUTTON_DPAD_DOWN],  "axis": [JOY_AXIS_LEFT_Y, 1.0]},
	"jump":  {"keys": [KEY_SPACE, KEY_Z], "joy": [JOY_BUTTON_A]},
	"dash":  {"keys": [KEY_SHIFT, KEY_C], "joy": [JOY_BUTTON_RIGHT_SHOULDER], "axis": [JOY_AXIS_TRIGGER_RIGHT, 1.0]},
	"run":   {"keys": [KEY_CTRL],         "joy": [JOY_BUTTON_B]},
	"grab":  {"keys": [KEY_E],            "joy": [JOY_BUTTON_Y]},
	"attack":{"keys": [KEY_X, KEY_J],     "joy": [JOY_BUTTON_X]},
	"pause": {"keys": [KEY_ESCAPE],       "joy": [JOY_BUTTON_START]},
}
func _ready() -> void:
	for a in MAP:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.35)
		for k in MAP[a].keys:
			var e := InputEventKey.new(); e.physical_keycode = k; InputMap.action_add_event(a, e)
		for b in MAP[a].joy:
			var j := InputEventJoypadButton.new(); j.button_index = b; InputMap.action_add_event(a, j)
		if MAP[a].has("axis"):
			var m := InputEventJoypadMotion.new(); m.axis = MAP[a].axis[0]; m.axis_value = MAP[a].axis[1]; InputMap.action_add_event(a, m)
