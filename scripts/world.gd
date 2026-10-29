extends Node2D
## 单间房间竞技场（R10）
##
## 不再是横贯 16000 px 的横版地形，而是「一屏一间房」：
##   · 地板：一块向后收拢的梯形地面（200..1100 × 510..760），带透视砖缝与深度横线
##   · 后墙：地板后沿立起一整面砖墙（含壁龛与拱门）
##   · 侧墙：左右各一道厚墙，把房间封住
##   · 四门：西 / 东 / 后 / 前，清场后开启；Boss 房四面禁制落下
##
## 换房不移动世界，只是把「这间房长什么样」换掉 —— 所以相机永远固定在一屏。

const SpaceScript := preload("res://scripts/space.gd")

## 静态尖刺（R10 已改为动态陷阱房，保留空数组兼容旧判定）
const SPIKES := []

const X0 := SpaceScript.ROOM_X0
const X1 := SpaceScript.ROOM_X1
const YF := SpaceScript.FLOOR_FAR_Y      # 510
const YN := SpaceScript.FLOOR_NEAR_Y     # 760
const CX := 650.0

## 门的判定边距
const DOOR_PAD := 30.0
## 闸门厚度
const GATE_H := 96.0

var extra_spikes: Array = []
var room_kind := "battle"
var gates := {"west": true, "east": true, "north": true, "south": true}
var doors := {"west": false, "east": false, "north": false, "south": false}

## R15 环境叙事：房间类型决定的静物（刻字 / 旧兵器 / 残灯 / 骸骨 / 受害者残影 / 负匣人）
var env_tier := 0          # 0 = 上排（偏里）  1 = 下排（偏外）
var env_level := 0
var pseudo_floor := false  # 关卡三：伪上下层（上排铁棺 / 下排铁链）
var guide_alpha := 0.0     # Boss 房「残影引导者」的可见度（0 = 不画）

var _t := 0.0
var _debris: Array = []


func _ready() -> void:
	_build_debris()


func build(_unused: Variant = null) -> void:
	_build_debris()
	queue_redraw()


func set_room(kind: String) -> void:
	room_kind = kind
	queue_redraw()


## R15：一并把「这一间该摆什么静物」告诉世界层
func set_room_env(kind: String, tier: int, level: int) -> void:
	room_kind = kind
	env_tier = clampi(tier, 0, 1)
	env_level = clampi(level, 0, 3)
	# 伪楼层只在关卡三（玄铁墓道）成立
	pseudo_floor = env_level == 2
	guide_alpha = 0.0
	queue_redraw()


func set_guide_alpha(a: float) -> void:
	guide_alpha = clampf(a, 0.0, 1.0)
	queue_redraw()


## 设置四个方向「有没有邻居」以及「闸门是否落下」
func set_doors(door_map: Dictionary, gate_map: Dictionary) -> void:
	for k in doors.keys():
		doors[k] = bool(door_map.get(k, false))
	for k in gates.keys():
		gates[k] = bool(gate_map.get(k, true))
	queue_redraw()


func bounds() -> Rect2:
	return Rect2(X0 - 60.0, YF - 220.0, (X1 - X0) + 120.0, (YN - YF) + 300.0)


func _build_debris() -> void:
	_debris.clear()
	var r := RandomNumberGenerator.new()
	r.seed = 20261026
	for i in 90:
		_debris.append({
			"x": r.randf_range(X0 + 16.0, X1 - 16.0),
			"y": r.randf_range(YF + 12.0, YN - 10.0),
			"r": r.randf_range(1.6, 4.6),
		})


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


# ------------------------------------------------------------------ 绘制
func _draw() -> void:
	_draw_back_wall()
	_draw_pseudo_floor()
	_draw_floor()
	_draw_pseudo_ground()
	_draw_side_walls()
	_draw_debris()
	_draw_spikes()
	_draw_doors()
	_draw_torches()
	_draw_env()
	_draw_guide()


