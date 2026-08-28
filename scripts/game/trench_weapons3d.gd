extends RefCounted
# =================================================================================================
# LA TRANCHÉE — VUE 3D (§8.152 LOT 3D-B) — LES QUATRE ARMES ASSEMBLÉES.
#
# Port de `src/weapons/models/{pistol,smg,rifle}.js` (1 114 l.) et de la MOITIÉ VUE de
# `src/weapons/defs.js` (320 l.).
#
# ╔═ ⚠️⚠️ CE FICHIER NE PORTE **PAS** LES RÈGLES — ET C'EST LA DÉCISION LA PLUS IMPORTANTE ICI ═══╗
# ║ `defs.js` mélange deux natures de nombres dans un même objet :                                ║
# ║                                                                                               ║
# ║   • des valeurs de **VUE** — poses de hanche et de sprint, dégagement d'œil, champ de vision, ║
# ║     amplitude du balancement, FORME du recul. Elles décrivent ce que l'œil voit.               ║
# ║   • des valeurs de **RÈGLE** — `rpm`, `damage`, `magSize`, `reserve`, `spreadHip/Ads`,        ║
# ║     `penetration`, `maxRange`, `reloadTac`… Elles décrivent ce que le jeu FAIT.               ║
# ║                                                                                               ║
# ║ **SEULE LA PREMIÈRE MOITIÉ EST PORTÉE.** Le cahier §0 est catégorique : « le serveur : sim    ║
# ║ 20 Hz, table v4, cotes de silhouette. **La vue change, les règles JAMAIS.** » Chez nous       ║
# ║ `dispersion_deg`, `mag_size`, `reload_ticks` et la cadence sont LUS DU SERVEUR à l'exécution  ║
# ║ (cf. `trench_fp._dispersion_degrees()` / `_mag_size()`), et le §8.151 §1.9 en a fait un       ║
# ║ invariant : « le réticule ne ment jamais ».                                                   ║
# ║                                                                                               ║
# ║ ⛔ Recopier leurs `magSize: 30` ou `spreadHip: 2.05` ici créerait une SECONDE source de        ║
# ║ vérité, qui divergerait du serveur au premier rééquilibrage — en silence, et du seul côté     ║
# ║ que le joueur voit. C'est exactement le défaut que le §8.148 a mis une session à débusquer.   ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ CORRESPONDANCE DES ARMES (cahier §2.2quinquies) ═════════════════════════════════════════════╗
# ║   `vipere`  ← leur `pistol` (P-19)   — ⚠️ AUCUNE OPTIQUE : visée mécanique guidon + hausse.   ║
# ║   `frelon`  ← leur `smg`    (MPX-9)  — optique point rouge COMPACTE.                          ║
# ║   `chacal`  ← leur `rifle`  (M4A1)   — optique point rouge LARGE, flancs très moletés.        ║
# ║   `condor`  ← ⚙ EXTRAPOLÉ du fusil   — canon long, optique à grossissement. **Aucune capture  ║
# ║              de référence n'existe pour lui** : le cahier impose d'en soumettre une à Hakim    ║
# ║              avant de le figer. Tout ce qui le concerne est marqué `⚙ EXTRAPOLÉ`.             ║
# ║                                                                                               ║
# ║ ⚠️ Le nom affiché vient du `name_key` d'i18n du projet, PAS du `label` de la référence : nos  ║
# ║ armes ne s'appellent pas P-19 ni M4A1.                                                        ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# =================================================================================================

const Meshgen := preload("res://scripts/game/trench_meshgen.gd")
const WParts := preload("res://scripts/game/trench_wparts.gd")
const Mathx := preload("res://scripts/game/trench_mathx.gd")


# L'ordre d'affichage du sélecteur d'arme — celui du registre serveur.
const WEAPON_IDS := ["vipere", "frelon", "chacal", "condor"]


