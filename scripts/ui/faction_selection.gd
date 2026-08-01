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
# Vue partagée des caractéristiques du héros (SOURCE UNIQUE : STAT_ROWS + formatage + rangée de
# pastilles) — mutualisée avec characters_screen.gd (DRY, aucun libellé/format dupliqué).
const HeroStatsView = preload("res://scripts/ui/hero_stats_view.gd")
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
# Vrai dès que la bascule vers l'arène est engagée (garde anti double change_scene : la
# resynchronisation draft_state + les faction_locked peuvent compléter le draft plusieurs fois).
var _left: bool = false
# Échéance UNIX (s) d'auto-verrouillage du draft (G2 durci) : le serveur verrouille d'office les
# retardataires passé ce délai — on affiche le compte à rebours. -1 = aucune échéance connue.
var _draft_deadline_at: float = -1.0
# Instance du héros 3D, montée une fois dans PortraitWrap (modèle échangé via set_model au défilement).
# Non typée à dessein (appels dynamiques — pas de class_name sur le composant).
var _hero3d = null

# --- Caractéristiques du héros de la faction centrée (sprint RPG — panneau de stats du draft) ---
# Roster reçu du backend (GET /api/v1/heroes via NetworkManager.heroes_loaded), indexé par
# faction_id (clé = FactionData.id). Alimenté de façon ASYNCHRONE → le bloc stats affiche un
# squelette « — » tant qu'il est vide, puis se remplit à la réception.
var _heroes_by_faction: Dictionary = {}
# Bloc de pastilles courant, reconstruit (queue_free + rebuild) à CHAQUE glissement — cf.
# _render_hero_stats (R3 : aucun empilement de nœuds au fil du carrousel).
var _stats_panel: Control = null
# Police condensée de la charte (§2) pour les pastilles construites par code (mêmes fallbacks
# que characters_screen ; la carte .tscn utilise déjà cette police via un SubResource).
var _stats_font: SystemFont

# --- Rotation & possession des factions PAYANTES (M3 §8.66) ---
# Ids des factions PAYANTES (catalogue serveur, catégorie "faction") ; prix Coins par id.
var _paid_ids: Dictionary = {}        # fid -> prix (int)
# Ids possédés (inventaire serveur, quantité > 0).
var _owned_ids: Dictionary = {}       # fid -> true
# Ids gratuits CETTE SEMAINE (rotation serveur). Tant que la rotation n'a pas répondu, le
# REPLI GRACIEUX grise toutes les payantes non possédées (comportement sûr — le serveur
# refuse de toute façon un choix verrouillé, erreur privée §8.66).
var _rotation_ids: Dictionary = {}    # fid -> true
# --- Accès TEMPORAIRES (chantiers Q/R) ---
# Crédit de parties gratuites de la semaine ; -1 = INCONNU (anonyme / serveur antérieur) → aucun
# compteur affiché et aucun verrouillage supplémentaire (le serveur reste l'autorité).
var _free_games_left: int = -1
var _free_games_max: int = -1
# Ids débloqués par le PASS pour la saison en cours (bloc `pass_faction_grants` de l'inventaire).
var _pass_granted_ids: Dictionary = {}   # fid -> true
# Bandeau « GRATUITE CETTE SEMAINE » / « VERROUILLÉE » créé par code au-dessus du nom.
var _access_banner: Label = null
# Ligne d'identité du MENEUR (refonte 2026-07-18) : « GÉNÉRAL VIKTOR "IRONLINE" STAHL », créée
# par code SOUS le nom de faction (aucune retouche .tscn — même pattern que _access_banner).
var _leader_line: Label = null
# Skins équipés par faction (M5 §8.69) : { faction_id: skin_id } — bloc `equipped` de l'inventaire.
var _equipped_map: Dictionary = {}
const SKINS_DIR := "res://resources/skins/"

