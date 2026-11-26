extends KinematicBody
# Base class for every combatant (human player, bots, online puppets).
# Inventory based: you start unarmed in battle royale and pick weapons up.

const MannequinScene = preload("res://src/Player/Mannequiny.tscn")
const W = preload("res://src/Game/Weapons.gd")
const CharLib = preload("res://src/Game/CharacterLib.gd")

enum Stance { STAND, CROUCH, PRONE }

const GRAVITY := -32.0
const JUMP_SPEED := 9.5
const MAX_HP := 100.0
const ANIM_STEP := 0.05
const SLIDE_TIME := 0.75
const SLIDE_COOLDOWN := 0.8
const MANNEQUIN_POS = Vector3(0, 0, 0.222992)
const LYING_ROT = Vector3(-75, 180, 0)
const LYING_POS = Vector3(0, 0.1, -0.6)

# per stance: [stand, crouch, prone]
const STANCE_SPEED := [1.0, 0.55, 0.28]
const STANCE_CAP_H := [1.2, 0.5, 0.1]
const STANCE_CAP_Y := [0.9, 0.55, 0.4]
const STANCE_HEAD_Y := [1.62, 1.1, 0.5]
const STANCE_HEADHIT := [1.5, 1.0, 0.42]
const STANCE_GUN_Y := [1.12, 0.8, 0.45]
const STANCE_MARKER_Y := [2.2, 1.7, 1.1]
const STANCE_SPREAD := [1.0, 0.75, 0.55]
const STEP_STRIDE := [2.0, 1.6, 1.1]
const STEP_HEAR := [28.0, 13.0, 6.0]

var game
var team := 0
var display_name := "Fighter"
var char_name := "Mannequin"
var net_id := 0
var is_puppet := false        # online remote player (visual only)
var is_local := false

var hp := MAX_HP
var alive := true
var invuln := 0.0
var respawn_left := 0.0
var _since_hit := 99.0

var skin
var _custom := false
var _skin_pos := MANNEQUIN_POS
var _shape: CollisionShape
var _cap: CapsuleShape
var _marker: MeshInstance
var _gun: Spatial
var _models := {}
var _flash: MeshInstance
var _anim_state := -1
var show_marker := true
var _anim_acc := 0.0
var _flash_t := 0.0
var _recoil := 0.0
var gun_pitch := 0.0
var _gun_base := Vector3(0.22, 1.12, -0.38)

var move_speed := 7.0
var velocity := Vector3.ZERO
var wish_dir := Vector3.ZERO
var want_jump := false
var sliding := false
var stance: int = Stance.STAND
var _slide_t := 0.0
var _slide_cd := 0.0
var _slide_dir := Vector3.ZERO
var _stride := 0.0

# weapons
var inv := {}              # name -> {"ammo": int, "reserve": int}
var cur := ""              # current weapon, "" = unarmed
var damage_mul := 1.0      # bots deal less damage
var speed_mul := 1.0       # bots shoot slower projectiles
var extra_spread := 0.0
var _cooldown := 0.0
var _reload_left := 0.0
var _reload_w := ""


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

	var custom = null
	if char_name != "" and char_name != CharLib.DEFAULT_NAME:
		custom = CharLib.make(char_name)
	if custom != null:
		skin = custom
		_custom = true
		_skin_pos = Vector3.ZERO
	else:
		skin = MannequinScene.instance()
		_skin_pos = MANNEQUIN_POS
	skin.rotation_degrees = Vector3(0, 180, 0)
	skin.translation = _skin_pos
	add_child(skin)
	if not _custom:
		skin.animation_tree.process_mode = AnimationTree.ANIMATION_PROCESS_MANUAL
		_tint_skin()
	_anim_acc = randf() * ANIM_STEP

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
		mm.flags_no_depth_test = true
	_marker.material_override = mm
	_marker.translation = Vector3(0, 2.2, 0)
	add_child(_marker)

	_build_gun()
	setup()
	_update_models()


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


