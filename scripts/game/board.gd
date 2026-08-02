extends Node

# Vue du plateau (carte monde type Risk). Les 42 territoires sont placés MANUELLEMENT dans
# l'éditeur 2D ; ce script les RELIE aux données de MapData par le NOM du nœud (= id du
# territoire). AUCUNE logique de jeu ici (Règle d'Or §6.1) : c'est main.gd qui décide.
#
# Le développeur glisse le conteneur des 42 nœuds-territoires dans `territories_container`.
# Chaque nœud doit être nommé d'après un id de MapData.TERRITORIES (ex: "Alaska", "Brazil"…,
# la casse est ignorée). Cas nominal : des Area2D dessinés à la main → on câble leur signal
# `input_event` pour détecter le clic gauche. Fallback : un BaseButton (signal `pressed`).
# Dans les deux cas, un clic GAUCHE émet `territory_clicked(id)`.
signal territory_clicked(territory_id)
# Clic DROIT sur un territoire (Area2D uniquement) — utilisé par le tampon de déploiement
# (main.gd) pour RETIRER une troupe en attente (-1). Voir §8.26.
signal territory_right_clicked(territory_id)
# SURVOL d'un territoire (Area2D mouse_entered/mouse_exited) — consommé par la Prévision de
# combat (G4 §8.63) : en Phase 3, source sélectionnée + survol d'une cible ennemie adjacente →
# main.gd calcule et affiche les probabilités (CombatOdds). Vue pure : on ne fait qu'émettre.
signal territory_hovered(territory_id)
signal territory_unhovered(territory_id)
# Clic GAUCHE dans le VIDE (aucun territoire touché) — referme l'Inspecteur Tactique de Territoire
# (§1, charte Warzone Command). Émis par _unhandled_input avec une garde « même frame » contre le
# picking physique des Area2D (qui émet input_event AVANT _unhandled_input dans la même passe).
signal board_cleared

# Le développeur y glisse le nœud parent (Node2D) contenant ses 42 Area2D-territoires.
@export var territories_container: Node2D

# Palette par JOUEUR (jusqu'à 6) — SOURCE UNIQUE de la couleur plateau (§8.97).
#
# ⚠️ Elle n'est PLUS un repli : elle est la règle. Avant §8.97, la couleur venait de
# l'accent_color de la FACTION, ce qui rendait le plateau illisible — les 6 factions GRATUITES
# (celles que tirent les bots et la plupart des joueurs) tiennent dans 43° du cercle chromatique :
# phalanges #D35400 / pillards #D88528 / barons #A05229 / éveillés #D9A520 / écorcheurs #B32121
# sont CINQ variantes de rouge-orange. Pire : l'unicité de faction n'étant pas imposée aux humains
# (décision produit §7.1 ouverte), deux joueurs de MÊME faction avaient la MÊME couleur — aucune
# palette de faction ne peut donc garantir la distinction. La couleur appartient donc au SIÈGE.
#
# Critère de construction : 6 teintes réparties sur TOUT le cercle, écart minimum 44°, toutes
# lisibles sur le gunmetal #0F1318 et distinctes du gris NEUTRAL_COLOR #8A97A5 (territoire sans
# propriétaire). AUCUN orange (→ pas de paire rouge/orange) et AUCUN violet (→ pas de paire
# bleu/violet) : ce sont les deux confusions signalées. Ne PAS insérer une 7ᵉ teinte intermédiaire
# sans recalculer les écarts — c'est ce glissement qui a produit les 5 oranges d'origine.
#
# L'identité de faction n'est pas perdue : accent_color survit via get_faction_accent() (losange ◆
# de player_chip, carrousel de draft, écran Personnages) — elle quitte seulement le plateau.
const PALETTE := [
	Color("e8443c"),  # rouge alerte    (teinte   2°)
	Color("d9c22e"),  # jaune toxique   (teinte  53°)
	Color("3cc26e"),  # vert radio      (teinte 145°)
	Color("22b8ce"),  # cyan glacier    (teinte 188°)
	Color("5a6ee8"),  # bleu cobalt     (teinte 232°)
	Color("d45bbd"),  # magenta plasma  (teinte 310°)
]
# Palette DALTONIENNE (E10 §8.82) : Okabe-Ito, sûre pour deutan/protan/tritan. Quand le mode
# daltonien est actif, elle REMPLACE la palette de faction pour TOUS les joueurs — la bascule vit
# DANS get_player_color (source unique E1) → roster, VS, feed, badges suivent automatiquement.
const PALETTE_COLORBLIND := [
	Color("e69f00"),  # orange
	Color("56b4e9"),  # bleu ciel
	Color("009e73"),  # vert bleuté
	Color("f0e442"),  # jaune
	Color("cc79a7"),  # rose
	Color("0072b2"),  # bleu profond
]

# Palettes d'ÉQUIPE (MODE ÉQUIPES §8.124) — la palette par SIÈGE ci-dessus est parfaite pour du
# chacun-pour-soi et catastrophique en équipe : six teintes maximalement écartées ne disent RIEN de
# « qui est avec qui ». Le joueur doit lire son camp AU PREMIER COUP D'ŒIL, sans compter les chips.
#
# Construction, dans cet ordre de priorité :
#   1. **ÉCART INTER-ÉQUIPES ≥ 90°** — deux camps ne doivent jamais pouvoir être confondus. Les
#      teintes MÉDIANES sont à 20° (braise), 208° (glacier) et 118° (toxine) : écarts 172° / 98° / 90°.
#   2. **ÉCART INTRA-ÉQUIPE ~18°** — assez proche pour lire « même camp » d'un coup d'œil, assez
#      distinct pour désigner un coéquipier précis (« celui en orange »).
#   3. Mêmes contraintes de fond que la palette par siège : lisibles sur le gunmetal #0F1318 et
#      distinctes du gris NEUTRAL_COLOR #8A97A5.
#
# ⚠️ Ne PAS resserrer l'écart INTER-équipes pour « faire de plus jolies familles » : c'est la seule
# distinction qui porte une règle de jeu (on ne peut pas attaquer son camp — un joueur qui se
# trompe de camp clique et se fait refuser, sans comprendre pourquoi).
# La 3ᵉ famille sert au 2v2v2 (playlist DÉSACTIVÉE) : elle est prête, elle n'est pas utilisée.
const PALETTE_TEAMS := [
	[Color("e8443c"), Color("e8703c"), Color("e89c3c")],  # ÉQUIPE 1 — braise   (  2° →  38°)
	[Color("3cc0e8"), Color("3c94e8"), Color("3c68e8")],  # ÉQUIPE 2 — glacier  (190° → 226°)
	[Color("8ce83c"), Color("60e83c"), Color("3ce860")],  # ÉQUIPE 3 — toxine   (100° → 136°)
]

# Palettes d'ÉQUIPE en mode DALTONIEN (E10 §8.82 + §8.124). Le principe s'INVERSE par rapport au
# FFA : c'est le **MOTIF qui devient commun à l'équipe** (cf. `_player_palette_index`) et la NUANCE
# qui distingue les membres. Raison : en deutan/protan, deux teintes voisines d'une même famille
# sont précisément ce qui se confond le mieux — s'y fier pour lire son CAMP serait le pire choix.
# Le motif, lui, ne dépend d'aucune perception chromatique.
# Familles Okabe-Ito : chaudes (équipe 1), bleues (équipe 2), vert/rose (équipe 3).
const PALETTE_TEAMS_COLORBLIND := [
	[Color("e69f00"), Color("f0e442"), Color("d55e00")],  # ÉQUIPE 1 — chaudes
	[Color("0072b2"), Color("56b4e9"), Color("004c73")],  # ÉQUIPE 2 — bleues
	[Color("009e73"), Color("66c2a5"), Color("cc79a7")],  # ÉQUIPE 3 — vert / rose
]

