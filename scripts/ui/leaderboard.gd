extends Control

# =========================================================================
# Classement mondial (Feuille de route R3) — charte « Warzone Command » §2
# =========================================================================
# Règle d'Or §6.1 : VUE pure — aucune logique de jeu brute. Le classement est SERVEUR (R3 —
# CONTRAT_RESEAU.md §9.2, ladder RP §8.95, navigation §8.98).
#
# §8.98 — NAVIGATION PAR DIVISION (le classement n'est plus « tous mélangés ») :
#   • bande des 5 divisions CLIQUABLE (seuil + effectif) → chaque division ouvre SON classement ;
#   • 3 onglets de SOUS-DIVISION (I/II/III, 200 RP chacune) — ÉLITE = ladder ouvert, sans onglet ;
#   • le PODIUM affiché est celui de la sous-division I de la division sélectionnée (spec) ;
#   • l'onglet GÉNÉRAL (lifetime) est retiré de l'écran (l'API reste servie — réseau additif) ;
#   • toutes les requêtes passent par une FILE (une seule en vol : le signal global ne rappelle
#     pas ses paramètres) et un CACHE par tranche « DIVISION|TIER ».
# REPLIS : backend sans `divisions` → liste plate historique (M6/§9.2) ; serveur muet → attente
# « SYNCHRONISATION… » ; échec avéré → mock étiqueté « HORS LIGNE » (§8.96).

# Nœuds câblés via @export + NodePath (drag-drop éditeur) — cf. conventions CLAUDE.md.
@export var panel: Control
@export var header_bar: HBoxContainer  # heberge le bouton « i REGLES » (chantier H)
@export var podium_box: HBoxContainer
@export var columns_header: HBoxContainer
@export var ranking_box: VBoxContainer
@export var status_label: Label

# Helpers UI partagés de la charte « Warzone Command » (§2) — encoches + badges hexagonaux.
const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")
# Header CANONIQUE partagé (§8.94) — remplace l'ex-en-tête (titre + RETOUR).
const TopNav = preload("res://scripts/ui/top_nav.gd")
# §8.107 — écran de PROFIL PUBLIC ouvert au clic sur une ligne (le pseudo transite par son
# `static var target_username`, cf. `_open_public_profile`).
const PublicProfileScreen = preload("res://scripts/ui/public_profile.gd")

# --- Palette canonique (§2) ---
const ACCENT := Color(0.211765, 0.772549, 0.85098, 1)   # cyan tactique
const GOLD := Color(0.878431, 0.698039, 0.286275, 1)    # or (podium / récompense)
const TEXT := Color(0.933333, 0.952941, 0.968627, 1)    # blanc froid
const MUTED := Color(0.541176, 0.592157, 0.647059, 1)   # acier (eyebrow / muet)
const SURFACE := Color(0.101961, 0.12549, 0.156863, 1)  # surface secondaire
const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 1) # fond gunmetal (texte sur badge or)

# Largeurs de colonnes (partagées entre l'en-tête fixe et les lignes défilantes → alignement garanti).
const COL_RANK := 90.0
const COL_LEVEL := 120.0
const COL_WINS := 140.0

# --- Données MOCK (remplacées par l'endpoint classement quand il sera spécifié) ---
# Classement mondial fictif (déjà trié desc. par victoires, comme le ferait le serveur).
# Chaque entrée : { name, level, wins }. L'opérateur local est inséré à part (_build_entries).
var _mock_board: Array = [
	{"name": "RAVAGEUR_PRIME", "level": 58, "wins": 412},
	{"name": "VDV_KOZLOV", "level": 51, "wins": 377},
	{"name": "SISTER_OBLIVION", "level": 49, "wins": 341},
	{"name": "GHOST_OF_KIEV", "level": 47, "wins": 318},
	{"name": "RUST_BARON_IX", "level": 44, "wins": 295},
	{"name": "ATOMIC_HYENA", "level": 42, "wins": 271},
	{"name": "PROPHETE_ISOTOPE", "level": 39, "wins": 244},
	{"name": "CENDRE_NOIRE", "level": 37, "wins": 228},
	{"name": "WARLORD_MOJAVE", "level": 34, "wins": 201},
	{"name": "LA_FAUCHEUSE", "level": 31, "wins": 176},
	{"name": "FERRAILLEUR_77", "level": 28, "wins": 152},
	{"name": "NOMADE_ERRANT", "level": 25, "wins": 131},
]

# Valeurs de l'opérateur local (lues défensivement du profil ; sinon mock).
var _local_name: String = ""
var _local_level: int = 23
var _local_wins: int = 118

# Classement RÉEL renvoyé par le serveur (R3, GET /leaderboard). Tant qu'il est vide (serveur muet
# ou hors-ligne), l'écran affiche le mock ci-dessus en prévisualisation ; dès qu'il répond, il le REMPLACE.
# Chaque entrée : { name, level, wins, rank } (rank = position GLOBALE serveur, 0 si forme legacy).
var _server_board: Array = []
# Bloc « me » (§9.2) : { rank, level, wins } de l'opérateur courant, rang GLOBAL fiable même hors page.
# Vide si non authentifié ou ancien backend. Sert à surligner / ajouter l'opérateur au classement réel.
var _me: Dictionary = {}

# Police condensée de la charte (§2), construite en code pour les nœuds générés dynamiquement.
var _font: SystemFont

# --- Ladder SAISONNIER (lot M6 §8.68, révisé §8.98) ---
# §8.98 : l'onglet GÉNÉRAL (lifetime) est RETIRÉ de l'écran (décision produit : « d'aucune
# utilité » pour l'instant) — l'API `scope=lifetime` reste servie côté serveur (réseau additif),
# seul le client n'en propose plus l'accès. Tout l'écran est donc en scope SAISON.
const SCOPE := "season"
# Bloc { id, ends_at, divisions?, rules? } de la réponse, lu de NetworkManager.
var _season_info: Dictionary = {}
# Vrai si le serveur fournit les divisions (backend ≥ M6). Repli legacy : false → liste plate.
var _has_division_data := false

# Couleurs des divisions (M6 §8.68 — bronze/argent/or charte/platine cyan pâle/élite cyan tactique).
const DIVISION_COLORS := {
	"BRONZE": Color("cd7f32"),
	"ARGENT": Color("c0c0c0"),
	"OR": Color(0.878431, 0.698039, 0.286275, 1),
	"PLATINE": Color("9adfea"),
	"ELITE": Color(0.211765, 0.772549, 0.85098, 1),
}
const COL_DIVISION := 120.0
const DANGER := Color(0.839216, 0.270588, 0.247059, 1)  # rouge (ΔRP négatif)

# --- Ladder RP (§8.95) ---
# Taille de page (le serveur accepte limit/offset ; l'écran figeait 20/0 → « AFFICHER PLUS »).
const PAGE_SIZE := 20
# Offset de la PROCHAINE page à demander — chemin LEGACY (liste plate) uniquement ; en navigation
# par division (§8.98) la pagination vit PAR TRANCHE dans _tier_cache.
var _offset: int = 0
# Vrai pendant qu'une page supplémentaire est en vol (évite d'empiler les clics sur « AFFICHER PLUS »).
var _loading_more: bool = false
# Vrai quand la dernière réponse a renvoyé MOINS que PAGE_SIZE → plus rien à charger (legacy).
var _end_reached: bool = false