## 后墙：地板后沿往上立起来的一整面砖墙
func _draw_back_wall() -> void:
	var top := YF - 196.0
	# 主体渐变：上暗下略亮（靠近地板处有一点地面反光）
	var bands := 10
	for i in bands:
		var f0 := float(i) / float(bands)
		var f1 := float(i + 1) / float(bands)
		var y0 := lerpf(top, YF, f0)
		var y1 := lerpf(top, YF, f1)
		var c := Color(0.016, 0.022, 0.030).lerp(Color(0.043, 0.058, 0.076), f0)
		draw_rect(Rect2(X0 - 30.0, y0, (X1 - X0) + 60.0, y1 - y0 + 1.0), c)
	# 砖缝
	var row_h := 26.0
	var y := top + row_h
	var row := 0
	while y < YF:
		draw_line(Vector2(X0 - 30.0, y), Vector2(X1 + 30.0, y), Color(0.10, 0.14, 0.18, 0.34), 1.0)
		var off := 0.0 if row % 2 == 0 else 52.0
		var bx := X0 - 30.0 + off
		while bx < X1 + 30.0:
			draw_line(Vector2(bx, y - row_h), Vector2(bx, y), Color(0.10, 0.14, 0.18, 0.22), 1.0)
			bx += 104.0
		y += row_h
		row += 1
	# 壁龛（三处暗洞）
	for i in 3:
		var nx := CX + (float(i) - 1.0) * 300.0
		draw_rect(Rect2(nx - 46.0, YF - 132.0, 92.0, 120.0), Color(0.008, 0.012, 0.017, 0.92))
		draw_line(Vector2(nx - 46.0, YF - 132.0), Vector2(nx + 46.0, YF - 132.0),
			Color(0.16, 0.21, 0.27, 0.55), 2.0)
	# 与地板交界的暗缝
	draw_line(Vector2(X0 - 30.0, YF), Vector2(X1 + 30.0, YF), Color(0.0, 0.0, 0.0, 0.75), 4.0)


## 地板：向后退的透视地面
func _draw_floor() -> void:
	# 12 条由近到远的渐变带
	var bands := 12
	for i in bands:
		var f0 := float(i) / float(bands)
		var f1 := float(i + 1) / float(bands)
		var y0 := lerpf(YN, YF, f0)
		var y1 := lerpf(YN, YF, f1)
		var c := Color(0.058, 0.078, 0.100).lerp(Color(0.017, 0.023, 0.031), f0)
		draw_rect(Rect2(X0, y1, X1 - X0, y0 - y1 + 1.0), c)

	# 透视砖缝：越靠后越向画面中心收拢
	var step := 100.0
	var sx := X0
	while sx <= X1 + 0.5:
		var bx := lerpf(sx, CX, 0.42)
		draw_line(Vector2(sx, YN), Vector2(bx, YF), Color(0.42, 0.58, 0.74, 0.14), 1.6)
		sx += step

	# 深度横线（前疏后密，模拟透视）
	for k in range(1, 7):
		var f := float(k) / 7.0
		var yy := lerpf(YN, YF, f * f * 0.55 + f * 0.45)
		draw_line(Vector2(X0, yy), Vector2(X1, yy), Color(0.36, 0.50, 0.64, 0.10), 1.2)

	# 门口的地面光带（哪边有门就在哪边亮一道）
	if bool(doors.get("west", false)):
		draw_rect(Rect2(X0, YN - 96.0, 54.0, 96.0), Color(0.30, 0.52, 0.72, 0.10))
	if bool(doors.get("east", false)):
		draw_rect(Rect2(X1 - 54.0, YN - 96.0, 54.0, 96.0), Color(0.30, 0.52, 0.72, 0.10))
	if bool(doors.get("north", false)):
		draw_rect(Rect2(CX - 74.0, YF, 148.0, 54.0), Color(0.30, 0.52, 0.72, 0.12))
	if bool(doors.get("south", false)):
		draw_rect(Rect2(CX - 74.0, YN - 40.0, 148.0, 40.0), Color(0.30, 0.52, 0.72, 0.10))

	# 前缘高光 + 房间左右暗边
	draw_line(Vector2(X0, YN), Vector2(X1, YN), Color(0.44, 0.60, 0.76, 0.34), 2.0)
	draw_rect(Rect2(X0, YF, 16.0, YN - YF), Color(0.0, 0.0, 0.0, 0.34))
	draw_rect(Rect2(X1 - 16.0, YF, 16.0, YN - YF), Color(0.0, 0.0, 0.0, 0.34))


