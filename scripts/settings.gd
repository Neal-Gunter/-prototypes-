extends Node
## 设置 + 存档（自动加载为 Cfg）。
## 设置存 user://settings.cfg，存档存 user://saves/slot_N.json。

const CFG_PATH := "user://settings.cfg"
const SAVE_DIR := "user://saves"
const SLOTS := 3
const MeridianScript := preload("res://scripts/meridian.gd")
const AlchemyScript := preload("res://scripts/alchemy.gd")

signal changed()

var master := 0.9      # 主音量 0..1
var sfx := 0.9         # 音效音量 0..1
var shake := 1.0       # 震屏强度 0..1.5
var fullscreen := false
## 手机虚拟按键：默认只在触屏设备（安卓）上开，PC 上默认关，避免按键糊在画面上
var touch_ui := OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()


## 这台设备是不是「没有键盘、只能靠点屏幕」的设备。
## 移动端 / 有触摸屏：虚拟按键是唯一的输入方式，不能被配置关死。
func is_touch_only() -> bool:
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
## 虚拟按键大小倍率（0.7 ~ 1.5）与逐键位移（可拖动自定义布局）
var touch_scale := 1.0
var touch_offsets := {}

## 今日道劫的本地记录：{"date": "2026-10-26", "rooms": 6, "cleared": true}
var daily_date := ""
var daily_rooms := 0
var daily_cleared := false
## R23：破劫时的剩血（评分向；-1 = 未记录）
var daily_hp := -1

## R28：破劫评分三件套 —— 用时（秒，仅计战斗时间）、受击次数、总分
var daily_time := 0.0
var daily_dmg := -1
var daily_score := 0

## R28：本地榜 —— 最近 5 条破劫记录 [{date, score, secs, dmg, hp}]
## 跨日期累积（不是「只看今天」），所以「今天打得好不好」有对照物。
var daily_board: Array = []
const DAILY_BOARD_MAX := 5

## R14：已看过的叙事台词（"kind:slot" / "stele:2" / "merchant:1"）。
## 首次完整播放，重开压成短句 —— 叙事不拖慢肉鸽。
var seen_lines := {}

## R16：残卷碎片永久收集（跨局保留，供图鉴页用）。
## 与 seen_lines 分开：seen_lines 管「台词播过没」，这里管「碎片拿到没」。
var fragments_seen := {}
## R19a：序章「钟楼」是否已经走完（走完就不再自动进序章）
var prologue_done := false
## R39：隐藏 Boss「钟楼旧主」是否已打赢。
## 与 prologue_done 分开：后者管「序章看过没」，前者管「顶阁通关没」。
## 打赢之后序章不会再开顶阁（无伤也没用 —— 已经赢过了）。
var old_master_beaten := false

## R16：已解锁的主角自述（"3" / "6" / "9" / "12"）
var self_seen := {}

## R33a：跨局货币「道痕」与经脉等级（节点 id → 0..3）。
## 与局内「道蕴」严格区分：道蕴是本局花的钱、会随开新局清零；
## 道痕是局外攒的点数，不进任何存档槽，只写进 settings.cfg 的 meta 段。
var daoyun := 0
var daoyun_total := 0
var meridian_lv := {}
## R33c 跨局背包：{消耗品 id: 件数}。上限 AlchemyScript.PANTRY_CAP，开局注入快捷格后清空
var pantry := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	load_cfg()


func _path() -> String:
	return ProjectSettings.globalize_path(CFG_PATH)