# =================================================================================================
# LE REGISTRE DE **VUE** — rien ici n'a d'effet sur une règle
# =================================================================================================
# ╔═ LES POSES SONT RÉSOLUES DEPUIS L'AXE DU CANON, PAS DEPUIS L'OPTIQUE ═════════════════════════╗
# ║ Commentaire de `defs.js`, et c'est contre-intuitif : « SOLVED FROM THE BORE AXIS, not from    ║
# ║ where the optic happens to land. […] What reads as "the gun points at the crosshair" is the   ║
# ║ MUZZLE being visible, up-left of the receiver, on the way to the centre of the screen. »      ║
# ║                                                                                               ║
# ║ ⚠️ `hip_pos.z = −0,30` (au lieu de −0,215) est MESURÉ, pas choisi : « the gun's vertical      ║
# ║ extent from optic to floorplate is 291 mm, and at 215 mm from the eye that is 93 % of the     ║
# ║ frame height ». C'est aussi la LIMITE : « the support hand is then 620 mm downrange of a      ║
# ║ shoulder 200 mm off the eye, and a 572 mm arm has nothing left ».                             ║
# ║                                                                                               ║
# ║ ⚠️ `eye_relief` est MESURÉ SUR L'IMAGE ADS, pas choisi pour le réalisme : à 0,078 m l'optique ║
# ║ occupait « HALF the frame height, and every critic called the optic oversized ». 0,115 la met ║
# ║ à 31 %. Et un dégagement PLUS LONG améliore le rapport image/boîtier : 0,53 → 0,69.           ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const VIEW_DEFS := {
	"chacal": {
		"source": "rifle", "ref_label": "M4A1",
		"hip_pos": Vector3(0.118, -0.185, -0.3),
		"hip_rot": Vector3(-0.05, 0.081, -0.135),
		"ads_cant": Vector3(0, 0, 0.004),
		"eye_relief": 0.115,
		"sprint_pos": Vector3(0.09, -0.262, -0.275),
		"sprint_rot": Vector3(-0.4, 0.6, 0.2),
		"low_ready_pos": Vector3(0.112, -0.28, -0.289),
		"low_ready_rot": Vector3(-0.46, 0.125, -0.09),
		"ads_time": 0.22, "ads_fov": 0.74, "view_fov": 0.86,
		"sway_scale": 1.0, "bob_scale": 1.0, "mag_len": 0.212,
		"draw_time": 0.62, "holster_time": 0.4, "inspect_time": 3.2,
		"recoil": {
			"pitch": 0.0085, "yaw": 0.0022, "kick_back": 0.019, "kick_up": 0.0072,
			"roll": 0.032, "punch": 0.35, "freq": 8.5, "damping": 0.42,
			"pattern_length": 30, "pattern_seed": 0x4d34a1,
			"climb_shape": [1.45, 1.3, 1.15, 1.05, 1.0], "drift": 0.55,
		},
	},
	"frelon": {
		"source": "smg", "ref_label": "MPX-9",
		"hip_pos": Vector3(0.111, -0.163, -0.288),
		"hip_rot": Vector3(-0.05, 0.072, -0.131),
		"ads_cant": Vector3(0, 0, 0.005),
		"eye_relief": 0.104,
		"sprint_pos": Vector3(0.088, -0.24, -0.262),
		"sprint_rot": Vector3(-0.38, 0.58, 0.19),
		"low_ready_pos": Vector3(0.108, -0.252, -0.276),
		"low_ready_rot": Vector3(-0.44, 0.125, -0.085),
		"ads_time": 0.185, "ads_fov": 0.78, "view_fov": 0.88,
		"sway_scale": 0.92, "bob_scale": 0.95, "mag_len": 0.192,
		"draw_time": 0.52, "holster_time": 0.34, "inspect_time": 2.9,
		"recoil": {
			"pitch": 0.0058, "yaw": 0.0026, "kick_back": 0.0135, "kick_up": 0.0052,
			"roll": 0.026, "punch": 0.24, "freq": 10.5, "damping": 0.4,
			"pattern_length": 32, "pattern_seed": 0x9ac31f,
			"climb_shape": [1.3, 1.18, 1.08, 1.0], "drift": 0.8,
		},
	},
	"vipere": {
		"source": "pistol", "ref_label": "P-19",
		"hip_pos": Vector3(0.115, -0.15, -0.34),
		"hip_rot": Vector3(-0.05, 0.066, -0.115),
		"ads_cant": Vector3(0, 0, 0.003),
		# ⚠️ 0,34 m et pas plus : « keeps both elbows visibly bent; past ~0.40 m the two-bone
		# solve hits full extension and they LOCK ». Le pistolet est tenu à DEUX MAINS, bras
		# tendus (§2.2quinquies) — c'est la distance qui rend cette pose tenable.
		"eye_relief": 0.34,
		"sprint_pos": Vector3(0.09, -0.25, -0.28),
		"sprint_rot": Vector3(-0.42, 0.5, 0.14),
		"low_ready_pos": Vector3(0.1, -0.26, -0.32),
		"low_ready_rot": Vector3(-0.44, 0.105, -0.07),
		"ads_time": 0.16, "ads_fov": 0.86, "view_fov": 0.92,
		"sway_scale": 1.15, "bob_scale": 1.1, "mag_len": 0.108,
		"draw_time": 0.42, "holster_time": 0.3, "inspect_time": 2.6,
		"recoil": {
			"pitch": 0.0125, "yaw": 0.0032, "kick_back": 0.012, "kick_up": 0.0105,
			"roll": 0.018, "punch": 0.3, "freq": 9.0, "damping": 0.45,
			"pattern_length": 17, "pattern_seed": 0x1f77bc,
			"climb_shape": [1.0], "drift": 1.2,
		},
	},
	# ⚙ EXTRAPOLÉ — aucune capture de référence. Bâti sur le fusil : arme plus lourde, donc recul
	# plus sec mais plus lent à revenir, dégagement d'œil plus long (optique à grossissement),
	# balancement plus ample (canon lourd), montée à l'œil plus lente.
	# ⛔ À SOUMETTRE À HAKIM AVANT DE FIGER (cahier §2.2quinquies).
	"condor": {
		"source": "rifle_long", "ref_label": "⚙ extrapolé",
		"hip_pos": Vector3(0.121, -0.196, -0.318),
		"hip_rot": Vector3(-0.048, 0.086, -0.142),
		"ads_cant": Vector3(0, 0, 0.003),
		"eye_relief": 0.132,
		"sprint_pos": Vector3(0.094, -0.276, -0.29),
		"sprint_rot": Vector3(-0.41, 0.62, 0.21),
		"low_ready_pos": Vector3(0.116, -0.295, -0.305),
		"low_ready_rot": Vector3(-0.47, 0.13, -0.095),
		"ads_time": 0.31, "ads_fov": 0.52, "view_fov": 0.84,
		"sway_scale": 1.22, "bob_scale": 1.08, "mag_len": 0.128,
		"draw_time": 0.78, "holster_time": 0.5, "inspect_time": 3.5,
		"recoil": {
			"pitch": 0.0175, "yaw": 0.0018, "kick_back": 0.028, "kick_up": 0.011,
			"roll": 0.022, "punch": 0.52, "freq": 6.5, "damping": 0.48,
			"pattern_length": 5, "pattern_seed": 0x2b91d4,
			"climb_shape": [1.0], "drift": 0.3,
		},
	},
}


static func view_def(weapon_id: String) -> Dictionary:
	return VIEW_DEFS.get(weapon_id, VIEW_DEFS["chacal"])


# =================================================================================================
# LE PATRON DE RECUL — port de `buildRecoilPattern` (`defs.js` l. 285)
# =================================================================================================
# ╔═ ⚠️ L'ORDRE DES TIRAGES EST SIGNIFICATIF ════════════════════════════════════════════════════╗
# ║ Le même RNG sert à quatre choses, et il est ENTRELACÉ dans la boucle : `sig` puis `signed()`  ║
# ║ à chaque coup. Reproduire la GRAINE ne suffit pas — il faut reproduire l'ORDRE D'APPEL, sinon ║
# ║ le patron est un autre patron. C'est le même piège que le §8.152.0 a documenté sur le RNG.    ║
# ║                                                                                               ║
# ║ « Everything comes from one fixed seed so the same weapon always kicks the same way —         ║
# ║ including in capture mode. » C'est ce qui rend le recul APPRENABLE : deux ondes déphasées     ║
# ║ « make the horizontal read as a learnable snake rather than as noise ».                       ║
# ║                                                                                               ║
# ║ ⚠️ CE PATRON EST 100 % COSMÉTIQUE chez nous. Il pilote le viewmodel et la présentation, et    ║
# ║ **rien d'autre** : la visée envoyée au serveur reste bit-identique (invariant §8.141.6, que   ║
# ║ `probe_trench_feel_aim` verrouille depuis le §8.151).                                         ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
static func build_recoil_pattern(weapon_id: String) -> PackedFloat32Array:
	var r: Dictionary = view_def(weapon_id)["recoil"]
	var n: int = r["pattern_length"]
	var rng := Mathx.TrenchRng.new(int(r["pattern_seed"]))
	var out := PackedFloat32Array()
	out.resize(n * 2)
	var climb_shape: Array = r["climb_shape"]
	var phase := rng.rand_float() * TAU
	var phase2 := rng.rand_float() * TAU
	var bias := rng.signed() * 0.35
	for i in n:
		var climb: float = climb_shape[mini(i, climb_shape.size() - 1)]
		# Vertical : fort au début, s'atténuant, avec une signature propre à chaque coup.
		var sig := 0.88 + rng.rand_float() * 0.24
		out[i * 2] = float(r["pitch"]) * climb * sig
		# Horizontal : un serpent lisse, plus une signature fixe par coup.
		var t := float(i) / float(maxi(1, n - 1))
		var snake := sin(phase + t * PI * 2.6) * 0.75 + sin(phase2 + t * PI * 5.1) * 0.35
		out[i * 2 + 1] = float(r["yaw"]) * (snake * float(r["drift"]) * 3.2
			+ bias + rng.signed() * 0.25)
	return out


