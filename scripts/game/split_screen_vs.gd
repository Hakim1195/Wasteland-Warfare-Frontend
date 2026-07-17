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

# Filet de sécurité : durée de vie maximale de la surcouche (somme des phases ≈ 5,5 s max,
# + duel de héros E2 ≈ 0,6 s, + permadeath ≈ 1,6 s → ~7,7 s max). main.gd suspend le
# rafraîchissement du plateau sur animation_finished : si une erreur imprévue interrompait la
# chorégraphie (coroutine avortée sans exception rattrapable), le signal ne partirait jamais et
# l'arène resterait figée. Ce garde-fou l'exclut (marge large au-dessus du pire cas E2).
const MAX_LIFETIME := 14.0

# --- E2 §8.74 : le combat raconte les HÉROS. ---
# Durées du récit de duel : tween de la barre PV du défenseur, gel dramatique et prolongation
# d'affichage de la permadeath (la surcouche vit +1,2 s de plus — c'est LE moment du jeu).
const HERO_BAR_TWEEN := 0.6
const PERMADEATH_FREEZE := 0.4
const PERMADEATH_EXTRA := 1.2
# Accents héros : dégâts cramoisis, PP gagné cyan / perdu orange (design E2 validé).
const COLOR_HERO_DAMAGE := Color("#d6453f")
const COLOR_PP_UP := Color("#36c5d9")
const COLOR_PP_DOWN := Color("#e0862f")
# Dégradé de santé PARTAGÉ (source unique : war_roster.pv_color, posé au lot E1 §8.73).
const RosterHelpers := preload("res://scripts/ui/war_roster.gd")

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

# --- E2 §8.74 : duel de héros (résolu serveur, champ hero_duel de attack_result §8.61). ---
# {} si hero_duel est null/absent (héros non initialisés, défenseur déjà mort, serveur ancien)
# → TOUTE l'UI héros (barres, jauge PP, flotteurs, tampon) reste masquée, aucun « 0 » fantôme.
var _duel: Dictionary = {}
var _atk_pv_bar: ProgressBar = null
var _atk_pv_lbl: Label = null
var _atk_pp_bar: ProgressBar = null
var _def_pv_bar: ProgressBar = null
var _def_pv_lbl: Label = null
var _def_pv_max: int = 1

# Auto-vérification debug (pattern G4) : une fois par session.
static var _self_checked := false

# --- Rythme des combats (E8 §8.80) : accélération / skip universels (participant ou non). ---
# 1er clic/Espace → vitesse ×VS_FAST ; 2ᵉ → saut au tableau final (dés + pertes + PV posés).
# ⚠️ Engine.time_scale INTERDIT (piège n° 7) : on scale localement les attentes (_wait) et les
# Tweens suivis (_speed_scale). combat_display "rapide" et la chaîne de ré-assaut (E7) démarrent
# pré-accélérés / condensés via meta.
const VS_FAST := 2.5
const SKIP_MIN_DISPLAY := 0.8   # affichage minimal du tableau final après un saut.
var _speed_scale := 1.0
var _skip := false
var _finalized := false         # tableau final déjà posé (idempotence du skip).
# Contexte du résultat, mémorisé pour un finalize immédiat (skip) à tout moment.
var _atk_rolls: Array = []
var _def_rolls: Array = []

func _ready() -> void:
	if OS.is_debug_build() and not _self_checked:
		_self_check()

# Contrôles universels (E8) : 1er clic gauche/Espace → ×2,5 ; 2ᵉ → saut au tableau final.
func _unhandled_input(event: InputEvent) -> void:
	var trigger: bool = (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_SPACE)
	if not trigger:
		return
	get_viewport().set_input_as_handled()
	if _speed_scale < VS_FAST:
		_speed_scale = VS_FAST   # 1er appui : accélère
	else:
		_skip = true             # 2ᵉ appui : saut au tableau final

