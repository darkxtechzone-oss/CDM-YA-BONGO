extends Node
# Sound manager (autoload "Sfx"). Put files in res://assets/sounds/<name>.ogg|wav|mp3
# Missing files are simply silent. Volume falls off with distance to the camera.

const DIR := "res://assets/sounds/"
const EXTS := ["ogg", "wav", "mp3"]
const POOL := 20

var volume := 1.0
var _streams := {}
var _players := []
var _next := 0
var _ui := []
var _ui_next := 0


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	for i in range(POOL):
		var p := AudioStreamPlayer3D.new()
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		p.max_db = 6.0
		add_child(p)
		_players.append(p)
	for i in range(4):
		var u := AudioStreamPlayer.new()
		add_child(u)
		_ui.append(u)


func _get_stream(sname: String):
	if sname == "":
		return null
	if _streams.has(sname):
		return _streams[sname]
	var found = null
	for e in EXTS:
		var path: String = DIR + sname + "." + e
		if ResourceLoader.exists(path):
			found = load(path)
			break
	_streams[sname] = found
	return found


# world sound: heard up to `hear` meters, quadratic fall-off
func play_at(sname: String, pos: Vector3, hear: float = 60.0, gain_db: float = 0.0) -> void:
	var st = _get_stream(sname)
	if st == null:
		return
	var cam := get_viewport().get_camera()
	var d := 0.0
	if cam != null:
		d = cam.global_transform.origin.distance_to(pos)
	if d >= hear:
		return
	var k: float = 1.0 - d / hear
	var p: AudioStreamPlayer3D = _players[_next]
	_next = (_next + 1) % POOL
	p.stream = st
	p.translation = pos
	p.unit_db = linear2db(max(k * k, 0.0001)) + gain_db + linear2db(max(volume, 0.0001))
	p.pitch_scale = rand_range(0.95, 1.05)
	p.play()


# non-positional sound (UI, hit markers, own damage)
func play_ui(sname: String, gain_db: float = 0.0) -> void:
	var st = _get_stream(sname)
	if st == null:
		return
	var u: AudioStreamPlayer = _ui[_ui_next]
	_ui_next = (_ui_next + 1) % _ui.size()
	u.stream = st
	u.volume_db = gain_db + linear2db(max(volume, 0.0001))
	u.play()
