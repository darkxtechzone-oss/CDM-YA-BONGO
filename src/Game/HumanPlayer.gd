extends "res://src/Game/Fighter.gd"
# The player: third-person over-the-shoulder camera, touch controls from the HUD.

const SENS := 0.0035
const CAM_OFFSET := Vector3(0.75, 0.25, 3.3)

var hud
var cam: Camera
var pivot: Spatial
var yaw := 0.0
var pitch := -0.08


func setup() -> void:
	move_speed = 7.5
	damage = 22.0
	fire_interval = 0.1
	yaw = rotation.y
	show_marker = false
	_marker.visible = false

	pivot = Spatial.new()
	pivot.translation = Vector3(0, 1.55, 0)
	add_child(pivot)

	cam = Camera.new()
	cam.fov = 72.0
	cam.far = 250.0
	cam.translation = CAM_OFFSET
	pivot.add_child(cam)
	cam.current = true


func think(delta: float) -> void:
	# --- look ---
	var ld: Vector2 = hud.consume_look()
	yaw -= ld.x * SENS
	pitch = clamp(pitch - ld.y * SENS, -1.0, 1.0)
	rotation.y = yaw
	pivot.rotation.x = pitch

	# --- move ---
	var mv: Vector2 = hud.move_vec
	mv.x += Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	mv.y += Input.get_action_strength("move_back") - Input.get_action_strength("move_front")
	if mv.length() > 1.0:
		mv = mv.normalized()
	var b := global_transform.basis
	wish_dir = b.x * mv.x + b.z * mv.y
	wish_dir.y = 0.0

	if hud.consume_jump() or Input.is_action_just_pressed("jump"):
		want_jump = true
	if hud.consume_reload() or Input.is_action_just_pressed("reload"):
		start_reload()

	_update_camera()

	# --- shoot ---
	if hud.fire_held:
		var t := cam.global_transform
		var dir := -t.basis.z
		var p0 := pivot.global_transform.origin
		var origin := t.origin + dir * max(0.0, (p0 - t.origin).dot(dir))
		spread = 0.006 + 0.012 * min(1.0, Vector3(velocity.x, 0, velocity.z).length() / move_speed)
		if can_fire():
			fire_at(origin, dir, muzzle_position())
			pitch = min(1.0, pitch + 0.004)


func _update_camera() -> void:
	var from := pivot.global_transform.origin
	var to := pivot.global_transform.xform(CAM_OFFSET)
	var hit := get_world().direct_space_state.intersect_ray(from, to, [self], 1)
	if hit:
		to = hit.position + (from - hit.position).normalized() * 0.25
	var t := cam.global_transform
	t.origin = to
	cam.global_transform = t


func on_damaged(_attacker) -> void:
	hud.flash_damage()


func on_respawned() -> void:
	yaw = rotation.y
	pitch = -0.08