## 左右两道厚墙
func _draw_side_walls() -> void:
	_wall_strip(X0 - 34.0, X0, false)
	_wall_strip(X1, X1 + 34.0, true)


func _wall_strip(a: float, b: float, flip: bool) -> void:
	var bands := 6
	for i in bands:
		var f0 := float(i) / float(bands)
		var f1 := float(i + 1) / float(bands)
		var y0 := lerpf(YF - 196.0, YN, f0)
		var y1 := lerpf(YF - 196.0, YN, f1)
		var c := Color(0.030, 0.040, 0.052).lerp(Color(0.014, 0.019, 0.025), f0)
		draw_rect(Rect2(a, y0, b - a, y1 - y0 + 1.0), c)
	# 内侧受光边
	var inner := b if flip else a
	draw_line(Vector2(inner, YF - 196.0), Vector2(inner, YN), Color(0.30, 0.42, 0.56, 0.35), 2.0)
	# 外侧压暗
	var outer := a if flip else b
	draw_line(Vector2(outer, YF - 196.0), Vector2(outer, YN), Color(0.0, 0.0, 0.0, 0.7), 3.0)
	# 竖向砌缝
	var y := YF - 170.0
	while y < YN:
		draw_line(Vector2(a, y), Vector2(b, y), Color(0.09, 0.12, 0.16, 0.30), 1.0)
		y += 34.0


func _draw_debris() -> void:
	for d in _debris:
		var p := Vector2(float(d["x"]), float(d["y"]))
		var z := SpaceScript.depth_of(p.y)
		var a := lerpf(0.50, 0.16, z)
		var rr: float = float(d["r"]) * SpaceScript.scale_of(z)
		draw_circle(p + Vector2(0, -rr * 0.4), rr, Color(0.17, 0.22, 0.28, a))
		draw_arc(p + Vector2(0, -rr * 0.4), rr, PI, TAU, 8, Color(0.34, 0.48, 0.62, a * 0.6), 1.0, true)


func _draw_spikes() -> void:
	for s in extra_spikes:
		var r: Rect2 = s
		draw_rect(Rect2(r.position.x, r.position.y + r.size.y - 8.0, r.size.x, 8.0),
			Color(0.06, 0.07, 0.09, 0.9))
		var n := int(r.size.x / 18.0)
		for i in n:
			var sx := r.position.x + 9.0 + float(i) * 18.0
			var tip := Vector2(sx, r.position.y - 16.0)
			draw_colored_polygon(PackedVector2Array([
				Vector2(sx - 8.0, r.position.y + r.size.y - 6.0),
				tip,
				Vector2(sx + 8.0, r.position.y + r.size.y - 6.0),
			]), Color(0.34, 0.38, 0.44))
			draw_line(tip, Vector2(sx - 8.0, r.position.y + r.size.y - 6.0),
				Color(0.55, 0.62, 0.70, 0.7), 1.0)


## 四向门 + 闸门
func _draw_doors() -> void:
	_door_slot("west", Rect2(X0 - 34.0, 604.0, 34.0, GATE_H))
	_door_slot("east", Rect2(X1, 604.0, 34.0, GATE_H))
	_door_slot("north", Rect2(CX - 62.0, YF - 108.0, 124.0, 108.0))
	_door_slot("south", Rect2(CX - 62.0, YN - 26.0, 124.0, 26.0))


