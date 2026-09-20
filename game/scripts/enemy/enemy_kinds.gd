class_name EnemyKinds
extends RefCounted
## Who you fight, as a table of numbers.
##
## Jurek asked for five things: men who punch, men with knives, men with pistols, rifles
## and RPGs, and big ones that are harder to web. They are one actor driven by one row of
## this table rather than six classes, because everything that actually differs between
## them is a number — how close they want to be, how hard they hit, how much webbing it
## takes to stop them. A subclass per thug would be six files that each override two
## constants and then drift apart.
##
## STATIC, and no autoload. Godot runs tools and tests with `--script`, which has no
## autoloads at all, so a table of numbers that needs a live SceneTree cannot be measured
## by anything. This project has learned that three separate times.

## `reach` is how close it tries to get, in metres. `dps` is damage a second at its own
## rate. `web` is how many web hits it takes to glue — the whole point of the big ones.
static var KINDS := {
	# Fists. Has to be right on top of you, hits hard when it gets there, and dies fast.
	"brawler": {
		name = "THUG", hp = 34.0, speed = 6.4, reach = 2.0, web = 1,
		damage = 9.0, rate = 0.85, ranged = false, scale = 1.0,
		body = Color(0.38, 0.40, 0.50), trim = Color(0.78, 0.22, 0.20),
	},
	# A knife is a fist with better numbers and a worse temper: faster, closer, hurts more.
	"knifer": {
		name = "KNIFE", hp = 28.0, speed = 7.8, reach = 1.8, web = 1,
		damage = 14.0, rate = 0.62, ranged = false, scale = 0.98,
		body = Color(0.30, 0.32, 0.38), trim = Color(0.92, 0.94, 1.00),
	},
	# The first one that can hurt you from where you are hovering.
	"pistol": {
		name = "PISTOL", hp = 26.0, speed = 5.2, reach = 26.0, web = 1,
		damage = 6.0, rate = 0.95, ranged = true, muzzle_speed = 150.0,
		spread = 0.045, burst = 1, scale = 1.0,
		body = Color(0.34, 0.38, 0.52), trim = Color(0.62, 0.64, 0.70),
	},
	# Bursts, further out, and enough of them will take a suit apart.
	"rifle": {
		name = "RIFLE", hp = 32.0, speed = 4.6, reach = 48.0, web = 2,
		damage = 5.0, rate = 1.35, ranged = true, muzzle_speed = 210.0,
		spread = 0.028, burst = 3, scale = 1.02,
		body = Color(0.30, 0.40, 0.34), trim = Color(0.72, 0.76, 0.46),
	},
	# Slow, loud, and the only thing here that punishes hovering still.
	"rpg": {
		name = "RPG", hp = 30.0, speed = 3.8, reach = 70.0, web = 2,
		damage = 26.0, rate = 3.4, ranged = true, muzzle_speed = 52.0,
		spread = 0.01, burst = 1, rocket = true, blast = 7.0, scale = 1.04,
		body = Color(0.46, 0.33, 0.18), trim = Color(1.00, 0.62, 0.16),
	},
	# THE BIG ONE. Jurek: "dużych (których spiderman trudniej związać)". Four web hits
	# instead of one, and the webbing wears off him faster than it does off anyone else —
	# so gluing a brute is something you commit to rather than something you flick at him.
	"brute": {
		name = "BRUTE", hp = 150.0, speed = 4.8, reach = 3.0, web = 4,
		damage = 22.0, rate = 1.5, ranged = false, scale = 1.45,
		web_decay = 2.2, knockback_resist = 0.82,
		body = Color(0.30, 0.31, 0.34), trim = Color(1.00, 0.45, 0.10),
	},
}

## Every row, filled in with the defaults the sparse ones leave out. Reading a missing key
## off a Dictionary returns null and then fails somewhere else entirely, so nothing
## downstream is allowed to guess.
static func spec(kind: String) -> Dictionary:
	var base := {
		name = "THUG", hp = 30.0, speed = 5.0, reach = 2.0, web = 1,
		damage = 8.0, rate = 1.0, ranged = false, muzzle_speed = 150.0,
		spread = 0.04, burst = 1, rocket = false, blast = 0.0, scale = 1.0,
		web_decay = 1.0, knockback_resist = 0.0,
		body = Color(0.2, 0.2, 0.24), trim = Color(0.4, 0.4, 0.44),
	}
	var row: Dictionary = KINDS.get(kind, {})
	for k in row:
		base[k] = row[k]
	base["kind"] = kind
	return base

static func names() -> Array:
	return KINDS.keys()
