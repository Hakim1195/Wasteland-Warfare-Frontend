extends Control

# RAPPORT POST-OPÉRATION (§4 Warzone Command) — débriefing after-action affiché en fin de partie.
# Fond = flou gaussien de l'arène gelée (report_blur.gdshader) + assombrissement gunmetal ; grand
# panneau central angulaire : titre massif, « Rapport d'Attrition » (depuis GameState.statistics,
# résolu par main.gd), et CTA « RETOURNER AU LOBBY ». View PURE (Règle d'Or §6.1) : aucune logique
# de jeu / réseau ici — main.gd pousse les données (populate) et gère la navigation (back_to_lobby).

signal back_to_lobby
# Re-queue en 1 clic (G3 §8.70) : « REJOUER » depuis le débriefing — bénéficie à TOUS les joueurs
# en fin de partie, pas qu'aux éliminés. main.gd relaie vers NetworkManager.requeue().
signal requeue_requested

const ACCENT_CYAN := Color("36c5d9")
const ACCENT_GOLD := Color("e0b249")
const TEXT_MUTED := Color("8a97a5")

# Jauge XP + Coins réutilisable (§8.47) — instanciée par code dans le bloc « Récompenses » (animé).
const XpCoinsBarScript = preload("res://scripts/ui/xp_coins_bar.gd")

# Garde anti double-construction : les récompenses peuvent arriver via populate(data.rewards) OU,
# en cas de course (game_over reçu APRÈS l'affichage du rapport), via populate_rewards() (main.gd).
var _rewards_built := false

func _ready() -> void:
	%BackToLobbyButton.pressed.connect(func(): back_to_lobby.emit())
	# SFX d'interface (survol/retour — R6).
	%BackToLobbyButton.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	%BackToLobbyButton.pressed.connect(func() -> void: AudioManager.play_sfx("back"))
	_build_requeue_button()

# Bouton « ⟳ REJOUER » (G3 §8.70), construit par code À CÔTÉ du retour lobby (aucune retouche
# .tscn) : or (CTA de relance), anti double-clic, émet requeue_requested (main.gd décide).
func _build_requeue_button() -> void:
	var anchor: Button = %BackToLobbyButton
	var parent := anchor.get_parent()
	var btn := Button.new()
	btn.name = "RequeueButton"
	btn.text = tr("REPORT_REQUEUE")
	btn.custom_minimum_size = anchor.custom_minimum_size
	btn.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.bg_color = Color(ACCENT_GOLD, 0.14)
	sb.set_border_width_all(2)
	sb.border_color = ACCENT_GOLD
	sb.set_content_margin_all(10)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(ACCENT_GOLD, 0.30)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", sb)
	btn.add_theme_color_override("font_color", ACCENT_GOLD)
	btn.add_theme_color_override("font_hover_color", Color("eef3f7"))
	btn.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	btn.pressed.connect(func() -> void:
		AudioManager.play_sfx("confirm")
		btn.disabled = true
		requeue_requested.emit())
	parent.add_child(btn)
	parent.move_child(btn, anchor.get_index())

# Remplit le rapport. data = {
#   title: String, title_color: Color, stagnation: int,
#   attrition: Array[{ pseudo: String, color: Color, losses: int }] (triée desc.),
#   worst_pseudo: String,
#   rewards: Dictionary (FACULTATIF) — gains du joueur local (game_over.match_rewards[my_id], §8.47) }
func populate(data: Dictionary) -> void:
	%ReportTitle.text = str(data.get("title", "OPÉRATION TERMINÉE")).to_upper()
	%ReportTitle.add_theme_color_override("font_color", data.get("title_color", ACCENT_GOLD))

	var stag := int(data.get("stagnation", 0))
	if stag > 0:
		%StagnationReport.text = "☢ La zone radioactive a stagné %d round(s) sans se déplacer." % stag
	else:
		%StagnationReport.text = "☢ Zone radioactive instable jusqu'au bout (déplacements fréquents)."

	var list: VBoxContainer = %AttritionList
	for child in list.get_children():
		child.queue_free()
	var attrition: Array = data.get("attrition", [])
	var worst := str(data.get("worst_pseudo", ""))
	if attrition.is_empty():
		var none := Label.new()
		none.text = "— Aucune perte enregistrée dans la zone —"
		none.add_theme_color_override("font_color", TEXT_MUTED)
		none.add_theme_font_size_override("font_size", 15)
		list.add_child(none)
	else:
		for e in attrition:
			var pseudo := str(e.get("pseudo", "?"))
			var is_worst: bool = pseudo == worst
			var row := Label.new()
			var prefix := "🥇 PLUS LOURD TRIBUT : " if is_worst else "❯ "
			row.text = "%s%s — %d unité(s) perdues dans la zone" % [prefix, pseudo, int(e.get("losses", 0))]
			row.add_theme_color_override("font_color", ACCENT_GOLD if is_worst else e.get("color", Color.WHITE))
			row.add_theme_font_size_override("font_size", 17 if is_worst else 15)
			list.add_child(row)

	# Bloc « Récompenses » animé (si les gains du joueur local sont déjà connus à l'affichage).
	var rewards: Dictionary = data.get("rewards", {})
	if not rewards.is_empty():
		populate_rewards(rewards)

