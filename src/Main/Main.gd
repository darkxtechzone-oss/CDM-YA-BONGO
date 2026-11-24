extends Node
# Match manager: builds the world, spawns 4v4, tracks score/time, respawns.

const ArenaScript = preload("res://src/Game/Arena.gd")
const HudScript = preload("res://src/Game/Hud.gd")
const PlayerScript = preload("res://src/Game/HumanPlayer.gd")
const BotScript = preload("res://src/Game/Bot.gd")

const USE_SHADOWS := false
const TEAM_SIZE := 4
const KILLS_TO_WIN := 30
const MATCH_TIME := 300.0

var respawn_delay := 3.0
var bot_skill := 1.0
var arena
var hud
var player
var scores := [0, 0]
var time_left := MATCH_TIME
var running := false

var _tracer_mat: SpatialMaterial
var _spark_mat: SpatialMaterial
const POOL := 24
var _tracers := []
var _sparks := []
var _until := []
var _pool_i := 0
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

	_tracer_mat = SpatialMaterial.new()
	_tracer_mat.flags_unshaded = true
	_tracer_mat.albedo_color = Color(1.0, 0.9, 0.4)
	_spark_mat = SpatialMaterial.new()
	_spark_mat.flags_unshaded = true
	_spark_mat.albedo_color = Color(1.0, 0.7, 0.2)
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
	add_child(f)
	return f


func _process(delta: float) -> void:
	_expire_effects()
	if not running:
		return
	time_left -= delta
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
	get_tree().reload_current_scene()


# ---------------------------------------------------------------- effects
func _make_pools() -> void:
	var cm := CubeMesh.new()
	cm.size = Vector3(1, 1, 1)
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	sm.radial_segments = 6
	sm.rings = 3
	for i in range(POOL):
		var t := MeshInstance.new()
		t.mesh = cm
		t.material_override = _tracer_mat
		t.visible = false
		add_child(t)
		_tracers.append(t)
		var sp := MeshInstance.new()
		sp.mesh = sm
		sp.material_override = _spark_mat
		sp.visible = false
		add_child(sp)
		_sparks.append(sp)
		_until.append(0)


func _expire_effects() -> void:
	var now := OS.get_ticks_msec()
	for i in range(POOL):
		if _until[i] != 0 and now >= _until[i]:
			_until[i] = 0
			_tracers[i].visible = false
			_sparks[i].visible = false


func spawn_tracer(a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	if length < 0.5:
		return
	var dir := (b - a) / length
	var up := Vector3.UP if abs(dir.y) < 0.99 else Vector3.RIGHT
	var i := _pool_i
	_pool_i = (_pool_i + 1) % POOL
	var t := Transform(Basis.IDENTITY, (a + b) * 0.5).looking_at(b, up)
	t.basis = t.basis.scaled(Vector3(0.035, 0.035, length))
	_tracers[i].transform = t
	_tracers[i].visible = true
	_sparks[i].translation = b
	_sparks[i].visible = true
	_until[i] = OS.get_ticks_msec() + 60