# --- Navigation PAR DIVISION (§8.98) ---
# Le classement ne s'affiche plus « tous mélangés » : on navigue par division (bande cliquable),
# puis par sous-division (3 onglets d'échelon I/II/III — ÉLITE n'en a pas, ladder ouvert).
# Actif dès que le serveur publie `season.divisions` (backend ≥ §8.98) ; sinon repli liste plate.
var _browse_mode: bool = false
var _selected_division: String = ""   # division affichée ("" tant que rien n'est sélectionné)
var _selected_tier: String = ""       # échelon affiché ("I"/"II"/"III" ; "" pour ÉLITE)
# Cache des tranches déjà chargées : "DIVISION|TIER" -> { "entries": Array, "end_reached": bool }.
var _tier_cache: Dictionary = {}
# File de requêtes leaderboard (UNE seule en vol à la fois : le signal global ne rappelle pas ses
# paramètres — sans sérialisation, deux réponses croisées se rangeraient dans la mauvaise tranche).
var _fetch_queue: Array = []
var _fetch_pending: Dictionary = {}   # requête EN VOL ({division, tier, offset}) ; {} = aucune
# Onglets d'échelon (rangée reconstruite à chaque sélection) + boutons de la bande des divisions.
var _tier_tabs_row: HBoxContainer = null
# Références scène (nommées dans le .tscn — pas de nom auto-généré, piège §8.95) :
var _podium_eyebrow: Label = null     # « PODIUM — {division} I » en navigation, clé brute sinon
var _ranking_eyebrow: Label = null    # masqué en navigation (les onglets d'échelon le remplacent)
# Conteneurs construits en code, insérés en tête du panneau (carte « VOTRE RANG » + bande divisions).
var _rank_card_slot: VBoxContainer = null
var _divisions_slot: VBoxContainer = null
# Bouton de pagination (pied de liste) + panneau RÈGLES (overlay à la demande).
var _more_button: Button = null
var _rules_button: Button = null
var _rules_overlay: Control = null
# Corps du panneau RÈGLES. ⚠️ Référence DIRECTE et non un get_node("CenterContainer/…") : un nœud
# ajouté par code sans `name` explicite reçoit un nom AUTO-GÉNÉRÉ (« @CenterContainer@2 ») — le
# chemin échouait silencieusement et le panneau s'affichait VIDE.
var _rules_body: VBoxContainer = null

# ΔRP du DERNIER game_over de la session (chip « dernier match » de la carte VOTRE RANG). Le Rapport
# Post-Op le publie via MatchConfig (autoload survivant au changement de scène) ; absent → pas de chip.
var _last_rp_delta_known: bool = false
var _last_rp_delta: int = 0

# §8.96 : passe à VRAI seulement après un ÉCHEC AVÉRÉ du fetch → le mock de prévisualisation n'est
# plus affiché « par défaut » mais uniquement hors ligne, étiqueté comme tel.
var _offline_fallback: bool = false

func _ready():
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	_font.font_weight = 700

	# Nav PARTAGÉE (§8.94), onglet CLASSEMENT actif (c'est lui qui nomme désormais l'écran, d'où le
	# retrait du titre interne) ; ÉCHAP (nav) remplace l'ex-bouton RETOUR.
	# ⚠️ active_tab réglé AVANT add_child (lu au _ready du composant).
	var nav := TopNav.new()
	nav.active_tab = "leaderboard"
	add_child(nav)
	# Ambiance sonore : à la charge de l'écran HÔTE (la nav ne la lance jamais) — R6, idempotent.
	AudioManager.start_menu_ambient()

	# Entrée d'écran UNIFORME (§8.96) : fondu + léger glissement, identique sur tous les écrans hub.
	WarzoneUI.animate_screen_enter(self)

	# Encoche biseautée d'angle sur le panneau principal (ADN angulaire §2).
	WarzoneUI.add_corner_notches(panel)

	# En-tête de colonnes (eyebrows alignés sur les lignes).
	_build_columns_header()

	# Emplacements du ladder RP (§8.95), insérés EN TÊTE du panneau : carte « VOTRE RANG » puis
	# bande des divisions (avant l'eyebrow du podium).
	_build_rp_slots()
	# Bouton « ℹ RÈGLES » dans la barre d'en-tête (masqué tant que `season.rules` est absent).
	_build_rules_button()
	# Pied de liste « AFFICHER PLUS » (pagination — masqué tant qu'il n'y a rien de plus à charger).
	_build_more_button()
	# ΔRP du dernier match de la session (chip de la carte VOTRE RANG) — lu du cache NetworkManager.
	_read_last_rp_delta()

	# Identité locale : connue dès le login (AuthManager.username) ; le niveau/victoires arrivent
	# via /auth/me (le code ne pousse que les valeurs ; les intitulés statiques vivent dans la scène).
	# Repli NEUTRE « Joueur » (COMMON_PLAYER) — COMMON_OPERATOR est un libellé, pas un nom (§8.102).
	_local_name = AuthManager.username if AuthManager.username != "" else tr("COMMON_PLAYER")
	AuthManager.profile_loaded.connect(_on_profile_loaded)
	AuthManager.get_profile()

	# §8.98 : plus d'onglets SAISON/GÉNÉRAL — l'écran est tout entier en scope SAISON (le GÉNÉRAL,
	# jugé sans utilité pour l'instant, n'a plus d'accès client ; l'API lifetime reste servie).

	# Classement mondial RÉEL (§P2) : GET /leaderboard via NetworkManager. Toutes les requêtes de
	# l'écran passent par la FILE (§8.98) — la requête d'amorçage est GLOBALE (division "") : elle
	# rapporte `me` + `divisions` + `rules` (et alimente le repli liste plate d'un backend antérieur).
	NetworkManager.leaderboard_loaded.connect(_on_leaderboard_loaded)
	# ÉCHEC réseau (§8.96) : le fetch signale ses erreurs via lobby_error → c'est SEULEMENT là qu'on
	# bascule sur le mock. Avant, le mock s'affichait D'EMBLÉE : un classement fictif « flashait »
	# une fraction de seconde avant d'être remplacé par le vrai — trompeur.
	NetworkManager.lobby_error.connect(_on_leaderboard_failed)
	_queue_fetch("", "", 0)

	# État d'ATTENTE : aucune donnée tant que le serveur n'a pas répondu (ni mock, ni podium fictif).
	_set_status(tr("COMMON_SYNCING"))

# ΔRP du DERNIER game_over de la session (§8.95). `last_match_rewards` est un cache d'autoload : il
# survit au changement de scène. Il est REDACTÉ par destinataire (E11 §8.83) → il ne contient QUE
# notre entrée, d'où la lecture par « clé unique ». Garde défensive : si un serveur ANTÉRIEUR à la
# redaction renvoie toutes les entrées, on ne saurait pas laquelle est la nôtre (l'id local n'est pas
# connu de cet écran) → on n'affiche RIEN plutôt qu'un ΔRP d'un autre joueur (repli prévu par la spec).
func _read_last_rp_delta() -> void:
	var rewards: Dictionary = NetworkManager.last_match_rewards
	if rewards.size() != 1:
		return
	var mine = rewards.values()[0]
	if typeof(mine) != TYPE_DICTIONARY or not mine.has("rp_delta"):
		return  # serveur antérieur au ladder RP → pas de chip.
	_last_rp_delta = int(mine.get("rp_delta", 0))
	_last_rp_delta_known = true

# Échec AVÉRÉ du fetch (§8.96) : c'est SEULEMENT ici qu'on montre le mock, explicitement étiqueté
# « HORS LIGNE — DONNÉES LOCALES » (avant, le mock passait pour de vraies données). `lobby_error` est
# un signal GLOBAL partagé par d'autres appels REST : on ignore l'erreur si le classement a DÉJÀ
# répondu (elle ne nous concerne alors pas) — sinon un échec d'un autre écran effacerait la liste.
func _on_leaderboard_failed(_message: String) -> void:
	if not is_inside_tree():
		return
	# §8.98 : libère la file (sinon une requête en vol échouée bloquerait toutes les suivantes).
	_fetch_pending = {}
	_pump_fetch_queue()
	if not _server_board.is_empty():
		return
	_loading_more = false
	_offline_fallback = true
	_refresh()
	_set_status(tr("COMMON_OFFLINE_LOCAL"))

# =========================================================
# FILE DE REQUÊTES (§8.98) — une seule requête leaderboard en vol à la fois
# =========================================================
# Le signal `leaderboard_loaded` est GLOBAL et ne rappelle pas les paramètres de la requête : la
# seule façon SÛRE d'associer une réponse à sa tranche est de n'avoir qu'UNE requête en vol.
func _queue_fetch(division: String, tier: String, offset: int) -> void:
	var req := {"division": division, "tier": tier, "offset": offset}
	if _fetch_pending == req or _fetch_queue.has(req):
		return  # déjà demandé (double-clic, resélection rapide).
	_fetch_queue.append(req)
	_pump_fetch_queue()

func _pump_fetch_queue() -> void:
	if not _fetch_pending.is_empty() or _fetch_queue.is_empty():
		return
	_fetch_pending = _fetch_queue.pop_front()
	NetworkManager.fetch_leaderboard(PAGE_SIZE, int(_fetch_pending["offset"]), SCOPE,
		str(_fetch_pending["division"]), str(_fetch_pending["tier"]))

