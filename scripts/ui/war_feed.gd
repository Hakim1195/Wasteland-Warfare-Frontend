extends RefCounted

# WAR FEED (E4 §8.76) — module de PARSING PUR (aucun nœud, aucun accès réseau/état) : transforme
# chaque `game_event` (+ ses system_messages) en entrées structurées pour le Journal de Guerre :
#   { "category": "combat"|"zone"|"cards"|"system", "icon": String, "rich_text": String (BBCode),
#     "tid": String ("" si aucun territoire), "major": bool (repris par le kill feed E4) }
# Résolutions (pseudos colorisés/échappés, noms de territoires, texte de repli) injectées par le
# contrôleur via `ctx` — le module reste testable par asserts (pattern G4) avec des stubs :
#   ctx = { "bb": Callable(pid)->String,        # pseudo BBCode (main._bb_pseudo — E1)
#           "tname": Callable(tid)->String,     # nom lisible d'un territoire
#           "fallback": String,                 # texte legacy (main._format_event) — AUCUNE perte
#           "atk_pid": int, "def_pid": int }    # propriétaires PRÉ-combat (attack_result seul)
#
# REPLI : tout évènement au type inconnu devient UNE entrée `system` portant le texte legacy.

const CAT_COMBAT := "combat"
const CAT_ZONE := "zone"
const CAT_CARDS := "cards"
const CAT_SYSTEM := "system"

# event_type → catégorie, pour les évènements dont le texte legacy (fallback) suffit tel quel.
const SIMPLE_CATEGORIES := {
	"card_played": CAT_CARDS,
	"card_kept": CAT_CARDS,
	"units_deployed": CAT_SYSTEM,
	"initial_units_placed": CAT_SYSTEM,
	"units_moved": CAT_SYSTEM,
	"conquer_move_resolved": CAT_SYSTEM,
	"turn_passed": CAT_SYSTEM,
	"turn_timeout": CAT_SYSTEM,
	"blind_deploy_submitted": CAT_SYSTEM,
	"blind_deploy_resolved": CAT_SYSTEM,
	"game_initialized": CAT_SYSTEM,
	"game_over": CAT_SYSTEM,
	"spy_done": CAT_SYSTEM,
}
const SIMPLE_ICONS := {"card_played": "❖", "card_kept": "❖"}

static func _mk(category: String, icon: String, rich_text: String,
		tid: String = "", major: bool = false) -> Dictionary:
	return {"category": category, "icon": icon, "rich_text": rich_text,
		"tid": tid, "major": major}

# Point d'entrée : un évènement serveur → une ou plusieurs entrées ORDONNÉES (l'entrée principale
# d'abord, puis conquête / permadeath / system_messages).
static func parse(event, ctx: Dictionary) -> Array:
	var out: Array = []
	if typeof(event) != TYPE_DICTIONARY:
		out.append(_mk(CAT_SYSTEM, "⚙", str(ctx.get("fallback", str(event)))))
		return out
	var etype := str(event.get("event_type", ""))
	var bb: Callable = ctx.get("bb", Callable())
	var tname: Callable = ctx.get("tname", Callable())

	if etype == "attack_result":
		out.append_array(_parse_attack(event, ctx, bb, tname))
	elif SIMPLE_CATEGORIES.has(etype):
		var cat: String = SIMPLE_CATEGORIES[etype]
		out.append(_mk(cat, SIMPLE_ICONS.get(etype, "⚙"), str(ctx.get("fallback", etype))))
	else:
		# Type inconnu (évolution serveur) → entrée system BRUTE : aucune perte d'info.
		out.append(_mk(CAT_SYSTEM, "⚙", str(ctx.get("fallback", etype))))

	# Évènements système STRUCTURÉS (i18n 2026-07-18) : quand le serveur les fournit
	# (system_events = [{code, params}]), on les traduit LOCALEMENT et on IGNORE les
	# system_messages legacy (mêmes informations en anglais invariant — doublon sinon).
	var sys_events = event.get("system_events", [])
	if typeof(sys_events) == TYPE_ARRAY and not sys_events.is_empty():
		for sev in sys_events:
			var entry := _system_event_entry(sev, tname, ctx.get("fname", Callable()), bb)
			if not entry.is_empty():
				out.append(entry)
		return out

	# system_messages legacy attachés (immunités Isotope, ALERTE MÉTÉO du télégraphe G1…) : BBCode
	# serveur conservé tel quel ; « ☢ »/« shielded » (et l'ancien libellé FR du Culte) → zone.
	for m in event.get("system_messages", []):
		var txt := str(m)
		var is_zone: bool = txt.find("☢") >= 0 or txt.find("shielded") >= 0 \
			or txt.find("Culte de l'Isotope a protégé") >= 0
		out.append(_mk(CAT_ZONE if is_zone else CAT_SYSTEM, "☢" if is_zone else "⚙", txt))
	return out

