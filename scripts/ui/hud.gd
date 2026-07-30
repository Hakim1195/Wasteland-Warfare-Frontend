extends Control

# HUD DE L'ARÈNE — refonte « barre basse pleine largeur » (PROMPT_REFONTE_UI_ARENE, lot A).
# Le plateau occupe 100 % de la fenêtre (MapViewportContainer, 1ᵉʳ enfant de Main) ; ce HUD est un
# Control plein écran TRANSPARENT AUX CLICS (mouse_filter = IGNORE) sur lequel flottent :
#   TopCenterWidget    : bandeau MINIMAL — qui joue · phase · chronomètre (rien d'autre).
#   TopRightWidget     : bouton ABANDONNER (rouge).
#   PlayerSheetWidget  : FICHE JOUEUR rétractable à gauche (identité, pouvoir, PV/PA/PB/PP,
#                        situation, territoire cliqué) + navigation ◀ ▶ entre belligérants.
#   SidePanelWidget    : COMMS — le chat SEUL (le Journal a déménagé dans la barre basse).
#   BottomCenterWidget : BARRE BASSE PLEINE LARGEUR rétractable, 3 zones —
#                        OBJECTIFS | OPÉRATEUR (moi) | COMMANDES (onglets ACTIONS/CARTES/JOURNAL).
# POURQUOI : l'ancien layout empilait 3 tiroirs INTEL à gauche, un War Roster en haut-droite et un
# bloc central bas étroit → écran illisible et infos redondantes (constat Hakim 2026-07-26). Les
# informations de pouvoir de faction vivent désormais dans la FICHE JOUEUR et la zone OPÉRATEUR.
# AUCUNE logique de jeu ici (Règle d'Or §6.1) : tout remonte à main.gd par signaux.

signal pass_pressed
# Émis quand le joueur clique une carte de sa main : transmet l'INDEX de la carte jouée.
# Une carte = un nombre brut de troupes (refonte économie) ; le contrôleur envoie play_card.
signal card_played(card_index: int)
# Émis quand le joueur CONFIRME l'abandon (2 clics : armer, puis confirmer sous 3 s).
signal abandon_pressed
# Émis quand le joueur valide son tampon de déploiement local via « CONFIRMER LE DÉPLOIEMENT »
# (placement initial ou renforts Phase 2, §8.26). main.gd envoie alors l'action bulk deploy_units.
signal deploy_confirmed
# Émis quand le joueur envoie un message de chat (§8.33). channel ∈ {"general","prive"} ; pour le
# canal privé, target_id = id du destinataire choisi (sinon -1). main.gd relaie à NetworkManager.
signal chat_send_requested(channel: String, text: String, target_id: int)
# Émis au clic d'une ligne du Roster de Guerre (E1 §8.73) — et désormais aussi par les flèches
# ◀ ▶ de la FICHE JOUEUR (même sémantique, lot A) : main.gd ouvre la fiche du joueur demandé
# et focalise la caméra sur son territoire le plus garni (le HUD reste une View pure §6.1).
signal roster_player_clicked(player_id: int)
# Émis au clic d'une entrée [url=<tid>] du Journal de Guerre (E4 §8.76) : main.gd focalise la
# caméra sur le territoire et le fait flasher — le journal devient un outil de navigation.
signal log_territory_clicked(territory_id: String)
# Émis au clic du bouton « RÉ-ASSAUT » (E7 §8.79) : main.gd rejoue le dernier assaut.
signal reassault_pressed
# Émis par les raccourcis de quantité +1/+5/MAX (E7 §8.79) : delta ∈ {1, 5, -1=MAX}. main.gd
# ajuste %AmountSpin (mouvement) ou le sens du tampon de déploiement selon la phase.
signal amount_quick(delta: int)
# Émis au clic d'un bouton de la carte POUVOIR (lot E) : action ∈ {"eclipse", "spy"}. main.gd
# rouvre la fenêtre correspondante — le HUD ne connaît AUCUNE règle de faction.
signal power_action_requested(action: String)

# Brique identité joueur (E1 §8.73) : réutilisée par la fiche joueur, la zone opérateur et le
# bandeau de combat compact.
const PlayerChipScene := preload("res://scenes/components/player_chip.tscn")
# Kill feed (E4 §8.76) : surimpression des entrées majeures, coin haut-droit hors panneaux.
const KillFeedScene := preload("res://scenes/components/kill_feed.tscn")
# Helpers partagés posés au lot E1 (dégradé de santé pv_color + _tint_progress + police mono).
const RosterHelpers := preload("res://scripts/ui/war_roster.gd")
# Composeur d'objectif traduit (i18n 2026-07-18) : describe(type/params) → texte en langue courante.
const ObjectiveTrackerModule := preload("res://scripts/ui/objective_tracker.gd")

# Teinte des vignettes de cartes (refonte : plus de cartes spéciales, juste un nombre de troupes).
const CARD_TINT := Color("2f7d8c")  # cyan-acier sombre (renforts) — charte Warzone Command
const ACCENT_CYAN := Color("36c5d9")
const ACCENT_GOLD := Color("e0b249")
# Ornements de charte partagés (encoches de coin biseautées, filets cyan) — §2.
const WarzoneUI := preload("res://scripts/ui/warzone_ui.gd")

# =========================================================
# ÉCHELLE TYPOGRAPHIQUE DU HUD (source UNIQUE — passe lisibilité 2026-07-27)
# =========================================================
# Constat Hakim : après la refonte du layout, l'écran gagne énormément de place mais TOUT le texte
# était resté calibré pour l'ancien HUD compact (10-13 px) → illisible à distance de jeu.
# La charte « Warzone Command » repose sur le rythme **eyebrow muet en petit → VALEUR en grand** :
# c'est l'ÉCART entre les deux niveaux qui structure la lecture, pas la taille absolue. On fixe donc
# une échelle explicite (rapport ≈ 1,25 entre deux crans) et on l'applique partout — plus une seule
# taille écrite en dur dans le corps du fichier.
const FS_EYEBROW := 13    # étiquettes muettes en MAJUSCULES (PV, SITUATION, MOUVEMENTS…)
const FS_SMALL := 14      # mentions secondaires (rappels, indices)
const FS_BODY := 16       # texte courant : lignes de fiche, état de pouvoir, objectifs
const FS_VALUE := 17      # valeurs chiffrées (police mono)
const FS_SECTION := 17    # titres de bloc (cyan, MAJUSCULES)
const FS_TITLE := 21      # nom de territoire, libellés forts
const FS_DISPLAY := 26    # bandeau haut, cartes, bandeaux de combat
# Taille des encoches de coin biseautées (charte §2) — un cran au-dessus du défaut des menus :
# les panneaux de l'arène sont plus grands, une encoche de 18 px s'y perdait.
const NOTCH_SIZE := 24.0

# --- Couleurs des barres de stats (SOURCE UNIQUE partagée fiche joueur / opérateur / VS, lot A) :
#     PV = dégradé santé (RosterHelpers.pv_color, vert→or→rouge) · PA = or · PB = cyan ·
#     PP = violet tactique. Chaque barre affiche « valeur / max » en clair. ---
const STAT_PA_COLOR := Color("e0b249")
const STAT_PB_COLOR := Color("36c5d9")
const STAT_PP_COLOR := Color("8c6bd9")

# Délai avant désarmement automatique du bouton ABANDONNER (anti mauvais clic).
const ABANDON_ARM_TIMEOUT := 3.0
# Durées des Tweens natifs (slide des panneaux latéraux, fondu de l'UI pendant le combat).
const SIDE_SLIDE_TIME := 0.35
const COMBAT_FADE_TIME := 0.5
# Slide vertical du panneau inférieur rétractable (§3, ergonomie).
const BOTTOM_SLIDE_TIME := 0.35
# Temps impartis AFFICHÉS en compte à rebours (§8.31, révisé) : 90 s en Phase 0 (déploiement aveugle
# simultané) ; en jeu, le rebours REPART à neuf à CHAQUE « Fin de Phase », avec un budget PAR PHASE.
const PHASE0_TIME := 90.0
# Budget par défaut d'une phase de jeu (Renforts / Déploiement / Mouvement) — miroir de
# DEFAULT_PHASE_TIMEOUT_SECONDS côté serveur (router.py).
const TURN_TIME := 60.0
# Phase d'Attaque (3) : budget de base plus large ET seule phase extensible par la Time Bank (§8.33).
const ATTACK_PHASE := 3
const ATTACK_PHASE_TIME := 90.0
# Plafond VISUEL du rebours en phase d'Attaque = hard_cap serveur (§8.33).
const ATTACK_PHASE_TIME_MAX := 180.0
# Couleurs du timer : normal (crème) puis rouge d'urgence sous le seuil.
const TIMER_COLOR := Color(0.9411765, 0.9019608, 0.8235294)
const TIMER_URGENT_COLOR := Color("d6453f")
const TIMER_URGENT_SECONDS := 10

# Longueur max d'un message — aligné sur le serveur (CHAT_MAX_LENGTH = 500, §8.33).
const CHAT_MAX_LENGTH := 500

# Index des onglets de la zone COMMANDES (barre basse, lot A) — ordre figé par la scène.
const TAB_ACTIONS := 0
const TAB_CARDS := 1
const TAB_JOURNAL := 2

var _log_count := 0
var _elapsed := 0.0          # secondes écoulées sur le tour courant (affichage MM:SS)
var _turn_key := ""          # signature étape|tour|joueur|phase, pour remettre le timer à zéro
var _abandon_armed := false
# --- CHAT PAR DESTINATAIRE (lot B) : UNE conversation affichée à la fois, choisie dans un
# sélecteur (« Tous » + chaque joueur HUMAIN). Le contrat réseau (§8.33) ne change pas — c'est
# uniquement la présentation qui devient sans ambiguïté (constat Hakim : tous les privés étaient
# mélangés dans un seul fil, sans notification, expéditeur illisible).
#   _conversations : conv_key → Array[{ who: String (BBCode déjà colorisé/échappé), text, ts }]
#   conv_key       : "general" (canal public) | str(pid) (fil privé avec ce joueur)
#   _unread        : conv_key → nombre de messages non lus
const CHAT_CONV_GENERAL := "general"
const CHAT_HISTORY_CAP := 200
# §8.122 (LOT C) — écart entre le craquement de talkie et le bip de notification de chat. 60 ms :
# assez pour être perçu comme deux évènements successifs, trop court pour se lire comme un retard.
const CHAT_RADIO_DELAY := 0.06
var _conversations: Dictionary = {}
var _unread: Dictionary = {}
var _current_conv := CHAT_CONV_GENERAL
var _chat_targets: Array = []      # [{id:int (-1 = Tous), name:String, color:Color}]
var _chat_input: LineEdit = null
var _chat_send_btn: Button = null
var _chat_target_option: OptionButton = null
# Toast de message entrant (haut-droite, 3 s) : cliquer ouvre la bonne conversation.
var _chat_toast: Button = null
var _chat_toast_tween: Tween = null
var _chat_toast_conv := ""
# Bandeau haut (lot A) : identité du joueur DONT C'EST LE TOUR (pseudo + couleur plateau), poussée
# par main.gd — le bandeau n'affiche plus que « TOUR DE X · PHASE · MM:SS ».
var _turn_pseudo: String = ""
var _turn_color: Color = Color.WHITE
# Gros bouton « CONFIRMER LE DÉPLOIEMENT » (construit par code, inséré dans l'onglet ACTIONS).
var _confirm_btn: Button = null
# Ré-assaut (E7 §8.79) : bouton « ⚔ RÉ-ASSAUT (S ➜ C) » près de « Fin de Phase ».
var _reassault_btn: Button = null
# Pulse « aucune action possible » sur %NextPhaseButton (E7) : état courant.
var _next_phase_pulse := false

# Panneau latéral COMMS rétractable (§8.29) : slide horizontal via Tween natif.
var _side_tween: Tween
var _side_hidden := false
var _side_shown_x := 0.0
var _side_width := 0.0
var _side_metrics_ready := false
# Fiche joueur (gauche, lot A) : même mécanique de slide, vers la GAUCHE.
var _sheet_tween: Tween
var _sheet_hidden := false
var _sheet_shown_x := 0.0
var _sheet_width := 0.0
var _sheet_metrics_ready := false
# Fondu de l'UI pendant le Split-Screen VS (§8.29) : Tween sur modulate.a du HUD racine.
var _fade_tween: Tween

# Compte à rebours de la PHASE courante (cf. update_display / _process).
var _turn_limit: float = 0.0
# --- Chrono SERVEUR (E3 §8.75) : quand le serveur diffuse son échéance (turn_timer/timer_update),
# %TimerLabel affiche deadline_epoch − (horloge locale + offset). ---
var _srv_active := false
var _srv_deadline_epoch: float = -1.0
var _srv_offset: float = 0.0   # server_time − horloge locale (immunise une horloge PC fausse)
# Pré-alerte AFK (E3) : sous AFK_ALERT_SECONDS sur NOTRE tour, chrono pulsé rouge + tic sonore/s.
const AFK_ALERT_SECONDS := 15
var _last_tick_second := -1
# Time Bank (§8.33) : cumul (s) crédité à la phase d'Attaque COURANTE par add_time_to_timer.
var _turn_bonus: float = 0.0
var _timer_urgent := false   # évite de réécrire la couleur du timer à chaque frame.
# Barre basse rétractable (slide vertical, Tween natif).
var _bottom_tween: Tween
var _bottom_hidden := false
var _bottom_shown_y := 0.0
# Nom de faction AFFICHABLE par joueur (player_id str → nom EN invariant du .tres), poussé par
# main.gd — le bandeau de tour ne montre plus l'id snake_case brut.
var faction_name_by_pid: Dictionary = {}

