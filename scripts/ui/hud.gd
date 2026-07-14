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

# Tiroir « INTEL : ZONE » (§8.36) — état ouvert/fermé + Tween de fondu du panneau (Mémoire Tactique).
var _intel_open := false
var _intel_tween: Tween
# Télégraphe de zone (G1 §8.62) : ligne d'état PERMANENTE « ☢ PROCHAINE ZONE : … » (or), créée
# par code sous l'objectif secret (BottomVBox) — pattern _build_confirm_button (pas de retouche .tscn).
var _forecast_label: Label = null
# Prévision de combat (G4 §8.63) : ligne « PRÉVISION : victoire NN % … » créée par code sous
# l'instruction (TopCenterWidget), visible uniquement au survol d'une cible valide en Phase 3.
var _odds_label: Label = null
# Tiroir « INTEL : FACTIONS » (§2) — état ouvert/fermé + Tween de fondu (miroir du tiroir Zone).
var _factions_intel_open := false
var _factions_intel_tween: Tween
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
	# Chat de salle CÂBLÉ au réseau (§8.33) : main.gd relaie chat_send_requested -> NetworkManager
	# et route les messages reçus vers add_chat_message. 2 canaux (Général / Privé).
	add_chat_message("general", "[i]— Canal général ouvert. —[/i]")
	add_chat_message("prive", "[i]— Aucune transmission privée. —[/i]")

# Compte à rebours du tour courant, affiché MM:SS. Le serveur ne transmet pas d'échéance (§8.31) :
# on décompte localement depuis _turn_limit (90 s Phase 0 / 60 s tour), remis à zéro au changement
# de tour par update_display(). _turn_limit == 0 → hors tour minuté → "--:--".
func _process(delta: float) -> void:
	if _turn_limit <= 0.0:
		if _timer_urgent:
			_timer_urgent = false
			%TimerLabel.add_theme_color_override("font_color", TIMER_COLOR)
		%TimerLabel.text = "--:--"
		return
	_elapsed += delta
	var remaining := int(ceil(maxf(0.0, _turn_limit - _elapsed)))
	%TimerLabel.text = "%02d:%02d" % [floori(remaining / 60.0), remaining % 60]
	# Bascule en rouge dans les dernières secondes (urgence), une seule fois au franchissement.
	var urgent := remaining <= TIMER_URGENT_SECONDS
	if urgent != _timer_urgent:
		_timer_urgent = urgent
		%TimerLabel.add_theme_color_override(
			"font_color", TIMER_URGENT_COLOR if urgent else TIMER_COLOR)

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
	%AbandonButton.text = "⚠ CONFIRMER ?"
	get_tree().create_timer(ABANDON_ARM_TIMEOUT).timeout.connect(_disarm_abandon)

func _disarm_abandon() -> void:
	# Le timer d'armement peut se déclencher APRÈS la confirmation serveur : on ne
	# réécrit pas le libellé d'un bouton déjà verrouillé par lock_abandon_button().
	if %AbandonButton.disabled:
		return
	_abandon_armed = false
	%AbandonButton.text = "☠ ABANDONNER"

# Verrouille définitivement le bouton une fois l'abandon CONFIRMÉ par le serveur
# (message player_abandoned nous concernant, relayé par main.gd) : évite un 2e envoi,
# que le backend rejetterait (« Vous avez déjà abandonné la partie »).
func lock_abandon_button() -> void:
	_abandon_armed = false
	%AbandonButton.text = "🏳️ ABANDONNÉ"
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
	_odds_label.text = "PRÉVISION : victoire %d %% · pertes est. %s   (hors pouvoirs à états)" % [pct, losses_txt]
	_odds_label.add_theme_color_override("font_color", col)
	_odds_label.visible = true

func hide_forecast() -> void:
	if _odds_label != null and is_instance_valid(_odds_label):
		_odds_label.visible = false

# Active/désactive le bouton « Fin de Phase » (verrou anti double-envoi piloté par main.gd, §8.48).
func set_pass_enabled(enabled: bool) -> void:
	%NextPhaseButton.disabled = not enabled

