extends Node

# =================================================================================================
# SONDE §8.152 — LOT 3D-E : LES CLIPS D'ANIMATION
#
# Lancement : <godot_console> --headless --path frontend res://tools/probe_vue3d_clips.tscn
#             --quit-after 2000
#
# ── SABOTAGES QUI DOIVENT LA FAIRE ROUGIR ──────────────────────────────────────────────────────
#  1. remettre `t: 1.0` en dur sur la clé terminale de `weapon`   -> E1 (ne revient pas au repos)
#  2. idem sur la clé terminale de `lhand`                        -> E2 (clés non triées) + E7
#  3. réintroduire le `or w < 0.5` de `mag_visible`               -> E3 (clignotement)
#  4. figer la durée de rechargement a 2.15 s                     -> E4 (ne suit plus le serveur)
#  5. glisser une valeur de RÈGLE dans le registre de vue         -> E5
#  6. décaler un événement au-delà de la durée du clip            -> E6 (jamais émis)
#  7. téléporter une clé de main d'appui de 30 cm                 -> E7
# =================================================================================================

const Weapons := preload("res://scripts/game/trench_weapons3d.gd")
const Clips := preload("res://scripts/game/trench_wclips.gd")

const CHECKS_ATTENDUS := 7

# Les cinq clips, et ceux dont on EXIGE le retour au repos. `holster` finit délibérément loin de la
# pose de base — c'est son objet même : sortir l'arme du cadre.
const CLIPS := ["reload_tac", "reload_empty", "inspect", "draw", "holster"]
const RETOUR_AU_REPOS := ["reload_tac", "reload_empty", "inspect", "draw"]

var _fails: Array = []
var _joues := 0


func _ok(nom: String, cond: bool, detail := "") -> void:
	_joues += 1
	if cond:
		print("  [OK]   %s   | %s" % [nom, detail])
	else:
		_fails.append(nom)
		print("  [ROUGE] %s   | %s" % [nom, detail])


# Une durée de rechargement PLAUSIBLE, du même ordre que celles du serveur (30/40/44/50 ticks à
# 20 Hz = 1,50 / 2,00 / 2,20 / 2,50 s). Elle est passée en ARGUMENT, jamais lue d'un registre.
const RELOAD_S := 2.20


func _jeu(id: String, reload_s := RELOAD_S) -> Dictionary:
	var m: Dictionary = Weapons.build(id)
	return Clips.build_clips(m["nodes"], Weapons.view_def(id), reload_s)


func _ready() -> void:
	print("\n=== SONDE 8.152 — LOT 3D-E : LES CLIPS ===\n")
	_probe_repos()
	_probe_tri()
	_probe_strobe()
	_probe_duree()
	_probe_frontiere()
	_probe_evenements()
	_probe_teleport()

	print("")
	if _joues != CHECKS_ATTENDUS:
		print("INCOMPLETE : %d controles joues, %d attendus" % [_joues, CHECKS_ATTENDUS])
		get_tree().quit(1)
	elif _fails.is_empty():
		print("TOUT VERT (%d/%d controles joues)" % [_joues, CHECKS_ATTENDUS])
		get_tree().quit(0)
	else:
		print("ECHEC : %d rouge(s) sur %d joues -> %s" % [_fails.size(), _joues, str(_fails)])
		get_tree().quit(1)


# =================================================================================================
# E1. ⭐⭐ CHAQUE CLIP REVIENT À LA POSE DE BASE — LA PORTE DU CAHIER
# =================================================================================================
# `PROMPT_TRANCHEE_VUE3D.md §5` : « la recharge se joue en entier et REVIENT à la pose de base
# (aucun effet qui survit) ».
#
# 🩸 C'est EXACTEMENT ce que la référence échoue. Ses 13 clés terminales portent `t: 1` en dur au
# lieu de `t: 1 * durée`, alors que l'échantillonnage se fait en SECONDES : les tableaux ne sont
# donc pas triés et la fin du clip n'est jamais atteinte. Mesuré sur leur code :
#   · `draw` (0,62 s) s'arrête à 0,91° de tangage — annulé d'un coup par l'arrêt du clip, donc un
#     CLAQUEMENT visible à chaque sortie d'arme ;
#   · `holster` ne parcourt que 70 % de sa course.
func _probe_repos() -> void:
	var fautes := []
	for id in Weapons.WEAPON_IDS:
		var jeu := _jeu(id)
		var hg: Vector3 = ((Weapons.build(id)["nodes"] as Dictionary)["gripL"] as Dictionary)["pos"]
		for nom in RETOUR_AU_REPOS:
			var c = jeu[nom]
			var s = Clips.Sample.new()
			c.sample(c.duration, s)
			if s.pos.length() > 1e-6 or s.rot.length() > 1e-6:
				fautes.append("%s/%s : residu p=%.4f m r=%.4f rad"
					% [id, nom, s.pos.length(), s.rot.length()])
			if s.lh_pos.distance_to(hg) > 1e-6:
				fautes.append("%s/%s : main a %.1f mm de la prise"
					% [id, nom, s.lh_pos.distance_to(hg) * 1000.0])
	# Contre-face : le rangement, lui, DOIT finir loin — sinon le contrôle serait satisfait par un
	# clip qui ne bouge jamais.
	var jeu0 := _jeu("chacal")
	var ch = jeu0["holster"]
	var sh = Clips.Sample.new()
	ch.sample(ch.duration, sh)
	if sh.pos.length() < 0.05:
		fautes.append("holster : ne sort PAS du cadre (%.3f m)" % sh.pos.length())
	_ok("E1 les 4 clips reviennent EXACTEMENT au repos, et le rangement sort bien du cadre",
		fautes.is_empty(), "%d faute(s) : %s" % [fautes.size(), str(fautes.slice(0, 3))])


