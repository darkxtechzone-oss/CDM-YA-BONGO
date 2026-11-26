extends "res://src/Game/Arena.gd"
# Big battle-royale map: a GRID x GRID town. 4 different building types are
# repeated over the cells, with roads, cover and loot. Built from the seed so
# every online player gets exactly the same map and loot.

const CELL := 70.0
const GRID := 5
const HALF := CELL * GRID * 0.5   # 175

var seed_v := 1
var loot := []     # [{"kind": String, "pos": Vector3}]
var _rng := RandomNumberGenerator.new()

const LOOT_OUT := [["pistol", 26], ["rifle", 14], ["rpg", 4], ["grenade", 18], ["medkit", 16], ["ammo", 16]]
const LOOT_IN := [["pistol", 16], ["rifle", 30], ["rpg", 10], ["grenade", 18], ["medkit", 14], ["ammo", 12]]


func _roll(table: Array) -> String:
	var total := 0
	for e in table:
		total += int(e[1])
	var r := _rng.randi() % total
	for e in table:
		r -= int(e[1])
		if r < 0:
			return String(e[0])
	return "pistol"


func _free(x: float, z: float) -> bool:
	var p := Vector2(x, z)
	for r in _solids:
		if r.has_point(p):
			return false
	return true


func _add_loot(x: float, z: float, inside: bool) -> void:
	loot.append({"kind": _roll(LOOT_IN if inside else LOOT_OUT), "pos": Vector3(x, 0.4, z)})


func _low_wall_x(cx: float, z: float, length: float, gap: float, h: float, t: float, col: Color) -> void:
	var seg := (length - gap) * 0.5
	add_box(Vector3(cx - gap * 0.5 - seg * 0.5, h * 0.5, z), Vector3(seg, h, t), col)
	add_box(Vector3(cx + gap * 0.5 + seg * 0.5, h * 0.5, z), Vector3(seg, h, t), col)


func _low_wall_z(x: float, cz: float, length: float, gap: float, h: float, t: float, col: Color) -> void:
	var seg := (length - gap) * 0.5
	add_box(Vector3(x, h * 0.5, cz - gap * 0.5 - seg * 0.5), Vector3(t, h, seg), col)
	add_box(Vector3(x, h * 0.5, cz + gap * 0.5 + seg * 0.5), Vector3(t, h, seg), col)


# ---- building type 1: house -------------------------------------------------
func _b_house(c: Vector3) -> void:
	_house(c, 12.0, 9.0, Color(0.66, 0.58, 0.46))
	_add_loot(c.x, c.z + 1.0, true)
	_add_loot(c.x - 3.0, c.z - 1.0, true)


# ---- building type 2: warehouse ---------------------------------------------
func _b_warehouse(c: Vector3) -> void:
	var col := Color(0.42, 0.5, 0.6)
	var h := 5.5
	var dh := 4.0
	var t := 0.5
	_wall_x(c.x, c.z - 6.0, 22.0, 5.0, 0.0, h, dh, t, col)
	_wall_x(c.x, c.z + 6.0, 22.0, 5.0, 4.0, h, dh, t, col)
	_wall_z(c.x - 11.0, c.z, 12.0, 4.0, 0.0, h, dh, t, col)
	_wall_z(c.x + 11.0, c.z, 12.0, 4.0, 0.0, h, dh, t, col)
	add_box(Vector3(c.x, h + 0.2, c.z), Vector3(23.0, 0.4, 13.0), col.darkened(0.4), false)
	var crate := Color(0.5, 0.36, 0.22)
	add_box(Vector3(c.x - 8.0, 1.0, c.z - 3.0), Vector3(2.4, 2.0, 2.4), crate)
	add_box(Vector3(c.x + 8.0, 1.0, c.z + 3.0), Vector3(2.4, 2.0, 2.4), crate)
	add_box(Vector3(c.x + 1.0, 0.7, c.z + 3.8), Vector3(1.8, 1.4, 1.8), crate)
	add_box(Vector3(c.x - 3.0, 0.7, c.z - 4.0), Vector3(1.8, 1.4, 1.8), crate)
	_add_loot(c.x - 4.0, c.z, true)
	_add_loot(c.x + 4.0, c.z - 1.0, true)
	_add_loot(c.x + 6.0, c.z + 1.0, true)


# ---- building type 3: compound (low walls, hut, silo) -----------------------
func _b_compound(c: Vector3) -> void:
	var col := Color(0.72, 0.46, 0.3)
	var wh := 1.4
	_low_wall_x(c.x, c.z - 11.0, 22.0, 5.0, wh, 0.5, col)
	_low_wall_x(c.x, c.z + 11.0, 22.0, 5.0, wh, 0.5, col)
	_low_wall_z(c.x - 11.0, c.z, 22.0, 5.0, wh, 0.5, col)
	_low_wall_z(c.x + 11.0, c.z, 22.0, 5.0, wh, 0.5, col)
	# hut with a door in the north and south wall
	var hc := Vector3(c.x - 4.0, 0, c.z)
	_wall_x(hc.x, hc.z - 3.0, 6.0, 2.6, 0.0, 3.0, 2.3, 0.4, col.lightened(0.15))
	_wall_x(hc.x, hc.z + 3.0, 6.0, 2.6, 0.0, 3.0, 2.3, 0.4, col.lightened(0.15))
	add_box(Vector3(hc.x - 3.0, 1.5, hc.z), Vector3(0.4, 3.0, 6.0), col.lightened(0.15))
	add_box(Vector3(hc.x + 3.0, 1.5, hc.z), Vector3(0.4, 3.0, 6.0), col.lightened(0.15))
	add_box(Vector3(hc.x, 3.2, hc.z), Vector3(7.0, 0.4, 7.0), col.darkened(0.4), false)
	# silo
	add_box(Vector3(c.x + 6.0, 4.5, c.z + 4.0), Vector3(4.0, 9.0, 4.0), Color(0.78, 0.78, 0.8))
	add_box(Vector3(c.x + 6.0, 0.6, c.z - 5.0), Vector3(2.0, 1.2, 2.0), Color(0.5, 0.36, 0.22))
	_add_loot(hc.x, hc.z, true)
	_add_loot(c.x + 6.0, c.z - 1.5, true)
	_add_loot(c.x - 8.0, c.z + 7.0, false)