func _ready():
	# Encoches biseautées sur le panneau principal (charte « Warzone Command » §2).
	WarzoneUI.add_corner_notches(panel)

	# Police des pastilles de stats (construites par code) — initialisée AVANT tout _apply_card_content.
	_stats_font = SystemFont.new()
	_stats_font.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	_stats_font.font_weight = 700

	_load_factions()

	prev_button.pressed.connect(_on_prev_pressed)
	next_button.pressed.connect(_on_next_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)

	# SFX d'interface (survol/clic — R6). Le « CONFIRMER » utilise le SFX de validation dédié.
	WarzoneUI.wire_buttons_sfx([prev_button, next_button])
	confirm_button.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	confirm_button.pressed.connect(func() -> void: AudioManager.play_sfx("confirm"))
	AudioManager.start_menu_ambient()  # nappe d'ambiance des menus (idempotente, R6)

	# PREMIÈRE OPÉRATION (§8.129) : le coach ouvre le briefing ICI (étapes BIENVENUE et LE DRAFT).
	# `confirm_button` sert d'ancre de surlignage — le carrousel bouge à chaque flèche, le bouton
	# de verrouillage, lui, ne bouge jamais. NO-OP hors partie guidée.
	TutorialManager.register_anchor("draft_recommended", confirm_button)
	TutorialManager.bind_draft(self)

	# Réseau : on écoute les verrouillages des autres joueurs.
	NetworkManager.faction_locked.connect(_on_faction_locked)
	# Resynchronisation du Draft (G2 durci) : les faction_locked des BOTS partent juste après
	# game_started, PENDANT la transition de scène — cet écran n'était pas encore à l'écoute et
	# les perdait (compteur bloqué à 1/3, partie jamais lancée). On demande donc au serveur la
	# photographie complète des verrouillages dès l'arrivée ici.
	NetworkManager.draft_state_received.connect(_on_draft_state)
	# Un joueur qui abandonne/déconnecte pendant le draft ne verrouillera jamais : on recompte
	# les attendus (joueurs ACTIFS) à chaque abandon pour ne pas attendre son verrou à vie.
	NetworkManager.player_abandoned.connect(_on_player_abandoned)
	# Filet de sécurité : si l'état passe en "playing" (Phase 0 résolue pendant qu'on était
	# encore ici — resync manquée, timeout serveur…), on rejoint l'arène sans condition.
	NetworkManager.game_state_updated.connect(_on_game_state_updated)
	_draft_deadline_at = NetworkManager.last_draft_deadline_at
	if NetworkManager.connected:
		NetworkManager.request_draft_state()

	# M3 (§8.66) : possession + rotation AVANT de laisser confirmer une payante. Chargements
	# asynchrones ; en attendant, les payantes non possédées sont grisées (repli sûr).
	NetworkManager.shop_catalog_loaded.connect(_on_shop_catalog_for_draft)
	NetworkManager.shop_inventory_loaded.connect(_on_shop_inventory_for_draft)
	NetworkManager.shop_rotation_loaded.connect(_on_shop_rotation_for_draft)
	NetworkManager.fetch_shop_catalog()
	NetworkManager.fetch_shop_inventory()
	NetworkManager.fetch_shop_rotation()

	# Roster des héros (GET /api/v1/heroes) : alimente le panneau de caractéristiques du draft. Le
	# carrousel reste PLEINEMENT fonctionnel si l'appel échoue/tarde (le bloc affiche un squelette
	# « — » puis se remplit à la réception ; robustesse esprit FALLBACK_PATHS). Vue pure : aucune
	# logique de jeu, on affiche les stats telles quelles depuis le payload.
	NetworkManager.heroes_loaded.connect(_on_heroes_loaded)
	NetworkManager.fetch_heroes()

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
	# Identité du meneur (refonte 2026-07-18) : rang traduit + nom propre invariant, sous le nom.
	_ensure_leader_line()
	_leader_line.text = WarzoneUI.faction_leader_title(f).to_upper()
	_leader_line.add_theme_color_override("font_color", Color(f.accent_color, 0.85))
	_leader_line.visible = _leader_line.text != ""
	# Dossier : lore + rappel du pouvoir — TRADUITS via les clés du .tres (i18n 2026-07-18).
	description_label.text = _dossier_text(f)
	_set_portrait(f)
	# Caractéristiques chiffrées du héros de la faction centrée, SOUS la description (IntelColumn).
	_render_hero_stats(f)
	# Compteur de position toujours à jour (réactualisé à chaque glissement, pas seulement au lock).
	if counter_label:
		counter_label.text = "%02d / %02d" % [_index + 1, _factions.size()]
	# M3 (§8.66) : accès à la faction courante (bandeau + grisage + verrou du CONFIRMER).
	_apply_access_state(f)

