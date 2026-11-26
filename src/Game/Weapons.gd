extends Reference
# Weapon table. Tune damage / fire rate / ammo / hearing range here.
# kind: "gun" (bullets), "rocket" (RPG), "throw" (grenade)
# hear = how far (meters) the shot can be heard. Louder = further.

const ORDER := ["pistol", "rifle", "rpg", "grenade"]

const DEFS := {
	"pistol": {
		"label": "PISTOL", "short": "PST", "kind": "gun",
		"damage": 18.0, "head": 2.0, "interval": 0.30, "mag": 12, "pickup_reserve": 24,
		"reload": 1.4, "spread": 0.010, "speed": 160.0, "range": 90.0,
		"shot": "shot_pistol", "reload_snd": "reload_pistol", "hear": 90.0,
		"color": Color(1.0, 0.9, 0.3)
	},
	"rifle": {
		"label": "RIFLE", "short": "RFL", "kind": "gun",
		"damage": 25.0, "head": 1.8, "interval": 0.09, "mag": 30, "pickup_reserve": 60,
		"reload": 2.1, "spread": 0.018, "speed": 190.0, "range": 160.0,
		"shot": "shot_rifle", "reload_snd": "reload_rifle", "hear": 150.0,
		"color": Color(1.0, 0.55, 0.15)
	},
	"rpg": {
		"label": "RPG", "short": "RPG", "kind": "rocket",
		"damage": 130.0, "radius": 8.5, "interval": 0.9, "mag": 1, "pickup_reserve": 2,
		"reload": 3.2, "spread": 0.0, "speed": 45.0, "range": 160.0,
		"shot": "rocket_launch", "reload_snd": "reload_rpg", "hear": 170.0,
		"color": Color(1.0, 0.2, 0.2)
	},
	"grenade": {
		"label": "GRENADE", "short": "GRN", "kind": "throw",
		"damage": 110.0, "radius": 7.0, "interval": 1.0, "mag": 1, "pickup_reserve": 0,
		"count": 2, "fuse": 2.4, "throw_speed": 17.0,
		"shot": "grenade_throw", "reload_snd": "", "hear": 40.0,
		"color": Color(0.3, 0.9, 0.3)
	},
}

# non-weapon pickups
const MEDKIT_HEAL := 50.0
const PICKUP_COLORS := {
	"medkit": Color(0.95, 0.95, 0.95),
	"ammo": Color(0.3, 0.6, 1.0),
}