# ---- building type 4: bunker -------------------------------------------------
func _b_bunker(c: Vector3) -> void:
	var col := Color(0.42, 0.45, 0.42)
	var h := 2.8
	var dh := 2.2
	_wall_x(c.x, c.z - 4.5, 9.0, 2.6, 0.0, h, dh, 0.6, col)
	_wall_x(c.x, c.z + 4.5, 9.0, 2.6, 0.0, h, dh, 0.6, col)
	add_box(Vector3(c.x - 4.5, h * 0.5, c.z), Vector3(0.6, h, 9.0), col)
	add_box(Vector3(c.x + 4.5, h * 0.5, c.z), Vector3(0.6, h, 9.0), col)
	add_box(Vector3(c.x, h + 0.35, c.z), Vector3(10.0, 0.7, 10.0), col.darkened(0.3), false)
	var sand := Color(0.6, 0.54, 0.36)
	add_box(Vector3(c.x - 5.5, 0.45, c.z - 8.0), Vector3(3.0, 0.9, 0.8), sand)
	add_box(Vector3(c.x + 5.5, 0.45, c.z - 8.0), Vector3(3.0, 0.9, 0.8), sand)
	add_box(Vector3(c.x - 5.5, 0.45, c.z + 8.0), Vector3(3.0, 0.9, 0.8), sand)
	add_box(Vector3(c.x + 5.5, 0.45, c.z + 8.0), Vector3(3.0, 0.9, 0.8), sand)
	_add_loot(c.x - 2.5, c.z + 2.5, true)
	_add_loot(c.x + 2.5, c.z - 2.5, true)


func _build() -> void:
	_rng.seed = seed_v
	var span := CELL * GRID
	var wall_col := Color(0.45, 0.42, 0.4)
	add_box(Vector3(0, -0.5, 0), Vector3(span + 10.0, 1, span + 10.0), Color(0.36, 0.46, 0.31), false)
	for i in range(GRID + 1):
		var p := -HALF + i * CELL
		_deco(Vector3(p, 0.01, 0), Vector3(6, 0.02, span), Color(0.24, 0.24, 0.26))
		_deco(Vector3(0, 0.012, p), Vector3(span, 0.02, 6), Color(0.24, 0.24, 0.26))
	var e := HALF + 5.5
	add_box(Vector3(0, 4, -e), Vector3(span + 14.0, 8, 1), wall_col, false)
	add_box(Vector3(0, 4, e), Vector3(span + 14.0, 8, 1), wall_col, false)
	add_box(Vector3(-e, 4, 0), Vector3(1, 8, span + 14.0), wall_col, false)
	add_box(Vector3(e, 4, 0), Vector3(1, 8, span + 14.0), wall_col, false)

	var rock := Color(0.45, 0.45, 0.42)
	var crate := Color(0.5, 0.36, 0.22)
	for gx in range(GRID):
		for gz in range(GRID):
			var c := Vector3(-HALF + CELL * (gx + 0.5), 0, -HALF + CELL * (gz + 0.5))
			match (gx + 2 * gz) % 4:
				0:
					_b_house(c)
				1:
					_b_warehouse(c)
				2:
					_b_compound(c)
				_:
					_b_bunker(c)
			# cover around the building
			for k in range(4):
				var a: float = _rng.randf_range(0.0, TAU)
				var r: float = _rng.randf_range(19.0, 27.0)
				var sz := Vector3(_rng.randf_range(1.5, 3.2), _rng.randf_range(1.0, 1.8), _rng.randf_range(1.5, 3.2))
				add_box(Vector3(c.x + cos(a) * r, sz.y * 0.5, c.z + sin(a) * r), sz, rock if k % 2 == 0 else crate)
			# loose loot outside
			var placed := 0
			var tries := 0
			while placed < 3 and tries < 20:
				tries += 1
				var a2: float = _rng.randf_range(0.0, TAU)
				var r2: float = _rng.randf_range(15.0, 28.0)
				var lx: float = c.x + cos(a2) * r2
				var lz: float = c.z + sin(a2) * r2
				if _free(lx, lz):
					_add_loot(lx, lz, false)
					placed += 1

	# spawn points: road crossings (not corners), shuffled with the seeded rng
	var pts := []
	for i in range(GRID + 1):
		for j in range(GRID + 1):
			if (i == 0 or i == GRID) and (j == 0 or j == GRID):
				continue
			pts.append(Vector3(-HALF + i * CELL, 0.3, -HALF + j * CELL))
	for i in range(pts.size() - 1, 0, -1):
		var j2: int = _rng.randi() % (i + 1)
		var tmp = pts[i]
		pts[i] = pts[j2]
		pts[j2] = tmp
	spawns = [pts, pts]

	# bot waypoints along the roads
	for i in range(GRID + 1):
		for j in range(GRID + 1):
			waypoints.append(Vector3(-HALF + i * CELL, 0.3, -HALF + j * CELL))
	for i in range(GRID):
		for j in range(GRID + 1):
			waypoints.append(Vector3(-HALF + CELL * (i + 0.5), 0.3, -HALF + j * CELL))
			waypoints.append(Vector3(-HALF + j * CELL, 0.3, -HALF + CELL * (i + 0.5)))
