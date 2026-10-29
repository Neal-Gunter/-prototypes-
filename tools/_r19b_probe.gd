extends SceneTree

func _initialize() -> void:
	await create_timer(0.3).timeout
	var packed: PackedScene = load("res://scenes/Main.tscn")
	var main: Node = packed.instantiate()
	Engine.get_main_loop().root.add_child(main)
	await create_timer(0.4).timeout
	var root: Node = Engine.get_main_loop().root
	var Cfg = root.get_node_or_null("Cfg")
	Cfg.prologue_done = true
	main.call("_start_run", false)
	main.call("_confirm_weapon")
	main.call("_enter_level", 4)
	print("[probe] level=%s name=%s rooms=%d" % [str(main.get("level_index")), str(main.get("level_name")), (main.get("rooms") as Array).size()])
	var rs: Array = main.get("rooms")
	for i in rs.size():
		print("   room %d kind=%s boss=%s mirror=%s" % [i, str(rs[i].get("kind")), str(rs[i].get("boss", "-")), str(rs[i].get("mirror", false))])
	main.call("_enter_room", 5)
	var es: Array = main.get("enemies")
	for e in es:
		print("   enemy kind=%s is_boss=%s hp=%s title=%s" % [str(e.get("kind")), str(e.get("is_boss")), str(e.get("max_hp")), str(e.call("boss_title"))])
	var b = main.get("boss")
	print("[probe] boss=%s locked=%s enemies=%d" % [str(b), str(main.get("boss_room_locked")), (main.get("enemies") as Array).size()])
	if b != null:
		print("[probe] boss kind=%d title=%s mirror=%s range=%.0f dmg=%d" % [int(b.get("kind")), str(b.call("boss_title")), str(b.get("mirror_weapon")), float(b.get("attack_range")), int(b.get("dmg"))])
	quit()