func load_cfg() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) != OK:
		apply()
		return
	master = float(cf.get_value("audio", "master", master))
	sfx = float(cf.get_value("audio", "sfx", sfx))
	shake = float(cf.get_value("video", "shake", shake))
	fullscreen = bool(cf.get_value("video", "fullscreen", fullscreen))
	touch_ui = bool(cf.get_value("video", "touch_ui", touch_ui))
	# 触屏设备上强制打开：否则玩家一旦关掉按键，就再也没有手指能点回来（会锁死）
	if is_touch_only():
		touch_ui = true
	touch_scale = clampf(float(cf.get_value("video", "touch_scale", touch_scale)), 0.7, 1.5)
	touch_offsets = _decode_offsets(str(cf.get_value("video", "touch_offsets", "")))
	daily_date = str(cf.get_value("daily", "date", ""))
	daily_rooms = int(cf.get_value("daily", "rooms", 0))
	daily_cleared = bool(cf.get_value("daily", "cleared", false))
	daily_hp = int(cf.get_value("daily", "hp", -1))
	daily_time = float(cf.get_value("daily", "time", 0.0))
	daily_dmg = int(cf.get_value("daily", "dmg", -1))
	daily_score = int(cf.get_value("daily", "score", 0))
	daily_board = _decode_board(str(cf.get_value("daily", "board", "")))
	seen_lines = _decode_seen(str(cf.get_value("lore", "seen", "")))
	fragments_seen = _decode_seen(str(cf.get_value("lore", "fragments", "")))
	self_seen = _decode_seen(str(cf.get_value("lore", "self", "")))
	prologue_done = bool(cf.get_value("lore", "prologue", false))
	old_master_beaten = bool(cf.get_value("lore", "old_master", false))
	daoyun = maxi(0, int(cf.get_value("meta", "daoyun", 0)))
	daoyun_total = maxi(0, int(cf.get_value("meta", "daoyun_total", 0)))
	meridian_lv = _decode_lv(str(cf.get_value("meta", "meridian", "")))
	pantry = _decode_counts(str(cf.get_value("meta", "pantry", "")), AlchemyScript.PANTRY_CAP)
	apply()


func save_cfg() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "master", master)
	cf.set_value("audio", "sfx", sfx)
	cf.set_value("video", "shake", shake)
	cf.set_value("video", "fullscreen", fullscreen)
	cf.set_value("video", "touch_ui", touch_ui)
	cf.set_value("video", "touch_scale", touch_scale)
	cf.set_value("video", "touch_offsets", _encode_offsets())
	cf.set_value("daily", "date", daily_date)
	cf.set_value("daily", "rooms", daily_rooms)
	cf.set_value("daily", "cleared", daily_cleared)
	cf.set_value("daily", "hp", daily_hp)
	cf.set_value("daily", "time", daily_time)
	cf.set_value("daily", "dmg", daily_dmg)
	cf.set_value("daily", "score", daily_score)
	cf.set_value("daily", "board", _encode_board())
	cf.set_value("lore", "seen", _encode_seen())
	cf.set_value("lore", "fragments", _encode_keys(fragments_seen))
	cf.set_value("lore", "self", _encode_keys(self_seen))
	cf.set_value("lore", "prologue", prologue_done)
	cf.set_value("lore", "old_master", old_master_beaten)
	cf.set_value("meta", "daoyun", daoyun)
	cf.set_value("meta", "daoyun_total", daoyun_total)
	cf.set_value("meta", "meridian", JSON.stringify(meridian_lv))
	cf.set_value("meta", "pantry", JSON.stringify(pantry))
	cf.save(CFG_PATH)
	apply()


# ---------------------------------------------------------------- R33a 道痕与经脉
## 计数型字典的编解码（JSON 字典；JSON 数字回来是 float，这里统一转 int 并夹上限）
func _decode_counts(s: String, cap: int) -> Dictionary:
	var out := {}
	if s.strip_edges() == "":
		return out
	var v = JSON.parse_string(s)
	if v is Dictionary:
		for k in v.keys():
			var n := int(v[k])
			if n > 0:
				out[str(k)] = clampi(n, 0, cap)
	return out


## 等级字典（经脉等级上限 MAX_LV）
func _decode_lv(s: String) -> Dictionary:
	return _decode_counts(s, MeridianScript.MAX_LV)


## 进账（死亡 / 通关结算都走这里），顺手落盘
func add_daoyun(n: int) -> int:
	if n <= 0:
		return 0
	daoyun += n
	daoyun_total += n
	save_cfg()
	return n


func spend_daoyun(n: int) -> bool:
	if n < 0 or daoyun < n:
		return false
	daoyun -= n
	save_cfg()
	return true


func mer_lv(id: String) -> int:
	return clampi(int(meridian_lv.get(id, 0)), 0, MeridianScript.MAX_LV)