# =================================================================================================
# E2. LES CLÉS SONT TRIÉES DANS LE TEMPS
# =================================================================================================
# La recherche de segment (`while keys[i+1].t <= t`) SUPPOSE un tableau trié. Un tableau non trié
# ne provoque aucune erreur : il rend simplement des valeurs fausses, en silence. C'est le contrôle
# qui attrape la cause là où E1 n'attrape que l'effet.
func _probe_tri() -> void:
	var fautes := []
	for id in Weapons.WEAPON_IDS:
		var jeu := _jeu(id)
		for nom in CLIPS:
			var c = jeu[nom]
			for piste_nom in ["weapon", "lhand", "parts", "events"]:
				var piste: Array = c.get(piste_nom)
				for i in range(1, piste.size()):
					var t0 := float((piste[i - 1] as Dictionary)["t"])
					var t1 := float((piste[i] as Dictionary)["t"])
					if t1 < t0:
						fautes.append("%s/%s/%s : cle %d a t=%.3f apres t=%.3f"
							% [id, nom, piste_nom, i, t1, t0])
					if t1 > c.duration + 1e-6:
						fautes.append("%s/%s/%s : cle %d a t=%.3f > duree %.3f"
							% [id, nom, piste_nom, i, t1, c.duration])
	_ok("E2 toutes les pistes sont TRIEES et tiennent dans la duree du clip",
		fautes.is_empty(), "%d faute(s) : %s" % [fautes.size(), str(fautes.slice(0, 3))])


# =================================================================================================
# E3. ⭐ LE CHARGEUR NE CLIGNOTE PAS
# =================================================================================================
# 🩸 Leur ligne 90 force la visibilité sur la PREMIÈRE MOITIÉ de tout segment, même quand les deux
# bornes disent « caché ». Mesuré sur leur code, rechargement tactique de 2,1 s :
#   visible 0→0,672 · CACHÉ 0,672→0,715 (43 ms) · visible 0,715→1,051 · CACHÉ 1,051→1,387 · visible
# Trois basculements de trop. Et chez eux c'est pire encore : l'événement `magdrop` fait apparaître
# le chargeur jeté à 0,714 s, **exactement quand celui de la main redevient visible** — deux
# chargeurs à l'écran pendant 0,34 s.
# Un rechargement honnête a DEUX basculements : le chargeur disparaît une fois, revient une fois.
func _probe_strobe() -> void:
	var fautes := []
	for id in Weapons.WEAPON_IDS:
		var jeu := _jeu(id)
		for nom in ["reload_tac", "reload_empty"]:
			var c = jeu[nom]
			var s = Clips.Sample.new()
			var bascules := 0
			var prec := true
			for k in 2000:
				c.sample(c.duration * float(k) / 1999.0, s)
				if s.mag_visible != prec:
					bascules += 1
					prec = s.mag_visible
			if bascules != 2:
				fautes.append("%s/%s : %d basculements (2 attendus)" % [id, nom, bascules])
	_ok("E3 le chargeur disparait UNE fois et revient UNE fois (pas de clignotement)",
		fautes.is_empty(), "%d faute(s) : %s" % [fautes.size(), str(fautes.slice(0, 3))])


