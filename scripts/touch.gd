extends CanvasLayer
## 触屏层（R10）
##
## 左边：**无限制 360 度移动轮盘**（不是按键式方向键）。
##   · 手指按在轮盘区域任意位置 → 以落点为圆心浮出摇杆，拖多远就多大推力
##   · 输出一个 -1..1 的平面向量到 Game.stick（x = 左右，y = 里外）
##   · 玩家脚本里摇杆优先、键盘兜底，所以同一个角色两边都能操作
## 右边：刀 / 冲 / 挡 / 蓄 / 疗 五颗动作键 + 右上角 Ⅱ 暂停
## 右上角的「设置」与「换武器」由 HUD 常驻绘制，点按走 game.top_hit()

var game: Node = null
var font: Font
## 由 --touch 强制显示（截图 / 调试用）。为 true 时设置里的开关不再覆盖它。
var forced := false
## 这台设备能不能触屏操作（移动端 / 触摸屏 / --touch 强制）。
## 与 visible 分开：visible 只管「画不画按键」，能不能收触摸由 can_touch 决定。
var can_touch := false
var _canvas: Control
var _touches := {}      # touch_index -> action
var _held := {}         # action -> 按住它的 touch 数量
var _oneshot := {}      # action -> 剩余帧数（点一下就松）
var _pulse := {}        # action -> 按下动画强度
var _t := 0.0

## 摇杆状态
var _stick_idx := -1
var _stick_base := Vector2.ZERO
var _stick_vec := Vector2.ZERO

## 布局编辑模式
var edit := false
var _drag := ""
var _drag_off := Vector2.ZERO

## 布局编辑态的「完成」按钮（固定位置，不参与拖动）
const BTN_EDIT_DONE := Rect2(520, 650, 240, 54)

## 轮盘默认圆心与半径（可在设置里拖动 / 缩放）
const STICK := {"a": "stick", "x": 236.0, "y": 552.0, "r": 104.0, "t": ""}

const BUTTONS := [
	{"a": "attack", "x": 1116.0, "y": 556.0, "r": 62.0, "t": "刀"},
	{"a": "dash", "x": 984.0, "y": 468.0, "r": 46.0, "t": "冲"},
	{"a": "guard", "x": 1228.0, "y": 470.0, "r": 46.0, "t": "挡"},
	{"a": "heavy", "x": 1044.0, "y": 644.0, "r": 44.0, "t": "蓄"},
	{"a": "focus", "x": 1218.0, "y": 618.0, "r": 40.0, "t": "疗"},
	{"a": "pause", "x": 1088.0, "y": 38.0, "r": 25.0, "t": "Ⅱ"},
]

var _all: Array = []


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = load("res://fonts/NotoSansSC.ttf")
	forced = OS.get_cmdline_args().has("--touch") or OS.get_cmdline_user_args().has("--touch")
	can_touch = forced or OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	_all = [STICK]
	for b in BUTTONS:
		_all.append(b)
	_canvas = Control.new()
	_canvas.position = Vector2.ZERO
	_canvas.size = Vector2(1280, 720)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)
	visible = can_touch
	# 输入处理**始终打开**：既保证「藏起按键后还能点回来」，
	# 也保证 has_feature 判错时能靠真实触摸事件自愈（见 _input 第一段）。
	set_process_input(true)
	set_process(can_touch)


func set_shown(v: bool) -> void:
	visible = v
	set_process(v or can_touch)
	if not v:
		_clear_stick()


# ------------------------------------------------------------------ 布局
func _scale() -> float:
	if Cfg == null or not is_instance_valid(Cfg):
		return 1.0
	return clampf(Cfg.touch_scale, 0.7, 1.5)


func _center(b: Dictionary) -> Vector2:
	var c := Vector2(float(b["x"]), float(b["y"]))
	if Cfg != null and is_instance_valid(Cfg):
		c += Cfg.touch_off(str(b["a"]))
	return c


func _radius(b: Dictionary) -> float:
	return float(b["r"]) * _scale()


