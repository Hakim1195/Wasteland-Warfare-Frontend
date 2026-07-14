extends Control

# =========================================================
# SPLIT-SCREEN VS — RÉSOLUTION VISUELLE D'UN COMBAT
# =========================================================
# Scène-surcouche instanciée dynamiquement par main.gd au-dessus du HUD quand le serveur
# renvoie un attack_result. L'écran se scinde en deux (attaquant à gauche, défenseur à
# droite), affiche les héros des factions et anime les dés façon "machine à sous", puis
# émet animation_finished et s'auto-détruit (queue_free). main.gd `await` ce signal pour
# figer la mise à jour visuelle du plateau pendant toute la chorégraphie.
#
# Découplage (Règle d'Or §6.1) : cette scène est une VUE pure. Elle reçoit des ids de
# faction et des jets de dés DÉJÀ résolus par le serveur — aucune logique de jeu, aucun
# accès réseau. Les données de faction sont chargées depuis les ressources data-driven
# resources/factions/*.tres (même pattern robuste que faction_selection.gd).

signal animation_finished

# Ressources de factions (scan + repli explicite + duck-typing, cf. correctifs §8.14).
const FACTIONS_DIR := "res://resources/factions/"
const FALLBACK_PATHS := [
	"res://resources/factions/nomades.tres",
	"res://resources/factions/phalangistes.tres",
	"res://resources/factions/rad_hunters.tres",
]

# Chorégraphie (durées en secondes).
const SLIDE_IN_TIME := 0.3   # Phase 1 — impact des deux moitiés
const ROLL_TIME := 1.5       # Phase 2 — roulement machine à sous
const ROLL_TICK := 0.05      #   cadence de changement des valeurs
const LOCK_STAGGER := 0.2    # Phase 3 — délai entre l'arrêt de chaque dé
const READ_TIME := 2.0       # Phase 5 — lecture du résultat avant la sortie
const FADE_OUT_TIME := 0.5   #   fondu de sortie global

# Filet de sécurité : durée de vie maximale de la surcouche (somme des phases ≈ 5,5 s max).
# main.gd suspend le rafraîchissement du plateau sur animation_finished : si une erreur
# imprévue interrompait la chorégraphie (coroutine avortée sans exception rattrapable),
# le signal ne partirait jamais et l'arène resterait figée. Ce garde-fou l'exclut.
const MAX_LIFETIME := 12.0

# Esthétique militaire (§5) : chiffres énormes, bords anguleux, accents très assombris.
const DIE_FONT_SIZE := 96
const DIE_SIZE := Vector2(132, 132)
const COLOR_DIE_BG := Color("#0f1318")
const COLOR_LOSER_CROSS := Color("#d6453f")
# Accents de repli si la faction n'a pas (encore) de .tres : charte Warzone Command (cyan / acier).
const FALLBACK_ACCENT_ATTACKER := Color("#36c5d9")
const FALLBACK_ACCENT_DEFENDER := Color("#5c6b78")
# Pop « TIME BANK +Ns » (récompense de l'attaquant) — or Warzone.
const COLOR_TIME_BANK := Color("#e0b249")
# Héros 3D (SubViewport transparent) — remplace les portraits 2D des deux camps si la faction a un .glb.
# Préchargé (pas de class_name, par prudence vis-à-vis du cache d'import).
const HeroViewport3DScene = preload("res://scenes/components/hero_viewport_3d.tscn")

@onready var _dim: ColorRect = %Dim
@onready var _vs_label: Label = %VSLabel
@onready var _left_half: Control = %LeftHalf
@onready var _right_half: Control = %RightHalf

# Dés instanciés (PanelContainer contenant les Labels "Value" et "Cross").
var _attack_dice: Array = []
var _defense_dice: Array = []
# Dés déjà verrouillés sur leur vraie valeur (la boucle de spin les ignore).
var _locked: Dictionary = {}
# Vrai tant que la machine à sous tourne (Phases 2-3).
var _spinning: bool = false
# Métadonnées du combat (pertes, Time Bank, attaquant local) poussées par main.gd (§3 Warzone).
var _meta: Dictionary = {}
# Instances de héros 3D par camp (montées une fois dans le cadre du portrait, modèle échangé via
# set_model). Non typées à dessein (appels dynamiques — pas de class_name sur le composant).
var _left_hero3d = null
var _right_hero3d = null

func _ready() -> void:
	# Garde-fou anti-gel (voir MAX_LIFETIME). En flux nominal la scène est libérée bien
	# avant l'échéance : Godot nettoie alors la connexion vers l'objet détruit, l'appel
	# n'a jamais lieu. Ne se déclenche donc qu'en cas d'anomalie.
	get_tree().create_timer(MAX_LIFETIME).timeout.connect(_on_lifetime_expired)

