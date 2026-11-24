extends Spatial
# Builds the 4v4 map from code: a walled compound with two houses and cover.
# Blue spawns on the west side, red on the east side. Layout is point-symmetric.

# [x, z, size_x, size_y, size_z] - each entry is also mirrored through the origin
const COVER = [
	[5.0, 5.0, 2.0, 1.2, 2.0],
	[9.0, 14.0, 4.0, 1.1, 0.7],
	[22.0, 6.0, 3.0, 1.2, 3.0],
	[25.0, -3.0, 0.7, 1.1, 5.0],
	[30.0, -14.0, 2.0, 1.2, 2.0],
	[4.0, -15.0, 5.0, 1.1, 0.7],
	[15.0, 17.0, 4.4, 1.4, 2.0],
	[30.0, 14.0, 2.0, 1.2, 2.0],
	[11.0, 3.0, 0.7, 1.1, 4.0],
	[37.0, 0.0, 2.2, 2.4, 2.2],
	[0.0, 9.0, 2.0, 1.2, 2.0],
]

var spawns := [[], []]
var spawn_yaw := [-PI / 2.0, PI / 2.0]
var waypoints := []
var _solids := []
var _mats := {}


func _ready() -> void:
	_build()


func random_waypoint() -> Vector3:
	return waypoints[randi() % waypoints.size()]


func _mat(c: Color) -> SpatialMaterial:
	var key := c.to_html()
	if not _mats.has(key):
		var m := SpatialMaterial.new()
		m.albedo_color = c
		m.roughness = 0.95
		_mats[key] = m
	return _mats[key]


func add_box(center: Vector3, size: Vector3, col: Color, track := true) -> void:
	var body := StaticBody.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.translation = center
	var cs := CollisionShape.new()
	var bs := BoxShape.new()
	bs.extents = size * 0.5
	cs.shape = bs
	body.add_child(cs)
	var mi := MeshInstance.new()
	var cm := CubeMesh.new()
	cm.size = size
	mi.mesh = cm
	mi.material_override = _mat(col)
	body.add_child(mi)
	add_child(body)
	if track:
		_solids.append(Rect2(center.x - size.x * 0.5 - 1.2, center.z - size.z * 0.5 - 1.2, size.x + 2.4, size.z + 2.4))


func _deco(center: Vector3, size: Vector3, col: Color) -> void:
	var mi := MeshInstance.new()
	var cm := CubeMesh.new()
	cm.size = size
	mi.mesh = cm
	mi.material_override = _mat(col)
	mi.translation = center
	add_child(mi)


func _wall_x(cx: float, z: float, length: float, gap: float, off: float, h: float, dh: float, t: float, col: Color) -> void:
	var gc := cx + off
	var left_len := (gc - gap * 0.5) - (cx - length * 0.5)
	var right_len := (cx + length * 0.5) - (gc + gap * 0.5)
	add_box(Vector3(cx - length * 0.5 + left_len * 0.5, h * 0.5, z), Vector3(left_len, h, t), col)
	add_box(Vector3(cx + length * 0.5 - right_len * 0.5, h * 0.5, z), Vector3(right_len, h, t), col)
	add_box(Vector3(gc, dh + (h - dh) * 0.5, z), Vector3(gap, h - dh, t), col)


func _wall_z(x: float, cz: float, length: float, gap: float, off: float, h: float, dh: float, t: float, col: Color) -> void:
	var gc := cz + off
	var a_len := (gc - gap * 0.5) - (cz - length * 0.5)
	var b_len := (cz + length * 0.5) - (gc + gap * 0.5)
	add_box(Vector3(x, h * 0.5, cz - length * 0.5 + a_len * 0.5), Vector3(t, h, a_len), col)
	add_box(Vector3(x, h * 0.5, cz + length * 0.5 - b_len * 0.5), Vector3(t, h, b_len), col)
	add_box(Vector3(x, dh + (h - dh) * 0.5, gc), Vector3(t, h - dh, gap), col)


func _house(c: Vector3, w: float, d: float, col: Color) -> void:
	var t := 0.5
	var h := 3.4
	var dh := 2.6
	var door := 3.6
	_wall_x(c.x, c.z - d * 0.5, w, door, -2.0, h, dh, t, col)
	_wall_x(c.x, c.z + d * 0.5, w, door, 2.0, h, dh, t, col)
	_wall_z(c.x - w * 0.5, c.z, d, door, 0.0, h, dh, t, col)
	_wall_z(c.x + w * 0.5, c.z, d, door, 1.0, h, dh, t, col)
	add_box(Vector3(c.x, h + 0.2, c.z), Vector3(w + 0.8, 0.4, d + 0.8), col.darkened(0.35), false)
	add_box(Vector3(c.x + 2.5, 0.6, c.z - 1.5), Vector3(1.6, 1.2, 1.6), Color(0.45, 0.33, 0.2))


func _build() -> void:
	var wall_col := Color(0.62, 0.57, 0.5)
	var crate_col := Color(0.5, 0.36, 0.22)
	# ground + decoration
	add_box(Vector3(0, -0.5, 0), Vector3(84, 1, 54), Color(0.38, 0.45, 0.34), false)
	_deco(Vector3(0, 0.01, 0), Vector3(84, 0.02, 7), Color(0.25, 0.25, 0.27))
	_deco(Vector3(-33, 0.01, 0), Vector3(8, 0.02, 22), Color(0.18, 0.3, 0.55))
	_deco(Vector3(33, 0.01, 0), Vector3(8, 0.02, 22), Color(0.55, 0.2, 0.18))
	# perimeter
	add_box(Vector3(0, 2.5, -27), Vector3(84, 5, 1), wall_col, false)
	add_box(Vector3(0, 2.5, 27), Vector3(84, 5, 1), wall_col, false)
	add_box(Vector3(-42, 2.5, 0), Vector3(1, 5, 54), wall_col, false)
	add_box(Vector3(42, 2.5, 0), Vector3(1, 5, 54), wall_col, false)
	# houses (point-symmetric)
	_house(Vector3(16, 0, -10), 12.0, 9.0, wall_col)
	_house(Vector3(-16, 0, 10), 12.0, 9.0, wall_col)
	# cover
	for e in COVER:
		add_box(Vector3(e[0], e[3] * 0.5, e[1]), Vector3(e[2], e[3], e[4]), crate_col)
		add_box(Vector3(-e[0], e[3] * 0.5, -e[1]), Vector3(e[2], e[3], e[4]), crate_col)
	add_box(Vector3(0, 0.6, 0), Vector3(3, 1.2, 3), Color(0.4, 0.4, 0.45))
	# spawns
	for z in [-9.0, -3.0, 3.0, 9.0]:
		spawns[0].append(Vector3(-33, 0.3, z))
		spawns[1].append(Vector3(33, 0.3, z))
	# waypoints
	for x in [-36.0, -28.0, -20.0, -10.0, 0.0, 10.0, 20.0, 28.0, 36.0]:
		for z in [-20.0, -10.0, 0.0, 10.0, 20.0]:
			var p := Vector2(x, z)
			var ok := true
			for r in _solids:
				if r.has_point(p):
					ok = false
					break
			if ok:
				waypoints.append(Vector3(x, 0.3, z))
	waypoints.append(Vector3(16, 0.3, -10))
	waypoints.append(Vector3(-16, 0.3, 10))
