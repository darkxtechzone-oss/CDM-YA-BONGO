extends "res://src/Game/Fighter.gd"
# Another online player: only follows the network state (damage is decided on
# the victim's own device, see Main.gd).

var tgt_pos := Vector3.ZERO
var tgt_yaw := 0.0
var _have := false


func setup() -> void:
	puppet = true
	show_marker = false
	_marker.visible = false
	tgt_pos = translation
	tgt_yaw = rotation.y


func net_state(m: Dictionary) -> void:
	var p: Array = m["p"]
	var v: Array = m["v"]
	tgt_pos = Vector3(p[0], p[1], p[2])
	tgt_yaw = float(m["r"])
	gun_pitch = float(m["pi"])
	velocity = Vector3(v[0], 0.0, v[1])
	var st := int(m["st"])
	if bool(m.get("sl", false)) != sliding:
		sliding = bool(m.get("sl", false))
		_apply_pose()
	if st != stance:
		stance = st
		_apply_pose()
	var w: String = String(m["w"])
	if w != cur:
		show_weapon(w)
	if not _have:
		_have = true
		translation = tgt_pos
		rotation.y = tgt_yaw


func think(delta: float) -> void:
	var k: float = clamp(12.0 * delta, 0.0, 1.0)
	translation = translation.linear_interpolate(tgt_pos, k)
	rotation.y = lerp_angle(rotation.y, tgt_yaw, k)


func _move(_delta: float) -> void:
	pass
