extends RefCounted
## 2.5D 空间层（R9 建立，R10 改成「平面地板」模型）
##
## R9 的做法：逻辑是纯 2D 的 (x, y)，y 永远是同一条地平线，另给每个实体一个 depth 做投影。
## R10 改成俯视平面后，更自然的模型是：**实体的 global_position 就是它在地板上的落点**，
## 地板是一条从近到远铺开的平面：
##
##   y = 760（FLOOR_NEAR_Y）  →  z = 0   贴着镜头（最近，画得最大）
##   y = 510（FLOOR_FAR_Y）   →  z = 1   贴着后墙（最远，画得最小）
##
## 于是「往里走」= 往上走，「往外走」= 往下走，深度 z 由 y 直接推导：
##   depth_of(y) = (FLOOR_NEAR_Y - y) / DEPTH_SPAN
##   y_of(z)     = FLOOR_NEAR_Y - DEPTH_SPAN * z
##
## 这样命中矩形、攻击矩形、AI 距离全部天然工作在平面上，不需要任何特判。
## z 仍然负责三件事：画多大（scale_of）、谁先画（z_order）、能不能互相打到（lane_ok）。

## 地板纵深（世界像素）：z 从 0 到 1 时 y 的跨度
const DEPTH_SPAN := 250.0
## z = 0（最近）时脚底所在的世界 y
const FLOOR_NEAR_Y := 760.0
## z = 1（最远）时的世界 y
const FLOOR_FAR_Y := 510.0
## 近端 / 远端缩放
const SCALE_NEAR := 1.08
const SCALE_FAR := 0.80
## 同一条刀路的容差：|zA - zB| <= LANE_TOL 才判定能互相打到（0.26 ≈ 65 px 身位）
const LANE_TOL := 0.26
## 深度移动速度（每秒 z 变化量）—— 仅用于需要「按深度推」的旧接口
const MOVE_SPEED := 0.90
## 玩家默认站位（略偏前）
const PLAYER_Z := 0.34
## 平面移动速度（与 player.SPEED 对齐，供敌人 / 提示用）
const PLANE_SPEED := 235.0

## 单间房间的地板矩形（世界坐标，所有房间共用同一块地方 —— 换房只是换内容）
const ROOM_X0 := 200.0
const ROOM_X1 := 1100.0
const ROOM_W := 900.0
## 相机固定点（一屏一间房）
const CAM_POS := Vector2(650.0, 545.0)


static func clamp_z(z: float) -> float:
	return clampf(z, 0.0, 1.0)


## 世界 y → 深度
static func depth_of(y: float) -> float:
	return clampf((FLOOR_NEAR_Y - y) / DEPTH_SPAN, 0.0, 1.0)


## 深度 → 世界 y（脚底落点）
static func y_of(z: float) -> float:
	return FLOOR_NEAR_Y - DEPTH_SPAN * clamp_z(z)


## 深度 → 缩放
static func scale_of(z: float) -> float:
	return lerpf(SCALE_NEAR, SCALE_FAR, clamp_z(z))


## 深度 → 脚底上移量（画地板 / 台面时用，实体本身不需要）
static func lift(z: float) -> float:
	return DEPTH_SPAN * clamp_z(z)


## 两个深度是否在同一条刀路上（能互相打到）
static func lane_ok(a: float, b: float) -> bool:
	return absf(clamp_z(a) - clamp_z(b)) <= LANE_TOL


## 深度 → z_index（越靠里越小 = 越先画）
static func z_order(z: float) -> int:
	return int(round((1.0 - clamp_z(z)) * 20.0))


## 深度 → 明暗系数（越靠里越暗，进一步拉开纵深）
static func shade(z: float) -> float:
	return lerpf(1.0, 0.62, clamp_z(z))


## 深度 → 阴影浓度（越靠里越淡）
static func shadow_alpha(z: float) -> float:
	return lerpf(0.34, 0.15, clamp_z(z))


## 深度 → 阴影横向半径倍数
static func shadow_scale(z: float) -> float:
	return scale_of(z)


## 把颜色按深度压暗
static func dim(c: Color, z: float) -> Color:
	var k := shade(z)
	return Color(c.r * k, c.g * k, c.b * k, c.a)


## 地板在屏幕上向后延伸的偏移（世界像素）
static func back_off() -> float:
	return DEPTH_SPAN


## 实体绘制用的变换：只按深度缩放（脚底原点不动）
static func apply_draw(node: CanvasItem, z: float) -> void:
	var s := scale_of(z)
	node.draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))


## 兼容旧接口：站在地上的影子
static func shadow_pos(z: float, foot_y: float) -> Vector2:
	return Vector2(0.0, foot_y - lift(z))


## 地板上的点是否在房间内（含边距）
static func in_room(p: Vector2, pad: float = 0.0) -> bool:
	return p.x >= ROOM_X0 + pad and p.x <= ROOM_X1 - pad \
		and p.y >= FLOOR_FAR_Y + pad * 0.6 and p.y <= FLOOR_NEAR_Y - pad * 0.3
