extends Control
# Touch HUD: floating joystick (left), look area (right), FIRE / JUMP / RELOAD
# buttons, health, ammo, score, kill feed, menu and end-of-match panels.

signal start_requested(skill)
signal restart_requested

const FONT_PATH := "res://assets/fonts/Montserrat-Bold.ttf"
const STICK_RADIUS := 90.0

var player = null
var active := false

# state read by the player
var move_vec := Vector2.ZERO
var fire_held := false
var _look_accum := Vector2.ZERO
var _jump := false
var _reload := false

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

var _f_small: DynamicFont
var _f_mid: DynamicFont
var _f_big: DynamicFont

var _scores := [0, 0]
var _time_left := 0.0
var _hit_flash := 0.0
var _hit_kill := false
var _dmg_flash := 0.0
var _feed := []

var _menu: ColorRect
var _end: ColorRect
var _end_title: Label
var _end_sub: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_f_small = _make_font(22)
	_f_mid = _make_font(30)
	_f_big = _make_font(64)
	_build_menu()
	_build_end()


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
	var cc := CenterContainer.new()
	cc.anchor_right = 1.0
	cc.anchor_bottom = 1.0
	_menu.add_child(cc)
	var vb := VBoxContainer.new()
	vb.add_constant_override("separation", 14)
	cc.add_child(vb)
	vb.add_child(_label("ARENA 4 v 4", _f_big))
	vb.add_child(_label("Team Deathmatch - first to 30 kills", _f_small, Color(0.8, 0.8, 0.8)))
	vb.add_child(_label("Choose difficulty", _f_small, Color(1, 0.85, 0.3)))
	var names := ["EASY", "NORMAL", "HARD"]
	var skills := [0.7, 1.0, 1.4]
	for i in range(3):
		var b := _button(names[i])
		b.connect("pressed", self, "_on_start", [skills[i]])
		vb.add_child(b)


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


func _on_start(skill: float) -> void:
	_menu.visible = false
	emit_signal("start_requested", skill)


func _on_restart() -> void:
	emit_signal("restart_requested")


func begin_match(p) -> void:
	player = p
	active = true


func show_end(title: String, sub: String) -> void:
	active = false
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


func consume_reload() -> bool:
	var r := _reload
	_reload = false
	return r


# ---------------------------------------------------------------- input
func _input(event: InputEvent) -> void:
	if not active:
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
	if p.distance_to(_fire_c) <= _fire_r * 1.15:
		_fire_touch = i
		fire_held = true
	elif p.distance_to(_jump_c) <= _jump_r * 1.25:
		_jump = true
	elif p.distance_to(_reload_c) <= _reload_r * 1.25:
		_reload = true
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
	_stick_rest = Vector2(170, s.y - 170)
	_hit_flash = max(0.0, _hit_flash - delta)
	_dmg_flash = max(0.0, _dmg_flash - delta * 2.0)
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

	# score + timer
	var secs := int(max(0.0, _time_left))
	_text(_f_mid, Vector2(c.x, 40), "%d:%02d" % [secs / 60, secs % 60], Color.white, true)
	_text(_f_mid, Vector2(c.x - 90, 40), str(_scores[0]), Color(0.3, 0.6, 1.0), true)
	_text(_f_mid, Vector2(c.x + 90, 40), str(_scores[1]), Color(1.0, 0.35, 0.3), true)

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
	var ammo_txt := "RELOADING" if player.is_reloading() else "%d / %d" % [player.ammo, player.mag_size]
	_text(_f_mid, Vector2(c.x + 190, s.y - 30), ammo_txt, Color(1, 0.85, 0.3) if not player.is_reloading() else Color(1, 0.6, 0.2))

	if not player.alive:
		_text(_f_mid, Vector2(c.x, c.y - 60), "RESPAWN IN %d" % int(ceil(max(0.0, player.respawn_left))), Color.white, true)
