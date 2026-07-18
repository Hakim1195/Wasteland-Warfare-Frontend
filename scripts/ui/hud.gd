extends Control

# HUD MILITAIRE "RTS MODERNE" — centre de commandement FLOTTANT de l'arène (CONTEXTE.md §8.29).
# Le plateau occupe 100 % de la fenêtre (MapViewportContainer, 1ᵉʳ enfant de Main) ; ce HUD est un
# Control plein écran TRANSPARENT AUX CLICS (mouse_filter = IGNORE) sur lequel flottent des widgets
# en glassmorphism militaire (PanelContainer gunmetal/anthracite translucide, charte « Warzone Command » §2) :
#   TopCenterWidget    : identité, phase, infos tour, timer MM:SS + instruction.
#   TopRightWidget     : bouton ABANDONNER (rouge).
#   BottomCenterWidget : inventaire de cartes, objectif secret, quantité, Fin de Phase + Confirmer.
#   SidePanelWidget    : comms (chat à onglets-ICÔNES) + Journal Militaire — RÉTRACTABLE (Tween).
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
# Émis au clic d'une ligne du Roster de Guerre (E1 §8.73) : main.gd ouvre l'inspecteur héros du
# joueur et focalise la caméra sur son territoire le plus garni (le HUD reste une View pure §6.1).
signal roster_player_clicked(player_id: int)
# Émis au clic d'une entrée [url=<tid>] du Journal de Guerre (E4 §8.76) : main.gd focalise la
# caméra sur le territoire et le fait flasher — le journal devient un outil de navigation.
signal log_territory_clicked(territory_id: String)
# Émis au clic du bouton « RÉ-ASSAUT » (E7 §8.79) : main.gd rejoue le dernier assaut.
signal reassault_pressed
# Émis par les raccourcis de quantité +1/+5/MAX (E7 §8.79) : delta ∈ {1, 5, -1=MAX}. main.gd
# ajuste %AmountSpin (mouvement) ou le sens du tampon de déploiement selon la phase.
signal amount_quick(delta: int)

# Roster de Guerre + brique identité (E1 §8.73) : roster permanent des belligérants inséré en
# tête du panneau latéral ; player_chip réutilisé par l'Inspecteur de Territoire (propriétaire).
const WarRosterScene := preload("res://scenes/components/war_roster.tscn")
const PlayerChipScene := preload("res://scenes/components/player_chip.tscn")
# Kill feed (E4 §8.76) : surimpression des entrées majeures, coin haut-droit hors panneaux.
const KillFeedScene := preload("res://scenes/components/kill_feed.tscn")
# Helpers partagés posés au lot E1 (dégradé de santé pv_color + _tint_progress) — réutilisés par
# l'Intel : GUERRE (E5 §8.77) pour les barres de ratio.
const RosterHelpers := preload("res://scripts/ui/war_roster.gd")
# Composeur d'objectif traduit (i18n 2026-07-18) : describe(type/params) → texte en langue courante.
const ObjectiveTrackerModule := preload("res://scripts/ui/objective_tracker.gd")

# Teinte des vignettes de cartes (refonte : plus de cartes spéciales, juste un nombre de troupes).
const CARD_TINT := Color("2f7d8c")  # cyan-acier sombre (renforts) — charte Warzone Command
# Accent « Orange Fusion » de la charte Modern Warfare (#d35400, §2) — liserés, CTA, illumination
# du texte des boutons « ghost » au survol, titres Intel. Source de vérité unique côté code.
const ACCENT_CYAN := Color("36c5d9")
const ACCENT_GOLD := Color("e0b249")

# Délai avant désarmement automatique du bouton ABANDONNER (anti mauvais clic).
const ABANDON_ARM_TIMEOUT := 3.0
# Durées des Tweens natifs (slide du panneau latéral, fondu de l'UI pendant le combat).
const SIDE_SLIDE_TIME := 0.35
const COMBAT_FADE_TIME := 0.5
# Slide vertical du panneau inférieur rétractable (§3, ergonomie).
const BOTTOM_SLIDE_TIME := 0.35
# Temps impartis AFFICHÉS en compte à rebours (§8.31, révisé) : 90 s en Phase 0 (déploiement aveugle
# simultané) ; en jeu, le rebours REPART à neuf à CHAQUE « Fin de Phase », avec un budget PAR PHASE.
# ⚠️ Le serveur ne diffuse PAS d'échéance dans l'état — sa minuterie est purement serveur (autorité).
# On affiche donc un rebours LOCAL aligné sur ces durées, remis à zéro à chaque changement de phase.
# Un léger décalage vs. l'échéance serveur est possible (toléré, indicatif).
const PHASE0_TIME := 90.0
# Budget par défaut d'une phase de jeu (Renforts / Déploiement / Mouvement) — miroir de
# DEFAULT_PHASE_TIMEOUT_SECONDS côté serveur (router.py).
const TURN_TIME := 60.0
# Phase d'Attaque (3) : budget de base plus large (animations de combat Split-Screen VS) ET seule
# phase extensible par la Time Bank (§8.33). Miroir de ATTACK_PHASE_TIMEOUT_SECONDS côté serveur.
const ATTACK_PHASE := 3
const ATTACK_PHASE_TIME := 90.0
# Plafond VISUEL du rebours en phase d'Attaque = hard_cap serveur (ATTACK_PHASE_MAX_TIMEOUT_SECONDS,
# §8.33) : la Time Bank ne peut JAMAIS pousser le compteur local au-delà (miroir de RoomTimers.hard_caps).
const ATTACK_PHASE_TIME_MAX := 180.0
# Couleurs du timer : normal (crème) puis rouge d'urgence sous le seuil.
const TIMER_COLOR := Color(0.9411765, 0.9019608, 0.8235294)
const TIMER_URGENT_COLOR := Color("d6453f")
const TIMER_URGENT_SECONDS := 10

# Canal de chat -> index d'onglet du TabContainer %ChatTabs (barre native masquée, §8.29).
# L'onglet « Alliés » est ABANDONNÉ (jeu chacun-pour-soi, §8.33) → 2 canaux seulement.
const CHAT_INDEX := {"general": 0, "prive": 1}
# Longueur max d'un message — aligné sur le serveur (CHAT_MAX_LENGTH = 500, §8.33).
const CHAT_MAX_LENGTH := 500

var _log_count := 0
var _elapsed := 0.0          # secondes écoulées sur le tour courant (affichage MM:SS)
var _turn_key := ""          # signature étape|tour|joueur|phase, pour remettre le timer à zéro
var _abandon_armed := false
var _chat_channels: Dictionary = {}
# Chat de salle (§8.33) : canal courant ("general"/"prive") + nœuds de la zone de saisie construite
# par code (LineEdit + sélecteur de destinataire privé + bouton d'envoi).
var _current_chat_tab := "general"
var _chat_input: LineEdit = null
var _chat_send_btn: Button = null
var _chat_target_option: OptionButton = null
# Identité du joueur LOCAL, poussée par le contrôleur (main.gd) : pseudo réel + couleur de la
# faction. Alimente l'indicateur d'identité de la TopBar et le libellé de tour (CONTEXTE.md §8.23).
var _local_pseudo: String = ""
var _local_color: Color = Color.WHITE
# Gros bouton « CONFIRMER LE DÉPLOIEMENT » (construit par code, inséré dans la barre d'action du
# BottomCenterWidget). Visible/actif uniquement quand le tampon atteint le quota exact (§8.26).
var _confirm_btn: Button = null
# Ré-assaut (E7 §8.79) : bouton « ⚔ RÉ-ASSAUT (S ➜ C) » près de « Fin de Phase ».
var _reassault_btn: Button = null
# Pulse « aucune action possible » sur %NextPhaseButton (E7) : état courant.
var _next_phase_pulse := false

# Panneau latéral rétractable (§8.29) : slide horizontal de SidePanelWidget via Tween natif.
var _side_tween: Tween
var _side_hidden := false
var _side_shown_x := 0.0
var _side_width := 0.0
var _side_metrics_ready := false
# Fondu de l'UI pendant le Split-Screen VS (§8.29) : Tween sur modulate.a du HUD racine.
var _fade_tween: Tween

# Compte à rebours de la PHASE courante : 90 s en Phase 0 / 90 s en Attaque / 60 s autres phases /
# 0 = hors tour minuté (initiative, fin de partie → "--:--"). Pilote _process ; posé par update_display.
var _turn_limit: float = 0.0
# --- Chrono SERVEUR (E3 §8.75) : quand le serveur diffuse son échéance (turn_timer/timer_update),
# %TimerLabel affiche deadline_epoch − (horloge locale + offset) — le rebours est alors EXACTEMENT
# celui qui déclenche le timeout serveur (reconnexion comprise). L'estimation locale historique
# (_turn_limit/_phase_turn_limit/add_time_to_timer) DEVIENT le repli legacy (serveur antérieur). ---
var _srv_active := false
var _srv_deadline_epoch: float = -1.0
var _srv_offset: float = 0.0   # server_time − horloge locale (immunise une horloge PC fausse)
# Pré-alerte AFK (E3) : sous AFK_ALERT_SECONDS sur NOTRE tour, chrono pulsé rouge + tic sonore/s.
const AFK_ALERT_SECONDS := 15
var _last_tick_second := -1
# Time Bank (§8.33) : cumul (s) crédité à la phase d'Attaque COURANTE par add_time_to_timer (≤ 90 s).
# Conservé d'un refresh à l'autre tant que la phase ne change pas → update_display le ré-applique sans
# l'écraser ; purgé au changement de phase (nouvelle signature _turn_key).
var _turn_bonus: float = 0.0
var _timer_urgent := false   # évite de réécrire la couleur du timer à chaque frame.
# Panneau inférieur rétractable (slide vertical, Tween natif). _bottom_shown_y = position Y déployée
# mémorisée juste avant un repli (robuste si la hauteur du panneau change).
var _bottom_tween: Tween
var _bottom_hidden := false
var _bottom_shown_y := 0.0
# Tooltip « Pouvoir de Faction » : nom + description poussés par main.gd (lus du .tres local).
var _faction_name: String = ""
var _faction_desc: String = ""
# Nom de faction AFFICHABLE par joueur (player_id str → nom EN invariant du .tres), poussé par
# main.gd (_push_factions_intel) — la barre d'info du tour ne montre plus l'id snake_case brut.
var faction_name_by_pid: Dictionary = {}

