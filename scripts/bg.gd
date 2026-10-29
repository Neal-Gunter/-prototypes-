extends Node2D
## 洞穴背景：多层视差、雾气、浮游光尘。

var cam: Camera2D
var level_index := 0          # R14：当前关卡（0..3），决定「玄界之门」引力点强度
var _t := 0.0
var _arches: Array = []
var _pillars: Array = []
var _stalactites: Array = []
var _motes: Array = []
var _glows: Array = []


func _ready() -> void:
	z_index = -100
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261025

	# 远景拱门
	var x := -6000.0
	while x < 23000.0:
		_arches.append({
			"x": x,
			"w": rng.randf_range(520.0, 1500.0),
			"top": rng.randf_range(420.0, 1150.0),
		})
		x += rng.randf_range(700.0, 1500.0)

	# 中景石柱
	x = -5000.0
	while x < 21000.0:
		_pillars.append({
			"x": x,
			"w": rng.randf_range(180.0, 620.0),
			"top": rng.randf_range(200.0, 950.0),
			"lean": rng.randf_range(-40.0, 40.0),
		})
		x += rng.randf_range(520.0, 1200.0)

	# 顶部钟乳石
	x = -5000.0
	while x < 21000.0:
		_stalactites.append({
			"x": x,
			"w": rng.randf_range(90.0, 320.0),
			"h": rng.randf_range(160.0, 620.0),
		})
		x += rng.randf_range(300.0, 780.0)

	# 光尘
	for i in 190:
		_motes.append({
			"x": rng.randf_range(-2000.0, 18000.0),
			"y": rng.randf_range(-300.0, 1000.0),
			"r": rng.randf_range(0.8, 2.2),
			"sp": rng.randf_range(6.0, 26.0),
			"ph": rng.randf_range(0.0, TAU),
		})

	for i in 7:
		_glows.append({
			"x": rng.randf_range(-1200.0, 17000.0),
			"y": rng.randf_range(180.0, 620.0),
			"r": rng.randf_range(200.0, 380.0),
		})


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## R14：切换关卡 → 玄界之门引力点强度随之变化
func set_level(i: int) -> void:
	level_index = clampi(i, 0, 3)
	queue_redraw()


## 门影强度（0..1）。四关严格递增：细光缝 → 门环轮廓 → 占背景 1/3 → 门即场地
func gate_strength() -> float:
	match clampi(level_index, 0, 3):
		0:
			return 0.10
		1:
			return 0.24
		2:
			return 0.48
		_:
			return 0.80


func _p(wx: float, wy: float, f: float) -> Vector2:
	var cp := Vector2.ZERO
	if cam:
		cp = cam.global_position
	var vs := get_viewport_rect().size
	return Vector2((wx - cp.x) * f + vs.x * 0.5, (wy - cp.y) * f + vs.y * 0.5)


func _draw() -> void:
	var vs := get_viewport_rect().size

	# 天空渐变
	var bands := 28
	for i in bands:
		var f := float(i) / float(bands)
		var c := Color(0.055, 0.078, 0.108).lerp(Color(0.012, 0.018, 0.028), f)
		draw_rect(Rect2(0, vs.y * f, vs.x, vs.y / bands + 1.5), c)

	# 2.5D：地板后沿之外的一道后墙（视差 0.75），给纵深一个「底」
	_draw_back_wall(vs)

	# R14：玄界之门引力点（全程可见，越深越亮越大）
	_draw_gate_silhouette(vs)

	# 大范围柔光
	for g in _glows:
		var p := _p(g["x"], g["y"], 0.10)
		var r: float = g["r"]
		for k in range(6, 0, -1):
			var rr := r * (k / 6.0)
			draw_circle(p, rr, Color(0.25, 0.55, 0.85, 0.012 * k))

	# 远景拱门
	for a in _arches:
		var px: float = _p(a["x"], 0.0, 0.12).x
		var w: float = a["w"]
		var top_y: float = _p(0.0, -float(a["top"]), 0.12).y
		var base_y: float = _p(0.0, 1900.0, 0.12).y
		if px + w < -200.0 or px - w > vs.x + 200.0 or base_y <= top_y + 60.0:
			continue
		var pts := PackedVector2Array([
			Vector2(px - w, base_y),
			Vector2(px - w, top_y + 90.0),
			Vector2(px - w * 0.62, top_y + 26.0),
			Vector2(px, top_y),
			Vector2(px + w * 0.62, top_y + 26.0),
			Vector2(px + w, top_y + 90.0),
			Vector2(px + w, base_y),
		])
		draw_colored_polygon(pts, Color(0.075, 0.105, 0.14, 0.9))
		draw_polyline(PackedVector2Array([
			Vector2(px - w, top_y + 90.0),
			Vector2(px - w * 0.62, top_y + 26.0),
			Vector2(px, top_y),
			Vector2(px + w * 0.62, top_y + 26.0),
			Vector2(px + w, top_y + 90.0),
		]), Color(0.20, 0.34, 0.46, 0.30), 2.0, true)

	# 中景石柱
	for pl in _pillars:
		var px: float = _p(pl["x"], 0.0, 0.3).x
		var w: float = pl["w"]
		var top_y: float = _p(0.0, -float(pl["top"]), 0.3).y
		var base_y: float = _p(0.0, 1500.0, 0.3).y
		if px + w < -200.0 or px - w > vs.x + 200.0 or base_y <= top_y + 40.0:
			continue
		var lean: float = pl["lean"]
		var pts := PackedVector2Array([
			Vector2(px - w * 0.5, base_y),
			Vector2(px - w * 0.32 + lean, top_y),
			Vector2(px + w * 0.32 + lean, top_y),
			Vector2(px + w * 0.5, base_y),
		])
		draw_colored_polygon(pts, Color(0.048, 0.068, 0.09, 0.94))
		draw_line(pts[1], pts[2], Color(0.16, 0.26, 0.35, 0.35), 2.0, true)
		draw_line(pts[0], pts[1], Color(0.13, 0.21, 0.29, 0.22), 1.5, true)

	# 顶部钟乳石
	for s in _stalactites:
		var px: float = _p(s["x"], 0.0, 0.3).x
		var w: float = s["w"]
		var h: float = s["h"]
		var top_y: float = _p(0.0, -520.0, 0.3).y
		var tip_y: float = _p(0.0, -520.0 + h, 0.3).y
		if px + w < -200.0 or px - w > vs.x + 200.0:
			continue
		draw_colored_polygon(PackedVector2Array([
			Vector2(px - w * 0.5, top_y),
			Vector2(px, tip_y),
			Vector2(px + w * 0.5, top_y),
		]), Color(0.042, 0.058, 0.08, 0.95))

	# 地面雾气
	for i in 8:
		var f := float(i) / 8.0
		var y := vs.y * (0.62 + f * 0.38)
		draw_rect(Rect2(0, y, vs.x, vs.y * 0.05 + 1.0), Color(0.12, 0.22, 0.32, 0.012 + 0.010 * f))

	# 光尘
	for m in _motes:
		var drift: float = _t * float(m["sp"])
		var wy: float = float(m["y"]) - fmod(drift, 700.0)
		var p := _p(float(m["x"]) + sin(_t * 0.6 + float(m["ph"])) * 18.0, wy, 0.55)
		if p.y < -20.0 or p.y > vs.y + 20.0:
			continue
		var a := 0.35 + 0.35 * sin(_t * 2.0 + float(m["ph"]))
		var r: float = m["r"]
		draw_circle(p, r * 3.0, Color(0.6, 0.85, 1.0, 0.05 * a))
		draw_circle(p, r, Color(0.75, 0.92, 1.0, a * 0.8))