# Visibilité Tactique (Partie 2) : badge de troupes + remplissage coloré des territoires.
const TerritoryBadgeScene := preload("res://scenes/game/territory_badge.tscn")
const FACTIONS_DIR := "res://resources/factions/"
# Opacité du remplissage du territoire (semi-transparent → on voit encore la carte de fond).
const FILL_ALPHA := 0.42
# Gris kaki pour un territoire neutre / sans propriétaire.
const NEUTRAL_COLOR := Color("8a97a5")

# Zone radioactive (§8.30) : shader de pulsation toxique appliqué en ShaderMaterial sur le
# remplissage d'un territoire contaminé, retiré dès qu'il sort de la zone.
const ToxicShader: Shader = preload("res://shaders/toxic_pulsation.gdshader")
const RAD_COLOR := Color("7fff00")    # vert nucléaire (miroir du défaut du shader)
const CONTAMINATED_ALPHA := 0.62      # opacité du remplissage contaminé (cf. fill_alpha shader)

# Hologramme Tactique (Concept A, Objectif 2) : contour néon + hachures diagonales défilantes
# appliqués sur les territoires POSSÉDÉS hors zone radioactive — on supprime ainsi le remplissage
# opaque uni qui rendait la carte illisible. Le shader écrase COLOR (cf. neon_hologram.gdshader) ;
# on lui passe l'accent du propriétaire ET les sommets du polygone (SDF du contour).
const HologramShader: Shader = preload("res://shaders/neon_hologram.gdshader")
const MAX_HOLO_POINTS := 64           # = MAX_POINTS du shader (au-delà, contour tronqué)
# Replis de remplissage STATIQUE (visibles seulement si un shader ne charge pas) : possédé = accent
# quasi transparent (plus de bloc uni), neutre = gris kaki très sombre (« vide »).
const HOLO_FALLBACK_ALPHA := 0.10
const NEUTRAL_FILL_COLOR := Color("0f1318")
const NEUTRAL_FILL_ALPHA := 0.22

# Mise en avant du JOUEUR LOCAL (perspective de CE client) : ses territoires doivent se distinguer
# d'un coup d'œil de ceux des adversaires. Deux leviers (couleur de faction CONSERVÉE, on ne joue
# que sur l'intensité) :
#   1) HOLOGRAMME renforcé — contour/halo/hachures plus marqués pour MOI, atténués pour les autres
#      (paramètres poussés au shader neon_hologram dans _apply_hologram_material) ;
#   2) RELIEF — une ombre portée (Polygon2D jumeau décalé, dessiné DERRIÈRE le remplissage) qui fait
#      « flotter » mes territoires au-dessus de la carte ; les territoires adverses restent à plat.
const OWN_FALLBACK_ALPHA := 0.18      # repli statique un peu plus dense pour MES territoires
# Décalage (px, espace local du board) + teinte de l'ombre portée des territoires possédés par MOI.
const OWN_RELIEF_OFFSET := Vector2(5, 8)
const OWN_RELIEF_COLOR := Color(0, 0, 0, 0.5)

var _selected_source: String = ""
var _owner_colors: Dictionary = {}
# Surlignage des cibles valides (E7 §8.79) : {tid: true} des cibles d'attaque légales, posé par
# main.gd à la sélection d'une source (Phase 3). Vide = aucun contexte d'attaque (rendu normal).
var _attack_targets: Dictionary = {}
# Flèche d'intention (E7) : Line2D pointillée animée source → territoire survolé (créée à la volée).
var _intent_arrow: Line2D = null
var _intent_target: String = ""
# id_territoire -> nœud visuel trouvé dans le conteneur.
var _nodes: Dictionary = {}
# faction_id (string) -> accent_color (Color), chargé une fois depuis resources/factions/*.tres.
var _faction_accents: Dictionary = {}
# id_territoire -> Polygon2D de remplissage (créé à la volée, enfant de l'Area2D).
var _fills: Dictionary = {}
# id_territoire -> Polygon2D d'ombre portée (relief) pour MES territoires (créé à la volée, dessiné
# DERRIÈRE le remplissage). Masqué dès que le territoire n'est plus à moi (cf. _apply/_clear_own_relief).
var _shadows: Dictionary = {}
# id_territoire -> instance de territory_badge.
var _badges: Dictionary = {}
# Calque (Node2D) accueillant les badges, dessiné par-dessus les territoires.
var _badge_layer: Node2D = null
# Déploiements EN ATTENTE (tampon local non confirmé piloté par main.gd, §8.26) : tid -> nb de
# troupes "+X". Affichés sur le badge/texte pour distinguer les troupes non encore validées.
var _pending: Dictionary = {}
# Frame du dernier clic ayant touché un territoire (picking Area2D) — garde anti-rebond pour
# distinguer un clic « dans le vide » (board_cleared) d'un clic sur un territoire (§1 Inspecteur).
var _pick_frame: int = -1

# --- Overlay « vraies frontieres » (§8.51) : colore/contoure les territoires d'apres la CARTE-ID
# (assets/images/territory_id_map.png, generee par tools/gen_territory_idmap.gd) AU LIEU des
# polygones-hitbox -> le rendu epouse les vraies cotes peintes. Voir territory_overlay.gdshader.
const ID_MAP_PATH := "res://assets/images/territory_id_map.png"
const ID_ORDER_PATH := "res://assets/images/territory_id_order.json"
const OverlayShader: Shader = preload("res://shaders/territory_overlay.gdshader")
const OVERLAY_CENTER := Vector2(1108, 757)   # centre du board_bg affiche en [8,2208]x[-8,1522]
var _overlay: Sprite2D = null
var _tid_index: Dictionary = {}              # tid -> index (1..N) dans la carte-ID

func _ready() -> void:
	# E1 §8.73 : le plateau s'enregistre pour les briques UI (player_chip) qui résolvent couleur
	# joueur / accent de faction via get_player_color / get_faction_accent — la palette reste
	# UNIQUE (piège n° 2 PLAN_EXPERIENCE : jamais de 2ᵉ table côté composants).
	add_to_group("game_board")
	_index_territory_nodes()
	_load_faction_accents()
	_setup_territory_overlay()
	# §8.122 (LOT E) : remise à zéro EXPLICITE de la tension. `tactical_map_material.tres` est une
	# ressource PARTAGÉE mise en cache par le ResourceLoader : sans ce reset, une partie quittée à
	# intensité 0,9 rouvrirait la suivante avec la vignette déjà en place, jusqu'au 1er état reçu.
	set_war_intensity(0.0)
	# §8.122 (LOT D) : carte vivante — orchestrateur des deux calques d'ambiance (cendres, fumées,
	# feux de camp, éclairs, oiseaux). Monté ici pour qu'il existe AVANT le premier generate_board.
	_setup_ambient_layer()
	# Mode daltonien (E10 §8.82) : au changement, on purge la table de couleurs (recalculée avec
	# la palette Okabe-Ito) et on redessine — toute l'UI suit via get_player_color.
	if not SettingsManager.comfort_changed.is_connected(_on_comfort_changed):
		SettingsManager.comfort_changed.connect(_on_comfort_changed)

func _on_comfort_changed(key: String, _value) -> void:
	# colorblind → palette + motifs ; reduced_motion → motion_scale du shader. Les deux exigent
	# un redraw (couleurs/motifs recalculés, uniformes repoussés).
	if key == "colorblind_mode" or key == "reduced_motion":
		_owner_colors.clear()
		generate_board()

