extends Node2D
## R35 · 灵兽蛋（精英房掉落的可拾取物）。玩家走到附近即获得一只同伴。
## 纯绘制，无文字（headless 下 draw_string 无字体会报错，文字交给 fx.text）。

var kind := 0      # 对应 companion.Kind
var _bob := 0.0


func _process(delta: float) -> void:
	_bob += delta
	position.y += sin(_bob * 3.0) * 0.3


func _draw() -> void:
	var col := Color(0.92, 0.86, 0.62)
	# 蛋身：椭圆（用两个圆近似）
	draw_circle(Vector2(0.0, 2.0), 15.0, col)
	draw_circle(Vector2(0.0, -6.0), 11.0, col)
	# 高光
	draw_circle(Vector2(-5.0, -8.0), 4.0, Color(1.0, 1.0, 1.0, 0.7))
	# 外圈微光
	draw_arc(Vector2(0.0, -2.0), 19.0, 0.0, TAU, 28, Color(0.7, 0.6, 0.3, 0.6), 2.0)