# Télégraphe de zone (G1 §8.62) : devenu un CHIP discret sous le bandeau haut (lot A) — cliquable,
# il ouvre l'onglet JOURNAL filtré ZONE.
var _zone_chip: Button = null
# Tracker d'objectif vivant (E6 §8.78) : conteneur de mini-lignes (barre + libellé) créé sous
# %ObjectiveLabel. ≥ 80 % → pulse OR (proche de la victoire).
var _objective_tracker: VBoxContainer = null
var _objective_pulse := false
# --- MODE STREAMER (§8.121, LOT E) — anti stream-sniping -----------------------------------------
# L'objectif secret est la SEULE information de l'écran qu'un spectateur puisse exploiter contre le
# joueur (les PP, les stats et la carte sont déjà publics ou sans valeur prédictive). En mode
# streamer, la zone OBJECTIFS et le tracker sont donc remplacés par une plaque « ⬛ INTEL CLASSIFIÉ
# — MAINTENIR POUR RÉVÉLER » : le joueur maintient le clic (ou survole > 0,6 s) pour lire, et
# l'information ne reste JAMAIS à l'écran plus longtemps que ce geste.
# Le renseignement d'ESPIONNAGE (Chasseurs d'Ombres) passe par la MÊME plaque plutôt que par le
# Journal : une ligne de journal ne peut pas être « maintenue pour révéler », et la laisser en clair
# aurait rouvert exactement la fuite que ce mode ferme.
const INTEL_HOVER_DELAY := 0.6
var _streamer_mode := false
var _intel_revealed := false      # vrai pendant le maintien / après le survol prolongé
var _intel_gate: Button = null    # la plaque cliquable
var _intel_hovering := false
var _intel_hover_clock := 0.0
var _spy_intel: String = ""       # objectif espionné (mémorisé, affiché derrière la plaque)
# Le tracker a-t-il des lignes à montrer ? Sans ce drapeau, démasquer l'intel rendrait VISIBLE un
# tracker vide (objectif non encore résolu / spectateur) au lieu de le laisser masqué.
var _objective_has_lines := false
# --- REBOURS GLOBAL DE PARTIE (chantier « Tension & fin de partie », LOT F) -----------------------
# Chip discret MM:SS sous le chrono de TOUR, calé sur `GameState.match_deadline_epoch` avec le MÊME
# offset d'horloge que le chrono de tour (`_srv_offset`) — un PC à l'heure fausse n'y change rien.
# Masqué si aucune échéance (serveur antérieur / limite désactivée). Sous FINAL_PROTOCOL_SECONDS :
# pulse rouge. Le bandeau « ⚠ PROTOCOLE FINAL » et le tic sonore sont pilotés par main.gd (View pure).
const FINAL_PROTOCOL_SECONDS := 120
var _match_chip: Label = null
var _match_deadline_epoch: float = 0.0
var _match_urgent := false
var _match_last_tick := -1
# Mini-classement de DÉPARTAGE (PROTOCOLE FINAL uniquement) : panneau compact 3-5 lignes, alimenté
# par main.gd depuis l'état PUBLIC. Créé à la demande, détruit à la sortie du protocole.
var _tiebreak_panel: PanelContainer = null
var _tiebreak_rows: VBoxContainer = null
# Prévision de combat (G4 §8.63) : ligne « PRÉVISION : victoire NN % … » créée par code sous
# l'instruction (onglet ACTIONS), visible uniquement au survol d'une cible valide en Phase 3.
var _odds_label: Label = null

# --- Journal de Guerre 2.0 (E4 §8.76) : flux structuré {category, icon, rich_text, tid, major},
# filtrable (chips TOUS/⚔/☢/🃏/⚙) et cliquable ([url=<tid>] → caméra). Vit désormais dans
# l'onglet JOURNAL de la barre basse (lot A) ; badge « • » quand l'onglet n'est pas ouvert. ---
const FEED_MAX := 200
var _feed_entries: Array = []
var _feed_filter := "all"
var _feed_filter_buttons: Dictionary = {}
var _feed_unread := false
var _kill_feed: Control = null
# Toast défensif (E4) : panneau furtif « ⚠ X ATTAQUÉ PAR Y » — le plus récent remplace l'ancien.
var _defense_toast: PanelContainer = null
var _toast_tween: Tween = null
# Bandeau de combat compact (E8 §8.80) : conservé comme REPLI si la flèche de guerre (lot D) ne
# peut pas se charger — jamais de crash, jamais de combat muet.
var _combat_banner: PanelContainer = null
var _combat_banner_tween: Tween = null

const HERO_DANGER := Color("d6453f")
const HERO_MUTED := Color("8a97a5")

# --- Zone OPÉRATEUR (barre basse) : identité + pouvoir + 4 barres de stats du héros LOCAL. ---
var _op_chip: Control = null
var _op_identity: Label = null
var _op_power_title: Label = null
var _op_power_state: Label = null
var _op_stats_box: VBoxContainer = null
var _op_built := false

# --- FICHE JOUEUR (panneau gauche) : ordre de navigation + joueur affiché. ---
var _sheet_order: Array = []      # pids ordonnés (turn_order), poussés par main.gd
var _sheet_pid: int = -9999       # joueur actuellement affiché (-9999 = aucun)

func _ready() -> void:
	%NextPhaseButton.pressed.connect(func(): pass_pressed.emit())
	%AbandonButton.pressed.connect(_on_abandon_clicked)
	%ToggleSidePanelButton.pressed.connect(_toggle_side_panel)
	%ToggleBottomPanelButton.pressed.connect(_toggle_bottom_panel)
	%TogglePlayerSheetButton.pressed.connect(_toggle_player_sheet)
	# Fiche joueur (lot A) : les flèches parcourent l'ordre de tour et RE-ÉMETTENT
	# roster_player_clicked (même sémantique que l'ancien clic de ligne du War Roster).
	%SheetPrevButton.pressed.connect(_on_sheet_step.bind(-1))
	%SheetNextButton.pressed.connect(_on_sheet_step.bind(1))
	# SFX d'interface (survol/clic — R6) sur les boutons d'action du HUD.
	for b in [%NextPhaseButton, %AbandonButton, %ToggleSidePanelButton, %ToggleBottomPanelButton,
			%TogglePlayerSheetButton, %SheetPrevButton, %SheetNextButton]:
		b.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
		b.pressed.connect(func() -> void: AudioManager.play_sfx("click"))
	# Titres TRADUITS des onglets COMMANDES (le nom de nœud sert de clé, mais on ne dépend pas de
	# l'auto-traduction du TabBar : on pose explicitement les libellés en langue courante).
	%CommandsTabs.set_tab_title(TAB_ACTIONS, tr("HUD_TAB_ACTIONS"))
	%CommandsTabs.set_tab_title(TAB_CARDS, tr("HUD_TAB_CARDS"))
	%CommandsTabs.set_tab_title(TAB_JOURNAL, tr("HUD_TAB_JOURNAL"))
	%CommandsTabs.tab_changed.connect(_on_command_tab_changed)
	_build_confirm_button()
	_build_operator_zone()
	_setup_chat_selector()
	_build_chat_input()
	_build_feed_filters()
	_build_kill_feed()
	_build_reassault_button()
	_build_amount_shortcuts()
	_ensure_zone_chip()
	_ensure_match_chip()
	_apply_charter_ornaments()
	# Fiche joueur repliée au départ : l'écran s'ouvre sur le plateau, pas sur un panneau.
	_collapse_player_sheet_initially()

	# MODE STREAMER (§8.121, LOT E) — posé EN DERNIER dans _ready : la plaque s'insère dans la zone
	# OBJECTIFS, et _apply_charter_ornaments (ci-dessus) y a déjà glissé son filet de titre en
	# comptant sur l'ordre des enfants. Inverser les deux déplacerait le filet sous la plaque.
	_streamer_mode = bool(SettingsManager.get_comfort("streamer_mode"))
	SettingsManager.comfort_changed.connect(_on_comfort_changed)
	_apply_intel_gate()

# Ornements de la charte « Warzone Command » (§2) posés sur les 3 panneaux vitrés de l'arène :
# encoches de coin biseautées cyan (ADN angulaire) + filet fin sous chaque titre de bloc. Ils
# étaient déjà la signature des écrans hub, mais l'arène ne les portait pas — c'est ce qui la
# faisait paraître « générique » à côté du reste du jeu.
func _apply_charter_ornaments() -> void:
	for panel in [%ChatLog.get_parent().get_parent().get_parent(),   # SidePanelWidget/GlassBody
			%SheetVBox.get_parent().get_parent(),                     # PlayerSheetWidget/GlassBody
			%ToggleBottomPanelButton.get_parent().get_node("GlassBody")]:
		if panel is Control:
			WarzoneUI.add_corner_notches(panel, NOTCH_SIZE)
	# Filet cyan sous CHAQUE titre de bloc (OBJECTIFS, OPÉRATEUR, COMMS, FICHE JOUEUR) : le titre
	# ne flotte plus au-dessus du contenu, il le COIFFE (structure lisible d'un coup d'œil).
	for title in [%ObjectiveLabel.get_parent().get_child(0),
			%OperatorZone.get_child(0),
			%ChatLog.get_parent().get_parent().get_child(0),
			%SheetVBox.get_child(0)]:
		if title is Control:
			var holder: Node = (title as Control).get_parent()
			var filet := WarzoneUI.add_filet(holder, 2)
			holder.move_child(filet, (title as Control).get_index() + 1)
	# Clic d'une entrée [url=<tid>] du journal (E4 §8.76) → remonte au contrôleur (caméra).
	%LogText.meta_clicked.connect(func(meta) -> void: log_territory_clicked.emit(str(meta)))
	# Chat de salle CÂBLÉ au réseau (§8.33) : main.gd relaie chat_send_requested -> NetworkManager
	# et route les messages reçus vers push_chat_message (une conversation par destinataire, lot B).
	add_chat_message("general", tr("HUD_CHAT_WELCOME_GENERAL"))

# Compte à rebours du tour courant, affiché MM:SS. Mode SERVEUR (E3 §8.75) : rebours calé sur
# l'échéance diffusée. Mode LEGACY (serveur antérieur, §9.2) : décompte local depuis _turn_limit.
func _process(delta: float) -> void:
	# reduced_motion (E10 §8.82) : coupe les pulses d'UI (objectif E6, phase E7) — état figé lisible.
	var still: bool = bool(SettingsManager.get_comfort("reduced_motion"))
	# Tracker d'objectif (E6 §8.78) : pulse OR discret quand on est à ≥ 80 % de la victoire.
	if _objective_pulse and not still and _objective_tracker != null and is_instance_valid(_objective_tracker):
		var g := 0.72 + 0.28 * absf(sin(float(Time.get_ticks_msec()) / 340.0))
		_objective_tracker.modulate = Color(1.0, 1.0, g)
	# Coup de pouce de phase (E7 §8.79) : pulse OR de « Fin de Phase » quand rien n'est jouable.
	if _next_phase_pulse and not still:
		var p := 0.7 + 0.3 * absf(sin(float(Time.get_ticks_msec()) / 300.0))
		%NextPhaseButton.modulate = Color(ACCENT_GOLD.r, ACCENT_GOLD.g, ACCENT_GOLD.b, 1.0).lerp(
			Color(1, 1, 1, 1), 1.0 - p)
	elif _next_phase_pulse and still:
		%NextPhaseButton.modulate = ACCENT_GOLD   # état figé mais distinct (accessibilité)
	# Rebours GLOBAL de partie (LOT F) : rendu à chaque frame comme le chrono de tour, mais
	# INDÉPENDANT de lui (il tourne aussi pendant un tour de bot, où `turn_timer` est nul).
	_render_match_countdown(still)
	# MODE STREAMER (§8.121) : révélation par SURVOL PROLONGÉ (> 0,6 s) en plus du maintien du clic —
	# le maintien est le geste sûr en direct, le survol le geste confortable hors caméra.
	if _streamer_mode and _intel_hovering and not _intel_revealed:
		_intel_hover_clock += delta
		if _intel_hover_clock >= INTEL_HOVER_DELAY:
			_intel_revealed = true
			_apply_intel_gate()
	if _srv_active:
		var remaining_f := _srv_deadline_epoch - (Time.get_unix_time_from_system() + _srv_offset)
		_render_remaining(int(ceil(maxf(0.0, remaining_f))))
		return
	if _turn_limit <= 0.0:
		if _timer_urgent:
			_timer_urgent = false
			%TimerLabel.add_theme_color_override("font_color", TIMER_COLOR)
		%TimerLabel.modulate.a = 1.0
		%TimerLabel.text = "--:--"
		return
	_elapsed += delta
	_render_remaining(int(ceil(maxf(0.0, _turn_limit - _elapsed))))

# Rendu partagé du rebours (modes serveur ET legacy) : MM:SS, urgence rouge, et pré-alerte AFK
# (E3) — sous 15 s sur NOTRE tour : pulse + tic sonore discret à chaque seconde.
func _render_remaining(remaining: int) -> void:
	%TimerLabel.text = "%02d:%02d" % [floori(remaining / 60.0), remaining % 60]
	var my_turn: bool = GameState.stage == "playing" \
		and int(GameState.current_player_id) == int(AuthManager.user_id)
	var alert: bool = my_turn and remaining > 0 and remaining <= AFK_ALERT_SECONDS
	var urgent: bool = remaining <= TIMER_URGENT_SECONDS or alert
	if urgent != _timer_urgent:
		_timer_urgent = urgent
		%TimerLabel.add_theme_color_override(
			"font_color", TIMER_URGENT_COLOR if urgent else TIMER_COLOR)
	if alert:
		# Pulse doux (sinus) — coupé net dès la sortie d'alerte.
		%TimerLabel.modulate.a = 0.62 + 0.38 * absf(sin(float(Time.get_ticks_msec()) / 260.0))
		if remaining != _last_tick_second:
			_last_tick_second = remaining
			AudioManager.play_sfx("timer_tick")
	else:
		%TimerLabel.modulate.a = 1.0
		_last_tick_second = -1

# =========================================================
# REBOURS GLOBAL DE PARTIE + MINI-CLASSEMENT DE DÉPARTAGE
# (chantier « Tension & fin de partie », LOT F)
# =========================================================

func _ensure_match_chip() -> void:
	if _match_chip != null and is_instance_valid(_match_chip):
		return
	_match_chip = Label.new()
	_match_chip.name = "MatchCountdownChip"
	_match_chip.tooltip_text = tr("MATCH_TIMER_TOOLTIP")
	_match_chip.mouse_filter = Control.MOUSE_FILTER_STOP  # le tooltip a besoin de capter le survol
	_match_chip.add_theme_font_size_override("font_size", FS_EYEBROW)
	_match_chip.add_theme_color_override("font_color", HERO_MUTED)
	_match_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_match_chip.visible = false
	# Inséré JUSTE SOUS le chrono de tour, dans son propre conteneur : les deux rebours se lisent
	# empilés (tour au-dessus, partie en dessous) au lieu de se disputer une place au centre.
	var anchor: Control = %TimerLabel
	var parent := anchor.get_parent()
	parent.add_child(_match_chip)
	parent.move_child(_match_chip, anchor.get_index() + 1)


# Échéance GLOBALE de la partie (epoch mur serveur), poussée par main.gd depuis l'état.
# `server_time` sert au MÊME calcul d'offset que le chrono de tour (§8.31) : on ne fait jamais
# confiance à l'horloge du PC. 0.0 → chip masqué (serveur antérieur / limite désactivée).
func set_match_deadline(deadline_epoch: float, server_time: float) -> void:
	_ensure_match_chip()
	if server_time > 0.0:
		_srv_offset = server_time - Time.get_unix_time_from_system()
	_match_deadline_epoch = maxf(0.0, deadline_epoch)
	_match_chip.visible = _match_deadline_epoch > 0.0