# =========================================================
# Rotation & possession des factions payantes (M3 §8.66)
# =========================================================

func _on_shop_catalog_for_draft(items: Array) -> void:
	_paid_ids.clear()
	for it in items:
		if typeof(it) == TYPE_DICTIONARY and str(it.get("category", "")) == "faction":
			# Piège JSON §5 : prix en float après parse → int().
			_paid_ids[str(it.get("id", ""))] = int(it.get("price", 0))
	_refresh_access()

func _on_shop_inventory_for_draft(data: Dictionary) -> void:
	_owned_ids.clear()
	var items: Dictionary = data.get("items", {})
	for fid in items:
		if int(items[fid]) > 0:
			_owned_ids[str(fid)] = true
	# Skins équipés par faction (M5 §8.69) : { faction_id: skin_id } — le carrousel montre le
	# héros AVEC son propre skin équipé (même résolution que le Split-Screen VS).
	var eq = data.get("equipped", {})
	_equipped_map = eq if typeof(eq) == TYPE_DICTIONARY else {}
	# Personnages débloqués par le PASS pour la saison en cours (chantier R.6) : jouables au draft
	# au même titre qu'une faction possédée, mais l'accès est TEMPORAIRE (bandeau dédié).
	_pass_granted_ids.clear()
	var grants = data.get("pass_faction_grants", [])
	if typeof(grants) == TYPE_ARRAY:
		for fid in grants:
			_pass_granted_ids[str(fid)] = true
	_refresh_access()
	_refresh_card(true)
	# §8.122 (LOT F) : la panoplie (skins équipés + finisher) n'est connue qu'ICI — c'est le seul
	# moment du draft où l'on puisse la comparer à celle du draft précédent.
	_maybe_pulse_loadout()


# =========================================================
# PULSE D'ÉQUIPEMENT (§8.122, LOT F)
# =========================================================
# Le joueur qui vient d'équiper un skin ou un finisher dans le hub n'avait AUCUN retour au moment
# où ça compte : l'entrée en partie. Un pulse unique du présentoir héros le lui montre — discret,
# une seule fois, et seulement si la panoplie A CHANGÉ depuis le dernier draft.
#
# La comparaison est LOCALE (settings.cfg [progress]) : aucun champ serveur « ma panoplie du
# dernier draft » n'existe, et en créer un pour un pulse de 0,4 s serait disproportionné.
const LOADOUT_PROGRESS_KEY := "draft_loadout"
const LOADOUT_PULSE_SCALE := 1.06
const LOADOUT_PULSE_TIME := 0.4

func _maybe_pulse_loadout() -> void:
	# Signature STABLE de la panoplie. Le FINISHER en fait partie sans traitement particulier : le
	# serveur le range dans le MÊME bloc `equipped`, sous le slot réservé « __finisher__ » (cf.
	# backend shop.py) — une seule boucle couvre donc skins ET finisher.
	# Le tri est indispensable : l'ordre des clés d'un Dictionary JSON n'est pas garanti d'une
	# session à l'autre, et une signature instable ferait pulser à CHAQUE draft.
	var parts: Array = []
	var fids: Array = _equipped_map.keys()
	fids.sort()
	for fid in fids:
		parts.append("%s=%s" % [str(fid), str(_equipped_map[fid])])
	var signature := "|".join(parts)
	var previous := SettingsManager.get_progress(LOADOUT_PROGRESS_KEY)
	SettingsManager.set_progress(LOADOUT_PROGRESS_KEY, signature)
	# Premier draft sur cette machine : on mémorise sans rien célébrer (tout serait « nouveau »).
	if previous == "" or previous == signature:
		return
	if bool(SettingsManager.get_comfort("reduced_motion")):
		return
	_pulse_hero_stage()

func _pulse_hero_stage() -> void:
	var target: Control = _hero3d if _hero3d != null and is_instance_valid(_hero3d) else hero_portrait
	if target == null or not is_instance_valid(target):
		return
	target.pivot_offset = target.size * 0.5
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(target, "scale", Vector2.ONE * LOADOUT_PULSE_SCALE, LOADOUT_PULSE_TIME * 0.5)
	tw.tween_property(target, "scale", Vector2.ONE, LOADOUT_PULSE_TIME * 0.5)