# Attente SCALÉE et interruptible (E8) : respecte _speed_scale et se termine dès un skip. Remplace
# les `await get_tree().create_timer(x).timeout` de la chorégraphie (jamais Engine.time_scale).
func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds and not _skip and is_inside_tree():
		await get_tree().process_frame
		t += get_process_delta_time() * _speed_scale
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
	# E2 §8.74 : le duel raconte les HÉROS — identités joueurs (pseudos + niveaux), barres PV,
	# garnisons avant ➜ après. Tout est rétro-compatible : meta legacy → aucun ajout visible.
	var duel = meta.get("hero_duel")
	_duel = duel if typeof(duel) == TYPE_DICTIONARY else {}
	_apply_identities()
	_build_hero_duel_ui()
	_build_garrison_labels()
	_build_skip_hint()
	_attack_dice = _spawn_dice(%LeftDice, attack_rolls.size(), attacker["accent"])
	_defense_dice = _spawn_dice(%RightDice, defense_rolls.size(), defender["accent"])
	_atk_rolls = attack_rolls
	_def_rolls = defense_rolls
	# Rythme (E8 §8.80) : mode "rapide" démarre pré-accéléré ; chaîne de ré-assaut (E7) = version
	# condensée (verrouillage direct des dés, pas de machine à sous). meta rétro-compatible.
	if float(meta.get("speed", 1.0)) > 1.0:
		_speed_scale = maxf(_speed_scale, float(meta.get("speed", 1.0)))
	var condensed := bool(meta.get("condensed", false))

	await _phase_impact()
	if not condensed and not _skip:
		_spinning = true
		_spin_loop() # machine à sous en arrière-plan jusqu'à la fin du verrouillage
		await _wait(ROLL_TIME)
		await _phase_lock(attack_rolls, defense_rolls)
	# Tableau final GARANTI (déroulé complet OU skip OU condensé → mêmes labels/PV) : dés
	# verrouillés, perdants barrés, pertes + Time Bank + duel héros posés (chaque étape idempotente).
	_spinning = false
	_lock_all_dice()
	_phase_result(attack_rolls, defense_rolls)
	_show_damage_and_bank()
	# Récit du duel de héros (E2) : instantané si skip/condensé, sinon animé.
	await _play_hero_duel()
	await _wait(SKIP_MIN_DISPLAY if (_skip or condensed) else READ_TIME)
	await _phase_exit()
	animation_finished.emit()
	queue_free()

# Hint discret bas-centre (E8 §8.80) : « CLIC : ACCÉLÉRER ▸ PASSER » — invite aux contrôles.
func _build_skip_hint() -> void:
	var hint := Label.new()
	hint.text = tr("VS_SKIP_HINT")
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color("8a97a5"))
	hint.add_theme_constant_override("outline_size", 4)
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(-110, -46)
	hint.custom_minimum_size = Vector2(220, 0)
	add_child(hint)

# Verrouille TOUS les dés sur leur vraie valeur (idempotent) — appelé au skip / en condensé.
func _lock_all_dice() -> void:
	for i in range(_attack_dice.size()):
		if i < _atk_rolls.size():
			_attack_dice[i].get_node("Value").text = str(int(_atk_rolls[i]))
	for i in range(_defense_dice.size()):
		if i < _def_rolls.size():
			_defense_dice[i].get_node("Value").text = str(int(_def_rolls[i]))

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

	role_label.text = "❯ ATTAQUANT" if is_left else "❯ DÉFENSEUR"
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

# =========================================================
# E2 §8.74 — IDENTITÉS, BARRES PV HÉROS, GARNISONS, DUEL
# =========================================================

# Rôles enrichis : « ❯ ASSAILLANT — <PSEUDO> » / « ❯ DÉFENSEUR — <PSEUDO> » à la couleur
# PLATEAU du joueur, + chip « NIV n » sous chaque rôle. Pseudo absent (meta legacy / territoire
# neutre) → libellés historiques conservés tels quels (client défensif §9.2).
func _apply_identities() -> void:
	_apply_side_identity(true, str(_meta.get("attacker_name", "")),
		_meta.get("attacker_color"), _meta.get("attacker_hero", {}))
	_apply_side_identity(false, str(_meta.get("defender_name", "")),
		_meta.get("defender_color"), _meta.get("defender_hero", {}))

func _apply_side_identity(is_left: bool, pseudo: String, color, hero) -> void:
	if pseudo == "":
		return
	var role: Label = %LeftRole if is_left else %RightRole
	role.text = (tr("VS_ROLE_ATTACKER") if is_left else tr("VS_ROLE_DEFENDER")) % pseudo.to_upper()
	if color is Color:
		role.add_theme_color_override("font_color", color)
	# Chip « NIV n » sous le rôle (masquée si héros non initialisé — aucun niveau fantôme).
	var h: Dictionary = hero if typeof(hero) == TYPE_DICTIONARY else {}
	if int(h.get("pv_max", 0)) <= 0:
		return
	var chip := Label.new()
	chip.text = tr("ROSTER_LEVEL") % int(h.get("level", 1))
	chip.add_theme_font_size_override("font_size", 16)
	chip.add_theme_color_override("font_color", Color("#36c5d9"))
	chip.add_theme_constant_override("outline_size", 4)
	chip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	if not is_left:
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var parent := role.get_parent()
	parent.add_child(chip)
	parent.move_child(chip, role.get_index() + 1)