# Tiroir « INTEL : ZONE » (§8.36) — état ouvert/fermé + Tween de fondu du panneau (Mémoire Tactique).
var _intel_open := false
var _intel_tween: Tween
# Télégraphe de zone (G1 §8.62) : ligne d'état PERMANENTE « ☢ PROCHAINE ZONE : … » (or), créée
# par code sous l'objectif secret (BottomVBox) — pattern _build_confirm_button (pas de retouche .tscn).
var _forecast_label: Label = null
# Tracker d'objectif vivant (E6 §8.78) : conteneur de mini-lignes (barre + libellé) créé sous
# %ObjectiveLabel. ≥ 80 % → pulse OR (proche de la victoire).
var _objective_tracker: VBoxContainer = null
var _objective_pulse := false
# Prévision de combat (G4 §8.63) : ligne « PRÉVISION : victoire NN % … » créée par code sous
# l'instruction (TopCenterWidget), visible uniquement au survol d'une cible valide en Phase 3.
var _odds_label: Label = null
# Tiroir « INTEL : FACTIONS » (§2) — état ouvert/fermé + Tween de fondu (miroir du tiroir Zone).
var _factions_intel_open := false
var _factions_intel_tween: Tween
# Tiroir « INTEL : GUERRE » (E5 §8.77) — 3ᵉ tiroir, construit PAR CODE (insertion relative dans
# IntelWidget après le tiroir Factions — piège n° 5 évité : aucun nouveau nœud %).
var _war_intel_open := false
var _war_intel_tween: Tween
var _war_intel_btn: Button = null
var _war_intel_panel: PanelContainer = null
var _war_intel_players: VBoxContainer = null
var _war_intel_continents: VBoxContainer = null
# Roster de Guerre (E1 §8.73) : instance insérée en tête du SideVBox, rafraîchie par update_display.
var _war_roster: Control = null
# --- Journal de Guerre 2.0 (E4 §8.76) : flux structuré {category, icon, rich_text, tid, major},
# filtrable (chips TOUS/⚔/☢/🃏/⚙) et cliquable ([url=<tid>] → caméra). Toute entrée passe par
# add_feed_entries ; add_log (legacy) y route ses textes en catégorie system — AUCUNE perte. ---
const FEED_MAX := 200
var _feed_entries: Array = []
var _feed_filter := "all"
var _kill_feed: Control = null
# Toast défensif (E4) : panneau furtif « ⚠ X ATTAQUÉ PAR Y » — le plus récent remplace l'ancien.
var _defense_toast: PanelContainer = null
var _toast_tween: Tween = null
# Bandeau de combat compact (E8 §8.80, mode "bandeau") : combats où je ne suis pas impliqué.
var _combat_banner: PanelContainer = null
var _combat_banner_tween: Tween = null
# Brique identité du propriétaire dans l'Inspecteur de Territoire (E1) — créée paresseusement,
# insérée juste après %InspectorOwner (le label nu ne sert plus qu'au cas NEUTRE).
var _inspector_chip: Control = null
# Inspecteur Tactique de Territoire (§1) — Tween de fondu d'apparition/disparition.
var _inspector_tween: Tween

# --- Couche RPG « Héros » (sprint RPG & Survie, Objectif 5) : panneau héros du joueur (PV/PA/PB/PP/
#     Niveau) + inspecteur des stats d'un adversaire. Construits PAR CODE (comme _build_confirm_button),
#     pilotés par main.gd (View pure §6.1 : set_hero_panel / set_player_inspector). ---
const HERO_DANGER := Color("d6453f")
const HERO_MUTED := Color("8a97a5")
var _hero_panel: PanelContainer = null
var _hero_level_lbl: Label = null
var _hero_pv_bar: ProgressBar = null
var _hero_pv_lbl: Label = null
var _hero_stats_lbl: Label = null
var _hero_pp_bar: ProgressBar = null
var _hero_pp_lbl: Label = null
var _hero_xp_bar: ProgressBar = null
var _hero_xp_lbl: Label = null
# Dernière valeur de PP affichée (pour la flèche de tendance ▲/▼ à chaque mise à jour). null = inconnu.
var _hero_pp_last = null
var _player_inspector: PanelContainer = null
var _pi_name: Label = null
var _pi_stats: Label = null
var _pi_tween: Tween = null

func _ready() -> void:
	%NextPhaseButton.pressed.connect(func(): pass_pressed.emit())
	%AbandonButton.pressed.connect(_on_abandon_clicked)
	%ToggleSidePanelButton.pressed.connect(_toggle_side_panel)
	%ToggleBottomPanelButton.pressed.connect(_toggle_bottom_panel)
	# Tiroir « INTEL : ZONE » (§8.36) : bouton ghost qui déploie/replie le panneau de Mémoire
	# Tactique (glassmorphism à liseré cyan). Masqué par défaut (alimenté par main.gd -> set_intel).
	%IntelToggleButton.pressed.connect(_toggle_intel)
	%IntelPanel.visible = false
	# Tiroir « INTEL : FACTIONS » (§2, Warzone Command) : 2ᵉ tiroir indépendant listant les pouvoirs
	# passifs des factions en jeu (data-driven ; alimenté par main.gd -> set_factions_intel).
	%IntelFactionsToggleButton.pressed.connect(_toggle_factions_intel)
	%IntelFactionsPanel.visible = false
	# Tiroir « INTEL : GUERRE » (E5 §8.77) : 3ᵉ tiroir — rapports de force complets.
	_build_war_intel()
	# Inspecteur Tactique de Territoire (§1) : panneau flottant bas-droite, ouvert au clic d'un
	# territoire (main.gd -> set_territory_inspector), refermé au clic dans le vide (board_cleared) ou ✕.
	%InspectorClose.pressed.connect(hide_territory_inspector)
	%TerritoryInspector.visible = false
	# SFX d'interface (survol/clic — R6) sur les boutons d'action du HUD.
	for b in [%NextPhaseButton, %AbandonButton, %ToggleSidePanelButton, %ToggleBottomPanelButton, %IntelToggleButton, %IntelFactionsToggleButton, %InspectorClose, %TabBtnGeneral, %TabBtnPrive]:
		b.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
		b.pressed.connect(func() -> void: AudioManager.play_sfx("click"))
	# Tooltip « Pouvoir de Faction » (§3) : survol de l'icône Info. Masqués tant que main.gd n'a pas
	# poussé une faction valide (set_faction_info).
	%FactionInfoButton.mouse_entered.connect(_show_faction_tooltip)
	%FactionInfoButton.mouse_exited.connect(_hide_faction_tooltip)
	%FactionInfoButton.visible = false
	%FactionTooltip.visible = false
	_build_confirm_button()
	_build_hero_panel()
	_build_player_inspector()
	_setup_chat_tabs()
	_build_chat_input()
	_build_war_roster()
	_build_feed_filters()
	_build_kill_feed()
	_build_reassault_button()
	_build_amount_shortcuts()
	# Clic d'une entrée [url=<tid>] du journal (E4 §8.76) → remonte au contrôleur (caméra).
	%LogText.meta_clicked.connect(func(meta) -> void: log_territory_clicked.emit(str(meta)))
	# Chat de salle CÂBLÉ au réseau (§8.33) : main.gd relaie chat_send_requested -> NetworkManager
	# et route les messages reçus vers add_chat_message. 2 canaux (Général / Privé).
	add_chat_message("general", tr("HUD_CHAT_WELCOME_GENERAL"))
	add_chat_message("prive", tr("HUD_CHAT_WELCOME_PRIVATE"))

# Compte à rebours du tour courant, affiché MM:SS. Mode SERVEUR (E3 §8.75) : rebours calé sur
# l'échéance diffusée (deadline_epoch − horloge locale corrigée de l'offset). Mode LEGACY (serveur
# antérieur, §9.2) : décompte local depuis _turn_limit (90 s Phase 0 / 60 s tour), remis à zéro au
# changement de tour par update_display(). Hors tour minuté → "--:--".
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
# (E3) — sous 15 s sur NOTRE tour : pulse + tic sonore discret à chaque seconde (l'abandon auto
# §8.31 ne doit JAMAIS surprendre).
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

# Budget du rebours pour la phase de JEU courante (miroir de router._playing_phase_budget) : la phase
# d'Attaque (3) part de 90 s et s'étend par la Time Bank (_turn_bonus) jusqu'à 180 s ; toute autre
# phase a un budget fixe de 60 s (le bonus y est ignoré — aucune attaque ne le crédite hors phase 3).
func _phase_turn_limit() -> float:
	if int(GameState.current_phase) == ATTACK_PHASE:
		return minf(ATTACK_PHASE_TIME + _turn_bonus, ATTACK_PHASE_TIME_MAX)
	return TURN_TIME

# Time Bank (§8.33) : crédite le rebours LOCAL de la phase d'Attaque des `seconds` gagnées par une
# attaque, en miroir EXACT de RoomTimers.extend_deadline côté serveur (qui repousse l'échéance de la
# phase d'Attaque). Appelée par main.gd à la réception de `attack_result`, sur TOUS les clients (le
# compteur affiché est celui de la phase courante, identique pour tous) — pas seulement l'attaquant.
# Plafond = ATTACK_PHASE_TIME_MAX (180 s), identique au hard_cap serveur → le compteur ne dépasse
# jamais l'échéance autorisée. No-op hors d'un tour minuté (_turn_limit <= 0) : la bank n'a de sens
# qu'en jeu (et en pratique seules les attaques, donc la phase 3, la créditent).
func add_time_to_timer(seconds: int) -> void:
	# Mode chrono SERVEUR (E3 §8.75) : le +10 s arrive par le message `timer_update`
	# (reason "time_bank") avec la NOUVELLE échéance — le crédit local serait un double comptage.
	if _srv_active:
		return
	if seconds <= 0 or _turn_limit <= 0.0:
		return
	# On accumule dans _turn_bonus (borné au plafond Attaque) puis on recalcule _turn_limit via le
	# budget de phase : le bonus survit ainsi aux update_display() suivants de la même phase (qui
	# relisent _turn_bonus). Hors phase d'Attaque, _phase_turn_limit() ignore le bonus (rebours fixe).
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

