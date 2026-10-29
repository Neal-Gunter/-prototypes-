extends Node2D
## 世界空间特效：火星、冲击环、刀光残影、飘字。

var font: Font

class Spark:
	var pos: Vector2
	var vel: Vector2
	var life: float
	var max_life: float
	var color: Color
	var width: float
	var grav: float
	var drag: float


class Ring:
	var pos: Vector2
	var r0: float
	var r1: float
	var life: float
	var max_life: float
	var color: Color
	var width: float


class Arc:
	var pos: Vector2
	var a0: float
	var a1: float
	var r: float
	var life: float
	var max_life: float
	var color: Color


class Beam:
	var pos: Vector2
	var size: Vector2
	var dir: int
	var life: float
	var max_life: float
	var color: Color


class Text:
	var pos: Vector2
	var text: String
	var life: float
	var max_life: float
	var color: Color
	var size: int
	var rise: float


var _sparks: Array = []
var _rings: Array = []
var _arcs: Array = []
var _texts: Array = []
var _beams: Array = []


func _ready() -> void:
	z_index = 60
	font = load("res://fonts/NotoSansSC.ttf")


func clear_all() -> void:
	_sparks.clear()
	_rings.clear()
	_arcs.clear()
	_texts.clear()
	_beams.clear()
	queue_redraw()


# ------------------------------------------------------------------ 生成
func sparks(pos: Vector2, dir: Vector2, count: int, color: Color, power: float = 1.0) -> void:
	for i in count:
		var s := Spark.new()
		var ang := dir.angle() + randf_range(-1.15, 1.15)
		var sp := randf_range(90.0, 460.0) * power
		s.pos = pos + Vector2(randf_range(-3, 3), randf_range(-3, 3))
		s.vel = Vector2(cos(ang), sin(ang)) * sp
		s.max_life = randf_range(0.18, 0.5)
		s.life = s.max_life
		s.color = color
		s.width = randf_range(1.2, 2.8)
		s.grav = randf_range(300.0, 780.0)
		s.drag = randf_range(2.0, 5.0)
		_sparks.append(s)


func burst(pos: Vector2, count: int, color: Color, power: float = 1.0) -> void:
	for i in count:
		var s := Spark.new()
		var ang := randf() * TAU
		var sp := randf_range(70.0, 420.0) * power
		s.pos = pos
		s.vel = Vector2(cos(ang), sin(ang)) * sp
		s.max_life = randf_range(0.2, 0.55)
		s.life = s.max_life
		s.color = color
		s.width = randf_range(1.0, 2.6)
		s.grav = randf_range(180.0, 620.0)
		s.drag = randf_range(1.6, 4.0)
		_sparks.append(s)


func ring(pos: Vector2, r0: float, r1: float, color: Color, life: float = 0.3, width: float = 3.0) -> void:
	var r := Ring.new()
	r.pos = pos
	r.r0 = r0
	r.r1 = r1
	r.max_life = life
	r.life = life
	r.color = color
	r.width = width
	_rings.append(r)


func arc(pos: Vector2, a0: float, a1: float, radius: float, color: Color, life: float = 0.18) -> void:
	var a := Arc.new()
	a.pos = pos
	a.a0 = a0
	a.a1 = a1
	a.r = radius
	a.max_life = life
	a.life = life
	a.color = color
	_arcs.append(a)


## R18b：绝招用的直线刀光 —— 从近端向远端展开，和矩形判定同形
func beam(pos: Vector2, size: Vector2, dir: int, color: Color, life: float = 0.28) -> void:
	var b := Beam.new()
	b.pos = pos
	b.size = size
	b.dir = dir
	b.max_life = life
	b.life = life
	b.color = color
	_beams.append(b)


func text(pos: Vector2, txt: String, color: Color, size: int = 26, rise: float = 46.0) -> void:
	var t := Text.new()
	t.pos = pos
	t.text = txt
	t.max_life = 1.0
	t.life = t.max_life
	t.color = color
	t.size = size
	t.rise = rise
	_texts.append(t)


func dust(pos: Vector2, count: int = 6) -> void:
	for i in count:
		var s := Spark.new()
		var ang := randf_range(-PI, 0.0)
		s.pos = pos + Vector2(randf_range(-8, 8), 0)
		s.vel = Vector2(cos(ang) * randf_range(30, 120), sin(ang) * randf_range(20, 70))
		s.max_life = randf_range(0.25, 0.5)
		s.life = s.max_life
		s.color = Color(0.62, 0.74, 0.85, 0.5)
		s.width = randf_range(1.5, 3.0)
		s.grav = 60.0
		s.drag = 3.0
		_sparks.append(s)