# Construit l'overlay des territoires (§8.51) : un Sprite2D portant la CARTE-ID, recouvrant
# EXACTEMENT le board_bg, avec territory_overlay.gdshader. Texture chargee BRUTE (index exacts,
# filtre NEAREST) ; l'ordre des index vient du JSON jumeau. Ajoute au-dessus du fond et SOUS les
# badges (crees plus tard). Sans la carte-ID/JSON, l'overlay reste absent (repli : aucun coloriage).
func _setup_territory_overlay() -> void:
	var f := FileAccess.open(ID_ORDER_PATH, FileAccess.READ)
	if f == null:
		push_warning("board.gd : territory_id_order.json absent — overlay desactive.")
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY or not data.has("order"):
		return
	var order: Array = data["order"]
	for i in range(order.size()):
		_tid_index[str(order[i])] = i + 1
	var tex := load(ID_MAP_PATH) as Texture2D
	if tex == null:
		push_warning("board.gd : territory_id_map.png absent — overlay desactive.")
		return
	var idtex := ImageTexture.create_from_image(tex.get_image())
	_overlay = Sprite2D.new()
	_overlay.name = "TerritoryOverlay"
	_overlay.texture = idtex
	_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_overlay.position = OVERLAY_CENTER
	var mat := ShaderMaterial.new()
	mat.shader = OverlayShader
	mat.set_shader_parameter("id_map", idtex)
	_overlay.material = mat
	add_child(_overlay)

# =========================================================
# CARTE VIVANTE (§8.122, LOT D) — montage de l'orchestrateur d'ambiance
# =========================================================
const AmbientLayerScript := preload("res://scripts/game/ambient_layer.gd")
var _ambient: Node = null

# Les deux CALQUES sont déclarés dans board.tscn (ordre de rendu documenté là-bas) ; l'orchestrateur
# est un Node NEUTRE monté ici. Si l'un des calques manque (scène ancienne / .tscn corrompu), on
# n'installe rien : le plateau se rend exactement comme avant (repli silencieux).
func _setup_ambient_layer() -> void:
	var back := get_node_or_null("AmbientBack") as Node2D
	var front := get_node_or_null("AmbientFront") as Node2D
	if back == null or front == null:
		return
	_ambient = Node.new()
	_ambient.name = "AmbientLayer"
	_ambient.set_script(AmbientLayerScript)
	add_child(_ambient)
	_ambient.setup(back, front, self, _background_rect())

# Rect du fond de carte, en coordonnées locales du plateau (les cendres doivent le couvrir, et la
# nuée d'oiseaux le traverser de bord à bord). Repli : rect vide → cendres centrées sur l'origine.
func _background_rect() -> Rect2:
	var bg := get_node_or_null("BoardBackground")
	if bg is Control:
		return Rect2((bg as Control).position, (bg as Control).size)
	return Rect2()

# Verrou d'animation de combat (poussé par main.gd) : relayé tel quel à la carte vivante, qui s'en
# sert pour ne PAS lancer d'oiseaux par-dessus un duel.
func set_ambient_busy(v: bool) -> void:
	if _ambient != null and is_instance_valid(_ambient):
		_ambient.set_busy(v)


# =========================================================
# CYCLE DE TENSION VISUEL (§8.122, LOT E)
# =========================================================
# `war_intensity` arrive DÉJÀ LISSÉE de main.gd (source unique §8.122 LOT A) : le plateau ne fait
# que la relayer au shader du fond de carte. Aucun `_process` ici — c'est main.gd qui cadence.
var _war_intensity := 0.0
var _board_bg: CanvasItem = null

func set_war_intensity(v: float) -> void:
	_war_intensity = clampf(v, 0.0, 1.0)
	_push_war_intensity()

# Pousse l'uniforme sur le ShaderMaterial de `BoardBackground` (tactical_map.gdshader). Silencieux
# si le nœud ou le matériau manque : la carte s'affiche alors sans cycle de tension, jamais d'erreur.
func _push_war_intensity() -> void:
	if _board_bg == null or not is_instance_valid(_board_bg):
		_board_bg = get_node_or_null("BoardBackground")
	if _board_bg == null or not (_board_bg.material is ShaderMaterial):
		return
	(_board_bg.material as ShaderMaterial).set_shader_parameter("war_intensity", _war_intensity)


