extends Control
# Touch HUD: floating joystick (left), look area (right), FIRE / JUMP / RELOAD
# buttons, health, ammo, score, kill feed, menu and end-of-match panels.

signal start_requested(mode, skill)
signal restart_requested
signal character_changed(cname)
signal cancel_room

const W = preload("res://src/Game/Weapons.gd")
const CharLib = preload("res://src/Game/CharacterLib.gd")

const FONT_PATH := "res://assets/fonts/Montserrat-Bold.ttf"
const STICK_RADIUS := 90.0
const SAVE_PATH := "user://settings.cfg"

var game = null
var player = null
var active := false
var game_mode := 0

# settings (saved on close)
var sens := 1.0
var assist := 0.6
var smooth := 0.4
var sound := 1.0

# state read by the player
var move_vec := Vector2.ZERO
var fire_held := false
var _look_accum := Vector2.ZERO
var _jump := false
var _reload := false
var _slide := false
var _crouch := false
var _prone := false
var _slot := ""

var _move_touch := -1
var _look_touch := -1
var _fire_touch := -1
var _stick_base := Vector2.ZERO
var _stick_rest := Vector2(170, 520)

var _fire_c := Vector2.ZERO
var _fire_r := 72.0
var _jump_c := Vector2.ZERO
var _jump_r := 46.0
var _reload_c := Vector2.ZERO
var _reload_r := 40.0
var _slide_c := Vector2.ZERO
var _slide_r := 38.0
var _gear_c := Vector2.ZERO
var _crouch_c := Vector2.ZERO
var _crouch_r := 38.0
var _prone_c := Vector2.ZERO
var _prone_r := 36.0

var _f_small: DynamicFont
var _f_mid: DynamicFont
var _f_big: DynamicFont
var _f_title: DynamicFont
var _f_tiny: DynamicFont

var _scores := [0, 0]
var _time_left := 0.0
var _hit_flash := 0.0
var _hit_kill := false
var _dmg_flash := 0.0
var _feed := []
var _notes := []
var _countdown := 0.0
var _zs := {}
var _alive := 1
var _chars := []
var _char_i := 0
var _mode_i := 0
var _diff_i := 1
var _char_lbl: Label
var _diff_btn: Button
var _name_edit: LineEdit
var _url_edit: LineEdit
var _room: ColorRect
var _room_lbl: Label
var _room_btn: Button
var _vol_lbl: Label

var _menu: ColorRect
var _end: ColorRect
var _end_title: Label
var _end_sub: Label
var _settings: ColorRect
var _sens_lbl: Label
var _assist_lbl: Label
var _smooth_lbl: Label


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_settings()
	Sfx.volume = sound
	_chars = CharLib.list()
	_char_i = max(0, _chars.find(Net.char_name))
	Net.char_name = _chars[_char_i]
	_f_small = _make_font(22)
	_f_mid = _make_font(30)
	_f_big = _make_font(64)
	_f_title = _make_font(46)
	_f_tiny = _make_font(18)
	_build_menu()
	_build_room()
	_build_end()
	_build_settings()


func _make_font(size: int) -> DynamicFont:
	var f := DynamicFont.new()
	f.font_data = load(FONT_PATH)
	f.size = size
	return f


# ---------------------------------------------------------------- overlays
func _label(text: String, font: DynamicFont, col := Color.white) -> Label:
	var l := Label.new()
	l.text = text
	l.align = Label.ALIGN_CENTER
	l.add_font_override("font", font)
	l.add_color_override("font_color", col)
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.rect_min_size = Vector2(380, 66)
	b.add_font_override("font", _f_mid)
	return b


func _overlay() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0, 0, 0, 0.8)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	r.anchor_right = 1.0
	r.anchor_bottom = 1.0
	add_child(r)
	return r


