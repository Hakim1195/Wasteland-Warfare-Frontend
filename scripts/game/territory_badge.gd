extends Node2D

# BADGE DE TROUPES — pastille militaire posée au centre d'un territoire (Visibilité Tactique).
# Cercle de fond sombre + anneau de bordure à la couleur de la faction propriétaire + nombre
# de troupes en typographie épaisse (Stencil) au centre. Instancié et positionné par board.gd
# (un badge par territoire). AUCUNE logique de jeu (Règle d'Or §6.1) : vue pure pilotée par
# set_data().
#
# Alerte ZONE RADIOACTIVE : si le territoire est dans la contamination_zone, le badge affiche
# une icône ☢ verte au-dessus du chiffre ET un anneau vert nucléaire autour de la pastille.
# L'état est repassé à CHAQUE rafraîchissement par board.gd → un territoire qui sort de la zone
# est automatiquement réinitialisé (☢ masqué, anneau retiré).
#
# TÉLÉGRAPHE (G1 §8.62) : si le territoire est ANNONCÉ pour la prochaine zone
# (contamination_zone.next_territories), le badge affiche un ⚠ OR sous le chiffre — distinct du
# ☢ vert de la zone courante. Même contrat : l'état est repassé à chaque rafraîchissement.

const RADIUS := 30.0
const BORDER_WIDTH := 5.0
# Disque de fond anthracite quasi opaque (lisibilité du chiffre par-dessus le plateau).
const BG_COLOR := Color(0.058824, 0.07451, 0.094118, 0.92)
# Vert nucléaire de la zone de contamination (cohérent avec la teinte du plateau, board.gd).
const RAD_COLOR := Color("7fff00")
# Épaisseur de l'anneau d'alerte radioactif dessiné autour du badge contaminé.
const RAD_RING_WIDTH := 4.0
# Couleur par défaut du chiffre (= celle posée dans territory_badge.tscn, blanc kaki).
const TEXT_COLOR := Color(0.933333, 0.952941, 0.968627, 1)
# Or vif pour les troupes EN ATTENTE de confirmation (tampon de déploiement, §8.26).
const PENDING_COLOR := Color("e0b249")
# Or/ambre du TÉLÉGRAPHE de zone (G1 §8.62) — miroir de forecast_color du shader overlay.
const FORECAST_COLOR := Color(1.0, 0.75, 0.1)

@onready var _label: Label = $Label
@onready var _rad_label: Label = $RadLabel

# Couleur de l'anneau = accent de la faction propriétaire (gris si neutre, décidé par board.gd).
var _border_color: Color = Color("8a97a5")
# Texte mémorisé tant que le Label n'est pas encore prêt (set_data peut précéder _ready).
var _troops_text: String = "0"
# Vrai si ce territoire est dans la zone de contamination (☢ + anneau vert).
var _contaminated: bool = false
# Vrai s'il reste des troupes en attente de confirmation sur ce territoire (affichage "+X" doré).
var _has_pending: bool = false
# Vrai si ce territoire est ANNONCÉ pour la prochaine zone (⚠ or, télégraphe G1 §8.62).
var _forecast: bool = false
# Label ⚠ créé PAR CODE au premier besoin (pas de retouche du .tscn) : clone du RadLabel (hérite
# de sa police symboles), repositionné SOUS le chiffre, teinté or.
var _forecast_label: Label = null
# Initiale du pseudo (E10 §8.82 — mode daltonien) : redondance TEXTE de l'identité du propriétaire,
# affichée en pastille de coin. "" = mode normal (aucune initiale).
var _initial: String = ""
var _initial_label: Label = null

func _ready() -> void:
	_apply_text()
	_apply_contamination()
	_apply_forecast()
	_apply_initial()
	queue_redraw()