func set_edit(v: bool) -> void:
	edit = v
	_drag = ""
	_pulse.clear()
	if v:
		visible = true
		set_process_input(true)
		set_process(true)
		_clear_stick()


func _button_at(p: Vector2) -> Dictionary:
	for b in BUTTONS:
		if p.distance_to(_center(b)) <= _radius(b) * 1.16:
			return b
	return {}


## 轮盘热区：比画出来的圈大一圈，拇指压偏一点也能推
func _stick_zone(p: Vector2) -> bool:
	var c := _center(STICK)
	return p.distance_to(c) <= _radius(STICK) * 1.55


func _press(a: String) -> void:
	if _held.get(a, 0) == 0:
		Input.action_press(a)
	_pulse[a] = 1.0
	_held[a] = int(_held.get(a, 0)) + 1


func _release(a: String) -> void:
	var n := int(_held.get(a, 0)) - 1
	if n <= 0:
		_held.erase(a)
		Input.action_release(a)
	else:
		_held[a] = n


# ------------------------------------------------------------------ 摇杆
func _stick_down(idx: int, pos: Vector2) -> void:
	_stick_idx = idx
	# 浮动圆心：按下的地方就是圆心（限制在热区内，避免圆心跑太远）
	var c := _center(STICK)
	var off := pos - c
	var lim := _radius(STICK) * 0.55
	if off.length() > lim:
		off = off.normalized() * lim
	_stick_base = c + off
	_stick_vec = Vector2.ZERO
	_update_stick(pos)


func _update_stick(pos: Vector2) -> void:
	var r := _radius(STICK)
	var d := pos - _stick_base
	var len := d.length()
	var v := Vector2.ZERO
	if len > 3.0:
		# 死区 12%：手指微动不会让人漂
		var mag := clampf((len / r - 0.12) / 0.88, 0.0, 1.0)
		v = d.normalized() * mag
	_stick_vec = v
	if Game != null and is_instance_valid(Game):
		Game.stick = v
		Game.stick_active = true


func _clear_stick() -> void:
	_stick_idx = -1
	_stick_vec = Vector2.ZERO
	if Game != null and is_instance_valid(Game):
		Game.stick = Vector2.ZERO
		Game.stick_active = false


# ------------------------------------------------------------------ 输入
func _input(event: InputEvent) -> void:
	var is_touch := event is InputEventScreenTouch or event is InputEventScreenDrag
	# 自愈：只要真收到触摸事件，这台设备就是能触屏的。
	# 不依赖 has_feature("mobile")，避免导出配置判错时把玩家彻底锁死。
	if not can_touch:
		if not is_touch:
			return
		can_touch = true
		visible = true
		set_process(true)
		if Cfg != null and is_instance_valid(Cfg):
			Cfg.touch_ui = true
			Cfg.save_cfg()
	# 触屏设备上按键被藏起来时，任何一次点击都先把它叫回来
	if not visible:
		if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
			set_shown(true)
			if Cfg != null and is_instance_valid(Cfg):
				Cfg.touch_ui = true
				Cfg.save_cfg()
		return
	if event is InputEventScreenTouch:
		var ev := event as InputEventScreenTouch
		if ev.pressed:
			if edit:
				_edit_down(ev.index, ev.position)
			else:
				_on_touch_down(ev.index, ev.position)
		else:
			if edit:
				_edit_up(ev.index)
			else:
				_on_touch_up(ev.index)
	elif event is InputEventScreenDrag:
		var dr := event as InputEventScreenDrag
		if edit:
			_edit_drag(dr.index, dr.position)
			return
		if dr.index == _stick_idx:
			_update_stick(dr.position)
			return
		var cur: String = _touches.get(dr.index, "")
		var b := _button_at(dr.position)
		var next: String = b.get("a", "")
		if next != cur:
			if cur != "":
				_release(cur)
			if next != "":
				_press(next)
				_touches[dr.index] = next
			else:
				_touches.erase(dr.index)