# Rendu du rebours global : MM:SS, rouge pulsé sous FINAL_PROTOCOL_SECONDS, tic sonore par seconde
# dans la dernière minute (le même `timer_tick` que la pré-alerte AFK — on ne crée pas un 2ᵉ son
# pour un 2ᵉ rebours, l'oreille en ferait une bouillie).
func _render_match_countdown(still: bool) -> void:
	if _match_chip == null or not is_instance_valid(_match_chip) or _match_deadline_epoch <= 0.0:
		return
	var remaining := int(ceil(maxf(0.0,
		_match_deadline_epoch - (Time.get_unix_time_from_system() + _srv_offset))))
	_match_chip.text = tr("MATCH_TIMER_FMT") % [floori(remaining / 60.0), remaining % 60]
	var urgent := remaining <= FINAL_PROTOCOL_SECONDS
	if urgent != _match_urgent:
		_match_urgent = urgent
		_match_chip.add_theme_color_override(
			"font_color", TIMER_URGENT_COLOR if urgent else HERO_MUTED)
	if urgent and not still:
		_match_chip.modulate.a = 0.55 + 0.45 * absf(sin(float(Time.get_ticks_msec()) / 300.0))
	else:
		_match_chip.modulate.a = 1.0
	# Tic sonore de la DERNIÈRE MINUTE seulement : à 2 min il serait interminable.
	if urgent and remaining <= 60 and remaining > 0 and remaining != _match_last_tick:
		_match_last_tick = remaining
		AudioManager.play_sfx("timer_tick")


func _ensure_tiebreak_panel() -> void:
	if _tiebreak_panel != null and is_instance_valid(_tiebreak_panel):
		return
	_tiebreak_panel = PanelContainer.new()
	_tiebreak_panel.name = "TiebreakBoard"
	_tiebreak_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.058824, 0.07451, 0.094118, 0.88)
	st.set_corner_radius_all(0)
	st.set_border_width_all(2)
	st.border_color = TIMER_URGENT_COLOR
	st.set_content_margin_all(10.0)
	_tiebreak_panel.add_theme_stylebox_override("panel", st)
	# HAUT-GAUCHE : la colonne droite porte déjà le chip de zone et ABANDONNER, le centre le
	# bandeau de tour. La gauche est la seule zone libre pendant une fin de partie.
	_tiebreak_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_tiebreak_panel.offset_left = 16.0
	_tiebreak_panel.offset_top = 96.0
	add_child(_tiebreak_panel)
	WarzoneUI.add_corner_notches(_tiebreak_panel, 14.0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_tiebreak_panel.add_child(box)
	var title := Label.new()
	title.text = tr("SCOREBOARD_TITLE")
	title.add_theme_font_size_override("font_size", FS_EYEBROW)
	title.add_theme_color_override("font_color", TIMER_URGENT_COLOR)
	box.add_child(title)
	_tiebreak_rows = VBoxContainer.new()
	_tiebreak_rows.add_theme_constant_override("separation", 1)
	box.add_child(_tiebreak_rows)


# Mini-classement de DÉPARTAGE, affiché UNIQUEMENT pendant le PROTOCOLE FINAL.
# `rows` (résolues par main.gd, View pure §6.1) : liste ordonnée de
#   { name: String, color: Color, objective: String, hero_pv: int, kills: int }
# `objective` est une CHAÎNE déjà décidée par le contrôleur : le vrai pourcentage pour SOI,
# « ??? » pour autrui — le % d'objectif d'un adversaire reste SECRET jusqu'au game_over, et c'est
# précisément cette incertitude qui fait la tension. Liste vide → panneau retiré.
func set_tiebreak_board(rows: Array) -> void:
	if rows.is_empty():
		if _tiebreak_panel != null and is_instance_valid(_tiebreak_panel):
			_tiebreak_panel.queue_free()
			_tiebreak_panel = null
			_tiebreak_rows = null
		return
	_ensure_tiebreak_panel()
	for c in _tiebreak_rows.get_children():
		_tiebreak_rows.remove_child(c)
		c.queue_free()
	for r in rows:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var line := RichTextLabel.new()
		line.bbcode_enabled = true
		line.fit_content = true
		line.scroll_active = false
		line.autowrap_mode = TextServer.AUTOWRAP_OFF
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_font_size_override("normal_font_size", FS_SMALL)
		var col: Color = r.get("color", Color("eef3f7"))
		line.text = tr("SCOREBOARD_ROW_FMT") % [
			col.to_html(false), str(r.get("name", "")),
			str(r.get("objective", "")), int(r.get("hero_pv", 0)), int(r.get("kills", 0))]
		_tiebreak_rows.add_child(line)


# --- API du chrono SERVEUR (E3 §8.75), pilotée par update_display() et main._on_timer_update ---

func apply_server_timer(deadline_epoch: float, server_time: float) -> void:
	if deadline_epoch <= 0.0:
		clear_server_timer()
		return
	if server_time > 0.0:
		_srv_offset = server_time - Time.get_unix_time_from_system()
	_srv_deadline_epoch = deadline_epoch
	_srv_active = true

func clear_server_timer() -> void:
	_srv_active = false
	_srv_deadline_epoch = -1.0

# Message léger timer_update (relayé par main.gd). reason == "time_bank" → le delta entre la
# nouvelle échéance et l'ancienne devient un flotteur « +N s » or près du chrono (§8.33 visible).
func apply_timer_update(deadline_epoch: float, reason: String, server_time: float) -> void:
	if reason == "time_bank" and _srv_active and _srv_deadline_epoch > 0.0:
		show_time_bank_gain(int(round(deadline_epoch - _srv_deadline_epoch)))
	apply_server_timer(deadline_epoch, server_time)

# Flotteur « +N s » OR près du chrono (E3) : le gain de Time Bank (§8.33) devient VISIBLE.
func show_time_bank_gain(seconds: int) -> void:
	if seconds <= 0:
		return
	var lbl := Label.new()
	lbl.text = "+%d s" % seconds
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", ACCENT_GOLD)
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	var anchor: Control = %TimerLabel
	lbl.global_position = anchor.global_position + Vector2(anchor.size.x + 10.0, -2.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 34.0, 1.1) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var fade := create_tween()
	fade.tween_interval(0.7)
	fade.tween_property(lbl, "modulate:a", 0.0, 0.4)
	fade.tween_callback(lbl.queue_free)

# Budget du rebours pour la phase de JEU courante (miroir de router._playing_phase_budget).
func _phase_turn_limit() -> float:
	if int(GameState.current_phase) == ATTACK_PHASE:
		return minf(ATTACK_PHASE_TIME + _turn_bonus, ATTACK_PHASE_TIME_MAX)
	return TURN_TIME

# Time Bank (§8.33) : crédite le rebours LOCAL de la phase d'Attaque (miroir de
# RoomTimers.extend_deadline). No-op en mode chrono SERVEUR (le +10 s arrive par timer_update).
func add_time_to_timer(seconds: int) -> void:
	if _srv_active:
		return
	if seconds <= 0 or _turn_limit <= 0.0:
		return
	_turn_bonus = minf(_turn_bonus + float(seconds), ATTACK_PHASE_TIME_MAX - ATTACK_PHASE_TIME)
	_turn_limit = _phase_turn_limit()

# =========================================================
# Abandon (Fallen Empire) — armement en 2 clics
# =========================================================

func _on_abandon_clicked() -> void:
	if _abandon_armed:
		_disarm_abandon()
		abandon_pressed.emit()
		return
	_abandon_armed = true
	%AbandonButton.text = tr("HUD_ABANDON_CONFIRM")
	get_tree().create_timer(ABANDON_ARM_TIMEOUT).timeout.connect(_disarm_abandon)

func _disarm_abandon() -> void:
	# Le timer d'armement peut se déclencher APRÈS la confirmation serveur : on ne
	# réécrit pas le libellé d'un bouton déjà verrouillé par lock_abandon_button().
	if %AbandonButton.disabled:
		return
	_abandon_armed = false
	%AbandonButton.text = tr("HUD_ABANDON")

# Verrouille définitivement le bouton une fois l'abandon CONFIRMÉ par le serveur.
func lock_abandon_button() -> void:
	_abandon_armed = false
	%AbandonButton.text = tr("HUD_ABANDONED")
	%AbandonButton.disabled = true

# =========================================================
# API utilisée par le contrôleur (main.gd)
# =========================================================

func get_amount() -> int:
	return int(%AmountSpin.value)

func set_instruction(text: String) -> void:
	%InstructionLabel.text = text

# Bandeau haut MINIMAL (lot A) : identité du joueur DONT C'EST LE TOUR (pseudo + couleur plateau),
# résolue par main.gd (View pure §6.1). Le libellé complet est composé par update_display().
func set_turn_identity(pseudo: String, color: Color) -> void:
	_turn_pseudo = pseudo
	_turn_color = color

# =========================================================
# Prévision de combat (G4 §8.63) — « PRÉVISION : victoire NN % · pertes est. N,N »
# =========================================================
# Ligne créée par code SOUS l'instruction (onglet ACTIONS) : cyan si ≥ 65 %, or si 40-65 %,
# rouge si < 40 %. Calcul 100 % client (CombatOdds).

func _ensure_odds_label() -> void:
	if _odds_label != null and is_instance_valid(_odds_label):
		return
	_odds_label = Label.new()
	_odds_label.name = "CombatOddsLabel"
	_odds_label.add_theme_font_size_override("font_size", FS_BODY)
	_odds_label.visible = false
	var anchor: Control = %InstructionLabel
	var parent := anchor.get_parent()
	parent.add_child(_odds_label)
	parent.move_child(_odds_label, anchor.get_index() + 1)

func show_forecast(win_prob: float, exp_losses: float) -> void:
	_ensure_odds_label()
	var pct := int(round(win_prob * 100.0))
	var col: Color = Color("d6453f")  # rouge danger (< 40 %)
	if win_prob >= 0.65:
		col = ACCENT_CYAN
	elif win_prob >= 0.40:
		col = ACCENT_GOLD
	var losses_txt := ("%.1f" % exp_losses).replace(".", ",")
	_odds_label.text = tr("HUD_FORECAST_FMT") % [pct, losses_txt]
	_odds_label.add_theme_color_override("font_color", col)
	_odds_label.visible = true

func hide_forecast() -> void:
	if _odds_label != null and is_instance_valid(_odds_label):
		_odds_label.visible = false

# Active/désactive le bouton « Fin de Phase » (verrou anti double-envoi piloté par main.gd, §8.48).
func set_pass_enabled(enabled: bool) -> void:
	%NextPhaseButton.disabled = not enabled

# =========================================================
# Commandement fluide (E7 §8.79) — ré-assaut, raccourcis quantité, coup de pouce de phase
# =========================================================

func _build_reassault_button() -> void:
	_reassault_btn = Button.new()
	_reassault_btn.visible = false
	_reassault_btn.add_theme_font_size_override("font_size", FS_BODY)
	_reassault_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var style := StyleBoxFlat.new()
	style.bg_color = Color("d6453f").darkened(0.35)
	style.border_color = Color("d6453f")
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.set_content_margin_all(8)
	var hover := style.duplicate()
	hover.bg_color = Color("d6453f").darkened(0.1)
	_reassault_btn.add_theme_stylebox_override("normal", style)
	_reassault_btn.add_theme_stylebox_override("hover", hover)
	_reassault_btn.add_theme_stylebox_override("pressed", hover)
	_reassault_btn.add_theme_color_override("font_color", Color("f0e6d2"))
	_reassault_btn.pressed.connect(func() -> void:
		AudioManager.play_sfx("click")
		reassault_pressed.emit())
	var row := %NextPhaseButton.get_parent()
	row.add_child(_reassault_btn)
	row.move_child(_reassault_btn, %NextPhaseButton.get_index())

# Pilote le bouton « RÉ-ASSAUT » : active=false → masqué ; sinon libellé « ⚔ RÉ-ASSAUT (S ➜ C) ».
func set_reassault(active: bool, source_name: String = "", target_name: String = "") -> void:
	if _reassault_btn == null:
		return
	_reassault_btn.visible = active
	if active:
		_reassault_btn.text = tr("HUD_REASSAULT_FMT") % [source_name, target_name]

# Raccourcis de quantité +1 / +5 / MAX accolés à %AmountSpin (E7 §8.79).
func _build_amount_shortcuts() -> void:
	var spin: Control = %AmountSpin
	var row := spin.get_parent()
	var defs := [["+1", 1], ["+5", 5], ["MAX", -1]]
	var idx := spin.get_index() + 1
	for d in defs:
		var b := Button.new()
		b.text = str(d[0])
		b.custom_minimum_size = Vector2(50, 42)
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.add_theme_font_size_override("font_size", FS_SMALL)
		var delta := int(d[1])
		b.pressed.connect(func() -> void:
			AudioManager.play_sfx("click")
			amount_quick.emit(delta))
		row.add_child(b)
		row.move_child(b, idx)
		idx += 1

# Coup de pouce de phase (E7 §8.79) : %NextPhaseButton pulse OR + tooltip quand AUCUNE action
# n'est possible dans la phase courante (calcul local main.gd — le serveur reste seul juge §8.48).
func pulse_next_phase(on: bool) -> void:
	_next_phase_pulse = on
	if not on:
		%NextPhaseButton.modulate = Color(1, 1, 1, 1)
		%NextPhaseButton.tooltip_text = ""
	else:
		%NextPhaseButton.tooltip_text = tr("CMD_NO_ACTION")

# =========================================================
# Barres de stats PV/PA/PB/PP (lot A) — SOURCE UNIQUE partagée fiche joueur / opérateur
# =========================================================
# Chaque barre : eyebrow (PV/PA/PB/PP) + ProgressBar teintée + valeur « n / max » en clair.
# `ratio_color` null → couleur fixe ; sinon dégradé de santé (RosterHelpers.pv_color).

func _stat_bar(label_key: String, value_text: String, ratio: float, col: Color,
		tooltip_key: String = "") -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	if tooltip_key != "":
		row.tooltip_text = tr(tooltip_key)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
	var eyebrow := Label.new()
	eyebrow.text = tr(label_key)
	eyebrow.custom_minimum_size = Vector2(34, 0)
	eyebrow.add_theme_font_size_override("font_size", FS_EYEBROW)
	eyebrow.add_theme_color_override("font_color", HERO_MUTED)
	eyebrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(eyebrow)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(64, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.max_value = 1.0
	bar.value = clampf(ratio, 0.0, 1.0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_bar(bar, col)
	row.add_child(bar)
	var val := Label.new()
	val.text = value_text
	val.custom_minimum_size = Vector2(74, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.add_theme_font_size_override("font_size", FS_VALUE)
	val.add_theme_color_override("font_color", Color("eef3f7"))
	val.add_theme_font_override("font", RosterHelpers._mono_font())
	val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(val)
	return row

# Style COMPLET d'une jauge de la charte : remplissage à la couleur donnée ET **piste sombre**
# derrière. `RosterHelpers._tint_progress` ne pose que le remplissage : sans piste, la portion vide
# se confondait avec le fond du panneau et on ne lisait pas « 48 sur 60 », seulement « une barre ».
# Liseré cyan très discret pour raccrocher la jauge à l'ADN angulaire (coins droits, §2).
func _style_bar(bar: ProgressBar, col: Color) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.07)
	track.border_color = Color(ACCENT_CYAN, 0.22)
	track.set_border_width_all(1)
	track.set_corner_radius_all(0)
	bar.add_theme_stylebox_override("background", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(0)
	bar.add_theme_stylebox_override("fill", fill)

# Les 4 barres d'un héros (PV/PA/PB/PP) empilées dans `box` (vidé au préalable). `hero` = dict
# normalisé GameState.hero_of(pid). Héros non initialisé (pv_max <= 0) → mention discrète.
func _fill_hero_stats(box: VBoxContainer, hero: Dictionary) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var pv_max := int(hero.get("pv_max", 0))
	if hero.is_empty() or pv_max <= 0:
		var none := Label.new()
		none.text = tr("HUD_NO_HERO")
		none.add_theme_font_size_override("font_size", FS_BODY)
		none.add_theme_color_override("font_color", HERO_MUTED)
		box.add_child(none)
		return
	var pv := int(hero.get("pv_current", 0))
	var dead: bool = bool(hero.get("is_dead", false))
	var pv_ratio := 0.0 if dead else clampf(float(pv) / float(pv_max), 0.0, 1.0)
	box.add_child(_stat_bar("HUD_STAT_PV",
		tr("HUD_STAT_PV_VALUE_FMT") % [0 if dead else pv, pv_max], pv_ratio,
		HERO_DANGER if dead else RosterHelpers.pv_color(pv_ratio), "HUD_STAT_PV_TOOLTIP"))
	# PA : points d'attaque du héros — normalisés sur PA_DISPLAY_MAX pour donner une barre lisible
	# (le moteur n'expose pas de plafond de PA ; la VALEUR chiffrée reste la vérité).
	var pa := int(hero.get("pa", 0))
	box.add_child(_stat_bar("HUD_STAT_PA", str(pa),
		clampf(float(pa) / float(PA_DISPLAY_MAX), 0.0, 1.0), STAT_PA_COLOR, "CHAR_STAT_PA_DESC"))
	# PB : réduction de dégâts (0..1 côté serveur) → pourcentage entier.
	var pb := clampf(float(hero.get("pb", 0.0)), 0.0, 1.0)
	box.add_child(_stat_bar("HUD_STAT_PB", tr("HUD_STAT_PB_VALUE_FMT") % int(round(pb * 100.0)),
		pb / PB_DISPLAY_MAX, STAT_PB_COLOR, "ROSTER_PB_TOOLTIP"))
	# PP : momentum de combat, borné [pp_min, pp_max] par le serveur.
	# §8.119 — TOOLTIP UNIFIÉ `PP_TOOLTIP` (et non plus `CHAR_STAT_PP_DESC`, qui décrivait des PP
	# purement passifs) : les PP sont désormais aussi une MONNAIE (RATIONNER + pouvoir de héros).
	# `_fill_hero_stats` étant la source UNIQUE des barres de stats, cette seule ligne met le
	# tooltip à jour sur TOUS les écrans qui l'utilisent (fiche joueur ET zone opérateur).
	var pp := int(hero.get("pp_current", 0))
	var pp_min := int(hero.get("pp_min", 0))
	var pp_max := int(hero.get("pp_max", 0))
	var span := maxi(pp_max - pp_min, 1)
	box.add_child(_stat_bar("HUD_STAT_PP", tr("HUD_STAT_PP_VALUE_FMT") % [pp, pp_max],
		clampf(float(pp - pp_min) / float(span), 0.0, 1.0), STAT_PP_COLOR, "PP_TOOLTIP"))

# Plafonds d'AFFICHAGE des barres PA/PB (aucune valeur de jeu : purement visuel — la valeur
# chiffrée à droite de chaque barre reste la vérité). PA 30 = ordre de grandeur d'un héros de
# haut niveau ; PB 0,60 = deux fois la réduction maximale observée (30 %), barre jamais saturée.
const PA_DISPLAY_MAX := 30.0
const PB_DISPLAY_MAX := 0.60

# =========================================================
# Zone OPÉRATEUR (barre basse) — moi : identité, pouvoir de faction, stats en barres
# =========================================================

func _build_operator_zone() -> void:
	var zone: VBoxContainer = %OperatorZone
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	zone.add_child(head)
	_op_chip = PlayerChipScene.instantiate()
	_op_chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	head.add_child(_op_chip)
	_op_identity = Label.new()
	_op_identity.add_theme_font_size_override("font_size", FS_BODY)
	_op_identity.add_theme_color_override("font_color", HERO_MUTED)
	_op_identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_op_identity.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_op_identity)

	_op_power_title = Label.new()
	_op_power_title.add_theme_font_size_override("font_size", FS_BODY)
	_op_power_title.add_theme_color_override("font_color", ACCENT_GOLD)
	_op_power_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	zone.add_child(_op_power_title)

	_op_power_state = Label.new()
	_op_power_state.add_theme_font_size_override("font_size", FS_SMALL)
	_op_power_state.add_theme_color_override("font_color", ACCENT_CYAN)
	_op_power_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	zone.add_child(_op_power_state)

	_op_stats_box = VBoxContainer.new()
	_op_stats_box.add_theme_constant_override("separation", 2)
	zone.add_child(_op_stats_box)
	_op_built = true

# Alimente la zone OPÉRATEUR. data = {
#   pid, pseudo, color, faction_name, leader, power_label, power_state, hero } — TOUT est résolu
# par main.gd (View pure §6.1).
func set_operator_panel(data: Dictionary) -> void:
	if not _op_built:
		return
	var pid := int(data.get("pid", -9999))
	if pid != -9999:
		_op_chip.setup(pid, false)
	var leader := str(data.get("leader", ""))
	var faction := str(data.get("faction_name", ""))
	_op_identity.text = ("%s · %s" % [leader, faction]) if leader != "" else faction
	var power := str(data.get("power_label", ""))
	_op_power_title.text = (tr("HUD_OPERATOR_POWER_FMT") % power) if power != "" else ""
	_op_power_title.visible = power != ""
	var state := str(data.get("power_state", ""))
	_op_power_state.text = state
	_op_power_state.visible = state != ""
	var hero = data.get("hero", {})
	_fill_hero_stats(_op_stats_box, hero if typeof(hero) == TYPE_DICTIONARY else {})
	# §8.119 — FLUCTUATION VISIBLE DES PP hors Split-Screen VS. Les PP bougeaient à chaque assaut
	# sans que rien ne le signale en dehors du VS (donc jamais pour les combats des AUTRES, ni après
	# un rationnement) : le joueur voyait une jauge sauter sans cause. On compare la valeur reçue à
	# la précédente et on fait flotter une flèche ▲/▼ furtive sur la zone opérateur.
	if typeof(hero) == TYPE_DICTIONARY and int(hero.get("pv_max", 0)) > 0:
		_track_pp_fluctuation(int(hero.get("pp_current", 0)))

# PP mémorisés au dernier rafraîchissement (§8.119). `INF` = jamais reçu → aucune flèche au premier
# état (sinon toute prise de contrôle afficherait un faux « gain » depuis 0).
var _last_pp: float = INF

func _track_pp_fluctuation(pp: int) -> void:
	var previous := _last_pp
	_last_pp = float(pp)
	if previous == INF or int(previous) == pp:
		return
	var delta := pp - int(previous)
	_spawn_pp_arrow(delta)

# Flèche ▲/▼ + delta chiffré, flottant 0,9 s au-dessus de la zone opérateur. Glyphes ▲/▼ : mêmes
# blocs Unicode que les ☢/⚠ déjà rendus par le jeu (aucun emoji — cf. tofu constaté en capture).
func _spawn_pp_arrow(delta: int) -> void:
	if not _op_built:
		return
	# reduced_motion (E10 §8.82) : pas d'animation, mais l'information reste lisible — on n'a pas
	# le droit de la SUPPRIMER (ce serait cacher une donnée de jeu), seulement de la figer.
	var still: bool = bool(SettingsManager.get_comfort("reduced_motion"))
	var zone: Control = %OperatorZone
	var lbl := Label.new()
	lbl.text = ("▲ +%d PP" % delta) if delta > 0 else ("▼ %d PP" % delta)
	lbl.add_theme_font_size_override("font_size", FS_VALUE)
	lbl.add_theme_color_override("font_color", ACCENT_CYAN if delta > 0 else HERO_DANGER)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.z_index = 60
	zone.add_child(lbl)
	lbl.position = Vector2(zone.size.x * 0.55, zone.size.y * 0.5)
	if still:
		get_tree().create_timer(1.2).timeout.connect(func() -> void:
			if is_instance_valid(lbl):
				lbl.queue_free())
		return
	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 26.0, 0.9)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.9).set_delay(0.25)
	tw.chain().tween_callback(lbl.queue_free)

# §8.119 — Flotteur VERT « +N PV » sur la zone opérateur quand NOTRE héros se soigne (RATIONNER).
# Pendant exact de `pulse_hero_pain` : le soin doit être aussi lisible que les dégâts.
func float_hero_heal(amount: int) -> void:
	if not _op_built or amount <= 0:
		return
	var zone: Control = %OperatorZone
	var lbl := Label.new()
	lbl.text = tr("ABILITY_HEAL_FLOAT_FMT") % amount
	lbl.add_theme_font_size_override("font_size", FS_BODY)
	lbl.add_theme_color_override("font_color", Color("7fff00"))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.z_index = 60
	zone.add_child(lbl)
	lbl.position = Vector2(zone.size.x * 0.12, zone.size.y * 0.5)
	if bool(SettingsManager.get_comfort("reduced_motion")):
		get_tree().create_timer(1.2).timeout.connect(func() -> void:
			if is_instance_valid(lbl):
				lbl.queue_free())
		return
	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 30.0, 1.0)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.0).set_delay(0.35)
	tw.chain().tween_callback(lbl.queue_free)