# Verrouille définitivement le bouton une fois l'abandon CONFIRMÉ par le serveur
# (message player_abandoned nous concernant, relayé par main.gd) : évite un 2e envoi,
# que le backend rejetterait (« Vous avez déjà abandonné la partie »).
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

# =========================================================
# Prévision de combat (G4 §8.63) — « PRÉVISION : victoire NN % · pertes est. N,N »
# =========================================================
# Ligne créée par code SOUS l'instruction (TopCenterWidget) : cyan si ≥ 65 %, or si 40-65 %,
# rouge si < 40 %. Poussée par main.gd au survol d'une cible ennemie adjacente (Phase 3, source
# sélectionnée), masquée au unhover / à la désélection. Calcul 100 % client (CombatOdds) — les
# pouvoirs ponctuels À ÉTATS (cartes, boucliers…) ne sont pas simulés, d'où la mention discrète.

func _ensure_odds_label() -> void:
	if _odds_label != null and is_instance_valid(_odds_label):
		return
	_odds_label = Label.new()
	_odds_label.name = "CombatOddsLabel"
	_odds_label.add_theme_font_size_override("font_size", 14)
	_odds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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

# Bouton « ⚔ RÉ-ASSAUT » construit par code et inséré juste avant « Fin de Phase » (pattern
# _build_confirm_button). Masqué par défaut ; piloté par set_reassault (main.gd).
func _build_reassault_button() -> void:
	_reassault_btn = Button.new()
	_reassault_btn.visible = false
	_reassault_btn.add_theme_font_size_override("font_size", 16)
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

# Raccourcis de quantité +1 / +5 / MAX accolés à %AmountSpin (E7 §8.79). Émettent amount_quick
# (delta 1 / 5 / -1=MAX) ; main.gd applique selon la phase (spin de mouvement ou tampon).
func _build_amount_shortcuts() -> void:
	var spin: Control = %AmountSpin
	var row := spin.get_parent()
	var defs := [["+1", 1], ["+5", 5], ["MAX", -1]]
	var idx := spin.get_index() + 1
	for d in defs:
		var b := Button.new()
		b.text = str(d[0])
		b.custom_minimum_size = Vector2(38, 0)
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.add_theme_font_size_override("font_size", 12)
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

# Identité du joueur LOCAL (pseudo + couleur de faction) — appelée par main.gd à chaque refresh.
# Colore le pseudo dans la TopBar avec la couleur de la faction du joueur (charte §8.23).
func set_local_identity(pseudo: String, color: Color) -> void:
	_local_pseudo = pseudo
	_local_color = color
	%IdentityLabel.text = "❯ " + (pseudo if pseudo != "" else "—")
	%IdentityLabel.add_theme_color_override("font_color", color)

# =========================================================
# Tooltip « Pouvoir de Faction » (§3) — icône Info survolable à côté de l'identité
# =========================================================

# Infos de faction du joueur LOCAL (nom + description du pouvoir), poussées par main.gd (lues du
# .tres). Nom vide → faction inconnue : on masque l'icône Info et tout tooltip ouvert.
func set_faction_info(faction_name: String, description: String) -> void:
	_faction_name = faction_name
	_faction_desc = description
	%FactionInfoButton.visible = faction_name != ""
	if faction_name == "":
		%FactionTooltip.visible = false

# Affiche le tooltip flottant (nom + description) sous l'icône Info, en le maintenant dans l'écran.
# Appelé au survol (mouse_entered) de %FactionInfoButton.
func _show_faction_tooltip() -> void:
	if _faction_name == "":
		return
	%FactionTooltipTitle.text = _faction_name
	%FactionTooltipDesc.text = _faction_desc if _faction_desc != "" else tr("HUD_NO_MODIFIER")
	var tip: Control = %FactionTooltip
	tip.reset_size()  # recalcule la taille (PanelContainer) avant de clamper la position.
	var btn: Control = %FactionInfoButton
	var pos := btn.global_position + Vector2(0.0, btn.size.y + 6.0)
	var screen_w := get_viewport_rect().size.x
	pos.x = clampf(pos.x, 8.0, maxf(8.0, screen_w - tip.size.x - 8.0))
	tip.global_position = pos
	tip.visible = true

func _hide_faction_tooltip() -> void:
	%FactionTooltip.visible = false

# =========================================================
# Tiroir « INTEL : ZONE » — Mémoire Tactique (§8.36)
# =========================================================
# Renseignements GLOBAUX sur la Zone de Contamination, exploitant GameState.statistics (§8.35).
# Le HUD reste une VIEW pure (Règle d'Or §6.1) : main.gd résout pseudos + couleurs de faction et
# pousse une liste prête à afficher via set_intel(). Aucun accès réseau/état ici.

# Déploie / replie le panneau Intel (fondu via Tween natif, cohérent avec les autres panneaux).
func _toggle_intel() -> void:
	_intel_open = not _intel_open
	%IntelToggleButton.text = tr("HUD_INTEL_ZONE") + (" ▾" if _intel_open else " ▸")
	if _intel_tween and _intel_tween.is_valid():
		_intel_tween.kill()
	var panel: Control = %IntelPanel
	if _intel_open:
		panel.modulate.a = 0.0
		panel.visible = true
		_intel_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_intel_tween.tween_property(panel, "modulate:a", 1.0, 0.2)
	else:
		_intel_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_intel_tween.tween_property(panel, "modulate:a", 0.0, 0.15)
		_intel_tween.tween_callback(func(): panel.visible = false)

# Alimente le panneau Intel (Mémoire Tactique §8.35). Poussé par main.gd à chaque rafraîchissement.
#   stagnation : rounds globaux consécutifs sans déplacement de la zone (zone_stagnation_turns).
#   entries    : Array[{ "pseudo": String, "color": Color, "kills": int }] — pertes infligées par la
#                zone, déjà résolues (pseudo + accent_color) par le contrôleur, triées et filtrées.
func set_intel(stagnation: int, entries: Array) -> void:
	if stagnation > 0:
		%StagnationLabel.text = tr("HUD_STAGNATION_FMT") % stagnation
	else:
		%StagnationLabel.text = tr("HUD_STAGNATION_UNSTABLE")
	var list: VBoxContainer = %ZoneKillsList
	for child in list.get_children():
		child.queue_free()
	if entries.is_empty():
		var empty := Label.new()
		empty.text = tr("HUD_ZONE_NO_LOSSES")
		empty.add_theme_color_override("font_color", Color("8a8f7a"))
		empty.add_theme_font_size_override("font_size", 13)
		list.add_child(empty)
		return
	for e in entries:
		var row := Label.new()
		row.text = tr("HUD_ZONE_LOSS_FMT") % [str(e.get("pseudo", "?")), int(e.get("kills", 0))]
		row.add_theme_color_override("font_color", e.get("color", Color.WHITE))
		row.add_theme_font_size_override("font_size", 14)
		list.add_child(row)

# =========================================================
# Télégraphe de la zone (G1 §8.62) — « PROCHAINE ZONE : <noms> »
# =========================================================
# Ligne d'état PERMANENTE (or, charte §2) affichée sous l'objectif secret dans le bloc central bas.
# Poussée par main.gd (noms déjà résolus via MapData — le HUD reste une View pure §6.1). Le label
# est créé paresseusement par code et inséré juste APRÈS %ObjectiveLabel dans son conteneur.

func _ensure_forecast_label() -> void:
	if _forecast_label != null and is_instance_valid(_forecast_label):
		return
	_forecast_label = Label.new()
	_forecast_label.name = "ZoneForecastLabel"
	_forecast_label.add_theme_color_override("font_color", ACCENT_GOLD)
	_forecast_label.add_theme_font_size_override("font_size", 13)
	_forecast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var anchor: Control = %ObjectiveLabel
	var parent := anchor.get_parent()
	parent.add_child(_forecast_label)
	parent.move_child(_forecast_label, anchor.get_index() + 1)

# =========================================================
# Tracker d'objectif vivant (E6 §8.78) — jauge de progression sous l'objectif secret
# =========================================================
# Conteneur créé paresseusement et inséré juste APRÈS %ObjectiveLabel (pattern _ensure_forecast_label,
# ancrage relatif — piège n° 6). Alimenté par main.gd (set_objective_progress, View pure §6.1).

func _ensure_objective_tracker() -> void:
	if _objective_tracker != null and is_instance_valid(_objective_tracker):
		return
	_objective_tracker = VBoxContainer.new()
	_objective_tracker.name = "ObjectiveTracker"
	_objective_tracker.add_theme_constant_override("separation", 1)
	var anchor: Control = %ObjectiveLabel
	var parent := anchor.get_parent()
	parent.add_child(_objective_tracker)
	parent.move_child(_objective_tracker, anchor.get_index() + 1)

# Alimente le tracker. data = objective_tracker.progress(objective, ctx) résolu par main.gd :
# { lines: Array[{label, ratio, done}], best_ratio: float, done: bool } + tooltip (description
# complète). Vide → tracker masqué (pas d'objectif / partie non lancée).
func set_objective_progress(data: Dictionary, tooltip: String = "") -> void:
	_ensure_objective_tracker()
	var lines: Array = data.get("lines", [])
	for c in _objective_tracker.get_children():
		_objective_tracker.remove_child(c)
		c.queue_free()
	if lines.is_empty():
		_objective_tracker.visible = false
		return
	_objective_tracker.visible = true
	var multi: bool = lines.size() > 1
	for i in range(lines.size()):
		var l: Dictionary = lines[i]
		var done: bool = bool(l.get("done", false))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		# Séparateur « OU » entre les deux volets d'un objectif double (§8.61).
		if multi and i > 0:
			var sep := Label.new()
			sep.text = tr("OBJ_OR")
			sep.add_theme_font_size_override("font_size", 10)
			sep.add_theme_color_override("font_color", HERO_MUTED)
			_objective_tracker.add_child(sep)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(80, 7)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.max_value = 1.0
		bar.value = float(l.get("ratio", 0.0))
		_tint_progress(bar, Color("46b58a") if done else ACCENT_GOLD)
		row.add_child(bar)
		var lbl := Label.new()
		lbl.text = ("✔ " if done else "") + str(l.get("label", ""))
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color("46b58a") if done else Color("c8cdd6"))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		_objective_tracker.add_child(row)
	if tooltip != "":
		_objective_tracker.tooltip_text = tooltip
	# ≥ 80 % (ou accompli) → pulse OR discret : proche de la victoire (piloté dans _process).
	_objective_pulse = float(data.get("best_ratio", 0.0)) >= 0.8 or bool(data.get("done", false))
	if not _objective_pulse:
		_objective_tracker.modulate = Color(1, 1, 1, 1)

