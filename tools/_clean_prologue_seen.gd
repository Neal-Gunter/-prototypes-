extends SceneTree
## 开发用：清掉序章台词的「已见」记录（截图之后让真实玩家还能看到完整教学）
func _initialize() -> void:
	var cfg = root.get_node_or_null("Cfg")
	if cfg == null:
		quit(1)
		return
	cfg.load_cfg()
	var keys := []
	for k in cfg.seen_lines.keys():
		if str(k).begins_with("prologue:"):
			keys.append(k)
	for k in keys:
		cfg.seen_lines.erase(k)
	cfg.save_cfg()
	print("[clean] prologue keys removed = %d" % keys.size())
	quit(0)
