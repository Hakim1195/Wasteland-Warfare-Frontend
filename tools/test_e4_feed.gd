extends Node

# TEST E4 §8.76 (style maison) — Journal de Guerre 2.0 : parsing war_feed (catégorie/icône/tid
# par type d'évènement, repli system pour un type inconnu — AUCUNE perte), entrées de zone,
# filtres + kill feed + toast au niveau HUD (arène réelle).
#   & <godot_console> --headless --path frontend res://tools/test_e4_feed.tscn

const WarFeed := preload("res://scripts/ui/war_feed.gd")

func _stub_ctx(fallback := "FALLBACK") -> Dictionary:
	return {
		"bb": func(pid: int) -> String: return "P%d" % pid,
		"tname": func(tid: String) -> String: return tid.capitalize(),
		"fallback": fallback,
		"atk_pid": 11, "def_pid": 7,
	}

func _ready() -> void:
	# 1) attack_result COMPLET (conquête + permadeath) → 3 entrées combat ordonnées.
	var ev := {
		"event_type": "attack_result",
		"attacker_territory_id": "peru", "defender_territory_id": "ontario",
		"attacker_losses": 1.0, "defender_losses": 3.0, "conquered": true,
		"hero_duel": {"attacker_id": 11.0, "defender_id": 7.0, "hero_died": true,
			"damage": 14, "defender_pv": 0, "defender_pv_max": 52},
		"system_messages": ["[color=yellow]☢ ALERTE MÉTÉO : prochaine zone prévue sur X[/color]",
			"note simple"],
	}
	var entries: Array = WarFeed.parse(ev, _stub_ctx())
	assert(entries.size() == 5)  # combat + conquête + permadeath + 2 system_messages
	assert(entries[0]["category"] == "combat" and entries[0]["tid"] == "ontario")
	assert(not entries[0]["major"])
	assert(entries[1]["major"] and entries[1]["rich_text"].find("(−3)") >= 0)
	assert(entries[2]["major"] and entries[2]["rich_text"].find("P7") >= 0 \
		and entries[2]["rich_text"].find("P11") >= 0)
	assert(entries[3]["category"] == "zone")     # ☢ ALERTE MÉTÉO
	assert(entries[4]["category"] == "system")   # note simple
	print("[OK] attack_result complet : 5 entrees, categories/majors exacts (7 asserts)")

	# 2) Types simples : cartes / système — le texte legacy (fallback) est conservé tel quel.
	assert(WarFeed.parse({"event_type": "card_played"}, _stub_ctx("CARTE"))[0]["category"] == "cards")
	assert(WarFeed.parse({"event_type": "turn_passed"}, _stub_ctx())[0]["category"] == "system")
	var unknown: Array = WarFeed.parse({"event_type": "evenement_futur"}, _stub_ctx("BRUT"))
	assert(unknown.size() == 1 and unknown[0]["category"] == "system" \
		and unknown[0]["rich_text"] == "BRUT")
	print("[OK] cartes/system + repli type inconnu sans perte (3 asserts)")

	# 3) Tics de zone AUTORITAIRES (ZONE LÉTALE §8.145) : le serveur ITEMISE enfin ses dégâts via
	# l'évènement structuré `zone_damage`. La dérivation client (`WarFeed.zone_entries` /
	# `main._derive_zone_ticks`) est SUPPRIMÉE — garder les deux aurait doublé chaque ligne.
	# Le MONTANT vient du serveur (registre `zone_settings.ZONE_DAMAGE`), jamais d'un « −1 » local.
	var zev := {
		"event_type": "turn_passed",
		"system_events": [
			{"code": "zone_damage", "territory_id": "quebec", "owner_id": 7,
				"amount": 1, "ravaged": false},
			{"code": "zone_damage", "territory_id": "ontario", "owner_id": null,
				"amount": 2, "ravaged": true},
		],
	}
	var zx: Array = WarFeed.parse(zev, _stub_ctx())
	assert(zx.size() == 3)  # entrée principale (turn_passed) + 2 évènements structurés
	assert(zx[1]["category"] == "zone" and zx[1]["tid"] == "quebec" and not zx[1]["major"])
	assert(zx[1]["rich_text"].find("1") >= 0 and zx[1]["rich_text"].find("Quebec") >= 0)
	# Territoire RAVAGÉ = entrée MAJEURE (elle remonte au kill feed), et le montant est celui du
	# serveur : un « 2 » ici prouve qu'aucun « −1 » n'est câblé en dur côté client.
	assert(zx[2]["major"] and zx[2]["tid"] == "ontario" and zx[2]["rich_text"].find("2") >= 0)
	print("[OK] zone_damage structure : tic simple + ravage majeur, montant SERVEUR (5 asserts)")

	# 4) Niveau HUD (arène réelle) : flux filtrable + [url=<tid>] + kill feed + toast.
	# NB : RichTextLabel.text n'est PAS mis à jour par append_text → on lit get_parsed_text()
	# (contenu sans balises) et on vérifie le [url] via le builder de ligne _feed_line.
	var arena = load("res://scenes/game/main.tscn").instantiate()
	add_child(arena)
	var hud = arena.get_node("HUD")
	hud.add_feed_entries(entries)
	assert(str(hud.get_node("%LogText").get_parsed_text()).find("Ontario") >= 0)
	assert(str(hud._feed_line(entries[0])).find("[url=ontario]") >= 0)
	hud._feed_filter = "cards"
	hud._rerender_feed()
	assert(str(hud.get_node("%LogText").get_parsed_text()).find("Ontario") < 0)  # filtré
	hud.add_feed_entries([{"category": "cards", "icon": "🃏",
		"rich_text": "CARTE-TEST", "tid": "", "major": false}])
	assert(str(hud.get_node("%LogText").get_parsed_text()).find("CARTE-TEST") >= 0)
	hud._feed_filter = "all"
	hud._rerender_feed()
	hud.push_kill_feed("⚔ TEST ➜ Ontario (−3)")
	assert(hud._kill_feed.get_child_count() >= 1)
	hud.show_defense_toast("⚠ TEST")
	assert(hud._defense_toast != null and hud._defense_toast.visible)
	print("[OK] HUD : rendu, [url], filtre, kill feed, toast (6 asserts)")

	print("[OK] TEST E4 FEED : 21 asserts verts")
	get_tree().quit(0)