func _door_slot(key: String, r: Rect2) -> void:
	if not bool(doors.get(key, false)):
		# 没有邻居：画成实心墙（此处无路）
		draw_rect(r, Color(0.020, 0.026, 0.034, 0.96))
		draw_line(r.position, Vector2(r.end.x, r.position.y), Color(0.10, 0.13, 0.17, 0.5), 1.0)
		return
	var open := not bool(gates.get(key, true))
	# 门洞
	draw_rect(r, Color(0.006, 0.010, 0.015, 0.95))
	var glow := 0.30 + 0.10 * sin(_t * 2.2)
	if open:
		glow = 0.55 + 0.16 * sin(_t * 3.0)
	draw_rect(r, Color(0.28, 0.52, 0.78, glow * 0.30))
	# 门框
	draw_line(r.position, Vector2(r.end.x, r.position.y), Color(0.26, 0.36, 0.48, 0.7), 2.0)
	draw_line(Vector2(r.position.x, r.end.y), r.end, Color(0.26, 0.36, 0.48, 0.7), 2.0)
	draw_line(r.position, Vector2(r.position.x, r.end.y), Color(0.26, 0.36, 0.48, 0.7), 2.0)
	draw_line(Vector2(r.end.x, r.position.y), r.end, Color(0.26, 0.36, 0.48, 0.7), 2.0)
	if not open:
		# 闸门：横向石条 + 红色符纹
		var bars := 5
		for i in bars:
			var f0 := float(i) / float(bars)
			var y0 := r.position.y + r.size.y * f0
			draw_rect(Rect2(r.position.x, y0 + 2.0, r.size.x, r.size.y / float(bars) - 4.0),
				Color(0.11, 0.13, 0.16, 0.98))
			draw_line(Vector2(r.position.x + 2.0, y0 + 3.0),
				Vector2(r.end.x - 2.0, y0 + 3.0), Color(0.24, 0.28, 0.34, 0.8), 1.0)
		var mid := r.get_center()
		draw_arc(mid, minf(r.size.x, r.size.y) * 0.28, 0.0, TAU, 16,
			Color(0.95, 0.28, 0.32, 0.55 + 0.25 * sin(_t * 5.0)), 2.0, true)


func _draw_torches() -> void:
	var spots := [
		Vector2(X0 - 16.0, YF - 150.0),
		Vector2(X1 + 16.0, YF - 150.0),
	]
	for i in spots.size():
		var p: Vector2 = spots[i]
		var fl := 0.7 + 0.3 * sin(_t * 9.0 + float(i) * 2.1) + 0.12 * sin(_t * 21.0 + float(i))
		# 支架
		draw_rect(Rect2(p.x - 3.0, p.y, 6.0, 26.0), Color(0.18, 0.20, 0.24))
		# 光晕
		draw_circle(p + Vector2(0, -6.0), 26.0 * fl, Color(1.0, 0.72, 0.38, 0.07))
		draw_circle(p + Vector2(0, -6.0), 12.0 * fl, Color(1.0, 0.78, 0.42, 0.16))
		# 火苗
		draw_colored_polygon(PackedVector2Array([
			p + Vector2(-5.0, -2.0),
			p + Vector2(0, -18.0 - 6.0 * fl),
			p + Vector2(5.0, -2.0),
		]), Color(1.0, 0.86, 0.52, 0.92))
		draw_circle(p + Vector2(0, -6.0), 3.4, Color(1.0, 0.97, 0.82))


# ------------------------------------------------------------------ R15 环境叙事
## 关卡三的伪上下层（上排 / 偏里）：后墙立两具横置铁棺 —— 让人读成「上面还压着一层」
## 只是「画」，不改任何判定 —— 用视觉错位把单层网格读成两层
func _draw_pseudo_floor() -> void:
	if not pseudo_floor or env_tier != 0:
		return
	for i in 2:
		var cx := CX + (float(i) - 0.5) * 420.0
		var top := YF - 150.0
		var w := 210.0
		var h := 76.0
		var r := Rect2(cx - w * 0.5, top, w, h)
		# 棺下的贴墙阴影，把它「压」在砖面上而不是浮着
		draw_rect(Rect2(r.position.x - 8.0, r.end.y - 4.0, w + 16.0, 12.0),
			Color(0.0, 0.0, 0.0, 0.45))
		draw_rect(r, Color(0.045, 0.052, 0.062, 0.96))
		draw_rect(r, Color(0.16, 0.19, 0.24, 0.55), false, 2.0)
		# 棺盖中缝
		draw_line(Vector2(r.position.x + 8.0, r.position.y + h * 0.5),
			Vector2(r.end.x - 8.0, r.position.y + h * 0.5), Color(0.10, 0.12, 0.15, 0.9), 2.0)
		# 铆钉
		for k in 5:
			var px := r.position.x + 20.0 + float(k) * (w - 40.0) / 4.0
			draw_circle(Vector2(px, r.position.y + 8.0), 2.2, Color(0.30, 0.34, 0.40, 0.75))
			draw_circle(Vector2(px, r.end.y - 8.0), 2.2, Color(0.30, 0.34, 0.40, 0.75))
		# 缝隙里透出的一点磷光（有两具「还醒着」的东西躺在里面）
		var gl := 0.20 + 0.12 * sin(_t * 1.6 + float(i) * 2.0)
		draw_rect(Rect2(r.position.x + 12.0, r.position.y + h * 0.5 - 6.0, w - 24.0, 12.0),
			Color(0.30, 0.80, 0.56, gl * 0.12))
		draw_rect(Rect2(r.position.x + 12.0, r.position.y + h * 0.5 - 1.5, w - 24.0, 3.0),
			Color(0.46, 0.90, 0.66, gl))