func _on_lifetime_expired() -> void:
	_spinning = false
	animation_finished.emit()
	queue_free()

# =========================================================
# POINT D'ENTRÉE (appelé par main.gd juste après add_child)
# =========================================================

func start_combat_resolution(attacker_faction_id: String, defender_faction_id: String,
		attack_rolls: Array, defense_rolls: Array, meta: Dictionary = {}) -> void:
	_meta = meta
	# Skins équipés (M5 §8.69) : lus du PlayerState PUBLIC de chaque camp par main.gd et passés
	# dans meta — LES DEUX joueurs voient donc le skin de l'autre (moment vitrine du cosmétique).
	var attacker := _load_faction(attacker_faction_id, FALLBACK_ACCENT_ATTACKER,
		str(meta.get("attacker_skin", "")))
	var defender := _load_faction(defender_faction_id, FALLBACK_ACCENT_DEFENDER,
		str(meta.get("defender_skin", "")))
	_setup_side(true, attacker)
	_setup_side(false, defender)
	_attack_dice = _spawn_dice(%LeftDice, attack_rolls.size(), attacker["accent"])
	_defense_dice = _spawn_dice(%RightDice, defense_rolls.size(), defender["accent"])

	await _phase_impact()
	_spinning = true
	_spin_loop() # coroutine machine à sous, tourne en arrière-plan jusqu'à la fin du verrouillage
	await get_tree().create_timer(ROLL_TIME).timeout
	await _phase_lock(attack_rolls, defense_rolls)
	_phase_result(attack_rolls, defense_rolls)
	_show_damage_and_bank()
	await get_tree().create_timer(READ_TIME).timeout
	await _phase_exit()
	animation_finished.emit()
	queue_free()

# =========================================================
# CHARGEMENT DES DONNÉES DE FACTION (data-driven)
# =========================================================

# Retrouve la ressource FactionData correspondant à l'id réseau (ex: "phalanges_acier").
# 7 factions sur 10 n'ont pas encore de .tres au stade MVP : repli sur un libellé dérivé
# de l'id et un accent de la charte, pour que l'écran reste fonctionnel quoi qu'il arrive.
func _load_faction(faction_id: String, fallback_accent: Color, equipped_skin: String = "") -> Dictionary:
	var out := {}
	for res in _faction_resources():
		if str(res.get("id")) == faction_id:
			# Coercitions défensives : le duck-typing n'exige que "id" ; une ressource sans
			# accent_color (null) ferait crasher l'assignation typée de _setup_side, et un
			# hero_path null ferait crasher ResourceLoader.exists().
			var accent = res.get("accent_color")
			var hero = res.get("hero_path")
			var model = res.get("hero_model_path")
			out = {
				"name": str(res.get("name")),
				"accent": accent if accent is Color else fallback_accent,
				"hero_path": hero if hero is String else "",
				"hero_model_path": model if model is String else "",
			}
			break
	if out.is_empty():
		var pretty := faction_id.capitalize() if faction_id != "" else "Faction Inconnue"
		out = {"name": pretty, "accent": fallback_accent, "hero_path": "", "hero_model_path": ""}

	# --- Skin équipé (M5 §8.69) : surcharge data-driven des visuels du héros. Un SkinData dont
	#     l'id ET la faction correspondent surcharge portrait/modèle (si ses chemins EXISTENT)
	#     et l'accent (accent_override) — placeholder teinté sinon (convention §4.3). ---
	if equipped_skin != "":
		var skin = _find_skin(equipped_skin, faction_id)
		if skin != null:
			var s_portrait := str(skin.get("portrait_path") if skin.get("portrait_path") != null else "")
			var s_model := str(skin.get("model_path") if skin.get("model_path") != null else "")
			if s_portrait != "" and ResourceLoader.exists(s_portrait):
				out["hero_path"] = s_portrait
			if s_model != "" and ResourceLoader.exists(s_model):
				out["hero_model_path"] = s_model
			var s_accent = skin.get("accent_override")
			if s_accent is Color:
				out["accent"] = s_accent
	return out

# =========================================================
# Registre des SKINS (M5 §8.69 — data-driven, pattern factions §4.3)
# =========================================================
const SKINS_DIR := "res://resources/skins/"

