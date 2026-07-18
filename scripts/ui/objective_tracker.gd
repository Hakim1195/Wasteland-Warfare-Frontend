extends RefCounted

# OBJECTIVE TRACKER (E6 §8.78) — module de calcul PUR (aucun nœud, aucun autoload) : transforme
# l'objectif secret du joueur (notre propre entrée GameState.objectives[me] — type/params, §4.4) +
# un contexte d'état PUBLIC en progression prête à afficher. Testable par asserts (pattern G4).
#
# ctx (résolu par main.gd — le module ne lit PAS l'état) :
#   { "owned_count": int,        # mes territoires
#     "continents_owned": int,   # mes continents ENTIÈREMENT possédés (réutilise la synthèse E5)
#     "target_alive": bool,      # cible d'eliminate_player encore en vie ?
#     "target_name": String }    # nom lisible de la cible (déjà résolu — aucune fuite nouvelle §4.4)
#
# progress(objective, ctx) → {
#   "lines": Array[{ "label": String, "ratio": float 0..1, "done": bool }],  # 1 (simple) ou 2 (double)
#   "best_ratio": float,   # max des ratios → pilote le pulse OR ≥ 80 % côté HUD
#   "done": bool }         # au moins une ligne accomplie (sémantique OU des objectifs doubles)

const NEAR_WIN := 0.8   # seuil du pulse « proche de la victoire » (piloté côté HUD).

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
	return {"label": str(objective.get("description", TranslationServer.translate("OBJ_SECRET_FALLBACK"))),
		"ratio": 0.0, "done": false}

# Progression complète. Pour un objectif DOUBLE (§8.61) : DEUX mini-lignes (kill / classique),
# la PLUS AVANCÉE en tête. Sinon une seule ligne.
static func progress(objective: Dictionary, ctx: Dictionary) -> Dictionary:
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