## 关卡三的伪上下层（下排 / 偏外）：近处地面堆着断铁链，链头朝画面外垂下去
## 必须画在 _draw_floor 之后，否则整片会被地板盖掉
func _draw_pseudo_ground() -> void:
	if not pseudo_floor or env_tier != 1:
		return
	for i in 5:
		var bx := X0 + 108.0 + float(i) * 190.0
		var by := YN - 56.0 + float((i * 7) % 5) * 8.0
		var flip := 1.0 if i % 2 == 0 else -1.0   # 相邻两堆方向相反，不然像一排装饰
		# 地面投影
		draw_circle(Vector2(bx + 34.0, by + 12.0), 30.0, Color(0.0, 0.0, 0.0, 0.32))
		# 散落的一串链节：环与环交叠才读得出「链」，间距比直径小
		for k in 5:
			var rr := 10.5 - float(k) * 1.2
			var lx := bx + float(k) * 12.0 * flip
			var ly := by - float(k) * 2.2 + sin(float(k) * 1.9 + float(i)) * 2.2
			draw_arc(Vector2(lx, ly), rr, 0.0, TAU, 14, Color(0.075, 0.095, 0.125, 0.98), 4.4, true)
			draw_arc(Vector2(lx, ly), rr + 1.5, 0.0, TAU, 14, Color(0.28, 0.35, 0.44, 0.16), 1.1, true)
		# 断口：一截链头翘起来，指向画面外
		draw_line(Vector2(bx + 62.0 * flip, by - 6.0), Vector2(bx + 80.0 * flip, by - 26.0),
			Color(0.09, 0.115, 0.15, 0.95), 3.4, true)
		draw_arc(Vector2(bx + 85.0 * flip, by - 32.0), 8.0, 0.0, TAU, 14,
			Color(0.075, 0.095, 0.125, 0.98), 3.6, true)
		# 两三节掉在旁边的散链
		for k in 2:
			draw_arc(Vector2(bx + 108.0 * flip + float(k) * 14.0, by + 16.0 - float(k) * 5.0), 6.5,
				0.0, TAU, 12, Color(0.07, 0.09, 0.115, 0.9), 3.0, true)


## 按房间类型摆静物：让每一间「讲一句环境台词」
func _draw_env() -> void:
	match room_kind:
		"start":
			_draw_env_start()
		"chest":
			_draw_env_skeleton(Vector2(CX + 196.0, 672.0), 0.85)
		"trap":
			_draw_env_victim(Vector2(CX - 210.0, 648.0))
		"shop":
			_draw_env_merchant(Vector2(CX + 214.0, 668.0))