# ------------------------------------------------------------------ 布局编辑
func _edit_down(idx: int, pos: Vector2) -> void:
	if BTN_EDIT_DONE.has_point(pos):
		if game != null and is_instance_valid(game):
			game.exit_touch_edit()
		return
	var b := _button_at(pos)
	if b.is_empty():
		if _stick_zone(pos):
			b = STICK
		else:
			return
	_drag = str(b["a"])
	_drag_off = _center(b) - pos
	_pulse[_drag] = 1.0


func _edit_drag(idx: int, pos: Vector2) -> void:
	if _drag == "":
		return
	var b := {}
	for it in _all:
		if str(it["a"]) == _drag:
			b = it
			break
	if b.is_empty():
		return
	var want := pos + _drag_off
	var base := Vector2(float(b["x"]), float(b["y"]))
	var off := want - base
	var r := _radius(b)
	off.x = clampf(off.x, -base.x + r + 4.0, 1276.0 - base.x - r)
	off.y = clampf(off.y, -base.y + r + 4.0, 716.0 - base.y - r)
	if Cfg != null and is_instance_valid(Cfg):
		Cfg.set_touch_off(_drag, off)
	_pulse[_drag] = 1.0


func _edit_up(idx: int) -> void:
	if _drag == "":
		return
	_drag = ""
	if Cfg != null and is_instance_valid(Cfg):
		Cfg.save_cfg()
	SFX.play("gate", 1.4, -14.0)


# ------------------------------------------------------------------ 常规触摸
func _on_touch_down(idx: int, pos: Vector2) -> void:
	var st := ""
	if game != null and is_instance_valid(game):
		st = str(game.state)
	if st == "title":
		if game != null and is_instance_valid(game) and game.title_hit(pos):
			return
		_tap("start")
		return
	if st == "dead" or st == "win":
		_tap("restart")
		return
	if st == "pause":
		if game != null and is_instance_valid(game) and game.pause_hit(pos):
			return
		_tap("pause")
		return
	if st == "setting":
		if game != null and is_instance_valid(game):
			game.setting_hit(pos)
		return
	if st == "weapon":
		if game != null and is_instance_valid(game):
			game.weapon_hit(pos)
		return
	if st == "branch":
		if game != null and is_instance_valid(game):
			game.branch_hit(pos)
		return
	if st == "event":
		if game != null and is_instance_valid(game):
			game.event_hit(pos)
		return
	if st == "reward" or st == "replace":
		if game != null and is_instance_valid(game):
			game.reward_hit(pos)
		return
	if st == "clear":
		if game != null and is_instance_valid(game):
			game.clear_hit(pos)
		return
	if st == "codex":
		if game != null and is_instance_valid(game):
			game.codex_hit(pos)
		return

	# R33a：经脉页 —— 点节点选中 / 再点升级，点底部按钮洗点 / 返回
	if st == "meridian":
		if game != null and is_instance_valid(game):
			game.mer_hit(pos)
		return
	if st == "play":
		# 右上角的设置 / 换武器 / 暂停优先
		if game != null and is_instance_valid(game) and game.top_hit(pos):
			return
		# R32a：左侧三个丹药格，点格子即服丹
		if game != null and is_instance_valid(game) and game.quick_hit(pos):
			return
		if _stick_zone(pos) and _stick_idx < 0:
			_stick_down(idx, pos)
			return
	var b := _button_at(pos)
	if b.is_empty():
		return
	var a: String = b["a"]
	_touches[idx] = a
	_press(a)


func _on_touch_up(idx: int) -> void:
	if idx == _stick_idx:
		_clear_stick()
		return
	var a: String = _touches.get(idx, "")
	if a == "":
		return
	_touches.erase(idx)
	_release(a)


## 点一下就走（start / restart / pause）
func _tap(a: String) -> void:
	if _oneshot.has(a):
		return
	Input.action_press(a)
	_pulse[a] = 1.0
	_oneshot[a] = 2


func _process(delta: float) -> void:
	_t += delta
	for a in _oneshot.keys():
		_oneshot[a] = int(_oneshot[a]) - 1
		if int(_oneshot[a]) <= 0:
			_oneshot.erase(a)
			Input.action_release(a)
	for a in _pulse.keys():
		_pulse[a] = maxf(0.0, float(_pulse[a]) - delta * 4.0)
	if _canvas:
		_canvas.queue_redraw()


