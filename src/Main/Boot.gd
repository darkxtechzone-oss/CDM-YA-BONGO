extends Node
# DEBUG boot screen: checks every script loads, starts Main, and shows a report
# on screen (so errors are visible on the phone). Remove later by setting
# run/main_scene back to res://src/Main/Main.tscn

const FILES := [
	"res://src/Game/Weapons.gd", "res://src/Game/Zone.gd", "res://src/Game/CharacterLib.gd",
	"res://src/Game/Arena.gd", "res://src/Game/BRMap.gd", "res://src/Player/Mannequiny.gd",
	"res://src/Game/Fighter.gd", "res://src/Game/HumanPlayer.gd", "res://src/Game/RemoteFighter.gd",
	"res://src/Game/Bot.gd", "res://src/Game/Hud.gd", "res://src/Main/Main.gd",
]

var _lbl: Label


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.1, 0.92)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	layer.add_child(bg)
	_lbl = Label.new()
	_lbl.autowrap = true
	_lbl.anchor_right = 1.0
	_lbl.anchor_bottom = 1.0
	_lbl.margin_left = 20
	_lbl.margin_top = 20
	_lbl.margin_right = -20
	var f := DynamicFont.new()
	f.font_data = load("res://assets/fonts/Montserrat-Bold.ttf")
	f.size = 22
	_lbl.add_font_override("font", f)
	layer.add_child(_lbl)

	var tx := "CDM DEBUG\n"
	tx += "Sfx autoload: %s\n" % ("OK" if get_node_or_null("/root/Sfx") != null else "MISSING")
	tx += "Net autoload: %s\n" % ("OK" if get_node_or_null("/root/Net") != null else "MISSING")
	var bad := []
	for p in FILES:
		var s = load(p)
		var ok: bool = s != null and s is GDScript and s.can_instantiate()
		tx += "%s  %s\n" % ["OK  " if ok else "FAIL", p.get_file()]
		if not ok:
			bad.append(p)
	_lbl.text = tx
	if not bad.empty():
		_lbl.text += "\nSCRIPT ERROR in the FAIL files above.\nSend me a screenshot of this screen."
		return

	var sc = load("res://src/Main/Main.tscn")
	if sc == null:
		_lbl.text += "\nMain.tscn failed to load."
		return
	var m = sc.instance()
	add_child(m)
	yield(get_tree().create_timer(1.0), "timeout")
	var hud_ok: bool = m.get("hud") != null
	var cam_ok: bool = get_viewport().get_camera() != null
	tx += "\nMain started.\nHUD created: %s\nCamera active: %s\n" % [str(hud_ok), str(cam_ok)]
	_lbl.text = tx
	if hud_ok and cam_ok:
		yield(get_tree().create_timer(2.0), "timeout")
		_lbl.get_parent().queue_free()
	else:
		_lbl.text += "\nMain._ready stopped early. Send me a screenshot."