# Douleur du héros (E9 §8.81) : pulse rouge 0,3 s sur la zone OPÉRATEUR quand NOTRE héros encaisse.
func pulse_hero_pain() -> void:
	if not _op_built:
		return
	var zone: Control = %OperatorZone
	zone.modulate = Color(1.0, 0.55, 0.5, 1.0)
	var tw := zone.create_tween()
	tw.tween_property(zone, "modulate", Color(1, 1, 1, 1), 0.3)

# =========================================================
# FICHE JOUEUR (panneau gauche, lot A) — remplace les tiroirs INTEL + les 2 inspecteurs
# =========================================================
# Ouverte par : clic sur un territoire, clic d'une ligne d'ordre de tour, ou son bouton-tiroir.
# Contenu : navigation ◀ pseudo ▶, bloc HÉROS (identité + pouvoir + 4 barres), bloc SITUATION
# (territoires, troupes, cartes, statut), bloc TERRITOIRE (si ouverte par un clic de territoire).

# Ordre de navigation poussé par main.gd (pids ordonnés turn_order, vivants d'abord).
func set_sheet_players(order: Array) -> void:
	_sheet_order = []
	for p in order:
		_sheet_order.append(int(p))

# Flèches ◀ ▶ : avance dans _sheet_order et RE-ÉMET roster_player_clicked (main.gd recompose la
# fiche et focalise la caméra — exactement l'ancienne sémantique du clic de ligne du War Roster).
func _on_sheet_step(delta: int) -> void:
	if _sheet_order.is_empty():
		return
	var idx := _sheet_order.find(_sheet_pid)
	if idx < 0:
		idx = 0 if delta > 0 else _sheet_order.size() - 1
	else:
		idx = wrapi(idx + delta, 0, _sheet_order.size())
	roster_player_clicked.emit(int(_sheet_order[idx]))

# Alimente ET ouvre la fiche. data = {
#   pid, pseudo, color, faction_name, leader, power_text, status_key, hero,
#   territories: int, troops: int, cards: int,
#   territory: { name, garrison, owner_name, contaminated, shielded, frozen } | null }
func set_player_sheet(data: Dictionary) -> void:
	_sheet_pid = int(data.get("pid", -9999))
	var col: Color = data.get("color", Color("8a97a5"))
	%SheetName.text = str(data.get("pseudo", "—")).to_upper()
	%SheetName.add_theme_color_override("font_color", col)

	var body: VBoxContainer = %SheetBody
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()

	# ---- Bloc HÉROS : identité de faction + pouvoir + 4 barres de stats ----
	body.add_child(_sheet_eyebrow("HUD_SHEET_HERO"))
	var ident := Label.new()
	var leader := str(data.get("leader", ""))
	var faction := str(data.get("faction_name", ""))
	ident.text = ("%s · %s" % [leader, faction]) if leader != "" else faction
	ident.add_theme_font_size_override("font_size", FS_BODY)
	ident.add_theme_color_override("font_color", col.lerp(Color.WHITE, 0.3))
	ident.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(ident)
	var power := str(data.get("power_text", ""))
	if power != "":
		var pw := Label.new()
		pw.text = power
		pw.add_theme_font_size_override("font_size", FS_SMALL)
		pw.add_theme_color_override("font_color", Color("c8cdd6"))
		pw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(pw)
	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 2)
	body.add_child(stats)
	var hero = data.get("hero", {})
	_fill_hero_stats(stats, hero if typeof(hero) == TYPE_DICTIONARY else {})

	# ---- Bloc SITUATION : territoires / troupes / cartes / statut ----
	body.add_child(_sheet_separator())
	body.add_child(_sheet_eyebrow("HUD_SHEET_SITUATION"))
	body.add_child(_sheet_line(tr("HUD_SHEET_TERRITORIES_FMT") % int(data.get("territories", 0))))
	body.add_child(_sheet_line(tr("HUD_SHEET_TROOPS_FMT") % int(data.get("troops", 0))))
	body.add_child(_sheet_line(tr("HUD_SHEET_CARDS_FMT") % int(data.get("cards", 0))))
	var status_key := str(data.get("status_key", "HUD_SHEET_STATUS_ALIVE"))
	var st := _sheet_line(tr(status_key))
	st.add_theme_color_override("font_color",
		Color("eef3f7") if status_key == "HUD_SHEET_STATUS_ALIVE" else HERO_DANGER)
	body.add_child(st)

	# ---- Bloc TERRITOIRE (uniquement si la fiche a été ouverte par un clic de territoire) ----
	var terr = data.get("territory")
	if typeof(terr) == TYPE_DICTIONARY and not (terr as Dictionary).is_empty():
		body.add_child(_sheet_separator())
		body.add_child(_sheet_eyebrow("HUD_SHEET_TERRITORY"))
		var tname := Label.new()
		tname.text = str(terr.get("name", "—")).to_upper()
		tname.add_theme_font_size_override("font_size", FS_TITLE)
		tname.add_theme_color_override("font_color", ACCENT_CYAN)
		body.add_child(tname)
		body.add_child(_sheet_line(tr("HUD_SHEET_GARRISON_FMT") % int(terr.get("garrison", 0))))
		if bool(terr.get("contaminated", false)):
			var rad := _sheet_line(tr("HUD_CONTAMINATED"))
			rad.add_theme_color_override("font_color", Color("7fff00"))
			body.add_child(rad)
	open_player_sheet()