func _on_draw() -> void:
	var c := _canvas
	if c == null:
		return
	var st := "play"
	if game != null and is_instance_valid(game):
		st = str(game.state)
	if not edit:
		if st != "play":
			return
	_draw_stick(c)
	for b in BUTTONS:
		if b["a"] == "pause":
			continue
		_draw_btn(c, b)
	_draw_btn(c, BUTTONS[5])
	if edit:
		_draw_edit_hint(c)


func _draw_stick(c: Control) -> void:
	var ctr := _center(STICK)
	var r := _radius(STICK)
	var act := _stick_idx >= 0
	var glow := 1.0 if act else 0.0
	# 底盘
	c.draw_circle(ctr, r, Color(0.10, 0.16, 0.22, 0.20 + 0.10 * glow))
	c.draw_arc(ctr, r, 0.0, TAU, 48, Color(0.66, 0.84, 1.0, 0.22 + 0.28 * glow), 2.0, true)
	c.draw_arc(ctr, r * 0.62, 0.0, TAU, 40, Color(0.66, 0.84, 1.0, 0.10), 1.2, true)
	# 十字刻度（提示这是 360 度，不是四个键）
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var a := ctr + Vector2(cos(ang), sin(ang)) * r * 0.86
		var b := ctr + Vector2(cos(ang), sin(ang)) * r * 0.97
		c.draw_line(a, b, Color(0.66, 0.84, 1.0, 0.16), 1.4)
	# 摇杆头
	var head := _stick_base + _stick_vec * r if act else ctr
	var hr := r * 0.42
	c.draw_circle(head, hr, Color(0.62, 0.82, 1.0, 0.22 + 0.20 * glow))
	c.draw_arc(head, hr, 0.0, TAU, 32, Color(0.78, 0.92, 1.0, 0.55 + 0.35 * glow), 2.4, true)
	c.draw_circle(head, hr * 0.34, Color(0.92, 0.98, 1.0, 0.55 + 0.35 * glow))
	if edit:
		c.draw_arc(ctr, r * 1.55, 0.0, TAU, 56, Color(1.0, 0.9, 0.6, 0.12), 1.0, true)
		var tip := "轮 盘"
		var ts := font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
		c.draw_string_outline(font, ctr + Vector2(-ts.x * 0.5, r + 26.0), tip,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color(0, 0, 0, 0.6))
		c.draw_string(font, ctr + Vector2(-ts.x * 0.5, r + 26.0), tip,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.92, 0.7))


func _draw_edit_hint(c: Control) -> void:
	# 半透明遮罩 + 十字参考线
	c.draw_rect(Rect2(0, 0, 1280, 720), Color(0.02, 0.03, 0.05, 0.42))
	for x in range(160, 1280, 160):
		c.draw_line(Vector2(x, 0), Vector2(x, 720), Color(0.55, 0.8, 1.0, 0.08), 1.0)
	for y in range(120, 720, 120):
		c.draw_line(Vector2(0, y), Vector2(1280, y), Color(0.55, 0.8, 1.0, 0.08), 1.0)
	var tip := "拖 动 轮 盘 / 按 键 到 顺 手 的 位 置"
	var sz := font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
	c.draw_string_outline(font, Vector2((1280.0 - sz.x) * 0.5, 66.0), tip,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 8, Color(0, 0, 0, 0.7))
	c.draw_string(font, Vector2((1280.0 - sz.x) * 0.5, 66.0), tip,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1.0, 0.94, 0.7))
	var tip2 := "大小用 ← → 调　·　按 Esc / 点右上 Ⅱ 退出并保存"
	var sz2 := font.get_string_size(tip2, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	c.draw_string_outline(font, Vector2((1280.0 - sz2.x) * 0.5, 96.0), tip2,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 6, Color(0, 0, 0, 0.7))
	c.draw_string(font, Vector2((1280.0 - sz2.x) * 0.5, 96.0), tip2,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.8, 0.9, 1.0))
	# 完成按钮
	var r := BTN_EDIT_DONE
	c.draw_rect(r, Color(0.10, 0.16, 0.22, 0.94))
	c.draw_line(r.position, Vector2(r.end.x, r.position.y), Color(1.0, 0.92, 0.6, 0.9), 2.0)
	c.draw_line(Vector2(r.end.x, r.position.y), r.end, Color(1.0, 0.92, 0.6, 0.9), 2.0)
	c.draw_line(r.end, Vector2(r.position.x, r.end.y), Color(1.0, 0.92, 0.6, 0.9), 2.0)
	c.draw_line(Vector2(r.position.x, r.end.y), r.position, Color(1.0, 0.92, 0.6, 0.9), 2.0)
	var dt := "完 成"
	var ds := font.get_string_size(dt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
	c.draw_string_outline(font, r.get_center() + Vector2(-ds.x * 0.5, 9.0), dt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24, 5, Color(0, 0, 0, 0.6))
	c.draw_string(font, r.get_center() + Vector2(-ds.x * 0.5, 9.0), dt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1.0, 0.96, 0.8))