# Clé de cache d'une tranche. L'échelon du PODIUM d'une division est toujours le I (spec §8.98) —
# sauf ÉLITE, ladder ouvert sans échelon.
func _cache_key(division: String, tier: String) -> String:
	return "%s|%s" % [division, tier]

func _podium_tier(division: String) -> String:
	return "" if division == "ELITE" else "I"

# --- Classement serveur (R3 — §9.2) -----------------------------------------
# Mappe les entrées backend vers le format d'affichage ({name, level, wins, rank}) puis redessine.
# Lecture défensive : clés canoniques §9.2 (level/wins/rank) en priorité, repli sur les alias
# historiques (niveau/stats_victoires). Le bloc `me` fixe l'identité + le rang global de l'opérateur.
func _on_leaderboard_loaded(entries: Array, me: Dictionary) -> void:
	if not is_inside_tree():
		return  # garde défensive : signal GLOBAL (partagé avec le top-3 du menu) reçu hors arbre.
	# §8.98 : réponse associée à la requête EN VOL de la file (une seule à la fois). Réponse sans
	# requête de notre part (émission croisée d'un autre écran pendant un changement de scène) → ignorée.
	var req := _fetch_pending
	_fetch_pending = {}
	if req.is_empty():
		_pump_fetch_queue()
		return
	_me = me if typeof(me) == TYPE_DICTIONARY else {}
	# Bloc saison { id, ends_at, divisions?, rules? } (M6/§8.95) — stocké par NetworkManager à côté du
	# signal (sa signature (entries, me) reste inchangée pour ses écouteurs existants).
	_season_info = NetworkManager.last_leaderboard_season
	# Identité/valeurs locales depuis le bloc me (rang global fiable même si l'opérateur est hors page).
	if not _me.is_empty():
		if _me.has("username") and str(_me["username"]) != "":
			_local_name = str(_me["username"])
		_local_level = int(_me.get("level", _local_level))
		_local_wins = int(_me.get("wins", _local_wins))
	# Bouton RÈGLES : révélé UNIQUEMENT si le serveur publie le barème (repli : masqué, §8.95).
	if _rules_button != null:
		var rules = _season_info.get("rules", {})
		_rules_button.visible = typeof(rules) == TYPE_DICTIONARY and not rules.is_empty()

	if str(req.get("division", "")) != "":
		_store_tier_page(req, entries)
	else:
		_apply_global_page(entries)

	_pump_fetch_queue()
	_build_columns_header()
	_refresh()
	_set_status(_season_status_line())

# Réponse GLOBALE (amorçage / repli liste plate). C'est elle qui décide du MODE de l'écran :
# `season.divisions` présent → navigation par division (§8.98) ; absent → liste plate historique.
func _apply_global_page(entries: Array) -> void:
	# PAGINATION legacy (§8.95) : une page suivante s'AJOUTE ; une 1re page (offset 0) REMPLACE.
	if not _loading_more:
		_server_board.clear()
	for e in entries:
		if typeof(e) == TYPE_DICTIONARY:
			_server_board.append(_map_entry(e))
	_end_reached = entries.size() < PAGE_SIZE
	_offset = _server_board.size()
	_loading_more = false
	# Repli LEGACY (M6, convention §9.2 client défensif) : réponse sans `division` → backend antérieur.
	_has_division_data = entries.size() > 0 and typeof(entries[0]) == TYPE_DICTIONARY \
		and entries[0].has("division")
	# Bascule en NAVIGATION PAR DIVISION (§8.98), une seule fois : division du joueur si connue
	# (échelon du joueur présélectionné — il se voit d'emblée), sinon ÉLITE (vitrine du haut du ladder).
	var divs = _season_info.get("divisions", [])
	if not _browse_mode and typeof(divs) == TYPE_ARRAY and not divs.is_empty():
		_browse_mode = true
		var my_div := str(_me.get("division", ""))
		if DIVISION_COLORS.has(my_div):
			_select_division(my_div, str(_me.get("division_tier", "")))
		else:
			_select_division("ELITE", "")

# Réponse de TRANCHE (division+échelon) : rangée dans le cache. offset 0 = remplace, sinon append.
func _store_tier_page(req: Dictionary, entries: Array) -> void:
	var key := _cache_key(str(req["division"]), str(req["tier"]))
	var bucket: Dictionary = _tier_cache.get(key, {"entries": [], "end_reached": false})
	if int(req["offset"]) == 0:
		bucket["entries"] = []
	for e in entries:
		if typeof(e) == TYPE_DICTIONARY:
			bucket["entries"].append(_map_entry(e))
	bucket["end_reached"] = entries.size() < PAGE_SIZE
	_tier_cache[key] = bucket

# Mapping COMMUN d'une entrée serveur vers la forme d'affichage (lecture défensive §9.2/§5).
func _map_entry(e: Dictionary) -> Dictionary:
	return {
		"name": str(e.get("username", "—")),
		"level": int(e.get("level", e.get("niveau", 1))),
		"wins": int(e.get("wins", e.get("stats_victoires", 0))),
		"rank": int(e.get("rank", 0)),
		# M6 : points de saison + division (défauts sûrs sur un backend antérieur).
		"season_points": int(e.get("season_points", 0)),
		"division": str(e.get("division", "")),
		# §8.95 : échelon (défaut sûr — backend antérieur).
		"division_tier": str(e.get("division_tier", "")),
	}

# Ligne de statut (M6). §8.95 : « VOTRE DIVISION » et le compte à rebours ne sont plus relégués ici
# — ils sont mis en avant par la carte « VOTRE RANG » en tête. On ne les répète DANS le statut que
# si cette carte n'a pas pu être construite (backend antérieur, sans `division_tier`).
func _season_status_line() -> String:
	# §8.98 : en navigation par division, la ligne du bas n'a plus rien à dire de la liste plate
	# globale (l'attente/le vide de la TRANCHE affichée vivent dans la liste elle-même).
	if _browse_mode:
		return tr("LEADERBOARD_STATUS_LOCATED")
	if _server_board.is_empty():
		return tr("LEADERBOARD_EMPTY")
	var base := tr("LEADERBOARD_STATUS_LOCATED")
	if not _has_division_data:
		return base
	if not _me_rank_info().is_empty():
		return base  # la carte VOTRE RANG porte déjà division + échelon + fin de saison.
	var parts: Array = []
	if not _me.is_empty() and str(_me.get("division", "")) != "":
		parts.append(tr("LEADERBOARD_MY_DIVISION").format({"division": str(_me["division"])}))
	var days := _season_days_left()
	if days > 0:
		parts.append(tr("LEADERBOARD_SEASON_END").format({"days": days}))
	if parts.is_empty():
		return base
	return " · ".join(PackedStringArray(parts))

func _season_days_left() -> int:
	var ends := str(_season_info.get("ends_at", ""))
	if ends == "":
		return 0
	var end_epoch := int(Time.get_unix_time_from_datetime_string(ends.trim_suffix("Z")))
	return maxi(0, int((end_epoch - int(Time.get_unix_time_from_system())) / 86400))

# =========================================================
# LADDER RP (§8.95) — carte « VOTRE RANG », bande des divisions, règles, pagination
# =========================================================
# Emplacements insérés EN TÊTE du panneau (juste après le filet de l'en-tête, avant le podium).
# Ils restent VIDES tant que le serveur ne fournit pas les données RP → un backend antérieur affiche
# exactement l'écran d'avant (repli §9.2).
func _build_rp_slots() -> void:
	var root := podium_box.get_parent()
	if root == null:
		return
	_rank_card_slot = VBoxContainer.new()
	_rank_card_slot.add_theme_constant_override("separation", 8)
	root.add_child(_rank_card_slot)
	_divisions_slot = VBoxContainer.new()
	_divisions_slot.add_theme_constant_override("separation", 6)
	root.add_child(_divisions_slot)
	# Ordre voulu : HeaderBar(0), FiletTop(1), [VOTRE RANG](2), [DIVISIONS](3), PodiumEyebrow…
	root.move_child(_rank_card_slot, 2)
	root.move_child(_divisions_slot, 3)

	# Références aux eyebrows de la SCÈNE (nœuds nommés dans le .tscn — fiables, contrairement aux
	# noms auto-générés des nœuds créés par code, piège §8.95) : le podium devient contextuel et
	# l'eyebrow de liste cède la place aux onglets d'échelon en navigation (§8.98).
	_podium_eyebrow = root.get_node_or_null("PodiumEyebrow") as Label
	_ranking_eyebrow = root.get_node_or_null("RankingEyebrow") as Label

	# Rangée des onglets d'échelon (§8.98), insérée À LA PLACE de l'eyebrow de liste (juste après
	# lui) — reconstruite à chaque sélection par _rebuild_tier_tabs, masquée en repli plat.
	_tier_tabs_row = HBoxContainer.new()
	_tier_tabs_row.add_theme_constant_override("separation", 4)
	_tier_tabs_row.visible = false
	root.add_child(_tier_tabs_row)
	if _ranking_eyebrow != null:
		root.move_child(_tier_tabs_row, _ranking_eyebrow.get_index() + 1)

