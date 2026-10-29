extends Node2D
## R35 · 灵兽 / 傀儡（同伴）
##
## 设计铁律：同伴**不能抢操作权**。灵兽全自动、傀儡只跟随不指挥 —— 本脚本
## 全程不读 Input，只用 player.global_position 与 enemy_provider() 获取敌人，
## 绝不移动玩家、绝不接管按键。self-test 里会断言这一点（T150）。
##
## 灵兽（FOX / TURTLE / BIRD）：被动技能，按周期触发，**不参与战斗判定**
## （不可被击杀，hurt_companion 对灵兽无效）。
## 傀儡（SWORD / SHIELD / RUNE）：跟随玩家作战，**有 HP、会死**。

enum Kind {
	FOX,      # 白狐：输出，每 5s 吐狐火（1 点）伤最近敌人
	TURTLE,   # 玄龟：防御，每 10s 给玩家 1 层护盾（挡 1 次）
	BIRD,     # 青鸟：辅助，每 8s 回 20 灵力
	SWORD,    # 剑傀儡：跟着玩家砍最近的敌人
	SHIELD,   # 盾傀儡：站在玩家身前挡刀，周期性给护盾
	RUNE,     # 符傀儡：站远处放符（复用弹幕通道）
}

const NAMES := {
	Kind.FOX: "白 狐", Kind.TURTLE: "玄 龟", Kind.BIRD: "青 鸟",
	Kind.SWORD: "剑 傀 儡", Kind.SHIELD: "盾 傀 儡", Kind.RUNE: "符 傀 儡",
}
const HUES := {
	Kind.FOX: 0.07, Kind.TURTLE: 0.42, Kind.BIRD: 0.52,
	Kind.SWORD: 0.02, Kind.SHIELD: 0.58, Kind.RUNE: 0.78,
}
const IS_BEAST := { Kind.FOX: true, Kind.TURTLE: true, Kind.BIRD: true,
	Kind.SWORD: false, Kind.SHIELD: false, Kind.RUNE: false }

# --- 运行时引用（由 main.gd 注入；类型放开以便自测注入 Mock）---
var player = null
var fx = null
var main_ref = null
var enemy_provider: Callable = Callable()   # 返回 Array，与 player 同款

# --- 状态 ---
var kind := Kind.FOX
var level := 1
var hp := 6
var max_hp := 6
var dead := false

var _t := 0.0          # 技能 / 攻击计时
var _hurt_t := 0.0     # 邻近敌人蹭血计时（傀儡会死用）
var _fired := 0        # 累计触发次数（自测可查）
var _offset := Vector2.ZERO

const BEAST_INTERVAL := { Kind.FOX: 5.0, Kind.TURTLE: 10.0, Kind.BIRD: 8.0 }
const PUPPET_HP := { Kind.SWORD: 6, Kind.SHIELD: 10, Kind.RUNE: 5 }


func init(k: int, pos: Vector2) -> void:
	kind = k
	level = 1
	dead = false
	_t = 0.0
	_hurt_t = 0.0
	_fired = 0
	global_position = pos
	if IS_BEAST.get(k, false):
		hp = 9999
		max_hp = 9999
	else:
		hp = int(PUPPET_HP.get(k, 6))
		max_hp = hp
	# 跟随偏移（相对玩家）：灵兽在后上方、傀儡在前/后
	match k:
		Kind.FOX: _offset = Vector2(-72.0, -12.0)
		Kind.TURTLE: _offset = Vector2(-52.0, 22.0)
		Kind.BIRD: _offset = Vector2(4.0, -64.0)
		Kind.SWORD: _offset = Vector2(64.0, 12.0)
		Kind.SHIELD: _offset = Vector2(86.0, 0.0)
		Kind.RUNE: _offset = Vector2(-96.0, -28.0)


func set_level(lv: int) -> void:
	level = clampi(lv, 1, 3)


## 法宝「灵契」：同伴伤害 +50%
func _dmg_mul() -> float:
	if player != null and is_instance_valid(player) and player.has_relic("pact"):
		return 1.5
	return 1.0


