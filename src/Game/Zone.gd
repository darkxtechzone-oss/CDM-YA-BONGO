extends Reference
# Battle-royale safe zone. Fully deterministic from the seed, so every online
# player computes the same circle from the match clock.

# radius at the start of each phase (last = final circle)
const R := [180.0, 115.0, 70.0, 36.0, 14.0, 6.0]
const HOLD := [40.0, 35.0, 30.0, 25.0, 20.0]     # seconds the circle waits
const SHRINK := [30.0, 25.0, 20.0, 15.0, 12.0]   # seconds it takes to shrink
const DPS := [1.0, 2.0, 4.0, 7.0, 10.0]          # damage / second outside

var centers := [Vector2.ZERO]


func _init(seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for i in range(HOLD.size()):
		var prev: Vector2 = centers[i]
		var room: float = R[i] - R[i + 1]
		var a: float = rng.randf_range(0.0, TAU)
		var d: float = sqrt(rng.randf()) * room * 0.8
		centers.append(prev + Vector2(cos(a), sin(a)) * d)


func state(t: float) -> Dictionary:
	var left := t
	for i in range(HOLD.size()):
		if left < HOLD[i]:
			return _mk(centers[i], R[i], i, false, HOLD[i] - left, centers[i + 1], R[i + 1])
		left -= HOLD[i]
		if left < SHRINK[i]:
			var f: float = left / SHRINK[i]
			var c: Vector2 = centers[i].linear_interpolate(centers[i + 1], f)
			var r: float = lerp(R[i], R[i + 1], f)
			return _mk(c, r, i, true, SHRINK[i] - left, centers[i + 1], R[i + 1])
		left -= SHRINK[i]
	var n: int = HOLD.size()
	return _mk(centers[n], R[n], n - 1, false, 0.0, centers[n], R[n])


func _mk(c: Vector2, r: float, phase: int, shrinking: bool, tl: float, nc: Vector2, nr: float) -> Dictionary:
	return {
		"center": c, "radius": r, "phase": phase, "shrinking": shrinking,
		"time_left": tl, "next_center": nc, "next_radius": nr, "dps": DPS[phase]
	}
