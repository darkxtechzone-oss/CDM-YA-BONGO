extends Node
# Match manager. Modes:
#   MODE_BR     battle royale vs bots (single player, works without a server)
#   MODE_ONLINE battle royale online (needs the node server, see /server)
#   MODE_TDM    the old 4v4 arena
# Handles: lobby stage, spawning, loot, bullets / rockets / grenades, zone,
# network messages, match end.

const ArenaScript = preload("res://src/Game/Arena.gd")
const BRMapScript = preload("res://src/Game/BRMap.gd")
const HudScript = preload("res://src/Game/Hud.gd")
const PlayerScript = preload("res://src/Game/HumanPlayer.gd")
const BotScript = preload("res://src/Game/Bot.gd")
const RemoteScript = preload("res://src/Game/RemoteFighter.gd")
const ZoneScript = preload("res://src/Game/Zone.gd")
const CharLib = preload("res://src/Game/CharacterLib.gd")
const MannequinScene = preload("res://src/Player/Mannequiny.tscn")
const W = preload("res://src/Game/Weapons.gd")

const MODE_BR := 0
const MODE_ONLINE := 1
const MODE_TDM := 2

const USE_SHADOWS := false
const TEAM_SIZE := 4
const KILLS_TO_WIN := 30
const MATCH_TIME := 300.0
const BR_BOTS := 9
const BULLET_POOL := 96
const SPARK_POOL := 24
const PICKUP_R := 1.7
const GRENADE_GRAVITY := -22.0
const MAP_HALF := 175.0

var respawn_delay := 3.0
var bot_skill := 1.0
var mode := MODE_BR
var arena
var hud
var player
var zone
var frozen := false
var running := false
var scores := [0, 0]
var time_left := MATCH_TIME
var pickups := []

var _freeze_left := 0.0
var _zone_t := 0.0
var _zs := {}
var _ring: MeshInstance
var _dmg_acc := 0.0
var _pick_acc := 0.0
var _net_acc := 0.0
var _last_shrink := -1
var _total := 1
var _puppets := {}
var _names := {}
var _connecting := false
var _conn_timer := 0.0
var _team_counter := 1

var _team_fighters := [[], []]
var _bullets := []
var _bullet_i := 0
var _bullet_mats := []
var _sparks := []
var _spark_until := []
var _spark_i := 0
var _spark_mat: SpatialMaterial
var _projs := []
var _fx := []
var _pk_mats := {}
var _pk_mesh: CubeMesh
var _stage: Spatial
var _preview: Spatial
var _preview_t := 0.0
var _menu_cam: Camera
var _blue_names := ["Alpha", "Bravo", "Charlie"]
var _red_names := ["Viper", "Raven", "Wolf", "Hawk"]
var _bot_names := ["Viper", "Raven", "Wolf", "Hawk", "Cobra", "Ghost", "Tiger", "Shadow", "Falcon", "Rhino", "Lynx", "Mamba"]


func _ready() -> void:
	randomize()
	OS.keep_screen_on = true
	_setup_world()

	_menu_cam = Camera.new()
	add_child(_menu_cam)
	_menu_cam.look_at_from_position(Vector3(2.4, 1.5, 4.2), Vector3(2.4, 1.0, 0), Vector3.UP)
	_menu_cam.current = true

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HudScript.new()
	hud.game = self
	layer.add_child(hud)
	hud.connect("start_requested", self, "_on_start")
	hud.connect("restart_requested", self, "_on_restart")
	hud.connect("character_changed", self, "_show_preview")
	hud.connect("cancel_room", self, "_on_restart")

	Net.connect("net_open", self, "_on_net_open")
	Net.connect("net_closed", self, "_on_net_closed")
	Net.connect("net_message", self, "_on_net_msg")

	_build_lobby_stage()
	_show_preview(Net.char_name)


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


