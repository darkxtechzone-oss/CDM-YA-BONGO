extends "res://src/Game/Fighter.gd"
# The player: third-person over-the-shoulder camera, touch controls from the HUD,
# smooth look, adjustable sensitivity and head-seeking aim assist.

const SENS := 0.0035
const CAM_OFFSET = Vector3(0.75, 0.25, 3.3)
const ASSIST_RANGE := 70.0

var hud
var cam: Camera
var pivot: Spatial
var yaw := 0.0
var pitch := -0.08
var _look_s := Vector2.ZERO
var _pivot_y := 1.55


func setup() -> void:
	move_speed = 7.5
	damage = 22.0
	fire_interval = 0.1
	bullet_speed = 170.0
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
	# --- look: smoothed + sensitivity from settings ---
	var raw: Vector2 = hud.consume_look()
	var a: float = lerp(1.0, 0.18, hud.smooth)
	_look_s += (raw - _look_s) * a
	var k: float = SENS * hud.sens
	yaw -= _look_s.x * k
	pitch = clamp(pitch - _look_s.y * k, -1.0, 1.0)

	# --- aim assist: pull the crosshair toward the nearest enemy head ---
	var head_target = null
	if hud.assist > 0.0:
		head_target = _assist_target()
	if head_target != null:
		var v: Vector3 = head_target - cam.global_transform.origin
		var d_yaw: float = atan2(-v.x, -v.z)
		var d_pitch: float = atan2(v.y, Vector2(v.x, v.z).length())
		var pull: float = hud.assist * (2.5 + (6.0 if hud.fire_held else 0.0)) * delta
		pull = min(pull, 0.5)
		yaw += wrapf(d_yaw - yaw, -PI, PI) * pull
		pitch += (d_pitch - pitch) * pull

	rotation.y = yaw
	pivot.rotation.x = pitch
	gun_pitch = pitch

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
	if hud.consume_slide():
		start_slide()
	if hud.consume_reload() or Input.is_action_just_pressed("reload"):
		start_reload()

	var target_y: float = 0.95 if sliding else 1.55
	_pivot_y = lerp(_pivot_y, target_y, clamp(10.0 * delta, 0.0, 1.0))
	pivot.translation = Vector3(0, _pivot_y, 0)
	_update_camera()

	# --- shoot ---
	if hud.fire_held and can_fire():
		var t := cam.global_transform
		var fwd := -t.basis.z
		var p0 := pivot.global_transform.origin
		var along: float = max(0.0, (p0 - t.origin).dot(fwd))
		var origin: Vector3 = t.origin + fwd * along
		var far: Vector3 = t.origin + fwd * 120.0
		var hit := get_world().direct_space_state.intersect_ray(origin, far, [self], 3)
		var aim: Vector3 = far
		if hit:
			aim = hit.position
		if head_target != null:
			aim = aim.linear_interpolate(head_target, hud.assist * 0.8)
		spread = 0.004 + 0.010 * min(1.0, Vector3(velocity.x, 0, velocity.z).length() / move_speed)
		fire_toward(aim, muzzle_position())
		pitch = min(1.0, pitch + 0.003)


func _assist_target():
	var t := cam.global_transform
	var fwd := -t.basis.z
	var best = null
	var best_ang: float = deg2rad(5.0 + 4.0 * hud.assist)
	for f in get_tree().get_nodes_in_group("fighters"):
		if f.team == team or not f.alive:
			continue
		var head: Vector3 = f.head_position()
		var to: Vector3 = head - t.origin
		var dist: float = to.length()
		if dist > ASSIST_RANGE or dist < 2.0:
			continue
		var ang: float = acos(clamp(fwd.dot(to / dist), -1.0, 1.0))
		if ang < best_ang:
			if get_world().direct_space_state.intersect_ray(t.origin, head, [self], 1).empty():
				best_ang = ang
				best = head
	return best


func _update_camera() -> void:
	var from := pivot.global_transform.origin
	var to: Vector3 = pivot.global_transform.xform(CAM_OFFSET)
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