func _sheet_eyebrow(key: String) -> Label:
	var l := Label.new()
	l.text = tr(key)
	l.add_theme_font_size_override("font_size", FS_EYEBROW)
	l.add_theme_color_override("font_color", HERO_MUTED)
	return l

func _sheet_line(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FS_BODY)
	l.add_theme_color_override("font_color", Color("eef3f7"))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _sheet_separator() -> HSeparator:
	return HSeparator.new()

# Pid actuellement affiché par la fiche (-9999 = aucune) — main.gd s'en sert pour rafraîchir la
# fiche EN TEMPS RÉEL à chaque état reçu (les PV de la cible changent après un combat).
func current_sheet_pid() -> int:
	return _sheet_pid

# =========================================================
# Chip « PROCHAINE ZONE » (G1 §8.62 — devenu discret, lot A)
# =========================================================
# Ligne d'état permanente devenue un CHIP sous le bandeau haut : cliquable → ouvre l'onglet
# JOURNAL filtré ZONE (l'info reste accessible sans occuper une colonne entière).

func _ensure_zone_chip() -> void:
	if _zone_chip != null and is_instance_valid(_zone_chip):
		return
	_zone_chip = Button.new()
	_zone_chip.name = "ZoneForecastChip"
	_zone_chip.flat = true
	_zone_chip.focus_mode = Control.FOCUS_NONE
	_zone_chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_zone_chip.tooltip_text = tr("HUD_ZONE_CHIP_TOOLTIP")
	_zone_chip.add_theme_font_size_override("font_size", FS_SMALL)
	_zone_chip.add_theme_color_override("font_color", ACCENT_GOLD)
	_zone_chip.add_theme_color_override("font_hover_color", Color("eef3f7"))
	# Ancré en HAUT-DROITE, à gauche du bouton ABANDONNER : au centre, il passait SOUS le bandeau
	# de tour/phase (E3 §8.75) à chaque changement de phase — les deux se chevauchaient (capture).
	# Fenêtre de largeur FIXE + `clip_text` : avec 4 territoires annoncés, un chip à largeur libre
	# grandissait vers la gauche jusqu'à toucher le bandeau (constaté en capture après la passe
	# typographique). Ici il reste borné, quoi qu'annonce le serveur.
	_zone_chip.clip_text = true
	_zone_chip.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_zone_chip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_zone_chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_zone_chip.offset_left = -566.0
	_zone_chip.offset_right = -206.0
	_zone_chip.offset_top = 16.0
	_zone_chip.pressed.connect(func() -> void:
		AudioManager.play_sfx("click")
		open_journal_tab("zone"))
	add_child(_zone_chip)

# Alimente le chip. `names` = noms lisibles des territoires annoncés (résolus par main.gd).
func set_zone_forecast(names: Array) -> void:
	_ensure_zone_chip()
	if names.is_empty():
		_zone_chip.text = tr("HUD_NEXT_ZONE_NONE")
	else:
		var joined := ", ".join(PackedStringArray(names))
		_zone_chip.text = tr("HUD_NEXT_ZONE_FMT") % joined

# =========================================================
# Tracker d'objectif vivant (E6 §8.78) — zone OBJECTIFS de la barre basse
# =========================================================

# =========================================================
# MODE STREAMER (§8.121, LOT E) — plaque « INTEL CLASSIFIÉ »
# =========================================================

# Construit (une fois) la plaque de masquage, insérée AVANT %ObjectiveLabel dans la zone OBJECTIFS.
# Un vrai `Button` (et non un `gui_input` sur le conteneur) : il expose `button_down`/`button_up`
# pour le maintien, et n'exige AUCUNE retouche des `mouse_filter` de la barre basse — un STOP posé
# sur un conteneur de la zone OBJECTIFS casserait le clic des widgets voisins (piège connu).
func _ensure_intel_gate() -> void:
	if _intel_gate != null and is_instance_valid(_intel_gate):
		return
	var anchor: Control = %ObjectiveLabel
	var parent := anchor.get_parent()
	var btn := Button.new()
	btn.name = "IntelGate"
	btn.text = tr("INTEL_CLASSIFIED")
	btn.visible = false
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.add_theme_font_size_override("font_size", FS_BODY)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.bg_color = Color(0.05, 0.05, 0.07, 0.55)
	sb.set_border_width_all(1)
	sb.border_color = Color(ACCENT_CYAN, 0.45)
	sb.set_content_margin_all(6)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(ACCENT_CYAN, 0.18)
	hover.border_color = ACCENT_CYAN
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_color_override("font_color", HERO_MUTED)
	btn.add_theme_color_override("font_hover_color", ACCENT_CYAN)
	btn.button_down.connect(func() -> void:
		_intel_revealed = true
		_apply_intel_gate())
	btn.button_up.connect(func() -> void:
		_intel_revealed = false
		_intel_hover_clock = 0.0
		_apply_intel_gate())
	btn.mouse_entered.connect(func() -> void:
		_intel_hovering = true
		_intel_hover_clock = 0.0)
	btn.mouse_exited.connect(func() -> void:
		_intel_hovering = false
		_intel_hover_clock = 0.0
		# Le curseur quitte la plaque → l'intel se referme immédiatement. C'est la garantie du mode :
		# rien ne reste lisible à l'écran une fois le geste terminé.
		if _intel_revealed:
			_intel_revealed = false
			_apply_intel_gate())
	parent.add_child(btn)
	parent.move_child(btn, anchor.get_index())
	_intel_gate = btn

# Applique l'état de masquage à la zone OBJECTIFS. Appelée au changement de réglage, à chaque
# rafraîchissement d'objectif, et aux deux bouts du geste de révélation.
func _apply_intel_gate() -> void:
	_ensure_intel_gate()
	var hide_intel := _streamer_mode and not _intel_revealed
	_intel_gate.visible = _streamer_mode
	_intel_gate.text = tr("INTEL_CLASSIFIED") if hide_intel else tr("INTEL_REVEALED")
	%ObjectiveLabel.visible = not hide_intel
	if _objective_tracker != null and is_instance_valid(_objective_tracker):
		# On ne FORCE pas la visibilité du tracker : s'il était déjà masqué (aucun objectif résolu),
		# il doit le rester — `_objective_has_lines` porte cette information.
		_objective_tracker.visible = _objective_has_lines and not hide_intel
	_refresh_spy_intel_label(hide_intel)

# Réglage changé en cours de partie (l'écran Paramètres est atteignable depuis l'arène) : on
# applique à chaud, sans redémarrage — même contrat que les autres réglages de confort.
func _on_comfort_changed(key: String, value) -> void:
	if key != "streamer_mode":
		return
	_streamer_mode = bool(value)
	_intel_revealed = false
	_intel_hovering = false
	_intel_hover_clock = 0.0
	_apply_intel_gate()

# RENSEIGNEMENT D'ESPIONNAGE (Chasseurs d'Ombres §8.24) — mémorisé par le HUD et rendu SOUS la
# plaque : en mode streamer il obéit donc au même geste que l'objectif propre. Hors mode streamer,
# main.gd continue d'écrire la ligne en clair au Journal et au chat (comportement historique) et
# n'appelle pas cette fonction.
func set_spy_intel(text: String) -> void:
	_spy_intel = str(text)
	_apply_intel_gate()

func _refresh_spy_intel_label(hidden: bool) -> void:
	var existing: Node = null
	if _objective_tracker != null and is_instance_valid(_objective_tracker):
		existing = _objective_tracker.get_node_or_null("SpyIntel")
	if _spy_intel == "" or hidden or _objective_tracker == null \
			or not is_instance_valid(_objective_tracker):
		if existing != null:
			existing.queue_free()
		return
	if existing == null:
		var lbl := Label.new()
		lbl.name = "SpyIntel"
		lbl.add_theme_font_size_override("font_size", FS_EYEBROW)
		lbl.add_theme_color_override("font_color", ACCENT_GOLD)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_objective_tracker.add_child(lbl)
		existing = lbl
	(existing as Label).text = tr("INTEL_SPY_LINE") % _spy_intel

# Le mode streamer masque-t-il l'objectif en ce moment ? Lu par main.gd pour router le résultat
# d'espionnage (plaque vs Journal en clair).
func is_intel_masked() -> bool:
	return _streamer_mode


func _ensure_objective_tracker() -> void:
	if _objective_tracker != null and is_instance_valid(_objective_tracker):
		return
	_objective_tracker = VBoxContainer.new()
	_objective_tracker.name = "ObjectiveTracker"
	_objective_tracker.add_theme_constant_override("separation", 2)
	var anchor: Control = %ObjectiveLabel
	var parent := anchor.get_parent()
	parent.add_child(_objective_tracker)
	parent.move_child(_objective_tracker, anchor.get_index() + 1)