# =================================================================================================
# E4. ⭐⭐ LA DURÉE SUIT LE SERVEUR, ELLE N'EST PAS DÉCIDÉE ICI
# =================================================================================================
# ⛔ `clips.js:141-142` lit `def.reloadTac ?? 2.15` et `def.reloadEmpty ?? 2.85` — deux DURÉES DE
# RECHARGEMENT AUTORITAIRES avec des DÉFAUTS. Chez nous elles vivent au serveur (`reload_ticks`,
# diffusé par `public_rules`, et c'est le serveur qui remplit le chargeur à l'échéance).
# 🩸 Le danger est le défaut, pas la lecture : 2,15 s d'animation pour une VIPÈRE que le serveur
# recharge en 1,50 s, c'est une main qui revient au garde-main 0,65 s APRÈS l'autorisation de tirer.
# On vérifie donc que la durée SUIT l'argument — et que les deux rechargements ont la MÊME (le
# serveur n'en connaît qu'une ; leur ratio 2,1/2,9 est lui-même une valeur de règle).
func _probe_duree() -> void:
	var fautes := []
	for id in Weapons.WEAPON_IDS:
		for secondes in [1.5, 2.2, 3.7]:
			var jeu := _jeu(id, secondes)
			for nom in ["reload_tac", "reload_empty"]:
				var c = jeu[nom]
				if absf(c.duration - secondes) > 1e-6:
					fautes.append("%s/%s : duree %.3f pour %.3f demandees"
						% [id, nom, c.duration, secondes])
				var s = Clips.Sample.new()
				c.sample(c.duration * 0.5, s)
				if s.pos.length() < 1e-6:
					fautes.append("%s/%s : clip INERTE a mi-course" % [id, nom])
			if absf(float(jeu["reload_tac"].duration) - float(jeu["reload_empty"].duration)) > 1e-9:
				fautes.append("%s : les deux rechargements n'ont pas la meme duree" % id)
	_ok("E4 la duree de rechargement SUIT l'argument serveur, identique pour les deux clips",
		fautes.is_empty(), "%d faute(s) : %s" % [fautes.size(), str(fautes.slice(0, 3))])


# =================================================================================================
# E5. ⭐⭐ AUCUNE VALEUR DE RÈGLE DANS LE REGISTRE DE VUE
# =================================================================================================
# Le lot 3D-B a posé cette frontière ; le lot 3D-E est le premier à la TOUCHER, puisque `clips.js`
# lit des durées de rechargement. On reverrouille ici, avec la liste dans les deux conventions de
# nommage — un contrôle qu'on ne peut pas satisfaire par inadvertance.
const INTERDITS := [
	"reload", "reload_tac", "reload_empty", "reloadTac", "reloadEmpty", "reload_ticks",
	"reloadTicks", "mag_size", "magSize", "reserve", "rpm", "damage", "degats", "spread",
	"spread_hip", "spreadHip", "spread_ads", "spreadAds", "dispersion", "dispersion_deg",
	"penetration", "max_range", "maxRange", "cycle_time", "cycleTime", "fire_rate", "fireRate",
	"headshot", "armor", "ttk",
]
func _probe_frontiere() -> void:
	var fautes := []
	for id in Weapons.WEAPON_IDS:
		var vd: Dictionary = Weapons.view_def(id)
		for cle in vd:
			if INTERDITS.has(String(cle)):
				fautes.append("%s : le registre de vue porte `%s`" % [id, cle])
	# Et la porte elle-même : la construction ne DOIT PAS pouvoir se faire sans durée fournie.
	# On le mesure au lieu de l'affirmer : deux durées differentes doivent donner deux clips
	# differents. Si un defaut interne existait, l'argument serait ignore et les deux seraient
	# identiques — ce que E4 attrape deja ; ici on verrouille le REGISTRE.
	var m: Dictionary = Weapons.build("chacal")
	var nds: Dictionary = m["nodes"]
	for cle in nds:
		if INTERDITS.has(String(cle)):
			fautes.append("chacal : le noeud d'attache porte `%s`" % cle)
	_ok("E5 ni le registre de vue ni les noeuds d'attache ne portent une valeur de REGLE",
		fautes.is_empty(), "%d faute(s) : %s" % [fautes.size(), str(fautes)])


# =================================================================================================
# E6. LES ÉVÉNEMENTS PARTENT TOUS, UNE FOIS, DANS L'ORDRE
# =================================================================================================
# Rejoue chaque clip par pas de 1/60 s et compte. Un événement qui ne part jamais est un son
# perdu ; un événement qui part deux fois est un son doublé. Les deux sont muets à la lecture.
func _probe_evenements() -> void:
	var fautes := []
	for id in Weapons.WEAPON_IDS:
		var jeu := _jeu(id)
		for nom in CLIPS:
			var c = jeu[nom]
			var vus := []
			var prec := -1.0
			var t := 0.0
			while t < c.duration + 1.0 / 60.0:
				var maintenant: float = minf(t, c.duration)
				for e in Clips.events_between(c, prec, maintenant):
					vus.append(e)
				prec = maintenant
				t += 1.0 / 60.0
			var attendus := []
			for e in c.events:
				attendus.append(String((e as Dictionary)["name"]))
			if vus != attendus:
				fautes.append("%s/%s : %s au lieu de %s" % [id, nom, str(vus), str(attendus)])
	_ok("E6 chaque evenement part UNE fois et dans l'ordre, sur toute la duree",
		fautes.is_empty(), "%d faute(s) : %s" % [fautes.size(), str(fautes.slice(0, 2))])