# ------------------------------------------------------------------ 更新
func _process(delta: float) -> void:
	for s in _sparks:
		s.life -= delta
		s.vel.y += s.grav * delta
		s.vel *= 1.0 - clampf(s.drag * delta, 0.0, 0.9)
		s.pos += s.vel * delta
	_sparks = _sparks.filter(func(x): return x.life > 0.0)

	for r in _rings:
		r.life -= delta
	_rings = _rings.filter(func(x): return x.life > 0.0)

	for a in _arcs:
		a.life -= delta
	_arcs = _arcs.filter(func(x): return x.life > 0.0)

	for t in _texts:
		t.life -= delta
		t.pos.y -= t.rise * delta
	_texts = _texts.filter(func(x): return x.life > 0.0)

	for b in _beams:
		b.life -= delta
	_beams = _beams.filter(func(x): return x.life > 0.0)

	if not (_sparks.is_empty() and _rings.is_empty() and _arcs.is_empty()
			and _texts.is_empty() and _beams.is_empty()):
		queue_redraw()


func _draw() -> void:
	# 冲击环
	for r in _rings:
		var p: float = 1.0 - r.life / r.max_life
		var rad: float = lerpf(r.r0, r.r1, ease(p, 0.4))
		var c: Color = r.color
		c.a *= (1.0 - p) * 0.9
		draw_arc(r.pos, rad, 0.0, TAU, 48, c, r.width * (1.0 - p * 0.6), true)
		if p < 0.5:
			var c2: Color = r.color
			c2.a *= (1.0 - p * 2.0) * 0.25
			draw_circle(r.pos, rad * 0.85, c2)

	# 刀光弧
	for a in _arcs:
		var p: float = 1.0 - a.life / a.max_life
		var c: Color = a.color
		c.a *= (1.0 - p) * 0.85
		var steps := 14
		var pts := PackedVector2Array()
		var r_out: float = a.r * (0.75 + 0.35 * p)
		var r_in: float = r_out - a.r * 0.42
		for i in range(steps + 1):
			var ang: float = lerpf(a.a0, a.a1, float(i) / steps)
			pts.append(a.pos + Vector2(cos(ang), sin(ang)) * r_out)
		for i in range(steps, -1, -1):
			var ang: float = lerpf(a.a0, a.a1, float(i) / steps)
			pts.append(a.pos + Vector2(cos(ang), sin(ang)) * r_in)
		if pts.size() >= 3:
			draw_colored_polygon(pts, c)

	# R18b 直线刀光
	for b in _beams:
		var pb: float = 1.0 - b.life / b.max_life
		var cb: Color = b.color
		cb.a *= (1.0 - pb) * 0.85
		var grow: float = clampf(pb * 4.0, 0.0, 1.0)      # 前 25% 迅速展开
		var w: float = b.size.x * grow
		var h: float = b.size.y * (1.0 - pb * 0.30)
		var cy: float = b.pos.y
		var x0: float = b.pos.x - b.size.x * 0.5 if b.dir > 0 else b.pos.x + b.size.x * 0.5 - w
		var rect := Rect2(Vector2(x0, cy - h * 0.5), Vector2(w, h))
		draw_rect(rect, cb)
		# 亮芯
		var core: Color = Color(1.0, 1.0, 1.0, cb.a * 0.9)
		draw_line(Vector2(rect.position.x, cy), Vector2(rect.position.x + w, cy), core, 3.0, true)

	# 火星
	for s in _sparks:
		var p: float = s.life / s.max_life
		var c: Color = s.color
		c.a *= clampf(p * 1.4, 0.0, 1.0)
		var tail: Vector2 = s.pos - s.vel.normalized() * minf(s.vel.length() * 0.035, 16.0)
		draw_line(tail, s.pos, c, s.width * clampf(p + 0.3, 0.0, 1.0), true)

	# 飘字
	if font:
		for t in _texts:
			var p: float = t.life / t.max_life
			var c: Color = t.color
			c.a *= clampf(p * 1.8, 0.0, 1.0)
			var sz := Vector2.ZERO
			sz = font.get_string_size(t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, t.size)
			var pos: Vector2 = t.pos - Vector2(sz.x * 0.5, 0)
			draw_string_outline(font, pos, t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, t.size, 6, Color(0, 0, 0, c.a * 0.75))
			draw_string(font, pos, t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, t.size, c)
