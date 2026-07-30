extends RefCounted

# OBJECTIVE TRACKER (E6 §8.78) — module de calcul PUR (aucun nœud, aucun autoload) : transforme
# l'objectif secret du joueur (notre propre entrée GameState.objectives[me] — type/params, §4.4) +
# un contexte d'état PUBLIC en progression prête à afficher. Testable par asserts (pattern G4).
#
# ctx (résolu par main.gd — le module ne lit PAS l'état) :
#   { "owned_count": int,        # mes territoires
#     "continents_owned": int,   # mes continents ENTIÈREMENT possédés (réutilise la synthèse E5)
#     "target_alive": bool,      # cible d'eliminate_player encore en vie ?
#     "target_name": String,     # nom lisible de la cible (déjà résolu — aucune fuite nouvelle §4.4)
#     # --- Clés des 3 types AJOUTÉS (chantier « Tension & fin de partie », LOT C) : MIROIR EXACT du
#     #     contexte serveur `objectives.build_context`, dont ce module réplique les formules. ---
#     "owned_by_continent": Dictionary,  # { continent_id : mes territoires DANS ce continent }
#     "continent_sizes": Dictionary,     # { continent_id : total de la carte jouée }
#     "combat_kills": int,               # MES unités ennemies tuées AU COMBAT (jamais la zone)
#     "owned_garrisons": Array }         # garnisons de MES territoires (pour fortified_hold)
#
# progress(objective, ctx) → {
#   "lines": Array[{ "label": String, "ratio": float 0..1, "done": bool }],  # 1 (simple) ou 2 (double)
#   "best_ratio": float,   # max des ratios → pilote le pulse OR ≥ 80 % côté HUD
#   "done": bool }         # au moins une ligne accomplie (sémantique OU des objectifs doubles)

const NEAR_WIN := 0.8   # seuil du pulse « proche de la victoire » (piloté côté HUD).

# Auto-vérification debug : une fois par session (pattern G4 §8.63 — combat_odds._self_check).
# Elle vaut CONTRE-ÉPREUVE des formules du chantier « Tension & fin de partie » (LOT C) : ces six
# ratios doivent rester le MIROIR EXACT d'`api/game/objectives.progress`, sinon la jauge affichée
# mentirait au joueur sur sa propre progression.
static var _self_checked := false

# Progression d'UN volet simple (conquer / continents / eliminate). Renvoie {label, ratio, done}.
# i18n : module STATIQUE (aucune instance → pas de tr() d'Object) — les libellés passent par
# TranslationServer.translate() (clés OBJ_* de translations/ui_strings.csv, locale gérée par
# LocaleManager). La ponctuation « %s : %s » est aussi une clé (espace fine FR avant les deux-points).
static func leg_progress(objective: Dictionary, ctx: Dictionary) -> Dictionary:
	var otype := str(objective.get("type", ""))
	var params: Dictionary = objective.get("params", {}) if typeof(objective.get("params")) == TYPE_DICTIONARY else {}
	if otype == "conquer_territories":
		var n := maxi(int(params.get("n", 24)), 1)
		var have := int(ctx.get("owned_count", 0))
		return {"label": TranslationServer.translate("OBJ_TERRITORIES_FMT") % [have, n],
			"ratio": clampf(float(have) / float(n), 0.0, 1.0), "done": have >= n}
	if otype == "control_continents":
		var n2 := maxi(int(params.get("n", 2)), 1)
		var have2 := int(ctx.get("continents_owned", 0))
		return {"label": TranslationServer.translate("OBJ_CONTINENTS_FMT") % [have2, n2],
			"ratio": clampf(float(have2) / float(n2), 0.0, 1.0), "done": have2 >= n2}
	if otype == "eliminate_player":
		var name := str(ctx.get("target_name", TranslationServer.translate("OBJ_TARGET_FALLBACK")))
		var alive := bool(ctx.get("target_alive", true))
		return {"label": TranslationServer.translate("OBJ_TARGET_LINE_FMT") % [name,
				(TranslationServer.translate("OBJ_TARGET_ALIVE") if alive
					else TranslationServer.translate("OBJ_TARGET_DOWN"))],
			"ratio": 0.0 if alive else 1.0, "done": not alive}
	# --- Trois types AJOUTÉS (chantier « Tension & fin de partie », LOT C) : formules MIROIR de
	#     `api/game/objectives.progress`. Toute divergence ferait mentir la jauge au joueur. ---
	if otype == "control_specific_continents":
		var pair: Array = params.get("continents", []) if typeof(params.get("continents")) == TYPE_ARRAY else []
		var owned_map: Dictionary = ctx.get("owned_by_continent", {})
		var sizes: Dictionary = ctx.get("continent_sizes", {})
		var have3 := 0
		var total3 := 0
		for cid in pair:
			have3 += int(owned_map.get(str(cid), 0))
			total3 += int(sizes.get(str(cid), 0))
		# Paire vide / continents inconnus de la carte → jamais de division par zéro (0 %).
		return {"label": TranslationServer.translate("OBJ_SPECIFIC_FMT") % [have3, maxi(total3, 0)],
			"ratio": 0.0 if total3 <= 0 else clampf(float(have3) / float(total3), 0.0, 1.0),
			"done": total3 > 0 and have3 >= total3}
	if otype == "destroy_units":
		var n4 := maxi(int(params.get("n", 40)), 1)
		var have4 := int(ctx.get("combat_kills", 0))
		return {"label": TranslationServer.translate("OBJ_DESTROY_FMT") % [have4, n4],
			"ratio": clampf(float(have4) / float(n4), 0.0, 1.0), "done": have4 >= n4}
	if otype == "fortified_hold":
		var n5 := maxi(int(params.get("n", 8)), 1)
		var threshold := maxi(int(params.get("min_garrison", 3)), 1)
		var garrisons: Array = ctx.get("owned_garrisons", []) if typeof(ctx.get("owned_garrisons")) == TYPE_ARRAY else []
		var have5 := 0
		for g in garrisons:
			if int(g) >= threshold:
				have5 += 1
		return {"label": TranslationServer.translate("OBJ_FORTIFIED_FMT") % [have5, n5, threshold],
			"ratio": clampf(float(have5) / float(n5), 0.0, 1.0), "done": have5 >= n5}
	return {"label": str(objective.get("description", TranslationServer.translate("OBJ_SECRET_FALLBACK"))),
		"ratio": 0.0, "done": false}