func _on_shop_rotation_for_draft(data: Dictionary) -> void:
	_rotation_ids.clear()
	for fid in data.get("free_faction_ids", []):
		_rotation_ids[str(fid)] = true
	# Crédit de parties gratuites (chantier Q.6). -1 = INCONNU (visiteur anonyme, serveur antérieur)
	# → on n'affiche aucun compteur et on ne verrouille RIEN de plus qu'avant (client défensif).
	_free_games_max = int(data.get("free_games_max", -1)) if data.has("free_games_max") else -1
	_free_games_left = int(data.get("free_games_left", -1)) if data.has("free_games_left") else -1
	_refresh_access()

# Vrai si le serveur nous a donné le compteur de parties gratuites (joueur authentifié).
func _has_free_games_counter() -> bool:
	return _free_games_left >= 0 and _free_games_max > 0

# Vrai si la faction est en rotation mais que le CRÉDIT de parties est ÉPUISÉ (chantier Q) : elle
# redevient alors injouable cette semaine — le serveur refuse le verrouillage.
func _rotation_exhausted(fid: String) -> bool:
	return (_rotation_ids.has(fid) and not _owned_ids.has(fid)
			and _has_free_games_counter() and _free_games_left <= 0)

# Vrai si la faction est VERROUILLÉE pour ce joueur : payante, non possédée, non débloquée par le
# Pass, et (hors rotation OU rotation épuisée). Tant que le catalogue n'a pas répondu, rien n'est
# payant côté client (le serveur reste l'autorité et refusera un choix verrouillé — erreur privée,
# draft non cassé).
func _is_locked(fid: String) -> bool:
	if not _paid_ids.has(fid):
		return false
	if _owned_ids.has(fid) or _pass_granted_ids.has(fid):
		return false
	if _rotation_exhausted(fid):
		return true
	return not _rotation_ids.has(fid)

func _refresh_access() -> void:
	if _factions.is_empty() or _confirmed:
		return
	_apply_access_state(_factions[_index])


# Nom AFFICHABLE d'une faction depuis son id — lu sur les ressources DÉJÀ chargées (`_factions`,
# source unique du catalogue côté draft). Pas de clé `FACTION_<ID>` : les noms de factions vivent
# dans les `.tres` (§4.3) et nulle part ailleurs. Id inconnu → l'id « humanisé », jamais une clé brute.
func _faction_display_name(fid: String) -> String:
	for f in _factions:
		if str(f.id) == fid:
			return str(f.name)
	return fid.replace("_", " ").to_upper()


# Pseudo du COÉQUIPIER ayant déjà verrouillé cette faction, ou "" (MODE ÉQUIPES §8.124).
# Lit `_locked`, qui reçoit à la fois les broadcasts `faction_locked` et la resynchro `draft_state` :
# les choix des coéquipiers apparaissent donc EN DIRECT, sans polling ni message dédié.
# Vide en FFA (`teammates_of` rend [] hors mode équipe) → aucune garde à écrire ailleurs.
func _teammate_holding(fid: String) -> String:
	for mate in GameState.teammates_of(AuthManager.user_id):
		if str(_locked.get(int(mate), "")) == fid:
			var p: Dictionary = GameState.players.get(str(int(mate)), {})
			var who := str(p.get("username", ""))
			# §8.126 — le tag de compagnie accompagne le pseudo jusque dans le DRAFT.
			return GameState.tagged_name(int(mate), who if who != "" else "#%d" % int(mate))
	return ""

