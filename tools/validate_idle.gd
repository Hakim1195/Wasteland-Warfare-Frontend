extends SceneTree
# Harnais de validation de l'idle. Args via OS.get_cmdline_user_args().
const HERO := "res://scenes/components/hero_viewport_3d.tscn"

func _initialize() -> void:
	_go()

func _go() -> void:
	var glb := ""
	var out := ""
	var a := OS.get_cmdline_user_args()
	for i in range(a.size()):
		if a[i] == "--glb" and i + 1 < a.size(): glb = a[i + 1]
		elif a[i] == "--out" and i + 1 < a.size(): out = a[i + 1]
	if glb == "" or out == "":
		print("ABORT_ARGS")
		quit(2)
		return
	var hero = load(HERO).instantiate()
	get_root().add_child(hero)
	await process_frame
	await process_frame
	var ok = hero.set_model(glb)
	print("SET_MODEL=", ok)
	if not ok:
		quit(1)
		return
	var ap: AnimationPlayer = _find(hero)
	if ap == null:
		print("NO_AP")
		quit(1)
		return
	var names: PackedStringArray = ap.get_animation_list()
	if names.is_empty():
		print("NO_ANIM")
		quit(1)
		return
	var pick: StringName = names[0]
	for n in names:
		if str(n).to_lower().contains("idle"): pick = n
	# compter les pistes non-constantes (idle inerte si 0)
	var anim: Animation = ap.get_animation(pick)
	var nonconst: int = 0
	for ti in range(anim.get_track_count()):
		if anim.track_get_key_count(ti) > 1: nonconst += 1
	print("TRACKS_NONCONST=", nonconst)
	var vp: SubViewport = hero.get_node("SubViewport")
	var labels: Array[String] = ["a", "b", "c", "d"]
	var L: float = anim.length
	ap.play(pick)
	for k in range(4):
		ap.seek((L * k) / 4.0, true)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		await process_frame
		await process_frame
		vp.get_texture().get_image().save_png(out + "/seek_" + labels[k] + ".png")
		print("SEEK_", labels[k])
	print("DONE")
	quit(0 if nonconst > 0 else 3)

# Recherche polymorphe typée : robuste aux AnimationPlayer sous-classés par script
# (get_class() renverrait le nom de classe du script, pas "AnimationPlayer").
func _find(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var r := _find(c)
		if r != null:
			return r
	return null