# Bouton « ℹ RÈGLES » (barre d'en-tête) — masqué par défaut, révélé si `season.rules` arrive.
func _build_rules_button() -> void:
	if header_bar == null:
		return
	_rules_button = Button.new()
	_rules_button.text = "LEADERBOARD_RULES"  # clé brute -> auto-traduction
	_rules_button.visible = false
	_rules_button.focus_mode = Control.FOCUS_NONE
	_rules_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rules_button.add_theme_font_override("font", _font)
	_rules_button.add_theme_font_size_override("font_size", 14)
	WarzoneUI.apply_ghost_button(_rules_button)
	WarzoneUI.wire_button_feedback(_rules_button)  # §8.96 — SFX + lueur de survol
	_rules_button.pressed.connect(_open_rules)
	header_bar.add_child(_rules_button)

# Pied de liste « AFFICHER PLUS » : l'API supportait DÉJÀ limit/offset, seul le client figeait 20/0.
func _build_more_button() -> void:
	var root := podium_box.get_parent()
	if root == null:
		return
	_more_button = Button.new()
	_more_button.text = "LEADERBOARD_SHOW_MORE"  # clé brute -> auto-traduction
	_more_button.visible = false
	_more_button.focus_mode = Control.FOCUS_NONE
	_more_button.add_theme_font_override("font", _font)
	_more_button.add_theme_font_size_override("font_size", 14)
	WarzoneUI.apply_ghost_button(_more_button)
	WarzoneUI.wire_button_feedback(_more_button)  # §8.96 — SFX + lueur de survol
	_more_button.pressed.connect(_on_more_pressed)
	root.add_child(_more_button)
	# Juste avant la ligne de statut (dernier enfant).
	if status_label != null and status_label.get_parent() == root:
		root.move_child(_more_button, status_label.get_index())

func _on_more_pressed() -> void:
	if _browse_mode:
		# §8.98 : pagination PAR TRANCHE — l'offset est la taille déjà chargée de la tranche affichée.
		var bucket: Dictionary = _tier_cache.get(_cache_key(_selected_division, _selected_tier), {})
		if bucket.is_empty() or bool(bucket.get("end_reached", false)):
			return
		_queue_fetch(_selected_division, _selected_tier, bucket["entries"].size())
		return
	if _loading_more or _end_reached:
		return
	_loading_more = true
	_more_button.disabled = true
	_queue_fetch("", "", _offset)

# =========================================================
# SÉLECTION DIVISION / ÉCHELON (§8.98)
# =========================================================
# Clic sur une division de la bande → on affiche SON classement : podium = sous-division I (spec —
# il ne suit PAS l'onglet sélectionné), liste = échelon sélectionné (3 onglets I/II/III ; ÉLITE n'en
# a pas). `wanted_tier` : échelon à présélectionner ("" → I ; toujours "" en ÉLITE).
func _select_division(division: String, wanted_tier: String = "") -> void:
	_selected_division = division
	if division == "ELITE":
		_selected_tier = ""
	else:
		_selected_tier = wanted_tier if wanted_tier in ["I", "II", "III"] else "I"
	# Tranches nécessaires : celle du PODIUM (échelon I) + celle de la LISTE (si différente).
	var podium_key := _cache_key(division, _podium_tier(division))
	if not _tier_cache.has(podium_key):
		_queue_fetch(division, _podium_tier(division), 0)
	var list_key := _cache_key(division, _selected_tier)
	if list_key != podium_key and not _tier_cache.has(list_key):
		_queue_fetch(division, _selected_tier, 0)
	_refresh()

func _on_division_clicked(division: String) -> void:
	AudioManager.play_sfx("click")
	if division == _selected_division:
		return
	_select_division(division)

func _on_tier_tab_pressed(tier: String) -> void:
	if tier == _selected_tier:
		return
	AudioManager.play_sfx("click")
	_selected_tier = tier
	var key := _cache_key(_selected_division, tier)
	if not _tier_cache.has(key):
		_queue_fetch(_selected_division, tier, 0)
	_refresh()

# Entrées de la tranche affichée (depuis le cache). Marque l'opérateur local à la volée (le pseudo
# peut arriver APRÈS la tranche, via /auth/me) — pas d'ajout artificiel de `me` hors de sa tranche :
# son rang global n'aurait aucun sens dans un classement de sous-division.
func _tier_entries(division: String, tier: String) -> Array:
	var bucket: Dictionary = _tier_cache.get(_cache_key(division, tier), {})
	var rows: Array = bucket.get("entries", [])
	var local_upper := _local_name.to_upper()
	for r in rows:
		r["is_local"] = str(r.get("name", "")).to_upper() == local_upper
	return rows

# Le podium de la division sélectionnée = top 3 de sa sous-division I (ÉLITE : de son ladder).
func _podium_entries() -> Array:
	return _tier_entries(_selected_division, _podium_tier(_selected_division))

# `rank_info` du bloc `me` — renvoie {} si le backend est antérieur au ladder RP (§8.95).
func _me_rank_info() -> Dictionary:
	if _me.is_empty() or not _me.has("division_tier"):
		return {}
	return {
		"division": str(_me.get("division", "")),
		"tier": str(_me.get("division_tier", "")),
		"rp_in_tier": int(_me.get("rp_in_tier", 0)),
		"tier_span": int(_me.get("tier_span", 0)),
		"points": int(_me.get("season_points", 0)),
		"rank": int(_me.get("rank", 0)),
	}

# Carte « VOTRE RANG » : badge hexagonal à la couleur de division + gros libellé (« OR II »), barre
# de progression rp_in_tier/tier_span (en ÉLITE : total RP, SANS barre — tier_span vaut 0), rang
# global #N, compte à rebours de fin de saison, chip « dernier match ». Repli : slot vidé.
func _rebuild_rank_card() -> void:
	if _rank_card_slot == null:
		return
	_clear(_rank_card_slot)
	var info := _me_rank_info()
	if info.is_empty():
		return  # backend antérieur au ladder RP → pas de carte.

	var division := str(info["division"])
	var color: Color = DIVISION_COLORS.get(division, ACCENT)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_card_style(color))
	_rank_card_slot.add_child(card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	card.add_child(row)

	# Badge hexagonal à la couleur de la division (échelon au centre ; « ★ » en ÉLITE, sans échelon).
	var tier := str(info["tier"])
	var badge := WarzoneUI.make_hex_badge(tier if tier != "" else "★", _font, 20, color, GUNMETAL, 58.0)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)

	# Bloc central : eyebrow VOTRE RANG → libellé de rang → barre de progression.
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 2)
	row.add_child(mid)
	mid.add_child(_mini_label("LEADERBOARD_YOUR_RANK", 13, ACCENT, true))

	var label_lbl := Label.new()
	label_lbl.text = _division_label(division, tier)
	label_lbl.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	label_lbl.add_theme_font_override("font", _font)
	label_lbl.add_theme_font_size_override("font_size", 30)
	label_lbl.add_theme_color_override("font_color", color)
	mid.add_child(label_lbl)

	var span := int(info["tier_span"])
	if span > 0:
		# Barre de progression vers l'échelon suivant.
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 8)
		bar.min_value = 0.0
		bar.max_value = float(span)
		bar.value = float(clampi(int(info["rp_in_tier"]), 0, span))
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(1, 1, 1, 0.08)
		bg.set_corner_radius_all(0)
		var fg := StyleBoxFlat.new()
		fg.bg_color = color
		fg.set_corner_radius_all(0)
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", fg)
		mid.add_child(bar)
		mid.add_child(_mini_label(tr("LEADERBOARD_RP_IN_TIER").format(
			{"cur": int(info["rp_in_tier"]), "max": span}), 12, MUTED))
	else:
		# ÉLITE : ladder ouvert → aucune barre, on affiche le TOTAL de RP.
		mid.add_child(_mini_label(tr("LEADERBOARD_RP_TOTAL").format({"n": int(info["points"])}), 14, color))

	# Bloc droit : rang mondial + fin de saison + ΔRP du dernier match.
	var right := VBoxContainer.new()
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_theme_constant_override("separation", 2)
	row.add_child(right)
	right.add_child(_mini_label("LEADERBOARD_GLOBAL_RANK", 12, ACCENT, true, HORIZONTAL_ALIGNMENT_RIGHT))
	right.add_child(_mini_label("#%d" % int(info["rank"]), 26, TEXT, false, HORIZONTAL_ALIGNMENT_RIGHT))
	var days := _season_days_left()
	if days > 0:
		right.add_child(_mini_label(tr("LEADERBOARD_SEASON_END").format({"days": days}),
			12, MUTED, false, HORIZONTAL_ALIGNMENT_RIGHT))
	if _last_rp_delta_known:
		right.add_child(_mini_label(
			tr("LEADERBOARD_LAST_DELTA").format({"delta": _signed(_last_rp_delta)}), 12,
			GOLD if _last_rp_delta >= 0 else DANGER, false, HORIZONTAL_ALIGNMENT_RIGHT))

	WarzoneUI.add_corner_notches(card, 14.0, color)