# Applique l'état d'accès de la faction affichée : bandeau OR « GRATUITE CETTE SEMAINE »
# (rotation), bandeau verrou + prix + renvoi BOUTIQUE (payante verrouillée, carte grisée,
# CONFIRMER désactivé), rien pour une gratuite/possédée.
func _apply_access_state(f) -> void:
	var fid := str(f.id)
	_ensure_access_banner()
	var locked := _is_locked(fid)
	var in_rotation: bool = _rotation_ids.has(fid) and not _owned_ids.has(fid)

	# MODE ÉQUIPES (§8.124) — UNICITÉ INTRA-ÉQUIPE : une faction déjà verrouillée par un COÉQUIPIER
	# est grisée et non confirmable. Ce cas passe AVANT tous les autres : il est le plus spécifique
	# (« celle-là, pas elle ») et le plus actionnable — il nomme la personne, donc le joueur sait
	# quoi faire. Les ADVERSAIRES peuvent toujours doubler nos factions (règle inchangée).
	var mate_owner := _teammate_holding(fid)
	if mate_owner != "":
		_access_banner.visible = true
		_access_banner.text = tr("TEAM_PICKED_BY") % mate_owner
		_access_banner.add_theme_color_override("font_color", Color("8a97a5"))
		card.modulate = Color(0.62, 0.66, 0.72, 1.0)
		if not _confirmed:
			confirm_button.disabled = true
			confirm_button.text = tr("FS_LOCKED_BTN")
		return

	# Ordre des cas, du plus SPÉCIFIQUE au plus général (chantier T) : un crédit épuisé doit dire
	# POURQUOI c'est verrouillé, et un déblocage par Pass doit se distinguer d'une possession.
	if _rotation_exhausted(fid):
		_access_banner.visible = true
		_access_banner.text = tr("FS_ROTATION_EXHAUSTED") % int(_paid_ids.get(fid, 0))
		_access_banner.add_theme_color_override("font_color", Color("8a97a5"))
	elif in_rotation:
		_access_banner.visible = true
		# Compteur de parties restantes dès qu'il est connu — sinon libellé historique.
		if _has_free_games_counter():
			_access_banner.text = tr("FS_ROTATION_FREE_GAMES") % [_free_games_left, _free_games_max]
		else:
			_access_banner.text = tr("FS_ROTATION_FREE")
		_access_banner.add_theme_color_override("font_color", Color("e0b249"))
	elif _pass_granted_ids.has(fid) and not _owned_ids.has(fid):
		# Débloquée par le Pass pour la saison : jouable, mais TEMPORAIRE (cyan, pas or).
		_access_banner.visible = true
		_access_banner.text = tr("FS_PASS_UNLOCKED")
		_access_banner.add_theme_color_override("font_color", Color("36c5d9"))
	elif locked:
		_access_banner.visible = true
		_access_banner.text = tr("FS_LOCKED_PAID").format({"price": _paid_ids.get(fid, 0)})
		_access_banner.add_theme_color_override("font_color", Color("8a97a5"))
	else:
		_access_banner.visible = false

	# Grisage de la carte + verrou du CONFIRMER (le serveur re-valide de toute façon §8.66).
	card.modulate = Color(0.62, 0.66, 0.72, 1.0) if locked else Color.WHITE
	if not _confirmed:
		confirm_button.disabled = locked
		confirm_button.text = tr("FS_LOCKED_BTN") if locked else tr("FS_CONFIRM")

# Bandeau d'accès créé par code SOUS le nom de faction (aucune retouche .tscn). Placé APRÈS la
# ligne d'identité du meneur quand elle existe (ordre : nom → meneur → bandeau).
func _ensure_access_banner() -> void:
	if _access_banner != null and is_instance_valid(_access_banner):
		return
	_access_banner = Label.new()
	_access_banner.name = "AccessBanner"
	_access_banner.visible = false
	_access_banner.add_theme_font_size_override("font_size", 15)
	_access_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var parent := faction_name_label.get_parent()
	parent.add_child(_access_banner)
	var anchor := _leader_line if (_leader_line != null and is_instance_valid(_leader_line)) else faction_name_label
	parent.move_child(_access_banner, anchor.get_index() + 1)

# Ligne d'identité du meneur, créée une fois SOUS le nom de faction (pattern _ensure_access_banner).
func _ensure_leader_line() -> void:
	if _leader_line != null and is_instance_valid(_leader_line):
		return
	_leader_line = Label.new()
	_leader_line.name = "LeaderLine"
	_leader_line.add_theme_font_size_override("font_size", 16)
	_leader_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var parent := faction_name_label.get_parent()
	parent.add_child(_leader_line)
	parent.move_child(_leader_line, faction_name_label.get_index() + 1)