# ---------------------------------------------------------------- lobby stage
func _build_lobby_stage() -> void:
	_stage = Spatial.new()
	add_child(_stage)
	var mi := MeshInstance.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 3.5
	cm.bottom_radius = 3.5
	cm.height = 0.1
	mi.mesh = cm
	var m := SpatialMaterial.new()
	m.albedo_color = Color(0.22, 0.25, 0.3)
	mi.material_override = m
	mi.translation = Vector3(0, -0.05, 0)
	_stage.add_child(mi)
	var gr := MeshInstance.new()
	var pm := CubeMesh.new()
	pm.size = Vector3(200, 0.1, 200)
	gr.mesh = pm
	var gm := SpatialMaterial.new()
	gm.albedo_color = Color(0.3, 0.4, 0.28)
	gr.material_override = gm
	gr.translation = Vector3(0, -0.2, 0)
	_stage.add_child(gr)


func _show_preview(cname: String) -> void:
	if _preview != null:
		_preview.queue_free()
		_preview = null
	var node = CharLib.make(cname)
	if node == null:
		node = MannequinScene.instance()
	_preview = node
	_stage.add_child(_preview)


func _clear_stage() -> void:
	if _stage != null:
		_stage.queue_free()
		_stage = null
	_preview = null


# ---------------------------------------------------------------- start
func _on_start(m: int, skill: float) -> void:
	mode = m
	bot_skill = skill
	Net.save_profile()
	if m == MODE_ONLINE:
		_connecting = true
		_conn_timer = 0.0
		hud.show_room("Connecting to server...\nA free server can take up to a minute to wake up.")
		if not Net.open():
			_connecting = false
			hud.show_room("Invalid server address.")
	elif m == MODE_TDM:
		_clear_stage()
		_start_tdm()
	else:
		_clear_stage()
		_start_br_local()


func _start_tdm() -> void:
	scores = [0, 0]
	time_left = MATCH_TIME
	arena = ArenaScript.new()
	add_child(arena)
	player = _make_fighter(PlayerScript, 0, Net.player_name, arena.spawns[0][0], arena.spawn_yaw[0], Net.char_name)
	for i in range(TEAM_SIZE - 1):
		_make_fighter(BotScript, 0, _blue_names[i], arena.spawns[0][(i + 1) % 4], arena.spawn_yaw[0], _random_char())
	for i in range(TEAM_SIZE):
		_make_fighter(BotScript, 1, _red_names[i], arena.spawns[1][i % 4], arena.spawn_yaw[1], _random_char())
	for f in get_tree().get_nodes_in_group("fighters"):
		f.give_weapon("pistol")
		f.give_weapon("rifle")
	_begin_play(2.0)


func _start_br_local() -> void:
	_build_br(randi() % 1000000 + 1)
	var order := []
	for i in range(arena.spawns[0].size()):
		order.append(i)
	for i in range(order.size() - 1, 0, -1):
		var j: int = randi() % (i + 1)
		var t = order[i]
		order[i] = order[j]
		order[j] = t
	player = _make_fighter(PlayerScript, 0, Net.player_name, arena.spawns[0][order[0]], randf() * TAU, Net.char_name)
	var names := _bot_names.duplicate()
	names.shuffle()
	for i in range(BR_BOTS):
		_make_fighter(BotScript, 1 + i, names[i], arena.spawns[0][order[i + 1]], randf() * TAU, _random_char())
	_total = BR_BOTS + 1
	_begin_play(3.0)


func _build_br(seed_v: int) -> void:
	arena = BRMapScript.new()
	arena.seed_v = seed_v
	add_child(arena)
	zone = ZoneScript.new(seed_v)
	_zs = zone.state(0.0)
	_zone_t = 0.0
	_last_shrink = -1
	_make_ring()
	for e in arena.loot:
		_add_pickup(String(e["kind"]), e["pos"])


func _random_char() -> String:
	var l := CharLib.list()
	return l[randi() % l.size()]


func _make_fighter(script, team: int, fname: String, pos: Vector3, yaw: float, cname: String):
	var f = script.new()
	f.team = team
	f.display_name = fname
	f.char_name = cname
	f.game = self
	if script == PlayerScript:
		f.hud = hud
	f.translation = pos
	f.rotation.y = yaw
	if mode == MODE_TDM:
		_team_fighters[team].append(f)
	add_child(f)
	if mode != MODE_TDM:
		f.show_marker = false
		f._marker.visible = false
	return f


