extends Control

@export var status_label: Label

# Champs de Connexion
@export var login_email_input: LineEdit
@export var login_password_input: LineEdit
@export var login_button: Button

# Champs d'Inscription
@export var reg_username_input: LineEdit
@export var reg_email_input: LineEdit
@export var reg_password_input: LineEdit
@export var register_button: Button

# --- Couche Vue 2.5D (parallaxe / VFX "Modern Warfare") ---
# Calques de profondeur pilotés par la souris + bouton de sortie.
@export var background: TextureRect
@export var hero_graphic: TextureRect
@export var ash_particles: GPUParticles2D
@export var quit_button: Button

# Amplitude du décalage parallaxe en pixels. Le héros (avant-plan) glisse plus
# vite que le fond → illusion de profondeur de champ.
const BG_PARALLAX := 22.0
const HERO_PARALLAX := 48.0
# Vitesse de lissage du lerp (plus haut = plus réactif).
const PARALLAX_SMOOTH := 6.0
# Sur-cadrage (overscan) des calques : marge identique aux offsets d'ancrage
# de la scène (Background/HeroGraphic) pour que le décalage ne révèle jamais
# les bords. Doit rester synchronisé avec offset_left/top des nœuds (-60).
const OVERSCAN := 60.0

# Positions de repos des calques, recalculées analytiquement à chaque resize.
var _bg_rest := Vector2.ZERO
var _hero_rest := Vector2.ZERO

# Reconnexion automatique en cours (§P1) : vrai pendant la validation silencieuse d'une session
# sauvegardée. Distingue un échec d'auto-login (→ retour discret au login) d'un échec de saisie.
var _auto_login := false

# Helper UI partagé (charte §2) — utilisé ici pour le sélecteur de langue FR/EN/IT (R4).
const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")

func _ready():
	# Connexion des signaux UI
	if login_button: login_button.pressed.connect(_on_login_pressed)
	if register_button: register_button.pressed.connect(_on_register_pressed)
	if quit_button: quit_button.pressed.connect(_on_quit_pressed)

	# SFX d'interface (survol/clic — R6) + nappe d'ambiance des menus (idempotente, R6).
	WarzoneUI.wire_buttons_sfx([login_button, register_button, quit_button])
	AudioManager.start_menu_ambient()

	# Connexion des signaux du serveur
	AuthManager.auth_success.connect(_on_auth_success)
	AuthManager.auth_failed.connect(_on_auth_failed)

	# Mise en place de la couche 2.5D (repos des calques + dimensionnement des cendres).
	_setup_view_layer()
	get_viewport().size_changed.connect(_setup_view_layer)

	# Sélecteur de langue FR/EN/IT (R4) : disponible DÈS l'écran de connexion (avant tout login),
	# ancré en haut à droite et câblé sur LocaleManager (widget autonome, charte §2).
	var lang := WarzoneUI.build_language_selector()
	add_child(lang)
	lang.anchor_left = 1.0
	lang.anchor_right = 1.0
	lang.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	lang.offset_top = 22.0
	lang.offset_right = -28.0

	# Reconnexion automatique (§P1) : si une session est sauvegardée, on la valide en silence et on
	# saute directement au menu. Token expiré/invalide → purge discrète, l'écran de login reste.
	if AuthManager.has_saved_token():
		_try_auto_login()

	# Session expirée AILLEURS (§AC.5) : message laissé par le hub avant redirection. Affiché ici (le
	# token a déjà été purgé → pas d'auto-login concurrent), puis effacé pour ne pas le re-montrer.
	if AuthManager.session_notice != "":
		status_label.text = AuthManager.session_notice
		AuthManager.session_notice = ""

# Lance la validation silencieuse de la session sauvegardée.
func _try_auto_login() -> void:
	_auto_login = true
	status_label.text = tr("AUTH_LOGGING_IN")
	# /auth/me OK → profile_loaded ; KO (401/expiré) → auth_failed (géré dans _on_auth_failed).
	AuthManager.profile_loaded.connect(_on_auto_login_ok)
	AuthManager.try_restore_session()

# Session valide : l'opérateur entre directement au menu (pas de re-saisie d'identifiants).
func _on_auto_login_ok(_data: Dictionary) -> void:
	if not _auto_login:
		return
	_auto_login = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

# Recalcule les positions de repos (overscan) et étale l'émetteur de cendres
# sur tout l'écran. Appelé au démarrage puis à chaque changement de résolution.
func _setup_view_layer():
	var vp := get_viewport_rect().size
	_bg_rest = Vector2(-OVERSCAN, -OVERSCAN)
	_hero_rest = Vector2(vp.x * 0.5 - OVERSCAN, -OVERSCAN)
	if ash_particles:
		ash_particles.position = vp * 0.5
		var mat := ash_particles.process_material as ParticleProcessMaterial
		if mat:
			mat.emission_box_extents = Vector3(vp.x * 0.5 + 64.0, vp.y * 0.5 + 64.0, 1.0)
		ash_particles.restart()

func _process(delta):
	if background == null and hero_graphic == null:
		return
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	# Décalage normalisé de la souris par rapport au centre de l'écran : ~[-0.5, 0.5].
	var ratio := (get_viewport().get_mouse_position() / vp) - Vector2(0.5, 0.5)
	var weight := clampf(delta * PARALLAX_SMOOTH, 0.0, 1.0)
	# Les calques glissent à l'inverse de la souris → effet de profondeur réactif.
	if background:
		background.position = background.position.lerp(_bg_rest - ratio * BG_PARALLAX, weight)
	if hero_graphic:
		hero_graphic.position = hero_graphic.position.lerp(_hero_rest - ratio * HERO_PARALLAX, weight)

func _on_quit_pressed():
	get_tree().quit()

# ===========================================================================
# LOGIQUE RÉSEAU — couche API conservée intégralement (cf. AuthManager).
# Ne pas modifier : seuls la Vue et les signaux associés ont été refondus.
# ===========================================================================
func _on_login_pressed():
	if login_email_input.text.is_empty() or login_password_input.text.is_empty():
		status_label.text = tr("AUTH_FILL_FIELDS")
		return
	status_label.text = tr("AUTH_LOGGING_IN")
	AuthManager.login(login_email_input.text, login_password_input.text)

func _on_register_pressed():
	if reg_username_input.text.is_empty() or reg_email_input.text.is_empty() or reg_password_input.text.is_empty():
		status_label.text = tr("AUTH_FILL_FIELDS")
		return
	status_label.text = tr("AUTH_REGISTERING")
	AuthManager.register(reg_username_input.text, reg_email_input.text, reg_password_input.text)

func _on_auth_success(message: String):
	# Message renvoyé par le serveur (déjà localisé côté API) : affiché tel quel.
	status_label.text = message
	await get_tree().create_timer(1.0).timeout
	TransitionManager.change_scene("res://scenes/ui/main_menu.tscn")

func _on_auth_failed(message: String):
	# Échec d'une reconnexion auto (§P1) : token expiré/invalide → on purge en silence et on laisse
	# l'écran de login normal (pas de message d'erreur intrusif au simple démarrage).
	if _auto_login:
		_auto_login = false
		AuthManager.clear_session()
		status_label.text = ""
		return
	status_label.text = tr("AUTH_ERROR_PREFIX") % message