# Texte du dossier : lore traduit (desc_key) + ligne de pouvoir traduite (power_key), même
# gabarit BBCode que l'ancien champ `description` en dur ("[b]Pouvoir :[/b] …"). Replis
# gracieux : .tres legacy sans clés → description en dur ; clé absente du CSV → clé brute
# évitée par le repli sur description.
func _dossier_text(f) -> String:
	var lore := tr(str(f.desc_key)) if str(f.desc_key) != "" else str(f.description)
	var power := tr(str(f.power_key)) if str(f.power_key) != "" else ""
	if power != "":
		return "%s\n\n[b]%s[/b] %s" % [lore, tr("FACTION_POWER_LABEL"), power]
	return lore

# =========================================================
# Caractéristiques du héros (panneau de stats du draft — sprint RPG)
# =========================================================

# Reconstruit le bloc de caractéristiques du héros de la faction `f`, SOUS la description (IntelColumn).
# Reconstruction PROPRE (queue_free + rebuild) à chaque glissement → aucun empilement de nœuds (R3).
# Héros absent (roster asynchrone pas encore là / faction sans héros) → squelette « — » discret,
# rempli dès l'arrivée de heroes_loaded. Robuste : no-op si la colonne d'intel n'est pas câblée.
func _render_hero_stats(f) -> void:
	if description_label == null:
		return
	var column := description_label.get_parent()
	if column == null:
		return
	# Purge de l'ancien bloc (pas d'empilement au fil des glissements).
	if _stats_panel != null and is_instance_valid(_stats_panel):
		column.remove_child(_stats_panel)
		_stats_panel.queue_free()
	_stats_panel = null
	# Correspondance faction ⇄ héros : hero.faction_id == FactionData.id (même identifiant backend).
	var hero = _heroes_by_faction.get(str(f.id), null)
	# Stats où ce héros domine tout le roster (repère ▲ doré) — recalculé à chaque affichage.
	var leaders := _leader_fields_for(hero)
	_stats_panel = HeroStatsView.build_compact_row(hero, _stats_font, f.accent_color, leaders)
	column.add_child(_stats_panel)  # ajouté en dernier → rendu SOUS la description

# Réception ASYNCHRONE du roster (GET /api/v1/heroes) : indexe les héros par faction_id, puis
# re-rend le bloc de la faction COURANTE (les autres se rempliront à leur affichage). Lecture
# défensive ; no-op hors de l'arbre ou si aucune faction n'est chargée (robustesse).
func _on_heroes_loaded(heroes: Array) -> void:
	if not is_inside_tree():
		return
	_heroes_by_faction.clear()
	for h in heroes:
		if h is Dictionary:
			_heroes_by_faction[str(h.get("faction_id", ""))] = h
	if _factions.is_empty():
		return
	_render_hero_stats(_factions[_index])

# Détermine les stats où le héros courant est le PLUS FORT de tout le roster (repère ▲ doré au
# draft — aide de décision). Comparaison côté client sur le roster déjà en mémoire (Vue pure : on
# classe des valeurs déjà fournies, aucun calcul de jeu). Renvoie la liste des champs dominés
# (pv_max, pa, …). Roster incomplet (< 2 héros) ou héros inconnu → aucune comparaison.
func _leader_fields_for(hero) -> Array:
	var out := []
	if not (hero is Dictionary) or _heroes_by_faction.size() < 2:
		return out
	var my_stats = hero.get("stats", {})
	if not (my_stats is Dictionary):
		return out
	for r in HeroStatsView.STAT_ROWS:
		var mine := HeroStatsView.stat_scalar(my_stats, r)
		if mine <= 0.0:
			continue  # stat à 0 → jamais « meilleure » (évite de tout marquer sur des données vides)
		var best := mine
		for other in _heroes_by_faction.values():
			if other is Dictionary:
				var os = other.get("stats", {})
				if os is Dictionary:
					best = maxf(best, HeroStatsView.stat_scalar(os, r))
		# Leader si personne ne fait STRICTEMENT mieux (égalité au sommet incluse ; tolérance float).
		if mine >= best - 0.0001:
			out.append(str(r["field"]))
	return out

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
# M5 (§8.69) : le skin ÉQUIPÉ du joueur pour cette faction surcharge portrait/modèle/accent
# (même résolution que le Split-Screen VS ; placeholder teinté accent_override si assets absents).
func _set_portrait(f) -> void:
	var accent: Color = f.accent_color
	var model_path := ""
	if f.get("hero_model_path") != null:
		model_path = str(f.get("hero_model_path"))
	var portrait_path := str(f.hero_path) if f.hero_path != null else ""

	# --- Surcharge par le skin équipé (M5) ---
	var skin = _find_skin(str(_equipped_map.get(str(f.id), "")), str(f.id))
	if skin != null:
		var s_model := str(skin.get("model_path") if skin.get("model_path") != null else "")
		var s_portrait := str(skin.get("portrait_path") if skin.get("portrait_path") != null else "")
		if s_model != "" and ResourceLoader.exists(s_model):
			model_path = s_model
		if s_portrait != "" and ResourceLoader.exists(s_portrait):
			portrait_path = s_portrait
		var s_accent = skin.get("accent_override")
		if s_accent is Color:
			accent = s_accent

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
	if portrait_path != "" and ResourceLoader.exists(portrait_path):
		tex = load(portrait_path)
	if tex != null:
		hero_portrait.texture = tex
		hero_portrait.visible = true
		portrait_placeholder.visible = false
	else:
		hero_portrait.texture = null
		hero_portrait.visible = false
		portrait_placeholder.visible = true
		portrait_placeholder.color = accent.darkened(0.25)