# Barres PV des héros sous chaque cadre de portrait (uniquement si un duel a eu lieu — E2) :
# attaquant = statique (ses PV ne bougent pas dans le duel asymétrique §8.61) + jauge PP ;
# défenseur = part des PV PRÉ-duel (defender_pv + damage) et encaissera pendant _play_hero_duel.
func _build_hero_duel_ui() -> void:
	if _duel.is_empty():
		return
	var atk_hero: Dictionary = _meta.get("attacker_hero", {}) \
		if typeof(_meta.get("attacker_hero")) == TYPE_DICTIONARY else {}
	# --- Côté attaquant : PV statiques + jauge PP (bornée [pp_min, pp_max] du héros). ---
	if int(atk_hero.get("pv_max", 0)) > 0:
		var apv := int(atk_hero.get("pv_current", 0))
		var apv_max := int(atk_hero.get("pv_max", 1))
		var abox := _make_bars_box(true)
		_atk_pv_bar = _make_pv_bar(apv_max, apv)
		abox.add_child(_atk_pv_bar)
		_atk_pv_lbl = _make_bar_label(tr("HUD_HERO_PV") % [apv, apv_max])
		abox.add_child(_atk_pv_lbl)
		_atk_pp_bar = ProgressBar.new()
		_atk_pp_bar.show_percentage = false
		_atk_pp_bar.custom_minimum_size = Vector2(300, 8)
		_atk_pp_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_atk_pp_bar.min_value = float(int(atk_hero.get("pp_min", -3)))
		_atk_pp_bar.max_value = float(int(atk_hero.get("pp_max", 3)))
		_atk_pp_bar.value = float(pp_gauge_value(_duel, atk_hero))
		RosterHelpers._tint_progress(_atk_pp_bar, Color("#e0b249"))
		_atk_pp_bar.tooltip_text = tr("HUD_HERO_PP") % [int(_duel.get("attacker_pp", 0)),
			int(atk_hero.get("pp_min", -3)), int(atk_hero.get("pp_max", 3))]
		abox.add_child(_atk_pp_bar)
	# --- Côté défenseur : la barre part des PV PRÉ-duel (reconstruits, jamais d'état antérieur). ---
	_def_pv_max = maxi(int(_duel.get("defender_pv_max", 1)), 1)
	var pre := duel_pre_pv(_duel)
	var dbox := _make_bars_box(false)
	_def_pv_bar = _make_pv_bar(_def_pv_max, pre)
	dbox.add_child(_def_pv_bar)
	_def_pv_lbl = _make_bar_label(tr("HUD_HERO_PV") % [pre, _def_pv_max])
	_def_pv_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dbox.add_child(_def_pv_lbl)

# Conteneur des barres héros d'un camp, inséré juste SOUS le cadre du portrait (insertion
# relative, aucune retouche .tscn — piège n° 6 PLAN_EXPERIENCE).
func _make_bars_box(is_left: bool) -> VBoxContainer:
	var frame: PanelContainer = %LeftPortraitFrame if is_left else %RightPortraitFrame
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if is_left else Control.SIZE_SHRINK_END
	var parent := frame.get_parent()
	parent.add_child(box)
	parent.move_child(box, frame.get_index() + 1)
	return box

# ProgressBar PV stylée charte (fond gunmetal, coins droits, remplissage au dégradé de santé).
func _make_pv_bar(pv_max: int, value: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(300, 16)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bar.max_value = float(maxi(pv_max, 1))
	bar.value = float(value)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.058824, 0.07451, 0.094118, 0.9)
	bg.border_color = Color(0.211765, 0.772549, 0.85098, 0.4)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(0)
	bar.add_theme_stylebox_override("background", bg)
	RosterHelpers._tint_progress(bar, RosterHelpers.pv_color(float(value) / float(maxi(pv_max, 1))))
	return bar

func _make_bar_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color("#eef3f7"))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	return lbl

# Garnisons lisibles sous les dés : « 🪖 12 ➜ 9 » par camp (avant ➜ après, données du transport).
# Clés absentes (meta legacy) → rien n'est ajouté.
func _build_garrison_labels() -> void:
	if not _meta.has("attacker_garrison_after"):
		return
	_add_garrison_label(true, int(_meta.get("attacker_garrison_before", 0)),
		int(_meta.get("attacker_garrison_after", 0)))
	_add_garrison_label(false, int(_meta.get("defender_garrison_before", 0)),
		int(_meta.get("defender_garrison_after", 0)))

