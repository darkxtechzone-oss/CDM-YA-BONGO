extends Node
# Match manager: builds the world, spawns 4v4, tracks score/time, respawns,
# and simulates bullets (visible coloured projectiles - damage only on contact).

const ArenaScript = preload("res://src/Game/Arena.gd")
const HudScript = preload("res://src/Game/Hud.gd")
const PlayerScript = preload("res://src/Game/HumanPlayer.gd")
const BotScript = preload("res://src/Game/Bot.gd")

const USE_SHADOWS := false
const TEAM_SIZE := 4
const KILLS_TO_WIN := 30
const MATCH_TIME := 300.0
const BULLET_POOL := 96
const SPARK_POOL := 24

var respawn_delay := 3.0
var bot_skill := 1.0
var arena
var hud
var player
var scores := [0, 0]
var time_left := MATCH_TIME
var running := false

var _team_fighters := [[], []]
var _bullets := []
var _bullet_i := 0
var _bullet_mats := []
var _sparks := []
var _spark_until := []
var _spark_i := 0
var _spark_mat: SpatialMaterial
var _blue_names := ["Alpha", "Bravo", "Charlie"]
var _red_names := ["Viper", "Raven", "Wolf", "Hawk"]


func _ready() -> void:
	randomize()
	OS.keep_screen_on = true
	_setup_world()

	arena = ArenaScript.new()
	add_child(arena)

	# camera shown behind the menu
	var menu_cam := Camera.new()
	add_child(menu_cam)
	menu_cam.look_at_from_position(Vector3(0, 24, 38), Vector3(0, 0, 0), Vector3.UP)
	menu_cam.current = true

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HudScript.new()
	layer.add_child(hud)
	hud.connect("start_requested", self, "start_match")
	hud.connect("restart_requested", self, "_on_restart")


func _setup_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.72, 0.9)
	env.ambient_light_color = Color(0.8, 0.84, 0.92)
	env.ambient_light_energy = 0.85
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = USE_SHADOWS
	add_child(sun)

	_make_pools()


# ---------------------------------------------------------------- match flow
func start_match(skill: float) -> void:
	bot_skill = skill
	scores = [0, 0]
	time_left = MATCH_TIME
	running = true

	player = _make_fighter(PlayerScript, 0, "You", 0)
	for i in range(TEAM_SIZE - 1):
		_make_fighter(BotScript, 0, _blue_names[i], i + 1)
	for i in range(TEAM_SIZE):
		_make_fighter(BotScript, 1, _red_names[i], i)
	hud.begin_match(player)


func _make_fighter(script, team: int, fname: String, idx: int):
	var f = script.new()
	f.team = team
	f.display_name = fname
	f.game = self
	if script == PlayerScript:
		f.hud = hud
	f.translation = arena.spawns[team][idx % arena.spawns[team].size()]
	f.rotation.y = arena.spawn_yaw[team]
	_team_fighters[team].append(f)
	add_child(f)
	return f


func _process(_delta: float) -> void:
	_expire_sparks()
	if not running:
		return
	time_left -= _delta
	hud.update_scores(scores, time_left)
	if time_left <= 0.0:
		end_match()


func respawn_fighter(f) -> void:
	if not running:
		return
	var best: Vector3 = arena.spawns[f.team][0]
	var best_d := -1.0
	for p in arena.spawns[f.team]:
		var nearest := 1e9
		for o in get_tree().get_nodes_in_group("fighters"):
			if o != f and o.alive:
				nearest = min(nearest, p.distance_to(o.global_transform.origin))
		nearest += rand_range(0.0, 3.0)
		if nearest > best_d:
			best_d = nearest
			best = p
	f.respawn_at(best, arena.spawn_yaw[f.team])


func report_hit(attacker, _victim, head: bool, killed: bool) -> void:
	if attacker != null and attacker == player:
		hud.hit_marker(killed, head)


func on_kill(attacker, victim, head: bool) -> void:
	if attacker != null and attacker != victim:
		scores[attacker.team] += 1
		hud.add_feed(attacker.display_name, attacker.team, victim.display_name, head)
	hud.update_scores(scores, time_left)
	if scores[0] >= KILLS_TO_WIN or scores[1] >= KILLS_TO_WIN:
		end_match()