## 2.5D：地板后沿之外的后墙 —— 视差 0.75，带竖向石肋，把「里面」封住
func _draw_back_wall(vs: Vector2) -> void:
	var back_y: float = _p(0.0, 642.0, 0.75).y
	if back_y < -420.0 or back_y > vs.y + 320.0:
		return
	var top := back_y - 300.0
	# 墙体本身：上暗下略亮
	var bands := 10
	for i in bands:
		var f := float(i) / float(bands)
		var c := Color(0.020, 0.028, 0.038).lerp(Color(0.052, 0.070, 0.092), f)
		draw_rect(Rect2(0, top + 300.0 * f, vs.x, 30.0 + 1.0), c)
	# 竖向石肋
	var step := 196.0
	var cp := Vector2.ZERO
	if cam != null and is_instance_valid(cam):
		cp = cam.global_position
	var sx := -fmod(cp.x * 0.75, step) - step
	while sx < vs.x + step:
		draw_line(Vector2(sx, top), Vector2(sx, back_y), Color(0.135, 0.185, 0.240, 0.60), 3.0)
		draw_line(Vector2(sx + step * 0.5, top + 90.0), Vector2(sx + step * 0.5, back_y),
			Color(0.090, 0.125, 0.165, 0.50), 2.0)
		sx += step
	# 后墙与地板交界的暗线
	draw_rect(Rect2(0, back_y - 3.0, vs.x, 6.0), Color(0.0, 0.0, 0.0, 0.72))


## R14：玄界之门剪影 —— 每关背景可见，随关卡变宽变亮（法环「黄金树」式引力点）
func _draw_gate_silhouette(vs: Vector2) -> void:
	var g := gate_strength()
	var cx := vs.x * 0.5
	var slit_w := 12.0 + 236.0 * g
	var top := vs.y * (0.30 - 0.14 * g)
	var bot := vs.y * (0.80 - 0.02 * g)
	if bot <= top:
		return
	# 门缝里的光（越深越亮）
	var glow := Color(0.52, 0.78, 1.0, 0.05 + 0.30 * g)
	draw_rect(Rect2(cx - slit_w * 0.5, top, slit_w, bot - top), glow)
	# 门缝核心更亮的一道
	draw_rect(Rect2(cx - slit_w * 0.18, top, slit_w * 0.36, bot - top),
		Color(0.80, 0.92, 1.0, 0.05 + 0.22 * g))
	# 门环（关卡二起可见轮廓，关卡三起清晰）
	if g > 0.15:
		var rr := 46.0 + 168.0 * g
		var ctr := Vector2(cx, top + (bot - top) * 0.46)
		draw_arc(ctr, rr, PI * 0.10, PI * 0.90, 48,
			Color(0.62, 0.86, 1.0, 0.10 + 0.36 * g), 2.0 + 2.2 * g, true)
		draw_arc(ctr, rr * 0.72, PI * 0.14, PI * 0.86, 40,
			Color(0.55, 0.78, 1.0, 0.06 + 0.22 * g), 1.4 + 1.4 * g, true)
	# 魔渊涌动（关卡三起）
	if g > 0.40:
		for i in 7:
			var f := float(i) / 7.0
			var yy := top + (bot - top) * f
			var wob := sin(_t * 1.3 + float(i) * 1.7) * (8.0 + 22.0 * g)
			draw_line(Vector2(cx - slit_w * 0.5 + wob, yy), Vector2(cx + slit_w * 0.5 + wob, yy),
				Color(0.42, 0.64, 1.0, 0.05 + 0.10 * g), 1.6)