# Retrouve la ressource SkinData (id + faction cohérents), ou null. Duck-typing (comme les
# factions) : on n'exige pas le class_name global SkinData, seulement les champs.
func _find_skin(skin_id: String, faction_id: String):
	var dir := DirAccess.open(SKINS_DIR)
	if dir == null:
		return null
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var fn := file_name
			if fn.ends_with(".remap"):
				fn = fn.trim_suffix(".remap")
			if fn.ends_with(".tres"):
				var full := SKINS_DIR + fn
				if ResourceLoader.exists(full):
					var res = load(full)
					if res != null and str(res.get("id")) == skin_id \
							and str(res.get("faction_id")) == faction_id:
						dir.list_dir_end()
						return res
		file_name = dir.get_next()
	dir.list_dir_end()
	return null

# Charge toutes les ressources de factions. Duck-typing : on n'exige pas le type global
# FactionData (son enregistrement peut manquer selon le cache d'import, cf. §8.14 bug 2).
func _faction_resources() -> Array:
	var paths := _scan_faction_paths()
	if paths.is_empty():
		paths = FALLBACK_PATHS.duplicate()
	var out := []
	for p in paths:
		if not ResourceLoader.exists(p):
			continue
		var res = load(p)
		if res != null and res.get("id") != null:
			out.append(res)
	return out

