extends KinematicBody
# Base class for every combatant (human player and bots).
# Subclasses override setup(), think(delta), on_damaged(), on_respawned().

const MannequinScene = preload("res://src/Player/Mannequiny.tscn")

const GRAVITY := -32.0
const JUMP_SPEED := 9.5
const MAX_HP := 100.0
const ANIM_STEP := 0.05  # animation updated at 20 Hz (saves CPU)
const SLIDE_TIME := 0.75
const SLIDE_COOLDOWN := 0.8
const GUN_POS = Vector3(0.22, 1.12, -0.38)
# slide pose (tweak if the body looks off)
const SLIDE_SKIN_ROT = Vector3(-75, 180, 0)
const SLIDE_SKIN_POS = Vector3(0, 0.1, -0.6)
const NORMAL_SKIN_POS = Vector3(0, 0, 0.222992)

var game          # Main node
var team := 0     # 0 = blue (player team), 1 = red
var display_name := "Fighter"

var hp := MAX_HP
var alive := true
var invuln := 0.0
var respawn_left := 0.0
var _since_hit := 99.0

var skin
var _shape: CollisionShape
var _cap: CapsuleShape
var _marker: MeshInstance
var _gun: Spatial
var _flash: MeshInstance
var _anim_state := -1
var show_marker := true
var _anim_acc := 0.0
var _flash_t := 0.0
var _recoil := 0.0
var gun_pitch := 0.0

# Movement (set by subclasses in think())
var move_speed := 7.0
var velocity := Vector3.ZERO
var wish_dir := Vector3.ZERO
var want_jump := false
var sliding := false
var _slide_t := 0.0
var _slide_cd := 0.0
var _slide_dir := Vector3.ZERO

# Weapon
var damage := 22.0
var fire_interval := 0.1
var mag_size := 30
var ammo := 30
var reload_time := 1.8
var spread := 0.02
var bullet_speed := 100.0
var _cooldown := 0.0
var _reload_left := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 2
	add_to_group("fighters")

	_shape = CollisionShape.new()
	_cap = CapsuleShape.new()
	_cap.radius = 0.3
	_cap.height = 1.2
	_shape.shape = _cap
	_shape.rotation_degrees = Vector3(90, 0, 0)
	_shape.translation = Vector3(0, 0.9, 0)
	add_child(_shape)

	skin = MannequinScene.instance()
	skin.rotation_degrees = Vector3(0, 180, 0)
	skin.translation = NORMAL_SKIN_POS
	add_child(skin)
	skin.animation_tree.process_mode = AnimationTree.ANIMATION_PROCESS_MANUAL
	_anim_acc = randf() * ANIM_STEP
	_tint_skin()

	_marker = MeshInstance.new()
	var sm := SphereMesh.new()
	sm.radius = 0.13
	sm.height = 0.26
	sm.radial_segments = 8
	sm.rings = 4
	_marker.mesh = sm
	var mm := SpatialMaterial.new()
	mm.flags_unshaded = true
	mm.albedo_color = _team_color()
	if team == 0:
		mm.flags_no_depth_test = true  # allies visible through walls
	_marker.material_override = mm
	_marker.translation = Vector3(0, 2.2, 0)
	add_child(_marker)

	_build_gun()
	setup()


func _team_color() -> Color:
	return Color(0.2, 0.5, 1.0) if team == 0 else Color(1.0, 0.2, 0.15)


func _tint_skin() -> void:
	var mi = skin.get_node_or_null("root/Skeleton/body001")
	if mi == null:
		return
	for i in range(mi.get_surface_material_count()):
		var m = mi.get_active_material(i)
		if m != null and m.resource_path.ends_with("Azul.material"):
			var d = m.duplicate()
			d.set("albedo_color", _team_color())
			mi.set_surface_material(i, d)