# Une entrée de journal TRADUITE pour un évènement système structuré {code, ...params} (i18n
# 2026-07-18). Codes connus : zone_forecast {territory_ids}, zone_protected {faction_id,
# territory_id}, reinforcements_granted {player_id, base, continent_bonus, faction_bonus, total}
# (REFONTE UI ARÈNE lot E). Code inconnu (évolution serveur) → entrée system brute (aucune perte).
# TranslationServer.translate (et non tr()) : module RefCounted statique, hors arbre de scène.
static func _system_event_entry(sev, tname: Callable, fname: Callable,
		bb: Callable = Callable()) -> Dictionary:
	if typeof(sev) != TYPE_DICTIONARY:
		return {}
	var code := str(sev.get("code", ""))
	match code:
		"reinforcements_granted":
			# « RENFORTS : 7 (base 4 + continents 2 + pouvoir 1) » — la part POUVOIR passe en OR
			# quand elle est non nulle : c'est TOUT l'intérêt de l'évènement (rendre visible le
			# +1 des Barons et le +N des Gardiens d'Éden, invisibles dans le total historique).
			var fac := int(sev.get("faction_bonus", 0))
			var detail := TranslationServer.translate("FEED_REINFORCE_DETAIL_FMT") % [
				int(sev.get("base", 0)), int(sev.get("continent_bonus", 0)),
				("[color=#e0b249]%d[/color]" % fac) if fac > 0 else str(fac)]
			return _mk(CAT_SYSTEM, "❖", TranslationServer.translate("FEED_REINFORCE_FMT") % [
				_bb_of(bb, int(sev.get("player_id", -9999))),
				int(sev.get("total", 0)), detail])
		"zone_forecast":
			var names := PackedStringArray()
			for tid in sev.get("territory_ids", []):
				names.append(_tname_of(tname, str(tid)))
			return _mk(CAT_ZONE, "☢",
				TranslationServer.translate("FEED_ZONE_FORECAST_FMT") % ", ".join(names))
		"zone_protected":
			var fac := str(sev.get("faction_id", ""))
			if fname.is_valid():
				fac = str(fname.call(fac))
			return _mk(CAT_ZONE, "☢",
				TranslationServer.translate("FEED_ZONE_PROTECTED_FMT") % [
					fac, _tname_of(tname, str(sev.get("territory_id", "")))],
				str(sev.get("territory_id", "")))
		_:
			return _mk(CAT_SYSTEM, "⚙", code)