# Retrouve la ressource SkinData (id + faction cohérents), ou null (duck-typing, export-safe —
# miroir de split_screen_vs._find_skin). skin_id vide → null immédiat.
func _find_skin(skin_id: String, faction_id: String):
	if skin_id == "":
		return null
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

# =========================================================
# CONFIRMATION & SYNCHRONISATION RÉSEAU
# =========================================================

func _on_confirm_pressed() -> void:
	# Robustesse : pas de confirmation sans sélection valide.
	if _confirmed or _factions.is_empty():
		return
	var f = _factions[_index]
	# M3 (§8.66) : jamais de confirmation d'une faction verrouillée (double sécurité — le bouton
	# est déjà désactivé, et le serveur refuserait de toute façon avec une erreur privée).
	if _is_locked(str(f.id)):
		return
	_confirmed = true

	# Verrouillage de l'UI : on ne peut plus changer de faction.
	confirm_button.disabled = true
	prev_button.disabled = true
	next_button.disabled = true
	confirm_button.text = tr("FS_LOCKED")

	# Envoi du choix au serveur.
	NetworkManager.send_faction_choice(f.id)
	# §8.129 — condition de sortie de l'étape LE DRAFT : le choix est VERROUILLÉ (pas « survolé »).
	TutorialManager.notify_faction_locked()
	# Optimiste : on s'enregistre soi-même immédiatement (au cas où le serveur n'écho pas
	# notre propre choix dans le broadcast faction_locked).
	_register_lock(AuthManager.user_id, f.id)
	_update_status()

# Réception du choix d'un autre joueur (broadcast serveur).
func _on_faction_locked(player_id, faction_id) -> void:
	_register_lock(player_id, faction_id)
	# MODE ÉQUIPES (§8.124) : le pick d'un COÉQUIPIER doit se voir EN DIRECT sur le carrousel — s'il
	# vient de prendre la faction affichée, elle devient grisée « PRIS PAR … » sans attendre que le
	# joueur fasse défiler. `_refresh_access` ne fait rien si l'on a déjà confirmé.
	_refresh_access()
	_update_status()

# Photographie complète du Draft renvoyée par le serveur (réponse à request_draft_state) :
# rattrape les verrouillages manqués pendant la transition de scène (bots notamment).
# Clés du dict = player_id en STRING (piège JSON §5) → int() avant enregistrement.
func _on_draft_state(locked: Dictionary) -> void:
	_draft_deadline_at = NetworkManager.last_draft_deadline_at
	for key in locked:
		_register_lock(str(key).to_int(), str(locked[key]))
	_update_status()

# Abandon/déconnexion pendant le draft : le partant ne verrouillera jamais — l'état diffusé
# (is_active=false) est déjà appliqué à GameState, on recompte donc les attendus.
func _on_player_abandoned(_player_id: int) -> void:
	_maybe_start_game()
	_update_status()