# Identité du joueur LOCAL (pseudo + couleur de faction) — appelée par main.gd à chaque refresh.
# Colore le pseudo dans la TopBar avec la couleur de la faction du joueur (charte §8.23).
func set_local_identity(pseudo: String, color: Color) -> void:
	_local_pseudo = pseudo
	_local_color = color
	%IdentityLabel.text = "👤 " + (pseudo if pseudo != "" else "—")
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
	%FactionTooltipDesc.text = _faction_desc if _faction_desc != "" else "Aucun modificateur."
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
	%IntelToggleButton.text = "🛰 INTEL : ZONE ▾" if _intel_open else "🛰 INTEL : ZONE ▸"
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
		%StagnationLabel.text = "STAGNATION : %d round(s) sans déplacement de zone" % stagnation
	else:
		%StagnationLabel.text = "STAGNATION : zone instable (déplacement récent)"
	var list: VBoxContainer = %ZoneKillsList
	for child in list.get_children():
		child.queue_free()
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "— Aucune perte enregistrée —"
		empty.add_theme_color_override("font_color", Color("8a8f7a"))
		empty.add_theme_font_size_override("font_size", 13)
		list.add_child(empty)
		return
	for e in entries:
		var row := Label.new()
		row.text = "☠ %s — %d unité(s)" % [str(e.get("pseudo", "?")), int(e.get("kills", 0))]
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

# Alimente la ligne du télégraphe. `names` = noms lisibles des territoires annoncés (Array[String],
# résolus par main.gd). Vide → mention neutre (serveur antérieur au télégraphe / partie non lancée).
func set_zone_forecast(names: Array) -> void:
	_ensure_forecast_label()
	if names.is_empty():
		_forecast_label.text = "☢ PROCHAINE ZONE : (non annoncée)"
	else:
		var joined := ", ".join(PackedStringArray(names))
		_forecast_label.text = "☢ PROCHAINE ZONE : " + joined


# =========================================================
# Tiroir « INTEL : FACTIONS » (§2) — pouvoirs passifs des factions adverses
# =========================================================
# Pendant du tiroir Zone : main.gd résout pseudo + faction + pouvoir + couleur et pousse une liste
# prête à afficher (Règle d'Or §6.1). Aucun accès réseau/état ici.

# Déploie / replie le panneau Factions (fondu Tween natif, cohérent avec le tiroir Zone).
func _toggle_factions_intel() -> void:
	_factions_intel_open = not _factions_intel_open
	%IntelFactionsToggleButton.text = "🛰 INTEL : FACTIONS ▾" if _factions_intel_open else "🛰 INTEL : FACTIONS ▸"
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
		empty.text = "— Aucune faction détectée —"
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
# Inspecteur Tactique de Territoire (§1) — lecteur flottant bas-droite
# =========================================================
# Ouvert au clic d'un territoire (main.gd résout les données, le HUD reste une View). data =
# { name, owner_name, owner_color: Color, troops: int, contaminated: bool }.

func set_territory_inspector(data: Dictionary) -> void:
	%InspectorName.text = str(data.get("name", "—")).to_upper()
	var owner_col: Color = data.get("owner_color", Color("8a97a5"))
	%InspectorOwner.text = str(data.get("owner_name", "—"))
	%InspectorOwner.add_theme_color_override("font_color", owner_col)
	%InspectorTroops.text = str(int(data.get("troops", 0)))
	%InspectorStatus.text = "☢ CONTAMINÉ" if bool(data.get("contaminated", false)) else ""
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
	_confirm_btn.text = "✔ CONFIRMER LE DÉPLOIEMENT"
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
	_confirm_btn.text = "✔ CONFIRMER (%d/%d)" % [total, quota]