static func _parse_attack(event: Dictionary, ctx: Dictionary,
		bb: Callable, tname: Callable) -> Array:
	var out: Array = []
	var atk_tid := str(event.get("attacker_territory_id", ""))
	var def_tid := str(event.get("defender_territory_id", ""))
	var def_name := _tname_of(tname, def_tid)
	var atk_pid := int(ctx.get("atk_pid", -9999))
	var def_pid := int(ctx.get("def_pid", -9999))
	var atk_label := _bb_of(bb, atk_pid) if atk_pid != -9999 else _tname_of(tname, atk_tid)

	var line := TranslationServer.translate("FEED_ATTACK_FMT") % [
		atk_label, def_name,
		int(event.get("attacker_losses", 0)), int(event.get("defender_losses", 0))]
	# Effets de faction déclenchés (marqueurs compacts — noms de factions EN invariants,
	# pouvoirs traduits ; refonte identités 2026-07-18).
	if event.get("phalanges_reroll"):
		line += " " + TranslationServer.translate("FEED_MARK_PHALANX")
	if event.get("aegis_kill"):
		line += " " + TranslationServer.translate("FEED_MARK_AEGIS")
	if event.get("terror_kill"):
		line += " " + TranslationServer.translate("FEED_MARK_TERROR")
	# REFONTE UI ARÈNE (lot E) : les 2 marqueurs MANQUANTS — Razzia (Pillards, relance de TOUS les
	# dés ≤ 2) et Embuscade (Chasseurs d'Ombres, dé d'attaque bonus). Le serveur posait déjà ces
	# flags ; ils n'étaient rendus NULLE PART, donc ces pouvoirs semblaient ne pas exister.
	if event.get("razzia_reroll"):
		line += " " + TranslationServer.translate("FEED_MARK_RAZZIA")
	if event.get("first_strike"):
		line += " " + TranslationServer.translate("FEED_MARK_AMBUSH")
	out.append(_mk(CAT_COMBAT, "⚔", line, def_tid))

	# Conquête → entrée MAJEURE compacte (kill feed E4 : « ⚔ Hakim ➜ Ontario (−3) »).
	if bool(event.get("conquered", false)):
		out.append(_mk(CAT_COMBAT, "⚑", "⚔ %s ➜ %s (−%d)" % [
			atk_label, def_name, int(event.get("defender_losses", 0))], def_tid, true))

	# Permadeath du héros défenseur → entrée MAJEURE (« 💀 X abattu par Y »).
	var duel = event.get("hero_duel")
	if typeof(duel) == TYPE_DICTIONARY and bool(duel.get("hero_died", false)):
		out.append(_mk(CAT_COMBAT, "☠", TranslationServer.translate("FEED_HERO_DOWN_FMT") % [
			_bb_of(bb, int(duel.get("defender_id", -9999))),
			_bb_of(bb, int(duel.get("attacker_id", -9999)))], def_tid, true))
	return out

# Entrées « tic de zone » (dégâts de contamination DÉRIVÉS par le contrôleur en comparant les
# garnisons affichées avant/après un évènement de tour — le serveur ne les itemise pas).
# ticks = Array[{ "tid": String, "name": String, "ravaged": bool }].
static func zone_entries(ticks: Array) -> Array:
	var out: Array = []
	for t in ticks:
		if typeof(t) != TYPE_DICTIONARY:
			continue
		var nm := str(t.get("name", t.get("tid", "?")))
		if bool(t.get("ravaged", false)):
			# Territoire rasé par les radiations (garnison 0 → neutre) : entrée MAJEURE.
			out.append(_mk(CAT_ZONE, "☢",
				TranslationServer.translate("FEED_ZONE_RAVAGED_FMT") % nm, str(t.get("tid", "")), true))
		else:
			out.append(_mk(CAT_ZONE, "☢",
				TranslationServer.translate("FEED_ZONE_TICK_FMT") % nm, str(t.get("tid", ""))))
	return out

static func _bb_of(bb: Callable, pid: int) -> String:
	if bb.is_valid():
		return str(bb.call(pid))
	return TranslationServer.translate("WR_PLAYER_FALLBACK") % pid

static func _tname_of(tname: Callable, tid: String) -> String:
	if tname.is_valid():
		return str(tname.call(tid))
	return tid
