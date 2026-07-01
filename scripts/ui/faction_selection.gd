extends Control

# =========================================================
# ÉCRAN DE DRAFT — CARROUSEL DE SÉLECTION DE FACTION
# =========================================================
# Étape intercalée entre la salle d'attente et l'arène (CONTEXTE.md §3/§4.3).
# Chaque joueur fait défiler les factions, en confirme une, et la partie ne bascule
# vers main.tscn que lorsque TOUS les joueurs ont verrouillé leur choix.
#
# Découplage (Règle d'Or §6.1) : cet écran est une VUE. Il lit des ressources data-driven
# (resources/factions/*.tres) et parle au réseau exclusivement via NetworkManager (signaux).

const FACTIONS_DIR := "res://resources/factions/"
# Liste de secours : si le scan du dossier ne renvoie rien (cache d'import partagé entre
# instances Godot, build exporté où le listage diffère…), on charge ces chemins explicites.
# Garde-fou de robustesse contre le bug "carrousel vide pour certains joueurs".
# DOIT lister les 10 factions (miroir du registre backend factions.py) pour que le draft
# affiche toujours la sélection COMPLÈTE, même si le scan du dossier échoue (bug "3 factions").
const FALLBACK_PATHS := [
	"res://resources/factions/phalangistes.tres",      # phalanges_acier
	"res://resources/factions/nomades.tres",           # pillards_poussiere
	"res://resources/factions/rad_hunters.tres",       # culte_isotope
	"res://resources/factions/barons_ferraille.tres",
	"res://resources/factions/gardiens_eden.tres",
	"res://resources/factions/corporation_aegis.tres",
	"res://resources/factions/ecorcheurs_cendres.tres",
	"res://resources/factions/eveilles_ruche.tres",
	"res://resources/factions/ordre_eclipse.tres",
	"res://resources/factions/chasseurs_ombres.tres",
]
const SLIDE_OUT := 0.12
const SLIDE_IN := 0.15

@export var faction_name_label: Label
@export var description_label: RichTextLabel
@export var hero_portrait: TextureRect
@export var portrait_placeholder: ColorRect
@export var prev_button: Button
@export var next_button: Button
@export var confirm_button: Button
@export var status_label: Label
@export var card: Control
# Panneau principal : reçoit les encoches de coin biseautées (charte « Warzone Command » §2).
@export var panel: Control
# Compteur de position dans le carrousel (« 03 / 10 »), réactualisé à chaque glissement (R4).
@export var counter_label: Label

# Helpers UI partagés de la charte « Warzone Command » (§2).
const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")
# Héros 3D (SubViewport transparent) — remplace le portrait 2D quand la faction a un .glb riggé.
# Préchargé (pas de class_name, par prudence vis-à-vis du cache d'import).
const HeroViewport3DScene = preload("res://scenes/components/hero_viewport_3d.tscn")

# Factions disponibles, chargées depuis le dossier de ressources.
var _factions: Array = []
# Index de la faction actuellement centrée dans le carrousel (= la sélection courante).
var _index: int = 0
# Vrai une fois le choix local verrouillé (empêche tout nouveau changement).
var _confirmed: bool = false
# Garde anti-spam pendant l'animation du Tween.
var _is_animating: bool = false
# player_id (int) -> faction_id : qui a verrouillé quoi. Sert à détecter "tout le monde a choisi".
var _locked: Dictionary = {}
# Instance du héros 3D, montée une fois dans PortraitWrap (modèle échangé via set_model au défilement).
# Non typée à dessein (appels dynamiques — pas de class_name sur le composant).
var _hero3d = null