# Charge la couleur d'accent de chaque faction depuis ses ressources data-driven (.tres).
# Même pattern robuste que faction_selection.gd : scan du dossier, export-safe (.remap),
# duck-typing (on n'exige pas le type global FactionData). 7/10 factions n'ont pas encore de
# .tres → ces joueurs retombent sur la PALETTE par index (voir _build_owner_colors).
func _load_faction_accents() -> void:
	_faction_accents.clear()
	var dir := DirAccess.open(FACTIONS_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var fn := file_name
			if fn.ends_with(".remap"):
				fn = fn.trim_suffix(".remap")
			if fn.ends_with(".tres"):
				var full := FACTIONS_DIR + fn
				if ResourceLoader.exists(full):
					var res = load(full)
					if res != null and res.get("id") != null:
						var accent = res.get("accent_color")
						if accent is Color:
							_faction_accents[str(res.get("id"))] = accent
		file_name = dir.get_next()
	dir.list_dir_end()

# Parcourt les enfants du conteneur, valide le nom contre MapData et câble les clics.
func _index_territory_nodes() -> void:
	_nodes.clear()
	if territories_container == null:
		push_warning("board.gd : 'territories_container' non assigné — placez vos 42 territoires dans l'éditeur et glissez le conteneur.")
		return
	for territory_node in territories_container.get_children():
		var t_id := String(territory_node.name).to_lower()
		if not MapData.TERRITORIES.has(t_id):
			push_warning("board.gd : nœud '%s' sans correspondance dans MapData.TERRITORIES (ignoré)." % territory_node.name)
			continue
		_nodes[t_id] = territory_node
		_wire_click(territory_node, t_id)

# Câble le clic d'un nœud-territoire vers `territory_clicked`, selon son type.
# Area2D (cas nominal) : signal `input_event` — on filtrera le clic gauche dans le handler.
# BaseButton (fallback) : signal `pressed`, déjà filtré par le moteur.
func _wire_click(node: Node, t_id: String) -> void:
	if node.has_signal("input_event"):
		_warn_if_area_not_clickable(node)
		var cb := _on_area_input_event.bind(t_id)
		if not node.input_event.is_connected(cb):
			node.input_event.connect(cb)
		# Survol (G4 §8.63) : relaie l'entrée/sortie de souris (prévision de combat).
		var cb_in := _on_area_mouse_entered.bind(t_id)
		if not node.mouse_entered.is_connected(cb_in):
			node.mouse_entered.connect(cb_in)
		var cb_out := _on_area_mouse_exited.bind(t_id)
		if not node.mouse_exited.is_connected(cb_out):
			node.mouse_exited.connect(cb_out)
	elif node.has_signal("pressed"):
		var cb_btn := _on_pressed.bind(t_id)
		if not node.pressed.is_connected(cb_btn):
			node.pressed.connect(cb_btn)
	else:
		push_warning("board.gd : nœud '%s' ni Area2D ni BaseButton — clic non câblé." % node.name)

# Diagnostic (level design manuel) : un Area2D ne reçoit `input_event` QUE s'il est
# `input_pickable` ET possède au moins une forme de collision. Oublier l'un ou l'autre rend le
# territoire silencieusement non cliquable (aucune erreur) — on prévient plutôt que de laisser
# deviner. N'altère rien : se contente de logguer un avertissement en build debug.
func _warn_if_area_not_clickable(node: Node) -> void:
	if "input_pickable" in node and not node.input_pickable:
		push_warning("board.gd : Area2D '%s' a input_pickable=false → clics ignorés." % node.name)
	for child in node.get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			return
	push_warning("board.gd : Area2D '%s' sans CollisionShape2D/CollisionPolygon2D → clics ignorés." % node.name)

func set_selected_source(tid: String) -> void:
	_selected_source = tid
	generate_board()

# Contexte d'attaque (E7 §8.79) : main.gd calcule les cibles légales à la sélection d'une source
# (Phase 3) → liseré cramoisi pulsant sur les cibles + désaturation des autres (via l'overlay).
func set_attack_context(source_tid: String, valid_targets: Array) -> void:
	_attack_targets = {}
	for tid in valid_targets:
		_attack_targets[str(tid)] = true
	generate_board()

# Contexte de CIBLAGE D'UNE CAPACITÉ (§8.119 — BASTION / ABSOLUTION). Réutilise TEL QUEL le
# pipeline de surlignage des cibles d'attaque (`_attack_targets` → liseré pulsant de l'overlay) :
# une seule mécanique de « cibles légales » dans le plateau, donc aucun risque de divergence
# visuelle entre un ciblage d'attaque et un ciblage de pouvoir. Sans source sélectionnée : on ne
# veut ni flèche d'intention ni territoire éclairci (le pouvoir ne part d'aucun territoire).
func set_ability_targets(valid_targets: Array) -> void:
	set_attack_context("", valid_targets)

# =========================================================
# SURLIGNAGE DU COACH (§8.129 — complété aux finitions pré-playtest)
# =========================================================
# L'étape ATTAQUER du briefing ne désignait AUCUN territoire : le plateau vit dans un `SubViewport`
# à caméra, et le coach surligne des `Control` d'écran (rect relu en coordonnées d'interface). La
# conversion monde→écran aurait demandé de suivre le zoom, le travelling et le recadrage de la
# caméra tactique à chaque frame — beaucoup de code, et un rectangle qui dérive dès qu'on bouge.
#
# Le plateau, lui, SAIT DÉJÀ se surligner : le télégraphe de zone (G1 §8.62) allume un liseré or
# pulsant sur un territoire depuis l'overlay, en coordonnées de CARTE. On emprunte donc ce canal
# plutôt que d'en inventer un — zéro shader neuf, zéro calcul d'écran, et le surlignage suit la
# caméra gratuitement puisqu'il est dessiné DANS le plateau.
#
# `reduced_motion` est déjà géré en aval par `motion_scale` (poussé plus bas) : le liseré devient
# FIXE au lieu de pulser, sans une ligne de plus ici.
var _tutorial_tid: String = ""

func tutorial_highlight(tid: String) -> void:
	if _tutorial_tid == str(tid):
		return
	_tutorial_tid = str(tid)
	generate_board()

func tutorial_highlight_clear() -> void:
	if _tutorial_tid == "":
		return   # no-op silencieux : appelable depuis les 4 chemins de nettoyage sans garde côté appelant
	_tutorial_tid = ""
	generate_board()

func clear_attack_context() -> void:
	if _attack_targets.is_empty() and _intent_target == "":
		return
	_attack_targets = {}
	clear_intent_arrow()
	generate_board()

# Flèche d'intention pointillée (E7) : source → territoire survolé. Recréée si la cible change.
func set_intent_arrow(target_tid: String) -> void:
	if _selected_source == "" or target_tid == _selected_source:
		clear_intent_arrow()
		return
	var from := get_territory_position(_selected_source)
	var to := get_territory_position(target_tid)
	if from == Vector2.INF or to == Vector2.INF:
		clear_intent_arrow()
		return
	_intent_target = target_tid
	if _intent_arrow == null or not is_instance_valid(_intent_arrow):
		_intent_arrow = Line2D.new()
		_intent_arrow.width = 5.0
		_intent_arrow.default_color = Color(0.85, 0.15, 0.15, 0.85)
		_intent_arrow.z_index = 50
		_intent_arrow.begin_cap_mode = Line2D.LINE_CAP_ROUND
		_intent_arrow.end_cap_mode = Line2D.LINE_CAP_ROUND
		add_child(_intent_arrow)
	_intent_arrow.visible = true
	# Trait principal + tête de flèche (deux segments obliques) — pointillé simulé par segments.
	var dir := (to - from).normalized()
	var head := to - dir * 46.0
	var perp := dir.orthogonal()
	_intent_arrow.points = PackedVector2Array([from, head])
	if _intent_head == null or not is_instance_valid(_intent_head):
		_intent_head = Line2D.new()
		_intent_head.width = 5.0
		_intent_head.default_color = Color(0.85, 0.15, 0.15, 0.95)
		_intent_head.z_index = 50
		add_child(_intent_head)
	_intent_head.visible = true
	_intent_head.points = PackedVector2Array([
		head + perp * 22.0 - dir * 4.0, to, head - perp * 22.0 - dir * 4.0])

var _intent_head: Line2D = null

func clear_intent_arrow() -> void:
	_intent_target = ""
	if _intent_arrow != null and is_instance_valid(_intent_arrow):
		_intent_arrow.visible = false
	if _intent_head != null and is_instance_valid(_intent_head):
		_intent_head.visible = false

# Couleur d'un joueur telle qu'utilisée sur le plateau : PALETTE par index de siège (§8.97), gris
# NEUTRAL_COLOR si le joueur est inconnu. Exposé pour que le HUD colore le pseudo du joueur de façon
# COHÉRENTE avec ses territoires (CONTEXTE.md §8.23). Reconstruit la table si elle n'a pas encore
# été bâtie. SOURCE UNIQUE (E1) : roster, VS, kill feed, badges et pastilles en découlent tous.
func get_player_color(pid: int) -> Color:
	if _owner_colors.is_empty():
		_build_owner_colors()
	return _owner_colors.get(pid, NEUTRAL_COLOR)

# Accent d'une faction (accent_color de son .tres) — NEUTRAL_COLOR si inconnue / sans ressource.
# Exposé pour la brique identité player_chip (E1 §8.73) : la table des accents chargée ici reste
# la SEULE source (aucun doublon de scan côté UI).
func get_faction_accent(faction_id: String) -> Color:
	return _faction_accents.get(faction_id, NEUTRAL_COLOR)

# Id du joueur LOCAL (la perspective de CE client) — ses territoires sont mis en avant (hologramme
# vif + relief) pour les distinguer des adversaires. Même source que main._my_id() / le HUD :
# AuthManager.user_id. board reste une Vue, il ne fait que REFLÉTER cette perspective (pas de logique
# de jeu). Vaut -1 tant que l'id n'est pas chargé → aucun territoire « à moi » (repli sûr).
func _local_pid() -> int:
	return AuthManager.user_id

# Ensemble des territoires contaminés (modèle CLUSTER §8.27 : clé "territories" = liste). Renvoie
# un Dictionary {tid: true} pour un test d'appartenance O(1) dans generate_board. Rétro-compatible
# avec l'ancien modèle « position unique ».
func _contaminated_set() -> Dictionary:
	var out: Dictionary = {}
	var zone = GameState.contamination_zone
	if typeof(zone) != TYPE_DICTIONARY:
		return out
	if zone.has("territories") and typeof(zone["territories"]) == TYPE_ARRAY:
		for tid in zone["territories"]:
			out[str(tid)] = true
	elif zone.has("position"):  # rétro-compatibilité ancien modèle
		out[str(zone["position"])] = true
	return out

# TÉLÉGRAPHE (G1 §8.62) : ensemble {tid: true} des territoires ANNONCÉS pour la PROCHAINE zone
# (contamination_zone.next_territories, pré-tiré par le serveur un round à l'avance). Même contrat
# que _contaminated_set ; clé absente (serveur antérieur / état legacy) → ensemble vide, aucun crash.
func _forecast_set() -> Dictionary:
	var out: Dictionary = {}
	var zone = GameState.contamination_zone
	if typeof(zone) != TYPE_DICTIONARY:
		return out
	if zone.has("next_territories") and typeof(zone["next_territories"]) == TYPE_ARRAY:
		for tid in zone["next_territories"]:
			out[str(tid)] = true
	return out

# Pousse le tampon de déploiement local (main.gd, §8.26) sur le plateau et redessine. Un dict
# vide efface tous les "+X". Appelé pendant les phases de placement / renforts.
func set_pending_deployments(pending: Dictionary) -> void:
	_pending = pending.duplicate() if pending != null else {}
	generate_board()

# Construit la table propriétaire -> couleur. La couleur est celle du SIÈGE : PALETTE par INDEX,
# sur l'ordre stable des ids (§8.97) → deux joueurs n'ont JAMAIS la même couleur, même s'ils ont
# choisi la même faction (les doublons humains restent permis, décision produit §7.1).
# L'accent_color de la faction n'intervient PLUS ici (cf. le pourquoi en tête de PALETTE) ; il
# reste exposé par get_faction_accent pour l'identité de faction hors plateau.
# Mode DALTONIEN (E10 §8.82) : la palette Okabe-Ito remplace la PALETTE, même mécanique par index ;
# les motifs (shader) renforcent la couleur.
func _build_owner_colors() -> void:
	var pids: Array = []
	for k in GameState.players.keys():
		pids.append(int(k))
	pids.sort()
	_owner_colors.clear()
	var colorblind: bool = bool(SettingsManager.get_comfort("colorblind_mode"))
	# MODE ÉQUIPES (§8.124) : les couleurs s'APPARIENT par camp (cf. PALETTE_TEAMS). Aiguillage en
	# tête, branche séparée — la table par SIÈGE ci-dessous reste intouchée pour le FFA.
	if GameState.team_mode != "":
		_build_team_colors(pids, colorblind)
		return
	for i in range(pids.size()):
		var pid: int = pids[i]
		var palette: Array = PALETTE_COLORBLIND if colorblind else PALETTE
		_owner_colors[pid] = palette[i % palette.size()]


# Couleurs APPARIÉES par équipe : famille de teintes selon le camp, nuance selon le RANG DU MEMBRE
# dans son équipe (ordre stable des ids). Deux joueurs de la même équipe portent donc deux nuances
# voisines d'une même teinte ; deux équipes sont à ≥ 90° l'une de l'autre.
# Joueur SANS équipe dans une partie d'équipe (état incohérent / bot mal affecté) → gris neutre
# plutôt qu'une couleur d'équipe mensongère : mieux vaut « je ne sais pas » que « il est avec toi ».
func _build_team_colors(pids: Array, colorblind: bool) -> void:
	var palettes: Array = PALETTE_TEAMS_COLORBLIND if colorblind else PALETTE_TEAMS
	var teams := GameState.teams_map()
	var team_ids := teams.keys()
	team_ids.sort()
	for pid in pids:
		var t := GameState.team_of(pid)
		var ti := team_ids.find(t)
		if t == 0 or ti < 0:
			_owner_colors[pid] = NEUTRAL_COLOR
			continue
		var members: Array = teams[t]
		var mi: int = max(0, members.find(int(pid)))
		var family: Array = palettes[ti % palettes.size()]
		_owner_colors[pid] = family[mi % family.size()]


# Index de MOTIF daltonien d'un joueur (E10 §8.82) — le shader en dérive `territory_pattern`.
#
# ⚠️ DEUX SÉMANTIQUES, selon le mode :
#   • **FFA** : index de SIÈGE (0..5, ordre stable des ids) → un motif PAR JOUEUR. C'est ce qui
#     distingue six adversaires quand la couleur ne suffit pas.
#   • **ÉQUIPE (§8.124)** : index d'ÉQUIPE → un motif PAR CAMP, COMMUN à ses membres. En mode
#     daltonien, le motif devient donc le porteur de « qui est avec qui » (la nuance, elle, ne
#     distingue plus que les individus) — cf. PALETTE_TEAMS_COLORBLIND. C'est l'inversion voulue :
#     l'information la plus importante est confiée au canal le plus fiable.
func _player_palette_index(pid: int) -> int:
	if GameState.team_mode != "":
		var team_ids := GameState.teams_map().keys()
		team_ids.sort()
		var ti := team_ids.find(GameState.team_of(pid))
		return ti if ti >= 0 else 0
	var pids: Array = []
	for k in GameState.players.keys():
		pids.append(int(k))
	pids.sort()
	var idx := pids.find(pid)
	return idx if idx >= 0 else 0

# Rafraîchit l'apparence de chaque nœud-territoire à partir de l'état courant (GameState) :
# remplissage semi-transparent à la couleur de faction du propriétaire (gris si neutre),
# badge de troupes au centre, surbrillance = sélection, ☢ = contamination.
func generate_board() -> void:
	_build_owner_colors()
	var contaminated := _contaminated_set()
	var forecast := _forecast_set()
	# CARTE VIVANTE (§8.122, LOT D) : « capitale » de chaque joueur = son territoire à la plus
	# grosse garnison. Accumulée DANS la boucle ci-dessous (elle parcourt déjà tout le plateau) :
	# une 2ᵉ passe sur les 42 territoires pour ça seul serait du gaspillage.
	var capital_by_owner: Dictionary = {}
	# Carte réduite (G5 §8.71) : territoires de LA CARTE JOUÉE — les nœuds hors carte sont
	# masqués/désactivés plus bas ; le rect englobant des actifs recadre la caméra tactique.
	var map_terrs: Dictionary = MapData.map_territories(GameState.map_id)
	var partial_map: bool = map_terrs.size() < _nodes.size()
	var active_rect := Rect2()
	var have_rect := false

	# Tableaux pousses a l'overlay (§8.51), indexes par la carte-ID : couleur+alpha de remplissage
	# et alpha de contour. Initialises transparents -> les territoires neutres restent invisibles.
	var ov_colors := PackedColorArray()
	ov_colors.resize(42)
	for i in range(42):
		ov_colors[i] = Color(0, 0, 0, 0)
	var ov_edges := PackedFloat32Array()
	ov_edges.resize(42)
	# 1 = territoire du JOUEUR LOCAL -> porte une ombre de relief (§8.52, via l'overlay).
	var ov_mine := PackedFloat32Array()
	ov_mine.resize(42)
	# 1 = territoire ANNONCÉ pour la prochaine zone -> liseré or pulsant (télégraphe G1 §8.62).
	var ov_forecast := PackedFloat32Array()
	ov_forecast.resize(42)
	# 1 = cible d'attaque valide -> liseré cramoisi pulsant (E7 §8.79).
	var ov_attack := PackedFloat32Array()
	ov_attack.resize(42)
	# Motif daltonien par index de joueur (E10 §8.82) : 0 = aucun (mode normal), 1..6 sinon.
	var ov_pattern := PackedFloat32Array()
	ov_pattern.resize(42)
	var colorblind: bool = bool(SettingsManager.get_comfort("colorblind_mode"))

	for tid in _nodes:
		var node = _nodes[tid]
		# Hors carte (G5) : nœud invisible + non cliquable + badge masqué, rien d'autre à faire
		# (l'overlay reste transparent : le territoire n'existe pas dans GameState.territories).
		var in_map: bool = map_terrs.has(tid)
		if "visible" in node:
			node.visible = in_map
		if "input_pickable" in node:
			node.input_pickable = in_map
		if not in_map:
			var stale = _badges.get(tid)
			if stale != null and is_instance_valid(stale):
				stale.visible = false
			continue
		# Rect englobant des territoires ACTIFS (recadrage caméra, seulement en carte partielle).
		if partial_map:
			var node_rect := _node_world_rect(node)
			if node_rect.size != Vector2.ZERO:
				active_rect = node_rect if not have_rect else active_rect.merge(node_rect)
				have_rect = true
		var t: Dictionary = GameState.territories.get(tid, {})
		var territory_owner = t.get("owner_id")
		var garrison := int(t.get("garrison", 0))
		# Troupes en attente de confirmation sur ce territoire (tampon local, §8.26).
		var pending := int(_pending.get(tid, 0))

		# Couleur d'accent du propriétaire (gris kaki si le territoire est neutre / vide).
		var accent: Color = NEUTRAL_COLOR
		if territory_owner != null and _owner_colors.has(int(territory_owner)):
			accent = _owner_colors[int(territory_owner)]

		# Territoire du JOUEUR LOCAL ? Ses possessions sont mises en avant (hologramme renforcé +
		# relief) pour se distinguer d'un coup d'œil de celles des adversaires (atténuées, à plat).
		var is_mine: bool = territory_owner != null and int(territory_owner) == _local_pid()

		# Couleur de remplissage du polygone (avec surbrillance de sélection et teinte de zone).
		# Type explicite : `tid` (clé de Dictionary) est un Variant → l'inférence `:=` échoue.
		var is_contaminated: bool = contaminated.has(tid)
		# Territoire annoncé pour la PROCHAINE zone (télégraphe G1 §8.62 — liseré or + badge ⚠).
		var is_forecast: bool = forecast.has(tid)
		var fill_col: Color
		var fill_alpha: float
		if territory_owner != null:
			fill_col = accent
			if tid == _selected_source:
				fill_col = fill_col.lightened(0.35)
			fill_alpha = OWN_FALLBACK_ALPHA if is_mine else HOLO_FALLBACK_ALPHA
			# Capitale du propriétaire (§8.122, LOT D) : plus grosse garnison ; à ÉGALITÉ, le tid
			# le plus petit alphabétiquement gagne → le feu de camp ne saute pas d'un territoire à
			# l'autre à chaque refresh quand deux garnisons se valent (ordre STABLE exigé).
			var opid := int(territory_owner)
			var best = capital_by_owner.get(opid)
			if best == null or garrison > int(best["g"]) \
					or (garrison == int(best["g"]) and str(tid) < str(best["tid"])):
				capital_by_owner[opid] = {"tid": str(tid), "g": garrison}
		else:
			# Territoire NEUTRE : pas d'hologramme → gris kaki très sombre (« vide »).
			fill_col = NEUTRAL_FILL_COLOR
			fill_alpha = NEUTRAL_FILL_ALPHA
		if is_contaminated:
			# Zone radioactive : superposition vert fluo nettement plus marquée ET plus opaque
			# que le remplissage normal → le territoire contaminé saute aux yeux (bug playtest).
			fill_col = fill_col.lerp(Color("7fff00"), 0.7)
			fill_alpha = 0.62

		# Overlay « vraies frontieres » (§8.51) : on POUSSE la couleur+alpha de remplissage calcules
		# ci-dessus dans la carte-ID (territory_overlay.gdshader), plus un alpha de CONTOUR neon (mes
		# territoires vifs, adverses attenues, contamines marques). Remplace les fills/hologramme/relief
		# qui suivaient le POLYGONE -> desormais le rendu epouse les VRAIES cotes peintes.
		var edge_a := 0.0
		if is_contaminated:
			edge_a = 0.9
		elif territory_owner != null:
			edge_a = 0.95 if is_mine else 0.55
			if tid == _selected_source:
				edge_a = 1.0
		if _tid_index.has(tid):
			var oi: int = int(_tid_index[tid]) - 1
			if oi >= 0 and oi < ov_colors.size():
				ov_colors[oi] = Color(fill_col.r, fill_col.g, fill_col.b, fill_alpha)
				ov_edges[oi] = edge_a
				ov_mine[oi] = 1.0 if is_mine else 0.0
				# Le surlignage du COACH emprunte le canal du télégraphe (liseré or pulsant) : même
				# uniforme de shader, aucun canal neuf. Les deux ne se contredisent jamais — ils
				# demandent le même geste (« regarde CE territoire »), et si le coach désigne par
				# hasard un territoire déjà annoncé, le liseré est simplement déjà allumé.
				ov_forecast[oi] = 1.0 if (is_forecast or tid == _tutorial_tid) else 0.0
				ov_attack[oi] = 1.0 if _attack_targets.has(tid) else 0.0
				# Motif daltonien (E10) : index de joueur +1 (1..6) sur les territoires possédés.
				if colorblind and territory_owner != null:
					ov_pattern[oi] = float(_player_palette_index(int(territory_owner)) % 6 + 1)

		# Badge de troupes : bordure à l'accent du propriétaire, nombre d'unités au centre,
		# alerte ☢ si contaminé, "+X" doré pour les troupes en attente, ⚠ or si le territoire
		# est annoncé pour la prochaine zone (télégraphe G1 §8.62). Mode daltonien (E10) :
		# initiale du pseudo du propriétaire en redondance texte.
		var initial := ""
		if colorblind and territory_owner != null:
			initial = _owner_initial(int(territory_owner))
		# Bouclier (§8.119 — BASTION D'ACIER) : liseré cyan + écusson sur le badge tant que le
		# compteur SERVEUR est armé. L'état fait foi, jamais une mémoire locale : à l'expiration
		# du compteur, le marquage disparaît au rafraîchissement suivant.
		var is_shielded: bool = int(t.get("shield_turns_left", 0)) > 0
		_update_badge(tid, garrison, accent, is_contaminated, pending, is_forecast, initial,
			is_shielded)

		# Libellé/garnison : on n'écrase un texte que si le nœud expose la propriété `text`
		# (cas fallback BaseButton ; les Area2D dessinés à la main n'ont pas de `text`).
		if "text" in node:
			var prefix := ""
			if tid == _selected_source:
				prefix = "▶ "
			if is_contaminated:
				prefix = "☢ " + prefix
			var troop_str := str(garrison)
			if pending > 0:
				troop_str = "%d+%d" % [garrison, pending]
			node.text = "%s%s\n%s" % [prefix, MapData.TERRITORIES[tid]["name"], troop_str]

	# Pousse couleurs + contours a l'overlay (un seul set par rafraichissement).
	if _overlay != null and _overlay.material is ShaderMaterial:
		var m := _overlay.material as ShaderMaterial
		m.set_shader_parameter("territory_colors", ov_colors)
		m.set_shader_parameter("territory_edge", ov_edges)
		m.set_shader_parameter("territory_mine", ov_mine)
		m.set_shader_parameter("territory_forecast", ov_forecast)
		m.set_shader_parameter("territory_attack", ov_attack)
		# attack_dim > 0 dès qu'une source a des cibles surlignées → désaturation des autres (E7).
		m.set_shader_parameter("attack_dim", 1.0 if not _attack_targets.is_empty() else 0.0)
		m.set_shader_parameter("territory_pattern", ov_pattern)  # motifs daltoniens (E10)
		# reduced_motion (E10) : fige les pulsations du plateau (télégraphe/attaque).
		m.set_shader_parameter("motion_scale",
			0.0 if bool(SettingsManager.get_comfort("reduced_motion")) else 1.0)

	# Cycle de tension (§8.122, LOT E) : l'uniforme vit sur un matériau PARTAGÉ (.tres) donc il
	# survit d'un refresh à l'autre — on le repousse quand même ici pour que le rendu ne puisse pas
	# diverger de la valeur courante si le matériau était rechargé.
	_push_war_intensity()

	# CARTE VIVANTE (§8.122, LOT D) : appel UNIQUE par refresh — capitales triées par id de joueur
	# (même ordre que la palette de sièges → un joueur garde SON émetteur de braises) et zone
	# courante pour les éclairs.
	if _ambient != null and is_instance_valid(_ambient):
		var owner_ids: Array = capital_by_owner.keys()
		owner_ids.sort()
		var capitals: Array = []
		for opid in owner_ids:
			capitals.append({"tid": str(capital_by_owner[opid]["tid"]),
				"color": get_player_color(int(opid))})
		_ambient.refresh({
			"round": int(GameState.current_turn),
			"contaminated": contaminated.keys(),
			"capitals": capitals,
		})

	# Cadre actif (G5) : mémorisé pour la caméra — Rect2() vide sur la carte COMPLÈTE (le
	# cadrage historique plein plateau est alors conservé, non-régression classic).
	_active_rect = active_rect if (partial_map and have_rect) else Rect2()

# Rect englobant MONDE d'un territoire actif (rect caméra G5) — Rect2() vide si aucun polygone.
func _node_world_rect(node: Node) -> Rect2:
	for child in node.get_children():
		if child is CollisionPolygon2D and child.polygon.size() > 0:
			var xform: Transform2D = child.global_transform
			var rect := Rect2(xform * child.polygon[0], Vector2.ZERO)
			for p in child.polygon:
				rect = rect.expand(xform * p)
			return rect
	if node is Node2D:
		return Rect2(node.global_position, Vector2.ZERO)
	return Rect2()

# Rect englobant des territoires de la carte ACTIVE (G5 §8.71) — vide = carte complète (le
# consommateur, la caméra tactique, garde alors sa vue plein plateau historique).
var _active_rect := Rect2()

func get_active_map_rect() -> Rect2:
	return _active_rect

# Crée (une fois) puis renvoie le Polygon2D de remplissage d'un territoire, construit à partir
# de son CollisionPolygon2D (mêmes points, transformés dans l'espace local de l'Area2D).
# Renvoie null si le nœud n'a pas de polygone exploitable (cas fallback BaseButton).
func _ensure_fill(tid: String, node: Node) -> Polygon2D:
	if _fills.has(tid) and is_instance_valid(_fills[tid]):
		return _fills[tid]
	var cpoly: CollisionPolygon2D = null
	for child in node.get_children():
		if child is CollisionPolygon2D and child.polygon.size() >= 3:
			cpoly = child
			break
	if cpoly == null:
		return null
	var pts := PackedVector2Array()
	for p in cpoly.polygon:
		pts.append(cpoly.transform * p)
	var fill := Polygon2D.new()
	fill.polygon = pts
	# Enfant de l'Area2D (dans TerritoriesContainer, rendu APRÈS le BoardBackground → par-dessus
	# la carte). Polygon2D n'a pas de picking → n'intercepte pas les clics (picking sur l'Area2D).
	node.add_child(fill)
	_fills[tid] = fill
	return fill

# Applique (ou met à jour) le ShaderMaterial de pulsation toxique (§8.30) sur le remplissage
# d'un territoire contaminé. Réutilise le matériau déjà présent pour ne pas en recréer un à
# chaque rafraîchissement ; lui passe l'accent du propriétaire (le shader pulse vers le vert
# nucléaire). Voir toxic_pulsation.gdshader.
func _apply_toxic_material(fill: Polygon2D, base_accent: Color) -> void:
	var mat := fill.material as ShaderMaterial
	# Recrée le matériau si absent OU s'il portait un AUTRE shader (ex. l'hologramme d'un territoire
	# qui vient d'ENTRER dans la zone) — sinon on pousserait des paramètres toxiques sur l'hologramme.
	if mat == null or mat.shader != ToxicShader:
		mat = ShaderMaterial.new()
		mat.shader = ToxicShader
		fill.material = mat
	mat.set_shader_parameter("base_color", base_accent)
	mat.set_shader_parameter("rad_color", RAD_COLOR)
	mat.set_shader_parameter("fill_alpha", CONTAMINATED_ALPHA)

# Applique (ou met à jour) le ShaderMaterial « Hologramme Tactique » (Concept A) sur le remplissage
# d'un territoire POSSÉDÉ hors zone : contour néon + hachures diagonales défilantes, intérieur quasi
# transparent. Réutilise le matériau s'il porte déjà ce shader (sinon le recrée — le territoire
# sortait peut-être de la zone radioactive). On lui transmet l'accent du propriétaire ET les sommets
# du polygone (espace local du Polygon2D) pour le SDF du contour. Voir neon_hologram.gdshader.
#
# `emphasized` (territoire du JOUEUR LOCAL) renforce contour + halo + hachures pour faire RESSORTIR
# mes possessions ; à false (adversaire) on atténue ces mêmes paramètres → la carte se lit « les
# miens brillent, les leurs sont en sourdine ». La couleur de faction reste INCHANGÉE dans les deux
# cas (on ne joue que sur l'intensité, pour préserver l'identité visuelle des factions).
func _apply_hologram_material(fill: Polygon2D, accent: Color, emphasized: bool = false) -> void:
	var mat := fill.material as ShaderMaterial
	if mat == null or mat.shader != HologramShader:
		mat = ShaderMaterial.new()
		mat.shader = HologramShader
		fill.material = mat
	mat.set_shader_parameter("accent_color", accent)
	# Intensité de l'hologramme selon l'appartenance (mes territoires = vifs, adverses = atténués).
	mat.set_shader_parameter("neon_width", 10.0 if emphasized else 5.0)
	mat.set_shader_parameter("glow_width", 52.0 if emphasized else 26.0)
	mat.set_shader_parameter("glow_strength", 0.5 if emphasized else 0.16)
	mat.set_shader_parameter("neon_boost", 2.4 if emphasized else 1.5)
	mat.set_shader_parameter("hatch_alpha", 0.24 if emphasized else 0.09)
	var pts := fill.polygon
	if pts.size() > MAX_HOLO_POINTS:
		push_warning("board.gd : territoire à %d sommets > %d — contour néon tronqué." % [pts.size(), MAX_HOLO_POINTS])
		pts = pts.slice(0, MAX_HOLO_POINTS)
	mat.set_shader_parameter("edge_points", pts)
	mat.set_shader_parameter("point_count", pts.size())

# Crée (ou réactive) l'ombre portée de relief d'un territoire possédé par le JOUEUR LOCAL : un
# Polygon2D jumeau du remplissage, décalé de OWN_RELIEF_OFFSET et dessiné DERRIÈRE lui (déplacé en
# 1er enfant de l'Area2D) → le territoire paraît soulevé au-dessus de la carte. Réutilisé d'un
# rafraîchissement à l'autre (on ne le recrée pas), simplement masqué quand il n'est plus à moi.
func _apply_own_relief(tid: String, node: Node, fill: Polygon2D) -> void:
	var shadow = _shadows.get(tid)
	if shadow == null or not is_instance_valid(shadow):
		shadow = Polygon2D.new()
		shadow.name = "OwnRelief"
		node.add_child(shadow)
		node.move_child(shadow, 0)  # dessiné AVANT le remplissage → derrière lui
		_shadows[tid] = shadow
	shadow.polygon = fill.polygon
	shadow.position = OWN_RELIEF_OFFSET
	shadow.color = OWN_RELIEF_COLOR
	shadow.visible = true

# Masque l'ombre de relief d'un territoire qui n'appartient plus au JOUEUR LOCAL (adverse / neutre /
# perdu). On la conserve masquée plutôt que de la libérer : elle resservira si le territoire revient.
func _clear_own_relief(tid: String) -> void:
	var shadow = _shadows.get(tid)
	if shadow != null and is_instance_valid(shadow):
		shadow.visible = false

# Crée ou met à jour le badge de troupes d'un territoire, positionné en son centre.
# `contaminated` (défaut false) pilote l'alerte ☢ ; `forecast` (défaut false) le ⚠ or du
# télégraphe (G1 §8.62) ; repassés à chaque rafraîchissement → un territoire qui quitte la zone
# (ou n'est plus annoncé) est automatiquement réinitialisé (☢/⚠ retirés).
# Initiale (majuscule) du pseudo d'un joueur pour la redondance texte du badge daltonien (E10).
func _owner_initial(pid: int) -> String:
	var p = GameState.players.get(str(pid), {})
	if typeof(p) == TYPE_DICTIONARY:
		var uname := str(p.get("username", ""))
		if uname != "":
			return uname.substr(0, 1).to_upper()
	return str(pid) if pid >= 0 else "IA"

func _update_badge(tid: String, troops: int, accent: Color, contaminated: bool = false,
		pending: int = 0, forecast: bool = false, initial: String = "",
		shielded: bool = false) -> void:
	var pos := get_territory_position(tid)
	if pos == Vector2.INF:
		return
	if _badge_layer == null or not is_instance_valid(_badge_layer):
		_badge_layer = Node2D.new()
		_badge_layer.name = "BadgeLayer"
		# §8.122 (LOT D) : les badges de troupes doivent rester AU-DESSUS du calque d'ambiance
		# AmbientFront (z_index 1, déclaré dans board.tscn) — une fumée de guerre ne masque jamais
		# un nombre de troupes. Voir le commentaire d'ordre de rendu dans board.tscn.
		_badge_layer.z_index = 2
		add_child(_badge_layer)
	var badge = _badges.get(tid)
	if badge == null or not is_instance_valid(badge):
		badge = TerritoryBadgeScene.instantiate()
		_badge_layer.add_child(badge)
		_badges[tid] = badge
	# Ré-affiche un badge masqué par un passage hors-carte (changement de carte, G5 §8.71).
	badge.visible = true
	badge.global_position = pos
	badge.set_data(troops, accent, contaminated, pending, forecast, initial, shielded)

# Position monde (espace du SubViewport) du centre d'un territoire — utilisée par la
# caméra tactique pour cadrer les combats. Centre = centroïde du CollisionPolygon2D si
# présent, sinon position du nœud. Vector2.INF si le territoire est inconnu.
func get_territory_position(tid: String) -> Vector2:
	var node = _nodes.get(tid)
	if node == null:
		return Vector2.INF
	for child in node.get_children():
		if child is CollisionPolygon2D and child.polygon.size() > 0:
			var centroid := Vector2.ZERO
			for p in child.polygon:
				centroid += p
			return child.global_transform * (centroid / child.polygon.size())
	if node is Node2D:
		return node.global_position
	return Vector2.INF

func _on_pressed(tid: String) -> void:
	territory_clicked.emit(tid)

# Survol d'un territoire (G4 §8.63) : simple relais de signal (aucune logique de jeu, §6.1).
func _on_area_mouse_entered(tid: String) -> void:
	territory_hovered.emit(tid)

func _on_area_mouse_exited(tid: String) -> void:
	territory_unhovered.emit(tid)

# Handler des Area2D : clic GAUCHE enfoncé → territory_clicked ; clic DROIT enfoncé →
# territory_right_clicked (retrait d'une troupe en attente, §8.26). Les autres évènements
# input_event (survol, relâche) sont ignorés.
func _on_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int, tid: String) -> void:
	if event is InputEventMouseButton and event.pressed:
		_pick_frame = Engine.get_process_frames()
		if event.button_index == MOUSE_BUTTON_LEFT:
			territory_clicked.emit(tid)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			territory_right_clicked.emit(tid)