func _begin_play(freeze: float) -> void:
	running = true
	frozen = freeze > 0.0
	_freeze_left = freeze
	hud.begin_match(player, mode)


# ---------------------------------------------------------------- main loop
func _process(delta: float) -> void:
	_expire_sparks()
	_update_fx(delta)
	if _stage != null and _preview != null:
		_preview_t += delta
		_preview.rotation.y = sin(_preview_t * 0.8) * 0.7
	if _connecting:
		_conn_timer += delta
		if _conn_timer > 80.0:
			_connecting = false
			Net.close()
			hud.show_room("Server did not answer. Check the address and try again.")
	for p in pickups:
		if p["on"]:
			p["node"].rotation.y += delta * 1.6
	if not running:
		return
	if frozen:
		_freeze_left -= delta
		hud.set_countdown(_freeze_left)
		if _freeze_left <= 0.0:
			frozen = false
			hud.set_countdown(0.0)
			Sfx.play_ui("match_start")
		return
	if mode == MODE_TDM:
		time_left -= delta
		hud.update_scores(scores, time_left)
		if time_left <= 0.0:
			end_match()
		return
	_br_tick(delta)
	if mode == MODE_ONLINE and player != null and player.alive:
		_net_acc += delta
		if _net_acc >= 0.1:
			_net_acc = 0.0
			var o: Vector3 = player.global_transform.origin
			Net.send({"t": "s", "p": [o.x, o.y, o.z], "r": player.rotation.y, "pi": player.gun_pitch,
				"st": player.stance, "sl": player.sliding, "w": player.cur,
				"v": [player.velocity.x, player.velocity.z]})


func _br_tick(delta: float) -> void:
	_zone_t += delta
	_zs = zone.state(_zone_t)
	_update_ring()
	if _zs["shrinking"] and _last_shrink != int(_zs["phase"]):
		_last_shrink = int(_zs["phase"])
		Sfx.play_ui("zone_warning")
	hud.update_zone(_zs, _alive_count())
	_dmg_acc += delta
	_pick_acc += delta
	if _dmg_acc >= 1.0:
		_dmg_acc = 0.0
		_zone_damage()
	if _pick_acc >= 0.12:
		_pick_acc = 0.0
		_check_pickups()


func _alive_count() -> int:
	var n := 0
	for f in get_tree().get_nodes_in_group("fighters"):
		if f.alive:
			n += 1
	return n


# ---------------------------------------------------------------- zone
func in_zone(p: Vector3, margin: float) -> bool:
	if _zs.empty():
		return true
	var c: Vector2 = _zs["center"]
	return Vector2(p.x, p.z).distance_to(c) <= float(_zs["radius"]) - margin


func zone_center() -> Vector3:
	var c: Vector2 = _zs["center"]
	return Vector3(c.x, 0.3, c.y)


func _zone_damage() -> void:
	var dps: float = _zs["dps"]
	for f in get_tree().get_nodes_in_group("fighters"):
		if not f.alive or f.puppet:
			continue
		if not in_zone(f.global_transform.origin, 0.0):
			f.take_damage(dps, null, false)
			if f == player:
				Sfx.play_ui("zone_damage")


func _make_ring() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 48
	var top := Vector3(0, 60, 0)
	for i in range(n):
		var a0: float = TAU * float(i) / float(n)
		var a1: float = TAU * float(i + 1) / float(n)
		var p0 := Vector3(cos(a0), 0, sin(a0))
		var p1 := Vector3(cos(a1), 0, sin(a1))
		st.add_vertex(p0)
		st.add_vertex(p1)
		st.add_vertex(p1 + top)
		st.add_vertex(p0)
		st.add_vertex(p1 + top)
		st.add_vertex(p0 + top)
	_ring = MeshInstance.new()
	_ring.mesh = st.commit()
	var m := SpatialMaterial.new()
	m.flags_unshaded = true
	m.flags_transparent = true
	m.params_cull_mode = SpatialMaterial.CULL_DISABLED
	m.albedo_color = Color(0.2, 0.5, 1.0, 0.28)
	_ring.material_override = m
	add_child(_ring)
	_update_ring()


