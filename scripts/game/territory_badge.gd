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

func _ready() -> void:
	_apply_text()
	_apply_contamination()
	queue_redraw()

# Met à jour le badge : nombre de troupes, couleur de bordure (accent de faction), état de
# contamination (☢) et troupes EN ATTENTE (`pending` → affichage "Troupes+X" doré, §8.26).
# `contaminated`/`pending` par défaut → rétro-compatible avec d'anciens appels à 2/3 arguments.
func set_data(troops: int, accent: Color, contaminated: bool = false, pending: int = 0) -> void:
	_border_color = accent
	_contaminated = contaminated
	_has_pending = pending > 0
	if _has_pending:
		_troops_text = "%d+%d" % [troops, pending]
	else:
		_troops_text = str(troops)
	if is_node_ready():
		_apply_text()
		_apply_contamination()
	queue_redraw()

func _apply_text() -> void:
	if _label:
		_label.text = _troops_text
		# Troupes en attente → chiffre doré pour les distinguer des troupes confirmées.
		_label.add_theme_color_override("font_color", PENDING_COLOR if _has_pending else TEXT_COLOR)

# Affiche ou masque l'icône ☢ selon l'état de contamination (réinitialisation incluse).
func _apply_contamination() -> void:
	if _rad_label:
		_rad_label.visible = _contaminated

func _draw() -> void:
	# Disque de fond sombre.
	draw_circle(Vector2.ZERO, RADIUS, BG_COLOR)
	# Anneau de bordure coloré (au milieu de l'épaisseur du trait).
	draw_arc(Vector2.ZERO, RADIUS - BORDER_WIDTH * 0.5, 0.0, TAU, 48, _border_color, BORDER_WIDTH, true)
	# Alerte radioactive : anneau vert nucléaire entourant le badge (lisible même de loin).
	if _contaminated:
		draw_arc(Vector2.ZERO, RADIUS + RAD_RING_WIDTH, 0.0, TAU, 48, RAD_COLOR, RAD_RING_WIDTH, true)