# =================================================================================================
# CONSTRUCTION — l'aiguillage
# =================================================================================================
# Rend `{ "body": Assembly, "moving": { nom: Assembly }, "nodes": {…}, "id": String }`.
# ⚠️ `moving` porte les sous-assemblages qui BOUGENT (chargeur, culasse, levier, détente,
# sélecteur, glissière) : le lot 3D-E les anime, le lot 3D-F les monte dans le rig.
static func build(weapon_id: String) -> Dictionary:
	match weapon_id:
		"vipere":
			return _build_vipere()
		"frelon":
			return _build_frelon()
		"chacal":
			return _build_chacal(false)
		"condor":
			return _build_chacal(true)
	push_warning("trench_weapons3d : arme inconnue « %s » — repli sur chacal." % weapon_id)
	return _build_chacal(false)


# =================================================================================================
# `vipere` — LE PISTOLET (leur `pistol`, P-19)
# =================================================================================================
# ⭐ §2.2quinquies : **AUCUNE OPTIQUE**. Visée mécanique guidon + hausse en U carré, nettement
# visible au-dessus de la glissière. C'est ce qui le distingue à l'œil des trois autres, et il ne
# faut surtout pas l'« harmoniser » en lui greffant un point rouge.
# (Le mini reflex de la référence est monté ici parce qu'il fait partie de leur P-19 ; la hausse
# mécanique de `build_slide` reste en place et reste la visée de secours.)
static func _build_vipere() -> Dictionary:
	var bore := 0.036
	var slide_h := 0.0248
	var slide_w := 0.0262
	var slide_len := 0.183
	var z_slide_rear := 0.052
	var z_slide_front := z_slide_rear - slide_len  # −0,131
	var grip_angle := 0.32

	var body = Meshgen.Assembly.new("vipere-frame")
	var slide_asm = Meshgen.Assembly.new("vipere-slide")
	var magazine = Meshgen.Assembly.new("vipere-mag")
	var trigger = Meshgen.Assembly.new("vipere-trigger")

	# Couvercle de carcasse (dust cover) sous la glissière.
	body.add(Meshgen.extrude([
		[-slide_w * 0.5 + 0.001, 0], [slide_w * 0.5 - 0.001, 0],
		[slide_w * 0.5 - 0.001, -0.0125], [slide_w * 0.5 - 0.004, -0.016],
		[-slide_w * 0.5 + 0.004, -0.016], [-slide_w * 0.5 + 0.001, -0.0125],
	], 0.108, {"bevel": 0.001}), "polymer", {"y": bore - 0.0075, "z": -0.062})
	body.add(Meshgen.blob(slide_w - 0.001, 0.05, 0.062, 0.004, 3), "polymer",
		{"y": bore - 0.032, "z": 0.012})
	# Tenon arrière (beavertail de carcasse).
	body.add(Meshgen.extrude([
		[-0.008, 0], [0.03, -0.004], [0.032, -0.012], [-0.008, -0.014],
	], slide_w - 0.003, {"bevel": 0.0012}), "polymer",
		{"y": 0.022, "z": 0.034, "ry": PI * 0.5})

	# Rail accessoire sous le canon — cotes MINIATURES : un rail de pistolet n'est pas un rail
	# de fusil, et reprendre les défauts de `picatinny` le ferait deux fois trop gros.
	WParts.add_rail(body, "polymer", -0.112, -0.058, bore - 0.0175, 0.0,
		{"width": 0.0175, "waist": 0.013, "baseH": 0.0026, "topH": 0.0024,
		"pitch": 0.0092, "slot": 0.0046})

	# Pontet.
	body.add(Meshgen.extrude([
		[-0.024, 0], [0.026, 0], [0.028, -0.007], [0.024, -0.022],
		[0.013, -0.027], [-0.016, -0.027], [-0.024, -0.021],
	], slide_w - 0.004, {"bevel": 0.001, "holes": [[
		[-0.019, -0.003], [0.021, -0.003], [0.0225, -0.009], [0.0185, -0.0205],
		[0.01, -0.0235], [-0.013, -0.0235], [-0.019, -0.0185],
	]]}), "polymer", {"y": bore - 0.0245, "z": -0.03})

	WParts.add_pistol_grip(body, "polymer", "rubber",
		{"y": bore - 0.014, "z": 0.016, "angle": grip_angle, "len": 0.113, "w": 0.0305})

	# Grenure moulée des flancs de poignée : 9 rangées × 5 colonnes de pyramides, en quinconce.
	var stip_parts := []
	for r in 9:
		for c in 5:
			stip_parts.append(Meshgen.box(0.0024, 0.0024, 0.0009, 0.0003, 1)
				.translate(-0.005 + c * 0.0026 + (r % 2) * 0.0013, -0.012 - r * 0.0072, 0))
	var stip = Meshgen.merge_all(stip_parts)
	for sx in [-1.0, 1.0]:
		body.add(stip, "rubber", {
			"x": sx * 0.0152, "y": bore - 0.016, "z": 0.017,
			"ry": sx * PI * 0.5, "rz": -0.32 if sx > 0.0 else 0.32,
		})

	# Bouton de chargeur, arrêtoir de glissière (des deux côtés), axe de démontage.
	body.add(Meshgen.lathe_z([
		[0, 0], [0, 0.0042], [0.0015, 0.0048], [0.0038, 0.0048], [0.0038, 0],
	], 12), "polymer", {"x": 0.0138, "y": 0.004, "z": -0.014, "ry": PI * 0.5})
	var stop_lever = Meshgen.extrude([
		[-0.014, -0.0028], [0.012, -0.0035], [0.014, 0.0028], [-0.014, 0.0035],
	], 0.0032, {"bevel": 0.0005})
	for sx in [-1.0, 1.0]:
		body.add(stop_lever, "steel",
			{"x": sx * 0.0132, "y": bore - 0.0135, "z": -0.022, "ry": PI * 0.5})
	body.add(Meshgen.lathe_z([
		[0, 0], [0, 0.0035], [0.0022, 0.004], [0.0022, 0],
	], 12), "steel", {"x": -0.0138, "y": bore - 0.0175, "z": -0.046, "ry": -PI * 0.5})

	# Canon apparent à la bouche, âme, et guide de ressort.
	body.add(Meshgen.lathe_z([
		[0, 0], [0, 0.0082], [0.0016, 0.0088], [0.006, 0.0088],
		[0.0072, 0.0078], [0.0072, 0.0048],
	], 18), "steel_bright", {"y": bore, "z": z_slide_front + 0.0012, "ry": PI})
	body.add(Meshgen.tube_z(0.0048, 0.0034, 0.03, 12, 0.0002), "cavity",
		{"y": bore, "z": z_slide_front + 0.012})
	body.add(Meshgen.lathe_z([
		[0, 0.0032], [0, 0.0048], [0.004, 0.0048], [0.004, 0.0032],
	], 12), "steel_bright", {"y": bore - 0.0125, "z": z_slide_front + 0.0025})

	# ⚠️ « Nitrided, not bare steel: a slide is one big flat facing the sky. » — d'où `steel_black`
	# et non `steel_bright` : la glissière est la plus grande surface plate de l'arme tournée vers
	# le ciel, et c'est exactement la géométrie qui s'allume.
	var slide: Dictionary = WParts.build_slide(slide_asm, {
		"w": slide_w, "h": slide_h, "len": slide_len,
		"mat": "steel_black", "zRear": z_slide_rear,
	})
	var reflex: Dictionary = WParts.build_mini_reflex(slide_asm, {
		"w": 0.0246, "h": 0.021, "len": 0.0455,
		"y": slide_h * 0.5 + 0.0018, "z": z_slide_rear - 0.038, "matBody": "alu_fine",
	})

	var mag: Dictionary = WParts.build_magazine(magazine, null, {
		"w": 0.0212, "d": 0.0295, "len": 0.108, "curve": 0.004, "segs": 5, "witness": 3,
		"caseLen": 0.0192, "rimR": 0.00478, "bulletLen": 0.0132, "poly": "polymer",
	})

	var trg: Dictionary = WParts.trigger_part("polymer")
	trigger.add(trg["geo"], "polymer", {})
	# Sécurité de détente (la languette au milieu de la queue).
	trigger.add(Meshgen.extrude([
		[-0.0022, 0.003], [0.0022, 0.003], [0.0022, -0.016], [-0.0022, -0.017],
	], 0.0028, {"bevel": 0.0004}), "steel", {"x": 0.0, "y": -0.001, "z": 0.0022})

	var optic_y := bore + slide_h * 0.5 + 0.0018 + 0.021 * 0.56
	var optic_z := z_slide_rear - 0.038 + 0.0455 * 0.14
	return {
		"id": "vipere",
		"body": body,
		"moving": {"magazine": magazine, "trigger": trigger, "slide": slide_asm},
		"shell": {"caseLen": 0.0192, "rimR": 0.00478},
		"nodes": {
			"muzzle": Vector3(0, bore, z_slide_front - 0.004),
			"chamber": Vector3(0, bore, z_slide_rear - 0.05),
			"eject": Vector3(slide_w * 0.5 + 0.004, bore + 0.005, z_slide_rear - 0.05),
			"ejectDir": Vector3(0.82, 0.52, 0.24),
			"sight": Vector3(0, optic_y, optic_z),
			"sightAxis": Vector3(0, 0, -1),
			"ironSight": Vector3(0, bore + slide_h * 0.5 + 0.0065, z_slide_rear - 0.012),
			"gripR": {"pos": Vector3(0.028, 0.003, 0.07),
				"finger": Vector3(0, -0.315, -0.949), "back": Vector3(0.98, 0, -0.2)},
			"gripL": {"pos": Vector3(-0.03, -0.012, 0.076),
				"finger": Vector3(0.34, -0.28, -0.9), "back": Vector3(0.15, 0.93, -0.33)},
			"magSeat": {"pos": Vector3(0, bore - 0.03, 0.019),
				"rot": Vector3(-grip_angle, 0, 0)},
			"magDrop": Vector3(0, -0.42, 0.05),
			"slideRest": {"pos": Vector3(0, bore, 0), "rot": Vector3.ZERO},
			"slideTravel": Vector3(0, 0, 0.0225),
			"triggerPivot": {"pos": Vector3(0, bore - 0.0135, -0.0165), "rot": Vector3.ZERO},
			"triggerPull": -0.3,
			"opticGlass": reflex,
			"slideGeom": slide,
		},
	}