# Met à jour le badge : nombre de troupes, couleur de bordure (accent de faction), état de
# contamination (☢), troupes EN ATTENTE (`pending` → affichage "Troupes+X" doré, §8.26) et
# ANNONCE de prochaine zone (`forecast` → ⚠ or, télégraphe G1 §8.62).
# Défauts → rétro-compatible avec d'anciens appels à 2/3/4 arguments.
func set_data(troops: int, accent: Color, contaminated: bool = false, pending: int = 0,
		forecast: bool = false, initial: String = "") -> void:
	_border_color = accent
	_contaminated = contaminated
	_forecast = forecast
	_initial = initial
	_has_pending = pending > 0
	if _has_pending:
		_troops_text = "%d+%d" % [troops, pending]
	else:
		_troops_text = str(troops)
	if is_node_ready():
		_apply_text()
		_apply_contamination()
		_apply_forecast()
		_apply_initial()
	queue_redraw()

# Initiale du propriétaire (E10 daltonien) : pastille en coin haut-gauche, créée paresseusement
# (clone du chiffre pour la police), masquée en mode normal.
func _apply_initial() -> void:
	if _initial != "" and _initial_label == null and _label != null:
		_initial_label = _label.duplicate()
		_initial_label.name = "InitialLabel"
		_initial_label.add_theme_font_size_override("font_size", 22)
		_initial_label.offset_left = -64.0
		_initial_label.offset_top = -64.0
		_initial_label.offset_right = -24.0
		_initial_label.offset_bottom = -24.0
		add_child(_initial_label)
	if _initial_label != null:
		_initial_label.visible = _initial != ""
		if _initial != "":
			_initial_label.text = _initial
			_initial_label.add_theme_color_override("font_color", _border_color.lightened(0.3))

func _apply_text() -> void:
	if _label:
		_label.text = _troops_text
		# Troupes en attente → chiffre doré pour les distinguer des troupes confirmées.
		_label.add_theme_color_override("font_color", PENDING_COLOR if _has_pending else TEXT_COLOR)

# Affiche ou masque l'icône ☢ selon l'état de contamination (réinitialisation incluse).
func _apply_contamination() -> void:
	if _rad_label:
		_rad_label.visible = _contaminated

# Affiche ou masque le ⚠ or du télégraphe (G1 §8.62). Le label est créé paresseusement en
# dupliquant RadLabel (même police symboles / contour), miroir SOUS le chiffre, teinté or.
func _apply_forecast() -> void:
	if _forecast and _forecast_label == null and _rad_label != null:
		_forecast_label = _rad_label.duplicate()
		_forecast_label.name = "ForecastLabel"
		_forecast_label.text = "⚠"
		_forecast_label.add_theme_color_override("font_color", FORECAST_COLOR)
		# Miroir vertical du ☢ (qui occupe [-72,-32] au-dessus) → [32,72] SOUS le chiffre.
		_forecast_label.offset_top = 32.0
		_forecast_label.offset_bottom = 72.0
		add_child(_forecast_label)
	if _forecast_label != null:
		_forecast_label.visible = _forecast

func _draw() -> void:
	# Disque de fond sombre.
	draw_circle(Vector2.ZERO, RADIUS, BG_COLOR)
	# Anneau de bordure coloré (au milieu de l'épaisseur du trait).
	draw_arc(Vector2.ZERO, RADIUS - BORDER_WIDTH * 0.5, 0.0, TAU, 48, _border_color, BORDER_WIDTH, true)
	# Alerte radioactive : anneau vert nucléaire entourant le badge (lisible même de loin).
	if _contaminated:
		draw_arc(Vector2.ZERO, RADIUS + RAD_RING_WIDTH, 0.0, TAU, 48, RAD_COLOR, RAD_RING_WIDTH, true)
	# Télégraphe (G1 §8.62) : anneau OR (par-dessous le vert si les deux s'appliquent) pour un
	# territoire annoncé — lisible même quand le shader du plateau est indisponible.
	elif _forecast:
		draw_arc(Vector2.ZERO, RADIUS + RAD_RING_WIDTH, 0.0, TAU, 48, FORECAST_COLOR, RAD_RING_WIDTH, true)