# Description COMPLÈTE traduite d'un objectif, composée de type/params (i18n 2026-07-18 — la
# `description` serveur, désormais en anglais invariant, ne sert que de repli pour un type
# inconnu). `target_name` optionnel = pseudo résolu de la cible du volet kill (sinon « #id »).
static func describe(objective: Dictionary, target_name: String = "") -> String:
	var otype := str(objective.get("type", ""))
	var params: Dictionary = objective.get("params", {}) if typeof(objective.get("params")) == TYPE_DICTIONARY else {}
	if otype == "double":
		var classic = objective.get("classic_objective")
		var classic_txt := describe(classic) if typeof(classic) == TYPE_DICTIONARY else ""
		var who := target_name
		if who == "":
			who = "#" + str(params.get("target_id", "?"))
		return "%s %s %s" % [TranslationServer.translate("OBJ_DESC_KILL_FMT") % who,
			TranslationServer.translate("OBJ_OR"), classic_txt]
	if otype == "conquer_territories":
		return TranslationServer.translate("OBJ_DESC_CONQUER_FMT") % int(params.get("n", 24))
	if otype == "control_continents":
		return TranslationServer.translate("OBJ_DESC_CONTINENTS_FMT") % int(params.get("n", 2))
	if otype == "eliminate_player":
		var who2 := target_name
		if who2 == "":
			who2 = "#" + str(params.get("target_id", "?"))
		return TranslationServer.translate("OBJ_DESC_ELIMINATE_FMT") % who2
	# --- Trois types AJOUTÉS (LOT C). Les continents DÉSIGNÉS réutilisent les clés CONT_* déjà
	#     traduites (§8.104) : on ne duplique jamais un nom de continent dans une nouvelle clé. ---
	if otype == "control_specific_continents":
		var pair: Array = params.get("continents", []) if typeof(params.get("continents")) == TYPE_ARRAY else []
		var names := PackedStringArray()
		for cid in pair:
			names.append(continent_name(str(cid)))
		if names.size() >= 2:
			return TranslationServer.translate("OBJ_DESC_CONTROL_SPECIFIC") % [names[0], names[1]]
		if names.size() == 1:
			return TranslationServer.translate("OBJ_DESC_CONTROL_SPECIFIC") % [names[0], "?"]
		return str(objective.get("description", ""))
	if otype == "destroy_units":
		return TranslationServer.translate("OBJ_DESC_DESTROY_UNITS") % int(params.get("n", 40))
	if otype == "fortified_hold":
		return TranslationServer.translate("OBJ_DESC_FORTIFIED_HOLD") % [
			int(params.get("n", 8)), int(params.get("min_garrison", 3))]
	return str(objective.get("description", ""))