# Bande des 5 divisions (§8.98 : c'est désormais LA navigation du classement) : seuil (floor) +
# effectif ; badge du joueur = encoches or ; badge SÉLECTIONNÉ = fond teinté + liseré plein. Chaque
# badge est CLIQUABLE → affiche le classement de sa division (podium sous-division I + onglets).
# Repli : `season` sans `divisions` (backend antérieur) → bande masquée, liste plate.
func _rebuild_divisions_band() -> void:
	if _divisions_slot == null:
		return
	_clear(_divisions_slot)
	var divs = _season_info.get("divisions", [])
	if typeof(divs) != TYPE_ARRAY or divs.is_empty():
		return
	_divisions_slot.add_child(_mini_label("LEADERBOARD_DIVISIONS", 13, ACCENT, true))
	var band := HBoxContainer.new()
	band.add_theme_constant_override("separation", 8)
	_divisions_slot.add_child(band)
	var mine := str(_me.get("division", ""))
	for d in divs:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var did := str(d.get("id", ""))
		band.add_child(_make_division_badge(d, did == mine, did == _selected_division))

func _make_division_badge(d: Dictionary, is_mine: bool, is_selected: bool) -> PanelContainer:
	var did := str(d.get("id", ""))
	var color: Color = DIVISION_COLORS.get(did, MUTED)
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	# Sélectionné > mien > neutre (un badge peut être les deux : fond de sélection + encoches or).
	sb.bg_color = Color(color, 0.26) if is_selected else (Color(color, 0.12) if is_mine else SURFACE)
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(2 if (is_selected or is_mine) else 1)
	sb.border_color = color if (is_selected or is_mine) else Color(color, 0.4)
	sb.set_content_margin_all(8.0)
	card.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	v.add_child(_mini_label(_division_name(did), 14, color, false, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_mini_label(tr("LEADERBOARD_DIVISION_FLOOR").format({"n": int(d.get("floor", 0))}),
		11, MUTED, false, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_mini_label(tr("LEADERBOARD_DIVISION_PLAYERS").format({"n": int(d.get("players", 0))}),
		11, TEXT if (is_mine or is_selected) else MUTED, false, HORIZONTAL_ALIGNMENT_CENTER))

	# Bouton transparent superposé : capte le clic sur tout le badge (le contenu ignore la souris —
	# même patron que les cartes de mode du menu). Ajouté en DERNIER → au-dessus, donc cliquable.
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty)
	btn.add_theme_stylebox_override("hover", empty)
	btn.add_theme_stylebox_override("pressed", empty)
	btn.add_theme_stylebox_override("focus", empty)
	btn.pressed.connect(func() -> void: _on_division_clicked(did))
	btn.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	card.add_child(btn)

	if is_mine:
		WarzoneUI.add_corner_notches(card, 8.0, GOLD)
	return card

# --- Panneau RÈGLES : rendu DEPUIS `season.rules` (jamais de barème en dur côté client) ----------
func _open_rules() -> void:
	var rules = _season_info.get("rules", {})
	if typeof(rules) != TYPE_DICTIONARY or rules.is_empty():
		return
	if _rules_overlay == null:
		_build_rules_overlay()
	_populate_rules(rules)
	_rules_overlay.visible = true

func _close_rules() -> void:
	if _rules_overlay:
		_rules_overlay.visible = false

func _build_rules_overlay() -> void:
	_rules_overlay = ColorRect.new()
	_rules_overlay.name = "RulesOverlay"
	_rules_overlay.color = Color(0, 0, 0, 0.6)
	_rules_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rules_overlay.visible = false
	_rules_overlay.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_close_rules())
	add_child(_rules_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rules_overlay.add_child(center)

	var pan := PanelContainer.new()
	pan.name = "RulesPanel"
	pan.custom_minimum_size = Vector2(560, 0)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.058824, 0.07451, 0.094118, 0.98)
	st.set_corner_radius_all(0)
	st.set_border_width_all(2)
	st.border_color = ACCENT
	st.set_content_margin_all(24.0)
	st.shadow_color = Color(0, 0, 0, 0.5)
	st.shadow_size = 10
	pan.add_theme_stylebox_override("panel", st)
	center.add_child(pan)
	WarzoneUI.add_corner_notches(pan)

	_rules_body = VBoxContainer.new()
	_rules_body.name = "Body"
	_rules_body.add_theme_constant_override("separation", 8)
	pan.add_child(_rules_body)

func _populate_rules(rules: Dictionary) -> void:
	var body := _rules_body
	if body == null:
		return
	_clear(body)
	body.add_child(_mini_label("LEADERBOARD_RULES_TITLE", 22, ACCENT, true))
	WarzoneUI.add_filet(body)

	# Barème par place — rendu DEPUIS le serveur (rp_by_rank), jamais en dur.
	body.add_child(_mini_label("LEADERBOARD_RULES_BY_RANK", 13, ACCENT, true))
	var by_rank = rules.get("rp_by_rank", [])
	if typeof(by_rank) == TYPE_ARRAY:
		for i in by_rank.size():
			var delta := int(by_rank[i])
			var place := (tr("LEADERBOARD_RULES_PLACE_FIRST") if i == 0
				else tr("LEADERBOARD_RULES_PLACE").format({"place": i + 1}))
			body.add_child(_rules_row(place, _signed(delta) + " RP", GOLD if delta >= 0 else DANGER))

	WarzoneUI.add_filet(body)
	body.add_child(_mini_label(tr("LEADERBOARD_RULES_ELIM").format(
		{"n": int(rules.get("elim_bonus", 0)), "cap": int(rules.get("elim_cap", 0))}), 13, TEXT))
	body.add_child(_mini_label(tr("LEADERBOARD_RULES_BRONZE").format(
		{"n": int(rules.get("bronze_loss_divisor", 1))}), 13, TEXT))
	if bool(rules.get("division_floor_lock", false)):
		body.add_child(_mini_label("LEADERBOARD_RULES_FLOOR", 13, TEXT, true))
	body.add_child(_mini_label(tr("LEADERBOARD_RULES_TIER").format(
		{"n": int(rules.get("tier_rp", 0))}), 13, TEXT))
	body.add_child(_mini_label("LEADERBOARD_RULES_UNRANKED", 12, MUTED, true))

	# Récompenses de fin de saison (§8.98) : `rewards_coins` = ENVELOPPE par division, répartie entre
	# les podiums des sous-divisions selon `reward_splits` — tout vient du serveur, rien en dur.
	var rewards = rules.get("rewards_coins", {})
	if typeof(rewards) == TYPE_DICTIONARY and not rewards.is_empty():
		WarzoneUI.add_filet(body)
		body.add_child(_mini_label("LEADERBOARD_RULES_REWARDS", 13, ACCENT, true))
		var splits = rules.get("reward_splits", {})
		if typeof(splits) == TYPE_DICTIONARY and not splits.is_empty():
			# Backend ≥ §8.98 : primes aux PODIUMS uniquement + répartitions I/II/III et 1ᵉʳ/2ᵉ/3ᵉ.
			body.add_child(_mini_label("LEADERBOARD_RULES_REWARDS_PODIUM", 12, MUTED, true))
			var t = splits.get("tiers", [])
			if typeof(t) == TYPE_ARRAY and t.size() >= 3:
				body.add_child(_mini_label(tr("LEADERBOARD_RULES_SPLIT_TIERS").format(
					{"one": int(t[0]), "two": int(t[1]), "three": int(t[2])}), 12, TEXT))
			var p = splits.get("podium", [])
			if typeof(p) == TYPE_ARRAY and p.size() >= 3:
				body.add_child(_mini_label(tr("LEADERBOARD_RULES_SPLIT_PODIUM").format(
					{"one": int(p[0]), "two": int(p[1]), "three": int(p[2])}), 12, TEXT))
		for did in rewards:
			body.add_child(_rules_row(_division_name(str(did)), "◈ %d" % int(rewards[did]),
				DIVISION_COLORS.get(str(did), GOLD)))

