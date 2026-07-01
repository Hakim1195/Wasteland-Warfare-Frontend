extends SubViewportContainer

# =========================================================================
# HERO VIEWPORT 3D — composant réutilisable (héros 3D sur fond transparent)
# =========================================================================
# Affiche un modèle .glb (héros de faction) dans un SubViewport 3D au fond
# TRANSPARENT, destiné à se composer SOUS l'UI « Glassmorphism » de la charte
# Warzone Command (§2). Remplace les TextureRect 2D de main_menu.tscn (héros
# central) et de split_screen_vs.tscn (portraits gauche/droite).
#
# VUE pure (Règle d'Or §6.1) : AUCUN accès réseau ni logique de jeu. L'hôte
# pousse un chemin de modèle + une couleur d'accent (résolus depuis les
# factions data-driven resources/factions/*.tres) via set_model() / set_accent().
# Aucun modèle valide → le plateau reste vide et éclairé ; l'hôte affiche alors
# son propre placeholder coloré (même convention que le code 2D actuel :
# main_menu.gd:_apply_hero / split_screen_vs.gd:_setup_side).
#
# Transparence : SubViewport.transparent_bg = true + Environment en
# BG_CLEAR_COLOR (JAMAIS BG_SKY, qui rendrait un fond opaque). L'alpha du
# viewport est nettoyé → la silhouette du héros se découpe au-dessus de l'UI.

# Accent cyan tactique de la charte (§2) — teinte par défaut du rim light, et
# repli si l'hôte ne pousse pas d'accent de faction.
const RIM_DEFAULT := Color(0.211765, 0.772549, 0.85098, 1)

@onready var _viewport: SubViewport = $SubViewport
@onready var _model_mount: Node3D = $SubViewport/HeroStage/ModelMount
@onready var _camera: Camera3D = $SubViewport/HeroStage/Camera3D
@onready var _key_light: DirectionalLight3D = $SubViewport/HeroStage/KeyLight
@onready var _fill_light: DirectionalLight3D = $SubViewport/HeroStage/FillLight
@onready var _rim_light: DirectionalLight3D = $SubViewport/HeroStage/RimLight

# Instance du modèle actuellement monté (libérée avant tout remplacement).
var _current_model: Node = null


func _ready() -> void:
	_orient_rig()
	# Veille par défaut (autorité runtime, immunisée contre la valeur sérialisée du .tscn) : tant
	# qu'aucun modèle n'est monté, le viewport ne se redessine pas. set_model l'activera.
	set_active(false)


# Oriente le trépied lumineux (key chaude / fill froide / rim cyan) et la caméra.
# La GÉOMÉTRIE est tenue par le code (rotation_degrees) plutôt que par des
# matrices Transform3D écrites à la main dans la scène : moins d'erreurs, et un
# seul endroit à ajuster une fois le vrai .glb cadré.
func _orient_rig() -> void:
	if _key_light:
		_key_light.rotation_degrees = Vector3(-32, 28, 0)   # haut avant-droit
	if _fill_light:
		_fill_light.rotation_degrees = Vector3(-10, -40, 0)  # déboucheur avant-gauche
	if _rim_light:
		_rim_light.rotation_degrees = Vector3(8, 200, 0)     # contre-jour (liseré cyan)
		_rim_light.light_color = RIM_DEFAULT


# ---------------------------------------------------------------------------
# API PUBLIQUE (appelée par l'hôte : main_menu.gd / split_screen_vs.gd)
# ---------------------------------------------------------------------------

# Monte un modèle .glb / PackedScene depuis `model_path`. Renvoie true si un
# modèle a bien été instancié. Chemin vide ou ressource absente → aucun modèle
# (l'hôte garde son placeholder). Joue une animation d'idle si le .glb en
# contient une (les modèles riggés Hunyuan3D exportent leur AnimationPlayer).
func set_model(model_path: String) -> bool:
	clear_model()
	if model_path == "" or not ResourceLoader.exists(model_path):
		return false
	var res = load(model_path)
	if not (res is PackedScene):
		return false
	var inst = (res as PackedScene).instantiate()
	if inst == null:
		return false
	_current_model = inst
	_model_mount.add_child(inst)
	_play_idle(inst)
	set_active(true)  # un modèle est monté → le viewport se redessine (idle, accents…)
	return true


# Détruit le modèle courant s'il y en a un (plateau vide). On DÉTACHE l'enfant du mount
# immédiatement (remove_child) avant le queue_free différé : ainsi deux set_model successifs
# dans la même frame (changement de faction) n'empilent jamais deux modèles vivants.
func clear_model() -> void:
	if _current_model != null and is_instance_valid(_current_model):
		if _current_model.get_parent() != null:
			_current_model.get_parent().remove_child(_current_model)
		_current_model.queue_free()
	_current_model = null
	set_active(false)  # plus de modèle → viewport en veille (UPDATE_DISABLED, aucun redraw)


# Teinte le rim light à l'accent de la faction → lie le héros 3D à la palette de
# sa faction (ex. orange Fusion #D35400 des Phalangistes), sinon cyan par défaut.
func set_accent(color: Color) -> void:
	if _rim_light:
		_rim_light.light_color = color


# Active/désactive le rendu du viewport. Piloté automatiquement par set_model/clear_model :
# un viewport SANS modèle (repli 2D, ou héros pas encore monté) reste en UPDATE_DISABLED et ne
# consomme RIEN — crucial sur split_screen_vs où deux instances coexistent. Exposé public pour
# permettre à l'hôte de figer aussi un héros monté mais hors-écran si besoin.
func set_active(active: bool) -> void:
	if _viewport:
		_viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
		)


# Cherche un AnimationPlayer dans le modèle importé et lance une idle (ou la 1re
# animation disponible), pour que le héros « respire » dès l'affichage.
func _play_idle(model: Node) -> void:
	var ap := _find_animation_player(model)
	if ap == null:
		return
	var names := ap.get_animation_list()
	if names.is_empty():
		return
	var pick: StringName = names[0]
	for n in names:
		if str(n).to_lower().contains("idle"):
			pick = n
			break
	# Forcer la boucle : les animations glTF s'importent SANS bouclage → l'idle ne
	# jouerait qu'une fois. On force LOOP_LINEAR sur le clip avant lecture (générique :
	# vaut pour tout perso dont le .glb contient un clip « idle »).
	var anim := ap.get_animation(pick)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR
	ap.play(pick)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
