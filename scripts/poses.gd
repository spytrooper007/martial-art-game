extends RefCounted
## Procedural pose library. Each pose is a set of joint positions in the stickman's
## local space. The character faces -Z, so its right hand side is +X.
## Shoulders, hip joints and neck are derived from these in stickman.gd.

const GUARD := {
	"hips": Vector3(0.0, 0.98, 0.0),
	"chest": Vector3(0.0, 1.48, -0.02),
	"head": Vector3(0.0, 1.72, -0.04),
	"l_elbow": Vector3(-0.28, 1.25, -0.15),
	"l_hand": Vector3(-0.13, 1.50, -0.34),
	"r_elbow": Vector3(0.28, 1.22, -0.05),
	"r_hand": Vector3(0.12, 1.45, -0.22),
	"l_knee": Vector3(-0.15, 0.52, -0.18),
	"l_foot": Vector3(-0.16, 0.05, -0.26),
	"r_knee": Vector3(0.18, 0.52, 0.12),
	"r_foot": Vector3(0.21, 0.05, 0.22),
}

const BLOCK_OVER := {
	"hips": Vector3(0.0, 0.94, 0.02),
	"chest": Vector3(0.0, 1.44, 0.0),
	"head": Vector3(0.0, 1.66, 0.02),
	"l_elbow": Vector3(-0.18, 1.34, -0.30),
	"l_hand": Vector3(0.06, 1.62, -0.30),
	"r_elbow": Vector3(0.18, 1.32, -0.28),
	"r_hand": Vector3(-0.06, 1.57, -0.33),
}

const DUCK := {
	"hips": Vector3(0.0, 0.58, 0.12),
	"chest": Vector3(0.0, 0.96, -0.14),
	"head": Vector3(0.0, 1.16, -0.25),
	"l_elbow": Vector3(-0.25, 0.84, -0.30),
	"l_hand": Vector3(-0.11, 1.06, -0.40),
	"r_elbow": Vector3(0.25, 0.84, -0.26),
	"r_hand": Vector3(0.11, 1.03, -0.37),
	"l_knee": Vector3(-0.22, 0.48, -0.42),
	"l_foot": Vector3(-0.22, 0.05, -0.30),
	"r_knee": Vector3(0.22, 0.14, 0.12),
	"r_foot": Vector3(0.24, 0.05, 0.50),
}

const DODGE_LEFT := {
	"hips": Vector3(-0.15, 0.86, 0.0),
	"chest": Vector3(-0.42, 1.30, 0.02),
	"head": Vector3(-0.58, 1.49, 0.02),
	"l_elbow": Vector3(-0.66, 1.08, -0.10),
	"l_hand": Vector3(-0.55, 1.33, -0.26),
	"r_elbow": Vector3(-0.16, 1.08, -0.12),
	"r_hand": Vector3(-0.33, 1.32, -0.26),
	"l_knee": Vector3(-0.36, 0.46, -0.02),
	"l_foot": Vector3(-0.48, 0.05, 0.0),
	"r_knee": Vector3(0.16, 0.46, 0.04),
	"r_foot": Vector3(0.38, 0.05, 0.06),
}

const DODGE_BACK := {
	"hips": Vector3(0.0, 0.90, 0.16),
	"chest": Vector3(0.0, 1.36, 0.32),
	"head": Vector3(0.0, 1.57, 0.40),
	"l_elbow": Vector3(-0.27, 1.14, 0.16),
	"l_hand": Vector3(-0.13, 1.40, -0.02),
	"r_elbow": Vector3(0.27, 1.12, 0.20),
	"r_hand": Vector3(0.12, 1.36, 0.04),
	"l_knee": Vector3(-0.15, 0.50, -0.12),
	"l_foot": Vector3(-0.16, 0.05, -0.22),
	"r_knee": Vector3(0.17, 0.44, 0.36),
	"r_foot": Vector3(0.20, 0.05, 0.48),
}

const DODGE_FORWARD := {
	"hips": Vector3(0.0, 0.78, -0.12),
	"chest": Vector3(0.05, 1.18, -0.42),
	"head": Vector3(0.07, 1.36, -0.56),
	"l_elbow": Vector3(-0.24, 1.02, -0.50),
	"l_hand": Vector3(-0.10, 1.24, -0.62),
	"r_elbow": Vector3(0.28, 1.00, -0.42),
	"r_hand": Vector3(0.14, 1.20, -0.58),
	"l_knee": Vector3(-0.16, 0.46, -0.52),
	"l_foot": Vector3(-0.17, 0.05, -0.40),
	"r_knee": Vector3(0.18, 0.32, 0.18),
	"r_foot": Vector3(0.21, 0.05, 0.42),
}