func _rules_row(label: String, value: String, value_color: Color) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var l := _mini_label(label, 14, MUTED)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(_mini_label(value, 15, value_color, false, HORIZONTAL_ALIGNMENT_RIGHT))
	return h

# Nom AFFICHÉ d'une division. Les IDS réseau sont ASCII (« ELITE ») ; l'affichage passe par une
# clé i18n (valeur du mapping = clé, traduite au point d'affichage : DIVISION_ELITE → « ÉLITE » fr,
# « ELITE » en/it) — miroir de seasons.DIVISION_LABELS côté serveur, qui compose déjà `rp_label` =
# « ÉLITE » pour le Rapport Post-Op. Sans ce mapping, le Rapport disait « ÉLITE » et le Classement
# « ELITE ». Les ids NON mappés (BRONZE/ARGENT/OR/PLATINE) restent affichés tels quels.
const DIVISION_LABELS := {"ELITE": "DIVISION_ELITE"}

func _division_name(division: String) -> String:
	if DIVISION_LABELS.has(division):
		return tr(str(DIVISION_LABELS[division]))
	return division

# Libellé « OR II » / « ÉLITE » — miroir de seasons.rank_info().label côté serveur (le bloc `me` ne
# transporte que division + division_tier, pas le libellé composé).
func _division_label(division: String, tier: String) -> String:
	if division == "":
		return "—"
	if tier == "":
		return _division_name(division)
	return tr("DIVISION_TIER_FMT").format({"division": _division_name(division), "tier": tier})

# « +30 » / « -20 » (le signe + n'est pas posé par %d sur les positifs).
func _signed(v: int) -> String:
	return ("+%d" % v) if v > 0 else str(v)