func _update_ring() -> void:
	if _ring == null:
		return
	var c: Vector2 = _zs["center"]
	var r: float = _zs["radius"]
	_ring.translation = Vector3(c.x, 0, c.y)
	_ring.scale = Vector3(r, 1, r)


# ---------------------------------------------------------------- loot
func _pk_material(kind: String) -> SpatialMaterial:
	if not _pk_mats.has(kind):
		var m := SpatialMaterial.new()
		m.flags_unshaded = true
		var col := Color.white
		if W.DEFS.has(kind):
			col = W.DEFS[kind]["color"]
		elif W.PICKUP_COLORS.has(kind):
			col = W.PICKUP_COLORS[kind]
		m.albedo_color = col
		_pk_mats[kind] = m
	return _pk_mats[kind]


func _add_pickup(kind: String, pos: Vector3) -> int:
	if _pk_mesh == null:
		_pk_mesh = CubeMesh.new()
		_pk_mesh.size = Vector3(0.3, 1.5, 0.3)
	var n := Spatial.new()
	n.translation = pos
	var mi := MeshInstance.new()
	mi.mesh = _pk_mesh
	mi.material_override = _pk_material(kind)
	mi.translation = Vector3(0, 0.45, 0)
	n.add_child(mi)
	add_child(n)
	pickups.append({"node": n, "kind": kind, "pos": pos, "on": true})
	return pickups.size() - 1


func nearest_pickup(pos: Vector3, maxd: float, skip: Array):
	var best = null
	var bd: float = maxd
	for p in pickups:
		if not p["on"]:
			continue
		var pp: Vector3 = p["pos"]
		var d: float = pos.distance_to(pp)
		if d >= bd:
			continue
		var skipped := false
		for s in skip:
			if s.distance_to(pp) < 0.5:
				skipped = true
				break
		if not skipped:
			bd = d
			best = pp
	return best


func _check_pickups() -> void:
	for f in get_tree().get_nodes_in_group("fighters"):
		if not f.alive or f.puppet:
			continue
		var fp: Vector3 = f.global_transform.origin
		for i in range(pickups.size()):
			var p = pickups[i]
			if not p["on"]:
				continue
			var pp: Vector3 = p["pos"]
			if abs(pp.x - fp.x) > PICKUP_R or abs(pp.z - fp.z) > PICKUP_R:
				continue
			if f.apply_pickup(String(p["kind"])):
				_take_pickup(i, f)


func _take_pickup(i: int, f) -> void:
	var p = pickups[i]
	p["on"] = false
	p["node"].visible = false
	if f == player:
		Sfx.play_ui("pickup")
		var kind: String = p["kind"]
		var label: String = kind.capitalize()
		if W.DEFS.has(kind):
			label = W.DEFS[kind]["label"]
		hud.notify("Picked up " + label)
		if mode == MODE_ONLINE:
			Net.send({"t": "loot", "i": i})
	else:
		Sfx.play_at("pickup", p["pos"], 25.0)


func _drop_loot(f) -> void:
	var o: Vector3 = f.global_transform.origin
	var k := 0
	for n in f.inv:
		_add_pickup(String(n), Vector3(o.x + cos(k * 2.1) * 0.9, 0.4, o.z + sin(k * 2.1) * 0.9))
		k += 1


# ---------------------------------------------------------------- match events
func respawn_fighter(f) -> void:
	if not running or mode != MODE_TDM:
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
		Sfx.play_ui("hit_headshot" if head else "hit_enemy")


func on_weapon_changed(_f) -> void:
	pass


func on_fire(f, wname: String, muzzle: Vector3, dir: Vector3) -> void:
	if mode == MODE_ONLINE and f == player:
		Net.send({"t": "fire", "w": wname, "o": [muzzle.x, muzzle.y, muzzle.z], "d": [dir.x, dir.y, dir.z]})


func on_reload(f, wname: String) -> void:
	if mode == MODE_ONLINE and f == player:
		Net.send({"t": "reload", "w": wname})