# Alimente le tracker. data = objective_tracker.progress(objective, ctx) résolu par main.gd :
# { lines: Array[{label, ratio, done}], best_ratio: float, done: bool } + tooltip.
func set_objective_progress(data: Dictionary, tooltip: String = "") -> void:
	_ensure_objective_tracker()
	var lines: Array = data.get("lines", [])
	for c in _objective_tracker.get_children():
		_objective_tracker.remove_child(c)
		c.queue_free()
	if lines.is_empty():
		_objective_has_lines = false
		_objective_tracker.visible = false
		_apply_intel_gate()
		return
	_objective_has_lines = true
	_objective_tracker.visible = true
	var multi: bool = lines.size() > 1
	for i in range(lines.size()):
		var l: Dictionary = lines[i]
		var done: bool = bool(l.get("done", false))
		# Séparateur « OU » entre les deux volets d'un objectif double (§8.61).
		if multi and i > 0:
			var sep := Label.new()
			sep.text = tr("OBJ_OR")
			sep.add_theme_font_size_override("font_size", FS_EYEBROW)
			sep.add_theme_color_override("font_color", HERO_MUTED)
			_objective_tracker.add_child(sep)
		# Volet = libellé COMPLET sur sa ligne + barre de progression dessous (lisible sans tooltip).
		var lbl := Label.new()
		lbl.text = ("◆ " if not done else "✔ ") + str(l.get("label", ""))
		lbl.add_theme_font_size_override("font_size", FS_BODY)
		lbl.add_theme_color_override("font_color", ACCENT_GOLD if done else Color("c8cdd6"))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_objective_tracker.add_child(lbl)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 12)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.max_value = 1.0
		bar.value = float(l.get("ratio", 0.0))
		_style_bar(bar, ACCENT_GOLD if done else ACCENT_CYAN)
		_objective_tracker.add_child(bar)
	# Rappel « dernier survivant » (toujours vrai, quel que soit l'objectif secret).
	var hint := Label.new()
	hint.text = tr("OBJ_LAST_SURVIVOR_HINT")
	hint.add_theme_font_size_override("font_size", FS_EYEBROW)
	hint.add_theme_color_override("font_color", HERO_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_tracker.add_child(hint)
	if tooltip != "":
		_objective_tracker.tooltip_text = tooltip
	# ≥ 80 % (ou accompli) → pulse OR discret : proche de la victoire (piloté dans _process).
	_objective_pulse = float(data.get("best_ratio", 0.0)) >= 0.8 or bool(data.get("done", false))
	if not _objective_pulse:
		_objective_tracker.modulate = Color(1, 1, 1, 1)
	# §8.121 — le tracker vient d'être reconstruit : on ré-applique le masquage streamer, sinon la
	# jauge fraîchement peuplée réapparaîtrait en clair sous la plaque.
	_apply_intel_gate()

# Construit (une fois) le gros bouton « CONFIRMER LE DÉPLOIEMENT » et l'insère dans la barre
# d'action de l'onglet ACTIONS, juste avant « Fin de Phase ». Masqué par défaut (§8.26).
func _build_confirm_button() -> void:
	_confirm_btn = Button.new()
	_confirm_btn.text = tr("HUD_DEPLOY_CONFIRM")
	_confirm_btn.visible = false
	_confirm_btn.add_theme_font_size_override("font_size", FS_BODY)
	_confirm_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Bouton « Ghost » (charte « Warzone Command » §2/§8.37).
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.07, 0.35)
	style.border_color = Color(ACCENT_CYAN, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.set_content_margin_all(8)
	var style_hover := style.duplicate()
	style_hover.bg_color = Color(ACCENT_CYAN, 0.14)
	style_hover.border_color = ACCENT_CYAN
	style_hover.set_border_width_all(2)
	var style_disabled := style.duplicate()
	style_disabled.border_color = Color(0.4, 0.42, 0.36, 0.4)
	_confirm_btn.add_theme_stylebox_override("normal", style)
	_confirm_btn.add_theme_stylebox_override("hover", style_hover)
	_confirm_btn.add_theme_stylebox_override("pressed", style_hover)
	_confirm_btn.add_theme_stylebox_override("disabled", style_disabled)
	_confirm_btn.add_theme_color_override("font_color", Color("f0e6d2"))
	_confirm_btn.add_theme_color_override("font_hover_color", ACCENT_CYAN)
	_confirm_btn.add_theme_color_override("font_pressed_color", ACCENT_CYAN)
	_confirm_btn.add_theme_color_override("font_disabled_color", Color("6a6a60"))
	_confirm_btn.pressed.connect(func(): deploy_confirmed.emit())
	_confirm_btn.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	_confirm_btn.pressed.connect(func() -> void: AudioManager.play_sfx("confirm"))
	var row := %NextPhaseButton.get_parent()
	row.add_child(_confirm_btn)
	row.move_child(_confirm_btn, %NextPhaseButton.get_index())

# Pilote le bouton « CONFIRMER LE DÉPLOIEMENT » (appelé par main.gd à chaque refresh, §8.26).
func set_deploy_confirm(active: bool, total: int = 0, quota: int = 0) -> void:
	if _confirm_btn == null:
		return
	if not active:
		_confirm_btn.visible = false
		return
	_confirm_btn.visible = true
	_confirm_btn.disabled = (total != quota)
	_confirm_btn.text = tr("HUD_DEPLOY_CONFIRM_FMT") % [total, quota]

# =========================================================
# Carte POUVOIR contextuelle (onglet ACTIONS — lot E)
# =========================================================
# `lines` = Array[String] (état vivant du pouvoir, déjà traduit par main.gd) ;
# `buttons` = Array[{ "label", "action", "subtitle"?, "tooltip"?, "disabled"?, "accent"? }] — le clic
# ré-émet power_action_requested. Clés OPTIONNELLES ajoutées en §8.119 (rétro-compatibles) :
#   • `subtitle` : 2ᵉ ligne dynamique sous le libellé (ex. « −5 PP → +30 PV ») — l'affaire proposée
#     est ainsi VISIBLE avant le clic, y compris quand le plafond de PV rogne la conversion ;
#   • `tooltip` + `disabled` : **jamais de bouton mort silencieux** — un bouton grisé porte TOUJOURS
#     la raison du grisage en infobulle (règle §8.119 lot E).
func set_power_card(lines: Array, buttons: Array = []) -> void:
	var box: VBoxContainer = %PowerBox
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	for l in lines:
		var lbl := Label.new()
		lbl.text = str(l)
		lbl.add_theme_font_size_override("font_size", FS_BODY)
		lbl.add_theme_color_override("font_color", ACCENT_CYAN)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(lbl)
	for b in buttons:
		if typeof(b) != TYPE_DICTIONARY:
			continue
		var btn := Button.new()
		var label := str(b.get("label", "—"))
		var subtitle := str(b.get("subtitle", ""))
		btn.text = ("%s\n%s" % [label, subtitle]) if subtitle != "" else label
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.add_theme_font_size_override("font_size", FS_BODY)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.disabled = bool(b.get("disabled", false))
		# `mouse_filter = STOP` sur un bouton DÉSACTIVÉ : sans ça, Godot ignore le survol et
		# l'infobulle de raison ne s'afficherait jamais — le bouton redeviendrait « mort muet ».
		if btn.disabled:
			btn.mouse_filter = Control.MOUSE_FILTER_STOP
		var tip := str(b.get("tooltip", ""))
		if tip != "":
			btn.tooltip_text = tip
		if b.has("accent"):
			btn.add_theme_color_override("font_color", b["accent"])
		var action := str(b.get("action", ""))
		btn.pressed.connect(func() -> void:
			AudioManager.play_sfx("click")
			power_action_requested.emit(action))
		box.add_child(btn)
	box.visible = not box.get_children().is_empty()

# §8.119 — BANDEAU furtif d'état de capacité (« PROCHAINE ATTAQUE : PORTÉE ILLIMITÉE » tant que
# `airborne_attacks_left > 0`). Chip discret inséré en TÊTE de la zone opérateur, sur le modèle du
# chip de télégraphe de zone (G1 §8.62) : créé paresseusement, masqué dès que le texte est vide.
var _ability_banner: Label = null

func set_ability_banner(text: String) -> void:
	if not _op_built:
		return
	if _ability_banner == null:
		_ability_banner = Label.new()
		_ability_banner.add_theme_font_size_override("font_size", FS_EYEBROW)
		_ability_banner.add_theme_color_override("font_color", ACCENT_GOLD)
		_ability_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_ability_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var zone: VBoxContainer = %OperatorZone
		zone.add_child(_ability_banner)
		zone.move_child(_ability_banner, 0)
	_ability_banner.text = text
	_ability_banner.visible = text != ""

# =========================================================
# Journal de Guerre 2.0 (E4 §8.76) — onglet JOURNAL, filtres, kill feed, toasts
# =========================================================

# Journal militaire. LEGACY conservé : tout texte brut devient une entrée `system` du flux
# structuré (filtrable comme le reste — AUCUNE perte d'info).
func add_log(text: String, icon_path: String = "") -> void:
	var rich := text
	if icon_path != "":
		rich = "[img=18]%s[/img] %s" % [icon_path, text]
	add_feed_entries([{"category": "system", "icon": "⚙", "rich_text": rich,
		"tid": "", "major": false}])

# Ajoute des entrées structurées (war_feed.parse — E4) au flux : numérotation à l'AJOUT (stable
# à travers les filtres), rendu incrémental si l'entrée passe le filtre courant, plafond FEED_MAX.
func add_feed_entries(entries: Array) -> void:
	var added := false
	for e in entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		_log_count += 1
		e["_num"] = _log_count
		_feed_entries.append(e)
		added = true
		if _feed_entries.size() > FEED_MAX:
			_feed_entries.pop_front()
		if _feed_matches(e):
			%LogText.append_text(_feed_line(e) + "\n")
	# Badge « • » sur l'onglet JOURNAL quand des entrées arrivent alors qu'il n'est pas ouvert.
	if added and int(%CommandsTabs.current_tab) != TAB_JOURNAL:
		_set_journal_badge(true)

func _feed_matches(e: Dictionary) -> bool:
	return _feed_filter == "all" or str(e.get("category", "system")) == _feed_filter

# Ligne BBCode d'une entrée : numéro acier + texte, le tout enveloppé [url=<tid>] si l'entrée
# pointe un territoire (clic → caméra, meta_clicked).
func _feed_line(e: Dictionary) -> String:
	var txt := str(e.get("rich_text", ""))
	var tid := str(e.get("tid", ""))
	if tid != "":
		txt = "[url=%s]%s[/url]" % [tid, txt]
	return "[color=#8a8f7a][%03d][/color] %s" % [int(e.get("_num", 0)), txt]

# Re-rendu COMPLET du journal selon le filtre courant (changement de chip).
func _rerender_feed() -> void:
	%LogText.clear()
	for e in _feed_entries:
		if _feed_matches(e):
			%LogText.append_text(_feed_line(e) + "\n")

# Rangée de chips de filtre TOUS / ⚔ / ☢ / ❖ / ⚙ (ButtonGroup), insérée juste AU-DESSUS de
# %LogText dans l'onglet JOURNAL (insertion relative, piège n° 6).
func _build_feed_filters() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var group := ButtonGroup.new()
	var defs := [["all", tr("FEED_FILTER_ALL")], ["combat", "⚔"], ["zone", "☢"],
		["cards", "❖"], ["system", "⚙"]]
	for d in defs:
		var b := Button.new()
		b.text = str(d[1])
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = str(d[0]) == "all"
		b.custom_minimum_size = Vector2(52, 32)
		b.add_theme_font_size_override("font_size", FS_BODY)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.tooltip_text = tr("FEED_FILTER_TOOLTIP")
		var key := str(d[0])
		_feed_filter_buttons[key] = b
		b.pressed.connect(func() -> void:
			_feed_filter = key
			AudioManager.play_sfx("click")
			_rerender_feed())
		row.add_child(b)
	var parent := %LogText.get_parent()
	parent.add_child(row)
	parent.move_child(row, %LogText.get_index())

# Ouvre l'onglet JOURNAL (optionnellement sur un filtre précis) — appelé par le chip de zone.
func open_journal_tab(filter_key: String = "") -> void:
	%CommandsTabs.current_tab = TAB_JOURNAL
	if filter_key != "" and _feed_filter_buttons.has(filter_key):
		var b: Button = _feed_filter_buttons[filter_key]
		b.button_pressed = true
		_feed_filter = filter_key
		_rerender_feed()

func _on_command_tab_changed(tab: int) -> void:
	if tab == TAB_JOURNAL:
		_set_journal_badge(false)

func _set_journal_badge(on: bool) -> void:
	if on == _feed_unread:
		return
	_feed_unread = on
	%CommandsTabs.set_tab_title(TAB_JOURNAL,
		tr("HUD_TAB_JOURNAL") + (" •" if on else ""))

# Kill feed (E4) : instancié coin haut-droit, À GAUCHE du panneau COMMS — hors panneaux.
# ⚠️ Ces offsets DÉPENDENT de la largeur du panneau COMMS (382 px depuis la passe lisibilité) :
# calés sur l'ancienne largeur de 320, ils faisaient passer le kill feed SOUS le chat.
const KILL_FEED_WIDTH := 320.0
const COMMS_WIDTH := 382.0
const KILL_FEED_GAP := 18.0

func _build_kill_feed() -> void:
	_kill_feed = KillFeedScene.instantiate()
	add_child(_kill_feed)
	_kill_feed.anchor_left = 1.0
	_kill_feed.anchor_right = 1.0
	_kill_feed.offset_right = -(COMMS_WIDTH + KILL_FEED_GAP)
	_kill_feed.offset_left = _kill_feed.offset_right - KILL_FEED_WIDTH
	_kill_feed.offset_top = 84.0
	_kill_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_kill_feed.grow_vertical = Control.GROW_DIRECTION_END

func push_kill_feed(rich_text: String) -> void:
	if _kill_feed != null and is_instance_valid(_kill_feed):
		_kill_feed.push_entry(rich_text)

# Toast défensif (E4) : « ⚠ ONTARIO ATTAQUÉ PAR X — pertes : N » quand un territoire à NOUS est
# frappé pendant le tour d'un AUTRE. Panneau furtif haut-centre, liseré rouge.
func show_defense_toast(rich_text: String) -> void:
	if _defense_toast == null or not is_instance_valid(_defense_toast):
		_defense_toast = PanelContainer.new()
		_defense_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.058824, 0.07451, 0.094118, 0.92)
		style.border_color = Color("d6453f")
		style.set_border_width_all(0)
		style.border_width_left = 3
		style.border_width_right = 3
		style.set_corner_radius_all(0)
		style.set_content_margin_all(8)
		_defense_toast.add_theme_stylebox_override("panel", style)
		var rtl := RichTextLabel.new()
		rtl.name = "ToastText"
		rtl.bbcode_enabled = true
		rtl.fit_content = true
		rtl.scroll_active = false
		rtl.autowrap_mode = TextServer.AUTOWRAP_OFF
		rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rtl.add_theme_font_size_override("normal_font_size", FS_TITLE)
		_defense_toast.add_child(rtl)
		add_child(_defense_toast)
	var text_node: RichTextLabel = _defense_toast.get_node("ToastText")
	text_node.clear()
	text_node.append_text(rich_text)
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_defense_toast.visible = true
	_defense_toast.modulate.a = 0.0
	_defense_toast.reset_size()
	_defense_toast.position = Vector2((size.x - _defense_toast.size.x) / 2.0, 112.0)
	_toast_tween = create_tween()
	_toast_tween.tween_property(_defense_toast, "modulate:a", 1.0, 0.18)
	_toast_tween.tween_interval(3.2)
	_toast_tween.tween_property(_defense_toast, "modulate:a", 0.0, 0.35)
	_toast_tween.tween_callback(func() -> void: _defense_toast.visible = false)

# Renvoie un pseudo colorisé à l'accent_color du joueur (BBCode), à embarquer dans add_log /
# add_chat_message.
func color_pseudo(pseudo: String, accent: Color) -> String:
	return "[color=#%s]%s[/color]" % [accent.to_html(false), pseudo]

# =========================================================
# Toast d'ACTION ADVERSE (lot C) — rythme des tours de bots/adversaires
# =========================================================
# « {pseudo colorisé} ❯ {action traduite} » haut-centre, sous le bandeau. Une action à la fois :
# le contrôleur (main.gd) draine sa file d'événements à cadence lisible et appelle ce toast pour
# CHACUNE — sans quoi les actions adverses s'appliquaient d'un coup au refresh d'état (« je ne
# comprends rien à ce qui se passe », constat Hakim 2026-07-26).
var _action_toast: PanelContainer = null
var _action_toast_tween: Tween = null

func show_action_toast(rich_text: String, accent: Color = Color("36c5d9"), duration: float = 0.9) -> void:
	if _action_toast == null or not is_instance_valid(_action_toast):
		_action_toast = PanelContainer.new()
		_action_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rtl := RichTextLabel.new()
		rtl.name = "ActionText"
		rtl.bbcode_enabled = true
		rtl.fit_content = true
		rtl.scroll_active = false
		rtl.autowrap_mode = TextServer.AUTOWRAP_OFF
		rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rtl.add_theme_font_size_override("normal_font_size", FS_TITLE)
		_action_toast.add_child(rtl)
		add_child(_action_toast)
	# Liseré à la couleur du joueur qui agit (repère instantané « qui fait quoi »).
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.058824, 0.07451, 0.094118, 0.92)
	style.border_color = accent
	style.set_border_width_all(0)
	style.border_width_left = 3
	style.set_corner_radius_all(0)
	style.set_content_margin_all(8)
	_action_toast.add_theme_stylebox_override("panel", style)
	var text_node: RichTextLabel = _action_toast.get_node("ActionText")
	text_node.clear()
	text_node.append_text(rich_text)
	if _action_toast_tween and _action_toast_tween.is_valid():
		_action_toast_tween.kill()
	_action_toast.visible = true
	_action_toast.modulate.a = 0.0
	_action_toast.reset_size()
	_action_toast.position = Vector2((size.x - _action_toast.size.x) / 2.0, 142.0)
	_action_toast_tween = create_tween()
	_action_toast_tween.tween_property(_action_toast, "modulate:a", 1.0, 0.12)
	_action_toast_tween.tween_interval(maxf(0.1, duration - 0.34))
	_action_toast_tween.tween_property(_action_toast, "modulate:a", 0.0, 0.22)
	_action_toast_tween.tween_callback(func() -> void:
		if _action_toast != null and is_instance_valid(_action_toast):
			_action_toast.visible = false)

# =========================================================
# Toast d'ACTIVATION DE POUVOIR (lot E) — « ⚡ Razzia (relance totale) »
# =========================================================
# Composant DÉDIÉ (distinct du toast d'action adverse, qui vit plus haut) : file interne, ~2 s par
# entrée, liseré à la couleur du camp concerné. POURQUOI : cinq pouvoirs mutent le combat côté
# serveur, mais deux d'entre eux (Razzia, Embuscade) n'étaient rendus NULLE PART — le joueur ne
# pouvait pas savoir que son pouvoir venait de s'appliquer.
const POWER_TOAST_TIME := 2.0
var _power_toast: PanelContainer = null
var _power_toast_queue: Array = []
var _power_toast_busy := false

func show_power_toast(text: String, accent: Color) -> void:
	_power_toast_queue.append({"text": text, "accent": accent})
	if not _power_toast_busy:
		_drain_power_toasts()