# Petit Label de la charte. `is_key` = texte encore BRUT (clé i18n auto-traduite par Godot) ; sinon
# le texte est DÉJÀ composé/traduit → auto-traduction désactivée.
func _mini_label(text: String, size: int, color: Color, is_key: bool = false,
		align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	if not is_key:
		l.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l


# --- Onglets d'ÉCHELON (§8.98) — une rangée I / II / III au-dessus de la liste ------------------
# Remplacent l'eyebrow « CLASSEMENT GÉNÉRAL » en navigation par division : chaque onglet ouvre le
# classement de SA sous-division (le podium, lui, reste celui de la sous-division I — spec).
# (Les ex-onglets SAISON/GÉNÉRAL de la barre d'en-tête ont été retirés en §8.98 : l'écran est tout
# entier en scope SAISON. Le style de pastille est repris tel quel pour les onglets d'échelon.)
func _rebuild_tier_tabs() -> void:
	if _tier_tabs_row == null:
		return
	_clear(_tier_tabs_row)
	# ÉLITE = ladder ouvert, pas de sous-divisions → aucun onglet.
	var show := _browse_mode and _selected_division != "" and _selected_division != "ELITE"
	_tier_tabs_row.visible = show
	if not show:
		return
	for tier in ["I", "II", "III"]:
		var btn := _make_pill_tab(_division_label(_selected_division, tier), tier == _selected_tier)
		var this_tier: String = tier  # capture de boucle (sinon toutes les lambdas verraient "III").
		btn.pressed.connect(func() -> void: _on_tier_tab_pressed(this_tier))
		_tier_tabs_row.add_child(btn)

func _make_pill_tab(text: String, active: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED  # libellé composé (« OR II »).
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 15)
	# §8.96 : feedback UNIFORME (SFX survol/clic + lueur cyan) — n'écrase pas _style_pill_tab.
	WarzoneUI.wire_button_feedback(btn)
	_style_pill_tab(btn, active)
	return btn

func _style_pill_tab(btn: Button, active: bool) -> void:
	if btn == null:
		return
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.bg_color = Color(ACCENT, 0.18) if active else Color(0, 0, 0, 0)
	if active:
		sb.border_width_bottom = 3
		sb.border_color = ACCENT
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(ACCENT, 0.14)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", sb)
	btn.add_theme_color_override("font_color", TEXT if active else MUTED)

# --- Profil / lecture défensive --------------------------------------------
func _on_profile_loaded(data: Dictionary):
	if data.has("username") and str(data["username"]) != "":
		_local_name = str(data["username"])
	_local_level = _read_int(data, ["niveau", "level"], _local_level)
	# Le backend (UserResponse) expose stats_victoires : on le lit en priorité (repli défensif ensuite).
	_local_wins = _read_int(data, ["stats_victoires", "victoires", "wins"], _local_wins)
	_refresh()
	# §8.96 : /auth/me répond souvent AVANT le classement — ne pas écraser l'état d'attente par
	# « OPÉRATEUR LOCALISÉ » alors qu'aucun classement n'est encore affiché.
	if not _server_board.is_empty() or _offline_fallback:
		_set_status(tr("LEADERBOARD_STATUS_LOCATED"))

# Lit la première clé présente d'une liste et la convertit en int (piège float JSON §5, CLAUDE.md).
func _read_int(data: Dictionary, keys: Array, fallback: int) -> int:
	for k in keys:
		if data.has(k):
			return int(data[k])
	return fallback

# --- Construction du classement (Règle d'Or §6.1, VUE pure) ----------------
# Deux chemins : (1) classement serveur §9.2 (entries avec rang global) → on RESPECTE l'ordre et les
# rangs serveur, on surligne/ajoute l'opérateur via le bloc `me` ; (2) repli (mock de prévisualisation
# OU ancien backend « liste plate » sans rang) → tri & rang calculés côté client.
func _build_entries() -> Array:
	if not _server_board.is_empty() and int(_server_board[0].get("rank", 0)) > 0:
		return _build_server_entries()
	return _build_ranked_locally()

# Chemin SERVEUR §9.2 : ordre et rangs du serveur respectés tels quels. L'opérateur courant est
# surligné s'il figure dans la page ; sinon il est AJOUTÉ en bas avec son rang GLOBAL réel (bloc me).
func _build_server_entries() -> Array:
	var rows: Array = _server_board.duplicate(true)
	var local_upper := _local_name.to_upper()
	var present := false
	for r in rows:
		if str(r.get("name", "")).to_upper() == local_upper:
			r["is_local"] = true   # on NE touche PAS à level/wins/rank : le serveur fait foi.
			present = true
			break
	# Opérateur hors de la page renvoyée : on l'ajoute distinctement avec son rang global (si connu).
	if not present and not _me.is_empty():
		rows.append({"name": _local_name, "level": _local_level, "wins": _local_wins,
			"rank": int(_me.get("rank", 0)), "is_local": true,
			"season_points": int(_me.get("season_points", 0)),
			"division": str(_me.get("division", "")),
			"division_tier": str(_me.get("division_tier", ""))})
	return rows

# Chemin REPLI : fusionne la source (mock, ou liste plate legacy) + l'opérateur local, trie desc.
# par victoires (départage par niveau), attribue les rangs côté client.
# §8.96 : le mock n'est utilisé QU'APRÈS un échec réseau avéré (_offline_fallback) — tant qu'on
# attend la réponse, on ne rend RIEN (état « SYNCHRONISATION… »).
func _build_ranked_locally() -> Array:
	if _server_board.is_empty() and not _offline_fallback:
		return []
	var source: Array = _server_board if not _server_board.is_empty() else _mock_board
	var rows: Array = source.duplicate(true)
	var local_upper := _local_name.to_upper()
	var present := false
	for r in rows:
		if str(r.get("name", "")).to_upper() == local_upper:
			r["wins"] = _local_wins
			r["level"] = _local_level
			r["is_local"] = true
			present = true
			break
	if not present:
		rows.append({"name": _local_name, "level": _local_level, "wins": _local_wins, "is_local": true})
	# Tri serveur simulé : victoires décroissantes (départage par niveau).
	rows.sort_custom(func(a, b):
		if int(a.get("wins", 0)) == int(b.get("wins", 0)):
			return int(a.get("level", 0)) > int(b.get("level", 0))
		return int(a.get("wins", 0)) > int(b.get("wins", 0)))
	var rank := 1
	for r in rows:
		r["rank"] = rank
		rank += 1
	return rows

# §8.118 — Vrai quand les lignes affichées sont les pseudos FICTIFS de `_mock_board`. Prédicat
# MIROIR de la sélection de source de `_build_ranked_locally` ci-dessus (`_server_board` vide ET
# échec réseau avéré) : on ne se contente pas de `_offline_fallback`, qui n'est jamais remis à
# false — un fetch réussi APRÈS un échec (clic sur une division) rendrait de VRAIES données que
# le seul drapeau ferait passer pour du mock. La navigation par division (`_browse_mode`) lit
# `_tier_cache`, alimenté exclusivement par le serveur : elle n'est donc jamais fictive.
func _showing_mock() -> bool:
	return _offline_fallback and _server_board.is_empty() and not _browse_mode

func _refresh() -> void:
	_rebuild_rank_card()      # §8.95 — carte « VOTRE RANG » (en tête)
	_rebuild_divisions_band() # §8.95/§8.98 — bande des 5 divisions (cliquable en navigation)
	_rebuild_tier_tabs()      # §8.98 — onglets d'échelon I/II/III de la division sélectionnée
	if _browse_mode:
		_populate_podium(_podium_entries())
		_populate_ranking(_tier_entries(_selected_division, _selected_tier))
	else:
		# Repli LISTE PLATE (backend antérieur / hors ligne) — chemins historiques inchangés.
		var entries := _build_entries()
		_populate_podium(entries)
		_populate_ranking(entries)
	_update_podium_eyebrow()
	_update_more_button()

# Eyebrow du podium (§8.98) : « PODIUM — OR I » en navigation (le podium est celui de la
# sous-division I de la division sélectionnée) ; clé historique en repli plat.
func _update_podium_eyebrow() -> void:
	if _podium_eyebrow == null:
		return
	if _browse_mode and _selected_division != "":
		_podium_eyebrow.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
		_podium_eyebrow.text = tr("LEADERBOARD_PODIUM_DIV").format(
			{"label": _division_label(_selected_division, _podium_tier(_selected_division))})
	else:
		_podium_eyebrow.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_INHERIT
		_podium_eyebrow.text = "LEADERBOARD_PODIUM"  # clé brute -> auto-traduction
	# L'eyebrow de la liste est REMPLACÉ par les onglets d'échelon en navigation.
	if _ranking_eyebrow != null:
		_ranking_eyebrow.visible = not _browse_mode

# Visibilité/état du bouton « AFFICHER PLUS » selon le mode (§8.98 : par tranche ; legacy : global).
func _update_more_button() -> void:
	if _more_button == null:
		return
	if _browse_mode:
		var bucket: Dictionary = _tier_cache.get(_cache_key(_selected_division, _selected_tier), {})
		_more_button.disabled = false
		_more_button.visible = not bucket.is_empty() \
			and not bool(bucket.get("end_reached", false)) \
			and not bucket.get("entries", []).is_empty()
	else:
		_more_button.disabled = false
		_more_button.visible = not _end_reached and not _server_board.is_empty()

# --- Podium top 3 (cartes générées en code, or pour le #1) -----------------
func _populate_podium(entries: Array) -> void:
	_clear(podium_box)
	var top := mini(3, entries.size())
	for i in top:
		podium_box.add_child(_make_podium_card(entries[i]))

# Carte de podium : badge hexagonal du rang (or pour #1, cyan pour #2/#3) + pseudo + victoires.
func _make_podium_card(entry: Dictionary) -> PanelContainer:
	var rank := int(entry.get("rank", 0))
	var is_first := rank == 1
	var is_local := bool(entry.get("is_local", false))
	var accent: Color = GOLD if is_first else ACCENT

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_card_style(accent))
	card.custom_minimum_size = Vector2(0, 150 if is_first else 132)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)

	# Badge hexagonal du rang (mutualisé via le helper §2 — make_hex_badge).
	var badge_fill: Color = GOLD if is_first else ACCENT
	var badge_text: Color = GUNMETAL
	var badge := WarzoneUI.make_hex_badge("#" + str(rank), _font, 26, badge_fill, badge_text, 64.0 if is_first else 54.0)
	var badge_holder := CenterContainer.new()
	badge_holder.add_child(badge)
	v.add_child(badge_holder)

	# Pseudo (cyan si c'est l'opérateur local).
	var name_label := Label.new()
	name_label.text = str(entry.get("name", "—")).to_upper()
	name_label.add_theme_font_override("font", _font)
	name_label.add_theme_font_size_override("font_size", 22 if is_first else 19)
	name_label.add_theme_color_override("font_color", ACCENT if is_local else TEXT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_label)

	# Valeur mise en avant (or) — §8.95/§8.98 : RP dès que le backend fournit le ladder saisonnier
	# (la clé de TRI) ; VICTOIRES seulement en repli mock/pré-M6 (où le tri suit les victoires).
	var value := Label.new()
	if _gold_is_rp():
		value.text = tr("LEADERBOARD_RP_TOTAL").format({"n": int(entry.get("season_points", 0))})
	else:
		value.text = _format_thousands(int(entry.get("wins", 0))) + " " + tr("COMMON_WINS")
	value.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	value.add_theme_font_override("font", _font)
	value.add_theme_font_size_override("font_size", 14)
	value.add_theme_color_override("font_color", GOLD)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(value)

	# Badge de division + échelon sous le podium (SAISON uniquement, backend ≥ §8.95).
	if _show_division_column():
		var pdiv := str(entry.get("division", ""))
		if pdiv != "":
			var dl := _mini_label(_division_label(pdiv, str(entry.get("division_tier", ""))),
				12, DIVISION_COLORS.get(pdiv, MUTED), false, HORIZONTAL_ALIGNMENT_CENTER)
			v.add_child(dl)

	WarzoneUI.add_corner_notches(card)
	return card

# --- En-tête de colonnes (fixe, hors scroll → reste aligné sur les lignes) --
func _build_columns_header() -> void:
	if columns_header == null:
		return
	_clear(columns_header)
	columns_header.add_theme_constant_override("separation", 14)
	columns_header.add_child(_header_cell(tr("LEADERBOARD_COL_RANK"), COL_RANK, HORIZONTAL_ALIGNMENT_LEFT))
	columns_header.add_child(_header_cell(tr("COMMON_OPERATOR"), 0.0, HORIZONTAL_ALIGNMENT_LEFT, true))
	# Colonne DIVISION (M6 §8.68) — uniquement sur l'onglet SAISON avec un backend qui la fournit.
	if _show_division_column():
		columns_header.add_child(_header_cell(tr("LEADERBOARD_COL_DIVISION"), COL_DIVISION, HORIZONTAL_ALIGNMENT_CENTER))
	# §8.95/§8.98 : la colonne MISE EN AVANT (or) est RP dès que le backend fournit le ladder
	# saisonnier (c'est sa clé de TRI) ; VICTOIRES en repli mock/pré-M6 (trié par victoires).
	columns_header.add_child(_header_cell(tr("COMMON_LEVEL"), COL_LEVEL, HORIZONTAL_ALIGNMENT_CENTER))
	columns_header.add_child(_header_cell(
		tr("LEADERBOARD_COL_RP") if _gold_is_rp() else tr("COMMON_WINS"),
		COL_WINS, HORIZONTAL_ALIGNMENT_RIGHT))