func on_kill(attacker, victim, head: bool) -> void:
	if mode == MODE_TDM:
		if attacker != null and attacker != victim:
			scores[attacker.team] += 1
			hud.add_feed(attacker.display_name, attacker.team, victim.display_name, head)
		hud.update_scores(scores, time_left)
		if scores[0] >= KILLS_TO_WIN or scores[1] >= KILLS_TO_WIN:
			end_match()
		return
	var an := "ZONE"
	if attacker != null:
		an = attacker.display_name
	hud.add_feed(an, 1, victim.display_name, head)
	if mode == MODE_BR and victim != player:
		_drop_loot(victim)
	if victim == player:
		if mode == MODE_ONLINE:
			var by := 0
			if attacker != null:
				by = attacker.net_id
			Net.send({"t": "dead", "by": by})
		_finish(false, _alive_count() + 1)
	elif player != null and player.alive and _alive_count() <= 1:
		_finish(true, 1)


func _finish(win: bool, rank: int) -> void:
	if not running:
		return
	running = false
	for f in get_tree().get_nodes_in_group("fighters"):
		f.set_physics_process(false)
	Sfx.play_ui("victory" if win else "defeat")
	hud.show_end("VICTORY" if win else "ELIMINATED", "Placed #%d of %d" % [rank, _total])


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
	Sfx.play_ui("victory" if title == "VICTORY" else "defeat")
	hud.show_end(title, "BLUE %d  -  %d RED" % [scores[0], scores[1]])


func _on_restart() -> void:
	get_tree().paused = false
	Net.close()
	get_tree().reload_current_scene()


# ---------------------------------------------------------------- network
func _on_net_open() -> void:
	Net.send({"t": "join", "name": Net.player_name, "skin": Net.char_name})
	hud.show_room("Connected. Looking for a room...")


func _on_net_closed(reason: String) -> void:
	_connecting = false
	if running:
		hud.notify(reason)
	else:
		hud.show_room(reason)


func _on_net_msg(m: Dictionary) -> void:
	var t: String = String(m.get("t", ""))
	match t:
		"welcome":
			_connecting = false
			Net.my_id = int(m["id"])
		"room":
			hud.show_room("Waiting for players\n%d / %d\nStarts in %d s" % [int(m["n"]), int(m["max"]), int(m["left"])])
		"start":
			if not running:
				_start_online(m)
		"s":
			var f = _puppets.get(int(m["id"]))
			if f != null and f.alive:
				f.net_state(m)
		"fire":
			_remote_fire(m)
		"reload":
			var f2 = _puppets.get(int(m["id"]))
			if f2 != null and f2.alive:
				var d: Dictionary = W.DEFS[String(m["w"])]
				Sfx.play_at(String(d["reload_snd"]), f2.global_transform.origin, 30.0)
		"loot":
			var i := int(m["i"])
			if i >= 0 and i < pickups.size() and pickups[i]["on"]:
				pickups[i]["on"] = false
				pickups[i]["node"].visible = false
		"dead", "left":
			_on_remote_dead(m, t == "left")
		"end":
			if running and player != null and player.alive:
				_finish(int(m.get("winner", 0)) == Net.my_id, 1 if int(m.get("winner", 0)) == Net.my_id else 2)


func _start_online(m: Dictionary) -> void:
	_clear_stage()
	hud.hide_room()
	_build_br(int(m["seed"]))
	var plist: Array = m["players"]
	_total = plist.size()
	for pd in plist:
		var id := int(pd["id"])
		var idx := int(pd["spawn"])
		var spawn: Vector3 = arena.spawns[0][idx % arena.spawns[0].size()]
		var nm := String(pd["name"])
		_names[id] = nm
		if id == Net.my_id:
			player = _make_fighter(PlayerScript, 0, nm, spawn, randf() * TAU, Net.char_name)
			player.net_id = id
		else:
			_team_counter += 1
			var f = _make_fighter(RemoteScript, _team_counter, nm, spawn, randf() * TAU, String(pd["skin"]))
			f.net_id = id
			_puppets[id] = f
	if player == null:
		hud.show_room("Could not join the match.")
		return
	_begin_play(float(m.get("freeze", 3)))