func _add_garrison_label(is_left: bool, before: int, after: int) -> void:
	var dice: HBoxContainer = %LeftDice if is_left else %RightDice
	var lbl := Label.new()
	lbl.text = "%d ➜ %d" % [before, after]
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color",
		Color("#8a97a5") if after >= before else Color("#d6453f").lightened(0.2))
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	if not is_left:
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var parent := dice.get_parent()
	parent.add_child(lbl)
	parent.move_child(lbl, dice.get_index() + 1)

# Récit du duel de héros (après _phase_result) : Tween 0,6 s de la barre du défenseur depuis
# ses PV pré-duel vers defender_pv, flotteur « -N PV » cramoisi (plus gros que les pertes de
# troupes), flotteur « ±N PP » côté attaquant, permadeath spectaculaire si hero_died.
func _play_hero_duel() -> void:
	if _duel.is_empty() or _def_pv_bar == null:
		return
	var damage := int(_duel.get("damage", 0))
	var def_pv := int(_duel.get("defender_pv", 0))
	# Flotteurs : dégâts héros côté défenseur (au-dessus des pertes de troupes), delta PP côté
	# attaquant (cyan gagné / orange perdu).
	if damage > 0:
		_spawn_floater(_right_half, "-%d PV" % damage, COLOR_HERO_DAMAGE, 130, 0.40)
		AudioManager.play_sfx("hero_hit")
	var pp_delta := int(_duel.get("pp_delta", 0))
	if pp_delta != 0:
		_spawn_floater(_left_half, "%+d PP" % pp_delta,
			COLOR_PP_UP if pp_delta > 0 else COLOR_PP_DOWN, 56, 0.42)
	# Skip (E8) : la barre saute DIRECTEMENT à la valeur finale (pas de Tween).
	if _skip:
		_set_def_bar(float(def_pv))
	else:
		var tw := create_tween()
		tw.tween_method(_set_def_bar, float(duel_pre_pv(_duel)), float(def_pv), HERO_BAR_TWEEN / _speed_scale) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		await tw.finished
	if bool(_duel.get("hero_died", false)):
		await _play_permadeath()

# Pose valeur + teinte (dégradé de santé) + libellé de la barre du défenseur — cible du
# tween_method (l'animation raconte l'encaissement PV par PV).
func _set_def_bar(v: float) -> void:
	if _def_pv_bar == null:
		return
	_def_pv_bar.value = v
	RosterHelpers._tint_progress(_def_pv_bar, RosterHelpers.pv_color(v / float(_def_pv_max)))
	if _def_pv_lbl != null:
		_def_pv_lbl.text = tr("HUD_HERO_PV") % [int(round(v)), _def_pv_max]