func nearest_enemy():
	if enemy_provider == null or not enemy_provider.is_valid():
		return null
	var list: Array = enemy_provider.call()
	var best = null
	var bd := 1e9
	for idx in list.size():
		var e = list[idx]
		if e == null or not is_instance_valid(e) or bool(e.get("dead")):
			continue
		var d: float = e.global_position.distance_to(global_position)
		if d < bd:
			bd = d
			best = e
	return best


func _process(delta: float) -> void:
	if dead:
		return
	if player == null or not is_instance_valid(player) or bool(player.get("dead")):
		return
	_follow(delta)
	if IS_BEAST.get(kind, false):
		_beast(delta)
	else:
		_puppet(delta)


func _follow(delta: float) -> void:
	var target: Vector2 = player.global_position + _offset
	# 盾傀儡贴脸：站在玩家与最近敌人之间
	if kind == Kind.SHIELD:
		var e = nearest_enemy()
		if e != null:
			var dir := signf(e.global_position.x - player.global_position.x)
			if dir == 0.0:
				dir = 1.0
			target = player.global_position + Vector2(dir * 84.0, 0.0)
	global_position = global_position.move_toward(target, 620.0 * delta)


# ============================================================ 灵兽（被动）
func _beast(delta: float) -> void:
	_t += delta
	var iv := float(BEAST_INTERVAL.get(kind, 6.0))
	if kind == Kind.TURTLE and level >= 2:
		iv = 8.0
	if _t < iv:
		return
	_t = 0.0
	_fired += 1
	match kind:
		Kind.FOX: _foxfire()
		Kind.TURTLE: _grant_shield()
		Kind.BIRD: _regen_mana()


func _foxfire() -> void:
	var dmg := level
	var targets := []
	var e = nearest_enemy()
	if e != null:
		targets.append(e)
	if level >= 2:
		# 第二技能：再多锁一个最近的（排除已选）
		var best2 = null
		var bd := 1e9
		if enemy_provider != null and enemy_provider.is_valid():
			var lst: Array = enemy_provider.call()
			for idx in lst.size():
				var n = lst[idx]
				if n == null or not is_instance_valid(n) or bool(n.get("dead")):
					continue
				if n == e:
					continue
				var d: float = n.global_position.distance_to(global_position)
				if d < bd:
					bd = d
					best2 = n
		if best2 != null:
			targets.append(best2)
	for idx in targets.size():
		var t = targets[idx]
		t.hurt(int(round(float(dmg) * _dmg_mul())), global_position, false, "companion")
	if fx != null:
		fx.burst(global_position, 8, Color.from_hsv(HUES[Kind.FOX], 0.7, 1.0), 0.5)
		fx.text(global_position + Vector2(0, -40.0), "狐 火", Color.from_hsv(HUES[Kind.FOX], 0.6, 1.0), 14, 24)


func _grant_shield() -> void:
	var n := level
	if player != null and is_instance_valid(player) and player.has_method("add_shield"):
		player.add_shield(n)
	if fx != null:
		fx.text(player.global_position + Vector2(0, -56.0),
			"护 盾 +%d" % n, Color.from_hsv(HUES[Kind.TURTLE], 0.5, 1.0), 16, 30)


func _regen_mana() -> void:
	var n := 20 * level
	if player != null and is_instance_valid(player) and player.has_method("add_stamina"):
		player.add_stamina(float(n))
	# 第二技能（2 级以上）：顺带回 1 点气血（不满才回）
	if level >= 2 and player != null and is_instance_valid(player) and player.has_method("add_hp_soft"):
		player.add_hp_soft(1)
	if fx != null:
		fx.text(player.global_position + Vector2(0, -56.0),
			"灵 力 +%d" % n, Color.from_hsv(HUES[Kind.BIRD], 0.5, 1.0), 16, 30)


# ============================================================ 傀儡（作战）
func _puppet(delta: float) -> void:
	if kind == Kind.RUNE:
		_rune(delta)
	else:
		_melee_puppet(delta)
	_proximity_damage(delta)