const JUMP := {
	"hips": Vector3(0.0, 1.00, 0.0),
	"chest": Vector3(0.0, 1.47, -0.06),
	"head": Vector3(0.0, 1.69, -0.09),
	"l_knee": Vector3(-0.15, 0.86, -0.32),
	"l_foot": Vector3(-0.15, 0.52, -0.08),
	"r_knee": Vector3(0.15, 0.80, -0.26),
	"r_foot": Vector3(0.15, 0.46, 0.02),
}

const STRIKE := {
	"hips": Vector3(0.0, 0.96, -0.04),
	"chest": Vector3(0.04, 1.46, -0.14),
	"head": Vector3(0.04, 1.69, -0.16),
	"l_elbow": Vector3(-0.30, 1.20, -0.10),
	"l_hand": Vector3(-0.16, 1.44, -0.26),
	"r_elbow": Vector3(0.10, 1.42, -0.48),
	"r_hand": Vector3(0.0, 1.47, -0.80),
}

const HIT := {
	"hips": Vector3(0.0, 0.95, 0.06),
	"chest": Vector3(0.0, 1.42, 0.22),
	"head": Vector3(0.0, 1.62, 0.34),
	"l_elbow": Vector3(-0.36, 1.28, 0.12),
	"l_hand": Vector3(-0.48, 1.08, 0.02),
	"r_elbow": Vector3(0.36, 1.28, 0.12),
	"r_hand": Vector3(0.48, 1.08, 0.02),
}

const KNEEL := {
	"hips": Vector3(0.0, 0.62, 0.15),
	"chest": Vector3(0.0, 1.02, 0.02),
	"head": Vector3(0.0, 1.20, -0.10),
	"l_elbow": Vector3(-0.25, 0.80, -0.05),
	"l_hand": Vector3(-0.22, 0.58, -0.12),
	"r_elbow": Vector3(0.25, 0.80, -0.05),
	"r_hand": Vector3(0.22, 0.58, -0.12),
	"l_knee": Vector3(-0.18, 0.46, -0.36),
	"l_foot": Vector3(-0.18, 0.05, -0.28),
	"r_knee": Vector3(0.18, 0.10, 0.10),
	"r_foot": Vector3(0.20, 0.05, 0.50),
}

# --- Attacker poses (training dummy) ---

const WINDUP_HIGH := {
	"hips": Vector3(0.0, 0.96, 0.04),
	"chest": Vector3(0.06, 1.46, 0.10),
	"head": Vector3(0.05, 1.69, 0.06),
	"r_elbow": Vector3(0.38, 1.38, 0.26),
	"r_hand": Vector3(0.28, 1.60, 0.36),
}

const PUNCH_HIGH := {
	"hips": Vector3(0.0, 0.96, -0.08),
	"chest": Vector3(-0.05, 1.47, -0.18),
	"head": Vector3(-0.05, 1.69, -0.22),
	"r_elbow": Vector3(0.14, 1.55, -0.45),
	"r_hand": Vector3(0.0, 1.62, -0.92),
	"r_knee": Vector3(0.18, 0.52, 0.18),
	"r_foot": Vector3(0.21, 0.05, 0.34),
}

const WINDUP_LOW := {
	"hips": Vector3(0.0, 0.88, 0.04),
	"chest": Vector3(-0.06, 1.38, -0.08),
	"head": Vector3(-0.07, 1.60, -0.12),
	"r_knee": Vector3(0.26, 0.56, 0.36),
	"r_foot": Vector3(0.32, 0.22, 0.52),
	"r_elbow": Vector3(0.38, 1.12, 0.02),
	"r_hand": Vector3(0.30, 1.30, -0.16),
}

const SWEEP_LOW := {
	"hips": Vector3(0.0, 0.70, 0.04),
	"chest": Vector3(-0.12, 1.14, 0.14),
	"head": Vector3(-0.14, 1.36, 0.16),
	"l_elbow": Vector3(-0.34, 0.96, 0.08),
	"l_hand": Vector3(-0.30, 0.74, -0.08),
	"r_elbow": Vector3(0.40, 0.92, 0.18),
	"r_hand": Vector3(0.42, 0.62, 0.04),
	"l_knee": Vector3(-0.22, 0.38, -0.04),
	"l_foot": Vector3(-0.22, 0.05, 0.06),
	"r_knee": Vector3(0.10, 0.26, -0.46),
	"r_foot": Vector3(-0.05, 0.12, -0.95),
}


static func with(base: Dictionary, over: Dictionary) -> Dictionary:
	var p := base.duplicate()
	for k in over:
		p[k] = over[k]
	return p


static func mirror(p: Dictionary) -> Dictionary:
	var out := {}
	for k in p:
		var key: String = k
		var v: Vector3 = p[k]
		var nk := key
		if key.begins_with("l_"):
			nk = "r_" + key.substr(2)
		elif key.begins_with("r_"):
			nk = "l_" + key.substr(2)
		out[nk] = Vector3(-v.x, v.y, v.z)
	return out