func _build_menu() -> void:
	_menu = _overlay()
	_menu.color = Color(0, 0, 0, 0.3)
	var hb := HBoxContainer.new()
	hb.anchor_right = 1.0
	hb.anchor_bottom = 1.0
	_menu.add_child(hb)

	# left: character picker (3D preview is drawn behind by Main.gd)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(left)
	var pad := Control.new()
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(pad)
	var pick := HBoxContainer.new()
	pick.alignment = BoxContainer.ALIGN_CENTER
	left.add_child(pick)
	var lb := _button("<")
	lb.rect_min_size = Vector2(70, 62)
	lb.connect("pressed", self, "_on_char", [-1])
	pick.add_child(lb)
	_char_lbl = _label(_chars[_char_i], _f_mid)
	_char_lbl.rect_min_size = Vector2(240, 0)
	_char_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pick.add_child(_char_lbl)
	var rb := _button(">")
	rb.rect_min_size = Vector2(70, 62)
	rb.connect("pressed", self, "_on_char", [1])
	pick.add_child(rb)
	var pad2 := Control.new()
	pad2.rect_min_size = Vector2(0, 30)
	left.add_child(pad2)

	# right: lobby
	var vb := VBoxContainer.new()
	vb.add_constant_override("separation", 8)
	vb.rect_min_size = Vector2(470, 0)
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(vb)
	var margin := Control.new()
	margin.rect_min_size = Vector2(30, 0)
	hb.add_child(margin)

	vb.add_child(_label("CDM YA BONGO", _f_title, Color(1, 0.85, 0.3)))

	_name_edit = LineEdit.new()
	_name_edit.text = Net.player_name
	_name_edit.placeholder_text = "Your name"
	_name_edit.max_length = 14
	_name_edit.rect_min_size = Vector2(0, 50)
	_name_edit.add_font_override("font", _f_small)
	_name_edit.connect("text_changed", self, "_on_name")
	vb.add_child(_name_edit)

	var row := HBoxContainer.new()
	row.add_constant_override("separation", 6)
	vb.add_child(row)
	var grp := ButtonGroup.new()
	var mnames := ["BR SOLO", "ONLINE", "4v4"]
	for i in range(3):
		var mb := Button.new()
		mb.text = mnames[i]
		mb.toggle_mode = true
		mb.group = grp
		mb.pressed = (i == 0)
		mb.rect_min_size = Vector2(150, 58)
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mb.add_font_override("font", _f_small)
		mb.connect("pressed", self, "_on_mode", [i])
		row.add_child(mb)

	_diff_btn = _button("")
	_diff_btn.rect_min_size = Vector2(0, 52)
	_diff_btn.connect("pressed", self, "_on_diff")
	vb.add_child(_diff_btn)
	_update_diff()

	_url_edit = LineEdit.new()
	_url_edit.text = Net.url
	_url_edit.placeholder_text = "wss://your-app.onrender.com"
	_url_edit.rect_min_size = Vector2(0, 46)
	_url_edit.add_font_override("font", _f_small)
	_url_edit.connect("text_changed", self, "_on_url")
	_url_edit.visible = false
	vb.add_child(_url_edit)

	var start := _button("START")
	start.rect_min_size = Vector2(0, 76)
	start.modulate = Color(0.55, 1.0, 0.55)
	start.connect("pressed", self, "_on_start")
	vb.add_child(start)
	var sb := _button("SETTINGS")
	sb.rect_min_size = Vector2(0, 52)
	sb.connect("pressed", self, "_open_settings")
	vb.add_child(sb)


func _build_room() -> void:
	_room = _overlay()
	_room.color = Color(0, 0, 0, 0.7)
	_room.visible = false
	var cc := CenterContainer.new()
	cc.anchor_right = 1.0
	cc.anchor_bottom = 1.0
	_room.add_child(cc)
	var vb := VBoxContainer.new()
	vb.add_constant_override("separation", 20)
	cc.add_child(vb)
	_room_lbl = _label("", _f_mid)
	vb.add_child(_room_lbl)
	_room_btn = _button("CANCEL")
	_room_btn.connect("pressed", self, "_on_cancel_room")
	vb.add_child(_room_btn)


func _on_char(dir: int) -> void:
	_char_i = (_char_i + dir + _chars.size()) % _chars.size()
	_char_lbl.text = _chars[_char_i]
	Net.char_name = _chars[_char_i]
	emit_signal("character_changed", _chars[_char_i])


func _on_name(t: String) -> void:
	Net.player_name = t if t.strip_edges() != "" else "Player"


func _on_url(t: String) -> void:
	Net.url = t


func _on_mode(i: int) -> void:
	_mode_i = i
	_url_edit.visible = (i == 1)


func _on_diff() -> void:
	_diff_i = (_diff_i + 1) % 3
	_update_diff()


func _update_diff() -> void:
	_diff_btn.text = "BOTS: " + ["EASY", "NORMAL", "HARD"][_diff_i]


func _on_cancel_room() -> void:
	emit_signal("cancel_room")


func show_room(text: String) -> void:
	_menu.visible = false
	_room.visible = true
	_room_lbl.text = text


func hide_room() -> void:
	_room.visible = false