func _ready():
	# Encoches biseautées sur le panneau principal (charte « Warzone Command » §2).
	WarzoneUI.add_corner_notches(panel)

	_load_factions()

	prev_button.pressed.connect(_on_prev_pressed)
	next_button.pressed.connect(_on_next_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)

	# SFX d'interface (survol/clic — R6). Le « CONFIRMER » utilise le SFX de validation dédié.
	WarzoneUI.wire_buttons_sfx([prev_button, next_button])
	confirm_button.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	confirm_button.pressed.connect(func() -> void: AudioManager.play_sfx("confirm"))
	AudioManager.start_menu_ambient()  # nappe d'ambiance des menus (idempotente, R6)

	# Réseau : on écoute les verrouillages des autres joueurs.
	NetworkManager.faction_locked.connect(_on_faction_locked)

	if _factions.is_empty():
		# Robustesse : aucune ressource trouvée -> on n'autorise pas de confirmation à vide.
		status_label.text = tr("FS_NO_FACTIONS") % FACTIONS_DIR
		confirm_button.disabled = true
		prev_button.disabled = true
		next_button.disabled = true
		return

	# Un seul élément : pas de navigation possible.
	if _factions.size() <= 1:
		prev_button.disabled = true
		next_button.disabled = true

	_refresh_card(true)
	_update_status()

# Charge toutes les ressources de factions (data-driven : ajout = simple dépôt de .tres).
# Robuste : scan du dossier, repli sur des chemins explicites, et duck-typing (on n'exige PAS
# le type global FactionData, dont l'enregistrement peut manquer selon le cache d'import).
func _load_factions() -> void:
	var paths := _scan_faction_paths()
	if paths.is_empty():
		# Repli : le scan n'a rien donné (cache d'import partagé / build exporté).
		paths = FALLBACK_PATHS.duplicate()
	for p in paths:
		if not ResourceLoader.exists(p):
			continue
		var res = load(p)
		# Duck-typing : on accepte toute ressource exposant au moins un id (script attaché).
		if res != null and res.get("id") != null:
			_factions.append(res)
	# Ordre stable et reproductible entre tous les clients (par id).
	_factions.sort_custom(func(a, b): return str(a.id) < str(b.id))

# Liste les chemins .tres du dossier de factions. Export-safe : un .tres peut être listé en
# ".tres.remap" dans un build exporté ; on retombe alors sur le .tres d'origine.
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
# NAVIGATION DU CARROUSEL (Tween)
# =========================================================

func _on_next_pressed() -> void:
	if _is_animating or _confirmed or _factions.size() <= 1:
		return
	_index = (_index + 1) % _factions.size()
	_animate_card(-1)

func _on_prev_pressed() -> void:
	if _is_animating or _confirmed or _factions.size() <= 1:
		return
	_index = (_index - 1 + _factions.size()) % _factions.size()
	_animate_card(1)

# Glissement fluide : la carte sort dans une direction, son contenu change, elle revient.
func _animate_card(direction: int) -> void:
	_is_animating = true
	var width := card.size.x if card.size.x > 0.0 else 400.0
	var offset := width * 0.6 * float(direction)

	var tween := create_tween().set_trans(Tween.TRANS_CUBIC)
	# Sortie (fondu + glissement).
	tween.tween_property(card, "modulate:a", 0.0, SLIDE_OUT).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(card, "position:x", -offset, SLIDE_OUT).set_ease(Tween.EASE_IN)
	# Échange du contenu hors écran, puis repositionnement de l'autre côté.
	tween.tween_callback(_apply_card_content)
	tween.tween_callback(func(): card.position.x = offset)
	# Entrée (fondu + glissement de retour).
	tween.tween_property(card, "modulate:a", 1.0, SLIDE_IN).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(card, "position:x", 0.0, SLIDE_IN).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func(): _is_animating = false)

# Réinitialise instantanément la carte (au démarrage, sans animation).
func _refresh_card(instant: bool) -> void:
	_apply_card_content()
	if instant:
		card.position.x = 0.0
		card.modulate.a = 1.0

# Peuple la carte centrale avec la faction courante.
func _apply_card_content() -> void:
	var f = _factions[_index]
	faction_name_label.text = f.name
	faction_name_label.add_theme_color_override("font_color", f.accent_color)
	description_label.text = _build_description(f)
	_set_portrait(f)
	# Compteur de position toujours à jour (réactualisé à chaque glissement, pas seulement au lock).
	if counter_label:
		counter_label.text = "%02d / %02d" % [_index + 1, _factions.size()]