# =========================================================
# Bloc « Récompenses » (§8.47) — décompte des points + barre d'XP qui se remplit + lueur Coins
# =========================================================
# Appelable séparément par main.gd quand le message game_over (porteur de match_rewards) arrive APRÈS
# la construction du rapport (course réseau : l'état winner_id et le game_over sont 2 messages). La
# garde _rewards_built évite tout doublon. `rewards` = match_rewards[player_id_local].
func populate_rewards(rewards: Dictionary) -> void:
	if _rewards_built or rewards.is_empty():
		return
	_rewards_built = true
	_build_and_animate_rewards(rewards)

func _build_and_animate_rewards(rewards: Dictionary) -> void:
	var list: VBoxContainer = %AttritionList

	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 6)

	var header := Label.new()
	header.text = "▌ RÉCOMPENSES DE FIN D'OPÉRATION"
	header.add_theme_color_override("font_color", ACCENT_CYAN)
	header.add_theme_font_size_override("font_size", 18)
	block.add_child(header)

	# Ligne « Points de Match » (décompte animé depuis 0).
	var points_lbl := Label.new()
	points_lbl.add_theme_color_override("font_color", ACCENT_GOLD)
	points_lbl.add_theme_font_size_override("font_size", 22)
	points_lbl.text = "POINTS DE MATCH : +0"
	block.add_child(points_lbl)

	# Pass Spécial (M4 §8.67) : le serveur a appliqué +25 % d'XP (et coins héros ×4) — simple
	# RELAIS du flag, suffixe discret or sur la ligne d'XP (aucun calcul client).
	if bool(rewards.get("pass_bonus_applied", false)):
		var pass_lbl := Label.new()
		pass_lbl.text = "★ +25 % XP — PASS SPÉCIAL ACTIF"
		pass_lbl.add_theme_color_override("font_color", ACCENT_GOLD)
		pass_lbl.add_theme_font_size_override("font_size", 13)
		block.add_child(pass_lbl)

	# Jauge XP + Coins réutilisable (remplissage cyan + lueur dorée aux paliers de 10 niveaux).
	var bar = XpCoinsBarScript.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_child(bar)

	if rewards.get("level_up_triggered", false):
		var lvl_lbl := Label.new()
		var gained := int(rewards.get("levels_gained", 0))
		lvl_lbl.text = "⬆ %d NIVEAU(X) GAGNÉ(S) — NIVEAU %d" % [gained, int(rewards.get("new_level", 1))]
		lvl_lbl.add_theme_color_override("font_color", ACCENT_CYAN)
		lvl_lbl.add_theme_font_size_override("font_size", 14)
		block.add_child(lvl_lbl)

	# --- PROGRESSION DU HÉROS (sprint RPG, Objectif 5c) : XP héros distincte du profil, barre
	#     logarithmique (fraction dans le niveau fournie par le serveur), pop-up de paliers franchis. ---
	block.add_child(HSeparator.new())
	var hero_header := Label.new()
	hero_header.text = "▌ PROGRESSION DU HÉROS"
	hero_header.add_theme_color_override("font_color", ACCENT_CYAN)
	hero_header.add_theme_font_size_override("font_size", 18)
	block.add_child(hero_header)

	var hero_xp_lbl := Label.new()
	hero_xp_lbl.add_theme_color_override("font_color", ACCENT_GOLD)
	hero_xp_lbl.add_theme_font_size_override("font_size", 20)
	hero_xp_lbl.text = "XP HÉROS : +0"
	block.add_child(hero_xp_lbl)

	var hero_level_lbl := Label.new()
	var h_old := int(rewards.get("hero_level", 1))
	var h_new := int(rewards.get("hero_new_level", h_old))
	hero_level_lbl.text = ("NIVEAU HÉROS %d ❯ %d" % [h_old, h_new]) if h_new > h_old else ("NIVEAU HÉROS %d" % h_new)
	hero_level_lbl.add_theme_color_override("font_color", ACCENT_CYAN if h_new > h_old else TEXT_MUTED)
	hero_level_lbl.add_theme_font_size_override("font_size", 14)
	block.add_child(hero_level_lbl)

	# Barre log : remplie à la fraction xp_in_level / xp_for_level (0..1) calculée serveur-side.
	var hero_bar := ProgressBar.new()
	hero_bar.min_value = 0.0
	hero_bar.max_value = 1.0
	hero_bar.value = 0.0
	hero_bar.show_percentage = false
	hero_bar.custom_minimum_size = Vector2(0, 14)
	hero_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_child(hero_bar)

	# Pop-up « Statistiques Améliorées » : un palier franchi → bonus de stats (ex. +50 PV, +1 PA).
	for ms in rewards.get("hero_milestones", []):
		var ms_lbl := Label.new()
		ms_lbl.text = "⬆ STATISTIQUES AMÉLIORÉES (Niv %d) : %s" % [
			int(ms.get("level", 0)), _format_milestone_bonus(ms.get("bonus", {}))]
		ms_lbl.add_theme_color_override("font_color", ACCENT_GOLD)
		ms_lbl.add_theme_font_size_override("font_size", 14)
		block.add_child(ms_lbl)

	block.add_child(HSeparator.new())

	# Le bloc Récompenses passe EN TÊTE de la liste de débriefing (avant le Rapport d'Attrition).
	list.add_child(block)
	list.move_child(block, 0)

	await _run_reward_animation(points_lbl, bar, rewards)
	await _animate_hero(hero_xp_lbl, hero_bar, rewards)