# =================================================================================================
# `frelon` — LA MITRAILLETTE (leur `smg`, MPX-9)
# =================================================================================================
static func _build_frelon() -> Dictionary:
	var bore := 0.068
	var r_rec := 0.0158
	var rail_top := bore + 0.0245  # 0,0925
	var z_rec_rear := 0.062
	var z_rec_front := -0.112
	var port_z := -0.042
	var mag_z := -0.052
	var mag_tilt := 0.05
	var hg_z0 := -0.114
	var hg_z1 := -0.268
	var hg_r := 0.019
	var z_barrel_end := -0.3
	var optic_y := bore + 0.055  # 0,123
	var optic_z := -0.008

	var body = Meshgen.Assembly.new("frelon-body")
	var magazine = Meshgen.Assembly.new("frelon-mag")
	var charging = Meshgen.Assembly.new("frelon-charging")
	var bolt = Meshgen.Assembly.new("frelon-bolt")
	var trigger = Meshgen.Assembly.new("frelon-trigger")
	var selector = Meshgen.Assembly.new("frelon-selector")

	# Boîtier de culasse.
	var rec_len := z_rec_rear - z_rec_front
	body.add(Meshgen.lathe_z([
		[0, r_rec * 0.55], [0, r_rec * 0.99], [0.002, r_rec],
		[rec_len - 0.004, r_rec], [rec_len - 0.002, r_rec * 0.96], [rec_len, r_rec * 0.6],
	], 22), "alu", {"y": bore, "z": z_rec_rear, "ry": PI})
	body.add(Meshgen.box(0.0225, 0.009, rec_len - 0.004, 0.0009, 1), "alu",
		{"y": bore + r_rec - 0.003, "z": (z_rec_rear + z_rec_front) * 0.5})
	# Tube du levier d'armement, sur le flanc gauche.
	body.add(Meshgen.tube_z(0.0072, 0.0052, 0.14, 14, 0.0004), "alu",
		{"x": -r_rec + 0.0028, "y": bore + r_rec - 0.007, "z": -0.06})

	WParts.add_rail(body, "alu", z_rec_front + 0.004, z_rec_rear - 0.004, rail_top)

	# Fenêtre d'éjection.
	body.add(Meshgen.box(0.01, 0.017, 0.03, 0.0008, 1), "cavity",
		{"x": r_rec - 0.006, "y": 0.07, "z": port_z, "ry": PI * 0.5})
	body.add(Meshgen.extrude(Meshgen.round_rect(0.034, 0.021, 0.002, 3), 0.002,
		{"bevel": 0.0005, "holes": [Meshgen.round_rect(0.03, 0.017, 0.0016, 3)]}), "alu",
		{"x": r_rec - 0.0012, "y": 0.07, "z": port_z, "ry": PI * 0.5})
	body.add(Meshgen.lathe_z([
		[0, r_rec * 0.5], [0, r_rec * 0.82], [0.07, r_rec * 0.82], [0.07, r_rec * 0.5],
	], 16), "steel_bright", {"y": bore, "z": port_z - 0.02})

	# Carcasse basse polymère + puits de chargeur.
	var mag_w := 0.0242
	var mag_d := 0.0345
	var well_h := 0.036
	body.add(Meshgen.box(0.0245, 0.028, 0.13, 0.0016, 2), "polymer",
		{"y": bore - 0.0195, "z": -0.02})
	var well_t := {"y": bore - 0.038, "z": mag_z, "rx": PI * 0.5 + mag_tilt}
	body.add(Meshgen.extrude(Meshgen.round_rect(mag_w + 0.003, mag_d + 0.003, 0.005, 4), well_h,
		{"bevel": 0.0011,
		"holes": [Meshgen.round_rect(mag_w - 0.002, mag_d - 0.002, 0.004, 4)]}),
		"polymer", well_t)
	body.add(Meshgen.extrude(Meshgen.round_rect(mag_w - 0.0022, mag_d - 0.0022, 0.004, 4),
		well_h - 0.004, {"bevel": 0.0005,
		"holes": [Meshgen.round_rect(mag_w - 0.005, mag_d - 0.005, 0.003, 4)]}),
		"cavity", well_t)
	body.add(Meshgen.extrude(Meshgen.round_rect(mag_w + 0.007, mag_d + 0.008, 0.006, 4), 0.007,
		{"bevel": 0.0012,
		"holes": [Meshgen.round_rect(mag_w + 0.001, mag_d + 0.001, 0.004, 4)]}),
		"polymer", {"y": bore - 0.055, "z": mag_z + 0.0016, "rx": PI * 0.5 + mag_tilt})

	# Pontet.
	body.add(Meshgen.extrude([
		[-0.026, 0], [0.028, 0], [0.03, -0.006], [0.026, -0.021],
		[0.016, -0.026], [-0.018, -0.026], [-0.026, -0.02],
	], 0.0155, {"bevel": 0.0009, "holes": [[
		[-0.021, -0.003], [0.0225, -0.003], [0.0235, -0.008], [0.02, -0.0195],
		[0.013, -0.0225], [-0.015, -0.0225], [-0.0205, -0.018],
	]]}), "polymer", {"y": bore - 0.03, "z": -0.008})
	# Palettes de sélecteur ambidextres.
	var paddle = Meshgen.extrude([
		[-0.008, -0.004], [0.009, -0.005], [0.01, 0.004], [-0.008, 0.005],
	], 0.004, {"bevel": 0.0006})
	for sx in [-1.0, 1.0]:
		body.add(paddle, "alu", {"x": sx * 0.0132, "y": bore - 0.026, "z": -0.03,
			"ry": PI * 0.5})

	WParts.add_pistol_grip(body, "polymer", "rubber",
		{"y": 0.033, "z": 0.018, "angle": 0.36, "len": 0.102, "w": 0.03})
	WParts.add_barrel(body, "steel", "cavity", {
		"y": bore, "zBreech": -0.09, "zMuzzle": z_barrel_end,
		"rChamber": 0.0092, "rBarrel": 0.0062, "rGas": 0.0072, "gasAt": -0.2, "knurl": false,
	})
	var muzzle: Dictionary = WParts.add_muzzle_device(body, "steel_soot", "cavity", "trilug",
		z_barrel_end, 0.0062, bore)
	# ⚠️ PAS de `matPanel` ici, contrairement au fusil : le garde-main de la mitraillette est tout
	# en aluminium. La séparation de classes se joue ailleurs sur cette arme.
	WParts.add_handguard(body, "alu", {
		"y": bore, "z0": hg_z0, "z1": hg_z1, "r": hg_r, "sides": 8,
		"slatW": 0.0132, "slatT": 0.0032, "slots": 3, "braces": 2,
	})
	WParts.add_rail(body, "alu", hg_z1 + 0.004, hg_z0 - 0.002, rail_top)
	WParts.add_fore_grip(body, "polymer", "rubber",
		{"y": bore - hg_r - 0.004, "z": -0.208, "angle": 0.2, "len": 0.058})
	WParts.add_qd_socket(body, "alu", "steel", -hg_r + 0.001, bore - 0.006, hg_z0 - 0.022,
		"x", 0.0045)
	WParts.add_pin(body, "steel", 0.0, bore - 0.008, z_rec_rear + 0.014, 0.003, 0.028)
	WParts.add_sling_loop(body, "steel", 0.0165, bore - 0.022, z_rec_rear + 0.026, 0.007,
		{"ry": PI * 0.5})

	# Crosse repliable : charnière, montants, traverse, plaque de couche, appui-joue.
	body.add(Meshgen.blob(0.026, 0.03, 0.024, 0.003, 3), "alu",
		{"y": 0.06, "z": z_rec_rear + 0.008})
	for sx in [-1.0, 1.0]:
		body.add(Meshgen.box(0.0075, 0.011, 0.145, 0.0018, 2), "alu",
			{"x": sx * 0.0125, "y": bore - 0.014, "z": z_rec_rear + 0.085, "rx": -0.045})
	body.add(Meshgen.box(0.032, 0.009, 0.0095, 0.0016, 2), "alu",
		{"y": bore - 0.019, "z": z_rec_rear + 0.12})
	body.add(Meshgen.extrude(Meshgen.round_rect(0.042, 0.058, 0.006, 4), 0.009,
		{"bevel": 0.0012}), "polymer",
		{"y": bore - 0.026, "z": z_rec_rear + 0.155, "rx": 0.06})
	body.add(Meshgen.blob(0.04, 0.05, 0.0085, 0.0035, 3), "rubber",
		{"y": bore - 0.026, "z": z_rec_rear + 0.162, "rx": 0.06})
	body.add(Meshgen.blob(0.019, 0.013, 0.09, 0.005, 3), "polymer",
		{"y": bore + 0.012, "z": z_rec_rear + 0.08, "rx": -0.05})

	var optic: Dictionary = WParts.build_optic(body, {
		"rTube": 0.0138, "len": 0.044, "hood": 0.006, "y": optic_y, "z": optic_z,
		"railTop": rail_top, "matBody": "alu_fine", "matSteel": "steel",
	})
	# ⚠️ ORGANES DE VISÉE DE SECOURS EN `polymer`, REPLIÉS, ET REJETÉS EN AVANT.
	# Mesuré chez eux : en `steel`/`steel_black` les feuilles rendaient à L=188-192, « the
	# brightest objects on the front half of the weapon ». Ce sont des MÉTAUX : à metalness 1
	# l'albédo est replié dans le F0 et baisser celui-ci deux fois ne les a déplacés que d'un
	# cinquième de diaphragme. `polymer` est à la fois honnête et DIÉLECTRIQUE — il accepte le
	# bridage spéculaire du reste de l'arme.
	WParts.add_front_sight(body, "polymer", "alu", 0.0, rail_top, -0.248, false)
	WParts.add_rear_sight(body, "polymer", "alu", 0.0, rail_top, -0.09, false)

	var mag: Dictionary = WParts.build_magazine(magazine, null, {
		"w": 0.0235, "d": 0.0335, "len": 0.192, "curve": 0.026, "segs": 7, "witness": 5,
		"caseLen": 0.0192, "rimR": 0.00478, "bulletLen": 0.0132, "poly": "polymer",
	})

	# Levier d'armement.
	var ch_parts := [Meshgen.rod_z(0.0048, 0.0048, 0.12, 12, 0.0004)]
	ch_parts.append(Meshgen.extrude([
		[0, -0.0075], [0.017, -0.009], [0.019, 0], [0.017, 0.008], [0, 0.007],
	], 0.0055, {"bevel": 0.0008}).rotate_y(-PI * 0.5).translate(-0.0075, 0, -0.05))
	ch_parts.append(Meshgen.dome(0.0055, 12, 0.6).rotate_y(-PI * 0.5)
		.translate(-0.024, 0, -0.05))
	charging.add(Meshgen.merge_all(ch_parts), "steel_bright", {})

	# Culasse et sa face.
	bolt.add(Meshgen.lathe_z([
		[0, r_rec * 0.45], [0, r_rec * 0.8], [0.078, r_rec * 0.8], [0.078, r_rec * 0.45],
	], 16), "steel_bright", {"z": -0.078})
	bolt.add(Meshgen.box(0.014, 0.014, 0.003, 0.0006, 1), "steel", {"z": -0.0005})

	# ⚠️⚠️ LA DOUILLE CHAMBRÉE VA SUR LA **CULASSE**, PAS SUR LA CARCASSE.
	# Défaut réel trouvé par la critique adversariale du 2026-08-28 : le portage l'ajoutait à
	# `body`. Elle serait restée FIGÉE dans la carcasse pendant que la culasse animée s'en écarte
	# (lot 3D-E) — une douille flottante, détachée de la face de culasse qui est censée l'extraire.
	# La source : `smg.js:297  bolt.add(chamberRound.brass, ...)`.
	# ⚠️ Et SEULE LA DOUILLE : l'ogive est jetée par la référence aussi. Un portage naïf ajouterait
	# une ogive parasite qui traverse la carcasse.
	var c := WParts.cartridge(0.0192, 0.00478, 0.0132)
	bolt.add(c["brass"], "brass", {"z": -0.0215, "ry": PI})

	var trg: Dictionary = WParts.trigger_part("steel_bright")
	trigger.add(trg["geo"], "steel_bright", {})
	var sel: Dictionary = WParts.selector_part("alu", "steel")
	selector.add(sel["geo"], "alu", {})
	selector.add(sel["geo"], "alu", {"sx": -1.0})

	return {
		"id": "frelon",
		"body": body,
		"moving": {"magazine": magazine, "charging": charging, "bolt": bolt,
			"trigger": trigger, "selector": selector},
		"shell": {"caseLen": 0.0192, "rimR": 0.00478},
		"nodes": {
			"muzzle": Vector3(0, bore, float(muzzle["crownZ"])),
			"chamber": Vector3(0, bore, port_z),
			"eject": Vector3(r_rec + 0.006, bore + 0.002, port_z),
			"ejectDir": Vector3(0.9, 0.4, 0.18),
			"sight": Vector3(0, optic_y, float(optic["lensZ"])),
			"sightAxis": Vector3(0, 0, -1),
			"ironSight": Vector3(0, rail_top + 0.024, 0.042),
			"gripR": {"pos": Vector3(0.024, 0.028, 0.064),
				"finger": Vector3(-0.05, -0.4, -0.915), "back": Vector3(0.97, -0.05, -0.22)},
			"gripL": {"pos": Vector3(-0.056, 0.015, -0.153),
				"finger": Vector3(0.45, 0.05, -0.89), "back": Vector3(-0.88, -0.05, -0.45)},
			"magSeat": {"pos": Vector3(0, bore - 0.02, mag_z), "rot": Vector3(mag_tilt, 0, 0)},
			"magDrop": Vector3(0, -0.4, 0.02),
			"chargeRest": {"pos": Vector3(-r_rec + 0.0028, bore + r_rec - 0.007, -0.06),
				"rot": Vector3.ZERO},
			"chargePull": Vector3(0, 0, 0.062),
			"boltRest": {"pos": Vector3(0, bore, port_z + 0.032), "rot": Vector3.ZERO},
			"boltTravel": Vector3(0, 0, 0.05),
			"triggerPivot": {"pos": Vector3(0, bore - 0.026, -0.001), "rot": Vector3.ZERO},
			"triggerPull": -0.36,
			"selectorPivot": {"pos": Vector3(0, bore - 0.019, 0.022), "rot": Vector3.ZERO},
			"opticGlass": optic,
		},
	}