# Clic GAUCHE « dans le vide » : si aucun Area2D n'a capté ce clic CETTE frame, on referme
# l'Inspecteur Tactique (§1). Le picking physique stampe _pick_frame juste avant ; si la frame
# courante diffère, c'est que le clic n'a touché aucun territoire. (Le bouton ✕ de l'Inspecteur
# reste le repli garanti si l'ordre picking/_unhandled_input variait.)
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Engine.get_process_frames() != _pick_frame:
			board_cleared.emit()

# Vrai si le territoire est dans la zone de contamination courante (§1 Inspecteur Tactique).
# Wrapper public sur _contaminated_set (modèle cluster §8.27).
func is_contaminated(tid: String) -> bool:
	return _contaminated_set().has(tid)

# Flash radial de CONQUÊTE (E9 §8.81) : halo 0,5 s à la teinte accent du conquérant sur le
# territoire pris (shader conquest_flash confiné au Polygon2D de remplissage — pattern §8.30).
const ConquestFlashShader: Shader = preload("res://shaders/conquest_flash.gdshader")

func conquest_flash(tid: String, accent: Color) -> void:
	# CARTE VIVANTE (§8.122, LOT D) : le territoire pris se met à FUMER. On le notifie ICI — c'est
	# le point unique par lequel passe toute conquête côté vue (main.gd n'en connaît pas d'autre) —
	# et le panache survit ensuite à sa propre logique d'ancienneté (round courant → round-2).
	if _ambient != null and is_instance_valid(_ambient):
		_ambient.on_conquest(tid, int(GameState.current_turn))
	var node = _nodes.get(tid)
	if node == null:
		return
	var fill := _ensure_fill(tid, node)
	if fill == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = ConquestFlashShader
	mat.set_shader_parameter("flash_color", Color(accent.r, accent.g, accent.b, 0.85))
	mat.set_shader_parameter("progress", 0.0)
	fill.material = mat
	fill.color = Color(accent.r, accent.g, accent.b, 0.0)
	fill.visible = true
	var tw := fill.create_tween()
	tw.tween_method(func(v: float): mat.set_shader_parameter("progress", v), 0.0, 1.0, 0.5)
	tw.tween_callback(func() -> void:
		fill.material = null
		fill.visible = false)