func _remote_fire(m: Dictionary) -> void:
	var who = _puppets.get(int(m["id"]))
	if who == null or not who.alive:
		return
	var w: String = String(m["w"])
	if not W.DEFS.has(w):
		return
	var o: Array = m["o"]
	var dd: Array = m["d"]
	var pos := Vector3(o[0], o[1], o[2])
	var dir := Vector3(dd[0], dd[1], dd[2])
	who.remote_fire(w)
	var d: Dictionary = W.DEFS[w]
	match String(d["kind"]):
		"gun":
			spawn_bullet(who, pos, dir, float(d["speed"]), float(d["damage"]), float(d["range"]), w)
		"rocket":
			spawn_rocket(who, pos, dir, w)
		_:
			throw_grenade(who, pos, dir, w)


func _on_remote_dead(m: Dictionary, left: bool) -> void:
	var id := int(m["id"])
	var f = _puppets.get(id)
	if f != null and f.alive:
		f.net_die()
		if not left:
			var by := int(m.get("by", 0))
			var kn := "ZONE"
			if by == Net.my_id:
				kn = Net.player_name
			elif _names.has(by):
				kn = String(_names[by])
			hud.add_feed(kn, 1, f.display_name, false)
	if running and player != null and player.alive and _alive_count() <= 1:
		_finish(true, 1)


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
			"speed": 0.0, "who": null, "dmg": 0.0, "left": 0.0, "ex": [], "hm": 2.0
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


func spawn_bullet(who, pos: Vector3, dir: Vector3, speed: float, dmg: float, rng: float, wname: String) -> void:
	var b = _bullets[_bullet_i]
	_bullet_i = (_bullet_i + 1) % BULLET_POOL
	b["active"] = true
	b["pos"] = pos
	b["dir"] = dir
	b["speed"] = speed
	b["who"] = who
	b["dmg"] = dmg
	b["left"] = rng
	b["hm"] = float(W.DEFS[wname]["head"])
	if mode == MODE_TDM:
		b["ex"] = _team_fighters[who.team]
	else:
		b["ex"] = [who]
	var mi: MeshInstance = b["mi"]
	mi.material_override = _bullet_mats[min(who.team, 1)]
	mi.visible = true
	_place_bullet(b)


func _orient(mi: MeshInstance, pos: Vector3, dir: Vector3, sc: Vector3, back: float) -> void:
	var up := Vector3.UP if abs(dir.y) < 0.99 else Vector3.RIGHT
	var center := pos - dir * back
	var t := Transform(Basis.IDENTITY, center).looking_at(center + dir, up)
	t.basis = t.basis.scaled(sc)
	mi.transform = t


func _place_bullet(b) -> void:
	_orient(b["mi"], b["pos"], b["dir"], Vector3(0.07, 0.07, 1.2), 0.6)


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
	_step_projectiles(delta, space)


func _bullet_hit(b, hit: Dictionary) -> void:
	_spark(hit.position)
	if not running:
		return
	var c = hit.collider
	if c != null and c.has_method("take_damage"):
		var head: bool = c.is_head(hit.position.y)
		if c.puppet:
			if b["who"] == player:
				hud.hit_marker(false, head)
				Sfx.play_ui("hit_headshot" if head else "hit_enemy")
			return
		var dmg: float = b["dmg"]
		c.take_damage(dmg * (float(b["hm"]) if head else 1.0), b["who"], head)


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


# ---------------------------------------------------------------- rockets / grenades
func _proj_mesh(col: Color) -> MeshInstance:
	var mi := MeshInstance.new()
	var cm := CubeMesh.new()
	cm.size = Vector3(1, 1, 1)
	mi.mesh = cm
	var m := SpatialMaterial.new()
	m.flags_unshaded = true
	m.albedo_color = col
	mi.material_override = m
	add_child(mi)
	return mi


func spawn_rocket(who, pos: Vector3, dir: Vector3, wname: String) -> void:
	var d: Dictionary = W.DEFS[wname]
	var mi := _proj_mesh(Color(1.0, 0.6, 0.15))
	_projs.append({
		"type": "rocket", "mi": mi, "pos": pos, "vel": dir * float(d["speed"]), "who": who,
		"left": float(d["range"]), "dmg": float(d["damage"]), "radius": float(d["radius"]), "fuse": 0.0
	})