func _build_gun() -> void:
	_gun = Spatial.new()
	_gun.translation = GUN_POS
	add_child(_gun)
	var dark := SpatialMaterial.new()
	dark.albedo_color = Color(0.09, 0.09, 0.11)
	var parts := [
		[Vector3(0.0, 0.0, 0.0), Vector3(0.07, 0.10, 0.55)],
		[Vector3(0.0, 0.02, -0.42), Vector3(0.035, 0.035, 0.32)],
		[Vector3(0.0, -0.13, 0.05), Vector3(0.05, 0.17, 0.08)],
		[Vector3(0.0, -0.02, 0.33), Vector3(0.06, 0.12, 0.18)],
	]
	for p in parts:
		var mi := MeshInstance.new()
		var bm := CubeMesh.new()
		bm.size = p[1]
		mi.mesh = bm
		mi.material_override = dark
		mi.translation = p[0]
		_gun.add_child(mi)
	_flash = MeshInstance.new()
	var fm := SphereMesh.new()
	fm.radius = 0.12
	fm.height = 0.24
	fm.radial_segments = 6
	fm.rings = 3
	_flash.mesh = fm
	var fmat := SpatialMaterial.new()
	fmat.flags_unshaded = true
	fmat.albedo_color = Color(1.0, 0.85, 0.3)
	_flash.material_override = fmat
	_flash.translation = Vector3(0, 0.02, -0.68)
	_flash.visible = false
	_gun.add_child(_flash)


# ---- hooks -----------------------------------------------------------------
func setup() -> void:
	pass


func think(_delta: float) -> void:
	pass


func on_damaged(_attacker) -> void:
	pass


func on_respawned() -> void:
	pass


# ---- main loop -------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if not alive:
		respawn_left -= delta
		if respawn_left <= 0.0 and game != null:
			game.respawn_fighter(self)
		return

	if invuln > 0.0:
		invuln -= delta
		skin.visible = invuln <= 0.0 or int(invuln * 12.0) % 2 == 0
		_gun.visible = skin.visible

	_since_hit += delta
	if hp < MAX_HP and _since_hit > 4.0:
		hp = min(MAX_HP, hp + 15.0 * delta)

	_cooldown = max(0.0, _cooldown - delta)
	_slide_cd = max(0.0, _slide_cd - delta)
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			ammo = mag_size

	if _flash_t > 0.0:
		_flash_t -= delta
		_flash.visible = _flash_t > 0.0
	_recoil = max(0.0, _recoil - delta * 9.0)
	_gun.translation = GUN_POS + Vector3(0, 0, _recoil * 0.07)
	_gun.rotation.x = gun_pitch + _recoil * 0.05

	think(delta)
	_move(delta)
	_animate(delta)


func _move(delta: float) -> void:
	var on_floor := is_on_floor()
	if sliding:
		_slide_t -= delta
		var f: float = clamp(_slide_t / SLIDE_TIME, 0.0, 1.0)
		var sp: float = lerp(move_speed * 0.6, move_speed * 1.7, f)
		velocity.x = _slide_dir.x * sp
		velocity.z = _slide_dir.z * sp
		if _slide_t <= 0.0 or want_jump:
			_end_slide()
	else:
		var target := wish_dir * move_speed
		var k: float = clamp(12.0 * delta, 0.0, 1.0)
		velocity.x = lerp(velocity.x, target.x, k)
		velocity.z = lerp(velocity.z, target.z, k)
	velocity.y += GRAVITY * delta
	if want_jump and on_floor:
		velocity.y = JUMP_SPEED
	want_jump = false
	velocity = move_and_slide(velocity, Vector3.UP, true)


func _animate(delta: float) -> void:
	var h := Vector3(velocity.x, 0.0, velocity.z)
	var st: int = skin.States.IDLE
	if not is_on_floor():
		st = skin.States.AIR
	elif h.length() > 0.6:
		st = skin.States.RUN
	skin.move_direction = Vector3(0, 0, min(1.0, h.length() / move_speed))
	if st != _anim_state:
		_anim_state = st
		skin.is_moving = (st == skin.States.RUN)
		skin.transition_to(st)
	_anim_acc += delta
	if _anim_acc >= ANIM_STEP:
		skin.animation_tree.advance(_anim_acc)
		_anim_acc = 0.0