# Flotteur « tic de zone » (E9 §8.81) : « -1 » vert toxique sur un territoire touché par la
# contamination. Réutilise le calque de badges (BadgeLayer) posé sur le plateau.
func spawn_zone_tick(tid: String) -> void:
	# Réglage damage_numbers (E10 §8.82) : les flotteurs de dégâts (zone comprise) sont masquables.
	if not bool(SettingsManager.get_comfort("damage_numbers")):
		return
	var pos := get_territory_position(tid)
	if pos == Vector2.INF:
		return
	if _badge_layer == null or not is_instance_valid(_badge_layer):
		_badge_layer = Node2D.new()
		_badge_layer.name = "BadgeLayer"
		# §8.122 (LOT D) : les badges de troupes doivent rester AU-DESSUS du calque d'ambiance
		# AmbientFront (z_index 1, déclaré dans board.tscn) — une fumée de guerre ne masque jamais
		# un nombre de troupes. Voir le commentaire d'ordre de rendu dans board.tscn.
		_badge_layer.z_index = 2
		add_child(_badge_layer)
	var lbl := Label.new()
	lbl.text = "-1"
	lbl.add_theme_font_size_override("font_size", 30)
	lbl.add_theme_color_override("font_color", Color("7fff00"))
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_badge_layer.add_child(lbl)
	lbl.global_position = pos + Vector2(-14, -60)
	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "global_position:y", lbl.global_position.y - 60.0, 1.1)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.1)
	tw.chain().tween_callback(lbl.queue_free)