# Construit le texte BBCode : lore + liste des modificateurs (miroir frontend du registre §4.3).
func _build_description(f) -> String:
	var txt: String = f.description
	if not f.modifiers.is_empty():
		txt += "\n\n[i]" + tr("FS_MODIFIERS_HEADER") + "[/i]"
		for key in f.modifiers:
			txt += "\n  • " + str(key) + " = " + str(f.modifiers[key])
	return txt

# Monte (une seule fois) le composant héros 3D dans PortraitWrap (parent du portrait), au même
# emplacement plein-cadre que le portrait 2D. Idempotent ; no-op si le portrait n'est pas câblé.
func _ensure_hero3d() -> void:
	if _hero3d != null:
		return
	if hero_portrait == null:
		return
	_hero3d = HeroViewport3DScene.instantiate()
	# PortraitWrap ne contient que le portrait + le placeholder → ajout sûr (aucun z-order volé).
	# La carte parente s'anime (modulate:a / position:x) : le composant, CanvasItem, fond/glisse avec.
	hero_portrait.get_parent().add_child(_hero3d)

# Portrait du héros : 3D D'ABORD si la faction expose un .glb valide (le modèle est échangé hors
# écran pendant le glissement de carte), sinon repli sur le portrait 2D, puis placeholder coloré.
func _set_portrait(f) -> void:
	var accent: Color = f.accent_color
	var model_path := ""
	if f.get("hero_model_path") != null:
		model_path = str(f.get("hero_model_path"))

	# --- Chemin 3D ---
	_ensure_hero3d()
	if _hero3d != null and _hero3d.set_model(model_path):
		_hero3d.set_accent(accent)
		_hero3d.visible = true
		hero_portrait.visible = false
		portrait_placeholder.visible = false
		return

	# --- Repli 2D ---
	if _hero3d != null:
		_hero3d.visible = false
	var tex = null
	if f.hero_path != "" and ResourceLoader.exists(f.hero_path):
		tex = load(f.hero_path)
	if tex != null:
		hero_portrait.texture = tex
		hero_portrait.visible = true
		portrait_placeholder.visible = false
	else:
		hero_portrait.texture = null
		hero_portrait.visible = false
		portrait_placeholder.visible = true
		portrait_placeholder.color = f.accent_color.darkened(0.25)

# =========================================================
# CONFIRMATION & SYNCHRONISATION RÉSEAU
# =========================================================

func _on_confirm_pressed() -> void:
	# Robustesse : pas de confirmation sans sélection valide.
	if _confirmed or _factions.is_empty():
		return
	var f = _factions[_index]
	_confirmed = true

	# Verrouillage de l'UI : on ne peut plus changer de faction.
	confirm_button.disabled = true
	prev_button.disabled = true
	next_button.disabled = true
	confirm_button.text = tr("FS_LOCKED")

	# Envoi du choix au serveur.
	NetworkManager.send_faction_choice(f.id)
	# Optimiste : on s'enregistre soi-même immédiatement (au cas où le serveur n'écho pas
	# notre propre choix dans le broadcast faction_locked).
	_register_lock(AuthManager.user_id, f.id)
	_update_status()

# Réception du choix d'un autre joueur (broadcast serveur).
func _on_faction_locked(player_id, faction_id) -> void:
	_register_lock(player_id, faction_id)
	_update_status()

# Enregistre un verrouillage et déclenche éventuellement le départ de la partie.
func _register_lock(player_id, faction_id) -> void:
	_locked[int(player_id)] = faction_id
	_maybe_start_game()

# Bascule vers l'arène quand TOUS les joueurs de la partie ont verrouillé leur faction.
func _maybe_start_game() -> void:
	var expected := _expected_players()
	if expected > 0 and _locked.size() >= expected:
		status_label.text = tr("FS_ALL_READY")
		TransitionManager.change_scene("res://scenes/game/main.tscn")

# Nombre de joueurs attendus : la composition de la partie est déjà connue (GameState peuplé
# par le message game_started reçu en salle d'attente).
func _expected_players() -> int:
	return GameState.players.size()

func _update_status() -> void:
	if _factions.is_empty():
		return
	var expected := _expected_players()
	var count_txt := str(_locked.size())
	if expected > 0:
		count_txt += " / " + str(expected)
	status_label.text = tr("FS_STATUS") % [_index + 1, _factions.size(), count_txt]
