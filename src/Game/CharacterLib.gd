extends Reference
# Finds and loads playable characters from res://assets/characters
# Supported: assets/characters/Name.glb  (or .gltf/.tscn/.scn/.dae)
#       or:  assets/characters/Name/Name.glb
# "Mannequin" is the built-in default character.

const DIR := "res://assets/characters"
const EXTS := ["glb", "gltf", "tscn", "scn", "dae"]
const HEIGHT := 1.75
const DEFAULT_NAME := "Mannequin"


static func list() -> Array:
	var out := [DEFAULT_NAME]
	var d := Directory.new()
	if d.open(DIR) != OK:
		return out
	d.list_dir_begin(true, true)
	var f := d.get_next()
	while f != "":
		if d.current_is_dir():
			if path_for(f) != "" and not out.has(f):
				out.append(f)
		else:
			var n := f
			for suf in [".import", ".remap"]:
				if n.ends_with(suf):
					n = n.substr(0, n.length() - suf.length())
			if EXTS.has(n.get_extension().to_lower()):
				var base := n.get_basename()
				if not out.has(base):
					out.append(base)
		f = d.get_next()
	d.list_dir_end()
	return out


static func path_for(cname: String) -> String:
	if cname == DEFAULT_NAME or cname == "":
		return ""
	for e in EXTS:
		var p1: String = "%s/%s.%s" % [DIR, cname, e]
		if ResourceLoader.exists(p1):
			return p1
		var p2: String = "%s/%s/%s.%s" % [DIR, cname, cname, e]
		if ResourceLoader.exists(p2):
			return p2
	return ""


# returns a Spatial (feet at y=0, ~1.75 m tall) or null. Meta "anim" = AnimationPlayer or null
static func make(cname: String):
	var path := path_for(cname)
	if path == "":
		return null
	var res = load(path)
	if res == null or not (res is PackedScene):
		return null
	var inst = res.instance()
	if not (inst is Spatial):
		return null
	var wrap := Spatial.new()
	var fit := Spatial.new()
	wrap.add_child(fit)
	fit.add_child(inst)
	var acc := {}
	_collect(inst, Transform.IDENTITY, acc)
	if acc.has("box"):
		var box: AABB = acc["box"]
		var h: float = max(box.size.y, 0.001)
		var s: float = HEIGHT / h
		var cx: float = box.position.x + box.size.x * 0.5
		var cz: float = box.position.z + box.size.z * 0.5
		fit.scale = Vector3(s, s, s)
		fit.translation = Vector3(-cx * s, -box.position.y * s, -cz * s)
	wrap.set_meta("anim", _find_anim(inst))
	return wrap


static func _collect(n: Node, xf: Transform, acc: Dictionary) -> void:
	var t := xf
	if n is Spatial:
		t = xf * (n as Spatial).transform
	if n is MeshInstance:
		var a: AABB = (n as MeshInstance).get_aabb()
		var tb: AABB = t.xform(a)
		if acc.has("box"):
			acc["box"] = (acc["box"] as AABB).merge(tb)
		else:
			acc["box"] = tb
	for c in n.get_children():
		_collect(c, t, acc)


static func _find_anim(n: Node):
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r = _find_anim(c)
		if r != null:
			return r
	return null


# pick an animation whose name contains one of the keys (idle / run / jump)
static func pick_anim(ap: AnimationPlayer, keys: Array) -> String:
	for a in ap.get_animation_list():
		var low: String = String(a).to_lower()
		for k in keys:
			if low.find(k) != -1:
				return a
	return ""