## 升一级（够钱才升）；成功返回 true
func mer_up(id: String) -> bool:
	var cur := mer_lv(id)
	var c := MeridianScript.cost(id, cur)
	if c < 0 or daoyun < c:
		return false
	daoyun -= c
	meridian_lv[id] = cur + 1
	save_cfg()
	return true


## 洗点：清空全部等级，退回 70%（返回退了多少；没点过返回 0）
func mer_respec() -> int:
	var back := MeridianScript.respec_refund(meridian_lv)
	if back <= 0:
		return 0
	meridian_lv.clear()
	daoyun += back
	save_cfg()
	return back


# ---------------------------------------------------------------- R33c 丹房与跨局背包
## 背包里现在有几件
func pantry_total() -> int:
	var t := 0
	for k in pantry.keys():
		t += maxi(0, int(pantry[k]))
	return t


## 某个东西存了几件
func pantry_of(id: String) -> int:
	return maxi(0, int(pantry.get(id, 0)))


## 炼一份：扣道痕 + 进背包（两个动作必须一起成功，不能扣了钱没进账）
func pantry_add(id: String, n: int, cost: int = 0) -> bool:
	if n <= 0 or id == "":
		return false
	if cost < 0:
		return false
	if cost > 0 and daoyun < cost:
		return false
	if pantry_total() + n > AlchemyScript.PANTRY_CAP:
		return false
	if cost > 0:
		daoyun -= cost
	pantry[id] = pantry_of(id) + n
	save_cfg()
	return true


## 取走全部（开局注入快捷格用），返回一份副本并清空背包
func pantry_take_all() -> Dictionary:
	var out := pantry.duplicate()
	pantry.clear()
	save_cfg()
	return out


# ---------------------------------------------------------------- 虚拟按键布局
func _decode_offsets(s: String) -> Dictionary:
	var out := {}
	if s == "":
		return out
	var v = JSON.parse_string(s)
	if v is Dictionary:
		for k in v.keys():
			var a = v[k]
			if a is Array and a.size() >= 2:
				out[str(k)] = Vector2(float(a[0]), float(a[1]))
	return out


func _encode_offsets() -> String:
	var out := {}
	for k in touch_offsets.keys():
		var v: Vector2 = touch_offsets[k]
		if absf(v.x) < 0.5 and absf(v.y) < 0.5:
			continue
		out[str(k)] = [snappedf(v.x, 1.0), snappedf(v.y, 1.0)]
	return JSON.stringify(out)


# ---------------------------------------------------------------- R14 叙事「已见」
func _decode_seen(s: String) -> Dictionary:
	var out := {}
	if s == "":
		return out
	var v = JSON.parse_string(s)
	if v is Array:
		for k in v:
			out[str(k)] = true
	return out


func _encode_seen() -> String:
	return _encode_keys(seen_lines)


## R28：本地榜编解码（数组里是 {date, score, secs, dmg, hp}）
func _encode_board() -> String:
	return JSON.stringify(daily_board)


func _decode_board(raw: String) -> Array:
	if raw.strip_edges() == "":
		return []
	var parsed = JSON.parse_string(raw)
	if not (parsed is Array):
		return []
	var out := []
	for it in parsed:
		if not (it is Dictionary):
			continue
		out.append({
			"date": str(it.get("date", "")),
			"score": int(it.get("score", 0)),
			"secs": float(it.get("secs", 0.0)),
			"dmg": int(it.get("dmg", 0)),
			"hp": int(it.get("hp", 0)),
		})
	return out