## 起始房：墙上刻字 + 斜靠的断剑 + 地上将灭的残灯
func _draw_env_start() -> void:
	# 刻字：后墙上一排竖刻痕（读作「很多人在这里记过数」）。
	# 刻意落在两个壁龛之间的实心砖面上 —— 画在壁龛黑洞里等于白画。
	# 高度用一组「没有规律」的固定值，避免读成柱状图。
	var gx := CX - 152.0
	var gy := YF - 62.0
	var hs := [26.0, 15.0, 33.0, 21.0, 38.0, 18.0, 29.0]
	var dys := [0.0, 4.0, -2.0, 2.0, -3.0, 5.0, 0.0]
	for i in 7:
		var xx := gx + float(i) * 11.0 + float((i * 3) % 2)
		var y0 := gy + float(dys[i])
		var h: float = float(hs[i])
		# 先压一道暗槽，再在左侧补一道亮边 —— 两色才读得出「凿进去」
		draw_line(Vector2(xx, y0), Vector2(xx, y0 - h), Color(0.05, 0.07, 0.09, 0.85), 2.8)
		draw_line(Vector2(xx - 1.4, y0 - 1.0), Vector2(xx - 1.4, y0 - h + 1.0),
			Color(0.38, 0.44, 0.51, 0.60), 1.5)
	draw_line(Vector2(gx - 8.0, gy + 8.0), Vector2(gx + 82.0, gy + 8.0),
		Color(0.30, 0.36, 0.42, 0.42), 1.6)

	# 旧兵器：一柄断了尖的剑靠在地上（剑柄着地，剑身斜指向上）
	var b := Vector2(CX - 206.0, 706.0)
	var dir := Vector2(0.26, -1.0).normalized()
	var side := Vector2(-dir.y, dir.x)
	var top := b + dir * 84.0
	# 地面投影
	draw_colored_polygon(PackedVector2Array([
		b + Vector2(-14.0, 2.0), b + Vector2(16.0, 6.0),
		b + Vector2(30.0, 14.0), b + Vector2(-4.0, 11.0),
	]), Color(0.0, 0.0, 0.0, 0.42))
	# 剑身：一条向上收窄的多边形
	draw_colored_polygon(PackedVector2Array([
		b + dir * 22.0 + side * 4.6, top + side * 2.4,
		top - side * 2.4, b + dir * 22.0 - side * 4.6,
	]), Color(0.44, 0.50, 0.58, 0.94))
	# 刃口高光（只在一边，暗示受光方向）
	draw_line(b + dir * 24.0 + side * 3.6, top + side * 1.6,
		Color(0.74, 0.82, 0.92, 0.50), 1.2, true)
	# 断口：斜切的一道亮线
	draw_line(top + side * 2.4, top - side * 2.4, Color(0.80, 0.86, 0.94, 0.72), 1.6)
	# 护手
	var g := b + dir * 20.0
	draw_line(g + side * 16.0, g - side * 16.0, Color(0.34, 0.30, 0.26, 0.95), 4.0, true)
	# 剑柄 + 柄头
	draw_line(b + dir * 4.0, g, Color(0.22, 0.18, 0.15, 0.95), 4.4, true)
	draw_circle(b + dir * 2.0, 4.4, Color(0.28, 0.24, 0.20, 0.95))
	# 断掉的半截躺在旁边
	var t2 := b + Vector2(46.0, 12.0)
	draw_line(t2, t2 + Vector2(38.0, -11.0), Color(0.34, 0.40, 0.47, 0.85), 4.2, true)
	draw_line(t2 + Vector2(2.0, -2.0), t2 + Vector2(36.0, -12.0),
		Color(0.62, 0.70, 0.80, 0.40), 1.2, true)

	# 残灯：石台 + 灯碗 + 将灭的火苗
	var lp := Vector2(CX + 232.0, 700.0)
	var fl := 0.55 + 0.45 * sin(_t * 7.0) * sin(_t * 2.3)
	# 地面光池：用几层同心圆伪造径向衰减，单圈会看出硬边
	for k in 5:
		var rr := 44.0 - float(k) * 8.0
		draw_circle(lp + Vector2(0, 18.0), rr * (0.88 + 0.12 * fl),
			Color(1.0, 0.60, 0.24, 0.012 + 0.007 * float(k) + 0.005 * fl))
	# 石台
	draw_colored_polygon(PackedVector2Array([
		lp + Vector2(-11.0, 20.0), lp + Vector2(-7.0, -2.0),
		lp + Vector2(7.0, -2.0), lp + Vector2(11.0, 20.0),
	]), Color(0.11, 0.12, 0.14, 0.98))
	draw_line(lp + Vector2(-11.0, 20.0), lp + Vector2(-7.0, -2.0),
		Color(0.22, 0.24, 0.27, 0.55), 1.2)
	# 灯碗
	draw_arc(lp + Vector2(0, -2.0), 9.0, PI, TAU, 14, Color(0.20, 0.18, 0.15, 0.98), 3.2, true)
	# 光晕
	draw_circle(lp + Vector2(0, -8.0), 34.0 * fl, Color(1.0, 0.68, 0.32, 0.055))
	draw_circle(lp + Vector2(0, -10.0), 16.0 * fl, Color(1.0, 0.74, 0.40, 0.13))
	# 火苗（尖头向上，长度随呼吸变化）
	var fh := 10.0 + 7.0 * fl
	draw_colored_polygon(PackedVector2Array([
		lp + Vector2(-3.4, -6.0), lp + Vector2(0.6, -6.0 - fh), lp + Vector2(4.0, -6.0),
	]), Color(1.0, 0.86, 0.52, 0.55 + 0.35 * fl))
	draw_circle(lp + Vector2(0, -10.0), 2.4, Color(1.0, 0.96, 0.80, 0.75))