# ---------------------------------------------------------------- weapon models
func _box(parent: Spatial, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance.new()
	var bm := CubeMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.translation = pos
	parent.add_child(mi)


func _build_gun() -> void:
	_gun = Spatial.new()
	_gun.translation = _gun_base
	add_child(_gun)
	var dark := SpatialMaterial.new()
	dark.albedo_color = Color(0.09, 0.09, 0.11)
	var green := SpatialMaterial.new()
	green.albedo_color = Color(0.2, 0.32, 0.18)
	var olive := SpatialMaterial.new()
	olive.albedo_color = Color(0.3, 0.33, 0.2)

	var rifle := Spatial.new()
	_box(rifle, Vector3(0, 0, 0), Vector3(0.07, 0.10, 0.55), dark)
	_box(rifle, Vector3(0, 0.02, -0.42), Vector3(0.035, 0.035, 0.32), dark)
	_box(rifle, Vector3(0, -0.13, 0.05), Vector3(0.05, 0.17, 0.08), dark)
	_box(rifle, Vector3(0, -0.02, 0.33), Vector3(0.06, 0.12, 0.18), dark)
	_models["rifle"] = rifle

	var pistol := Spatial.new()
	_box(pistol, Vector3(0, 0, -0.05), Vector3(0.05, 0.08, 0.24), dark)
	_box(pistol, Vector3(0, -0.09, 0.04), Vector3(0.045, 0.12, 0.06), dark)
	_models["pistol"] = pistol

	var rpg := Spatial.new()
	var tube := MeshInstance.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.06
	cyl.height = 0.95
	cyl.radial_segments = 8
	tube.mesh = cyl
	tube.material_override = olive
	tube.rotation_degrees = Vector3(90, 0, 0)
	rpg.add_child(tube)
	_box(rpg, Vector3(0, -0.12, 0.05), Vector3(0.05, 0.16, 0.07), dark)
	var head := MeshInstance.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.1
	cone.height = 0.22
	cone.radial_segments = 8
	head.mesh = cone
	head.material_override = green
	head.rotation_degrees = Vector3(-90, 0, 0)
	head.translation = Vector3(0, 0, -0.55)
	rpg.add_child(head)
	_models["rpg"] = rpg

	var gren := Spatial.new()
	var gm := MeshInstance.new()
	var sph := SphereMesh.new()
	sph.radius = 0.07
	sph.height = 0.14
	sph.radial_segments = 8
	sph.rings = 4
	gm.mesh = sph
	gm.material_override = green
	gren.add_child(gm)
	_models["grenade"] = gren

	for k in _models:
		_models[k].visible = false
		_gun.add_child(_models[k])

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


func _update_models() -> void:
	for k in _models:
		_models[k].visible = (k == cur)
	_gun.visible = (cur != "") and alive and skin.visible
	var z := -0.68
	if cur == "pistol":
		z = -0.3
	elif cur == "rpg":
		z = -1.05
	_flash.translation = Vector3(0, 0.02, z)


# ---------------------------------------------------------------- hooks
func setup() -> void:
	pass


func think(_delta: float) -> void:
	pass


func on_damaged(_attacker) -> void:
	pass


func on_respawned() -> void:
	pass


# ---------------------------------------------------------------- main loop
func _physics_process(delta: float) -> void:
	if game != null and game.frozen:
		return
	if not alive:
		respawn_left -= delta
		if respawn_left <= 0.0 and game != null:
			game.respawn_fighter(self)
		return

	if invuln > 0.0:
		invuln -= delta
		skin.visible = invuln <= 0.0 or int(invuln * 12.0) % 2 == 0
		_update_models()

	_since_hit += delta
	if hp < MAX_HP and _since_hit > 4.0 and not is_puppet:
		hp = min(MAX_HP, hp + 15.0 * delta)

	_cooldown = max(0.0, _cooldown - delta)
	_slide_cd = max(0.0, _slide_cd - delta)
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()

	if _flash_t > 0.0:
		_flash_t -= delta
		_flash.visible = _flash_t > 0.0
	_recoil = max(0.0, _recoil - delta * 9.0)
	_gun.translation = _gun_base + Vector3(0, 0, _recoil * 0.07)
	_gun.rotation.x = gun_pitch + _recoil * 0.05

	think(delta)
	_move(delta)
	_footsteps(delta)
	_animate(delta)


func current_pose() -> int:
	return Stance.PRONE if sliding else stance


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
		var target := wish_dir * move_speed * STANCE_SPEED[stance]
		var k: float = clamp(12.0 * delta, 0.0, 1.0)
		velocity.x = lerp(velocity.x, target.x, k)
		velocity.z = lerp(velocity.z, target.z, k)
	velocity.y += GRAVITY * delta
	if want_jump and on_floor:
		if stance != Stance.STAND:
			set_stance(Stance.STAND)
		else:
			velocity.y = JUMP_SPEED
			if game != null:
				Sfx.play_at("jump", global_transform.origin, 20.0)
	want_jump = false
	var was_air := not on_floor
	velocity = move_and_slide(velocity, Vector3.UP, true)
	if was_air and is_on_floor() and velocity.y <= 0.0:
		Sfx.play_at("land", global_transform.origin, 25.0)


func _footsteps(delta: float) -> void:
	var grounded: bool = is_puppet or is_on_floor()
	var h := Vector3(velocity.x, 0.0, velocity.z).length()
	if sliding or not grounded or h < 1.0:
		return
	_stride += h * delta
	var pose: int = stance
	if _stride >= STEP_STRIDE[pose]:
		_stride = 0.0
		var ratio: float = clamp(h / max(move_speed * STANCE_SPEED[pose], 0.1), 0.4, 1.0)
		Sfx.play_at("footstep", global_transform.origin, STEP_HEAR[pose] * ratio)


func _animate(delta: float) -> void:
	var grounded: bool = is_puppet or is_on_floor()
	var h := Vector3(velocity.x, 0.0, velocity.z)
	var st := 0   # 0 idle, 1 run, 2 air
	if not grounded:
		st = 2
	elif h.length() > 0.6:
		st = 1
	if _custom:
		if st != _anim_state:
			_anim_state = st
			var ap = skin.get_meta("anim")
			if ap != null:
				var keys := ["idle", "stand"]
				if st == 1:
					keys = ["run", "walk", "jog", "sprint"]
				elif st == 2:
					keys = ["jump", "fall", "air"]
				var an: String = CharLib.pick_anim(ap, keys)
				if an == "" and st == 2:
					an = CharLib.pick_anim(ap, ["idle", "stand"])
				if an != "":
					ap.get_animation(an).loop = true
					ap.play(an)
		return
	var ms: int = skin.States.IDLE
	if st == 2:
		ms = skin.States.AIR
	elif st == 1:
		ms = skin.States.RUN
	skin.move_direction = Vector3(0, 0, min(1.0, h.length() / move_speed))
	if ms != _anim_state:
		_anim_state = ms
		skin.is_moving = (ms == skin.States.RUN)
		skin.transition_to(ms)
	_anim_acc += delta
	if _anim_acc >= ANIM_STEP:
		skin.animation_tree.advance(_anim_acc)
		_anim_acc = 0.0


# ---------------------------------------------------------------- stance / slide
func set_stance(s: int) -> void:
	if s == stance or not alive:
		return
	if s < stance and not _has_headroom(s):
		return
	stance = s
	_apply_pose()
	Sfx.play_at("crouch", global_transform.origin, 15.0)


func _has_headroom(target: int) -> bool:
	var o := global_transform.origin
	var need: float = STANCE_HEAD_Y[target] + 0.25
	var hit := get_world().direct_space_state.intersect_ray(o + Vector3(0, 0.3, 0), o + Vector3(0, need, 0), [self], 1)
	return hit.empty()


func _apply_pose() -> void:
	var pose: int = current_pose()
	_cap.height = STANCE_CAP_H[pose]
	_shape.translation = Vector3(0, STANCE_CAP_Y[pose], 0)
	_marker.translation = Vector3(0, STANCE_MARKER_Y[pose], 0)
	_gun_base = Vector3(0.22, STANCE_GUN_Y[pose], -0.38)
	if pose == Stance.PRONE:
		skin.rotation_degrees = LYING_ROT
		skin.translation = LYING_POS
		skin.scale = Vector3.ONE
	else:
		skin.rotation_degrees = Vector3(0, 180, 0)
		skin.translation = _skin_pos
		skin.scale = Vector3(1, 0.74 if pose == Stance.CROUCH else 1.0, 1)


func start_slide() -> void:
	if sliding or not alive or _slide_cd > 0.0 or not is_on_floor():
		return
	if stance != Stance.STAND:
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
	_apply_pose()
	Sfx.play_at("slide", global_transform.origin, 25.0)


func _end_slide() -> void:
	sliding = false
	_slide_cd = SLIDE_COOLDOWN
	_apply_pose()


func head_position() -> Vector3:
	return global_transform.origin + Vector3(0, STANCE_HEAD_Y[current_pose()], 0)


func is_head(hit_y: float) -> bool:
	return (hit_y - global_transform.origin.y) > STANCE_HEADHIT[current_pose()]


# ---------------------------------------------------------------- inventory
func has_weapon(n: String) -> bool:
	return inv.has(n)


func give_weapon(n: String) -> void:
	var d: Dictionary = W.DEFS[n]
	if inv.has(n):
		if d["kind"] == "throw":
			inv[n]["ammo"] += int(d["count"])
		else:
			inv[n]["reserve"] += int(d["pickup_reserve"])
	elif d["kind"] == "throw":
		inv[n] = {"ammo": int(d["count"]), "reserve": 0}
	else:
		inv[n] = {"ammo": int(d["mag"]), "reserve": int(d["pickup_reserve"])}
	if cur == "" or (cur == "pistol" and n != "grenade"):
		select_weapon(n)


func select_weapon(n: String) -> void:
	if not inv.has(n) or n == cur:
		return
	cur = n
	_reload_left = 0.0
	_cooldown = 0.3
	_update_models()
	Sfx.play_at("weapon_switch", global_transform.origin, 25.0)
	if game != null:
		game.on_weapon_changed(self)


# used for online puppets to just show a model
func show_weapon(n: String) -> void:
	cur = n
	_update_models()


func drop_current_if_empty() -> void:
	if cur != "" and inv.has(cur):
		var d: Dictionary = W.DEFS[cur]
		if d["kind"] == "throw" and inv[cur]["ammo"] <= 0:
			inv.erase(cur)
			cur = ""
			for n in W.ORDER:
				if inv.has(n):
					cur = n
					break
			_update_models()


func apply_pickup(kind: String) -> bool:
	if W.DEFS.has(kind):
		give_weapon(kind)
		return true
	if kind == "medkit":
		if hp >= MAX_HP:
			return false
		hp = min(MAX_HP, hp + W.MEDKIT_HEAL)
		return true
	if kind == "ammo":
		var any := false
		for n in inv:
			var d: Dictionary = W.DEFS[n]
			if d["kind"] == "gun":
				inv[n]["reserve"] += int(d["mag"])
				any = true
			elif d["kind"] == "rocket":
				inv[n]["reserve"] += 1
				any = true
		return any
	return false


func ammo_text() -> String:
	if cur == "":
		return "UNARMED"
	var d: Dictionary = W.DEFS[cur]
	var st: Dictionary = inv[cur]
	if d["kind"] == "throw":
		return "x%d" % st["ammo"]
	return "%d / %d" % [st["ammo"], st["reserve"]]


# ---------------------------------------------------------------- shooting
func is_reloading() -> bool:
	return _reload_left > 0.0


func can_fire() -> bool:
	if not alive or cur == "" or _cooldown > 0.0 or _reload_left > 0.0:
		return false
	return inv[cur]["ammo"] > 0


func start_reload() -> void:
	if cur == "" or _reload_left > 0.0:
		return
	var d: Dictionary = W.DEFS[cur]
	if d["kind"] == "throw":
		return
	var st: Dictionary = inv[cur]
	if st["ammo"] >= int(d["mag"]) or st["reserve"] <= 0:
		return
	_reload_left = float(d["reload"])
	_reload_w = cur
	Sfx.play_at(String(d["reload_snd"]), global_transform.origin, 30.0)
	if game != null:
		game.on_reload(self, cur)


func _finish_reload() -> void:
	if not inv.has(_reload_w) or _reload_w != cur:
		return
	var d: Dictionary = W.DEFS[_reload_w]
	var st: Dictionary = inv[_reload_w]
	var need: int = int(d["mag"]) - int(st["ammo"])
	var take: int = int(min(need, st["reserve"]))
	st["ammo"] += take
	st["reserve"] -= take


func fire_toward(target_point: Vector3, muzzle: Vector3) -> void:
	if cur == "" or not alive:
		return
	if _cooldown > 0.0 or _reload_left > 0.0:
		return
	var d: Dictionary = W.DEFS[cur]
	var st: Dictionary = inv[cur]
	if st["ammo"] <= 0:
		if d["kind"] != "throw":
			if st["reserve"] > 0:
				start_reload()
			else:
				_cooldown = 0.4
				Sfx.play_at("empty_click", muzzle, 20.0)
		return
	var wname := cur
	_cooldown = float(d["interval"])
	st["ammo"] -= 1
	var dir := (target_point - muzzle).normalized()
	var kind: String = d["kind"]
	if kind == "gun":
		dir = _apply_spread(dir, float(d["spread"]) * STANCE_SPREAD[current_pose()] + extra_spread)
		_flash_t = 0.05
		_recoil = 1.0
		if game != null:
			game.spawn_bullet(self, muzzle, dir, float(d["speed"]) * speed_mul, float(d["damage"]) * damage_mul, float(d["range"]), wname)
	elif kind == "rocket":
		_flash_t = 0.08
		_recoil = 1.5
		if game != null:
			game.spawn_rocket(self, muzzle, dir, wname)
	else:
		if game != null:
			game.throw_grenade(self, muzzle, dir, wname)
	Sfx.play_at(String(d["shot"]), muzzle, float(d["hear"]))
	if game != null:
		game.on_fire(self, wname, muzzle, dir)
	if kind == "throw":
		drop_current_if_empty()
	elif st["ammo"] <= 0:
		start_reload()


func remote_fire(wname: String) -> void:
	_flash_t = 0.06
	_recoil = 1.0
	var d: Dictionary = W.DEFS[wname]
	Sfx.play_at(String(d["shot"]), muzzle_position(), float(d["hear"]))


func _apply_spread(dir: Vector3, spread: float) -> Vector3:
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


# ---------------------------------------------------------------- health
func take_damage(amount: float, attacker, headshot := false) -> void:
	if is_puppet or not alive or invuln > 0.0:
		return
	if attacker != null and attacker != self and attacker.team == team:
		return
	hp -= amount
	_since_hit = 0.0
	on_damaged(attacker)
	if is_local:
		Sfx.play_ui("hurt")
	else:
		Sfx.play_at("hurt", global_transform.origin, 30.0)
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
	Sfx.play_at("death", global_transform.origin, 45.0)
	if game != null:
		game.on_kill(attacker, self, headshot)


func net_die() -> void:
	alive = false
	hp = 0.0
	skin.visible = false
	_gun.visible = false
	_marker.visible = false
	_shape.set_deferred("disabled", true)
	Sfx.play_at("death", global_transform.origin, 45.0)


func respawn_at(pos: Vector3, yaw: float) -> void:
	translation = pos
	rotation.y = yaw
	hp = MAX_HP
	alive = true
	for n in inv:
		var d: Dictionary = W.DEFS[n]
		inv[n]["ammo"] = int(d["count"]) if d["kind"] == "throw" else int(d["mag"])
	_reload_left = 0.0
	_cooldown = 0.0
	_since_hit = 99.0
	invuln = 2.0
	velocity = Vector3.ZERO
	stance = Stance.STAND
	_apply_pose()
	skin.visible = true
	_marker.visible = show_marker
	_shape.set_deferred("disabled", false)
	_update_models()
	on_respawned()