# =================================================================================================
# `chacal` — LE FUSIL D'ASSAUT (leur `rifle`, M4A1) · et `condor` en variante LONGUE
# =================================================================================================
# ⚙ `long = true` produit le `condor` : canon rallongé, optique à grossissement, garde-main
# étendu. EXTRAPOLÉ — aucune capture de référence, à soumettre à Hakim avant de figer.
static func _build_chacal(long: bool) -> Dictionary:
	var bore := 0.075
	var r_upper := 0.0192
	var rail_top := bore + 0.0286  # 0,1036
	var z_upper_rear := 0.055
	var z_upper_front := -0.143
	var port_z := -0.052
	var mag_z := -0.058
	var mag_tilt := 0.08
	var hg_z0 := -0.145
	var hg_z1 := -0.385 if not long else -0.470
	var hg_r := 0.0235
	var z_breech := -0.1
	var z_barrel_end := -0.44 if not long else -0.585
	var optic_y := bore + 0.067  # 0,142
	var optic_z := -0.022
	# ⚠️ « Moved 10 mm rearward (was −0.245) when the hipfire pose pushed the weapon out to
	# 300 mm: the support arm is REACH-LIMITED, and every 10 mm off the contact is elbow bend
	# recovered. 150 mm of handguard remains ahead of the hand. »
	var hand_z := -0.235 if not long else -0.275

	var nom := "condor" if long else "chacal"
	var body = Meshgen.Assembly.new(nom + "-body")
	var magazine = Meshgen.Assembly.new(nom + "-mag")
	var charging = Meshgen.Assembly.new(nom + "-charging")
	var bolt = Meshgen.Assembly.new(nom + "-bolt")
	var trigger = Meshgen.Assembly.new(nom + "-trigger")
	var selector = Meshgen.Assembly.new(nom + "-selector")

	WParts.add_upper_receiver(body, "alu", "steel", "cavity", {
		"zRear": z_upper_rear, "zFront": z_upper_front, "bore": bore, "r": r_upper,
		"portZ": port_z, "railTop": rail_top,
	})
	WParts.add_lower_receiver(body, "alu", "steel", {
		"bore": bore, "zRear": z_upper_rear + 0.004, "zFront": -0.088, "w": 0.0245,
		"magW": 0.0292, "magD": 0.0672, "magTop": 0.049, "magBottom": 0.008,
		"magZ": mag_z, "magTilt": mag_tilt, "triggerZ": -0.012, "gripAngle": 0.38,
	})
	# Arrêtoir de culasse, bossage, cache et bouton de chargeur.
	body.add(Meshgen.extrude([
		[-0.012, -0.0035], [0.012, -0.0045], [0.014, 0.0035], [-0.012, 0.0045],
	], 0.0042, {"bevel": 0.0007}), "steel",
		{"x": -0.0135, "y": 0.0545, "z": -0.018, "ry": PI * 0.5})
	body.add(Meshgen.blob(0.006, 0.011, 0.014, 0.0018, 2), "alu",
		{"x": -0.0128, "y": 0.0555, "z": -0.0085})
	body.add(Meshgen.blob(0.0075, 0.016, 0.019, 0.0022, 2), "alu",
		{"x": 0.0132, "y": 0.0505, "z": -0.0295})
	body.add(Meshgen.lathe_z([
		[0, 0], [0, 0.0048], [0.0016, 0.0052], [0.0042, 0.0052], [0.0042, 0],
	], 14), "steel", {"x": 0.0158, "y": 0.0505, "z": -0.0295, "ry": PI * 0.5})

	WParts.add_pin(body, "steel", 0.0, 0.0555, -0.083, 0.0028, 0.0252)
	WParts.add_pin(body, "steel", 0.0, 0.0555, 0.0455, 0.0028, 0.0252)
	# ⚠️ Le poinçon est gravé « on the side that faces the camera in the hipfire pose, engraved as
	# GEOMETRY so it cannot swim ».
	WParts.add_rollmark(body, "cavity", {"x": -0.0149, "y": 0.0355, "z": -0.031, "h": 0.0036})
	WParts.add_rollmark(body, "cavity", {
		"x": -0.0149, "y": 0.0272, "z": -0.033, "h": 0.0024, "pitch": 0.0014,
		"pattern": [2, 3, 1, 0, 2, 2, 3, 0, 3, 2],
	})

	WParts.add_barrel(body, "steel", "cavity", {
		"y": bore, "zBreech": z_breech, "zMuzzle": z_barrel_end,
		"rChamber": 0.0112, "rBarrel": 0.0077 if not long else 0.0086,
		"rGas": 0.0098, "gasAt": -0.3 if not long else -0.38,
	})
	# ⚠️ Suie sur le bloc de gaz : « the gas block VENTS COMBUSTION PRODUCTS by design and the
	# brake is 20 mm from the crown ».
	WParts.add_gas_block(body, "steel_soot", {
		"y": bore, "z": -0.3 if not long else -0.38, "rBarrel": 0.0077,
		"tubeTo": -0.15, "w": 0.021, "h": 0.0195,
	})
	var muzzle: Dictionary = WParts.add_muzzle_device(body, "steel_soot", "cavity",
		"brake" if not long else "comp", z_barrel_end, 0.0077 if not long else 0.0086, bore)

	# ⚠️ LA SÉPARATION DE CLASSES EST ICI, ET ELLE EST VOULUE : « a warm, 0.023-albedo, 0.65-rough
	# moulded shell bolted to a cool, 0.033-albedo, 0.40-rough anodised receiver, with phosphate
	# steel forward of both ». C'est le seul endroit de l'arme où deux diélectriques se touchent
	# sur une grande surface — d'où la lisibilité des classes au tir à la hanche.
	WParts.add_handguard(body, "alu", {
		"matPanel": "polymer", "y": bore, "z0": hg_z0, "z1": hg_z1, "r": hg_r, "sides": 8,
		"slatW": 0.0166, "slatT": 0.0036, "slots": 4 if not long else 6, "braces": 3,
		"topFrom": hand_z + 0.048, "topTo": hg_z1 + 0.056,
	})
	# ⚠️ UN SEUL RAIL CONTINU. Il était scindé autour des articulations de la main de soutien
	# (« a hand cannot close over Picatinny teeth without the fingers passing through them »),
	# mais la main empoigne désormais SOUS le garde-main : la scission ne laissait plus qu'un vide
	# de 138 mm au milieu du pont, pour rien.
	# 🩸 Le commentaire de bloc de `rifle.js` décrit ENCORE l'ancienne logique scindée alors que
	# leur code ne pose plus qu'un `addRail`. **Le code fait foi.**
	WParts.add_rail(body, "alu", hg_z1 + 0.004, hg_z0 - 0.002, rail_top)
	WParts.add_qd_socket(body, "alu", "steel", -hg_r + 0.001, bore - 0.008, hg_z0 - 0.035,
		"x", 0.005)
	WParts.add_sling_loop(body, "steel", 0.0, bore - hg_r - 0.0015, hg_z1 + 0.03, 0.0075,
		{"rx": PI * 0.5, "ry": PI * 0.5})
	WParts.add_pistol_grip(body, "polymer", "rubber",
		{"y": 0.035, "z": 0.015, "angle": 0.38, "len": 0.108, "w": 0.031})
	# ⚠️ « Buffer tube stays ALUMINIUM (it is a machined extrusion); the cheek riser and butt stock
	# are the polymer class, the pad is rubber. **Three classes, one part.** »
	WParts.add_carbine_stock(body, "alu", "polymer", "rubber", {
		"bore": bore, "zFront": z_upper_rear + 0.003, "zRear": 0.245, "y": bore - 0.012,
	})

	# ⚙ L'optique du condor : corps plus LONG, tube plus fin, pare-soleil plus profond — la
	# signature d'un grossissement. Le réticule fin (dispersion 0,0°) est du ressort du HUD.
	var optic: Dictionary = WParts.build_optic(body, {
		"rTube": 0.0155 if not long else 0.0142,
		"len": 0.052 if not long else 0.098,
		"hood": 0.007 if not long else 0.018,
		"y": optic_y, "z": optic_z, "railTop": rail_top,
		"matBody": "alu_fine", "matSteel": "steel",
	})
	# ⚠️ La hausse de secours est REJETÉE VERS L'AVANT (z −0,112 au lieu de +0,038) : repliée, elle
	# se trouvait à 75 mm de l'œil en ADS — « CLOSER than any other part of the weapon, closer than
	# the optic itself ». Mesuré au lancer de rayon : tous ces pixels rendaient `rifle-body-steel`
	# à d = 0,072-0,076. La déplacer la met à 224 mm, soit « a NINTH of the screen area ».
	WParts.add_front_sight(body, "polymer", "alu", 0.0, rail_top, -0.358 if not long else -0.44,
		false)
	WParts.add_rear_sight(body, "polymer", "alu", 0.0, rail_top, -0.112, false)

	var mag: Dictionary = WParts.build_magazine(magazine, null, {
		"w": 0.0255, "d": 0.0655,
		"len": 0.212 if not long else 0.128,
		"curve": 0.03 if not long else 0.008,
		"segs": 8 if not long else 5,
		"witness": 4 if not long else 2, "poly": "polymer",
	})

	# ⚠️ LEVIER D'ARMEMENT EN `alu`, PAS EN `steel_bright`. « An AR charging handle is a
	# black-anodised ALUMINIUM extrusion, not bright steel. Measured as `steel_bright` it was a
	# 30 × 15 px CREAM PLATE at L=170-184 sitting on the receiver flank in hipfire — one of the
	# "untextured white blocks". »
	charging.add(WParts.charging_handle_part(), "alu", {})
	WParts.add_bolt_carrier(bolt, "steel_bright", {"r": 0.0152, "len": 0.092, "z": 0.0})

	# Sur la CULASSE et seule la DOUILLE, encore — cf. le pavé du `frelon`.
	# Source : `rifle.js:297  bolt.add(chamberRound.brass, ...)`. Et le commentaire qui l'entoure
	# vaut d'être gardé : « pushed far enough forward that only the case head shows in the ejection
	# port. Left where it is easy to put it, a chambered round **spears out through the receiver
	# wall and reads as a bug**. »
	var c := WParts.cartridge(0.0446, 0.00495, 0.019)
	bolt.add(c["brass"], "brass", {"y": 0.0, "z": -0.09, "ry": PI})

	var trg: Dictionary = WParts.trigger_part("steel_bright")
	trigger.add(trg["geo"], "steel_bright", {})
	var sel: Dictionary = WParts.selector_part("alu", "steel")
	selector.add(sel["geo"], "alu", {})
	selector.add(sel["geo"], "alu", {"sx": -1.0})

	return {
		"id": nom,
		"body": body,
		"moving": {"magazine": magazine, "charging": charging, "bolt": bolt,
			"trigger": trigger, "selector": selector},
		"shell": {"caseLen": 0.0446, "rimR": 0.00495},
		"nodes": {
			"muzzle": Vector3(0, bore, float(muzzle["crownZ"])),
			"chamber": Vector3(0, bore, port_z),
			"eject": Vector3(r_upper + 0.008, bore + 0.003, port_z),
			"ejectDir": Vector3(0.86, 0.44, 0.26),
			"sight": Vector3(0, optic_y, float(optic["lensZ"])),
			"sightAxis": Vector3(0, 0, -1),
			"ironSight": Vector3(0, rail_top + 0.026, 0.038),
			# ⚠️ LES CIBLES DE MAIN SONT DES POIGNETS, PAS DES PAUMES : « the glove is modelled
			# from the wrist forward, with the knuckle line 98 mm along the hand's −Z. So each
			# target is derived as `knuckle − 0.098 * fingerDir`. **Authoring the palm position
			# directly is what BURIES the hand inside the handguard.** »
			"gripR": {"pos": Vector3(0.0251, 0.06, 0.1223),
				"finger": Vector3(0.05, -0.55, -0.833), "back": Vector3(1, 0.03, 0.04)},
			"gripL": {"pos": Vector3(-0.1, 0.0734, hand_z + 0.0252),
				"finger": Vector3(0.8977, -0.3267, -0.2955),
				"back": Vector3(-0.2784, -0.7648, 0.581)},
			# ⚠️ `r` est le rayon EXTÉRIEUR DES PANNEAUX polymère (les lattes saillent de 3,6 mm
			# du châssis de 23,5 mm) : c'est la surface qu'une main touche réellement.
			"handguard": {"axis": Vector3(0, bore, 0), "dir": Vector3(0, 0, 1),
				"r": hg_r + 0.0036, "z0": hg_z0, "z1": hg_z1},
			"magSeat": {"pos": Vector3(0, 0.061, mag_z), "rot": Vector3(mag_tilt, 0, 0)},
			"magDrop": Vector3(0, -0.4, 0.02),
			"chargeRest": {"pos": Vector3(0, bore + r_upper - 0.0075, z_upper_rear - 0.024),
				"rot": Vector3.ZERO},
			"chargePull": Vector3(0, 0, 0.082),
			"boltRest": {"pos": Vector3(0, bore, 0.021), "rot": Vector3.ZERO},
			"boltTravel": Vector3(0, 0, 0.062),
			"triggerPivot": {"pos": Vector3(0, 0.0455, -0.0055), "rot": Vector3.ZERO},
			"triggerPull": -0.34,
			"selectorPivot": {"pos": Vector3(0, 0.0525, 0.0205), "rot": Vector3.ZERO},
			"opticGlass": optic,
		},
	}
