extends "res://src/Game/Fighter.gd"
# Simple AI: finds the nearest visible enemy, strafes and shoots in bursts,
# otherwise wanders between waypoints. Uses raycasts for obstacle avoidance.

var skill := 1.0
var target = null
var target_visible := false
var last_known := Vector3.ZERO
var _chase_time := 0.0
var _reaction := 0.0
var _think_timer := 0.0
var _strafe_dir := 1.0
var _strafe_timer := 0.0
var _burst_left := 6
var _pause := 0.0
var _waypoint := Vector3.ZERO
var _avoid_timer := 0.0
var _avoid_dir := 1.0
var _stuck_timer := 0.0
var _last_pos := Vector3.ZERO


func setup() -> void:
	skill = game.bot_skill
	move_speed = rand_range(5.0, 6.2)
	damage = 8.0 + 3.0 * skill
	fire_interval = 0.13
	spread = 0.07 / skill
	_think_timer = randf() * 0.3
	_pick_waypoint()
	_last_pos = global_transform.origin


func on_respawned() -> void:
	target = null
	target_visible = false
	_chase_time = 0.0
	_pick_waypoint()


func on_damaged(attacker) -> void:
	if attacker != null and attacker.alive:
		last_known = attacker.global_transform.origin
		_chase_time = 4.0


func think(delta: float) -> void:
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = rand_range(0.2, 0.4)
		_acquire_target()
	if _chase_time > 0.0:
		_chase_time -= delta

	var pos := global_transform.origin
	var eye := pos + Vector3(0, 1.5, 0)
	var move := Vector3.ZERO
	var face := Vector3.ZERO

	if target != null and (not target.alive):
		target = null
		target_visible = false

	if target_visible and target != null:
		var tpos: Vector3 = target.global_transform.origin
		var to_t := tpos - pos
		var flat := Vector3(to_t.x, 0, to_t.z)
		var dist := flat.length()
		flat = flat.normalized()
		face = flat
		_strafe_timer -= delta
		if _strafe_timer <= 0.0:
			_strafe_timer = rand_range(0.8, 2.0)
			_strafe_dir = 1.0 if randf() < 0.5 else -1.0
		move = flat.cross(Vector3.UP) * _strafe_dir * 0.7
		if dist > 18.0:
			move += flat * 0.8
		elif dist < 7.0:
			move -= flat * 0.6

		_reaction -= delta
		_pause -= delta
		var yaw_err: float = abs(wrapf(_yaw_for(flat) - rotation.y, -PI, PI))
		if _reaction <= 0.0 and _pause <= 0.0 and yaw_err < 0.3 and can_fire():
			var aim := tpos + Vector3(0, rand_range(0.9, 1.5), 0)
			fire_at(eye, (aim - eye).normalized(), muzzle_position())
			_burst_left -= 1
			if _burst_left <= 0:
				_burst_left = randi() % 6 + 5
				_pause = rand_range(0.3, 0.9) / skill
	else:
		var dest := _waypoint
		if _chase_time > 0.0:
			dest = last_known
		var to_d := dest - pos
		to_d.y = 0.0
		if to_d.length() < 2.0:
			_chase_time = 0.0
			_pick_waypoint()
		else:
			move = to_d.normalized()
			face = move
		if ammo < mag_size / 2:
			start_reload()

	if move.length() > 0.1:
		move = _avoid(move, pos, delta)
	if move.length() > 1.0:
		move = move.normalized()
	wish_dir = move

	if face != Vector3.ZERO:
		rotation.y = lerp_angle(rotation.y, _yaw_for(face), clamp(8.0 * delta, 0.0, 1.0))

	# stuck detection
	_stuck_timer += delta
	if _stuck_timer > 1.0:
		_stuck_timer = 0.0
		if move.length() > 0.3 and pos.distance_to(_last_pos) < 0.6:
			_pick_waypoint()
			_avoid_timer = 0.8
			_avoid_dir = 1.0 if randf() < 0.5 else -1.0
			want_jump = randf() < 0.5
		_last_pos = pos


func _yaw_for(dir: Vector3) -> float:
	# forward is -Z: rotation y = atan2(-x, -z)
	return atan2(-dir.x, -dir.z)


func _ray_blocked(from: Vector3, dir: Vector3, length: float) -> bool:
	var hit := get_world().direct_space_state.intersect_ray(from, from + dir * length, [self], 1)
	return not hit.empty()


func _avoid(move: Vector3, pos: Vector3, delta: float) -> Vector3:
	var dir := move.normalized()
	if _avoid_timer > 0.0:
		_avoid_timer -= delta
		return dir.rotated(Vector3.UP, _avoid_dir * 1.2)
	var low := _ray_blocked(pos + Vector3(0, 0.4, 0), dir, 1.6)
	if low:
		var high := _ray_blocked(pos + Vector3(0, 1.5, 0), dir, 1.6)
		if not high:
			want_jump = true  # low cover: hop over it
			return move
		var left_blocked := _ray_blocked(pos + Vector3(0, 0.6, 0), dir.rotated(Vector3.UP, 1.1), 2.0)
		var right_blocked := _ray_blocked(pos + Vector3(0, 0.6, 0), dir.rotated(Vector3.UP, -1.1), 2.0)
		if left_blocked and not right_blocked:
			_avoid_dir = -1.0
		elif right_blocked and not left_blocked:
			_avoid_dir = 1.0
		else:
			_avoid_dir = 1.0 if randf() < 0.5 else -1.0
		_avoid_timer = 0.6
		return dir.rotated(Vector3.UP, _avoid_dir * 1.2)
	return move


func _pick_waypoint() -> void:
	_waypoint = game.arena.random_waypoint()


func _acquire_target() -> void:
	var pos := global_transform.origin
	var eye := pos + Vector3(0, 1.5, 0)
	var best = null
	var best_d := 1e9
	for f in get_tree().get_nodes_in_group("fighters"):
		if f.team == team or not f.alive:
			continue
		var fpos: Vector3 = f.global_transform.origin
		var d := pos.distance_to(fpos)
		if d > 60.0 or d >= best_d:
			continue
		if not _ray_blocked(eye, ((fpos + Vector3(0, 1.2, 0)) - eye).normalized(), d):
			best = f
			best_d = d
	if best != null:
		if best != target or not target_visible:
			_reaction = rand_range(0.25, 0.6) / skill
		target = best
		target_visible = true
		last_known = best.global_transform.origin
		_chase_time = 3.0
	else:
		target_visible = false
