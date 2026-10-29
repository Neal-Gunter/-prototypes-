extends Node2D
## 弹幕：剑冢守的远程弹幕（可被玩家刀锋弹反回去），
## 以及 R13 玩家飞剑流甩出去的友方飞剑。

var vel := Vector2.ZERO
var radius := 9.0
var life := 5.0
var hostile := true
var dmg := 2
var pierce := false        # R13：飞剑是否穿透（穿云）
var sword := false         # R13：画成剑形，而不是法球
var talisman := false      # R29：画成纸符（符剑的符击 / 符阵·万剑）
var hue := 0.56
var _t := 0.0
var _hit: Array = []       # 穿透时记录已经打过的敌人，避免同一只被重复结算
var _trail: Array = []


func setup(pos: Vector2, dir: Vector2, speed: float) -> void:
	global_position = pos
	vel = dir.normalized() * speed
	z_index = 17


## R13 飞剑：友方、剑形、带伤害与穿透
func setup_sword(pos: Vector2, dir: Vector2, speed: float, d: int, h: float) -> void:
	setup(pos, dir, speed)
	hostile = false
	sword = true
	dmg = d
	hue = h
	radius = 7.0
	life = 2.2
	z_index = 18


## R29 符剑：友方纸符 —— 比飞剑慢、判定略大，但打一下就没了（不穿透）
func setup_talisman(pos: Vector2, dir: Vector2, speed: float, d: int, h: float) -> void:
	setup(pos, dir, speed)
	hostile = false
	talisman = true
	dmg = d
	hue = h
	radius = 8.0
	life = 1.6
	z_index = 18


func rect() -> Rect2:
	if sword:
		return Rect2(global_position - Vector2(radius * 1.6, radius * 1.1),
			Vector2(radius * 3.2, radius * 2.2))
	return Rect2(global_position - Vector2(radius, radius), Vector2(radius, radius) * 2.0)


## 被刀锋弹反：反向飞回去，变成可以打 Boss 的弹幕
func deflect() -> void:
	hostile = false
	vel = -vel * 1.45
	life = minf(life, 2.4)
	_trail.clear()


## 穿透判定用：这只敌人是不是已经被这道飞剑打过
func already_hit(e: Node) -> bool:
	return _hit.has(e)


func mark_hit(e: Node) -> void:
	_hit.append(e)


func _process(delta: float) -> void:
	_t += delta
	global_position += vel * delta
	life -= delta
	_trail.append(global_position)
	if _trail.size() > 7:
		_trail.pop_front()
	if life <= 0.0:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if sword:
		_draw_sword()
		return
	if talisman:
		_draw_talisman()
		return
	var col := Color(0.86, 0.45, 1.0) if hostile else Color(0.55, 0.95, 1.0)
	for i in _trail.size():
		var p: Vector2 = _trail[i] - global_position
		draw_circle(p, radius * (0.20 + 0.09 * float(i)), Color(col.r, col.g, col.b, 0.04 + 0.03 * float(i)))
	var pulse := 0.85 + 0.15 * sin(_t * 22.0)
	draw_circle(Vector2.ZERO, radius * 2.4, Color(col.r, col.g, col.b, 0.10 * pulse))
	draw_circle(Vector2.ZERO, radius, Color(col.r, col.g, col.b, 0.85))
	draw_circle(Vector2.ZERO, radius * 0.45, Color(1, 1, 1, 0.95))
	draw_arc(Vector2.ZERO, radius * 1.7, _t * 9.0, _t * 9.0 + PI * 1.3, 16,
		Color(col.r, col.g, col.b, 0.65), 1.6, true)


## R29 符剑：一枚翻转的纸符 + 紫色符光。纸面画一道朱砂笔画，飞得越远拖尾越淡。
func _draw_talisman() -> void:
	var col := Color.from_hsv(hue, 0.52, 1.0)
	var dir := vel.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var perp := Vector2(-dir.y, dir.x)
	for i in _trail.size():
		var p: Vector2 = _trail[i] - global_position
		var a := 0.04 + 0.04 * float(i)
		draw_circle(p, radius * (0.35 + 0.06 * float(i)), Color(col.r, col.g, col.b, a))
	draw_circle(Vector2.ZERO, radius * 2.2, Color(col.r, col.g, col.b, 0.12))
	# 纸符本体：随飞行角度翻转（用 cos 收窄宽度，做出「翻面」感）
	var flip := absf(cos(_t * 13.0))
	var hw := radius * (0.42 + 0.58 * flip)
	var hh := radius * 0.85
	draw_rect(Rect2(-hw, -hh, hw * 2.0, hh * 2.0), Color(0.96, 0.94, 0.86, 0.95))
	draw_rect(Rect2(-hw, -hh, hw * 2.0, hh * 2.0), Color(col.r, col.g, col.b, 0.9), false, 1.2)
	# 朱砂笔画
	if flip > 0.35:
		var ink := Color(0.80, 0.16, 0.20, 0.9 * flip)
		draw_line(Vector2(-hw * 0.35, -hh * 0.55), Vector2(hw * 0.35, -hh * 0.55), ink, 1.4)
		draw_line(Vector2(0, -hh * 0.75), Vector2(0, hh * 0.30), ink, 1.4)
		draw_line(Vector2(-hw * 0.40, hh * 0.50), Vector2(hw * 0.40, hh * 0.50), ink, 1.2)


## 飞剑：一道细长光刃 + 拖尾，朝向由速度决定
func _draw_sword() -> void:
	var col := Color.from_hsv(hue, 0.55, 1.0)
	var dir := vel.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var perp := Vector2(-dir.y, dir.x)
	# 拖尾
	for i in _trail.size():
		var p: Vector2 = _trail[i] - global_position
		var a := 0.05 + 0.05 * float(i)
		draw_line(p - dir * 10.0, p + dir * 10.0, Color(col.r, col.g, col.b, a), 2.0)
	# 光晕
	draw_circle(Vector2.ZERO, radius * 2.0, Color(col.r, col.g, col.b, 0.12))
	# 剑身
	var tip := dir * radius * 2.6
	var back := -dir * radius * 1.5
	draw_colored_polygon(PackedVector2Array([
		tip, back + perp * radius * 0.55, back - perp * radius * 0.55,
	]), Color(0.90, 0.96, 1.0, 0.95))
	draw_line(back, tip, Color(col.r, col.g, col.b, 0.95), 2.4, true)
	# 剑格
	draw_line(back + perp * radius * 0.9, back - perp * radius * 0.9,
		Color(col.r, col.g, col.b, 0.8), 2.0)