## 宝箱房：旁边坐着一具骸骨（腿伸开、头低着 —— 开箱开到一半就死了）
func _draw_env_skeleton(pos: Vector2, a: float) -> void:
	var bone := Color(0.66, 0.64, 0.58, 0.72 * a)
	var dark := Color(0.06, 0.07, 0.09, 0.9 * a)
	# 影子
	draw_circle(pos + Vector2(6.0, 20.0), 26.0, dark)
	# 头骨
	draw_circle(pos + Vector2(0, -14.0), 9.0, bone)
	draw_circle(pos + Vector2(-3.0, -16.0), 2.0, dark)
	draw_circle(pos + Vector2(3.0, -16.0), 2.0, dark)
	# 脊柱 + 肋骨
	draw_line(pos + Vector2(0, -5.0), pos + Vector2(0, 14.0), bone, 3.0, true)
	for i in 3:
		var yy := pos.y + 1.0 + float(i) * 5.0
		draw_arc(Vector2(pos.x, yy), 8.0 - float(i), 0.0, PI, 8, bone, 1.8, true)
	# 腿（伸在地上）
	draw_line(pos + Vector2(0, 14.0), pos + Vector2(-20.0, 22.0), bone, 3.0, true)
	draw_line(pos + Vector2(0, 14.0), pos + Vector2(20.0, 24.0), bone, 3.0, true)
	# 垂着的手
	draw_line(pos + Vector2(-5.0, -2.0), pos + Vector2(-16.0, 12.0), bone, 2.4, true)
	draw_line(pos + Vector2(5.0, -2.0), pos + Vector2(15.0, 11.0), bone, 2.4, true)


## 陷阱房：受害者的残影（半透明、缓慢上下浮动 —— 一直踩在同一个地方）
func _draw_env_victim(pos: Vector2) -> void:
	var bob := sin(_t * 1.4) * 4.0
	var a := 0.16 + 0.08 * sin(_t * 1.9)
	var c := Color(0.62, 0.86, 1.0, a)
	var p := pos + Vector2(0, bob)
	# 脚下：还留着的那一小片暗痕
	draw_circle(p + Vector2(0, 18.0), 20.0, Color(0.35, 0.55, 0.75, a * 0.42))
	# 身体（肩宽腰窄，微微前倾）
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(-12.0, 14.0), p + Vector2(-10.0, -10.0), p + Vector2(-6.0, -20.0),
		p + Vector2(5.0, -20.0), p + Vector2(10.0, -10.0), p + Vector2(11.0, 14.0),
	]), c)
	# 垂着的两条手臂
	draw_line(p + Vector2(-10.0, -10.0), p + Vector2(-15.0, 8.0),
		Color(c.r, c.g, c.b, a * 1.15), 3.0, true)
	draw_line(p + Vector2(10.0, -10.0), p + Vector2(15.0, 9.0),
		Color(c.r, c.g, c.b, a * 1.15), 3.0, true)
	# 低着的头
	draw_circle(p + Vector2(0, -26.0), 6.5, Color(c.r, c.g, c.b, a * 1.5))
	# 脚下拖出的一点残雾
	draw_circle(p + Vector2(0, 22.0), 16.0, Color(c.r, c.g, c.b, a * 0.26))