func end_match() -> void:
	if not running:
		return
	running = false
	for f in get_tree().get_nodes_in_group("fighters"):
		f.set_physics_process(false)
	var title := "DRAW"
	if scores[0] > scores[1]:
		title = "VICTORY"
	elif scores[0] < scores[1]:
		title = "DEFEAT"
	hud.show_end(title, "BLUE %d  -  %d RED" % [scores[0], scores[1]])


func _on_restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


# ---------------------------------------------------------------- bullets
func _make_pools() -> void:
	for c in [Color(0.35, 0.9, 1.0), Color(1.0, 0.35, 0.15)]:
		var m := SpatialMaterial.new()
		m.flags_unshaded = true
		m.albedo_color = c
		_bullet_mats.append(m)
	_spark_mat = SpatialMaterial.new()
	_spark_mat.flags_unshaded = true
	_spark_mat.albedo_color = Color(1.0, 0.8, 0.3)

	var cm := CubeMesh.new()
	cm.size = Vector3(1, 1, 1)
	for i in range(BULLET_POOL):
		var mi := MeshInstance.new()
		mi.mesh = cm
		mi.visible = false
		add_child(mi)
		_bullets.append({
			"mi": mi, "active": false, "pos": Vector3.ZERO, "dir": Vector3(0, 0, -1),
			"speed": 0.0, "who": null, "dmg": 0.0, "left": 0.0, "ex": []
		})

	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	sm.radial_segments = 6
	sm.rings = 3
	for i in range(SPARK_POOL):
		var sp := MeshInstance.new()
		sp.mesh = sm
		sp.material_override = _spark_mat
		sp.visible = false
		add_child(sp)
		_sparks.append(sp)
		_spark_until.append(0)


func spawn_bullet(who, pos: Vector3, dir: Vector3, speed: float, dmg: float) -> void:
	var b = _bullets[_bullet_i]
	_bullet_i = (_bullet_i + 1) % BULLET_POOL
	b["active"] = true
	b["pos"] = pos
	b["dir"] = dir
	b["speed"] = speed
	b["who"] = who
	b["dmg"] = dmg
	b["left"] = 100.0
	b["ex"] = _team_fighters[who.team]
	var mi: MeshInstance = b["mi"]
	mi.material_override = _bullet_mats[who.team]
	mi.visible = true
	_place_bullet(b)


func _place_bullet(b) -> void:
	var dir: Vector3 = b["dir"]
	var pos: Vector3 = b["pos"]
	var up := Vector3.UP if abs(dir.y) < 0.99 else Vector3.RIGHT
	var center := pos - dir * 0.6
	var t := Transform(Basis.IDENTITY, center).looking_at(center + dir, up)
	t.basis = t.basis.scaled(Vector3(0.07, 0.07, 1.2))
	var mi: MeshInstance = b["mi"]
	mi.transform = t


func _deactivate(b) -> void:
	b["active"] = false
	var mi: MeshInstance = b["mi"]
	mi.visible = false


func _physics_process(delta: float) -> void:
	var space := get_viewport().world.direct_space_state
	for b in _bullets:
		if not b["active"]:
			continue
		var dir: Vector3 = b["dir"]
		var step: float = b["speed"] * delta
		var from: Vector3 = b["pos"]
		var to: Vector3 = from + dir * step
		var hit := space.intersect_ray(from, to, b["ex"], 3)
		if hit:
			_bullet_hit(b, hit)
			_deactivate(b)
			continue
		b["pos"] = to
		b["left"] -= step
		if b["left"] <= 0.0:
			_deactivate(b)
		else:
			_place_bullet(b)


func _bullet_hit(b, hit: Dictionary) -> void:
	_spark(hit.position)
	if not running:
		return
	var c = hit.collider
	if c != null and c.has_method("take_damage"):
		var head: bool = c.is_head(hit.position.y)
		var dmg: float = b["dmg"]
		c.take_damage(dmg * (2.0 if head else 1.0), b["who"], head)


func _spark(pos: Vector3) -> void:
	var s: MeshInstance = _sparks[_spark_i]
	s.translation = pos
	s.visible = true
	_spark_until[_spark_i] = OS.get_ticks_msec() + 90
	_spark_i = (_spark_i + 1) % SPARK_POOL


func _expire_sparks() -> void:
	var now := OS.get_ticks_msec()
	for i in range(SPARK_POOL):
		if _spark_until[i] != 0 and now >= _spark_until[i]:
			_spark_until[i] = 0
			_sparks[i].visible = false
