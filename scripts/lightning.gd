extends Node2D
## 前世身第三阶段的天雷：先落下一道警示光柱，再劈下闪电。
## 伤害结算交给 main.gd（这里只负责表现 + 发信号）。

signal struck(x: float, radius: float)

const WARN := 0.62       # 警示时长
const RADIUS := 46.0     # 落点伤害半径

var ground_y := 760.0
## R32b：警示时长可变 —— 雷符要连落 5 道，靠错开的警示时间形成「连劈」
var warn_t := WARN
var _t := 0.0
var _hit := false
var _flash := 0.0
var _segs: Array = []


func setup(px: float, gy: float, warn: float = WARN) -> void:
	global_position = Vector2(px, gy)
	ground_y = gy
	warn_t = maxf(0.08, warn)
	z_index = 30
	_build_bolt()
	SFX.play("gate", 1.55, -16.0)


## 随机折线，看起来像真的闪电
func _build_bolt() -> void:
	_segs.clear()
	var y := -900.0
	var x := 0.0
	_segs.append(Vector2(x, y))
	while y < -30.0:
		y += randf_range(46.0, 92.0)
		x = clampf(x + randf_range(-26.0, 26.0), -46.0, 46.0)
		_segs.append(Vector2(x, y))
	_segs.append(Vector2(0.0, 0.0))


func _process(delta: float) -> void:
	_t += delta
	if not _hit and _t >= warn_t:
		_hit = true
		_flash = 1.0
		_build_bolt()
		struck.emit(global_position.x, RADIUS)
		SFX.play("thunder", randf_range(0.92, 1.1), -1.0)
		Game.add_shake(10.0)
	if _hit:
		_flash = maxf(0.0, _flash - delta * 3.2)
		if _flash <= 0.0:
			queue_free()
	queue_redraw()


func _draw() -> void:
	if not _hit:
		# 警示：细光柱 + 地面收缩圈
		var p := clampf(_t / maxf(0.01, warn_t), 0.0, 1.0)
		var a := 0.18 + 0.22 * sin(_t * 26.0)
		draw_line(Vector2(0, -900), Vector2(0, 0), Color(0.62, 0.85, 1.0, a * 0.7), 2.0)
		draw_line(Vector2(0, -900), Vector2(0, 0), Color(0.85, 0.95, 1.0, a * 0.35), 7.0)
		var rr := lerpf(RADIUS * 2.4, RADIUS, p)
		draw_arc(Vector2(0, 0), rr, 0.0, TAU, 32, Color(0.7, 0.92, 1.0, 0.35 + 0.3 * p), 2.0, true)
		draw_circle(Vector2(0, 0), RADIUS * p, Color(0.75, 0.92, 1.0, 0.06 + 0.12 * p))
		return

	# 闪电本体
	var f := _flash
	draw_line(Vector2(0, -900), Vector2(0, 0), Color(0.75, 0.9, 1.0, 0.35 * f), 16.0)
	var pts := PackedVector2Array(_segs)
	draw_polyline(pts, Color(0.85, 0.95, 1.0, 0.9 * f), 7.0, true)
	draw_polyline(pts, Color(1.0, 1.0, 1.0, f), 2.6, true)
	# 落点炸开
	draw_circle(Vector2(0, 0), RADIUS * (1.1 + 0.8 * (1.0 - f)), Color(0.8, 0.95, 1.0, 0.35 * f))
	draw_arc(Vector2(0, 0), RADIUS * (1.4 + 1.6 * (1.0 - f)), 0.0, TAU, 36,
		Color(0.9, 0.98, 1.0, 0.5 * f), 3.0, true)