## 商人房：负匣人 —— 一个背着大匣子的剪影，站在阴影里
func _draw_env_merchant(pos: Vector2) -> void:
	var body := Color(0.035, 0.045, 0.060, 0.97)
	var rim := Color(0.40, 0.48, 0.58, 0.60)
	# 影子
	draw_circle(pos + Vector2(4.0, 22.0), 26.0, Color(0.0, 0.0, 0.0, 0.55))
	# 背上的匣子
	var box := Rect2(pos.x - 31.0, pos.y - 46.0, 36.0, 52.0)
	draw_rect(box, body)
	draw_rect(box, rim, false, 1.4)
	draw_line(Vector2(box.position.x + 4.0, box.get_center().y),
		Vector2(box.end.x - 4.0, box.get_center().y), rim, 1.2)
	# 匣子上的铜扣
	draw_circle(Vector2(box.get_center().x, box.get_center().y - 10.0), 2.0,
		Color(0.62, 0.50, 0.28, 0.65))
	# 人（斗篷）
	var cloak := PackedVector2Array([
		pos + Vector2(-13.0, 24.0), pos + Vector2(-10.0, -16.0), pos + Vector2(-5.0, -30.0),
		pos + Vector2(6.0, -30.0), pos + Vector2(11.0, -16.0), pos + Vector2(13.0, 24.0),
	])
	draw_colored_polygon(cloak, body)
	# 斗篷的轮廓光：身体几乎全黑，没有这条边就和地面糊在一起了
	draw_polyline(PackedVector2Array([
		pos + Vector2(13.0, 24.0), pos + Vector2(11.0, -16.0),
		pos + Vector2(6.0, -30.0),
	]), rim, 1.6, true)
	draw_line(pos + Vector2(-13.0, 24.0), pos + Vector2(-10.0, -16.0),
		Color(rim.r, rim.g, rim.b, rim.a * 0.45), 1.2, true)
	# 兜帽下的两点光
	draw_circle(pos + Vector2(-3.5, -22.0), 2.0, Color(1.0, 0.78, 0.42, 0.80))
	draw_circle(pos + Vector2(3.5, -22.0), 2.0, Color(1.0, 0.78, 0.42, 0.80))
	# 手杖
	draw_line(pos + Vector2(15.0, 24.0), pos + Vector2(17.0, -26.0),
		Color(0.30, 0.25, 0.19, 0.95), 2.6)
	draw_circle(pos + Vector2(17.0, -28.0), 2.6, Color(0.44, 0.36, 0.26, 0.85))


## Boss 房「残影引导者」：站在后门前的半透明人形，给一句方向暗示
func _draw_guide() -> void:
	if guide_alpha <= 0.01:
		return
	var a := guide_alpha * (0.30 + 0.10 * sin(_t * 2.6))
	var p := Vector2(CX, YF + 26.0)
	var c := Color(0.70, 0.90, 1.0, a)
	# 脚下光晕
	draw_circle(p + Vector2(0, 14.0), 30.0, Color(0.55, 0.82, 1.0, a * 0.22))
	# 身形
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(-11.0, 16.0), p + Vector2(-9.0, -16.0), p + Vector2(-3.0, -26.0),
		p + Vector2(4.0, -26.0), p + Vector2(10.0, -16.0), p + Vector2(12.0, 16.0),
	]), c)
	draw_circle(p + Vector2(0, -33.0), 7.0, Color(c.r, c.g, c.b, a * 1.6))
	# 手里提着的一把刀（指向门）
	draw_line(p + Vector2(12.0, -8.0), p + Vector2(30.0, -18.0),
		Color(0.85, 0.92, 1.0, a * 1.2), 2.2, true)