# LE moment dramatique du jeu (E2) : gel 0,4 s, vignette rouge, tampon diagonal
# « HÉROS ABATTU — <PSEUDO> ÉLIMINÉ », SFX dédié, +1,2 s d'affichage.
func _play_permadeath() -> void:
	# Même un SKIP montre la permadeath (LE moment du jeu) — juste plus court (_wait scalé).
	await _wait(PERMADEATH_FREEZE)
	var vignette := ColorRect.new()
	vignette.color = Color(0.55, 0.04, 0.04, 0.0)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(vignette)
	create_tween().tween_property(vignette, "color:a", 0.30, 0.25)

	var stamp := Label.new()
	var pseudo := str(_meta.get("defender_name", "")).to_upper()
	stamp.text = tr("VS_HERO_DOWN_STAMP") % pseudo if pseudo != "" else tr("VS_HERO_DOWN_STAMP_ANON")
	var stamp_font := SystemFont.new()
	stamp_font.font_names = PackedStringArray(["Black Ops One", "Impact", "Arial Black", "Arial"])
	stamp.add_theme_font_override("font", stamp_font)
	stamp.add_theme_font_size_override("font_size", 64)
	stamp.add_theme_color_override("font_color", COLOR_HERO_DAMAGE.lightened(0.15))
	stamp.add_theme_constant_override("outline_size", 12)
	stamp.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stamp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stamp.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(stamp)
	stamp.pivot_offset = get_viewport_rect().size / 2.0
	stamp.rotation_degrees = -8.0
	stamp.scale = Vector2(2.2, 2.2)
	stamp.modulate.a = 0.0
	AudioManager.play_sfx("hero_down")
	var tw := create_tween().set_parallel(true)
	tw.tween_property(stamp, "scale", Vector2.ONE, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(stamp, "modulate:a", 1.0, 0.18)
	# Prolongation de la surcouche : le tampon se lit, le moment s'imprime.
	await _wait(PERMADEATH_EXTRA)

# --- Helpers PURS (statiques, testés — pattern G4) -----------------------------------

# PV du défenseur AVANT le duel, reconstruits depuis les champs du duel (defender_pv + damage,
# bornés au pv_max — l'overkill d'un coup fatal ne gonfle pas la barre au-delà du max).
static func duel_pre_pv(duel: Dictionary) -> int:
	var dmg := int(duel.get("damage", 0))
	var pv := int(duel.get("defender_pv", 0))
	var pv_max := maxi(int(duel.get("defender_pv_max", pv + dmg)), 1)
	return mini(pv + dmg, pv_max)

# Valeur de la jauge PP de l'attaquant, TOUJOURS bornée [pp_min, pp_max] du héros (le serveur
# borne déjà — ceinture-bretelles côté affichage, critère d'acceptation E2).
static func pp_gauge_value(duel: Dictionary, attacker_hero: Dictionary) -> int:
	var lo := int(attacker_hero.get("pp_min", -3))
	var hi := maxi(int(attacker_hero.get("pp_max", 3)), lo)
	return clampi(int(duel.get("attacker_pp", 0)), lo, hi)

static func _self_check() -> void:
	_self_checked = true
	# PV avant = defender_pv + damage (cas nominal) ; borné au pv_max en cas d'overkill.
	assert(duel_pre_pv({"defender_pv": 46, "damage": 14, "defender_pv_max": 60}) == 60)
	assert(duel_pre_pv({"defender_pv": 12, "damage": 9, "defender_pv_max": 60}) == 21)
	assert(duel_pre_pv({"defender_pv": 0, "damage": 99, "defender_pv_max": 60}) == 60)
	# Bornage PP respecté (valeur hors bornes ramenée dans [pp_min, pp_max]).
	assert(pp_gauge_value({"attacker_pp": 5}, {"pp_min": -3, "pp_max": 3}) == 3)
	assert(pp_gauge_value({"attacker_pp": -7}, {"pp_min": -3, "pp_max": 3}) == -3)
	assert(pp_gauge_value({"attacker_pp": 2}, {"pp_min": -3, "pp_max": 3}) == 2)

# Accès de test (tools/test_e2_vs.gd) : l'UI héros est-elle montée ?
func debug_duel_ui_visible() -> bool:
	return _def_pv_bar != null and is_instance_valid(_def_pv_bar) and _def_pv_bar.visible

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
		if _skip:
			break   # E8 : saut au tableau final → _lock_all_dice finit le travail.
		await _wait(LOCK_STAGGER)
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

var _result_marked := false

func _phase_result(attack_rolls: Array, defense_rolls: Array) -> void:
	if _result_marked:   # idempotent (E8 : appelé au déroulé complet ET au finalize/skip).
		return
	_result_marked = true
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
var _damage_shown := false

func _show_damage_and_bank() -> void:
	if _damage_shown:   # idempotent (E8 : jamais de double flotteur au finalize/skip).
		return
	_damage_shown = true
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

# Gros nombre de pertes de troupes qui jaillit (punch) puis s'élève et s'efface (rouge danger).
func _spawn_damage_number(half: Control, amount: int) -> void:
	_spawn_floater(half, str(amount), COLOR_LOSER_CROSS, 110, 0.58)

# Flotteur GÉNÉRIQUE (E2 §8.74) : punch d'apparition puis élévation + fondu. Sert aux pertes de
# troupes (historique ci-dessus), aux dégâts de héros « -N PV » (plus GROS que les pertes) et au
# delta « ±N PP » de l'attaquant — mêmes cinétiques, textes/couleurs/tailles/hauteurs libres.
# Réglage damage_numbers (E10 §8.82) : masque TOUS les flotteurs de dégâts si désactivé.
func _spawn_floater(half: Control, text: String, color: Color, font_size: int, y_frac: float) -> void:
	if not bool(SettingsManager.get_comfort("damage_numbers")):
		return
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_constant_override("outline_size", maxi(4, font_size / 11))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size = Vector2(420, float(font_size) + 24.0)
	half.add_child(lbl)
	lbl.position = Vector2(half.size.x * 0.5 - lbl.size.x * 0.5, half.size.y * y_frac)
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
	lbl.text = "TIME BANK +%ds" % bonus
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
