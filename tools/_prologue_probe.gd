extends SceneTree
## R19a 序章流程探针：选武器 → 3 间教学房 → 自动接主线第一关
var _f := 0
var m: Node = null
var _orig := false

func _initialize() -> void:
	m = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	var cfg = root.get_node_or_null("Cfg")
	if cfg != null:
		cfg.load_cfg()
		_orig = bool(cfg.prologue_done)

func _process(_d: float) -> bool:
	_f += 1
	var cfg = root.get_node_or_null("Cfg")
	if _f == 3:
		cfg.prologue_done = false
		m.call("_start_run", false)
		m.call("_confirm_weapon")
		print("[p] enter: prologue=%s room=%d enemies=%d name=%s"
			% [str(m.get("prologue_mode")), int(m.get("room_i")),
			   (m.get("enemies") as Array).size(), str(m.get("level_name"))])
	if _f == 5:
		m.call("_resolve_room_clear", false)
		print("[p] room1 cleared -> prologue=%s room=%d enemies=%d"
			% [str(m.get("prologue_mode")), int(m.get("room_i")),
			   (m.get("enemies") as Array).size()])
	if _f == 7:
		m.call("_resolve_room_clear", false)
		print("[p] room2 cleared -> prologue=%s room=%d enemies=%d"
			% [str(m.get("prologue_mode")), int(m.get("room_i")),
			   (m.get("enemies") as Array).size()])
	if _f == 9:
		m.call("_resolve_room_clear", false)
		print("[p] room3 cleared -> prologue=%s level=%d done=%s name=%s state=%s"
			% [str(m.get("prologue_mode")), int(m.get("level_index")),
			   str(cfg.prologue_done), str(m.get("level_name")), str(m.get("state"))])
		cfg.prologue_done = _orig
		cfg.save_cfg()
		quit(0)
		return true
	return false
