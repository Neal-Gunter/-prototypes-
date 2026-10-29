extends Node2D
## R37 · 旧影（「轮回台」的机制变奏）
##
## 它是**你刚才那几秒的走位**的回放：把玩家最近的坐标轨迹录下来，
## 让一个半透明的影子沿这条轨迹再走一遍。你绕圈，它也绕圈；
## 你贴边走，它也贴边走 —— 所以这一关的正解是**打破自己的节奏**。
##
## 铁律与同伴 / 符阵一致：它只读玩家坐标、只扣玩家气血，**不接管任何操作**。
##
## 注意：不是「上一局」的存档回放（那要跨进程存轨迹），
## 而是**同一局内最近 4 秒**的轨迹 —— 手感上更像「它记住了你」，
## 也让这套机制不必依赖存档格式。

const TOUCH_R := 34.0        # 碰到就扣血
const TOUCH_CD := 0.8        # 同一次接触的冷却
const DEFAULT_LIFE := 8.0    # 存在时长，到点自行消散
const MIN_PATH := 2          # 少于两个点就没法「走」了，退化成追击

var path: Array = []         # Array[Vector2]，录制下来的轨迹
var idx := 0
var speed := 330.0
var life := DEFAULT_LIFE
var player = null
var fx = null

var dead := false
var hits := 0

var _cool := 0.0
var _t := 0.0
var _trail: Array = []       # 拖影（纯表现）


## 参数不标类型 —— 与 companion.gd / seal.gd 一致，自测才能注入 Mock（RefCounted）
func setup(p_path: Array, p = null, fx_node = null, spd := 330.0) -> void:
	path = []
	for v in p_path:
		path.append(v)
	idx = 0
	speed = spd
	player = p
	fx = fx_node
	life = DEFAULT_LIFE
	z_index = 12
	if path.size() > 0:
		global_position = path[0]


## 沿轨迹走一步。抽成公开方法 —— 自测可直接推帧，不必等物理循环。
func advance(dt: float) -> void:
	if dead:
		return
	_t += dt
	_cool = maxf(0.0, _cool - dt)
	life -= dt
	if life <= 0.0:
		dead = true
		return

	_trail.push_front(global_position)
	if _trail.size() > 7:
		_trail.resize(7)

	if path.size() >= MIN_PATH:
		var target: Vector2 = path[idx]
		var to: Vector2 = target - global_position
		var step: float = speed * dt
		if to.length() <= step:
			global_position = target
			idx = (idx + 1) % path.size()
		else:
			global_position += to.normalized() * step
	elif player != null and is_instance_valid(player) and not bool(player.get("dead")):
		# 轨迹太短（开局就召）→ 退化成「朝玩家飘」
		var to2: Vector2 = player.global_position - global_position
		if to2.length() > 1.0:
			global_position += to2.normalized() * speed * dt

	_touch_check()


func _touch_check() -> void:
	if _cool > 0.0:
		return
	if player == null or not is_instance_valid(player):
		return
	if bool(player.get("dead")):
		return
	if global_position.distance_to(player.global_position) > TOUCH_R:
		return
	_cool = TOUCH_CD
	hits += 1
	if player.has_method("take_hit"):
		player.take_hit(global_position, false)
	if fx != null:
		fx.ring(global_position, 4.0, 30.0, Color(0.72, 0.6, 1.0), 0.3, 2.0)
	SFX.play("hit", 1.25, -20.0)


func _process(delta: float) -> void:
	advance(delta)
	if dead and _t > 0.0:
		queue_free()


func _draw() -> void:
	if dead:
		return
	var fade: float = clampf(life / DEFAULT_LIFE, 0.0, 1.0)
	var a: float = 0.30 + 0.28 * fade
	var col := Color(0.72, 0.6, 1.0, a)
	# 拖影：越靠后越淡
	for i in _trail.size():
		var t: float = float(i) / float(maxi(1, _trail.size()))
		var off: Vector2 = _trail[i] - global_position
		draw_circle(off + Vector2(0, -20.0), 11.0 * (1.0 - t * 0.5),
			Color(col.r, col.g, col.b, a * 0.16 * (1.0 - t)))
	# 身体：一个人形剪影（不做美术，只做「像你」的轮廓）
	draw_circle(Vector2(0, -34.0), 9.0, Color(col.r, col.g, col.b, a * 0.85))
	draw_line(Vector2(0, -26.0), Vector2(0, -6.0), col, 6.0)
	draw_line(Vector2(0, -20.0), Vector2(-9.0, -12.0), col, 3.0)
	draw_line(Vector2(0, -20.0), Vector2(9.0, -12.0), col, 3.0)
	draw_line(Vector2(0, -6.0), Vector2(-7.0, 4.0), col, 3.0)
	draw_line(Vector2(0, -6.0), Vector2(7.0, 4.0), col, 3.0)
	# 脚下光圈：提示「这是回响，不是活人」
	var pulse: float = 0.5 + 0.5 * sin(_t * 4.0)
	draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 20,
		Color(col.r, col.g, col.b, 0.20 + 0.18 * pulse), 1.6)
