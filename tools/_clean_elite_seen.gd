extends SceneTree
## 开发用：把 Cfg 里 elite_* 的「已见」记录清掉（截图后让存档回到未见过状态）
## 注意：--script 入口里 autoload 的 _ready 还没跑，必须先显式 load_cfg()，
##       否则内存里是空字典，save_cfg() 会把整段 lore 洗掉。
func _initialize() -> void:
	var cfg = root.get_node_or_null("Cfg")
	if cfg == null:
		print("[clean] 取不到 Cfg 单例")
		quit(1)
		return
	cfg.load_cfg()
	var keys := []
	for k in cfg.seen_lines.keys():
		if str(k).begins_with("elite_"):
			keys.append(k)
	for k in keys:
		cfg.seen_lines.erase(k)
	cfg.save_cfg()
	print("[clean] removed %d elite keys, left=%d" % [keys.size(), cfg.seen_lines.size()])
	quit(0)
