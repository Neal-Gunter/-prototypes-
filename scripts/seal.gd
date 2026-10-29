extends Node2D
## R36 · 地面符阵（「符箓秘境」的机制变奏）
##
## 踩上去触发一次：奇数位「生符」回灵力，偶数位「煞符」灼烧 1 点。
## **一次性** —— 触发后熄灭；重进房间会重新生成，所以每趟都得重新踩。
##
## 铁律与同伴一致：它只读玩家坐标、只改玩家资源，**不接管任何操作**。

const RADIUS := 46.0

var good := true          # true = 生符（增益）/ false = 煞符（减益）
var used := false
var player = null
var fx = null

var _t := 0.0


## 参数不标类型 —— 与 companion.gd 一致，自测才能注入 Mock（RefCounted）
func setup(is_good: bool, pos: Vector2, p = null, fx_node = null) -> void:
	good = is_good
	global_position = pos
	player = p
	fx = fx_node
	z_index = 2


func _process(delta: float) -> void:
	_t += delta
	if used or player == null or not is_instance_valid(player):
		return
	if bool(player.get("dead")):
		return
	if global_position.distance_to(player.global_position) <= RADIUS:
		trigger()


## 真正结算一次。抽成公开方法 —— 自测可直接调，不必等物理帧。
func trigger() -> void:
	if used:
		return
	used = true
	if good:
		if player != null and is_instance_valid(player) and player.has_method("add_stamina"):
			player.add_stamina(12.0)
		if fx != null:
			fx.text(global_position + Vector2(0, -34.0), "生 符 · 灵 力",
				Color(0.6, 1.0, 0.78), 15, 30)
			fx.ring(global_position, 6.0, 54.0, Color(0.6, 1.0, 0.78), 0.35, 2.4)
		SFX.play("gate", 1.2, -16.0)
	else:
		if player != null and is_instance_valid(player) and player.has_method("take_hit"):
			player.take_hit(global_position, false)
		if fx != null:
			fx.text(global_position + Vector2(0, -34.0), "煞 符",
				Color(1.0, 0.55, 0.5), 15, 30)
			fx.ring(global_position, 6.0, 54.0, Color(1.0, 0.55, 0.5), 0.35, 2.4)
		SFX.play("gate", 0.8, -16.0)


func _draw() -> void:
	var col := Color(0.55, 0.95, 0.78) if good else Color(0.95, 0.45, 0.42)
	var a := 0.16 if used else 0.34
	var pulse := 0.5 + 0.5 * sin(_t * 2.6)
	draw_circle(Vector2.ZERO, RADIUS, Color(col.r, col.g, col.b, a * 0.5))
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 32,
		Color(col.r, col.g, col.b, a + 0.25 * pulse), 2.2)
	draw_arc(Vector2.ZERO, RADIUS * 0.62, 0.0, TAU, 24, Color(col.r, col.g, col.b, a * 0.8), 1.4)
	draw_circle(Vector2.ZERO, 9.0, Color(col.r, col.g, col.b, 0.55 if not used else 0.22))