# ---- slide -----------------------------------------------------------------
func start_slide() -> void:
	if sliding or not alive or _slide_cd > 0.0 or not is_on_floor():
		return
	var h := Vector3(velocity.x, 0.0, velocity.z)
	if h.length() > 1.0:
		_slide_dir = h.normalized()
	else:
		var fwd := -global_transform.basis.z
		fwd.y = 0.0
		_slide_dir = fwd.normalized()
	sliding = true
	_slide_t = SLIDE_TIME
	_set_slide_pose(true)


func _end_slide() -> void:
	sliding = false
	_slide_cd = SLIDE_COOLDOWN
	_set_slide_pose(false)


func _set_slide_pose(on: bool) -> void:
	_cap.height = 0.3 if on else 1.2
	_shape.translation = Vector3(0, 0.45 if on else 0.9, 0)
	_marker.translation = Vector3(0, 1.3 if on else 2.2, 0)
	if on:
		skin.rotation_degrees = SLIDE_SKIN_ROT
		skin.translation = SLIDE_SKIN_POS
	else:
		skin.rotation_degrees = Vector3(0, 180, 0)
		skin.translation = NORMAL_SKIN_POS


func head_position() -> Vector3:
	return global_transform.origin + Vector3(0, 0.75 if sliding else 1.62, 0)


func is_head(hit_y: float) -> bool:
	return (hit_y - global_transform.origin.y) > (0.65 if sliding else 1.5)


# ---- weapon ----------------------------------------------------------------
func is_reloading() -> bool:
	return _reload_left > 0.0


func can_fire() -> bool:
	return alive and _cooldown <= 0.0 and _reload_left <= 0.0 and ammo > 0


func start_reload() -> void:
	if _reload_left <= 0.0 and ammo < mag_size:
		_reload_left = reload_time


func fire_toward(target_point: Vector3, muzzle: Vector3) -> void:
	if not can_fire():
		if ammo <= 0:
			start_reload()
		return
	_cooldown = fire_interval
	ammo -= 1
	var dir := _apply_spread((target_point - muzzle).normalized())
	_flash_t = 0.05
	_recoil = 1.0
	if game != null:
		game.spawn_bullet(self, muzzle, dir, bullet_speed, damage)
	if ammo <= 0:
		start_reload()


func _apply_spread(dir: Vector3) -> Vector3:
	if spread <= 0.0:
		return dir
	var ref := Vector3.UP if abs(dir.y) < 0.99 else Vector3.RIGHT
	var right := dir.cross(ref).normalized()
	var up := right.cross(dir).normalized()
	var a := rand_range(0.0, TAU)
	var r := rand_range(0.0, spread)
	return (dir + right * cos(a) * r + up * sin(a) * r).normalized()


func muzzle_position() -> Vector3:
	return _gun.global_transform.xform(Vector3(0, 0.02, -0.7))


# ---- health ----------------------------------------------------------------
func take_damage(amount: float, attacker, headshot := false) -> void:
	if not alive or invuln > 0.0:
		return
	if attacker != null and attacker.team == team:
		return
	hp -= amount
	_since_hit = 0.0
	on_damaged(attacker)
	var killed := hp <= 0.0
	if game != null:
		game.report_hit(attacker, self, headshot, killed)
	if killed:
		_die(attacker, headshot)


func _die(attacker, headshot: bool) -> void:
	if sliding:
		_end_slide()
	alive = false
	hp = 0.0
	respawn_left = game.respawn_delay if game != null else 3.0
	skin.visible = false
	_gun.visible = false
	_marker.visible = false
	_shape.set_deferred("disabled", true)
	velocity = Vector3.ZERO
	wish_dir = Vector3.ZERO
	if game != null:
		game.on_kill(attacker, self, headshot)


func respawn_at(pos: Vector3, yaw: float) -> void:
	translation = pos
	rotation.y = yaw
	hp = MAX_HP
	alive = true
	ammo = mag_size
	_reload_left = 0.0
	_cooldown = 0.0
	_since_hit = 99.0
	invuln = 2.0
	velocity = Vector3.ZERO
	skin.visible = true
	_gun.visible = true
	_marker.visible = show_marker
	_shape.set_deferred("disabled", false)
	on_respawned()