func _draw_btn(c: Control, b: Dictionary) -> void:
	var a: String = b["a"]
	var ctr := _center(b)
	var r := _radius(b)
	var glow := float(_pulse.get(a, 0.0))
	var down: bool = int(_held.get(a, 0)) != 0

	var fill := Color(0.62, 0.82, 1.0, 0.10 + 0.20 * glow)
	var rim := Color(0.72, 0.88, 1.0, 0.30 + 0.45 * glow)
	match a:
		"attack":
			fill = Color(1.0, 0.86, 0.55, 0.10 + 0.22 * glow)
			rim = Color(1.0, 0.90, 0.62, 0.34 + 0.45 * glow)
		"heavy":
			fill = Color(1.0, 0.74, 0.42, 0.09 + 0.20 * glow)
			rim = Color(1.0, 0.82, 0.55, 0.30 + 0.42 * glow)
		"guard":
			fill = Color(0.55, 0.75, 1.0, 0.10 + 0.22 * glow)
			rim = Color(0.68, 0.86, 1.0, 0.34 + 0.45 * glow)
		"dash":
			fill = Color(0.85, 0.70, 1.0, 0.10 + 0.20 * glow)
			rim = Color(0.90, 0.80, 1.0, 0.32 + 0.45 * glow)
		"focus":
			fill = Color(0.55, 0.95, 1.0, 0.08 + 0.18 * glow)
			rim = Color(0.70, 0.97, 1.0, 0.28 + 0.40 * glow)

	if edit:
		fill = Color(fill.r, fill.g, fill.b, maxf(fill.a, 0.16))
		rim = Color(1.0, 0.92, 0.6, 0.75 if a == _drag else 0.45)
		c.draw_arc(ctr, r * 1.42, 0.0, TAU, 40, Color(1.0, 0.9, 0.6, 0.10), 1.0, true)

	c.draw_circle(ctr, r * (1.0 - 0.05 * glow), fill)
	c.draw_arc(ctr, r * (1.0 - 0.05 * glow), 0.0, TAU, 40, rim, 2.0, true)
	if down:
		c.draw_arc(ctr, r * 0.86, 0.0, TAU, 32, Color(1, 1, 1, 0.18), 1.5, true)

	var txt: String = b["t"]
	var sz := int(30.0 * _scale()) if txt.length() <= 1 else int(26.0 * _scale())
	if a == "pause":
		sz = int(20.0 * _scale())
	sz = maxi(11, sz)
	var col := Color(0.90, 0.96, 1.0, 0.72 + 0.25 * glow)
	if a == "attack":
		col = Color(1.0, 0.94, 0.78, 0.80 + 0.20 * glow)
	var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz)
	c.draw_string_outline(font, ctr + Vector2(-ts.x * 0.5, ts.y * 0.34), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, Color(0, 0, 0, 0.55))
	c.draw_string(font, ctr + Vector2(-ts.x * 0.5, ts.y * 0.34), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
