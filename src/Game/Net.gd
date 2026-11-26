extends Node
# Autoload "Net": player profile (name / character / server url) + websocket client.

signal net_open
signal net_closed(reason)
signal net_message(m)

const DEFAULT_URL := "wss://YOUR-APP.onrender.com"
const PROFILE := "user://profile.cfg"

var url := DEFAULT_URL
var player_name := "Player"
var char_name := "Mannequin"
var my_id := 0
var is_open := false

var _ws: WebSocketClient = null
var _ping := 0.0


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	var cf := ConfigFile.new()
	if cf.load(PROFILE) == OK:
		url = cf.get_value("p", "url", DEFAULT_URL)
		player_name = cf.get_value("p", "name", "Player")
		char_name = cf.get_value("p", "char", "Mannequin")


func save_profile() -> void:
	var cf := ConfigFile.new()
	cf.set_value("p", "url", url)
	cf.set_value("p", "name", player_name)
	cf.set_value("p", "char", char_name)
	cf.save(PROFILE)


func open() -> bool:
	close()
	_ws = WebSocketClient.new()
	_ws.connect("connection_established", self, "_on_open")
	_ws.connect("connection_closed", self, "_on_close")
	_ws.connect("connection_error", self, "_on_error")
	_ws.connect("data_received", self, "_on_data")
	var u := url.strip_edges()
	if u.begins_with("https://"):
		u = "wss://" + u.substr(8)
	elif u.begins_with("http://"):
		u = "ws://" + u.substr(7)
	return _ws.connect_to_url(u) == OK


func close() -> void:
	if _ws != null:
		_ws.disconnect_from_host()
		_ws = null
	is_open = false
	my_id = 0


func send(d: Dictionary) -> void:
	if _ws == null or not is_open:
		return
	_ws.get_peer(1).put_packet(JSON.print(d).to_utf8())


func _process(delta: float) -> void:
	if _ws == null:
		return
	if _ws.get_connection_status() != NetworkedMultiplayerPeer.CONNECTION_DISCONNECTED:
		_ws.poll()
	if is_open:
		_ping += delta
		if _ping > 20.0:
			_ping = 0.0
			send({"t": "ping"})


func _on_open(_proto) -> void:
	is_open = true
	_ws.get_peer(1).set_write_mode(WebSocketPeer.WRITE_MODE_TEXT)
	emit_signal("net_open")


func _on_close(_clean = false) -> void:
	var was := is_open
	is_open = false
	if was:
		emit_signal("net_closed", "Connection lost")


func _on_error() -> void:
	is_open = false
	emit_signal("net_closed", "Could not connect to server")


func _on_data() -> void:
	var txt: String = _ws.get_peer(1).get_packet().get_string_from_utf8()
	var r := JSON.parse(txt)
	if r.error == OK and typeof(r.result) == TYPE_DICTIONARY:
		emit_signal("net_message", r.result)
