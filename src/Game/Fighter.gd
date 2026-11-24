extends KinematicBody
# Base class for every combatant (human player and bots).
# Subclasses override setup(), think(delta), on_damaged(), on_respawned().

const MannequinScene = preload("res://src/Player/Mannequiny.tscn")

const GRAVITY := -32.0
const JUMP_SPEED := 9.5
const MAX_HP := 100.0

var game          # Main node
var team := 0     # 0 = blue (player team), 1 = red
var display_name := "Fighter"

var hp := MAX_HP
var alive := true
var invuln := 0.0
var respawn_left := 0.0

var skin
var _shape: CollisionShape
var _marker: MeshInstance
var _anim_state := -1
var show_marker := true

# Movement (set by subclasses in think())
var move_speed := 7.0
var velocity := Vector3.ZERO
var wish_dir := Vector3.ZERO
var want_jump := false

# Weapon
var damage := 22.0
var fire_interval := 0.1
var mag_size := 30
var ammo := 30
var reload_time := 1.8
var spread := 0.02
var weapon_range := 90.0
var _cooldown := 0.0
var _reload_left := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 2
	add_to_group("fighters")

	_shape = CollisionShape.new()
	var cap := CapsuleShape.new()
	cap.radius = 0.3
	cap.height = 1.2
	_shape.shape = cap
	_shape.rotation_degrees = Vector3(90, 0, 0)
	_shape.translation = Vector3(0, 0.9, 0)
	add_child(_shape)

	skin = MannequinScene.instance()
	skin.rotation_degrees = Vector3(0, 180, 0)
	skin.translation = Vector3(0, 0, 0.222992)
	add_child(skin)
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

	_cooldown = max(0.0, _cooldown - delta)
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			ammo = mag_size

	think(delta)
	_move(delta)
	_animate()


func _move(delta: float) -> void:
	var on_floor := is_on_floor()
	var target := wish_dir * move_speed
	var k: float = clamp(12.0 * delta, 0.0, 1.0)
	velocity.x = lerp(velocity.x, target.x, k)
	velocity.z = lerp(velocity.z, target.z, k)
	velocity.y += GRAVITY * delta
	if want_jump and on_floor:
		velocity.y = JUMP_SPEED
	want_jump = false
	velocity = move_and_slide(velocity, Vector3.UP, true)


func _animate() -> void:
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


# ---- weapon ----------------------------------------------------------------
func is_reloading() -> bool:
	return _reload_left > 0.0


func can_fire() -> bool:
	return alive and _cooldown <= 0.0 and _reload_left <= 0.0 and ammo > 0


func start_reload() -> void:
	if _reload_left <= 0.0 and ammo < mag_size:
		_reload_left = reload_time


func fire_at(origin: Vector3, dir: Vector3, muzzle: Vector3) -> void:
	if not can_fire():
		if ammo <= 0:
			start_reload()
		return
	_cooldown = fire_interval
	ammo -= 1
	var d := _apply_spread(dir)
	var to := origin + d * weapon_range
	var hit := get_world().direct_space_state.intersect_ray(origin, to, [self], 3)
	var end := to
	if hit:
		end = hit.position
		var c = hit.collider
		if c != null and c.has_method("take_damage"):
			var head: bool = (hit.position.y - c.global_transform.origin.y) > 1.5
			c.take_damage(damage * (2.0 if head else 1.0), self, head)
	if game != null:
		game.spawn_tracer(muzzle, end)
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
	return global_transform.xform(Vector3(0.25, 1.3, -0.7))


# ---- health ----------------------------------------------------------------
func take_damage(amount: float, attacker, headshot := false) -> void:
	if not alive or invuln > 0.0:
		return
	if attacker != null and attacker.team == team:
		return
	hp -= amount
	on_damaged(attacker)
	var killed := hp <= 0.0
	if game != null:
		game.report_hit(attacker, self, headshot, killed)
	if killed:
		_die(attacker, headshot)


func _die(attacker, headshot: bool) -> void:
	alive = false
	hp = 0.0
	respawn_left = game.respawn_delay if game != null else 3.0
	skin.visible = false
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
	invuln = 2.0
	velocity = Vector3.ZERO
	skin.visible = true
	_marker.visible = show_marker
	_shape.set_deferred("disabled", false)
	on_respawned()