func _drain_power_toasts() -> void:
	if _power_toast_queue.is_empty():
		_power_toast_busy = false
		return
	_power_toast_busy = true
	var item: Dictionary = _power_toast_queue.pop_front()
	if _power_toast == null or not is_instance_valid(_power_toast):
		_power_toast = PanelContainer.new()
		_power_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lbl := Label.new()
		lbl.name = "PowerText"
		lbl.add_theme_font_size_override("font_size", FS_TITLE)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_power_toast.add_child(lbl)
		add_child(_power_toast)
	var accent: Color = item.get("accent", ACCENT_GOLD)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.058824, 0.07451, 0.094118, 0.94)
	style.border_color = accent
	style.set_border_width_all(0)
	style.border_width_left = 4
	style.border_width_bottom = 1
	style.set_corner_radius_all(0)
	style.set_content_margin_all(9)
	_power_toast.add_theme_stylebox_override("panel", style)
	var text_node: Label = _power_toast.get_node("PowerText")
	text_node.text = str(item.get("text", ""))
	text_node.add_theme_color_override("font_color", accent.lerp(Color("eef3f7"), 0.45))
	_power_toast.visible = true
	_power_toast.modulate.a = 0.0
	_power_toast.reset_size()
	_power_toast.position = Vector2((size.x - _power_toast.size.x) / 2.0, 190.0)
	var tw := create_tween()
	tw.tween_property(_power_toast, "modulate:a", 1.0, 0.14)
	tw.tween_interval(POWER_TOAST_TIME - 0.4)
	tw.tween_property(_power_toast, "modulate:a", 0.0, 0.26)
	tw.tween_callback(func() -> void:
		if _power_toast != null and is_instance_valid(_power_toast):
			_power_toast.visible = false
		_drain_power_toasts())

# =========================================================
# CHAT PAR DESTINATAIRE (lot B) — une conversation à la fois, notifications sans ambiguïté
# =========================================================
# Le HUD reste une VIEW pure : main.gd résout pseudo/couleur/échappement et appelle
# push_chat_message ; l'envoi ressort par le signal chat_send_requested (contrat réseau §8.33
# INCHANGÉ : tab general/private + target_id).

# Clé de conversation d'un message privé avec le joueur `pid` (le fil est le MÊME que je sois
# l'expéditeur ou le destinataire — c'est un dialogue, pas deux listes).
func _conv_key_for(pid: int) -> String:
	return str(pid)

func _conv(key: String) -> Array:
	if not _conversations.has(key):
		_conversations[key] = []
	return _conversations[key]

# Ajoute un message à une conversation et le rend s'il s'agit de celle qui est AFFICHÉE.
#   conv_key : "general" ou str(pid) du correspondant
#   who      : pseudo BBCode PRÊT (colorisé + échappé par main.gd ; « MOI » traduit pour nos envois)
#   text     : texte DÉJÀ échappé (anti-injection BBCode §8.33)
#   notify   : false pour un message système local (accueil, résultat d'espionnage) — pas de badge.
func push_chat_message(conv_key: String, who: String, text: String, notify: bool = true) -> void:
	var conv := _conv(conv_key)
	var stamp := Time.get_time_string_from_system().substr(0, 5)   # HH:MM
	conv.append({"who": who, "text": text, "ts": stamp})
	if conv.size() > CHAT_HISTORY_CAP:
		conv.pop_front()
	# Rendu incrémental UNIQUEMENT si c'est la conversation affichée ET le panneau déployé ; sinon
	# le message est simplement stocké (il sera rendu par _render_conversation à l'ouverture).
	if conv_key == _current_conv and not _side_hidden:
		%ChatLog.append_text(_chat_line(who, text, stamp) + "\n")
		return
	if not notify:
		return
	# Conversation non affichée OU panneau replié → notification SANS AMBIGUÏTÉ : badge de non-lus
	# par destinataire, toast cliquable, et son discret. Jamais pendant le Split-Screen VS : le HUD
	# y est fondu à 0 (fade_ui_for_combat), on ne sonne donc pas par-dessus le duel.
	_unread[conv_key] = int(_unread.get(conv_key, 0)) + 1
	_refresh_chat_badges()
	_show_chat_toast(conv_key, who)
	if modulate.a > 0.5:
		# §8.122 (LOT C) : craquement de talkie PUIS notification — 60 ms d'écart suffisent à faire
		# entendre « une transmission arrive » plutôt qu'« une appli notifie ». Le délai passe par
		# un timer de scène (get_tree().create_timer) : `await` ici bloquerait push_chat_message.
		AudioManager.play_sfx("radio_crackle")
		get_tree().create_timer(CHAT_RADIO_DELAY).timeout.connect(
			func() -> void: AudioManager.play_sfx("chat_ping"))

func _chat_line(who: String, text: String, stamp: String) -> String:
	return "[color=#8a8f7a][%s][/color] %s ❯ %s" % [stamp, who, text]

# Re-rendu COMPLET de la conversation affichée (changement de destinataire / ouverture).
func _render_conversation() -> void:
	%ChatLog.clear()
	for m in _conv(_current_conv):
		%ChatLog.append_text(_chat_line(str(m.get("who", "?")), str(m.get("text", "")),
			str(m.get("ts", "--:--"))) + "\n")

# LEGACY (§8.33) : messages système locaux (accueil, résultat d'espionnage). Routés vers le canal
# général ("general") ou vers le fil du correspondant si `channel` est un pid — aucune perte.
func add_chat_message(channel: String, text: String) -> void:
	var key := CHAT_CONV_GENERAL if (channel == "general" or channel == "prive") else channel
	push_chat_message(key, tr("CHAT_SYSTEM"), text, false)
	if key == _current_conv:
		_render_conversation()

func update_display() -> void:
	var stage := str(GameState.stage)

	# Remise à zéro du rebours quand le tour, le joueur actif OU la PHASE change (§8.31, révisé).
	var key := "%s|%s|%s|%s" % [
		stage, str(GameState.current_turn), str(GameState.current_player_id), str(GameState.current_phase)]
	if key != _turn_key:
		_turn_key = key
		_elapsed = 0.0
		_turn_bonus = 0.0

	# Chrono SERVEUR prioritaire (E3 §8.75) ; sans server_time, REPLI legacy (client défensif §9.2).
	if GameState.server_time > 0.0:
		if GameState.turn_timer.is_empty():
			clear_server_timer()
			_turn_limit = 0.0
		else:
			apply_server_timer(float(GameState.turn_timer.get("deadline_epoch", 0.0)),
				GameState.server_time)
	else:
		clear_server_timer()
		match stage:
			"placement": _turn_limit = PHASE0_TIME
			"playing": _turn_limit = _phase_turn_limit()
			_: _turn_limit = 0.0

	if stage == "playing":
		%PhaseLabel.text = _phase_name(GameState.current_phase).to_upper()
	else:
		%PhaseLabel.text = _stage_name(stage).to_upper()

	# Bandeau haut MINIMAL (lot A) : « TOUR DE {pseudo colorisé} » — plus d'identité locale ni de
	# ligne d'infos redondante. Le pseudo/la couleur viennent de main.gd (set_turn_identity).
	var who := _turn_pseudo
	if who == "":
		var pdata: Dictionary = GameState.players.get(str(GameState.current_player_id), {})
		who = str(pdata.get("username", ""))
		if who == "":
			who = tr("HUD_PLAYER_NUM") % GameState.player_number(GameState.current_player_id)
	%TurnLabel.text = tr("HUD_TURN_OF_FMT") % who.to_upper()
	%TurnLabel.add_theme_color_override("font_color", _turn_color)

	# Objectif secret du joueur local — COMPOSÉ localement en langue courante depuis type/params.
	var obj: Dictionary = GameState.objectives.get(str(AuthManager.user_id), {})
	var obj_txt := ObjectiveTrackerModule.describe(obj, _objective_target_pseudo(obj))
	if obj_txt == "":
		obj_txt = tr("HUD_OBJECTIVE_SECRET")
	%ObjectiveLabel.text = obj_txt
	# §8.121 — mode streamer : le libellé vient d'être réécrit, on repose la plaque par-dessus.
	_apply_intel_gate()

	_refresh_cards()

# =========================================================
# Sélecteur de destinataire (lot B) — « 📢 Tous » + un item par joueur HUMAIN vivant
# =========================================================
func _setup_chat_selector() -> void:
	_chat_target_option = %ChatTargetOption
	_chat_target_option.item_selected.connect(_on_chat_target_selected)
	# Liste minimale tant que main.gd n'a pas poussé la composition de la salle.
	_chat_targets = [{"id": -1, "name": tr("CHAT_ALL"), "color": ACCENT_CYAN}]
	_rebuild_chat_targets()
	_select_conversation(CHAT_CONV_GENERAL)

func _on_chat_target_selected(index: int) -> void:
	AudioManager.play_sfx("click")
	var id := _chat_target_option.get_item_id(index)
	_select_conversation(CHAT_CONV_GENERAL if id < 0 else _conv_key_for(id))

# Bascule la conversation AFFICHÉE : re-rendu complet, non-lus remis à zéro, placeholder adapté.
func _select_conversation(conv_key: String) -> void:
	_current_conv = conv_key
	_unread[conv_key] = 0
	_render_conversation()
	_refresh_chat_badges()
	if _chat_input:
		_chat_input.placeholder_text = tr("CHAT_PLACEHOLDER_FMT") % _conv_display_name(conv_key)

# Libellé NU (sans badge) d'une conversation, pour le placeholder et le toast.
func _conv_display_name(conv_key: String) -> String:
	if conv_key == CHAT_CONV_GENERAL:
		return tr("CHAT_ALL")
	for t in _chat_targets:
		if str(int(t.get("id", -1))) == conv_key:
			return str(t.get("name", "?"))
	return conv_key

# Reconstruit les items du sélecteur avec leur compteur de non-lus (« Kael Draven (2) »), en
# conservant la conversation courante sélectionnée.
func _rebuild_chat_targets() -> void:
	if _chat_target_option == null:
		return
	_chat_target_option.clear()
	for t in _chat_targets:
		var pid := int(t.get("id", -1))
		var key := CHAT_CONV_GENERAL if pid < 0 else _conv_key_for(pid)
		var n := int(_unread.get(key, 0))
		var label := str(t.get("name", "?"))
		if n > 0:
			label = tr("CHAT_UNREAD_FMT") % [label, n]
		_chat_target_option.add_item(label)
		var idx := _chat_target_option.item_count - 1
		_chat_target_option.set_item_id(idx, pid)
		# Pastille à la couleur PLATEAU du correspondant : un PopupMenu ne rend pas le BBCode →
		# on passe par une petite texture unie (même repère visuel que les badges du plateau).
		var col = t.get("color", Color("eef3f7"))
		if col is Color:
			_chat_target_option.set_item_icon(idx, _color_swatch(col))
		if key == _current_conv:
			_chat_target_option.select(idx)

# Petite texture unie mise en cache par couleur (pastille d'item du sélecteur de destinataire).
static var _swatch_cache: Dictionary = {}

func _color_swatch(col: Color) -> ImageTexture:
	var key := col.to_html(false)
	if _swatch_cache.has(key):
		return _swatch_cache[key]
	var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	img.fill(col)
	var tex := ImageTexture.create_from_image(img)
	_swatch_cache[key] = tex
	return tex

# Badges : compteur par item du sélecteur + total sur le bouton-tiroir COMMS quand il est replié.
func _refresh_chat_badges() -> void:
	_rebuild_chat_targets()
	var total := 0
	for k in _unread:
		total += int(_unread[k])
	var base := "◀" if _side_hidden else "▶"
	%ToggleSidePanelButton.text = ("%s\n(%d)" % [base, total]) if (total > 0 and _side_hidden) else base
	%ToggleSidePanelButton.add_theme_color_override("font_color",
		Color("d6453f") if (total > 0 and _side_hidden) else Color("eef3f7"))

# Toast discret haut-droite « ✉ {pseudo} » (3 s) : le clic ouvre la bonne conversation.
func _show_chat_toast(conv_key: String, who_bb: String) -> void:
	if _chat_toast == null or not is_instance_valid(_chat_toast):
		_chat_toast = Button.new()
		_chat_toast.flat = false
		_chat_toast.focus_mode = Control.FOCUS_NONE
		_chat_toast.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_chat_toast.add_theme_font_size_override("font_size", FS_BODY)
		_chat_toast.add_theme_color_override("font_color", Color("eef3f7"))
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.058824, 0.07451, 0.094118, 0.94)
		st.border_color = ACCENT_CYAN
		st.set_border_width_all(0)
		st.border_width_left = 3
		st.set_corner_radius_all(0)
		st.set_content_margin_all(8)
		_chat_toast.add_theme_stylebox_override("normal", st)
		_chat_toast.add_theme_stylebox_override("hover", st)
		_chat_toast.add_theme_stylebox_override("pressed", st)
		_chat_toast.pressed.connect(func() -> void:
			if _side_hidden:
				_toggle_side_panel()
			_open_conversation(_chat_toast_conv))
		add_child(_chat_toast)
	_chat_toast_conv = conv_key
	# Le pseudo arrive en BBCode (couleur) : le Button ne rend pas le BBCode → on le dépouille.
	_chat_toast.text = tr("CHAT_TOAST_FMT") % _strip_bbcode(who_bb)
	_chat_toast.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_chat_toast.reset_size()
	_chat_toast.position = Vector2(size.x - _chat_toast.size.x - 340.0, 150.0)
	_chat_toast.visible = true
	_chat_toast.modulate.a = 0.0
	if _chat_toast_tween and _chat_toast_tween.is_valid():
		_chat_toast_tween.kill()
	_chat_toast_tween = create_tween()
	_chat_toast_tween.tween_property(_chat_toast, "modulate:a", 1.0, 0.18)
	_chat_toast_tween.tween_interval(2.5)
	_chat_toast_tween.tween_property(_chat_toast, "modulate:a", 0.0, 0.3)
	_chat_toast_tween.tween_callback(func() -> void: _chat_toast.visible = false)

# Ouvre une conversation depuis l'extérieur (clic du toast) : sélectionne l'item correspondant.
func _open_conversation(conv_key: String) -> void:
	_select_conversation(conv_key)

# Retire les balises BBCode d'un pseudo pour un affichage en Label/Button (qui ne les interprète pas).
func _strip_bbcode(s: String) -> String:
	var re := RegEx.new()
	re.compile("\\[[^\\]]*\\]")
	return re.sub(s, "", true)