func _build_end() -> void:
	_end = _overlay()
	_end.visible = false
	var cc := CenterContainer.new()
	cc.anchor_right = 1.0
	cc.anchor_bottom = 1.0
	_end.add_child(cc)
	var vb := VBoxContainer.new()
	vb.add_constant_override("separation", 14)
	cc.add_child(vb)
	_end_title = _label("", _f_big)
	_end_sub = _label("", _f_mid)
	vb.add_child(_end_title)
	vb.add_child(_end_sub)
	var b := _button("PLAY AGAIN")
	b.connect("pressed", self, "_on_restart")
	vb.add_child(b)


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		sens = cf.get_value("controls", "sens", 1.0)
		assist = cf.get_value("controls", "assist", 0.6)
		smooth = cf.get_value("controls", "smooth", 0.4)
		sound = cf.get_value("controls", "sound", 1.0)


func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("controls", "sens", sens)
	cf.set_value("controls", "assist", assist)
	cf.set_value("controls", "smooth", smooth)
	cf.set_value("controls", "sound", sound)
	cf.save(SAVE_PATH)


func _slider(lo: float, hi: float, step: float, val: float) -> HSlider:
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = val
	sl.rect_min_size = Vector2(460, 48)
	return sl


func _build_settings() -> void:
	_settings = _overlay()
	_settings.color = Color(0, 0, 0, 0.88)
	_settings.visible = false
	var cc := CenterContainer.new()
	cc.anchor_right = 1.0
	cc.anchor_bottom = 1.0
	_settings.add_child(cc)
	var vb := VBoxContainer.new()
	vb.add_constant_override("separation", 10)
	cc.add_child(vb)
	vb.add_child(_label("SETTINGS", _f_mid, Color(1, 0.85, 0.3)))

	_sens_lbl = _label("", _f_small)
	vb.add_child(_sens_lbl)
	var s1 := _slider(0.3, 2.5, 0.05, sens)
	s1.connect("value_changed", self, "_on_sens")
	vb.add_child(s1)

	_assist_lbl = _label("", _f_small)
	vb.add_child(_assist_lbl)
	var s2 := _slider(0.0, 1.0, 0.05, assist)
	s2.connect("value_changed", self, "_on_assist")
	vb.add_child(s2)

	_smooth_lbl = _label("", _f_small)
	vb.add_child(_smooth_lbl)
	var s3 := _slider(0.0, 1.0, 0.05, smooth)
	s3.connect("value_changed", self, "_on_smooth")
	vb.add_child(s3)

	_vol_lbl = _label("", _f_small)
	vb.add_child(_vol_lbl)
	var s4 := _slider(0.0, 1.0, 0.05, sound)
	s4.connect("value_changed", self, "_on_sound")
	vb.add_child(s4)

	var close := _button("CLOSE")
	close.connect("pressed", self, "_close_settings")
	vb.add_child(close)
	_update_labels()


func _update_labels() -> void:
	_sens_lbl.text = "Look sensitivity: %.2f" % sens
	_assist_lbl.text = "Aim assist (head): %d%%" % int(assist * 100.0)
	_smooth_lbl.text = "Camera smoothing: %d%%" % int(smooth * 100.0)
	_vol_lbl.text = "Sound volume: %d%%" % int(sound * 100.0)


func _on_sens(v: float) -> void:
	sens = v
	_update_labels()


func _on_assist(v: float) -> void:
	assist = v
	_update_labels()


func _on_smooth(v: float) -> void:
	smooth = v
	_update_labels()


func _on_sound(v: float) -> void:
	sound = v
	Sfx.volume = v
	_update_labels()


func _open_settings() -> void:
	_settings.visible = true
	fire_held = false
	_fire_touch = -1
	_move_touch = -1
	_look_touch = -1
	move_vec = Vector2.ZERO
	if active:
		get_tree().paused = true


func _close_settings() -> void:
	_settings.visible = false
	get_tree().paused = false
	_save_settings()


func _on_start() -> void:
	_menu.visible = false
	var skills := [0.7, 1.0, 1.4]
	var m: int = _mode_i
	emit_signal("start_requested", m, skills[_diff_i])


func _on_restart() -> void:
	emit_signal("restart_requested")


func begin_match(p, m: int = 0) -> void:
	player = p
	game_mode = m
	active = true


func set_countdown(t: float) -> void:
	_countdown = t


func notify(text: String) -> void:
	_notes.append({"s": text, "t": 2.5})
	if _notes.size() > 3:
		_notes.pop_front()


