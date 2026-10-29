extends SceneTree
## 触屏链路探针（R19 修 APK 点不动屏幕）
var _f := 0
var m: Node = null
var _orig_ui := false

func _initialize() -> void:
	m = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	var cfg = root.get_node_or_null("Cfg")
	if cfg != null:
		_orig_ui = bool(cfg.touch_ui)

func _process(_d: float) -> bool:
	_f += 1
	if _f == 3:
		var t = m.get("touch")
		print("[probe] mobile=", OS.has_feature("mobile"),
			" can_touch=", t.can_touch, " touch_mode=", m.get("touch_mode"),
			" visible=", t.visible, " input=", t.is_processing_input())
	if _f == 5:
		var t = m.get("touch")
		# 模拟玩家在设置里把按键关掉
		t.set_shown(false)
		print("[probe] hidden -> visible=", t.visible, " input=", t.is_processing_input())
		# 再来一次点击，应该把按键叫回来
		var ev := InputEventScreenTouch.new()
		ev.index = 0
		ev.pressed = true
		ev.position = Vector2(640, 360)
		t._input(ev)
		print("[probe] after tap -> visible=", t.visible, " input=", t.is_processing_input())
	if _f == 7:
		var t = m.get("touch")
		print("[probe] state before tap=", m.get("state"))
		var ev := InputEventScreenTouch.new()
		ev.index = 1
		ev.pressed = true
		ev.position = Vector2(640, 250)
		t._input(ev)
		var up := InputEventScreenTouch.new()
		up.index = 1
		up.pressed = false
		up.position = Vector2(640, 250)
		t._input(up)
	if _f == 10:
		print("[probe] state after tap=", m.get("state"))
		# 探针不改玩家配置
		var cfg = root.get_node_or_null("Cfg")
		if cfg != null:
			cfg.touch_ui = _orig_ui
			cfg.save_cfg()
		quit(0)
		return true
	return false
