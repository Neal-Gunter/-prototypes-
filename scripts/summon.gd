extends Node2D
## R32b 召符：一张符唤出的小纸人。
##
## 约束（和以后 R34 的同伴同一条）：**不抢操作权** —— 只跟随、只自动打最近的敌人。
## 它不改任何全局状态；伤害走 main 的统一入口，所以处决 / 护体罡气 / 阴阳同界
## 这些规则对它一视同仁（不会出现「纸人能跨阴阳界打人」这种破规矩的东西）。

const SpaceScript := preload("res://scripts/space.gd")

const SPEED := 300.0
const ATK_RANGE := 104.0
const ATK_CD := 1.05
const DMG := 1
const LEASH := 420.0        # 离玩家太远的目标不追（否则它会满场乱跑）

var main: Node = null
var player: Node = null
var fx: Node = null
var depth := SpaceScript.PLAYER_Z
var life := 10.0

var _cd := 0.45
var _t := 0.0
var _flash := 0.0
var _atk_t := 0.0
var _facing := 1
var _gone := false


func setup(m: Node, p: Node, f: Node, lifetime: float = 10.0) -> void:
	main = m
	player = p
	fx = f
	life = lifetime
	if p != null and is_instance_valid(p):
		depth = float(p.depth)
		_facing = int(p.facing) if int(p.facing) != 0 else 1
		global_position = p.global_position + Vector2(-46.0 * float(_facing), 0.0)
	# 同一条深度线上永远画在玩家之后：纸人是「帮手」，不能挡自己人的脸
	z_index = SpaceScript.z_order(depth) - 1


func _process(delta: float) -> void:
	if _gone:
		return
	_t += delta
	life -= delta
	_cd = maxf(0.0, _cd - delta)
	_atk_t = maxf(0.0, _atk_t - delta)
	_flash = maxf(0.0, _flash - delta * 4.0)
	if life <= 0.0:
		_vanish()
		return

	var target := _nearest()
	var dest := global_position
	# 只追 x，不换道：纸人和玩家同一条深度线（否则它会飘到别的阴阳界上去，
	# 而它的判定仍按自己的 depth 算，画面上就会出现「纸人站在远处却在打近处」）
	var lane_y := global_position.y
	if player != null and is_instance_valid(player):
		lane_y = player.global_position.y
	if target != null:
		var dir := signf(target.global_position.x - global_position.x)
		if dir != 0.0:
			_facing = int(dir)
		dest = Vector2(target.global_position.x - float(_facing) * ATK_RANGE * 0.66, lane_y)
	elif player != null and is_instance_valid(player):
		_facing = int(player.facing) if int(player.facing) != 0 else _facing
		dest = Vector2(player.global_position.x - 46.0 * float(_facing), lane_y)

	global_position = global_position.move_toward(dest, SPEED * delta)
	global_position.x = clampf(global_position.x,
		SpaceScript.ROOM_X0 + 10.0, SpaceScript.ROOM_X1 - 10.0)

	# 同一深度（阴阳同界）且进范围才出手
	if target != null and _cd <= 0.0 \
			and global_position.distance_to(target.global_position) <= ATK_RANGE:
		_atk_t = 0.18
		_cd = ATK_CD
		_flash = 1.0
		if main != null and is_instance_valid(main):
			main.summon_strike(self, target, DMG)
	z_index = SpaceScript.z_order(depth) - 1
	queue_redraw()


## 最近的、同界、且没离玩家太远的敌人
func _nearest() -> Node:
	if main == null or not is_instance_valid(main):
		return null
	var anchor := global_position
	if player != null and is_instance_valid(player):
		anchor = player.global_position
	var best: Node = null
	var bd := 1.0e9
	for e in main.enemies:
		if e == null or not is_instance_valid(e) or e.dead:
			continue
		if not SpaceScript.lane_ok(depth, float(e.depth)):
			continue
		if anchor.distance_to(e.global_position) > LEASH:
			continue
		var d: float = global_position.distance_to(e.global_position)
		if d < bd:
			bd = d
			best = e
	return best


func _vanish() -> void:
	_gone = true
	if fx != null and is_instance_valid(fx):
		fx.burst(global_position + Vector2(0, -20.0), 14, Color(0.96, 0.92, 0.80), 0.9)
		fx.ring(global_position + Vector2(0, -20.0), 6.0, 52.0,
			Color(0.96, 0.90, 0.70), 0.3, 2.5)
	queue_free()


func _draw() -> void:
	SpaceScript.apply_draw(self, depth)
	var bob := sin(_t * 7.0) * 2.0
	var o := Vector2(0, bob)
	var body := Color(0.96, 0.92, 0.80, 0.92)
	var edge := Color(0.80, 0.68, 0.44, 0.85)
	if _flash > 0.0:
		body = body.lerp(Color(1.0, 1.0, 0.94), _flash)

	# 脚下淡影
	draw_circle(Vector2(0, 2), 15.0, Color(0.05, 0.06, 0.08, 0.28))
	# 纸身（一个窄长的梯形，像折出来的）
	draw_colored_polygon(PackedVector2Array([
		o + Vector2(-11, -46), o + Vector2(11, -46),
		o + Vector2(8, 0), o + Vector2(-8, 0),
	]), body)
	draw_polyline(PackedVector2Array([
		o + Vector2(-11, -46), o + Vector2(11, -46),
		o + Vector2(8, 0), o + Vector2(-8, 0), o + Vector2(-11, -46),
	]), edge, 1.4, true)
	# 袖（两只小折角，随呼吸摆）
	var sw := 5.0 + 3.0 * sin(_t * 9.0)
	draw_line(o + Vector2(-9, -34), o + Vector2(-9 - sw, -26), edge, 2.0, true)
	draw_line(o + Vector2(9, -34), o + Vector2(9 + sw, -26), edge, 2.0, true)
	# 符面：一个朱砂「令」字的简写（两横一竖），比画眼睛更像纸人
	var red := Color(0.88, 0.28, 0.26, 0.95)
	draw_line(o + Vector2(-5, -40), o + Vector2(5, -40), red, 1.6, true)
	draw_line(o + Vector2(-4, -35), o + Vector2(4, -35), red, 1.4, true)
	draw_line(o + Vector2(0, -41), o + Vector2(0, -30), red, 1.6, true)
	# 出手时一道细光
	if _atk_t > 0.0:
		var k := _atk_t / 0.18
		draw_line(o + Vector2(float(_facing) * 10.0, -26),
			o + Vector2(float(_facing) * (10.0 + 34.0 * k), -26),
			Color(1.0, 0.94, 0.66, 0.85 * k), 2.6, true)