# Filet de sécurité : la partie est passée en "playing" alors qu'on est encore sur le draft
# (verrouillages manqués + Phase 0 résolue côté serveur) → on rejoint l'arène sans condition.
func _on_game_state_updated() -> void:
	if GameState.stage == "playing":
		_go_to_arena()

# Enregistre un verrouillage et déclenche éventuellement le départ de la partie.
func _register_lock(player_id, faction_id) -> void:
	_locked[int(player_id)] = faction_id
	_maybe_start_game()

# Bascule vers l'arène quand TOUS les joueurs ACTIFS de la partie ont verrouillé leur faction.
# (Compter tous les joueurs attendait à vie le verrou d'un déconnecté — compteur figé à N-1/N.)
func _maybe_start_game() -> void:
	var expected := _expected_players()
	if expected <= 0:
		return
	var locked_active := 0
	for pid in _locked:
		if _is_player_active(pid):
			locked_active += 1
	if locked_active >= expected:
		_go_to_arena()

# Bascule unique vers l'arène (garde anti double change_scene : resync + broadcasts + filet
# stage=="playing" peuvent tous conclure « draft terminé »).
func _go_to_arena() -> void:
	if _left:
		return
	_left = true
	status_label.text = tr("FS_ALL_READY")
	TransitionManager.change_scene("res://scenes/game/main.tscn")

# Vrai si le joueur est encore ACTIF dans la partie (déserteurs exclus). Lecture défensive de
# GameState.players : clés string (piège JSON §5), is_active absent = actif (rétro-compat).
func _is_player_active(pid) -> bool:
	var p = GameState.players.get(str(int(pid)), null)
	if p == null:
		p = GameState.players.get(int(pid), null)
	if not (p is Dictionary):
		return true
	return bool(p.get("is_active", true))

# Nombre de joueurs attendus au draft : les joueurs ACTIFS de la partie (GameState peuplé par
# le message game_started reçu en salle d'attente, puis tenu à jour par player_abandoned).
func _expected_players() -> int:
	var count := 0
	for pid in GameState.players:
		if _is_player_active(pid):
			count += 1
	return count

func _update_status() -> void:
	if _factions.is_empty() or _left:
		return
	var expected := _expected_players()
	var count_txt := str(_locked.size())
	if expected > 0:
		count_txt += " / " + str(expected)
	status_label.text = tr("FS_STATUS") % [_index + 1, _factions.size(), count_txt]
	# MODE ÉQUIPES (§8.124) : bandeau « ÉQUIPE n » préfixé au statut, avec les picks des
	# coéquipiers DÉJÀ verrouillés. C'est la seule information de draft qui se partage — les
	# adversaires restent un compteur anonyme (règle inchangée). Vide en FFA.
	var my_team := GameState.team_of(AuthManager.user_id)
	if my_team != 0:
		var picks := PackedStringArray()
		for mate in GameState.teammates_of(AuthManager.user_id):
			var fid := str(_locked.get(int(mate), ""))
			if fid == "":
				continue
			var p: Dictionary = GameState.players.get(str(int(mate)), {})
			picks.append("%s ◆ %s" % [
				GameState.tagged_name(int(mate), str(p.get("username", "#%d" % int(mate)))),
				_faction_display_name(fid)])
		var banner := tr("TEAM_BANNER") % my_team
		if picks.size() > 0:
			banner += "  —  " + " · ".join(picks)
		status_label.text = "%s\n%s" % [banner, status_label.text]

func _process(_delta: float) -> void:
	# Compte à rebours d'auto-verrouillage (G2 durci) : tant que le joueur n'a PAS confirmé et
	# qu'une échéance serveur est connue, le statut affiche le temps restant (à 0, le serveur
	# verrouille d'office la faction provisoire et la salle bascule d'elle-même vers l'arène).
	if _left or _confirmed or _draft_deadline_at <= 0.0 or _factions.is_empty():
		return
	var remaining := int(ceil(_draft_deadline_at - Time.get_unix_time_from_system()))
	if remaining >= 0 and remaining <= 30:
		status_label.text = tr("FS_AUTO_LOCK_IN") % remaining
		status_label.add_theme_color_override("font_color", Color(0.878431, 0.698039, 0.286275, 1))