func update_zone(zs: Dictionary, alive: int) -> void:
	_zs = zs
	_alive = alive


func show_end(title: String, sub: String) -> void:
	active = false
	get_tree().paused = false
	fire_held = false
	move_vec = Vector2.ZERO
	_move_touch = -1
	_look_touch = -1
	_fire_touch = -1
	_end_title.text = title
	_end_sub.text = sub
	_end.visible = true


# ---------------------------------------------------------------- API for game
func update_scores(scores: Array, time_left: float) -> void:
	_scores = scores
	_time_left = time_left


func add_feed(killer: String, killer_team: int, victim: String, head: bool) -> void:
	_feed.append({"k": killer, "kt": killer_team, "v": victim, "h": head, "t": 5.0})
	if _feed.size() > 4:
		_feed.pop_front()


func flash_damage() -> void:
	_dmg_flash = 1.0


func hit_marker(killed: bool, _head: bool) -> void:
	_hit_flash = 0.25
	_hit_kill = killed


func consume_look() -> Vector2:
	var v := _look_accum
	_look_accum = Vector2.ZERO
	return v


func consume_jump() -> bool:
	var j := _jump
	_jump = false
	return j


func consume_slide() -> bool:
	var sl := _slide
	_slide = false
	return sl


func consume_crouch() -> bool:
	var c := _crouch
	_crouch = false
	return c


func consume_prone() -> bool:
	var c := _prone
	_prone = false
	return c


func consume_slot() -> String:
	var c := _slot
	_slot = ""
	return c


func consume_reload() -> bool:
	var r := _reload
	_reload = false
	return r


# ---------------------------------------------------------------- input
func _input(event: InputEvent) -> void:
	if not active or _settings.visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index)
	elif event is InputEventScreenDrag:
		_touch_drag(event.index, event.position, event.relative)


func _touch_down(i: int, p: Vector2) -> void:
	var s := rect_size
	if p.distance_to(_gear_c) <= 42.0:
		_open_settings()
		return
	for k in range(W.ORDER.size()):
		if _slot_rect(k).grow(6.0).has_point(p):
			_slot = W.ORDER[k]
			return
	if p.distance_to(_crouch_c) <= _crouch_r * 1.25:
		_crouch = true
		return
	if p.distance_to(_prone_c) <= _prone_r * 1.25:
		_prone = true
		return
	if p.distance_to(_fire_c) <= _fire_r * 1.15:
		_fire_touch = i
		fire_held = true
	elif p.distance_to(_jump_c) <= _jump_r * 1.25:
		_jump = true
	elif p.distance_to(_reload_c) <= _reload_r * 1.25:
		_reload = true
	elif p.distance_to(_slide_c) <= _slide_r * 1.25:
		_slide = true
	elif p.x < s.x * 0.4:
		if _move_touch == -1:
			_move_touch = i
			_stick_base = p
			move_vec = Vector2.ZERO
	elif _look_touch == -1:
		_look_touch = i


func _touch_up(i: int) -> void:
	if i == _move_touch:
		_move_touch = -1
		move_vec = Vector2.ZERO
	if i == _look_touch:
		_look_touch = -1
	if i == _fire_touch:
		_fire_touch = -1
		fire_held = false


func _touch_drag(i: int, p: Vector2, rel: Vector2) -> void:
	if i == _move_touch:
		var d := p - _stick_base
		if d.length() > STICK_RADIUS:
			d = d.normalized() * STICK_RADIUS
		move_vec = d / STICK_RADIUS
		if move_vec.length() < 0.12:
			move_vec = Vector2.ZERO
	elif i == _look_touch or i == _fire_touch:
		_look_accum += rel


# ---------------------------------------------------------------- drawing
func _process(delta: float) -> void:
	var s := get_viewport_rect().size
	rect_position = Vector2.ZERO
	rect_size = s
	_fire_c = Vector2(s.x - 150, s.y - 170)
	_jump_c = Vector2(s.x - 300, s.y - 90)
	_reload_c = Vector2(s.x - 300, s.y - 215)
	_slide_c = Vector2(s.x - 150, s.y - 320)
	_gear_c = Vector2(s.x - 50, 95)
	_crouch_c = Vector2(s.x - 300, s.y - 340)
	_prone_c = Vector2(s.x - 420, s.y - 190)
	_stick_rest = Vector2(170, s.y - 170)
	_hit_flash = max(0.0, _hit_flash - delta)
	_dmg_flash = max(0.0, _dmg_flash - delta * 2.0)
	for e in _notes:
		e["t"] -= delta
	while _notes.size() > 0 and _notes[0]["t"] <= 0.0:
		_notes.pop_front()
	for e in _feed:
		e["t"] -= delta
	while _feed.size() > 0 and _feed[0]["t"] <= 0.0:
		_feed.pop_front()
	update()