# Alimente la ligne du télégraphe. `names` = noms lisibles des territoires annoncés (Array[String],
# résolus par main.gd). Vide → mention neutre (serveur antérieur au télégraphe / partie non lancée).
func set_zone_forecast(names: Array) -> void:
	_ensure_forecast_label()
	if names.is_empty():
		_forecast_label.text = tr("HUD_NEXT_ZONE_NONE")
	else:
		var joined := ", ".join(PackedStringArray(names))
		_forecast_label.text = tr("HUD_NEXT_ZONE_FMT") % joined


# =========================================================
# Tiroir « INTEL : FACTIONS » (§2) — pouvoirs passifs des factions adverses
# =========================================================
# Pendant du tiroir Zone : main.gd résout pseudo + faction + pouvoir + couleur et pousse une liste
# prête à afficher (Règle d'Or §6.1). Aucun accès réseau/état ici.

# Déploie / replie le panneau Factions (fondu Tween natif, cohérent avec le tiroir Zone).
func _toggle_factions_intel() -> void:
	_factions_intel_open = not _factions_intel_open
	%IntelFactionsToggleButton.text = tr("HUD_INTEL_FACTIONS") + (" ▾" if _factions_intel_open else " ▸")
	if _factions_intel_tween and _factions_intel_tween.is_valid():
		_factions_intel_tween.kill()
	var panel: Control = %IntelFactionsPanel
	if _factions_intel_open:
		panel.modulate.a = 0.0
		panel.visible = true
		_factions_intel_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_factions_intel_tween.tween_property(panel, "modulate:a", 1.0, 0.2)
	else:
		_factions_intel_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_factions_intel_tween.tween_property(panel, "modulate:a", 0.0, 0.15)
		_factions_intel_tween.tween_callback(func(): panel.visible = false)

# Alimente la liste des factions (§2). entries = Array[{ pseudo, faction_name, color: Color, power }],
# déjà résolue et triée par main.gd. Chaque joueur = une « operator card » Warzone : chevron à la
# couleur de faction + pseudo, nom de faction coloré, résumé du pouvoir passif.
func set_factions_intel(entries: Array) -> void:
	var list: VBoxContainer = %FactionsList
	for child in list.get_children():
		child.queue_free()
	if entries.is_empty():
		var empty := Label.new()
		empty.text = tr("HUD_NO_FACTION_DETECTED")
		empty.add_theme_color_override("font_color", Color("8a8f7a"))
		empty.add_theme_font_size_override("font_size", 13)
		list.add_child(empty)
		return
	for e in entries:
		var color: Color = e.get("color", ACCENT_CYAN)
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 0)
		var who := Label.new()
		who.text = "❯ %s" % str(e.get("pseudo", "?"))
		who.add_theme_color_override("font_color", color)
		who.add_theme_font_size_override("font_size", 15)
		card.add_child(who)
		var fac := Label.new()
		fac.text = str(e.get("faction_name", "—")).to_upper()
		fac.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.25))
		fac.add_theme_font_size_override("font_size", 12)
		card.add_child(fac)
		var pw := Label.new()
		pw.text = str(e.get("power", ""))
		pw.add_theme_color_override("font_color", Color("c8cdd6"))
		pw.add_theme_font_size_override("font_size", 12)
		pw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pw.custom_minimum_size = Vector2(224, 0)
		card.add_child(pw)
		list.add_child(card)

# =========================================================
# Tiroir « INTEL : GUERRE » (E5 §8.77) — rapports de force complets (War Room)
# =========================================================
# 3ᵉ tiroir, construit PAR CODE et inséré dans IntelWidget APRÈS le tiroir Factions (insertion
# relative — aucun nouveau nœud % dans la scène, pièges n° 5/6). Mêmes anims/styles que les deux
# tiroirs existants ; alimenté par main.gd → set_war_intel (View pure §6.1).

func _build_war_intel() -> void:
	var widget := %IntelFactionsPanel.get_parent()
	_war_intel_btn = Button.new()
	_war_intel_btn.text = tr("INTEL_WAR_BTN") + " ▸"
	_war_intel_btn.custom_minimum_size = Vector2(150, 0)
	_war_intel_btn.size_flags_horizontal = 0
	_war_intel_btn.tooltip_text = tr("INTEL_WAR_TOOLTIP")
	_war_intel_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Style « ghost » des toggles Intel (répliqué par code — les SubResources vivent dans la scène).
	var ghost := StyleBoxFlat.new()
	ghost.bg_color = Color(0.05, 0.05, 0.07, 0.35)
	ghost.border_color = Color(ACCENT_CYAN, 0.55)
	ghost.set_border_width_all(1)
	ghost.set_corner_radius_all(0)
	ghost.set_content_margin_all(6)
	var ghost_hover := ghost.duplicate()
	ghost_hover.bg_color = Color(ACCENT_CYAN, 0.14)
	ghost_hover.border_color = ACCENT_CYAN
	_war_intel_btn.add_theme_stylebox_override("normal", ghost)
	_war_intel_btn.add_theme_stylebox_override("hover", ghost_hover)
	_war_intel_btn.add_theme_stylebox_override("pressed", ghost_hover)
	_war_intel_btn.add_theme_color_override("font_color", Color("eef3f7"))
	_war_intel_btn.add_theme_color_override("font_hover_color", ACCENT_CYAN)
	_war_intel_btn.add_theme_color_override("font_pressed_color", ACCENT_CYAN)
	_war_intel_btn.add_theme_font_size_override("font_size", 14)
	_war_intel_btn.pressed.connect(_toggle_war_intel)
	_war_intel_btn.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	_war_intel_btn.pressed.connect(func() -> void: AudioManager.play_sfx("click"))

	_war_intel_panel = PanelContainer.new()
	_war_intel_panel.visible = false
	_war_intel_panel.custom_minimum_size = Vector2(300, 0)
	_war_intel_panel.add_theme_stylebox_override("panel", _hero_panel_style())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_war_intel_panel.add_child(col)
	var title := Label.new()
	title.text = tr("WARROOM_TITLE")
	title.add_theme_color_override("font_color", ACCENT_CYAN)
	title.add_theme_font_size_override("font_size", 15)
	col.add_child(title)
	_war_intel_players = VBoxContainer.new()
	_war_intel_players.add_theme_constant_override("separation", 8)
	col.add_child(_war_intel_players)
	var sep := HSeparator.new()
	col.add_child(sep)
	var ctitle := Label.new()
	ctitle.text = tr("WARROOM_CONTINENTS")
	ctitle.add_theme_color_override("font_color", HERO_MUTED)
	ctitle.add_theme_font_size_override("font_size", 11)
	col.add_child(ctitle)
	_war_intel_continents = VBoxContainer.new()
	_war_intel_continents.add_theme_constant_override("separation", 3)
	col.add_child(_war_intel_continents)

	# Insertion APRÈS le tiroir Factions (le widget est un VBox : bouton puis panneau).
	widget.add_child(_war_intel_btn)
	widget.move_child(_war_intel_btn, %IntelFactionsPanel.get_index() + 1)
	widget.add_child(_war_intel_panel)
	widget.move_child(_war_intel_panel, _war_intel_btn.get_index() + 1)

func _toggle_war_intel() -> void:
	_war_intel_open = not _war_intel_open
	_war_intel_btn.text = tr("INTEL_WAR_BTN") + (" ▾" if _war_intel_open else " ▸")
	if _war_intel_tween and _war_intel_tween.is_valid():
		_war_intel_tween.kill()
	if _war_intel_open:
		_war_intel_panel.modulate.a = 0.0
		_war_intel_panel.visible = true
		_war_intel_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_war_intel_tween.tween_property(_war_intel_panel, "modulate:a", 1.0, 0.2)
	else:
		_war_intel_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_war_intel_tween.tween_property(_war_intel_panel, "modulate:a", 0.0, 0.15)
		_war_intel_tween.tween_callback(func() -> void: _war_intel_panel.visible = false)

# Alimente la War Room (E5). rows = war_room.player_rows (tri territoires desc) ; continents =
# war_room.continent_rows. Reconstruction complète (pattern set_factions_intel).
func set_war_intel(rows: Array, continents: Array) -> void:
	if _war_intel_players == null:
		return
	for c in _war_intel_players.get_children():
		c.queue_free()
	var max_threat := 1
	for r in rows:
		max_threat = maxi(max_threat, int(r.get("threat", 0)))
	for r in rows:
		_war_intel_players.add_child(_make_war_row(r, max_threat))
	for c in _war_intel_continents.get_children():
		c.queue_free()
	for cr in continents:
		_war_intel_continents.add_child(_make_continent_row(cr))