func throw_grenade(who, pos: Vector3, dir: Vector3, wname: String) -> void:
	var d: Dictionary = W.DEFS[wname]
	var mi := _proj_mesh(Color(0.2, 0.35, 0.15))
	var v: Vector3 = (dir + Vector3(0, 0.3, 0)).normalized() * float(d["throw_speed"])
	_projs.append({
		"type": "grenade", "mi": mi, "pos": pos, "vel": v, "who": who, "left": 0.0,
		"dmg": float(d["damage"]), "radius": float(d["radius"]), "fuse": float(d["fuse"])
	})


func _step_projectiles(delta: float, space) -> void:
	var i := _projs.size() - 1
	while i >= 0:
		var p = _projs[i]
		var vel: Vector3 = p["vel"]
		var from: Vector3 = p["pos"]
		var done := false
		if p["type"] == "rocket":
			var step: float = vel.length() * delta
			var to: Vector3 = from + vel * delta
			var hit := space.intersect_ray(from, to, [p["who"]], 3)
			if hit:
				_explode(hit.position + hit.normal * 0.1, p["radius"], p["dmg"], p["who"])
				done = true
			else:
				p["pos"] = to
				p["left"] -= step
				if p["left"] <= 0.0:
					_explode(to, p["radius"], p["dmg"], p["who"])
					done = true
				else:
					_orient(p["mi"], to, vel.normalized(), Vector3(0.12, 0.12, 0.8), 0.4)
		else:
			p["fuse"] -= delta
			vel.y += GRENADE_GRAVITY * delta
			var to2: Vector3 = from + vel * delta
			var hit2 := space.intersect_ray(from, to2, [], 1)
			if hit2:
				vel = vel.bounce(hit2.normal) * 0.45
				p["pos"] = hit2.position + hit2.normal * 0.12
				if hit2.normal.y > 0.7 and vel.length() < 2.0:
					vel = Vector3.ZERO
			else:
				p["pos"] = to2
			p["vel"] = vel
			var mi: MeshInstance = p["mi"]
			mi.transform = Transform(Basis.IDENTITY.scaled(Vector3(0.22, 0.22, 0.22)), p["pos"])
			if p["fuse"] <= 0.0:
				_explode(p["pos"], p["radius"], p["dmg"], p["who"])
				done = true
		if done:
			p["mi"].queue_free()
			_projs.remove(i)
		i -= 1


func _explode(pos: Vector3, radius: float, dmg: float, who) -> void:
	Sfx.play_at("explosion", pos, 170.0)
	var mi := MeshInstance.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	var m := SpatialMaterial.new()
	m.flags_unshaded = true
	m.flags_transparent = true
	m.albedo_color = Color(1.0, 0.55, 0.15, 0.85)
	mi.material_override = m
	mi.translation = pos
	add_child(mi)
	_fx.append({"mi": mi, "t": 0.0, "r": radius * 0.6, "m": m})
	var space := get_viewport().world.direct_space_state
	for f in get_tree().get_nodes_in_group("fighters"):
		if not f.alive or f.puppet:
			continue
		var tp: Vector3 = f.global_transform.origin + Vector3(0, 0.8, 0)
		var dist: float = pos.distance_to(tp)
		if dist > radius:
			continue
		var cover := 1.0
		if dist > 1.5 and not space.intersect_ray(pos + Vector3(0, 0.3, 0), tp, [], 1).empty():
			cover = 0.3
		var fall: float = 1.0 - dist / radius
		f.take_damage(dmg * (0.25 + 0.75 * fall) * cover, who, false)


func _update_fx(delta: float) -> void:
	var i := _fx.size() - 1
	while i >= 0:
		var e = _fx[i]
		e["t"] += delta
		var k: float = e["t"] / 0.4
		if k >= 1.0:
			e["mi"].queue_free()
			_fx.remove(i)
		else:
			var s: float = e["r"] * (0.3 + 0.7 * k)
			e["mi"].scale = Vector3(s, s, s)
			var m: SpatialMaterial = e["m"]
			m.albedo_color = Color(1.0, 0.55, 0.15, 0.85 * (1.0 - k))
		i -= 1