func _text(font: Font, pos: Vector2, txt: String, col: Color, centered := false) -> void:
	var p := pos
	if centered:
		p.x -= font.get_string_size(txt).x * 0.5
	draw_string(font, p + Vector2(2, 2), txt, Color(0, 0, 0, 0.7))
	draw_string(font, p, txt, col)


func _circle_button(c: Vector2, r: float, label: String, pressed: bool) -> void:
	draw_circle(c, r, Color(1, 1, 1, 0.28 if pressed else 0.12))
	draw_arc(c, r, 0, TAU, 40, Color(1, 1, 1, 0.65), 3.0)
	_text(_f_small, c + Vector2(0, 8), label, Color.white, true)


func _draw() -> void:
	if not active or player == null:
		return
	var s := rect_size
	var c := s * 0.5

	if _dmg_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, s), Color(1, 0, 0, 0.3 * _dmg_flash))

	# crosshair
	var cc := Color(1, 1, 1, 0.9)
	draw_line(c + Vector2(-16, 0), c + Vector2(-6, 0), cc, 2.0)
	draw_line(c + Vector2(6, 0), c + Vector2(16, 0), cc, 2.0)
	draw_line(c + Vector2(0, -16), c + Vector2(0, -6), cc, 2.0)
	draw_line(c + Vector2(0, 6), c + Vector2(0, 16), cc, 2.0)
	if _hit_flash > 0.0:
		var hc := Color(1, 0.2, 0.2, 1) if _hit_kill else Color(1, 1, 1, 1)
		draw_line(c + Vector2(-10, -10), c + Vector2(-4, -4), hc, 3.0)
		draw_line(c + Vector2(10, -10), c + Vector2(4, -4), hc, 3.0)
		draw_line(c + Vector2(-10, 10), c + Vector2(-4, 4), hc, 3.0)
		draw_line(c + Vector2(10, 10), c + Vector2(4, 4), hc, 3.0)

	# joystick
	var base := _stick_base if _move_touch != -1 else _stick_rest
	draw_circle(base, STICK_RADIUS, Color(1, 1, 1, 0.1))
	draw_arc(base, STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.45), 3.0)
	draw_circle(base + move_vec * STICK_RADIUS * 0.75, 38.0, Color(1, 1, 1, 0.4))

	# buttons
	_circle_button(_fire_c, _fire_r, "FIRE", fire_held)
	_circle_button(_jump_c, _jump_r, "JUMP", false)
	_circle_button(_reload_c, _reload_r, "R", false)
	_circle_button(_slide_c, _slide_r, "SLIDE", false)
	_circle_button(_crouch_c, _crouch_r, "DUCK", player.stance == 1)
	_circle_button(_prone_c, _prone_r, "LIE", player.stance == 2)
	_circle_button(_gear_c, 26.0, "SET", false)

	_text(_f_small, Vector2(s.x - 110, 30), "%d FPS" % Engine.get_frames_per_second(), Color(0.7, 1, 0.7))

	if game_mode == 2:
		var secs := int(max(0.0, _time_left))
		_text(_f_mid, Vector2(c.x, 40), "%d:%02d" % [secs / 60, secs % 60], Color.white, true)
		_text(_f_mid, Vector2(c.x - 90, 40), str(_scores[0]), Color(0.3, 0.6, 1.0), true)
		_text(_f_mid, Vector2(c.x + 90, 40), str(_scores[1]), Color(1.0, 0.35, 0.3), true)
	else:
		_text(_f_mid, Vector2(c.x, 40), "ALIVE %d" % _alive, Color.white, true)
		if not _zs.empty():
			var tl := int(_zs["time_left"])
			var zt: String = ("ZONE CLOSING %d s" if _zs["shrinking"] else "ZONE SHRINKS IN %d s") % tl
			_text(_f_small, Vector2(c.x, 72), zt, Color(0.5, 0.75, 1.0) if _zs["shrinking"] else Color(0.8, 0.8, 0.8), true)
		_draw_minimap(s)

	# kill feed
	var y := 40.0
	for e in _feed:
		var col := Color(0.4, 0.7, 1.0) if e["kt"] == 0 else Color(1.0, 0.45, 0.4)
		var txt: String = "%s  >  %s%s" % [e["k"], e["v"], "  (HS)" if e["h"] else ""]
		_text(_f_small, Vector2(24, y), txt, col)
		y += 30.0

	# health + ammo
	var hp_ratio: float = clamp(player.hp / 100.0, 0.0, 1.0)
	var bar := Rect2(c.x - 170, s.y - 50, 340, 18)
	draw_rect(bar, Color(0, 0, 0, 0.55))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * hp_ratio, bar.size.y)), Color(1.0 - hp_ratio, 0.3 + 0.6 * hp_ratio, 0.2))
	_text(_f_small, Vector2(c.x, s.y - 58), "HP %d" % int(player.hp), Color.white, true)
	var ammo_txt: String = "RELOADING" if player.is_reloading() else player.ammo_text()
	_text(_f_mid, Vector2(c.x + 190, s.y - 30), ammo_txt, Color(1, 0.85, 0.3) if not player.is_reloading() else Color(1, 0.6, 0.2))

	# weapon slots
	for k in range(W.ORDER.size()):
		var wn: String = W.ORDER[k]
		var r := _slot_rect(k)
		var owned: bool = player.has_weapon(wn)
		var sel: bool = player.cur == wn
		draw_rect(r, Color(1, 1, 1, 0.35) if sel else Color(0, 0, 0, 0.4))
		draw_rect(r, Color(1, 0.85, 0.3, 0.9) if sel else Color(1, 1, 1, 0.3), false, 2.0)
		var lbl: String = W.DEFS[wn]["short"]
		if owned:
			var st: Dictionary = player.inv[wn]
			lbl += " " + (str(st["ammo"]) if W.DEFS[wn]["kind"] == "throw" else str(st["ammo"]))
		_text(_f_tiny, r.position + Vector2(r.size.x * 0.5, 30), lbl, Color.white if owned else Color(1, 1, 1, 0.3), true)

	if player.alive and player.cur == "" and game_mode != 2:
		_text(_f_mid, Vector2(c.x, s.y * 0.72), "FIND A WEAPON", Color(1, 0.85, 0.3), true)

	var ny := s.y * 0.62
	for e in _notes:
		_text(_f_small, Vector2(c.x, ny), e["s"], Color(0.6, 1, 0.6), true)
		ny += 28.0
	if _countdown > 0.0:
		_text(_f_big, Vector2(c.x, c.y - 20), str(int(ceil(_countdown))), Color.white, true)
		_text(_f_mid, Vector2(c.x, c.y + 30), "LAND AND LOOT", Color(1, 0.85, 0.3), true)

	if not player.alive and game_mode == 2:
		_text(_f_mid, Vector2(c.x, c.y - 60), "RESPAWN IN %d" % int(ceil(max(0.0, player.respawn_left))), Color.white, true)