## R28：提交一条破劫记录 → 返回名次（1 起；0 = 没进前 5）
## 同一天同分数视为同一条，不重复占位。
func push_daily_record(date_key: String, score: int, secs: float, dmg: int, hp: int) -> int:
	var rec := {"date": date_key, "score": score, "secs": secs, "dmg": dmg, "hp": hp}
	var idx := -1
	for i in daily_board.size():
		var it: Dictionary = daily_board[i]
		if str(it["date"]) == date_key and int(it["score"]) == score:
			idx = i
			break
	if idx >= 0:
		# 同日同分：留用时更短的那条
		if secs < float(daily_board[idx]["secs"]):
			daily_board[idx] = rec
	else:
		daily_board.append(rec)
	# 按分数降序、同分按用时升序
	daily_board.sort_custom(func(a, b):
		if int(a["score"]) != int(b["score"]):
			return int(a["score"]) > int(b["score"])
		return float(a["secs"]) < float(b["secs"]))
	if daily_board.size() > DAILY_BOARD_MAX:
		daily_board.resize(DAILY_BOARD_MAX)
	for i in daily_board.size():
		var it: Dictionary = daily_board[i]
		if str(it["date"]) == date_key and int(it["score"]) == score:
			return i + 1
	return 0


## R28：榜上最高分（无记录返回 0）
func best_daily_score() -> int:
	return int(daily_board[0]["score"]) if not daily_board.is_empty() else 0


## R16：把任意「key → true」字典编成 JSON 数组（碎片 / 自述共用）
func _encode_keys(d: Dictionary) -> String:
	var arr := []
	for k in d.keys():
		arr.append(str(k))
	return JSON.stringify(arr)


func has_seen_line(id: String) -> bool:
	return bool(seen_lines.get(id, false))


func mark_seen_line(id: String) -> void:
	if not bool(seen_lines.get(id, false)):
		seen_lines[id] = true
		save_cfg()


# ---------------------------------------------------------------- R16 残卷碎片
func has_fragment(id: String) -> bool:
	return bool(fragments_seen.get(id, false))


## 记下一条碎片（已记过就不重复写盘）
func mark_fragment(id: String) -> void:
	if id == "" or bool(fragments_seen.get(id, false)):
		return
	fragments_seen[id] = true
	save_cfg()


## 永久收集到的碎片总数（图鉴页显示 x/12）
func fragment_total() -> int:
	return fragments_seen.size()


## 已解锁的自述门槛（3 / 6 / 9 / 12）
func mark_self(need: int) -> void:
	var k := str(need)
	if bool(self_seen.get(k, false)):
		return
	self_seen[k] = true
	save_cfg()


func has_self(need: int) -> bool:
	return bool(self_seen.get(str(need), false))


func touch_off(action: String) -> Vector2:
	var v = touch_offsets.get(action, Vector2.ZERO)
	if v is Vector2:
		return v
	return Vector2.ZERO


func set_touch_off(action: String, off: Vector2) -> void:
	touch_offsets[action] = off


func reset_touch_layout() -> void:
	touch_offsets.clear()
	touch_scale = 1.0


## 把音量 / 全屏真正作用到引擎
func apply() -> void:
	var idx := AudioServer.get_bus_index("Master")
	if idx >= 0:
		var v := clampf(master, 0.0, 1.0) * clampf(sfx, 0.0, 1.0)
		AudioServer.set_bus_mute(idx, v <= 0.002)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(0.0015, v)))
	if DisplayServer.get_name() != "headless":
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want:
			DisplayServer.window_set_mode(want)
	changed.emit()


func shake_mul() -> float:
	return clampf(shake, 0.0, 1.5)


# ------------------------------------------------------------------ 存档
func slot_path(i: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, i]


func save_slot(i: int, data: Dictionary) -> bool:
	data["time"] = Time.get_datetime_string_from_system(false, true)
	data["stamp"] = Time.get_unix_time_from_system()
	var f := FileAccess.open(slot_path(i), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return true


func load_slot(i: int) -> Dictionary:
	if not has_slot(i):
		return {}
	var f := FileAccess.open(slot_path(i), FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var v = JSON.parse_string(txt)
	if v is Dictionary:
		return v
	return {}


func has_slot(i: int) -> bool:
	return FileAccess.file_exists(slot_path(i))


func slot_info(i: int) -> String:
	var d := load_slot(i)
	if d.is_empty():
		return "空"
	var lv := str(d.get("level_name", "镇 钟 廊"))
	var rm := int(d.get("room", 1))
	var hp := int(d.get("hp", 5))
	return "%s · 第 %d 间 · %d 血" % [lv, rm, hp]


func erase_slot(i: int) -> void:
	if has_slot(i):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(i)))