# La colonne or affiche les RP dès que le serveur publie le ladder saisonnier ; en NAVIGATION la
# question ne se pose pas (le mode n'existe qu'avec un backend ≥ §8.98).
func _gold_is_rp() -> bool:
	return _browse_mode or _has_division_data

# Colonne DIVISION : seulement en liste PLATE d'un backend ≥ M6 (repli §9.2 sinon). En NAVIGATION
# par division (§8.98) elle est MASQUÉE : toutes les lignes de la tranche portent le même badge —
# l'information vit déjà dans l'onglet actif et l'eyebrow du podium.
func _show_division_column() -> bool:
	return _has_division_data and not _browse_mode

func _header_cell(text: String, width: float, align: int, expand: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", ACCENT)
	l.horizontal_alignment = align
	if expand:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		l.custom_minimum_size = Vector2(width, 0)
	return l

# --- Lignes du classement (générées en code) -------------------------------
func _populate_ranking(entries: Array) -> void:
	_clear(ranking_box)
	if entries.is_empty():
		var empty := Label.new()
		# §8.96 : distinguer « on attend le réseau » (SYNCHRONISATION…) de « le serveur a répondu, il
		# n'y a personne » (AUCUN OPÉRATEUR CLASSÉ) — avant, les deux affichaient le même message.
		# §8.98 : en navigation, « on attend » = la tranche affichée n'est pas encore au cache.
		var waiting: bool
		if _browse_mode:
			waiting = not _tier_cache.has(_cache_key(_selected_division, _selected_tier))
		else:
			waiting = _server_board.is_empty() and not _offline_fallback
		empty.text = tr("COMMON_SYNCING") if waiting else tr("LEADERBOARD_EMPTY")
		empty.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
		empty.add_theme_font_override("font", _font)
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", ACCENT if waiting else MUTED)
		ranking_box.add_child(empty)
		return
	for entry in entries:
		ranking_box.add_child(_make_ranking_row(entry))

func _make_ranking_row(entry: Dictionary) -> PanelContainer:
	var rank := int(entry.get("rank", 0))
	var is_local := bool(entry.get("is_local", false))
	# Ligne de l'opérateur local : surface accentuée + liseré cyan plus épais (repère visuel §2).
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _make_row_style(is_local))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row.add_child(h)

	# Rang (chevron + numéro ; or pour le top 3).
	var rank_label := Label.new()
	rank_label.text = "❯ %d" % rank
	rank_label.add_theme_font_override("font", _font)
	rank_label.add_theme_font_size_override("font_size", 18)
	rank_label.add_theme_color_override("font_color", GOLD if rank <= 3 else MUTED)
	rank_label.custom_minimum_size = Vector2(COL_RANK, 0)
	rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(rank_label)

	# Pseudo (cyan + suffixe « (VOUS) » pour l'opérateur local).
	var name_label := Label.new()
	var who := str(entry.get("name", "—")).to_upper()
	if is_local:
		who += tr("LEADERBOARD_YOU")
	name_label.text = who
	name_label.add_theme_font_override("font", _font)
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", ACCENT if is_local else TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(name_label)

	# Badge de DIVISION + ÉCHELON (§8.95) : « OR II » coloré au ton de la division. Les RP ne sont
	# plus collés ici : ils ont leur propre colonne or (voir plus bas).
	if _show_division_column():
		var division := str(entry.get("division", ""))
		var div_label := Label.new()
		div_label.text = _division_label(division, str(entry.get("division_tier", "")))
		div_label.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
		div_label.add_theme_font_override("font", _font)
		div_label.add_theme_font_size_override("font_size", 15)
		div_label.add_theme_color_override("font_color", DIVISION_COLORS.get(division, MUTED))
		div_label.custom_minimum_size = Vector2(COL_DIVISION, 0)
		div_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		div_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(div_label)

	# Niveau (valeur centrée).
	var level_label := Label.new()
	level_label.text = str(int(entry.get("level", 0)))
	level_label.add_theme_font_override("font", _font)
	level_label.add_theme_font_size_override("font_size", 18)
	level_label.add_theme_color_override("font_color", TEXT)
	level_label.custom_minimum_size = Vector2(COL_LEVEL, 0)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(level_label)

	# Colonne OR = la clé de TRI du ladder affiché (§8.95/§8.98) : RP dès que le serveur les
	# fournit, VICTOIRES en repli mock/pré-M6.
	var value_label := Label.new()
	value_label.text = _format_thousands(
		int(entry.get("season_points", 0)) if _gold_is_rp() else int(entry.get("wins", 0)))
	value_label.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	value_label.add_theme_font_override("font", _font)
	value_label.add_theme_font_size_override("font_size", 18)
	value_label.add_theme_color_override("font_color", GOLD)
	value_label.custom_minimum_size = Vector2(COL_WINS, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(value_label)

	# §8.107 — la ligne ouvre le PROFIL PUBLIC de l'opérateur. AJOUT PUR : le rendu construit
	# ci-dessus n'est pas touché, on ne fait que rendre la ligne cliquable (curseur + infobulle +
	# gestionnaire d'entrée). Le Classement reste le SEUL accès à cet écran (demande produit).
	# On route par PSEUDO : `LeaderboardEntry` n'expose délibérément aucun id technique (« Données
	# PUBLIQUES uniquement »), décision maintenue — pas d'identifiant séquentiel énumérable.
	#
	# ⚠️ §8.118 — CAUSE RACINE d'un écran INATTEIGNABLE : on lisait ici `entry["username"]`, une clé
	# qui n'existe dans AUCUNE des entrées d'affichage. `_map_entry` (mapping serveur → affichage)
	# renomme `username` en **`name`**, et les données mock/le repli local emploient déjà `name` —
	# la lecture renvoyait donc TOUJOURS "", le `if` ne passait jamais, et `public_profile.tscn`
	# (livré §8.107, son SEUL accès étant cette ligne) n'était joignable par aucun chemin.
	var uname := str(entry.get("name", ""))
	# Garde MOCK (§8.96) : en repli « HORS LIGNE » la liste affiche des pseudos FICTIFS
	# (`_mock_board`) — router vers le profil public d'un joueur inexistant ne produirait qu'un
	# 404. Hors ligne, la ligne reste donc inerte : ni curseur main, ni infobulle, ni handler.
	if uname != "" and not _showing_mock():
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.tooltip_text = tr("LEADERBOARD_VIEW_PROFILE")
		row.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed \
					and ev.button_index == MOUSE_BUTTON_LEFT:
				_open_public_profile(uname))

	return row


# §8.107 — ouvre le profil public. Le pseudo transite par un `static var` du script de l'écran
# cible : `TransitionManager.change_scene` ne transporte aucun paramètre, et cette voie évite
# d'ajouter un champ étranger à un autoload existant (aucune modification de l'existant).
func _open_public_profile(username: String) -> void:
	AudioManager.play_sfx("click")
	PublicProfileScreen.target_username = username
	TransitionManager.change_scene("res://scenes/ui/public_profile.tscn")

# --- Fabriques de styles (charte §2, cohérent avec shop.gd / profile.gd) ----
# Style d'une carte de podium : surface gunmetal + bordure d'accent (or pour le #1).
func _make_card_style(border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = SURFACE
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(2)
	sb.border_color = border
	sb.content_margin_left = 14.0
	sb.content_margin_top = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_bottom = 14.0
	return sb

# Style d'une ligne de classement : surface gunmetal + liseré cyan gauche (épais + teinté si local).
func _make_row_style(is_local: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.211765, 0.772549, 0.85098, 0.10) if is_local else SURFACE
	sb.set_corner_radius_all(0)
	sb.border_width_left = 5 if is_local else 3
	sb.border_color = ACCENT
	sb.content_margin_left = 16.0
	sb.content_margin_top = 10.0
	sb.content_margin_right = 16.0
	sb.content_margin_bottom = 10.0
	return sb

# --- Utilitaires ------------------------------------------------------------
# Sépare les milliers par une fine espace (lisibilité, comme shop / profile).
func _format_thousands(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = " " + out
	if value < 0:
		out = "-" + out
	return out

# Vide un conteneur sans laisser de doublons (cf. lobby_screen.gd / shop.gd / profile.gd).
func _clear(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _set_status(text: String) -> void:
	if status_label:
		status_label.text = text