# Flash bref d'un territoire (E4 §8.76 — clic d'une entrée du Journal de Guerre) : teinte accent
# du propriétaire, 0,4 s. Réutilise le Polygon2D de remplissage legacy (_ensure_fill — inutilisé
# depuis l'overlay « vraies frontières » §8.51) comme calque de flash ponctuel.
func flash_territory(tid: String) -> void:
	var accent: Color = NEUTRAL_COLOR
	var t: Dictionary = GameState.territories.get(tid, {})
	var o = t.get("owner_id")
	if o != null:
		accent = get_player_color(int(o))
	flash_territory_color(tid, Color(accent.r, accent.g, accent.b, 0.55), 0.4)

# Flash d'un territoire à une couleur ARBITRAIRE (§8.122, LOT D — éclair de zone blanc-vert).
# EXTRAIT de flash_territory : les deux effets partagent le même Polygon2D de remplissage legacy,
# et une 2ᵉ implémentation aurait fini par diverger (z-order, nettoyage du matériau, durée).
# L'alpha de `color` fait foi ; le fondu ramène simplement à 0.
func flash_territory_color(tid: String, color: Color, duration: float) -> void:
	var node = _nodes.get(tid)
	if node == null:
		return
	var fill := _ensure_fill(tid, node)
	if fill == null:
		return
	# Purge d'un éventuel ShaderMaterial (conquest_flash / legacy toxique) : sinon le shader
	# écraserait COLOR et le flash serait invisible.
	fill.material = null
	fill.color = color
	fill.visible = true
	var tw := fill.create_tween()
	tw.tween_property(fill, "color:a", 0.0, maxf(duration, 0.05))
	tw.tween_callback(func() -> void: fill.visible = false)
