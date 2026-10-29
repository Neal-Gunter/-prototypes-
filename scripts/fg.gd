extends Node2D
## 前景遮挡层（2.5D 纵深的最后一层）：
## 贴着镜头、比场景移动更快的近景剪影 —— 只用来「框住」画面，绝不挡住战斗区。
## 两种元素：
##   1. 从画面上方垂下来的铁链（只占顶部一条，会轻轻摆动）
##   2. 只有滑到画面左右边缘时才出现的粗石柱（进出画面时形成擦身而过的感觉）
## z_index 由 main 设为 80（画在角色之前）。

const PAR := 1.26          # 视差系数：比 1.0 快 = 离镜头更近
const C_BASE := Color(0.008, 0.013, 0.020, 0.98)
const C_EDGE := Color(0.15, 0.23, 0.32, 0.20)
const EDGE_W := 250.0      # 石柱只在离屏幕边缘这么近时才画

var cam: Camera2D
var _t := 0.0
var _props: Array = []
## R15：Boss 房禁制落下时近景石柱内收（0 = 正常，1 = 完全内收），压缩可视区
var squeeze := 0.0
## R15：关卡三伪楼层 —— 0 = 上排（垂链稀），1 = 下排（垂链密，离镜头更近）
var tier := 0


func set_squeeze(v: float) -> void:
	squeeze = clampf(v, 0.0, 1.0)


func set_tier(t: int) -> void:
	tier = clampi(t, 0, 1)


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 771026
	var x := -3200.0
	while x < 20400.0:
		_props.append({
			"x": x,
			"chain": rng.randf() < 0.55,
			"w": rng.randf_range(54.0, 120.0),
			"h": rng.randf_range(120.0, 260.0),
			"ph": rng.randf_range(0.0, TAU),
		})
		x += rng.randf_range(420.0, 1150.0)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var vs := get_viewport_rect().size
	var cp := Vector2.ZERO
	if cam != null and is_instance_valid(cam):
		cp = cam.global_position
	# R15：禁制落下内收 —— 近景柱子的「有效范围」变大，等于往画面中间挤
	var edge_w := EDGE_W * (1.0 + 0.60 * squeeze)
	for p in _props:
		var sx: float = (float(p["x"]) - cp.x) * PAR + vs.x * 0.5
		# 禁制落下时把近景往画面中心拽一把 —— 只加宽不移动的话，几乎看不出「门关上了」
		if squeeze > 0.01:
			sx += (vs.x * 0.5 - sx) * 0.11 * squeeze
		if sx < -edge_w - 200.0 or sx > vs.x + edge_w + 200.0:
			continue
		if bool(p["chain"]):
			_hanging_chain(sx, float(p["h"]), float(p["ph"]))
		else:
			# 只有靠近左右边缘才画柱子，避免挡住中间的战斗区
			var edge_d := minf(sx, vs.x - sx)
			if edge_d > edge_w:
				continue
			var a := 1.0 - clampf(edge_d / edge_w, 0.0, 1.0)
			# 内收时柱子整体变粗一点，压迫感更足
			_edge_pillar(sx, vs.y, float(p["w"]) * (1.0 + 0.22 * squeeze),
				float(p["h"]), a)
	if tier == 1:
		_draw_near_chains(vs, cp)
	# 禁制落下时左右再压两道暗边，把可视区「夹」出来
	if squeeze > 0.01:
		var bw := 118.0 * squeeze
		draw_rect(Rect2(0, 0, bw, vs.y), Color(0.0, 0.0, 0.0, 0.62 * squeeze))
		draw_rect(Rect2(vs.x - bw, 0, bw, vs.y), Color(0.0, 0.0, 0.0, 0.62 * squeeze))


## R15 关卡三下排：离镜头更近的一层垂链（比上排密，随相机更快滑过）
## 近景链本身几乎全黑，靠一圈更亮的轮廓光才读得出来 —— 所以 rim 拉高
func _draw_near_chains(vs: Vector2, cp: Vector2) -> void:
	for i in 6:
		var bx := float(i) * 270.0 + 40.0
		var sx := fposmod(bx - cp.x * 1.55, vs.x + 540.0) - 270.0
		var h := 168.0 + float((i * 37) % 108)
		_hanging_chain(sx, h, float(i) * 1.7, 2.6, 1.25)


## 从画面上方垂下来的近景铁链（带轻微摆动）
func _hanging_chain(cx: float, h: float, ph: float, rim: float = 1.0, wide: float = 1.0) -> void:
	var sway := sin(_t * 0.8 + ph) * 5.0
	var links := int(minf(h, 300.0) / 24.0)
	for i in links:
		var y := -18.0 + i * 24.0
		var r := (8.5 - float(i) * 0.12) * wide
		var f := float(i) / float(maxi(links, 1))
		var lx := cx + sway * f
		draw_arc(Vector2(lx, y), r, 0.0, TAU, 12, C_BASE, 4.2, true)
		if i % 2 == 0:
			draw_arc(Vector2(lx, y), r + 1.6, 0.0, TAU, 12,
				Color(C_EDGE.r, C_EDGE.g, C_EDGE.b, C_EDGE.a * rim), 1.2, true)


## 贴在画面左 / 右边缘的粗石柱（越靠边越实）
func _edge_pillar(cx: float, base_y: float, w: float, h: float, a: float) -> void:
	var c := Color(C_BASE.r, C_BASE.g, C_BASE.b, C_BASE.a * a)
	var pts := PackedVector2Array([
		Vector2(cx - w * 0.5, base_y + 40.0),
		Vector2(cx - w * 0.40, base_y - h * 0.62),
		Vector2(cx - w * 0.14, base_y - h),
		Vector2(cx + w * 0.20, base_y - h * 0.94),
		Vector2(cx + w * 0.44, base_y - h * 0.55),
		Vector2(cx + w * 0.5, base_y + 40.0),
	])
	draw_colored_polygon(pts, c)
	draw_polyline(PackedVector2Array([
		Vector2(cx - w * 0.40, base_y - h * 0.62),
		Vector2(cx - w * 0.14, base_y - h),
		Vector2(cx + w * 0.20, base_y - h * 0.94),
	]), Color(C_EDGE.r, C_EDGE.g, C_EDGE.b, C_EDGE.a * a), 2.0, true)