# Carte joueur (E-visuel) : en-tête [chip | 🏴 terr | barre MENACE étiquetée] puis une GRILLE de
# pastilles ÉTIQUETÉES (ligne 1 = Combat, ligne 2 = Héros/Zone) et le ratio V/D chiffré. Chaque
# pastille porte son tooltip → fini la « soupe d'emojis » compressée, tout est lisible sans survol.
func _make_war_row(r: Dictionary, max_threat: int) -> Control:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 4)

	# ---- En-tête : identité + territoires + menace labellisée ----
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var chip := PlayerChipScene.instantiate()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(chip)
	chip.setup(int(r.get("pid", 0)), true)
	var terr := Label.new()
	terr.text = "⚑%d" % int(r.get("territories", 0))
	terr.add_theme_font_size_override("font_size", 12)
	terr.add_theme_color_override("font_color", Color("eef3f7"))
	terr.add_theme_font_override("font", RosterHelpers._mono_font())
	terr.tooltip_text = tr("ROSTER_TERR_TOOLTIP")
	terr.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(terr)
	# Barre de MENACE ÉTIQUETÉE (indice indicatif, AUCUN effet gameplay) : territoires×2 + kills
	# − pertes + éliminations×5, normalisé sur le max de la table (formule en tooltip).
	var threat_lbl := Label.new()
	threat_lbl.text = tr("WARROOM_LBL_THREAT")
	threat_lbl.add_theme_font_size_override("font_size", 9)
	threat_lbl.add_theme_color_override("font_color", HERO_MUTED)
	threat_lbl.tooltip_text = tr("WARROOM_THREAT_TOOLTIP") % int(r.get("threat", 0))
	head.add_child(threat_lbl)
	var threat := ProgressBar.new()
	threat.show_percentage = false
	threat.custom_minimum_size = Vector2(40, 6)
	threat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	threat.max_value = float(max_threat)
	threat.value = float(maxi(int(r.get("threat", 0)), 0))
	threat.mouse_filter = Control.MOUSE_FILTER_PASS
	threat.tooltip_text = tr("WARROOM_THREAT_TOOLTIP") % int(r.get("threat", 0))
	RosterHelpers._tint_progress(threat, ACCENT_GOLD)
	head.add_child(threat)
	card.add_child(head)

	# ---- Grille de pastilles étiquetées : ligne 1 = Combat, ligne 2 = Héros/Zone ----
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	grid.add_child(_stat_pill("⚔", "WARROOM_LBL_KILLS", int(r.get("kills", 0)), "WARROOM_TIP_KILLS"))
	grid.add_child(_stat_pill("☠", "WARROOM_LBL_LOSSES", int(r.get("losses", 0)), "WARROOM_TIP_LOSSES"))
	grid.add_child(_stat_pill("⚑", "WARROOM_LBL_CONQ", int(r.get("conquests", 0)), "WARROOM_TIP_CONQ"))
	grid.add_child(_stat_pill("◎", "WARROOM_LBL_ELIM", int(r.get("eliminations", 0)), "WARROOM_TIP_ELIM"))
	grid.add_child(_stat_pill("✸", "WARROOM_LBL_HERODMG", int(r.get("hero_damage", 0)), "WARROOM_TIP_HERODMG"))
	grid.add_child(_stat_pill("⚰", "WARROOM_LBL_HEROKILL", int(r.get("hero_kills", 0)), "WARROOM_TIP_HEROKILL"))
	grid.add_child(_stat_pill("☢", "WARROOM_LBL_ZONE", int(r.get("zone_deaths", 0)), "WARROOM_TIP_ZONE"))
	card.add_child(grid)

	# ---- Ratio V/D : libellé + barre (dégradé pv_color) + pourcentage chiffré ----
	var ratio := float(r.get("ratio", 0.5))
	var ratio_tip := tr("WARROOM_RATIO_TOOLTIP") % [int(r.get("kills", 0)), int(r.get("losses", 0))]
	var ratio_line := HBoxContainer.new()
	ratio_line.add_theme_constant_override("separation", 6)
	var wl := Label.new()
	wl.text = tr("WARROOM_LBL_WL")
	wl.add_theme_font_size_override("font_size", 10)
	wl.add_theme_color_override("font_color", HERO_MUTED)
	wl.tooltip_text = ratio_tip
	ratio_line.add_child(wl)
	var rbar := ProgressBar.new()
	rbar.show_percentage = false
	rbar.custom_minimum_size = Vector2(0, 6)
	rbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rbar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rbar.max_value = 1.0
	rbar.value = ratio
	rbar.mouse_filter = Control.MOUSE_FILTER_PASS
	rbar.tooltip_text = ratio_tip
	RosterHelpers._tint_progress(rbar, RosterHelpers.pv_color(ratio))
	ratio_line.add_child(rbar)
	var pct := Label.new()
	pct.text = "%d%%" % int(round(ratio * 100.0))
	pct.add_theme_font_size_override("font_size", 11)
	pct.add_theme_color_override("font_color", Color("eef3f7"))
	pct.add_theme_font_override("font", RosterHelpers._mono_font())
	pct.tooltip_text = ratio_tip
	pct.mouse_filter = Control.MOUSE_FILTER_PASS
	ratio_line.add_child(pct)
	card.add_child(ratio_line)
	return card

# Pastille de stat étiquetée (E-visuel) : [icône][libellé court MUET][valeur mono claire] sur un
# fond très discret, coins droits (charte §2). Le tooltip explicatif rend la légende globale
# facultative (elle reste néanmoins en tooltip du panneau). Remplace la « soupe d'emojis ».
func _stat_pill(icon: String, label_key: String, value: int, tip_key: String) -> Control:
	var pill := PanelContainer.new()
	pill.tooltip_text = tr(tip_key)
	pill.mouse_filter = Control.MOUSE_FILTER_PASS
	var st := StyleBoxFlat.new()
	st.bg_color = Color(1, 1, 1, 0.04)
	st.set_corner_radius_all(0)
	st.content_margin_left = 4
	st.content_margin_right = 4
	st.content_margin_top = 2
	st.content_margin_bottom = 2
	pill.add_theme_stylebox_override("panel", st)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	pill.add_child(box)
	var ic := Label.new()
	ic.text = icon
	ic.add_theme_font_size_override("font_size", 10)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(ic)
	var lbl := Label.new()
	lbl.text = tr(label_key)
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", HERO_MUTED)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lbl)
	var val := Label.new()
	val.text = str(value)
	val.add_theme_font_size_override("font_size", 11)
	val.add_theme_color_override("font_color", Color("eef3f7"))
	val.add_theme_font_override("font", RosterHelpers._mono_font())
	val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(val)
	return pill

# Ligne de continent : « CONTRÔLÉ par <chip> » si un joueur possède TOUT, sinon « CONTESTÉ x/y »
# avec le leader en chip atténuée.
func _make_continent_row(cr: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var name_lbl := Label.new()
	name_lbl.text = str(cr.get("name", "?")).to_upper()
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", Color("c8cdd6"))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_lbl)
	var owner = cr.get("owner", null)
	if owner != null:
		var tag := Label.new()
		tag.text = tr("WARROOM_CONTROLLED")
		tag.add_theme_font_size_override("font_size", 10)
		tag.add_theme_color_override("font_color", ACCENT_GOLD)
		row.add_child(tag)
		var chip := PlayerChipScene.instantiate()
		row.add_child(chip)
		chip.setup(int(owner), true)
	else:
		var tag := Label.new()
		tag.text = tr("WARROOM_CONTESTED") % [int(cr.get("held", 0)), int(cr.get("total", 0))]
		tag.add_theme_font_size_override("font_size", 10)
		tag.add_theme_color_override("font_color", HERO_MUTED)
		row.add_child(tag)
		var leader = cr.get("leader_pid", null)
		if leader != null:
			var chip := PlayerChipScene.instantiate()
			chip.modulate = Color(1, 1, 1, 0.6)
			row.add_child(chip)
			chip.setup(int(leader), true)
	return row

# =========================================================
# Inspecteur Tactique de Territoire (§1) — lecteur flottant bas-droite
# =========================================================
# Ouvert au clic d'un territoire (main.gd résout les données, le HUD reste une View). data =
# { name, owner_name, owner_color: Color, owner_id: int|null (E1), troops: int, contaminated: bool }.

# Brique identité du propriétaire (E1 §8.73) : créée paresseusement et insérée juste APRÈS
# %InspectorOwner dans son conteneur (pattern _ensure_forecast_label — insertion relative).
func _ensure_inspector_chip() -> void:
	if _inspector_chip != null and is_instance_valid(_inspector_chip):
		return
	_inspector_chip = PlayerChipScene.instantiate()
	var anchor: Control = %InspectorOwner
	var parent := anchor.get_parent()
	parent.add_child(_inspector_chip)
	parent.move_child(_inspector_chip, anchor.get_index() + 1)

func set_territory_inspector(data: Dictionary) -> void:
	%InspectorName.text = str(data.get("name", "—")).to_upper()
	var owner_col: Color = data.get("owner_color", Color("8a97a5"))
	# E1 §8.73 : propriétaire présenté par player_chip (pastille couleur plateau + pseudo + faction)
	# dès qu'il y en a un — y compris un BOT (id NÉGATIF, G2 §8.72). Le label nu ne sert plus qu'au
	# cas NEUTRE (owner_id null) et aux appels legacy sans owner_id (rétro-compat).
	var owner_id = data.get("owner_id", null)
	if owner_id != null:
		_ensure_inspector_chip()
		_inspector_chip.visible = true
		_inspector_chip.setup(int(owner_id), true)
		%InspectorOwner.visible = false
	else:
		if _inspector_chip != null and is_instance_valid(_inspector_chip):
			_inspector_chip.visible = false
		%InspectorOwner.visible = true
		%InspectorOwner.text = str(data.get("owner_name", "—"))
		%InspectorOwner.add_theme_color_override("font_color", owner_col)
	%InspectorTroops.text = str(int(data.get("troops", 0)))
	%InspectorStatus.text = tr("HUD_CONTAMINATED") if bool(data.get("contaminated", false)) else ""
	var insp: Control = %TerritoryInspector
	if _inspector_tween and _inspector_tween.is_valid():
		_inspector_tween.kill()
	# Fondu d'apparition seulement quand le panneau était masqué ; un re-clic (autre territoire)
	# met juste à jour le texte sans re-fader (lecture fluide).
	if not insp.visible:
		insp.modulate.a = 0.0
		insp.visible = true
		_inspector_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_inspector_tween.tween_property(insp, "modulate:a", 1.0, 0.18)

func hide_territory_inspector() -> void:
	var insp: Control = %TerritoryInspector
	if not insp.visible:
		return
	if _inspector_tween and _inspector_tween.is_valid():
		_inspector_tween.kill()
	_inspector_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_inspector_tween.tween_property(insp, "modulate:a", 0.0, 0.14)
	_inspector_tween.tween_callback(func(): insp.visible = false)


# =========================================================
# Couche RPG « Héros » — panneau du joueur + inspecteur adversaire (Objectif 5a / 5b)
# =========================================================
# Style de panneau angulaire « Warzone Command » (surface gunmetal + fin liseré cyan, coins droits).
func _hero_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.058824, 0.07451, 0.094118, 0.92)
	s.border_color = Color(ACCENT_CYAN, 0.55)
	s.set_border_width_all(1)
	s.set_corner_radius_all(0)
	s.set_content_margin_all(10)
	return s