func _melee_puppet(delta: float) -> void:
	var e = nearest_enemy()
	var reach := 150.0
	if kind == Kind.SHIELD:
		reach = 120.0
	# 盾傀儡额外：周期性给玩家护盾
	if kind == Kind.SHIELD:
		_t += delta
		if _t >= 6.0:
			_t = 0.0
			_fired += 1
			if player != null and is_instance_valid(player) and player.has_method("add_shield"):
				player.add_shield(level)
			if fx != null:
				fx.text(player.global_position + Vector2(0, -56.0),
					"护 盾 +%d" % level, Color.from_hsv(HUES[Kind.SHIELD], 0.5, 1.0), 16, 30)
		return
	_t += delta
	if e == null:
		return
	if global_position.distance_to(e.global_position) > reach:
		return
	if _t < 1.2:
		return
	_t = 0.0
	_fired += 1
	var dmg := int(round(2.0 * float(level) * _dmg_mul()))
	e.hurt(dmg, global_position, false, "companion")
	if fx != null:
		fx.burst(e.global_position, 6, Color.from_hsv(HUES[Kind.SWORD], 0.7, 1.0), 0.4)


func _rune(delta: float) -> void:
	# 符傀儡：保持距离，周期性放符（复用 main 的弹幕通道）
	var e = nearest_enemy()
	if e != null:
		var d := global_position.distance_to(e.global_position)
		var want := 200.0
		if d < want - 30.0:
			global_position = global_position.move_toward(
				player.global_position + Vector2(-96.0, -28.0), 500.0 * delta)
	_t += delta
	if e == null or _t < 3.0:
		return
	_t = 0.0
	_fired += 1
	var dmg := int(round(2.0 * float(level) * _dmg_mul()))
	if main_ref != null and main_ref.has_method("_spawn_companion_shot"):
		var dir: Vector2 = (e.global_position - global_position).normalized()
		main_ref._spawn_companion_shot(global_position, dir, dmg)
	else:
		e.hurt(dmg, global_position, false, "companion")
	if fx != null:
		fx.burst(global_position, 6, Color.from_hsv(HUES[Kind.RUNE], 0.7, 1.0), 0.4)


## 傀儡被邻近敌人蹭血 —— 会死
func _proximity_damage(delta: float) -> void:
	if IS_BEAST.get(kind, false):
		return
	var hit := false
	if enemy_provider != null and enemy_provider.is_valid():
		var lst: Array = enemy_provider.call()
		for idx in lst.size():
			var e = lst[idx]
			if e == null or not is_instance_valid(e) or bool(e.get("dead")):
				continue
			if e.global_position.distance_to(global_position) < 38.0:
				hit = true
				break
	if not hit:
		return
	_hurt_t += delta
	if _hurt_t >= 1.0:
		_hurt_t = 0.0
		hurt_companion(1)


## 同伴受伤（灵兽免疫；傀儡掉血、归零则死）
func hurt_companion(dmg: int) -> void:
	if dead:
		return
	if IS_BEAST.get(kind, false):
		return
	hp -= dmg
	if fx != null:
		fx.burst(global_position, 5, Color(1.0, 0.5, 0.5), 0.4)
	if hp <= 0:
		hp = 0
		dead = true
		if fx != null:
			fx.text(global_position + Vector2(0, -36.0), "碎", Color(1.0, 0.5, 0.5), 18, 30)
		queue_free()


func _draw() -> void:
	if dead:
		return
	var hue: float = HUES.get(kind, 0.5)
	var col := Color.from_hsv(hue, 0.6, 1.0)
	var r := 13.0
	if not IS_BEAST.get(kind, false):
		r = 12.0
	draw_circle(Vector2.ZERO, r, Color(col.r, col.g, col.b, 0.85))
	draw_arc(Vector2.ZERO, r + 2.0, 0.0, TAU, 24,
		Color(col.r, col.g, col.b, 0.5), 2.0)
	# 灵兽画个小内点，傀儡画个十字表示「武器」
	if IS_BEAST.get(kind, false):
		draw_circle(Vector2.ZERO, 4.0, Color(1.0, 1.0, 1.0, 0.9))
	else:
		draw_line(Vector2(-5.0, 0.0), Vector2(5.0, 0.0), Color(1.0, 1.0, 1.0, 0.9), 2.0)
		draw_line(Vector2(0.0, -5.0), Vector2(0.0, 5.0), Color(1.0, 1.0, 1.0, 0.9), 2.0)