# =================================================================================================
# E7. ⭐ LA MAIN D'APPUI NE TÉLÉPORTE JAMAIS, ET SA VITESSE NE DÉRIVE PAS
# =================================================================================================
# 🩸 Mesuré sur leur code : à cause des clés `t: 1` non remises à l'échelle, la main d'appui de
# `reloadTac` saute de (0,000 ; −0,082 ; 0,020) à la prise en **26 cm sur une seule image**, et la
# pose bascule `open → wrap` dans le même pas. C'est un défaut qu'aucune inspection du code ne
# donne et qu'aucun test de valeur finale n'attrape : il faut ÉCHANTILLONNER LE MOUVEMENT.
#
# ╔═ ⚠️ DEUX CONTRÔLES EN UN, ET C'EST DÉLIBÉRÉ ════════════════════════════════════════════════╗
# ║ 🩸 Premier jet : un seuil unique à 60 mm/image, calé sur les pointes que j'avais SOUS LES     ║
# ║ YEUX (44 mm au rechargement tactique). Il a rougi sur l'approche du levier d'armement du      ║
# ║ `chacal` — **60,3 mm**, une valeur que la référence lui a toujours donnée et que je n'avais   ║
# ║ pas encore isolée. Un seuil tiré d'un échantillon de trois points condamne le quatrième.      ║
# ║                                                                                               ║
# ║ On sépare donc les deux questions, parce que ce sont deux natures de défaut :                  ║
# ║  • **TÉLÉPORTATION** — seuil tiré de la PHYSIQUE, pas de mon échantillon : une main humaine    ║
# ║    rapide plafonne vers 7 m/s, soit ~117 mm par image à 60 Hz. Au-delà de **120 mm**, ce n'est ║
# ║    plus un geste, c'est une coupure. Le défaut de la référence en faisait 260.                 ║
# ║  • **DÉRIVE** — garde-fou de NON-RÉGRESSION sur les pointes relevées ci-dessous. Il ne dit pas ║
# ║    ce qui est beau ; il rougit si une retouche accélère un geste de plus de 5 mm/image.        ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# Pointes relevées (mm par image à 60 Hz, rechargement de 2,20 s) :
#   arme   | tactique | à sec | inspection | sortie | rangement
#   vipere |   29,8   |  42,8 |    2,6     |  20,4  |   19,5
#   frelon |   41,0   |  49,3 |    2,4     |  16,7  |   17,3
#   chacal |   44,0   |  60,3 |    2,1     |  14,1  |   14,8
#   condor |   35,4   |  55,1 |    2,0     |  11,3  |   12,0
const POINTES := {
	"vipere": {"reload_tac": 29.8, "reload_empty": 42.8, "inspect": 2.6, "draw": 20.4,
		"holster": 19.5},
	"frelon": {"reload_tac": 41.0, "reload_empty": 49.3, "inspect": 2.4, "draw": 16.7,
		"holster": 17.3},
	"chacal": {"reload_tac": 44.0, "reload_empty": 60.3, "inspect": 2.1, "draw": 14.1,
		"holster": 14.8},
	"condor": {"reload_tac": 35.4, "reload_empty": 55.1, "inspect": 2.0, "draw": 11.3,
		"holster": 12.0},
}
func _probe_teleport() -> void:
	var teleports := []
	var derives := []
	for id in Weapons.WEAPON_IDS:
		var jeu := _jeu(id)
		for nom in CLIPS:
			var c = jeu[nom]
			var s = Clips.Sample.new()
			var prec := Vector3.INF
			var pire := 0.0
			var quand := 0.0
			var n := int(ceilf(c.duration * 60.0))
			for k in n + 1:
				var t: float = minf(c.duration, float(k) / 60.0)
				c.sample(t, s)
				if prec != Vector3.INF:
					var saut: float = s.lh_pos.distance_to(prec)
					if saut > pire:
						pire = saut
						quand = t
				prec = s.lh_pos
			var mm := pire * 1000.0
			if mm > 120.0:
				teleports.append("%s/%s : %.0f mm a t=%.2f s" % [id, nom, mm, quand])
			var repere: float = float((POINTES[id] as Dictionary)[nom])
			if mm > repere + 5.0:
				derives.append("%s/%s : %.1f mm (repere %.1f)" % [id, nom, mm, repere])
	_ok("E7 aucune teleportation (>120 mm/image) et aucune derive du releve des pointes",
		teleports.is_empty() and derives.is_empty(),
		"teleportations : %s · derives : %s" % [str(teleports), str(derives)])