# Panneau Héros du joueur local : ancré en haut-à-gauche, recapte les clics (mouse_filter STOP) pour
# ne pas les laisser traverser vers le plateau. Construit une fois ; alimenté par set_hero_panel().
func _build_hero_panel() -> void:
	_hero_panel = PanelContainer.new()
	_hero_panel.add_theme_stylebox_override("panel", _hero_panel_style())
	_hero_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_hero_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hero_panel.position = Vector2(18, 92)
	_hero_panel.custom_minimum_size = Vector2(230, 0)
	_hero_panel.visible = false

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_hero_panel.add_child(col)

	_hero_level_lbl = Label.new()
	_hero_level_lbl.add_theme_color_override("font_color", ACCENT_CYAN)
	_hero_level_lbl.add_theme_font_size_override("font_size", 16)
	col.add_child(_hero_level_lbl)

	_hero_pv_lbl = Label.new()
	_hero_pv_lbl.add_theme_color_override("font_color", Color("eef3f7"))
	_hero_pv_lbl.add_theme_font_size_override("font_size", 13)
	col.add_child(_hero_pv_lbl)

	_hero_pv_bar = ProgressBar.new()
	_hero_pv_bar.show_percentage = false
	_hero_pv_bar.custom_minimum_size = Vector2(0, 12)
	col.add_child(_hero_pv_bar)

	_hero_stats_lbl = Label.new()
	_hero_stats_lbl.add_theme_color_override("font_color", HERO_MUTED)
	_hero_stats_lbl.add_theme_font_size_override("font_size", 13)
	col.add_child(_hero_stats_lbl)

	_hero_pp_lbl = Label.new()
	_hero_pp_lbl.add_theme_color_override("font_color", ACCENT_GOLD)
	_hero_pp_lbl.add_theme_font_size_override("font_size", 13)
	col.add_child(_hero_pp_lbl)

	_hero_pp_bar = ProgressBar.new()
	_hero_pp_bar.show_percentage = false
	_hero_pp_bar.custom_minimum_size = Vector2(0, 8)
	col.add_child(_hero_pp_bar)

	# Barre de progression XP vers le niveau suivant (snapshot méta-jeu ; masquée au niveau max).
	_hero_xp_lbl = Label.new()
	_hero_xp_lbl.add_theme_color_override("font_color", HERO_MUTED)
	_hero_xp_lbl.add_theme_font_size_override("font_size", 11)
	col.add_child(_hero_xp_lbl)

	_hero_xp_bar = ProgressBar.new()
	_hero_xp_bar.show_percentage = false
	_hero_xp_bar.custom_minimum_size = Vector2(0, 6)
	col.add_child(_hero_xp_bar)

	add_child(_hero_panel)

# Alimente le panneau Héros du joueur local. `hero` = GameState.hero_of(local_id) (dict normalisé).
# Vide / non initialisé (pv_max=0) → panneau masqué (rétro-compat pré-RPG).
func set_hero_panel(hero: Dictionary) -> void:
	if _hero_panel == null:
		return
	var pv_max := int(hero.get("pv_max", 0))
	if hero.is_empty() or pv_max <= 0:
		_hero_panel.visible = false
		return
	_hero_panel.visible = true
	var pv := int(hero.get("pv_current", 0))
	var dead: bool = bool(hero.get("is_dead", false))
	_hero_level_lbl.text = (tr("HUD_HERO_EYEBROW") % int(hero.get("level", 1))) + ("  " + tr("HUD_HERO_DEAD") if dead else "")
	_hero_level_lbl.add_theme_color_override("font_color", HERO_DANGER if dead else ACCENT_CYAN)
	_hero_pv_lbl.text = tr("HUD_HERO_PV") % [pv, pv_max]
	_hero_pv_bar.max_value = float(pv_max)
	_hero_pv_bar.value = float(pv)
	_tint_progress(_hero_pv_bar, HERO_DANGER if (pv_max > 0 and float(pv) / float(pv_max) <= 0.3) else ACCENT_CYAN)
	_hero_stats_lbl.text = tr("HUD_HERO_ATK_DEF") % [int(hero.get("pa", 0)), int(round(float(hero.get("pb", 0.0)) * 100.0))]
	var pp := int(hero.get("pp_current", 0))
	# Indicateur de tendance ▲/▼ : compare au dernier PP affiché (le momentum monte/descend au combat).
	var trend := ""
	var trend_col := ACCENT_GOLD
	if _hero_pp_last != null and pp != int(_hero_pp_last):
		if pp > int(_hero_pp_last):
			trend = "  ▲"
			trend_col = ACCENT_CYAN
		else:
			trend = "  ▼"
			trend_col = HERO_DANGER
	_hero_pp_last = pp
	_hero_pp_lbl.text = (tr("HUD_HERO_PP") % [pp, int(hero.get("pp_min", 0)), int(hero.get("pp_max", 0))]) + trend
	_hero_pp_lbl.add_theme_color_override("font_color", trend_col)
	_hero_pp_bar.min_value = float(hero.get("pp_min", 0))
	_hero_pp_bar.max_value = float(hero.get("pp_max", 0))
	_hero_pp_bar.value = float(pp)
	# Barre d'XP vers le niveau suivant (statique pendant le match) ; masquée au niveau max (for<=0).
	var xp_for := int(hero.get("xp_for_level", 0))
	var xp_in := int(hero.get("xp_in_level", 0))
	if xp_for > 0:
		_hero_xp_lbl.visible = true
		_hero_xp_bar.visible = true
		_hero_xp_lbl.text = tr("HUD_HERO_XP") % [xp_in, xp_for]
		_hero_xp_bar.max_value = float(xp_for)
		_hero_xp_bar.value = float(clamp(xp_in, 0, xp_for))
		_tint_progress(_hero_xp_bar, ACCENT_GOLD)
	else:
		_hero_xp_lbl.visible = true
		_hero_xp_bar.visible = false
		_hero_xp_lbl.text = tr("CHAR_LEVEL_MAX")

func hide_hero_panel() -> void:
	if _hero_panel != null:
		_hero_panel.visible = false

# Douleur du héros (E9 §8.81) : pulse rouge 0,3 s sur le liseré de la fiche héros quand NOTRE
# héros encaisse. Piloté par main.gd (VFX gérés par le réglage reduced_motion E10, côté appelant).
func pulse_hero_pain() -> void:
	if _hero_panel == null or not _hero_panel.visible:
		return
	var painful := _hero_panel_style()
	painful.border_color = HERO_DANGER
	painful.set_border_width_all(3)
	_hero_panel.add_theme_stylebox_override("panel", painful)
	var tw := _hero_panel.create_tween()
	tw.tween_interval(0.3)
	tw.tween_callback(func() -> void:
		if _hero_panel != null and is_instance_valid(_hero_panel):
			_hero_panel.add_theme_stylebox_override("panel", _hero_panel_style()))

# Recolore le remplissage d'une ProgressBar (fill stylebox) à la couleur donnée.
func _tint_progress(bar: ProgressBar, col: Color) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(0)
	bar.add_theme_stylebox_override("fill", fill)

# Inspecteur d'ADVERSAIRE : panneau flottant (bas-gauche) montrant les stats du héros d'un autre
# joueur (PV/PA/PB/PP en cours), ouvert au clic sur un de ses territoires (main.gd). Fondu comme
# l'inspecteur de territoire. Stats PUBLIQUES (aucune redaction côté serveur).
func _build_player_inspector() -> void:
	_player_inspector = PanelContainer.new()
	_player_inspector.add_theme_stylebox_override("panel", _hero_panel_style())
	_player_inspector.mouse_filter = Control.MOUSE_FILTER_STOP
	_player_inspector.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_player_inspector.position = Vector2(18, -120)
	_player_inspector.custom_minimum_size = Vector2(230, 0)
	_player_inspector.visible = false

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_player_inspector.add_child(col)

	var eyebrow := Label.new()
	eyebrow.text = tr("HUD_ENEMY_HERO_EYEBROW")
	eyebrow.add_theme_color_override("font_color", HERO_MUTED)
	eyebrow.add_theme_font_size_override("font_size", 11)
	col.add_child(eyebrow)

	_pi_name = Label.new()
	_pi_name.add_theme_font_size_override("font_size", 16)
	col.add_child(_pi_name)

	_pi_stats = Label.new()
	_pi_stats.add_theme_color_override("font_color", Color("eef3f7"))
	_pi_stats.add_theme_font_size_override("font_size", 13)
	col.add_child(_pi_stats)

	add_child(_player_inspector)

# Affiche l'inspecteur adverse. data = { pseudo, color, hero (dict GameState.hero_of) }.
func set_player_inspector(data: Dictionary) -> void:
	if _player_inspector == null:
		return
	var hero: Dictionary = data.get("hero", {})
	if hero.is_empty() or int(hero.get("pv_max", 0)) <= 0:
		hide_player_inspector()
		return
	_pi_name.text = str(data.get("pseudo", "?")).to_upper() + ("  ☠" if bool(hero.get("is_dead", false)) else "")
	_pi_name.add_theme_color_override("font_color", data.get("color", Color.WHITE))
	_pi_stats.text = tr("HUD_ENEMY_HERO_STATS") % [
		int(hero.get("level", 1)), int(hero.get("pv_current", 0)), int(hero.get("pv_max", 0)),
		int(hero.get("pa", 0)), int(round(float(hero.get("pb", 0.0)) * 100.0)),
		int(hero.get("pp_current", 0))]
	if _pi_tween and _pi_tween.is_valid():
		_pi_tween.kill()
	if not _player_inspector.visible:
		_player_inspector.modulate.a = 0.0
		_player_inspector.visible = true
		_pi_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_pi_tween.tween_property(_player_inspector, "modulate:a", 1.0, 0.18)