# Journal militaire (panneau latéral) : historique horodaté des conquêtes / évènements.
# Le RichTextLabel accepte le BBCode avancé (§8.29) : on peut préfixer une icône via [img] et le
# texte peut contenir des pseudos colorés à l'accent_color du joueur (voir color_pseudo()).
func add_log(text: String, icon_path: String = "") -> void:
	_log_count += 1
	var prefix := "[color=#8a8f7a][%03d][/color] " % _log_count
	if icon_path != "":
		prefix += "[img=18]%s[/img] " % icon_path
	%LogText.append_text(prefix + text + "\n")

# Renvoie un pseudo colorisé à l'accent_color du joueur (BBCode), à embarquer dans add_log /
# add_chat_message. Ex. : hud.add_log("%s attaque" % hud.color_pseudo(nom, accent)).
func color_pseudo(pseudo: String, accent: Color) -> String:
	return "[color=#%s]%s[/color]" % [accent.to_html(false), pseudo]

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

	# Durée du rebours (§8.31, révisé) : 90 s en Phase 0 (placement) ; en jeu, budget PAR PHASE via
	# _phase_turn_limit() (90 s en Attaque + Time Bank jusqu'à 180 s, 60 s sinon) ; sinon caché. On
	# RECALCULE depuis _turn_bonus (et non une valeur figée) pour que le bonus crédité SURVIVE au refresh.
	match stage:
		"placement": _turn_limit = PHASE0_TIME
		"playing": _turn_limit = _phase_turn_limit()
		_: _turn_limit = 0.0

	if stage == "playing":
		%PhaseLabel.text = "PHASE : " + _phase_name(GameState.current_phase).to_upper()
	else:
		%PhaseLabel.text = "ÉTAPE : " + stage.to_upper()

	var pdata: Dictionary = GameState.players.get(str(GameState.current_player_id), {})
	# Le serveur diffuse désormais le VRAI pseudo dans chaque PlayerState (§8.28) : on l'affiche
	# pour TOUS les joueurs (plus seulement le nôtre), avec repli sur le numéro séquentiel 1..N
	# si l'identité n'a pas pu être résolue côté serveur.
	var uname := str(pdata.get("username", ""))
	if uname == "":
		uname = "JOUEUR %d" % GameState.player_number(GameState.current_player_id)
	# Bot de remplissage (G2 §8.72) : préfixe « [IA] » (id négatif ou is_bot public).
	if int(GameState.current_player_id) < 0 or bool(pdata.get("is_bot", false)):
		uname = "[IA] " + uname
	var who := "%s (%s)" % [uname, str(pdata.get("faction", "?"))]
	%InfoLabel.text = "TOUR %s ▪ %s ▪ STOCK : %s" % [
		str(GameState.current_turn), who, str(pdata.get("units_in_stock", 0))]

	# Objectif secret du joueur local.
	var obj: Dictionary = GameState.objectives.get(str(AuthManager.user_id), {})
	%ObjectiveLabel.text = "🎯 OBJECTIF : " + str(obj.get("description", "(secret)"))

	_refresh_cards()

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
		_chat_input.placeholder_text = "Message privé…" if channel == "prive" else "Message général…"

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
	_chat_target_option.tooltip_text = "Destinataire du message privé"
	_chat_target_option.add_theme_font_size_override("font_size", 13)
	_chat_target_option.custom_minimum_size = Vector2(96, 0)
	row.add_child(_chat_target_option)

	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Message général…"
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
	_chat_send_btn.tooltip_text = "Envoyer"
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
			add_chat_message("prive", "[i][color=#d6453f]— Aucun destinataire disponible. —[/color][/i]")
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
		lbl.text = "— Aucune carte en stock —"
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
	card.tooltip_text = ("Jouer cette carte : +%d troupes à déployer." % value) if playable \
		else ("+%d troupes — jouable pendant votre tour." % value)
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

func _phase_name(phase: int) -> String:
	match phase:
		0: return "Contamination"
		1: return "Renforts"
		2: return "Déploiement"
		3: return "Attaque"
		4: return "Mouvement"
		5: return "Évènement"
		_: return "Phase " + str(phase)