# Nom TRADUIT d'un continent depuis son id snake_case, via les clés CONT_* existantes
# (CONT_NORTH_AMERICA, CONT_EUROPE…). Clé absente du CSV → on renvoie l'id « humanisé » plutôt
# que la clé brute : jamais de « CONT_XXX » affiché à l'écran.
static func continent_name(continent_id: String) -> String:
	var key := "CONT_" + continent_id.to_upper()
	var label := TranslationServer.translate(key)
	if label == key:
		return continent_id.replace("_", " ").capitalize()
	return label

# Progression complète. Pour un objectif DOUBLE (§8.61) : DEUX mini-lignes (kill / classique),
# la PLUS AVANCÉE en tête. Sinon une seule ligne.
static func progress(objective: Dictionary, ctx: Dictionary) -> Dictionary:
	if OS.is_debug_build() and not _self_checked:
		_self_check()
	var lines: Array = []
	if str(objective.get("type", "")) == "double":
		var kill = objective.get("kill_objective")
		var classic = objective.get("classic_objective")
		if typeof(kill) == TYPE_DICTIONARY:
			lines.append(leg_progress(kill, ctx))
		if typeof(classic) == TYPE_DICTIONARY:
			lines.append(leg_progress(classic, ctx))
		# La plus avancée d'abord (ratio décroissant, tri stable).
		lines.sort_custom(func(a, b): return float(a.get("ratio", 0.0)) > float(b.get("ratio", 0.0)))
	else:
		lines.append(leg_progress(objective, ctx))

	var best := 0.0
	var any_done := false
	for l in lines:
		best = maxf(best, float(l.get("ratio", 0.0)))
		any_done = any_done or bool(l.get("done", false))
	return {"lines": lines, "best_ratio": best, "done": any_done}


# Contre-épreuve des formules (miroir de api/game/objectives.progress). Les libellés passent par
# TranslationServer et ne sont donc PAS vérifiés ici (une clé absente rend la clé, pas une erreur) :
# on vérifie les RATIOS et les drapeaux `done`, seuls porteurs de sens métier.
static func _self_check() -> void:
	_self_checked = true
	# conquer_territories : 14/15 (le seuil est passé de 24 à 15 au LOT C).
	var conq := leg_progress({"type": "conquer_territories", "params": {"n": 15}},
		{"owned_count": 14})
	assert(absf(float(conq["ratio"]) - 14.0 / 15.0) < 0.001 and not bool(conq["done"]))
	assert(bool(leg_progress({"type": "conquer_territories", "params": {"n": 15}},
		{"owned_count": 15})["done"]))
	# control_specific_continents : 5 possédés sur 8 (Amérique du Sud 4 + Océanie 4).
	var spec := leg_progress(
		{"type": "control_specific_continents", "params": {"continents": ["south_america", "oceania"]}},
		{"owned_by_continent": {"south_america": 4, "oceania": 1},
		 "continent_sizes": {"south_america": 4, "oceania": 4}})
	assert(absf(float(spec["ratio"]) - 0.625) < 0.001 and not bool(spec["done"]))
	# Paire vide / carte inconnue : JAMAIS de division par zéro, jamais « accompli ».
	var empty := leg_progress({"type": "control_specific_continents", "params": {"continents": []}}, {})
	assert(float(empty["ratio"]) == 0.0 and not bool(empty["done"]))
	# destroy_units : 20/40 puis plafond à 1.0.
	assert(absf(float(leg_progress({"type": "destroy_units", "params": {"n": 40}},
		{"combat_kills": 20})["ratio"]) - 0.5) < 0.001)
	assert(float(leg_progress({"type": "destroy_units", "params": {"n": 40}},
		{"combat_kills": 999})["ratio"]) == 1.0)
	# fortified_hold : 2 territoires à garnison >= 7 sur 8 requis (garnison 7 = valeur du registre).
	var fort := leg_progress({"type": "fortified_hold", "params": {"n": 8, "min_garrison": 7}},
		{"owned_garrisons": [9, 7, 6, 1, 1]})
	assert(absf(float(fort["ratio"]) - 0.25) < 0.001 and not bool(fort["done"]))
	# Objectif DOUBLE : le meilleur des deux volets pilote `best_ratio` (sémantique OU).
	var dbl := progress({"type": "double", "params": {"target_id": 2},
		"kill_objective": {"type": "eliminate_player", "params": {"target_id": 2}},
		"classic_objective": {"type": "destroy_units", "params": {"n": 10}}},
		{"target_alive": true, "combat_kills": 8})
	assert(dbl["lines"].size() == 2 and absf(float(dbl["best_ratio"]) - 0.8) < 0.001)