# Formate un bonus de palier ({pv_max:50, pa:1, pb:0.01}) en libellé lisible (« +50 PV, +1 PA »).
func _format_milestone_bonus(bonus: Dictionary) -> String:
	var parts: Array[String] = []
	if int(bonus.get("pv_max", 0)) != 0:
		parts.append("+%d PV" % int(bonus.get("pv_max", 0)))
	if int(bonus.get("pa", 0)) != 0:
		parts.append("+%d PA" % int(bonus.get("pa", 0)))
	if float(bonus.get("pb", 0.0)) != 0.0:
		parts.append("+%d%% PB" % int(round(float(bonus.get("pb", 0.0)) * 100.0)))
	return ", ".join(parts) if not parts.is_empty() else "amélioration"


# Animation du bloc héros : décompte de l'XP gagnée puis remplissage de la barre log.
func _animate_hero(hero_xp_lbl: Label, hero_bar: ProgressBar, rewards: Dictionary) -> void:
	var earned := int(rewards.get("hero_xp_earned", 0))
	var t := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_method(
		func(v: float): hero_xp_lbl.text = "XP HÉROS : +%d" % int(round(v)),
		0.0, float(earned), 0.8)
	await t.finished

	var span := int(rewards.get("hero_xp_for_level", 0))
	var frac := 0.0 if span <= 0 else clampf(float(rewards.get("hero_xp_in_level", 0)) / float(span), 0.0, 1.0)
	var tb := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tb.tween_property(hero_bar, "value", frac, 0.7)
	await tb.finished

func _run_reward_animation(points_lbl: Label, bar, rewards: Dictionary) -> void:
	# Laisse le layout se résoudre (tailles des nœuds) avant les Tweens d'échelle/pivot.
	await get_tree().process_frame

	# 1) Décompte des Points de Match (0 → match_points).
	var pts := int(rewards.get("match_points", 0))
	var t := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_method(
		func(v: float): points_lbl.text = "POINTS DE MATCH : +%d" % int(round(v)),
		0.0, float(pts), 0.9)
	await t.finished

	# 2) La barre d'XP se remplit (avec montées de niveau + lueur Coins aux paliers de 10, §4).
	await bar.play_match_result(rewards)