# =========================================================
# Zone de saisie du chat (§8.33) — LineEdit + bouton d'envoi
# =========================================================
func _build_chat_input() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = tr("HUD_CHAT_PLACEHOLDER_GENERAL")
	_chat_input.max_length = CHAT_MAX_LENGTH
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.add_theme_font_size_override("font_size", FS_VALUE)
	var in_style := StyleBoxFlat.new()
	in_style.bg_color = Color(0.058824, 0.07451, 0.094118, 0.85)
	in_style.border_color = Color(ACCENT_CYAN, 0.45)
	in_style.set_border_width_all(1)
	in_style.set_corner_radius_all(2)
	in_style.set_content_margin_all(6)
	var in_focus := in_style.duplicate()
	in_focus.border_color = ACCENT_CYAN
	_chat_input.add_theme_stylebox_override("normal", in_style)
	_chat_input.add_theme_stylebox_override("focus", in_focus)
	_chat_input.text_submitted.connect(func(_t): _on_chat_submit())
	row.add_child(_chat_input)

	_chat_send_btn = Button.new()
	_chat_send_btn.text = "➤"
	_chat_send_btn.tooltip_text = tr("HUD_CHAT_SEND_TOOLTIP")
	_chat_send_btn.custom_minimum_size = Vector2(46, 42)
	_chat_send_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_chat_send_btn.add_theme_font_size_override("font_size", FS_TITLE)
	var s_style := StyleBoxFlat.new()
	s_style.bg_color = Color(ACCENT_CYAN, 0.18)
	s_style.border_color = Color(ACCENT_CYAN, 0.55)
	s_style.set_border_width_all(1)
	s_style.set_corner_radius_all(2)
	var s_hover := s_style.duplicate()
	s_hover.bg_color = Color(ACCENT_CYAN, 0.32)
	s_hover.border_color = ACCENT_CYAN
	_chat_send_btn.add_theme_stylebox_override("normal", s_style)
	_chat_send_btn.add_theme_stylebox_override("hover", s_hover)
	_chat_send_btn.add_theme_stylebox_override("pressed", s_hover)
	_chat_send_btn.add_theme_color_override("font_color", Color("eef3f7"))
	_chat_send_btn.pressed.connect(_on_chat_submit)
	_chat_send_btn.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	_chat_send_btn.pressed.connect(func() -> void: AudioManager.play_sfx("click"))
	row.add_child(_chat_send_btn)

	# Insertion dans le SideVBox, juste APRÈS le panneau de conversation.
	var side_vbox: Node = %ChatLog.get_parent().get_parent()
	side_vbox.add_child(row)

# Envoi : valide le texte (non vide), résout le destinataire depuis la conversation AFFICHÉE, émet
# le signal et vide le champ. On NE colle PAS le message localement : le serveur renvoie un écho
# (§8.33). « Tous » → ("general", texte, -1) ; joueur X → ("prive", texte, X) — réseau INCHANGÉ.
func _on_chat_submit() -> void:
	if _chat_input == null:
		return
	var text := _chat_input.text.strip_edges()
	if text == "":
		return
	_chat_input.clear()
	if _current_conv == CHAT_CONV_GENERAL:
		chat_send_requested.emit("general", text, -1)
	else:
		chat_send_requested.emit("prive", text, int(_current_conv))

# Met à jour la liste des destinataires (§8.33 — lot B). entries = Array[{ id, name, color }] :
# UNIQUEMENT les joueurs HUMAINS vivants (les bots ne parlent pas), résolus par main.gd. L'item
# « Tous » est ajouté ICI, en tête. Si la conversation courante disparaît (joueur éliminé), on
# retombe proprement sur le canal général.
func set_chat_targets(entries: Array) -> void:
	_chat_targets = [{"id": -1, "name": tr("CHAT_ALL"), "color": ACCENT_CYAN}]
	for e in entries:
		var pid := int(e.get("id", -9999))
		if pid == -9999:
			continue
		_chat_targets.append({"id": pid, "name": str(e.get("name", "?")),
			"color": e.get("color", Color("eef3f7"))})
	var still_there := _current_conv == CHAT_CONV_GENERAL
	for t in _chat_targets:
		if _conv_key_for(int(t.get("id", -1))) == _current_conv:
			still_there = true
	if not still_there:
		_select_conversation(CHAT_CONV_GENERAL)
	else:
		_refresh_chat_badges()

# =========================================================
# Bandeau de combat compact (E8 §8.80) — REPLI de la flèche de guerre (lot D)
# =========================================================
# data = { atk_pid, def_pid, atk_rolls, def_rolls, atk_losses, def_losses, hero_damage,
#          hero_died, conquered }. Panneau haut-centre 2,2 s (durée pilotée par main.gd).
func show_combat_banner(data: Dictionary) -> void:
	if _combat_banner == null or not is_instance_valid(_combat_banner):
		_combat_banner = PanelContainer.new()
		_combat_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.058824, 0.07451, 0.094118, 0.92)
		style.border_color = Color(ACCENT_CYAN, 0.5)
		style.set_border_width_all(0)
		style.border_width_bottom = 2
		style.set_corner_radius_all(0)
		style.set_content_margin_all(8)
		_combat_banner.add_theme_stylebox_override("panel", style)
		add_child(_combat_banner)
	for c in _combat_banner.get_children():
		_combat_banner.remove_child(c)
		c.queue_free()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_combat_banner.add_child(row)
	# Camp attaquant (chip) + dés figés.
	var atk_chip := PlayerChipScene.instantiate()
	row.add_child(atk_chip)
	atk_chip.setup(int(data.get("atk_pid", 0)), true)
	row.add_child(_banner_dice_label(data.get("atk_rolls", []), ACCENT_CYAN))
	var vs := Label.new()
	vs.text = "⚔"
	vs.add_theme_font_size_override("font_size", FS_TITLE)
	row.add_child(vs)
	row.add_child(_banner_dice_label(data.get("def_rolls", []), Color("d6453f")))
	var def_chip := PlayerChipScene.instantiate()
	row.add_child(def_chip)
	def_chip.setup(int(data.get("def_pid", 0)), true)
	# Pertes + dégâts héros + issue.
	var summary := Label.new()
	var txt := "  −%d / −%d" % [int(data.get("atk_losses", 0)), int(data.get("def_losses", 0))]
	if int(data.get("hero_damage", 0)) > 0:
		txt += "  ♥−%d" % int(data.get("hero_damage", 0))
	if bool(data.get("hero_died", false)):
		txt += "  ☠"
	elif bool(data.get("conquered", false)):
		txt += "  ⚑"
	summary.text = txt
	summary.add_theme_font_size_override("font_size", FS_BODY)
	summary.add_theme_color_override("font_color", Color("c8cdd6"))
	row.add_child(summary)

	if _combat_banner_tween and _combat_banner_tween.is_valid():
		_combat_banner_tween.kill()
	_combat_banner.visible = true
	_combat_banner.modulate.a = 0.0
	_combat_banner.reset_size()
	_combat_banner.position = Vector2((size.x - _combat_banner.size.x) / 2.0, 96.0)
	_combat_banner_tween = create_tween()
	_combat_banner_tween.tween_property(_combat_banner, "modulate:a", 1.0, 0.18)
	_combat_banner_tween.tween_interval(1.7)
	_combat_banner_tween.tween_property(_combat_banner, "modulate:a", 0.0, 0.3)
	_combat_banner_tween.tween_callback(func() -> void: _combat_banner.visible = false)

func _banner_dice_label(rolls: Array, col: Color) -> Label:
	var parts: Array = []
	for r in rolls:
		parts.append(str(int(r)))
	var lbl := Label.new()
	lbl.text = "[%s]" % " ".join(PackedStringArray(parts))
	lbl.add_theme_font_size_override("font_size", FS_BODY)
	lbl.add_theme_color_override("font_color", col)
	return lbl

# =========================================================
# Panneaux rétractables (§8.29) — slides horizontaux / vertical (Tweens natifs)
# =========================================================

# Mémorise (une fois, après le 1ᵉʳ layout) la position « déployée » et la largeur du panneau COMMS.
func _cache_side_metrics() -> void:
	if _side_metrics_ready:
		return
	var panel: Control = %ToggleSidePanelButton.get_parent()  # SidePanelWidget (Control)
	_side_shown_x = panel.position.x
	_side_width = panel.size.x
	_side_metrics_ready = true

func _toggle_side_panel() -> void:
	var panel: Control = %ToggleSidePanelButton.get_parent()
	_cache_side_metrics()
	_side_hidden = not _side_hidden
	var target_x := _side_shown_x + (_side_width if _side_hidden else 0.0)
	# Lot B : à la ré-ouverture on RE-REND la conversation (les messages arrivés panneau replié
	# n'ont été que stockés) et on purge son compteur de non-lus.
	if not _side_hidden:
		_unread[_current_conv] = 0
		_render_conversation()
	_refresh_chat_badges()
	if _side_tween and _side_tween.is_valid():
		_side_tween.kill()
	_side_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_side_tween.tween_property(panel, "position:x", target_x, SIDE_SLIDE_TIME)

# Fiche joueur : même mécanique, slide vers la GAUCHE (le bouton-tiroir protubère à droite).
func _cache_sheet_metrics() -> void:
	if _sheet_metrics_ready:
		return
	var panel: Control = %TogglePlayerSheetButton.get_parent()
	_sheet_shown_x = panel.position.x
	_sheet_width = panel.size.x
	_sheet_metrics_ready = true

func _toggle_player_sheet() -> void:
	_cache_sheet_metrics()
	_set_player_sheet_hidden(not _sheet_hidden)

func _set_player_sheet_hidden(hide_it: bool) -> void:
	_cache_sheet_metrics()
	var panel: Control = %TogglePlayerSheetButton.get_parent()
	_sheet_hidden = hide_it
	var target_x := _sheet_shown_x - (_sheet_width if _sheet_hidden else 0.0)
	%TogglePlayerSheetButton.text = "▶" if _sheet_hidden else "◀"
	if _sheet_tween and _sheet_tween.is_valid():
		_sheet_tween.kill()
	_sheet_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_sheet_tween.tween_property(panel, "position:x", target_x, SIDE_SLIDE_TIME)

# Déploie la fiche si elle est repliée (appelée par set_player_sheet — un clic territoire doit
# TOUJOURS montrer la fiche demandée).
func open_player_sheet() -> void:
	if _sheet_hidden:
		_set_player_sheet_hidden(false)

# Repli initial : différé d'une frame pour que les conteneurs aient résolu la géométrie (sinon
# _sheet_width vaut 0 et le panneau ne se déplace pas).
func _collapse_player_sheet_initially() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_cache_sheet_metrics()
	_set_player_sheet_hidden(true)

# Replie (vers le BAS) / déploie la barre basse. On mémorise la position déployée juste AVANT un
# repli (robuste si la hauteur du panneau change).
func _toggle_bottom_panel() -> void:
	var wrapper: Control = %ToggleBottomPanelButton.get_parent()  # BottomCenterWidget (VBox)
	var glass: Control = wrapper.get_node("GlassBody")
	_bottom_hidden = not _bottom_hidden
	var target_y: float
	if _bottom_hidden:
		_bottom_shown_y = wrapper.position.y
		target_y = _bottom_shown_y + glass.size.y
	else:
		target_y = _bottom_shown_y
	%ToggleBottomPanelButton.text = "▲" if _bottom_hidden else "▼"
	if _bottom_tween and _bottom_tween.is_valid():
		_bottom_tween.kill()
	_bottom_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_bottom_tween.tween_property(wrapper, "position:y", target_y, BOTTOM_SLIDE_TIME)

# =========================================================
# Masquage de l'UI pour le Split-Screen VS (§8.29)
# =========================================================
func fade_ui_for_combat(is_hidden: bool) -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	if not is_hidden:
		visible = true  # ré-affiché avant de remonter l'alpha (au cas où masqué à 0)
	var target := 0.0 if is_hidden else 1.0
	_fade_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fade_tween.tween_property(self, "modulate:a", target, COMBAT_FADE_TIME)

# =========================================================
# Inventaire de cartes (onglet CARTES)
# =========================================================

func _refresh_cards() -> void:
	var box: HBoxContainer = %CardsBox
	for child in box.get_children():
		child.queue_free()
	var my: Dictionary = GameState.players.get(str(AuthManager.user_id), {})
	var hand: Array = my.get("cards_in_hand", [])
	if hand.is_empty():
		var lbl := Label.new()
		lbl.text = tr("HUD_NO_CARDS")
		lbl.add_theme_color_override("font_color", Color("8a8f7a"))
		box.add_child(lbl)
		return
	# Main TOUJOURS INSPECTABLE, jouable UNIQUEMENT pendant SON tour de jeu (G3 §8.70 explicité).
	var playable := GameState.stage == "playing" \
		and int(GameState.current_player_id) == int(AuthManager.user_id) \
		and str(my.get("status", "alive")) == "alive"
	for i in range(hand.size()):
		box.add_child(_make_card_button(int(hand[i]), i, playable))

# Vignette de carte stylisée : un bouton « +N » (valeur en gros). Clic = card_played(index).
func _make_card_button(value: int, index: int, playable: bool = true) -> Control:
	var card := Button.new()
	card.text = "+%d" % value
	card.custom_minimum_size = Vector2(96, 76)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.disabled = not playable
	card.tooltip_text = (tr("HUD_CARD_PLAY_TOOLTIP") % value) if playable \
		else (tr("HUD_CARD_LOCKED_TOOLTIP") % value)
	card.add_theme_font_size_override("font_size", FS_DISPLAY + 6)
	card.add_theme_color_override("font_color", Color("f0e6d2"))

	var style := StyleBoxFlat.new()
	style.bg_color = Color("121212").lerp(CARD_TINT, 0.3)
	style.border_color = CARD_TINT.lightened(0.15)
	style.set_border_width_all(2)
	style.set_corner_radius_all(0)
	style.set_content_margin_all(6)
	var style_hover := style.duplicate()
	style_hover.bg_color = CARD_TINT.darkened(0.15)
	style_hover.border_color = ACCENT_CYAN  # cyan tactique au survol (charte Warzone Command)
	card.add_theme_stylebox_override("normal", style)
	card.add_theme_stylebox_override("hover", style_hover)
	card.add_theme_stylebox_override("pressed", style_hover)

	card.pressed.connect(func(): card_played.emit(index))
	card.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	card.pressed.connect(func() -> void: AudioManager.play_sfx("click"))
	return card

# Alias PUBLIC du libellé de phase (E3 : consommé par les bandeaux de tour/phase de main.gd).
func phase_name(phase: int) -> String:
	return _phase_name(phase)

func _phase_name(phase: int) -> String:
	match phase:
		0: return tr("PHASE_CONTAMINATION")
		1: return tr("PHASE_REINFORCEMENT")
		2: return tr("PHASE_DEPLOYMENT")
		3: return tr("PHASE_ATTACK")
		4: return tr("PHASE_MOVEMENT")
		5: return tr("PHASE_EVENT")
		_: return tr("PHASE_GENERIC") % phase

# Libellé TRADUIT d'une étape macro de la partie ("initiative" / "placement").
func _stage_name(stage: String) -> String:
	match stage:
		"initiative": return tr("STAGE_INITIATIVE")
		"placement": return tr("STAGE_PLACEMENT")
		_: return stage

# Pseudo résolu de la cible du volet « kill » de l'objectif local (params.target_id → username
# public de l'état). "" si irrésolu → le composeur retombe sur « #id ».
func _objective_target_pseudo(obj: Dictionary) -> String:
	var params = obj.get("params", {})
	if typeof(params) != TYPE_DICTIONARY:
		return ""
	var tid = params.get("target_id")
	if tid == null:
		return ""
	var p = GameState.players.get(str(int(tid)), {})
	return str(p.get("username", "")) if typeof(p) == TYPE_DICTIONARY else ""