func hide_player_inspector() -> void:
	if _player_inspector == null or not _player_inspector.visible:
		return
	if _pi_tween and _pi_tween.is_valid():
		_pi_tween.kill()
	_pi_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_pi_tween.tween_property(_player_inspector, "modulate:a", 0.0, 0.14)
	_pi_tween.tween_callback(func(): _player_inspector.visible = false)

# Construit (une fois) le gros bouton « CONFIRMER LE DÉPLOIEMENT » et l'insère dans la barre
# d'action du BottomCenterWidget, juste avant « Fin de Phase ». Masqué par défaut ; piloté par
# set_deploy_confirm (§8.26). L'insertion reste relative à %NextPhaseButton (robuste au re-layout).
func _build_confirm_button() -> void:
	_confirm_btn = Button.new()
	_confirm_btn.text = tr("HUD_DEPLOY_CONFIRM")
	_confirm_btn.visible = false
	_confirm_btn.add_theme_font_size_override("font_size", 18)
	_confirm_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Bouton « Ghost » (charte « Warzone Command » §2/§8.37) : fond quasi transparent, fin liseré cyan,
	# texte crème qui s'ILLUMINE en cyan tactique au survol (font_hover_color).
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.07, 0.35)
	style.border_color = Color(ACCENT_CYAN, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
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
#   active=false → bouton masqué (hors phase de placement/renforts ou rien à placer).
#   active=true  → bouton visible, ACTIVÉ seulement si total == quota (toutes les troupes posées).
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
# Journal de Guerre 2.0 (E4 §8.76) — flux structuré, filtres, kill feed, toasts
# =========================================================

# Journal militaire (panneau latéral). LEGACY conservé : tout texte brut devient une entrée
# `system` du flux structuré (filtrable comme le reste — AUCUNE perte d'info).
func add_log(text: String, icon_path: String = "") -> void:
	var rich := text
	if icon_path != "":
		rich = "[img=18]%s[/img] %s" % [icon_path, text]
	add_feed_entries([{"category": "system", "icon": "⚙", "rich_text": rich,
		"tid": "", "major": false}])

# Ajoute des entrées structurées (war_feed.parse — E4) au flux : numérotation à l'AJOUT (stable
# à travers les filtres), rendu incrémental si l'entrée passe le filtre courant, plafond FEED_MAX.
func add_feed_entries(entries: Array) -> void:
	for e in entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		_log_count += 1
		e["_num"] = _log_count
		_feed_entries.append(e)
		if _feed_entries.size() > FEED_MAX:
			_feed_entries.pop_front()
		if _feed_matches(e):
			%LogText.append_text(_feed_line(e) + "\n")

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

# Rangée de chips de filtre TOUS / ⚔ / ☢ / 🃏 / ⚙ (ButtonGroup — pattern %ChatIconBar §8.29),
# insérée juste AU-DESSUS de %LogText (insertion relative, piège n° 6).
func _build_feed_filters() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var group := ButtonGroup.new()
	var defs := [["all", "TOUS"], ["combat", "⚔"], ["zone", "☢"], ["cards", "❖"], ["system", "⚙"]]
	for d in defs:
		var b := Button.new()
		b.text = str(d[1])
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = str(d[0]) == "all"
		b.custom_minimum_size = Vector2(38, 26)
		b.add_theme_font_size_override("font_size", 13)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.tooltip_text = tr("FEED_FILTER_TOOLTIP")
		var key := str(d[0])
		b.pressed.connect(func() -> void:
			_feed_filter = key
			AudioManager.play_sfx("click")
			_rerender_feed())
		row.add_child(b)
	var parent := %LogText.get_parent()
	parent.add_child(row)
	parent.move_child(row, %LogText.get_index())

# Kill feed (E4) : instancié coin haut-droit, À GAUCHE du panneau latéral (320 px) — hors panneaux.
func _build_kill_feed() -> void:
	_kill_feed = KillFeedScene.instantiate()
	add_child(_kill_feed)
	_kill_feed.anchor_left = 1.0
	_kill_feed.anchor_right = 1.0
	_kill_feed.offset_left = -652.0
	_kill_feed.offset_right = -332.0
	_kill_feed.offset_top = 72.0
	_kill_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_kill_feed.grow_vertical = Control.GROW_DIRECTION_END

func push_kill_feed(rich_text: String) -> void:
	if _kill_feed != null and is_instance_valid(_kill_feed):
		_kill_feed.push_entry(rich_text)

# Toast défensif (E4) : « ⚠ ONTARIO ATTAQUÉ PAR X — pertes : N » quand un territoire à NOUS est
# frappé pendant le tour d'un AUTRE. Panneau furtif haut-centre (sous le bandeau E3), liseré
# rouge — le plus récent REMPLACE l'ancien (jamais d'empilement).
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
		rtl.add_theme_font_size_override("normal_font_size", 16)
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
# add_chat_message. Ex. : hud.add_log("%s attaque" % hud.color_pseudo(nom, accent)).
func color_pseudo(pseudo: String, accent: Color) -> String:
	return "[color=#%s]%s[/color]" % [accent.to_html(false), pseudo]

# =========================================================
# Roster de Guerre (E1 §8.73) — panneau permanent des belligérants
# =========================================================
# Instancié PAR CODE en tête du SideVBox (au-dessus des comms/chat) — insertion RELATIVE dans le
# conteneur existant, aucune retouche de main.tscn (piège n° 6 PLAN_EXPERIENCE, pattern
# _build_confirm_button). Le clic d'une ligne REMONTE au contrôleur via roster_player_clicked.
func _build_war_roster() -> void:
	_war_roster = WarRosterScene.instantiate()
	var side_vbox := %ChatTabs.get_parent()
	side_vbox.add_child(_war_roster)
	side_vbox.move_child(_war_roster, 0)
	_war_roster.player_clicked.connect(
		func(pid: int) -> void: roster_player_clicked.emit(pid))

# Chat à onglets-icônes. channel ∈ {"general", "prive"} ; text accepte le BBCode (déjà échappé
# côté main.gd pour le texte des joueurs — anti-injection BBCode, §8.33).
func add_chat_message(channel: String, text: String) -> void:
	var rtl: RichTextLabel = _chat_channels.get(channel)
	if rtl:
		rtl.append_text(text + "\n")

func update_display() -> void:
	var stage := str(GameState.stage)

	# Remise à zéro du rebours quand le tour, le joueur actif OU la PHASE change (§8.31, révisé) : le
	# serveur repart le timer à CHAQUE « Fin de Phase » → on en fait le miroir local. Le rebours ET la
	# Time Bank accumulée sont propres à UNE phase → on purge les deux à chaque nouvelle signature.
	var key := "%s|%s|%s|%s" % [
		stage, str(GameState.current_turn), str(GameState.current_player_id), str(GameState.current_phase)]
	if key != _turn_key:
		_turn_key = key
		_elapsed = 0.0
		_turn_bonus = 0.0

	# Chrono SERVEUR prioritaire (E3 §8.75) : un état portant server_time vient d'un serveur qui
	# diffuse son échéance — turn_timer null = AUCUN rebours à afficher (tour de bot / hors
	# minuterie). Sans server_time (VPS pas encore redéployé), REPLI legacy : estimation locale
	# historique ci-dessous, intacte (client défensif §9.2).
	if GameState.server_time > 0.0:
		if GameState.turn_timer.is_empty():
			clear_server_timer()
			_turn_limit = 0.0
		else:
			apply_server_timer(float(GameState.turn_timer.get("deadline_epoch", 0.0)),
				GameState.server_time)
	else:
		clear_server_timer()
		# Durée du rebours (§8.31, révisé) : 90 s en Phase 0 (placement) ; en jeu, budget PAR PHASE
		# via _phase_turn_limit() (90 s en Attaque + Time Bank jusqu'à 180 s, 60 s sinon) ; sinon
		# caché. On RECALCULE depuis _turn_bonus pour que le bonus crédité SURVIVE au refresh.
		match stage:
			"placement": _turn_limit = PHASE0_TIME
			"playing": _turn_limit = _phase_turn_limit()
			_: _turn_limit = 0.0

	if stage == "playing":
		%PhaseLabel.text = tr("BANNER_PHASE") % _phase_name(GameState.current_phase).to_upper()
	else:
		%PhaseLabel.text = tr("HUD_STAGE_FMT") % _stage_name(stage).to_upper()

	var pdata: Dictionary = GameState.players.get(str(GameState.current_player_id), {})
	# Le serveur diffuse désormais le VRAI pseudo dans chaque PlayerState (§8.28) : on l'affiche
	# pour TOUS les joueurs (plus seulement le nôtre), avec repli sur le numéro séquentiel 1..N
	# si l'identité n'a pas pu être résolue côté serveur.
	var uname := str(pdata.get("username", ""))
	if uname == "":
		uname = tr("HUD_PLAYER_NUM") % GameState.player_number(GameState.current_player_id)
	# Bot de remplissage (G2 §8.72) : préfixe « [IA] » (id négatif ou is_bot public).
	if int(GameState.current_player_id) < 0 or bool(pdata.get("is_bot", false)):
		uname = tr("COMMON_AI_PREFIX") + uname
	# Nom de faction AFFICHABLE (EN invariant, poussé par main.gd via faction_name_by_pid) —
	# repli sur l'id brut si la résolution n'est pas encore arrivée.
	var fac_disp := str(faction_name_by_pid.get(str(GameState.current_player_id),
		pdata.get("faction", "?")))
	var who := "%s (%s)" % [uname, fac_disp]
	%InfoLabel.text = tr("HUD_TURN_INFO_FMT") % [
		str(GameState.current_turn), who, str(pdata.get("units_in_stock", 0))]

	# Objectif secret du joueur local — COMPOSÉ localement en langue courante depuis type/params
	# (i18n 2026-07-18) ; repli sur la description serveur (type inconnu) puis « (secret) ».
	var obj: Dictionary = GameState.objectives.get(str(AuthManager.user_id), {})
	var obj_txt := ObjectiveTrackerModule.describe(obj, _objective_target_pseudo(obj))
	if obj_txt == "":
		obj_txt = tr("HUD_OBJECTIVE_SECRET")
	%ObjectiveLabel.text = tr("HUD_OBJECTIVE_FMT") % obj_txt

	_refresh_cards()

	# Roster de Guerre (E1 §8.73) : rafraîchi à chaque état reçu — AUCUN nouveau flux réseau
	# (update_display est déjà invoqué par main._refresh() à chaque game_state_updated).
	if _war_roster != null and is_instance_valid(_war_roster):
		_war_roster.refresh()

# =========================================================
# Onglets de chat par ICÔNES (§8.29)
# =========================================================
# La barre %ChatIconBar (3 boutons-icônes en ButtonGroup) pilote le TabContainer %ChatTabs dont la
# barre d'onglets native est masquée (tabs_visible=false). Les 3 RichTextLabels restent les pages
# du TabContainer → add_chat_message / _chat_channels inchangés (mapping par get_node).
func _setup_chat_tabs() -> void:
	# 2 canaux seulement : l'onglet « Alliés » est abandonné (chacun-pour-soi, §8.33).
	_chat_channels = {
		"general": %ChatTabs.get_node("GÉNÉRAL"),
		"prive": %ChatTabs.get_node("PRIVÉ"),
	}
	%TabBtnGeneral.pressed.connect(_select_chat.bind("general"))
	%TabBtnPrive.pressed.connect(_select_chat.bind("prive"))
	_select_chat("general")

func _select_chat(channel: String) -> void:
	_current_chat_tab = channel
	%ChatTabs.current_tab = int(CHAT_INDEX.get(channel, 0))
	# Le sélecteur de destinataire n'a de sens qu'en canal PRIVÉ (target_id requis, §8.33).
	if _chat_target_option:
		_chat_target_option.visible = (channel == "prive")
	if _chat_input:
		_chat_input.placeholder_text = tr("HUD_CHAT_PLACEHOLDER_PRIVATE") if channel == "prive" else tr("HUD_CHAT_PLACEHOLDER_GENERAL")

# =========================================================
# Zone de saisie du chat (§8.33) — LineEdit + sélecteur de destinataire privé + bouton d'envoi
# =========================================================
# Construite par code (comme « CONFIRMER LE DÉPLOIEMENT ») et insérée dans le SideVBox juste sous le
# TabContainer du chat. Le HUD reste une VIEW pure (Règle d'Or §6.1) : l'envoi remonte à main.gd via
# le signal chat_send_requested ; aucun accès réseau ici. La liste des destinataires privés est
# poussée par main.gd (set_chat_targets) — les pseudos/ids sont résolus côté contrôleur.
func _build_chat_input() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	_chat_target_option = OptionButton.new()
	_chat_target_option.visible = false  # affiché uniquement en canal privé
	_chat_target_option.tooltip_text = tr("HUD_CHAT_TARGET_TOOLTIP")
	_chat_target_option.add_theme_font_size_override("font_size", 13)
	_chat_target_option.custom_minimum_size = Vector2(96, 0)
	row.add_child(_chat_target_option)

	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = tr("HUD_CHAT_PLACEHOLDER_GENERAL")
	_chat_input.max_length = CHAT_MAX_LENGTH
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.add_theme_font_size_override("font_size", 14)
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
	_chat_send_btn.custom_minimum_size = Vector2(36, 0)
	_chat_send_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_chat_send_btn.add_theme_font_size_override("font_size", 16)
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

	# Insertion dans le SideVBox, juste APRÈS le TabContainer du chat (avant le Journal Militaire).
	var side_vbox := %ChatTabs.get_parent()
	side_vbox.add_child(row)
	side_vbox.move_child(row, %ChatTabs.get_index() + 1)

# Envoi : valide le texte (non vide), résout le destinataire en privé, émet le signal et vide le
# champ. On NE colle PAS le message localement : le serveur renvoie un écho (§8.33) qui l'affichera.
func _on_chat_submit() -> void:
	if _chat_input == null:
		return
	var text := _chat_input.text.strip_edges()
	if text == "":
		return
	var target_id := -1
	if _current_chat_tab == "prive":
		if _chat_target_option == null or _chat_target_option.item_count == 0:
			add_chat_message("prive", tr("HUD_CHAT_NO_TARGET"))
			return
		target_id = _chat_target_option.get_selected_id()
	_chat_input.clear()
	chat_send_requested.emit(_current_chat_tab, text, target_id)

# Met à jour la liste des destinataires privés (§8.33). entries = Array[{ "id": int, "name": String }]
# (autres joueurs, déjà résolus par main.gd). On conserve la sélection courante si elle existe encore.
func set_chat_targets(entries: Array) -> void:
	if _chat_target_option == null:
		return
	var previous := _chat_target_option.get_selected_id() if _chat_target_option.item_count > 0 else -1
	_chat_target_option.clear()
	for e in entries:
		var pid := int(e.get("id", -1))
		if pid < 0:
			continue
		_chat_target_option.add_item(str(e.get("name", "?")))
		_chat_target_option.set_item_id(_chat_target_option.item_count - 1, pid)
	# Restaure la sélection précédente si le joueur est toujours présent.
	if previous >= 0:
		for i in range(_chat_target_option.item_count):
			if _chat_target_option.get_item_id(i) == previous:
				_chat_target_option.select(i)
				break

# =========================================================
# Bandeau de combat compact (E8 §8.80) — combats où je ne suis pas impliqué
# =========================================================
# data = { atk_pid, def_pid, atk_rolls, def_rolls, atk_losses, def_losses, hero_damage,
#          hero_died, conquered }. Panneau haut-centre 2,2 s (piloté par main.gd, la durée
# d'attente vit côté contrôleur — file _combat_animating). Chips E1 + dés figés + pertes.
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
	vs.add_theme_font_size_override("font_size", 16)
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
	summary.add_theme_font_size_override("font_size", 14)
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
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", col)
	return lbl

# =========================================================
# Panneau latéral rétractable (§8.29) — slide horizontal (Tween natif)
# =========================================================

# Mémorise (une fois, après le 1ᵉʳ layout) la position « déployée » et la largeur du panneau.
# Différé au 1ᵉʳ clic : au _ready les tailles ne sont pas encore résolues par les conteneurs.
func _cache_side_metrics() -> void:
	if _side_metrics_ready:
		return
	var panel: Control = %ToggleSidePanelButton.get_parent()  # SidePanelWidget (Control)
	_side_shown_x = panel.position.x
	_side_width = panel.size.x
	_side_metrics_ready = true

# Replie / déploie le panneau : Tween de SINE/EASE_OUT sur position.x (slide in/out). Le bouton
# de bascule protubère à gauche du panneau → il reste visible au bord de l'écran même replié.
func _toggle_side_panel() -> void:
	var panel: Control = %ToggleSidePanelButton.get_parent()
	_cache_side_metrics()
	_side_hidden = not _side_hidden
	var target_x := _side_shown_x + (_side_width if _side_hidden else 0.0)
	%ToggleSidePanelButton.text = "◀" if _side_hidden else "▶"
	if _side_tween and _side_tween.is_valid():
		_side_tween.kill()
	_side_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_side_tween.tween_property(panel, "position:x", target_x, SIDE_SLIDE_TIME)

# =========================================================
# Panneau inférieur rétractable (§3) — slide vertical (Tween natif)
# =========================================================

# Replie (vers le BAS) / déploie le panneau inférieur (cartes, objectif, actions). On mémorise la
# position déployée juste AVANT un repli (robuste si la hauteur du panneau a changé), puis on glisse
# de la hauteur du corps vitré → seul le bouton de bascule reste visible au bord bas de l'écran. Le
# wrapper est un VBoxContainer enfant du HUD (Control) : sa propre position se tween librement (comme
# le panneau latéral), seule la disposition de SES enfants est gérée par le conteneur.
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
# Fond le HUD racine (modulate.a 1→0 si caché, 0→1 sinon) sur 0,5 s pour ne pas parasiter
# l'affrontement des héros. main.gd instancie la scène VS HORS du HUD (enfant de Main) → seul
# le HUD s'efface, jamais le duel.
func fade_ui_for_combat(is_hidden: bool) -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	if not is_hidden:
		visible = true  # ré-affiché avant de remonter l'alpha (au cas où masqué à 0)
	var target := 0.0 if is_hidden else 1.0
	_fade_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fade_tween.tween_property(self, "modulate:a", target, COMBAT_FADE_TIME)

# =========================================================
# Inventaire de cartes (BottomCenterWidget)
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
	# Main TOUJOURS INSPECTABLE, jouable UNIQUEMENT pendant SON tour de jeu (G3 §8.70 explicité) :
	# hors tour (ou éliminé — jamais joueur courant), les vignettes restent visibles mais
	# DÉSACTIVÉES (lecture seule) au lieu de laisser le serveur refuser le clic.
	var playable := GameState.stage == "playing" \
		and int(GameState.current_player_id) == int(AuthManager.user_id) \
		and str(my.get("status", "alive")) == "alive"
	# Chaque carte est un entier de troupes : on l'affiche comme un bouton « +N ».
	# Le piège JSON (§5) convertit les nombres en float → on repasse en int() pour l'affichage.
	for i in range(hand.size()):
		box.add_child(_make_card_button(int(hand[i]), i, playable))

# Vignette de carte stylisée : un bouton « +N » (valeur en gros). Clic = card_played(index).
# `playable` = false (hors tour / éliminé) → vignette VISIBLE mais désactivée (lecture seule).
func _make_card_button(value: int, index: int, playable: bool = true) -> Control:
	var card := Button.new()
	card.text = "+%d" % value
	card.custom_minimum_size = Vector2(80, 60)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.disabled = not playable
	card.tooltip_text = (tr("HUD_CARD_PLAY_TOOLTIP") % value) if playable \
		else (tr("HUD_CARD_LOCKED_TOOLTIP") % value)
	card.add_theme_font_size_override("font_size", 28)
	card.add_theme_color_override("font_color", Color("f0e6d2"))

	# Fond teinté militaire (StyleBoxFlat construit par code, comme le reste du HUD).
	var style := StyleBoxFlat.new()
	style.bg_color = Color("121212").lerp(CARD_TINT, 0.3)
	style.border_color = CARD_TINT.lightened(0.15)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
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

# Libellé TRADUIT d'une étape macro de la partie ("initiative" / "placement" — i18n 2026-07-18 :
# l'étape brute du serveur n'est plus affichée telle quelle).
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