# Liste les .tres du dossier de factions. Export-safe : en build exporté un .tres peut
# être listé en ".tres.remap" ; on retombe alors sur le .tres d'origine.
func _scan_faction_paths() -> Array:
	var out := []
	var dir := DirAccess.open(FACTIONS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var fn := file_name
			if fn.ends_with(".remap"):
				fn = fn.trim_suffix(".remap")
			if fn.ends_with(".tres"):
				var full := FACTIONS_DIR + fn
				if not out.has(full):
					out.append(full)
		file_name = dir.get_next()
	dir.list_dir_end()
	return out

# =========================================================
# PEUPLEMENT DE L'UI (portraits, noms, fonds, dés)
# =========================================================

func _setup_side(is_left: bool, faction: Dictionary) -> void:
	var accent: Color = faction["accent"]
	var role_label: Label = %LeftRole if is_left else %RightRole
	var name_label: Label = %LeftName if is_left else %RightName
	var frame: PanelContainer = %LeftPortraitFrame if is_left else %RightPortraitFrame
	var portrait: TextureRect = %LeftPortrait if is_left else %RightPortrait
	var placeholder: ColorRect = %LeftPlaceholder if is_left else %RightPlaceholder
	var background: TextureRect = %LeftBackground if is_left else %RightBackground

	role_label.text = "⚔ ATTAQUANT" if is_left else "🛡 DÉFENSEUR"
	name_label.text = str(faction["name"]).to_upper()
	name_label.add_theme_color_override("font_color", accent.lightened(0.35))

	# Fond de moitié : gradient horizontal accent TRÈS assombri -> noir vers le centre (§5).
	background.texture = _make_gradient(accent, is_left)

	# Cadre du portrait : bord anguleux teinté à l'accent de la faction.
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color("#1f2615")
	frame_style.border_color = accent
	frame_style.set_border_width_all(3)
	frame_style.set_corner_radius_all(0)
	frame.add_theme_stylebox_override("panel", frame_style)

	# Héros 3D d'abord : .glb valide → monté dans le cadre, 2D masqué (own_world_3d isole l'éclairage
	# de ce camp de l'autre moitié).
	var hero3d = _ensure_side_hero3d(is_left, frame)
	var model_path: String = str(faction.get("hero_model_path", ""))
	if hero3d != null and hero3d.set_model(model_path):
		hero3d.set_accent(accent)
		hero3d.visible = true
		portrait.visible = false
		placeholder.visible = false
		return

	# Repli 2D : portrait du héros, ou placeholder teinté (même convention que le carrousel de Draft).
	if hero3d != null:
		hero3d.visible = false
	var tex = null
	if faction["hero_path"] != "" and ResourceLoader.exists(faction["hero_path"]):
		tex = load(faction["hero_path"])
	if tex != null:
		portrait.texture = tex
		portrait.visible = true
		placeholder.visible = false
	else:
		portrait.visible = false
		placeholder.visible = true
		placeholder.color = accent.darkened(0.25)

# Monte (une seule fois par camp) le composant héros 3D dans le cadre du portrait. Renvoie
# l'instance (ou null si le cadre manque). Non typé → appels dynamiques set_model/set_accent.
func _ensure_side_hero3d(is_left: bool, frame: PanelContainer):
	if is_left and _left_hero3d != null:
		return _left_hero3d
	if not is_left and _right_hero3d != null:
		return _right_hero3d
	if frame == null:
		return null
	var inst = HeroViewport3DScene.instantiate()
	frame.add_child(inst)
	if is_left:
		_left_hero3d = inst
	else:
		_right_hero3d = inst
	return inst

# Gradient orienté vers le centre de l'écran (l'extérieur porte la couleur de faction).
func _make_gradient(accent: Color, is_left: bool) -> GradientTexture2D:
	var outer := accent.darkened(0.55)
	outer.a = 0.95
	var inner := Color(0.02, 0.03, 0.01, 0.97)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([outer, inner] if is_left else [inner, outer])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(1.0, 0.0)
	return tex

# Instancie `count` dés stylisés (PanelContainer anguleux + chiffre énorme + croix cachée).
func _spawn_dice(container: HBoxContainer, count: int, accent: Color) -> Array:
	var dice := []
	for _i in range(count):
		var die := PanelContainer.new()
		die.custom_minimum_size = DIE_SIZE
		var style := StyleBoxFlat.new()
		style.bg_color = COLOR_DIE_BG
		style.border_color = accent
		style.set_border_width_all(3)
		style.set_corner_radius_all(0) # bords anguleux (§5)
		die.add_theme_stylebox_override("panel", style)

		var value := Label.new()
		value.name = "Value"
		value.text = "?"
		value.add_theme_font_size_override("font_size", DIE_FONT_SIZE)
		value.add_theme_color_override("font_color", accent.lightened(0.5))
		value.add_theme_constant_override("outline_size", 8)
		value.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		die.add_child(value)

		# Croix rouge de dé perdant (Phase 4), superposée à la valeur, cachée par défaut.
		var cross := Label.new()
		cross.name = "Cross"
		cross.text = "✗"
		cross.visible = false
		cross.add_theme_font_size_override("font_size", DIE_FONT_SIZE)
		cross.add_theme_color_override("font_color", COLOR_LOSER_CROSS)
		cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		die.add_child(cross)

		container.add_child(die)
		dice.append(die)
	return dice

# =========================================================
# PHASE 1 — L'IMPACT (glissement violent des deux moitiés)
# =========================================================

func _phase_impact() -> void:
	# Anti-flash : la scène reste invisible (modulate, pour ne pas geler la mise en page)
	# le temps que les conteneurs calculent les positions cibles des deux moitiés.
	modulate.a = 0.0
	_dim.modulate.a = 0.0
	_vs_label.modulate.a = 0.0
	await get_tree().process_frame

	var width := get_viewport_rect().size.x
	var left_target := _left_half.position.x
	var right_target := _right_half.position.x
	_left_half.position.x = left_target - width * 0.6
	_right_half.position.x = right_target + width * 0.6
	_vs_label.pivot_offset = _vs_label.size / 2.0
	_vs_label.scale = Vector2(2.5, 2.5)
	modulate.a = 1.0

	var tween := create_tween().set_parallel(true)
	tween.tween_property(_dim, "modulate:a", 1.0, SLIDE_IN_TIME)
	tween.tween_property(_left_half, "position:x", left_target, SLIDE_IN_TIME) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(_right_half, "position:x", right_target, SLIDE_IN_TIME) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	# Le "VS" central claque à l'impact.
	tween.tween_property(_vs_label, "modulate:a", 1.0, SLIDE_IN_TIME)
	tween.tween_property(_vs_label, "scale", Vector2.ONE, SLIDE_IN_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished

# =========================================================
# PHASE 2 — LE ROULEMENT (machine à sous)
# =========================================================

# Toutes les ROLL_TICK secondes, chaque dé NON verrouillé affiche une valeur aléatoire.
# Continue de tourner pendant la Phase 3 pour les dés pas encore arrêtés.
func _spin_loop() -> void:
	while _spinning and is_inside_tree():
		for die in _attack_dice + _defense_dice:
			if not _locked.has(die):
				die.get_node("Value").text = str(randi_range(1, 6))
		await get_tree().create_timer(ROLL_TICK).timeout

# =========================================================
# PHASE 3 — LE VERROUILLAGE (arrêt un par un sur les vraies valeurs)
# =========================================================

func _phase_lock(attack_rolls: Array, defense_rolls: Array) -> void:
	# Alternance attaque/défense pour la montée de tension. int(...) : les valeurs issues
	# du JSON serveur sont des floats (piège Godot, cf. CONTEXTE.md §5).
	var order := []
	for i in range(maxi(attack_rolls.size(), defense_rolls.size())):
		if i < attack_rolls.size():
			order.append([_attack_dice[i], int(attack_rolls[i])])
		if i < defense_rolls.size():
			order.append([_defense_dice[i], int(defense_rolls[i])])
	for entry in order:
		await get_tree().create_timer(LOCK_STAGGER).timeout
		_lock_die(entry[0], entry[1])
	_spinning = false

func _lock_die(die: Control, value: int) -> void:
	_locked[die] = true
	die.get_node("Value").text = str(value)
	# SFX §8.66 : claque sèche à chaque dé qui se verrouille (feedback de tension).
	AudioManager.play_sfx("die_lock")
	# Punch d'arrêt : le dé "claque" sur sa valeur réelle.
	die.pivot_offset = die.size / 2.0
	die.scale = Vector2(1.35, 1.35)
	create_tween().tween_property(die, "scale", Vector2.ONE, 0.15) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# =========================================================
# PHASE 4 — LE RÉSULTAT (règles Risk : plus hauts dés comparés par paires)
# =========================================================

func _phase_result(attack_rolls: Array, defense_rolls: Array) -> void:
	# Les jets arrivent DÉJÀ triés du plus haut au plus bas par le serveur (engine.py).
	# Comparaison paire à paire ; ÉGALITÉ = avantage défenseur (§4.2). Le perdant de chaque
	# duel est assombri et barré d'une croix rouge ; les dés non appariés ne combattent pas.
	var pairs := mini(attack_rolls.size(), defense_rolls.size())
	for i in range(pairs):
		if int(attack_rolls[i]) > int(defense_rolls[i]):
			_mark_loser(_defense_dice[i])
		else:
			_mark_loser(_attack_dice[i])

func _mark_loser(die: Control) -> void:
	die.get_node("Cross").visible = true
	create_tween().tween_property(die, "modulate", Color(0.4, 0.4, 0.4, 1.0), 0.3)

# §3 Warzone — affichage des DÉGÂTS (gros « −N » lumineux par camp) + pop « TIME BANK +Ns ».
func _show_damage_and_bank() -> void:
	var atk_losses := int(_meta.get("attacker_losses", 0))
	var def_losses := int(_meta.get("defender_losses", 0))
	# SFX §8.66 : coup encaissé à la révélation des pertes (un seul impact, même si les deux camps perdent).
	if atk_losses > 0 or def_losses > 0:
		AudioManager.play_sfx("impact")
	if atk_losses > 0:
		_spawn_damage_number(_left_half, -atk_losses)
	if def_losses > 0:
		_spawn_damage_number(_right_half, -def_losses)
	# TIME BANK : uniquement pour l'ATTAQUANT LOCAL (le serveur n'étend QUE son timer, §8.33).
	if bool(_meta.get("local_is_attacker", false)) and int(_meta.get("time_bank_bonus", 0)) > 0:
		_spawn_time_bank(int(_meta.get("time_bank_bonus", 0)))

# Gros nombre de pertes qui jaillit (punch) puis s'élève et s'efface (rouge danger lumineux).
func _spawn_damage_number(half: Control, amount: int) -> void:
	var lbl := Label.new()
	lbl.text = str(amount)
	lbl.add_theme_font_size_override("font_size", 110)
	lbl.add_theme_color_override("font_color", COLOR_LOSER_CROSS)
	lbl.add_theme_constant_override("outline_size", 10)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size = Vector2(160, 130)
	half.add_child(lbl)
	lbl.position = Vector2(half.size.x * 0.5 - 80.0, half.size.y * 0.58)
	lbl.pivot_offset = lbl.size * 0.5
	lbl.scale = Vector2(0.4, 0.4)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "position:y", lbl.position.y - 110.0, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var fade := create_tween()
	fade.tween_interval(1.0)
	fade.tween_property(lbl, "modulate:a", 0.0, 0.6)
	fade.tween_callback(lbl.queue_free)

# Pop « ⏱ TIME BANK +Ns » (or) qui s'envole côté attaquant (récompense de l'attaque).
func _spawn_time_bank(bonus: int) -> void:
	var lbl := Label.new()
	lbl.text = "⏱ TIME BANK +%ds" % bonus
	lbl.add_theme_font_size_override("font_size", 46)
	lbl.add_theme_color_override("font_color", COLOR_TIME_BANK)
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size = Vector2(360, 60)
	_left_half.add_child(lbl)
	lbl.position = Vector2(_left_half.size.x * 0.5 - 180.0, _left_half.size.y * 0.30)
	lbl.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "modulate:a", 1.0, 0.25)
	tw.tween_property(lbl, "position:y", lbl.position.y - 110.0, 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var fade := create_tween()
	fade.tween_interval(1.4)
	fade.tween_property(lbl, "modulate:a", 0.0, 0.5)
	fade.tween_callback(lbl.queue_free)

# =========================================================
# PHASE 5 — LA SORTIE (fade out global)
# =========================================================

func _phase_exit() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_OUT_TIME)
	await tween.finished