func _slot_rect(i: int) -> Rect2:
	var s := rect_size
	return Rect2(Vector2(s.x * 0.5 - 240 + i * 92, s.y - 112), Vector2(84, 46))


func _draw_minimap(s: Vector2) -> void:
	if _zs.empty() or game == null or player == null:
		return
	var size := 96.0
	var org := Vector2(s.x - 176, 122)
	var k: float = size / (game.MAP_HALF * 2.0)
	var cen := org + Vector2(size, size) * 0.5
	draw_rect(Rect2(org, Vector2(size, size)), Color(0, 0, 0, 0.45))
	var zc: Vector2 = _zs["center"]
	var zr: float = _zs["radius"]
	draw_arc(cen + zc * k, zr * k, 0, TAU, 32, Color(0.3, 0.6, 1.0), 2.0)
	var nc: Vector2 = _zs["next_center"]
	var nr: float = _zs["next_radius"]
	draw_arc(cen + nc * k, nr * k, 0, TAU, 24, Color(1, 1, 1, 0.8), 1.5)
	var po: Vector3 = player.global_transform.origin
	var pp := cen + Vector2(po.x, po.z) * k
	pp.x = clamp(pp.x, org.x, org.x + size)
	pp.y = clamp(pp.y, org.y, org.y + size)
	draw_circle(pp, 3.5, Color(1, 0.9, 0.2))
	var yaw: float = player.rotation.y
	draw_line(pp, pp + Vector2(-sin(yaw), -cos(yaw)) * 9.0, Color(1, 0.9, 0.2), 2.0)
