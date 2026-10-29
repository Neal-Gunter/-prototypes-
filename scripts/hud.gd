extends CanvasLayer
## HUD：气血面具、道蕴容器、Boss 血条、提示文字、各种全屏状态。

const RelicScript := preload("res://scripts/relics.gd")
const WeaponScript := preload("res://scripts/weapons.gd")
const LoreScript := preload("res://scripts/lore.gd")
const InscribeScript := preload("res://scripts/inscribe.gd")
const ConsumeScript := preload("res://scripts/consumable.gd")
const RoomScript := preload("res://scripts/rooms.gd")
const SpaceScript := preload("res://scripts/space.gd")
const MeridianScript := preload("res://scripts/meridian.gd")
const AlchemyScript := preload("res://scripts/alchemy.gd")
const CompanionScript := preload("res://scripts/companion.gd")   # R35 同伴
## R33c：丹房是经脉页的第 4 个页签（和 main.gd 的 MER_TAB_ALCH 保持一致）
const MER_TAB_ALCH := 3

var player: Node = null
var boss: Node = null
var game: Node = null
var mode := "title"
var touch_mode := false
var win_title := "前 世 身 · 已 陨 落"
var dark := 0.0        # 第三阶段环境变暗
var white := 0.0       # 天雷闪光
var level_name := ""   # 当前关卡名（肉鸽）
var room_name := ""    # 当前房间名（肉鸽）

var prompt_text := ""
var prompt_t := 0.0
## 剧情碎片浮层
var lore_title := ""
var lore_text := ""
var lore_t := 0.0
## R28：镜卷（第 13 卷）用大卡 + 专属配色，和普通残卷区分开
var lore_accent := Color(0, 0, 0, 0)
var _prompt_hold := 0.0
var _t := 0.0
# R25：win 页演出计时（进 win 页从 0 计，离开归零）
var _win_t := 0.0
var font: Font
var _vignette: ColorRect
var _mat: ShaderMaterial
var _canvas: Control

## R10：右上角常驻三颗圆钮 —— 暂停 / 换武器 / 设置（PC 用鼠标、手机用拇指）
const TOP_BTN := [
	{"id": "pause", "c": Vector2(1088.0, 38.0), "r": 24.0, "t": "Ⅱ"},
	{"id": "weapon", "c": Vector2(1156.0, 38.0), "r": 24.0, "t": "换"},
	{"id": "settings", "c": Vector2(1224.0, 38.0), "r": 24.0, "t": "设"},
]
## 小地图格子
const MAP_CELL := Vector2(44.0, 26.0)
const MAP_ORIGIN := Vector2(1100.0, 78.0)


## 命中右上角哪颗钮（返回 "" / "pause" / "weapon" / "settings"）
func top_hit(p: Vector2) -> String:
	for b in TOP_BTN:
		if p.distance_to(Vector2(b["c"])) <= float(b["r"]) * 1.22:
			return str(b["id"])
	return ""


func _ready() -> void:
	layer = 10
	font = load("res://fonts/NotoSansSC.ttf")

	_vignette = ColorRect.new()
	_vignette.color = Color(1, 1, 1, 1)
	_vignette.position = Vector2.ZERO
	_vignette.size = Vector2(1280, 720)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh: Shader = load("res://shaders/vignette.gdshader")
	if sh:
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_vignette.material = _mat
	add_child(_vignette)

	_canvas = Control.new()
	_canvas.position = Vector2.ZERO
	_canvas.size = Vector2(1280, 720)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_canvas_draw)
	add_child(_canvas)


func show_prompt(txt: String, hold: float = 3.2) -> void:
	prompt_text = txt
	prompt_t = 1.0
	_prompt_hold = hold


## 拾取剧情碎片时从底部浮出的文字
func show_lore(title: String, txt: String, hold: float = 5.5,
		accent: Color = Color(0, 0, 0, 0)) -> void:
	lore_title = title
	lore_text = txt
	lore_t = hold
	# R28：accent 有透明度 = 特殊卷（镜卷），走大卡 + 自动折行
	lore_accent = accent


func _process(delta: float) -> void:
	_t += delta
	# R25：win 页演出计时
	if mode == "win":
		_win_t += delta
	else:
		_win_t = 0.0
	if _mat:
		_mat.set_shader_parameter("hurt", Game.hurt_flash)
		_mat.set_shader_parameter("perfect", Game.perfect_flash)
		_mat.set_shader_parameter("darken", dark)
		_mat.set_shader_parameter("white", white)
	if _prompt_hold > 0.0:
		_prompt_hold -= delta
	else:
		prompt_t = maxf(0.0, prompt_t - delta * 1.6)
	if lore_t > 0.0:
		lore_t = maxf(0.0, lore_t - delta)
	_canvas.queue_redraw()


# ------------------------------------------------------------------ 绘制
func _on_canvas_draw() -> void:
	var c := _canvas
	var w := 1280.0

	if mode == "title":
		_draw_title(c)
		return

	if mode == "weapon":
		_draw_weapon(c)
		return

	if mode == "codex":
		_draw_codex(c)
		return

	if mode == "meridian":
		_draw_meridian(c)
		return

	# 进行中的 HUD 底图（暂停 / 法宝 / 飞升 / 设置 都在它上面叠面板）
	if mode == "play" or mode == "pause" or mode == "reward" or mode == "replace" 			or mode == "clear" or mode == "setting" or mode == "branch" or mode == "event" 			or mode == "forge":
		_draw_hud(c)

	if mode == "pause":
		c.draw_rect(Rect2(0, 0, 1280, 720), Color(0.02, 0.03, 0.045, 0.72))
		_text_c(c, 340, "暂  停", 56, Color(0.9, 0.95, 1.0))
		_text_c(c, 400, "点 击 屏 幕 继 续" if touch_mode else "按 Esc 继续", 22, Color(0.6, 0.72, 0.85))
		_text_c(c, 464, "A / D  左右      W / S  入阴 / 还阳（纵深）      Shift  冲刺", 19, Color(0.55, 0.68, 0.8))
		_text_c(c, 494, "J  挥刀（连按 = 连招）    L  格挡    U / I  蓄力斩·绝招    K  聚集治疗", 19, Color(0.55, 0.68, 0.8))
		_text_c(c, 528, "F  处决（道心失守时）      C  残卷图鉴      R  重新开始", 19, Color(0.55, 0.68, 0.8))
		_text_c(c, 558, "灵力（左上绿条）：出刀 / 冲刺 / 举盾都消耗，用完会力竭", 19, Color(0.6, 0.92, 0.78))
		_text_c(c, 588, "剑意交锋：敌人刀锋亮起的瞬间挥刀，两刀相撞", 20, Color(0.8, 0.9, 1.0))
		_text_c(c, 616, "剑意交锋与格挡会累积敌人头顶的硬直条，打满 → 长硬直", 19, Color(0.7, 0.85, 0.95))
		_text_c(c, 644, "格挡：正面挡刀不掉血，护体罡气满 → 道心失守（不即死）　｜　攻速：连打越快，5 秒不砍中会回落", 18,
			Color(0.7, 0.85, 0.95))
		_text_c(c, 670, "位次：剑 / 体 / 灵 各 3 格（装满后可花 45 道蕴扩到 4 格）；剑位放飞剑类 + 灵位 2 件道蕴 = 飞剑流", 18,
			Color(0.62, 0.95, 1.0))
		var cb := Rect2(660, 686, 380, 30)
		var fb := Rect2(240, 686, 380, 30)
		if game != null and is_instance_valid(game):
			cb = game.BTN_PAUSE_CODEX
			fb = game.BTN_PAUSE_FORGE
		# R31：左边「兵器铭刻」、右边「残卷图鉴」
		var iron_n := 0
		var slot_txt := "— / —"
		if player != null and is_instance_valid(player):
			iron_n = player.iron
			var slots: Array = player.inscribe_slots()
			slot_txt = "%s / %s" % [
				InscribeScript.name_of(str(slots[0])) if str(slots[0]) != "" else "空",
				InscribeScript.name_of(str(slots[1])) if str(slots[1]) != "" else "空"]
		c.draw_rect(fb, Color(0.16, 0.13, 0.09, 0.9))
		c.draw_rect(fb, Color(0.86, 0.72, 0.42, 0.6), false, 1.0)
		_text_rc(c, fb, fb.position.y + 21.0, "兵 器 铭 刻　（M / 点此处）　精铁 %d" % iron_n, 15,
			Color(1.0, 0.9, 0.68, 0.95))
		c.draw_rect(cb, Color(0.10, 0.16, 0.22, 0.88))
		c.draw_rect(cb, Color(0.42, 0.62, 0.78, 0.55), false, 1.0)
		_text_rc(c, cb, cb.position.y + 21.0, "残 卷 图 鉴　（C / 点此处）", 15,
			Color(0.95, 0.86, 0.6, 0.95))

	if mode == "reward" or mode == "replace":
		_draw_reward(c)

	if mode == "branch":
		_draw_branch(c)

	if mode == "event":
		_draw_event(c)

	if mode == "clear":
		_draw_clear(c)

	if mode == "setting":
		_draw_setting(c)

	if mode == "forge":
		_draw_forge(c)

	if mode == "dead":
		c.draw_rect(Rect2(0, 0, 1280, 720), Color(0.05, 0.01, 0.02, 0.62))
		_text_c(c, 330, "你  倒  下  了", 60, Color(0.95, 0.86, 0.86))
		if game != null and is_instance_valid(game) and int(game.daoyun_gain) > 0:
			_text_c(c, 372, "道 痕 +%d　（共 %d）" % [int(game.daoyun_gain), Cfg.daoyun], 20,
				Color(0.98, 0.88, 0.58, 0.95), 5)
		var blink := 0.5 + 0.5 * sin(_t * 4.0)
		_text_c(c, 400, "点 击 屏 幕 重 新 开 始" if touch_mode else "按 R 从记录点重新开始", 24, Color(0.85, 0.9, 0.95, blink))

	if mode == "win":
		var is_true: bool = game != null and bool(game.get("true_ending"))
		var wt := _win_t
		# R25：普通结算保持静态原样；真结局做「合页 + 停摆」演出（按 R 随时可跳过）
		var fade := 0.55 if not is_true else 0.55 * _ramp(wt, 0.0, 0.6)
		if fade > 0.005:
			c.draw_rect(Rect2(0, 0, 1280, 720), Color(0.01, 0.03, 0.05, fade))
		if not is_true:
			_text_c(c, 300, win_title, 58, Color(0.92, 0.97, 1.0))
			_text_c(c, 366, "剑意交锋 %d 次　悟道 %d 次　命中 %d 次" % [Game.clash_count, Game.perfect_count, Game.hit_count], 21,
				Color(0.6, 0.8, 0.95))
			_text_c(c, 396, "格挡 %d 次　精准格挡 %d 次　最高连斩 %d" % [Game.guard_count, Game.perfect_guard_count, Game.max_combo], 21,
				Color(0.6, 0.8, 0.95))
			_text_c(c, 424, "硬直打破 %d 次　弹反弹幕 %d 次" % [Game.break_count, Game.deflect_count], 21,
				Color(0.6, 0.8, 0.95))
			if game != null and is_instance_valid(game) and int(game.daoyun_gain) > 0:
				_text_c(c, 452, "道 痕 +%d　（共 %d）" % [int(game.daoyun_gain), Cfg.daoyun], 19,
					Color(0.98, 0.88, 0.58, 0.95), 5)
			# R38：业力与结局分支（三结局挂在结算页，不动真结局演出）
			_draw_karma_line(c, 480)
			var blink2 := 0.5 + 0.5 * sin(_t * 4.0)
			_text_c(c, 540, "点 击 屏 幕 再 来 一 次" if touch_mode else "按 R 再来一次", 24, Color(0.85, 0.92, 1.0, blink2))
			return

		# —— 真结局演出 ——
		# 标题：0.35s 起淡入下滑
		var ta := _ramp(wt, 0.35, 0.95)
		if ta > 0.01:
			_text_c(c, 300.0 - 24.0 * (1.0 - ta), "心 魔 · 已 照 见", 58, Color(0.92, 0.97, 1.0, ta))
		# 残卷合页：0.7s 起逐页闭合（页数 = 已收卷数），闭合后逐页淡出
		var npg: int = maxi(1, Cfg.fragment_total())
		var all_gone := true
		for i in npg:
			var t0 := 0.7 + 0.07 * float(i)
			var k := _ramp(wt, t0, t0 + 0.3)
			var alpha := 1.0 - _ramp(wt, t0 + 0.55, t0 + 0.85)
			if alpha > 0.01:
				all_gone = false
				var pw := 26.0 * (1.0 - 0.92 * k)
				var px := 640.0 + (float(i) - float(npg - 1) * 0.5) * 30.0
				c.draw_rect(Rect2(px - pw * 0.5, 316.0, pw, 30.0), Color(0.98, 0.93, 0.78, 0.72 * alpha))
				c.draw_rect(Rect2(px - pw * 0.5, 316.0, minf(pw, 3.0), 30.0), Color(0.55, 0.42, 0.3, 0.8 * alpha))
		# 全部淡出后 → 一根鎏金书脊（合上的残卷）
		var tb := 0.7 + 0.07 * float(npg - 1) + 0.85
		var bk := _ramp(wt, tb, tb + 0.4)
		if bk > 0.01:
			var bw := 90.0 * bk
			c.draw_rect(Rect2(640.0 - bw * 0.5, 328.0, bw, 6.0), Color(1.0, 0.90, 0.66, 0.8 * bk))
		# 统计三行：1.1s 起淡入
		var sa := _ramp(wt, 1.1, 1.7)
		if sa > 0.01:
			_text_c(c, 366, "剑意交锋 %d 次　悟道 %d 次　命中 %d 次" % [Game.clash_count, Game.perfect_count, Game.hit_count], 21,
				Color(0.6, 0.8, 0.95, sa))
			_text_c(c, 396, "格挡 %d 次　精准格挡 %d 次　最高连斩 %d" % [Game.guard_count, Game.perfect_guard_count, Game.max_combo], 21,
				Color(0.6, 0.8, 0.95, sa))
			_text_c(c, 424, "硬直打破 %d 次　弹反弹幕 %d 次" % [Game.break_count, Game.deflect_count], 21,
				Color(0.6, 0.8, 0.95, sa))
		# 钟摆停摆：1.8s 起摆动，振幅衰减，~5s 后停摆亮起微光
		var pa := _ramp(wt, 1.8, 2.4)
		if pa > 0.01:
			var pt := maxf(0.0, wt - 1.8)
			var ang := pendulum_angle(pt)
			var piv := Vector2(640.0, 128.0)
			var tip := piv + Vector2(sin(ang), cos(ang)) * 92.0
			c.draw_line(piv, tip, Color(0.7, 0.78, 0.9, 0.85 * pa), 3.0)
			c.draw_circle(piv, 5.0, Color(0.85, 0.9, 1.0, 0.9 * pa))
			c.draw_circle(tip, 11.0, Color(0.98, 0.93, 0.78, 0.9 * pa))
			if absf(ang) < 0.02:
				var glow := 0.35 + 0.25 * sin(_t * 2.0)
				c.draw_circle(tip, 16.0, Color(1.0, 0.95, 0.8, glow * pa * 0.45))
		# 终局语 + 落款 + 重开提示
		var qa := _ramp(wt, 2.5, 3.1)
		if qa > 0.01:
			var et := LoreScript.ending_text(Cfg.fragment_total())
			_text_c(c, 452, "「%s」" % et, 20, Color(0.98, 0.93, 0.78, qa))
		var ia := _ramp(wt, 2.9, 3.4)
		if ia > 0.01:
			var it := LoreScript.identity_title(Cfg.fragment_total())
			if it != "":
				_text_c(c, 486, "—— %s ——" % it, 17, Color(1.0, 0.90, 0.66, 0.9 * ia))
		if wt > 3.4:
			var blink2 := 0.5 + 0.5 * sin(_t * 4.0)
			# R38：真结局也标业力 —— 你走到了终章，但一路怎么走的另算
			_draw_karma_line(c, 514, false)
			_text_c(c, 556, "点 击 屏 幕 再 来 一 次" if touch_mode else "按 R 再来一次", 24, Color(0.85, 0.92, 1.0, blink2))


func _draw_hud(c: Control) -> void:
	# 气血面具
	var hp := 5
	var mx := 5
	if player and is_instance_valid(player):
		hp = player.hp
		mx = player.max_hp()
	for i in mx:
		var p := Vector2(46 + i * 33, 46)
		_mask(c, p, 12.0, i < hp)

	# R38：业力（左上，血条上方一行）—— 慢变量，不必时刻盯，但一瞥要知道自己在往哪条路上走。
	# 不放右上角：那里被触屏的暂停/换/设按钮和快捷格占了，文字会被压住（R38 截图踩到）。
	# 只在非 0 时显示：0 = 人道，是人人都有的常态，不该占屏幕。
	if int(Game.karma) != 0:
		var kc := Color(0.86, 0.90, 0.94, 0.88)
		if Game.karma_branch() == 0:
			kc = Color(0.62, 0.98, 0.80, 0.95)
		elif Game.karma_branch() == 2:
			kc = Color(1.0, 0.58, 0.54, 0.95)
		var ks := "+" if int(Game.karma) > 0 else ""
		_text(c, Vector2(24.0, 24.0), "业 力 %s%d · %s" % [ks, int(Game.karma), Game.karma_branch_name()],
			14, kc, 4)

	# R16：身份称号 —— 随残卷收集数变化（0 条不显示）
	var ident := LoreScript.identity_title(Cfg.fragment_total())
	if ident != "":
		var iremain := LoreScript.identity_remain(Cfg.fragment_total())
		_text(c, Vector2(24.0, 96.0), ident, 14, Color(1.0, 0.90, 0.66, 0.95), 4)
		if iremain > 0:
			_text(c, Vector2(24.0 + 14.0 * float(ident.length()) * 0.62 + 12.0, 96.0),
				"· 再 %d 卷" % iremain, 11, Color(0.62, 0.74, 0.88, 0.75), 3)

	# 道蕴容器
	var soul := 0.0
	if player and is_instance_valid(player):
		soul = player.soul
	var frac := clampf(soul / 99.0, 0.0, 1.0)
	var oc := Vector2(46, 108)
	c.draw_circle(oc, 26.0, Color(0.03, 0.05, 0.07, 0.85))
	c.draw_arc(oc, 26.0, 0.0, TAU, 40, Color(0.25, 0.4, 0.52, 0.9), 2.0, true)
	if frac > 0.02:
		var pulse := 0.85 + 0.15 * sin(_t * 3.0)
		c.draw_circle(oc, 22.0 * frac, Color(0.55, 0.9, 1.0, 0.22 * pulse))
		c.draw_circle(oc, 22.0 * frac, Color(0.65, 0.95, 1.0, 0.18))
		c.draw_arc(oc, 22.0 * frac, 0.0, TAU, 32, Color(0.8, 0.98, 1.0, 0.55), 1.5, true)
	if soul >= Game.SOUL_HEAL_COST:
		c.draw_arc(oc, 29.0, -PI * 0.5, -PI * 0.5 + TAU * (soul / 99.0), 40,
			Color(0.55, 0.9, 1.0, 0.55 + 0.25 * sin(_t * 5.0)), 2.0, true)

	# 灵力条
	var stam := 1.0
	var exh := false
	if player and is_instance_valid(player):
		stam = player.stamina_frac()
		exh = player.exhausted
	var sx := 26.0
	var sy := 68.0
	var sw := 156.0
	var sh := 7.0
	c.draw_rect(Rect2(sx - 1.5, sy - 1.5, sw + 3.0, sh + 3.0), Color(0.03, 0.045, 0.06, 0.9))
	c.draw_rect(Rect2(sx, sy, sw, sh), Color(0.10, 0.13, 0.16, 1.0))
	var scol := Color(0.45, 0.90, 0.72)
	if stam < 0.34:
		scol = Color(0.95, 0.70, 0.32)
	if exh:
		var fl := 0.55 + 0.45 * sin(_t * 16.0)
		scol = Color(1.0, 0.38, 0.34, fl)
	if stam > 0.005:
		c.draw_rect(Rect2(sx, sy, sw * stam, sh), scol)
		c.draw_rect(Rect2(sx, sy, sw * stam, 2.0), Color(1, 1, 1, 0.35))
	# 四等分刻度
	for i in range(1, 4):
		var tx := sx + sw * (float(i) / 4.0)
		c.draw_line(Vector2(tx, sy), Vector2(tx, sy + sh), Color(0.03, 0.05, 0.07, 0.65), 1.0)
	if exh:
		_text(c, Vector2(sx + sw + 8.0, sy + sh + 1.0), "力竭", 14, Color(1.0, 0.6, 0.5, 0.9), 4)

	# R29 符力条（只在符剑时出现）：5 格，逐格熄灭 —— 弹药要看得出还剩几发。
	# 位置放在灵力条右侧同一行：灵力条下沿是身份称号(96)与道蕴圆(108)，塞不进去。
	if player and is_instance_valid(player) and player.uses_rune():
		var rx := 190.0
		var ry := 66.0
		var rw := 104.0
		var rh := 7.0
		var rf: float = player.rune_frac()
		c.draw_rect(Rect2(rx - 1.5, ry - 1.5, rw + 3.0, rh + 3.0), Color(0.03, 0.045, 0.06, 0.9))
		c.draw_rect(Rect2(rx, ry, rw, rh), Color(0.10, 0.13, 0.16, 1.0))
		if rf > 0.004:
			var rcol := Color(0.80, 0.62, 1.0)
			if rf < 0.22:
				rcol = Color(1.0, 0.55, 0.62)
			c.draw_rect(Rect2(rx, ry, rw * rf, rh), rcol)
			c.draw_rect(Rect2(rx, ry, rw * rf, 2.0), Color(1, 1, 1, 0.35))
		# 5 格刻度：一眼数得出「还能打几发」
		for i in range(1, 5):
			var tx3 := rx + rw * (float(i) / 5.0)
			c.draw_line(Vector2(tx3, ry), Vector2(tx3, ry + rh), Color(0.03, 0.05, 0.07, 0.75), 1.0)
		_text(c, Vector2(rx + rw + 8.0, ry + rh), "符力 %d" % int(ceil(player.rune_power)),
			12, Color(0.84, 0.72, 1.0, 0.9), 4)

	# 攻速（热度：越打越快）
	var heat := 0.0
	var spd := 1.0
	if player and is_instance_valid(player):
		heat = player.heat_frac()
		spd = player.atk_speed()
	var ax := 90.0
	var ay := 104.0
	var aw := 96.0
	var ah := 5.0
	c.draw_rect(Rect2(ax - 1.5, ay - 1.5, aw + 3.0, ah + 3.0), Color(0.03, 0.045, 0.06, 0.9))
	c.draw_rect(Rect2(ax, ay, aw, ah), Color(0.10, 0.13, 0.16, 1.0))
	if heat > 0.004:
		var hc := Color(0.55, 0.72, 0.95).lerp(Color(1.0, 0.78, 0.35), heat)
		c.draw_rect(Rect2(ax, ay, aw * heat, ah), hc)
		c.draw_rect(Rect2(ax, ay, aw * heat, 1.6), Color(1, 1, 1, 0.35))
	for i in range(1, 4):
		var tx2 := ax + aw * (float(i) / 4.0)
		c.draw_line(Vector2(tx2, ay), Vector2(tx2, ay + ah), Color(0.03, 0.05, 0.07, 0.6), 1.0)
	if heat > 0.5:
		c.draw_arc(Vector2(ax + aw + 4.0, ay + ah * 0.5), 3.0, 0.0, TAU, 10,
			Color(1.0, 0.8, 0.4, 0.6 + 0.3 * sin(_t * 6.0)), 1.2, true)
	_text(c, Vector2(ax + aw + 10.0, ay + ah + 1.0), "攻速 ×%.2f" % spd, 13,
		Color(0.72, 0.84, 0.96, 0.85), 4)
	if player and is_instance_valid(player):
		# R29：从 (88,98) 挪到攻速条右上 —— 原来会和身份称号「守钟人 · 再 N 卷」撞在一起
		_text(c, Vector2(196.0, 96.0), str(player.weapon_name()), 13,
			Color(0.95, 0.88, 0.66, 0.9), 4)

	# R12 连招段位 / 动作标签：只在实际出刀时显示，避免常驻噪音
	# 取消窗口一开，整行转绿 —— 这是「现在可以撤了」的唯一提示
	if player and is_instance_valid(player) and player.combo_stage() > 0:
		var cs: int = player.combo_stage()
		var cl: int = player.combo_len()
		var tname: String = WeaponScript.tag_name(player.attack_tag())
		var cancel_ok: bool = player.can_cancel()
		var ccol := Color(1.0, 0.86, 0.55, 0.95)
		var ctxt := "%d/%d · %s" % [cs, cl, tname]
		if cancel_ok:
			ccol = Color(0.62, 1.0, 0.78, 1.0)
			ctxt += "  可取消"
		_text(c, Vector2(ax, ay + 24.0), ctxt, 13, ccol, 4)

	# 位次 / 套装进度（R13：位次 = 套系，每格最多 SLOT_CAP 件，装满即解锁流派）
	if player and is_instance_valid(player):
		var set_y := 176.0
		var shown := 0
		for tag in RelicScript.SLOT_ORDER:
			var n: int = player.slot_used(tag)
			if n <= 0:
				continue
			var scol2: Color = RelicScript.set_color(tag)
			# R16：容量读 player，扩容后是 4
			var cap: int = player.slot_cap(tag)
			var full: bool = n >= cap
			var label := "%s %d/%d" % [RelicScript.slot_name(tag), n, cap]
			var w2 := 52.0
			var rr := Rect2(24.0, set_y - 12.0, w2, 16.0)
			c.draw_rect(rr, Color(0.03, 0.05, 0.07, 0.72))
			c.draw_rect(rr, Color(scol2.r, scol2.g, scol2.b, 0.90 if full else 0.30), false, 1.0)
			if full:
				c.draw_rect(rr, Color(scol2.r, scol2.g, scol2.b, 0.18))
			_text(c, Vector2(30.0, set_y), label, 12,
				Color(1.0, 1.0, 1.0, 0.95) if full else Color(0.75, 0.85, 0.95, 0.8), 3)
			# 格子小点：一眼看出还剩几格
			for k in cap:
				var px := 24.0 + w2 + 6.0 + float(k) * 9.0
				c.draw_circle(Vector2(px, set_y - 4.0), 2.6,
					Color(scol2.r, scol2.g, scol2.b, 0.95) if k < n
					else Color(0.25, 0.32, 0.40, 0.9))
			set_y += 19.0
			shown += 1
		# 流派名（Build 身份）
		if shown > 0:
			var bt: String = player.build_title()
			var bcol := Color(0.80, 0.88, 1.0, 0.9)
			if bt == "飞 剑 流":
				bcol = Color(0.62, 0.95, 1.0, 1.0)
			elif bt == "剑 修":
				bcol = Color(1.0, 0.72, 0.60, 1.0)
			elif bt == "体 修":
				bcol = Color(0.66, 0.86, 1.0, 1.0)
			elif bt == "灵 御":
				bcol = Color(0.92, 0.80, 1.0, 1.0)
			var muts: Array = player.mutation_titles()
			if not muts.is_empty():
				bt += "  ·  " + str(muts[0])
				bcol = Color(1.0, 0.90, 0.62, 1.0)
			_text(c, Vector2(24.0, set_y), bt, 13, bcol, 4)

		# R35：同伴一览 —— 灵兽全自动（不显示血）、傀儡有 HP 会死。
		# 接在位次 / 流派名下面：set_y 是位次列表的实时下沿，天然不撞。
		var comps: Array = []
		if game != null and is_instance_valid(game):
			comps = game.companions
		if not comps.is_empty():
			var cy := set_y + 8.0
			for cc in comps:
				if cc == null or not is_instance_valid(cc) or bool(cc.get("dead")):
					continue
				var ck := int(cc.kind)
				var cnm: String = str(CompanionScript.NAMES.get(ck, "?"))
				var beast: bool = bool(CompanionScript.IS_BEAST.get(ck, false))
				var ccol3 := Color.from_hsv(float(CompanionScript.HUES.get(ck, 0.5)), 0.55, 1.0)
				var line := cnm
				if not beast:
					line += "  %d/%d" % [int(cc.hp), int(cc.max_hp)]
				_text(c, Vector2(24.0, cy), line, 12, ccol3, 3)
				cy += 16.0

	# 护体罡气（R11 · 只狼式躯干值）：0–100 横条，满 → 道心失守
	var posture := 0.0
	var pmax := 100.0
	var guarding := false
	var broken := false
	if player and is_instance_valid(player):
		posture = float(player.posture)
		pmax = float(player.posture_max())
		guarding = player.is_guarding()
		broken = player.is_broken()
	if posture > 0.5 or guarding or broken:
		var pw := 128.0
		var ph := 9.0
		var ppos := Vector2(24.0, 146.0)
		var back := Rect2(ppos, Vector2(pw, ph))
		c.draw_rect(back, Color(0.03, 0.05, 0.07, 0.80))
		var pfrac := clampf(posture / maxf(1.0, pmax), 0.0, 1.0)
		var fill_col := Color(1.0, 0.62, 0.35)
		if pfrac > 0.66:
			fill_col = Color(1.0, 0.38, 0.30)
		elif pfrac > 0.33:
			fill_col = Color(1.0, 0.78, 0.40)
		c.draw_rect(Rect2(ppos, Vector2(pw * pfrac, ph)), fill_col)
		c.draw_rect(back, Color(1.0, 0.90, 0.75, 0.5), false, 1.0)
		var lbl := "护体罡气"
		var lcol := Color(1.0, 0.86, 0.70, 0.92)
		if broken:
			lbl = "道 心 失 守"
			lcol = Color(1.0, 0.40, 0.40, 1.0)
		_text(c, Vector2(24.0, 141.0), lbl, 12, lcol, 3)

	# 连斩计数
	if game != null and is_instance_valid(game) and game.combo_hits >= 2:
		var ct := "连斩 × %d" % game.combo_hits
		var csz := font.get_string_size(ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
		_text(c, Vector2(1236.0 - csz.x, 106), ct, 20, Color(1.0, 0.85, 0.55, 0.95))

	# 剑意交锋计数
	if Game.clash_count > 0:
		var txt := "剑意交锋 × %d" % Game.clash_count
		var sz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
		var px := 1236.0 - sz.x
		_text(c, Vector2(px, 50), txt, 22, Color(0.85, 0.95, 1.0, 0.9))
		if Game.perfect_count > 0:
			var t2 := "完美 × %d" % Game.perfect_count
			_text(c, Vector2(1236.0 - font.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x, 78), t2, 18,
				Color(1.0, 0.88, 0.6, 0.9))

	# Boss 血条
	if boss != null and is_instance_valid(boss) and not boss.dead:
		_draw_boss_bar(c)

	# 提示
	if prompt_t > 0.0 and prompt_text != "":
		var a := clampf(prompt_t, 0.0, 1.0)
		# R36 顺手修：残卷浮层占住底部（普通框 596~670 / 镜卷大卡 512~670），
		# 提示原本固定画在 640，会被压在浮层里面。有浮层时上移。
		var has_lore: bool = lore_t > 0.0 and lore_text != ""
		var py := 484.0 if has_lore else (596.0 if touch_mode else 640.0)
		_text_c(c, py, prompt_text, 19 if touch_mode else 22,
			Color(0.86, 0.93, 1.0, a), 7 if touch_mode else 8)

	# 关卡 / 房间名（肉鸽）
	if level_name != "":
		_text_c(c, 26, level_name, 17, Color(0.72, 0.86, 0.96, 0.85), 7)
		var bar_on: bool = boss != null and is_instance_valid(boss) and not boss.dead
		if room_name != "" and not bar_on:
			_text_c(c, 48, "· " + room_name, 14, Color(0.62, 0.8, 0.92, 0.8), 5)

	# 2.5D：深度（阴 / 阳）指示条
	if mode == "play":
		_draw_depth(c)
		_draw_quick(c)
		_draw_top(c)
		_draw_minimap(c)

	# 剧情碎片
	if lore_t > 0.0 and lore_text != "":
		var la := clampf(lore_t / 1.2, 0.0, 1.0)
		if lore_accent.a > 0.0:
			# R28 镜卷：大卡 + 折行 + 专属描边（普通残卷一行装不下它）
			var big := Rect2(280, 512, 720, 158)
			c.draw_rect(big, Color(0.035, 0.025, 0.055, 0.92 * la))
			_draw_rect_edge(c, big, Color(lore_accent.r, lore_accent.g, lore_accent.b, 0.75 * la), 2.0)
			c.draw_rect(Rect2(big.position.x + 6, big.position.y + 6,
				big.size.x - 12, big.size.y - 12),
				Color(lore_accent.r, lore_accent.g, lore_accent.b, 0.18 * la), false, 1.0)
			_text(c, Vector2(big.position.x + 24.0, big.position.y + 34.0), lore_title, 19,
				Color(lore_accent.r, lore_accent.g, lore_accent.b, la), 4)
			c.draw_line(Vector2(big.position.x + 24.0, big.position.y + 46.0),
				Vector2(big.end.x - 24.0, big.position.y + 46.0),
				Color(lore_accent.r, lore_accent.g, lore_accent.b, 0.35 * la), 1.0)
			_wrap_text_left(c, Vector2(big.position.x + 24.0, big.position.y + 74.0),
				lore_text, Color(0.86, 0.92, 1.0, la), 668.0, 15)
		else:
			var box := Rect2(300, 596, 680, 74)
			c.draw_rect(box, Color(0.02, 0.035, 0.05, 0.80 * la))
			_draw_rect_edge(c, box, Color(0.55, 0.78, 1.0, 0.42 * la), 1.5)
			_text(c, Vector2(318, 622), lore_title, 15, Color(0.85, 0.9, 0.72, la), 4)
			_text(c, Vector2(318, 648), lore_text, 15, Color(0.80, 0.88, 0.98, la), 4)


## 右上角常驻三颗圆钮
func _draw_top(c: Control) -> void:
	for b in TOP_BTN:
		var ctr := Vector2(b["c"])
		var r := float(b["r"])
		var id := str(b["id"])
		var fill := Color(0.10, 0.15, 0.21, 0.82)
		var rim := Color(0.62, 0.80, 1.0, 0.45)
		if id == "weapon":
			fill = Color(0.16, 0.14, 0.10, 0.85)
			rim = Color(1.0, 0.86, 0.55, 0.50)
		c.draw_circle(ctr, r, fill)
		c.draw_arc(ctr, r, 0.0, TAU, 32, rim, 2.0, true)
		var txt := str(b["t"])
		var sz := 20
		var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz)
		c.draw_string_outline(font, ctr + Vector2(-ts.x * 0.5, 7.0), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, Color(0, 0, 0, 0.6))
		var col := Color(0.86, 0.94, 1.0)
		if id == "weapon":
			col = Color(1.0, 0.92, 0.72)
		c.draw_string(font, ctr + Vector2(-ts.x * 0.5, 7.0), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
	# 当前兵器名（换武器钮下方）
	if player and is_instance_valid(player):
		var wn := str(player.weapon_name())
		var ws := font.get_string_size(wn, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		_text(c, Vector2(1156.0 - ws.x * 0.5, 74.0), wn, 12,
			Color(1.0, 0.90, 0.68, 0.85), 4)


## 小地图：3×2 房间网格，当前位置高亮，已清场点亮，Boss 房标红
func _draw_minimap(c: Control) -> void:
	if game == null or not is_instance_valid(game):
		return
	var rs: Array = game.rooms
	if rs.is_empty():
		return
	var cur: int = int(game.room_i)
	var states: Array = game.room_state
	for i in rs.size():
		var r: Dictionary = rs[i]
		var col_i := int(r.get("col", 0))
		var row_i := int(r.get("row", 0))
		var o := MAP_ORIGIN + Vector2(float(col_i) * (MAP_CELL.x + 7.0),
			float(1 - row_i) * (MAP_CELL.y + 7.0))
		var rect := Rect2(o, MAP_CELL)
		var st := "new"
		if i < states.size():
			st = str(states[i])
		var is_boss := str(r.get("kind", "")) == "boss"
		var fill := Color(0.07, 0.10, 0.13, 0.80)
		var edge := Color(0.34, 0.44, 0.56, 0.70)
		if st == "cleared":
			fill = Color(0.12, 0.22, 0.26, 0.85)
			edge = Color(0.45, 0.85, 0.78, 0.85)
		if is_boss:
			fill = Color(0.20, 0.09, 0.11, 0.88)
			edge = Color(0.95, 0.35, 0.36, 0.85)
		if i == cur:
			fill = Color(0.18, 0.30, 0.42, 0.92)
			edge = Color(1.0, 0.92, 0.62, 0.95)
		c.draw_rect(rect, fill)
		c.draw_rect(rect, edge, false, 1.5)
		if i == cur:
			c.draw_arc(rect.get_center(), 4.0, 0.0, TAU, 12, Color(1.0, 0.94, 0.7), 1.6, true)
		elif is_boss:
			c.draw_arc(rect.get_center(), 3.4, 0.0, TAU, 10, Color(1.0, 0.4, 0.4, 0.9), 1.4, true)


## 2.5D：深度（阴 / 阳）指示条 —— 竖条，上 = 阴（远），下 = 阳（近）
func _draw_depth(c: Control) -> void:
	if player == null or not is_instance_valid(player):
		return
	var z: float = clampf(float(player.depth), 0.0, 1.0)
	var x := 28.0
	var y0 := 452.0
	var h := 122.0
	var w := 11.0
	var track := Rect2(x, y0, w, h)
	c.draw_rect(track, Color(0.03, 0.045, 0.062, 0.78))
	_draw_rect_edge(c, track, Color(0.32, 0.46, 0.60, 0.55), 1.2)
	# 当前深度（从下往上填）
	var fh := h * z
	c.draw_rect(Rect2(x, y0 + h - fh, w, fh), Color(0.34, 0.62, 0.88, 0.55))
	# 同一刀路的容差带
	var tol := SpaceScript.LANE_TOL
	var by := y0 + h * (1.0 - z - tol)
	c.draw_rect(Rect2(x - 4.0, by, w + 8.0, h * tol * 2.0), Color(0.55, 0.85, 1.0, 0.10))
	# 当前刻度
	var my := y0 + h * (1.0 - z)
	c.draw_line(Vector2(x - 6.0, my), Vector2(x + w + 6.0, my), Color(0.95, 0.98, 1.0, 0.95), 2.4)
	_text(c, Vector2(x + w + 9.0, y0 + 10.0), "阴", 13, Color(0.58, 0.72, 0.88, 0.9), 3)
	_text(c, Vector2(x + w + 9.0, y0 + h), "阳", 13, Color(0.58, 0.72, 0.88, 0.9), 3)


## R32a：快捷格（丹药 / 符箓共用三格）—— 常驻左侧，空槽也画出来。
## 空槽必须画：否则玩家不知道自己还剩几格、也就不会去想「带什么」。
func _draw_quick(c: Control) -> void:
	if player == null or not is_instance_valid(player):
		return
	_text(c, Vector2(26.0, 282.0), "丹 符 · 1 / 2 / 3", 11, Color(0.62, 0.76, 0.90, 0.72), 3)
	var pl: float = player.pojing_left()
	if pl > 0.0:
		_text(c, Vector2(126.0, 282.0), "破 境 %.1fs" % pl, 12,
			Color(1.0, 0.78, 0.42, 0.55 + 0.4 * sin(_t * 6.0)), 4)
	var cd: float = player.quick_cd()
	for i in player.quick.size():
		var y := 292.0 + float(i) * 52.0
		var box := Rect2(26.0, y, 46.0, 46.0)
		var s: Dictionary = player.quick_slot(i)
		var id := str(s.get("id", ""))
		var cnt := int(s.get("n", 0))
		var key := str(i + 1)
		c.draw_rect(box, Color(0.03, 0.05, 0.07, 0.82))
		if id == "":
			_draw_rect_edge(c, box, Color(0.28, 0.36, 0.46, 0.50), 1.2)
			_text_c_at(c, Vector2(box.position.x + 23.0, y + 30.0), key, 15,
				Color(0.40, 0.50, 0.60, 0.85), 3)
			continue
		var tint: Color = ConsumeScript.tint_of(id)
		_draw_rect_edge(c, box, tint, 1.8)
		c.draw_circle(box.position + Vector2(23.0, 23.0), 17.0, Color(tint.r, tint.g, tint.b, 0.16))
		_text_c_at(c, Vector2(box.position.x + 23.0, y + 30.0), ConsumeScript.short_of(id), 18, tint, 4)
		_text(c, Vector2(box.position.x + 4.0, y + 13.0), key, 11, Color(0.62, 0.74, 0.86, 0.8), 3)
		if cnt > 1:
			_text(c, Vector2(box.end.x - 13.0, box.end.y - 4.0), "×%d" % cnt, 12,
				Color(1.0, 0.95, 0.80, 0.95), 3)
		_text(c, Vector2(box.end.x + 10.0, y + 20.0), ConsumeScript.name_of(id), 13,
			Color(tint.r, tint.g, tint.b, 0.95), 4)
		_text(c, Vector2(box.end.x + 10.0, y + 36.0), ConsumeScript.desc_of(id), 11,
			Color(0.68, 0.78, 0.90, 0.78), 3)
		if cd > 0.0:
			var f := clampf(cd / ConsumeScript.USE_CD, 0.0, 1.0)
			c.draw_rect(Rect2(box.position.x, box.position.y + 46.0 * (1.0 - f),
				46.0, 46.0 * f), Color(0.02, 0.03, 0.05, 0.55))


func _draw_boss_bar(c: Control) -> void:
	if boss == null or not is_instance_valid(boss):
		return
	if boss.dead:
		return
	var frac: float = clampf(float(boss.hp) / float(boss.max_hp), 0.0, 1.0)
	var bx := 380.0
	var by := 54.0
	var bw := 520.0
	var phases := 1
	var phase := 1
	if boss.has_method("phase_count"):
		phases = int(boss.phase_count())
		phase = int(boss.current_phase())
	var hpcol := Color(0.78, 0.22, 0.26)
	if phases > 1:
		hpcol = Color(0.86, 0.24, 0.40)
	c.draw_rect(Rect2(bx - 2, by - 2, bw + 4, 12), Color(0.05, 0.06, 0.08, 0.9))
	c.draw_rect(Rect2(bx, by, bw, 8), Color(0.12, 0.13, 0.16))
	c.draw_rect(Rect2(bx, by, bw * frac, 8), hpcol)
	c.draw_rect(Rect2(bx, by, bw * frac, 2.5), Color(1.0, 0.55, 0.5, 0.8))
	for i in range(1, phases):
		var tx := bx + bw * (float(i) / float(phases))
		c.draw_line(Vector2(tx, by - 1.5), Vector2(tx, by + 9.5), Color(0.02, 0.03, 0.04, 0.95), 2.0)
	var title := "镇 钟 力 士"
	if boss.has_method("boss_title"):
		title = str(boss.boss_title())
	_text_c(c, by - 12, title, 18, Color(0.88, 0.9, 0.95, 0.9))
	if phases > 1:
		var pt := "第 %d / %d 阶 段" % [phase, phases]
		var psz := font.get_string_size(pt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
		_text(c, Vector2(bx + bw - psz.x, by + 24.0), pt, 15, Color(1.0, 0.75, 0.55, 0.85))
	# 硬直度（剑意交锋 / 格挡累积）
	var sm := 0.0
	if boss.has_method("stagger_frac"):
		sm = float(boss.stagger_frac())
	if sm > 0.01:
		c.draw_rect(Rect2(bx, by + 11.0, bw, 3.5), Color(0.09, 0.075, 0.05, 0.9))
		c.draw_rect(Rect2(bx, by + 11.0, bw * sm, 3.5), Color(1.0, 0.76, 0.32))
		if sm > 0.7:
			c.draw_rect(Rect2(bx, by + 11.0, bw * sm, 1.5), Color(1.0, 0.95, 0.8, 0.8))
	# 护体罡气（R11）：敌方躯干值，满 → 道心失守（可处决）
	var pf := 0.0
	if boss.has_method("posture_frac"):
		pf = float(boss.posture_frac())
	var boss_broken: bool = boss.has_method("is_broken") and boss.is_broken()
	if pf > 0.005 or boss_broken:
		var py := by + 16.5
		c.draw_rect(Rect2(bx, py, bw, 4.0), Color(0.05, 0.05, 0.07, 0.92))
		var pcol := Color(0.55, 0.85, 1.0)
		if boss_broken:
			pcol = Color(1.0, 0.35, 0.35)
		elif pf > 0.7:
			pcol = Color(1.0, 0.55, 0.30)
		c.draw_rect(Rect2(bx, py, bw * pf, 4.0), pcol)
		if boss_broken:
			_text(c, Vector2(bx + bw + 8.0, py + 4.0), "道 心 失 守", 14, Color(1.0, 0.40, 0.40, 1.0), 4)


func _draw_title(c: Control) -> void:
	c.draw_rect(Rect2(0, 0, 1280, 720), Color(0.01, 0.015, 0.022, 0.55))
	var pulse := 0.85 + 0.15 * sin(_t * 2.0)
	_text_c(c, 178, "玄   界", 92, Color(0.93, 0.96, 1.0, pulse), 12)
	_text_c(c, 218, "X  U  A  N  J  I  E", 18, Color(0.45, 0.62, 0.76))
	c.draw_line(Vector2(440, 244), Vector2(840, 244), Color(0.3, 0.45, 0.58, 0.5), 1.5)
	_text_c(c, 282, "剑 意 交 锋 · 试 炼", 26, Color(0.72, 0.85, 0.95))

	# R17：玄界小识 —— 标题页左侧三行世界观（一屏只教三个词，不铺设定）
	var pr := Rect2(116, 330, 336, 178)
	c.draw_rect(pr, Color(0.03, 0.05, 0.075, 0.80))
	_draw_rect_edge(c, pr, Color(0.30, 0.46, 0.60, 0.50), 1.2)
	_text(c, Vector2(pr.position.x + 24.0, pr.position.y + 32.0), "玄 界 小 识", 19,
		Color(0.95, 0.86, 0.6, 0.95), 4)
	c.draw_line(Vector2(pr.position.x + 24.0, pr.position.y + 44.0),
		Vector2(pr.end.x - 24.0, pr.position.y + 44.0), Color(0.30, 0.46, 0.60, 0.45), 1.0)
	var notes := [
		"钟 停 则 天 门 闭",
		"阴 阳 两 界 同 界 才 能 互 击",
		"罡 气 尽 则 道 心 失 守",
	]
	for i in notes.size():
		_text(c, Vector2(pr.position.x + 24.0, pr.position.y + 78.0 + 30.0 * float(i)),
			str(notes[i]), 15, Color(0.76, 0.86, 0.96, 0.92), 4)

	# R28：道劫榜 —— 本地前 3 次破劫（跨日期累积，空榜时给一句提示）
	var br := Rect2(116, 520, 336, 150)
	c.draw_rect(br, Color(0.03, 0.05, 0.075, 0.80))
	_draw_rect_edge(c, br, Color(0.30, 0.46, 0.60, 0.50), 1.2)
	_text(c, Vector2(br.position.x + 24.0, br.position.y + 30.0), "道 劫 榜", 18,
		Color(0.95, 0.86, 0.6, 0.95), 4)
	c.draw_line(Vector2(br.position.x + 24.0, br.position.y + 42.0),
		Vector2(br.end.x - 24.0, br.position.y + 42.0), Color(0.30, 0.46, 0.60, 0.45), 1.0)
	var rows_b: Array = []
	if game != null and is_instance_valid(game):
		rows_b = game.daily_board_lines(3)
	if rows_b.is_empty():
		_text(c, Vector2(br.position.x + 24.0, br.position.y + 74.0), "尚 无 破 劫 记 录", 14,
			Color(0.55, 0.66, 0.78, 0.85), 4)
		_text(c, Vector2(br.position.x + 24.0, br.position.y + 100.0), "打 一 次「今 日 道 劫」就 会 上 榜", 13,
			Color(0.44, 0.55, 0.66, 0.8), 3)
	else:
		for i in rows_b.size():
			_text(c, Vector2(br.position.x + 24.0, br.position.y + 74.0 + 30.0 * float(i)),
				str(rows_b[i]), 13, Color(0.78, 0.88, 0.98, 0.92), 3)

	# 三行主菜单
	var sel := 0
	var daily := ""
	if game != null and is_instance_valid(game):
		sel = int(game.title_sel)
		daily = str(game.daily_line())
	var labels := ["开 始 修 行", "今 日 道 劫", "设 置", "残 卷 图 鉴", "经 脉 · 丹 房"]
	var subs := ["随机种子 · 四关 · 三选武器", daily, "音量 / 存档 / 手机按键",
		"已 收 集 %d / %d 卷" % [Cfg.fragment_total(), LoreScript.total()],
		"道 痕 %d · 经 脉 %d / %d 级 · 丹 房 %d / %d" % [Cfg.daoyun,
			MeridianScript.total_lv(Cfg.meridian_lv),
			MeridianScript.all().size() * MeridianScript.MAX_LV,
			Cfg.pantry_total(), AlchemyScript.PANTRY_CAP]]
	for i in 5:
		var r: Rect2 = game.BTN_TITLE[i] if game != null and is_instance_valid(game) else Rect2(490, 0, 300, 0)
		var on := (i == sel)
		if on:
			c.draw_rect(r.grow(3.0), Color(0.16, 0.26, 0.34, 0.92))
		c.draw_rect(r, Color(0.04, 0.06, 0.09, 0.86))
		_draw_rect_edge(c, r, Color(0.62, 0.82, 1.0, 0.9) if on else Color(0.28, 0.4, 0.5, 0.7),
			2.0 if on else 1.2)
		_text_rc(c, r, r.position.y + 34.0, str(labels[i]), 24,
			Color(0.96, 0.99, 1.0) if on else Color(0.72, 0.84, 0.94))
		if i != 1:
			_text_rc(c, r, r.position.y + 52.0, str(subs[i]), 12, Color(0.55, 0.68, 0.8, 0.9), 3)
		else:
			# R23：今日之镜 —— 未破金色（邀请），已破绿色（完成）
			var dcol := Color(1.0, 0.86, 0.5, 0.95)
			if game != null and is_instance_valid(game) and game.daily_done_today():
				dcol = Color(0.58, 0.95, 0.65, 0.95)
			_text_rc(c, r, r.position.y + 52.0, str(subs[i]), 12, dcol, 3)

	if touch_mode:
		_text_c(c, 684, "左下 摇杆 移动（上下推 = 纵深）　右下 刀 挥刀　冲 冲刺", 15,
			Color(0.55, 0.68, 0.8))
		_text_c(c, 704, "挡 格挡　蓄 蓄力斩·绝招　疗 聚集治疗　左侧三格 = 丹药 / 符箓（点格子用）", 15,
			Color(0.55, 0.68, 0.8))
	else:
		_text_c(c, 684, "A/D 移动　W/S 纵深　Shift 冲刺　J 挥刀（连招）　L 格挡　U/I 绝招　K 聚集治疗", 15,
			Color(0.55, 0.68, 0.8))
		_text_c(c, 704, "↑↓ 选择菜单　空格 / 回车 确认　1/2/3 丹药·符箓　M 铭刻　核心：敌人刀锋亮起的瞬间挥刀 = 剑意交锋", 15,
			Color(0.72, 0.86, 0.98))


## R33a 经脉页 —— 3 脉 × 4 条，每条 3 级。
## 数字全部来自 meridian.gd：hud 一个效果值都不硬编码，改表就改界面。
func _draw_meridian(c: Control) -> void:
	c.draw_rect(Rect2(0, 0, 1280, 720), Color(0.012, 0.018, 0.026, 0.96))
	var cur_mer := 0
	if game != null and is_instance_valid(game):
		cur_mer = clampi(int(game.mer_col), 0, MER_TAB_ALCH)
	var alch := cur_mer == MER_TAB_ALCH
	_text_c(c, 70, "丹  房" if alch else "经  脉", 44,
		Color(1.0, 0.93, 0.82) if alch else Color(0.93, 0.97, 1.0), 10)
	_text_c(c, 100, "局 外 炼 制 · 产 物 开 局 自 动 带 进 快 捷 格" if alch
		else "局 外 成 长 · 只 改 手 感，不 改 这 局 拿 到 什 么", 15,
		Color(0.52, 0.66, 0.80, 0.95), 4)

	var lv: Dictionary = Cfg.meridian_lv
	var dy := int(Cfg.daoyun)
	var cap := MeridianScript.all().size() * MeridianScript.MAX_LV
	if alch:
		_text_c(c, 130, "道 痕 %d　·　丹 房 存 货 %d / %d" % [
			dy, Cfg.pantry_total(), AlchemyScript.PANTRY_CAP], 18,
			Color(0.98, 0.88, 0.58, 0.98), 5)
	else:
		_text_c(c, 130, "道 痕 %d　·　已 点 %d / %d 级　·　洗 点 退 回 %d" % [
			dy, MeridianScript.total_lv(lv), cap, MeridianScript.respec_refund(lv)], 18,
			Color(0.98, 0.88, 0.58, 0.98), 5)

	# R33b 页签 / R33c 加第四页「丹房」—— 一页只画一脉的 8 条（2 列 × 4 行）
	var tabs: Array = []
	for ti in MER_TAB_ALCH + 1:
		tabs.append(Rect2(365.0 + 140.0 * float(ti), 150.0, 130.0, 34.0))
	if game != null and is_instance_valid(game):
		tabs = game.BTN_MER_TABS
	for ti in MER_TAB_ALCH + 1:
		var is_alch_tab := ti == MER_TAB_ALCH
		var tt: Color = Color(1.0, 0.84, 0.52) if is_alch_tab \
			else MeridianScript.MERS[ti]["tint"]
		var tr: Rect2 = tabs[ti]
		var on_tab := ti == cur_mer
		c.draw_rect(tr, Color(0.10, 0.15, 0.20, 0.96) if on_tab
			else Color(0.030, 0.045, 0.062, 0.92))
		c.draw_rect(tr, Color(tt.r, tt.g, tt.b, 0.85) if on_tab
			else Color(0.22, 0.30, 0.38, 0.60), false, 2.0 if on_tab else 1.0)
		var tname := "丹 房" if is_alch_tab else str(MeridianScript.MERS[ti]["name"])
		_text_rc(c, tr, tr.position.y + 23.0, "%d  %s" % [ti + 1, tname], 16,
			tt if on_tab else Color(0.55, 0.66, 0.76, 0.9))

	if alch:
		_draw_alchemy_body(c, dy)
		return

	var rects: Array = []
	var sel := 0
	if game != null and is_instance_valid(game):
		rects = game.mer_node_rects()
		sel = int(game.mer_row)

	# 当前脉的副标题 + 本脉进度
	var mm: Dictionary = MeridianScript.MERS[cur_mer]
	var tint: Color = mm["tint"]
	var nodes: Array = MeridianScript.by_mer(str(mm["id"]))
	var mer_done := 0
	for n in nodes:
		mer_done += int(lv.get(str(n["id"]), 0))
	_text_c(c, 202, "%s　·　本 脉 %d / %d 级" % [str(mm["sub"]), mer_done,
		nodes.size() * MeridianScript.MAX_LV], 12, Color(0.52, 0.64, 0.76, 0.9), 3)

	for ri in nodes.size():
		var n: Dictionary = nodes[ri]
		var id := str(n["id"])
		var col := 0 if ri < 4 else 1
		var r := Rect2(296.0 + 356.0 * float(col), 214.0 + 100.0 * float(ri % 4), 332.0, 88.0)
		if ri < rects.size():
			r = rects[ri]
		var on := (ri == sel)
		var cur := int(lv.get(id, 0))
		var cst := MeridianScript.cost(id, cur)
		var can := cst >= 0 and dy >= cst
		c.draw_rect(r, Color(0.075, 0.11, 0.15, 0.96) if on else Color(0.035, 0.05, 0.07, 0.92))
		var edge := Color(0.24, 0.34, 0.44, 0.75)
		if cur > 0:
			edge = Color(tint.r, tint.g, tint.b, 0.55)
		if on:
			edge = Color(0.75, 0.92, 1.0, 0.95)
		_draw_rect_edge(c, r, edge, 2.0 if on else 1.2)
		_text(c, Vector2(r.position.x + 18.0, r.position.y + 30.0), str(n["name"]), 20,
			tint if cur > 0 else Color(0.70, 0.80, 0.90), 5)
		# 三级刻度点
		for k in MeridianScript.MAX_LV:
			var pp := Vector2(r.position.x + 120.0 + 17.0 * float(k), r.position.y + 24.0)
			if k < cur:
				c.draw_circle(pp, 5.5, tint)
			else:
				c.draw_circle(pp, 5.5, Color(0.16, 0.22, 0.30, 0.9))
				c.draw_arc(pp, 5.5, 0.0, TAU, 16, Color(tint.r, tint.g, tint.b, 0.30), 1.2)
		# 当前效果 / 下一级效果
		if cur > 0:
			_text(c, Vector2(r.position.x + 18.0, r.position.y + 56.0),
				MeridianScript.desc_of(lv, id), 12, Color(0.80, 0.90, 1.0, 0.95), 3)
		else:
			_text(c, Vector2(r.position.x + 18.0, r.position.y + 56.0), "未 点", 12,
				Color(0.46, 0.56, 0.66, 0.9), 3)
		if cst < 0:
			_text(c, Vector2(r.position.x + 18.0, r.position.y + 76.0), "已 满 级", 12,
				Color(0.98, 0.88, 0.58, 0.9), 3)
		else:
			var nx: Dictionary = lv.duplicate()
			nx[id] = cur + 1
			_text(c, Vector2(r.position.x + 18.0, r.position.y + 76.0),
				"下一级 " + MeridianScript.desc_of(nx, id), 12,
				Color(0.62, 0.95, 0.72, 0.92) if can else Color(0.50, 0.58, 0.68, 0.75), 3)
		# 价格
		if cst >= 0:
			_text_r(c, r.end.x - 16.0, r.position.y + 30.0, "%d 道痕" % cst, 14,
				Color(0.98, 0.88, 0.58, 0.95) if can else Color(0.72, 0.58, 0.46, 0.8), 3)

	# 选中节点的「满级额外效果」（只有带 l3 的节点有）
	if game != null and is_instance_valid(game):
		var sn: Dictionary = MeridianScript.node(str(game.mer_sel_id()))
		var l3 := str(sn.get("l3", ""))
		if l3 != "":
			_text_c(c, 606, l3, 14, Color(0.86, 0.92, 0.66, 0.9), 4)

	# 反馈行
	if game != null and is_instance_valid(game) and float(game.mer_msg_t) > 0.0:
		_text_c(c, 630, str(game.mer_msg), 16, Color(1.0, 0.92, 0.66, 0.95), 5)

	# 操作提示（放在按钮上方，避免贴到屏幕下沿被裁）
	if touch_mode:
		_text_c(c, 650, "点 页 签 切 页　·　点 卡 格 选 中，再 点 一 下 升 级", 12,
			Color(0.50, 0.62, 0.74, 0.85), 3)
	else:
		_text_c(c, 650, "↑↓ 选 行　　←→ 换 列　　1 / 2 / 3 / 4 切 页 签　　空 格 升 级　　R 洗 点　　Esc 返 回", 12,
			Color(0.50, 0.62, 0.74, 0.85), 3)

	# 底部按钮
	var rb := Rect2(390, 662, 250, 44)
	var bb := Rect2(660, 662, 230, 44)
	if game != null and is_instance_valid(game):
		rb = game.BTN_MER_RESPEC
		bb = game.BTN_MER_BACK
	c.draw_rect(rb, Color(0.16, 0.13, 0.09, 0.9))
	c.draw_rect(rb, Color(0.86, 0.72, 0.42, 0.6), false, 1.0)
	_text_rc(c, rb, rb.position.y + 28.0, "洗 点（退 70%）", 15, Color(1.0, 0.9, 0.68, 0.95))
	c.draw_rect(bb, Color(0.10, 0.16, 0.22, 0.88))
	c.draw_rect(bb, Color(0.42, 0.62, 0.78, 0.55), false, 1.0)
	_text_rc(c, bb, bb.position.y + 28.0, "返 回", 15, Color(0.95, 0.86, 0.6, 0.95))


# ============================================================ R33c 丹房页体
## 12 张方子（4 列 × 3 行）：字徽 / 名字 / 效果 / 价格 / 已存几件
func _draw_alchemy_body(c: Control, dy: int) -> void:
	var recs: Array = AlchemyScript.recipes()
	var rects: Array = []
	var sel := 0
	if game != null and is_instance_valid(game):
		rects = game.alch_rects()
		sel = int(game.alch_sel_row())
	var stock_all := Cfg.pantry_total()
	var full := stock_all >= AlchemyScript.PANTRY_CAP

	for k in recs.size():
		var r: Dictionary = recs[k]
		var id := str(r["id"])
		var tint: Color = r["tint"]
		var col := k % 4
		var row := 0 if k < 4 else (1 if k < 8 else 2)
		var rr := Rect2(124.0 + 264.0 * float(col), 214.0 + 124.0 * float(row), 240.0, 108.0)
		if k < rects.size():
			rr = rects[k]
		var on := k == sel
		var cost := int(r["cost"])
		var can := (not full) and dy >= cost
		var stock := Cfg.pantry_of(id)
		c.draw_rect(rr, Color(0.075, 0.11, 0.15, 0.96) if on else Color(0.035, 0.05, 0.07, 0.92))
		var edge := Color(0.24, 0.34, 0.44, 0.75)
		if stock > 0:
			edge = Color(tint.r, tint.g, tint.b, 0.55)
		if on:
			edge = Color(0.75, 0.92, 1.0, 0.95)
		_draw_rect_edge(c, rr, edge, 2.0 if on else 1.2)
		# 右上角字徽（格子小，画不下全名）
		var bc := Vector2(rr.end.x - 32.0, rr.position.y + 30.0)
		c.draw_circle(bc, 15.0, Color(tint.r, tint.g, tint.b, 0.20))
		c.draw_arc(bc, 15.0, 0.0, TAU, 24, Color(tint.r, tint.g, tint.b, 0.75), 1.4)
		var sc := str(r["short"])
		var ssz := font.get_string_size(sc, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		_text(c, Vector2(bc.x - ssz.x * 0.5, rr.position.y + 36.0), sc, 16, tint, 3)
		_text(c, Vector2(rr.position.x + 16.0, rr.position.y + 30.0), str(r["name"]), 18,
			tint if stock > 0 else Color(0.70, 0.80, 0.90), 5)
		_text(c, Vector2(rr.position.x + 16.0, rr.position.y + 56.0), str(r["desc"]), 11,
			Color(0.80, 0.90, 1.0, 0.95), 3)
		_text(c, Vector2(rr.position.x + 16.0, rr.position.y + 84.0), "%d 道痕" % cost, 14,
			Color(0.98, 0.88, 0.58, 0.95) if can else Color(0.72, 0.58, 0.46, 0.8), 3)
		if stock > 0:
			_text_r(c, rr.end.x - 16.0, rr.position.y + 84.0, "存 %d" % stock, 13,
				Color(0.62, 0.95, 0.72, 0.95), 3)

	# 说明行（选中项的效果再念一遍，长文案在这里不受卡片宽度限制）
	var note := "开 局 自 动 带 进 快 捷 格　·　带 进 去 就 归 这 一 局，死 了 不 还"
	if game != null and is_instance_valid(game):
		var sr: Dictionary = AlchemyScript.recipe(str(game.alch_sel_id()))
		if not sr.is_empty():
			note = "%s —— %s" % [str(sr["name"]), str(sr["desc"])]
	_text_c(c, 592, note, 13,
		Color(0.86, 0.92, 0.66, 0.9) if not full else Color(0.96, 0.72, 0.55, 0.95), 4)

	# 反馈行
	if game != null and is_instance_valid(game) and float(game.mer_msg_t) > 0.0:
		_text_c(c, 618, str(game.mer_msg), 16, Color(1.0, 0.92, 0.66, 0.95), 5)

	if touch_mode:
		_text_c(c, 640, "点 页 签 切 页　·　点 方 子 选 中，再 点 一 下 炼 制", 12,
			Color(0.50, 0.62, 0.74, 0.85), 3)
	else:
		_text_c(c, 640, "↑↓←→ 选 方 子　　空 格 炼 制　　1 / 2 / 3 / 4 切 页 签　　Esc 返 回", 12,
			Color(0.50, 0.62, 0.74, 0.85), 3)

	var bb := Rect2(490, 662, 300, 44)
	if game != null and is_instance_valid(game):
		bb = game.BTN_ALCH_BACK
	c.draw_rect(bb, Color(0.10, 0.16, 0.22, 0.88))
	c.draw_rect(bb, Color(0.42, 0.62, 0.78, 0.55), false, 1.0)
	_text_rc(c, bb, bb.position.y + 28.0, "返 回", 15, Color(0.95, 0.86, 0.6, 0.95))



## R16：残卷图鉴 —— 四幕分组，未收集的显示为「？？？」
# ============================================================ R31 兵器铭刻页
func _draw_forge(c: Control) -> void:
	# 0.78 太透，世界里的房间名（如「残碑」）会透到底部说明行上 —— 和残卷图鉴（0.96）对齐
	c.draw_rect(Rect2(0, 0, 1280, 720), Color(0.02, 0.03, 0.05, 0.92))
	_text_c(c, 118, "兵 器 铭 刻", 44, Color(1.0, 0.93, 0.78))

	var wname := "—"
	var iron_n := 0
	var slots: Array = ["", ""]
	var sel := 0
	if player != null and is_instance_valid(player):
		wname = player.weapon_name()
		iron_n = player.iron
		slots = player.inscribe_slots()
	if game != null and is_instance_valid(game):
		sel = int(game.forge_sel)

	_text_c(c, 156, "当前兵器 · %s　｜　每把兵器各 2 槽，换兵器不丢" % wname, 17,
		Color(0.74, 0.86, 0.98))
	# 右上角精铁
	var ir := Rect2(1030, 96, 210, 40)
	c.draw_rect(ir, Color(0.10, 0.12, 0.16, 0.92))
	_draw_rect_edge(c, ir, Color(0.62, 0.72, 0.86, 0.6), 1.2)
	_text_rc(c, ir, ir.position.y + 27.0, "精 铁  %d" % iron_n, 19, Color(0.86, 0.92, 1.0))

	for i in InscribeScript.SLOTS:
		var r := Rect2(230.0, 236.0 + float(i) * 132.0, 820.0, 112.0)
		if game != null and is_instance_valid(game) and game.has_method("_forge_slot_rect"):
			r = game._forge_slot_rect(i)
		var on := (i == sel)
		var id := str(slots[i]) if i < slots.size() else ""
		var col := InscribeScript.hue_of(id) if id != "" else 0.55
		var cc := Color.from_hsv(col, 0.55, 1.0)
		if on:
			c.draw_rect(r.grow(6.0), Color(0.20, 0.18, 0.12, 0.92))
		c.draw_rect(r, Color(0.05, 0.07, 0.10, 0.96))
		# 选中用金色描边（不用词条色，否则金底 + 紫框两层颜色打架）
		_draw_rect_edge(c, r, Color(1.0, 0.92, 0.66) if on else Color(0.30, 0.40, 0.50, 0.85),
			2.6 if on else 1.4)
		# 槽号
		_text(c, Vector2(r.position.x + 24.0, r.position.y + 34.0),
			"第 %d 铭" % (i + 1), 15, Color(0.62, 0.74, 0.86), 4)
		if id == "":
			_text(c, Vector2(r.position.x + 24.0, r.position.y + 76.0), "— 未 铭 —", 30,
				Color(0.42, 0.50, 0.60))
			_text(c, Vector2(r.position.x + 200.0, r.position.y + 74.0),
				"花 %d 精铁刻一条随机词条" % InscribeScript.COST_FORGE, 18,
				Color(0.58, 0.70, 0.82))
		else:
			_text(c, Vector2(r.position.x + 24.0, r.position.y + 76.0),
				InscribeScript.name_of(id), 30, cc)
			_text(c, Vector2(r.position.x + 152.0, r.position.y + 48.0),
				InscribeScript.desc_of(id), 19, Color(0.88, 0.94, 1.0))
			_text(c, Vector2(r.position.x + 152.0, r.position.y + 80.0),
				"花 %d 精铁洗练（重 roll 一条）" % InscribeScript.COST_REFORGE, 15,
				Color(0.56, 0.68, 0.80))
		if on:
			_text(c, Vector2(r.end.x - 54.0, r.position.y + 34.0), "▶ 选 中", 14,
				Color(1.0, 0.95, 0.7), 4)

	# 反馈行
	if game != null and is_instance_valid(game) and float(game.forge_msg_t) > 0.0:
		_text_c(c, 512, str(game.forge_msg), 20, Color(1.0, 0.92, 0.62))

	# 底部两个按钮
	var ab := Rect2(390, 560, 250, 44)
	var bb := Rect2(660, 560, 230, 44)
	if game != null and is_instance_valid(game):
		ab = game.BTN_FORGE_ACTION
		bb = game.BTN_FORGE_BACK
	var cur_id := str(slots[sel]) if sel < slots.size() else ""
	var act_txt := "洗 练" if cur_id != "" else "刻 上"
	c.draw_rect(ab, Color(0.16, 0.13, 0.09, 0.94))
	_draw_rect_edge(c, ab, Color(0.90, 0.76, 0.46, 0.8), 1.6)
	_text_rc(c, ab, ab.position.y + 29.0, act_txt + "　（空格）", 18, Color(1.0, 0.92, 0.68))
	c.draw_rect(bb, Color(0.10, 0.14, 0.19, 0.94))
	_draw_rect_edge(c, bb, Color(0.46, 0.62, 0.78, 0.6), 1.2)
	_text_rc(c, bb, bb.position.y + 29.0, "返 回　（Esc / M）", 18, Color(0.82, 0.90, 0.98))

	_text_c(c, 634, "← → 选槽　·　空格 刻 / 洗　·　Esc 返回", 16, Color(0.62, 0.76, 0.9))
	_text_c(c, 660, "精铁只从精英（+1）与 Boss（+2）来，杂兵不掉　·　同一把兵器的两条词条不会重复", 14,
		Color(0.56, 0.68, 0.80))
	_text_c(c, 684, "铭刻是局内构筑：开新局清空、不进存档　·　符剑另有「符铭 / 迅符」两条专属词条", 14,
		Color(0.56, 0.68, 0.80))


func _draw_codex(c: Control) -> void:
	c.draw_rect(Rect2(0, 0, 1280, 720), Color(0.012, 0.018, 0.026, 0.96))
	var act := 1
	var total := 0
	if game != null and is_instance_valid(game):
		act = clampi(int(game.codex_act), 1, LoreScript.act_count())
	total = Cfg.fragment_total()

	_text_c(c, 64, "残 卷 图 鉴", 40, Color(0.93, 0.97, 1.0))
	_text_c(c, 104, "已 收 集 %d / %d 卷　·　共 %d 幕" % [total, LoreScript.total(), LoreScript.act_count()],
		17, Color(0.62, 0.76, 0.9))

	# 幕标签条（R24：第 5 幕加入后 5 个签超宽 —— 宽度自适应收窄）
	var n := LoreScript.act_count()
	var tab_w := minf(250.0, (1240.0 - 12.0 * float(n - 1)) / float(n))
	var tab_x := (1280.0 - (tab_w * float(n) + 12.0 * float(n - 1))) * 0.5
	for i in n:
		var a := i + 1
		var r := Rect2(tab_x + float(i) * (tab_w + 12.0), 140.0, tab_w, 42.0)
		var on := a == act
		var done := LoreScript.act_done(a, _owned_ids())
		c.draw_rect(r, Color(0.06, 0.09, 0.12, 0.95) if not on else Color(0.13, 0.21, 0.29, 0.98))
		_draw_rect_edge(c, r, Color(1.0, 0.92, 0.66, 0.95) if on
			else (Color(0.42, 0.78, 0.72, 0.7) if done else Color(0.26, 0.36, 0.46, 0.6)),
			2.0 if on else 1.2)
		_text_rc(c, r, r.position.y + 27.0, LoreScript.act_name(a), 17,
			Color(1.0, 0.97, 0.86) if on else Color(0.68, 0.8, 0.92))

	# 幕引导语
	_text_c(c, 208, LoreScript.act_intro(act), 16, Color(0.6, 0.74, 0.88))

	# 三条残卷
	var fs := LoreScript.fragments_of_act(act)
	var owned := _owned_ids()
	for i in fs.size():
		var f: Dictionary = fs[i]
		var y := 248.0 + float(i) * 128.0
		var r := Rect2(180.0, y, 920.0, 112.0)
		var got := owned.has(str(f["id"]))
		c.draw_rect(r, Color(0.05, 0.07, 0.10, 0.94) if got else Color(0.035, 0.045, 0.06, 0.9))
		_draw_rect_edge(c, r, Color(0.5, 0.72, 0.9, 0.75) if got else Color(0.2, 0.27, 0.34, 0.7),
			1.4)
		# 序号
		c.draw_circle(Vector2(r.position.x + 34.0, r.get_center().y), 17.0,
			Color(0.12, 0.18, 0.24, 0.95))
		_text_c_at(c, Vector2(r.position.x + 34.0, r.get_center().y + 6.0),
			str(f["id"]), 15, Color(0.7, 0.84, 0.96) if got else Color(0.4, 0.48, 0.56), 3)
		# R17：一律左对齐（原来的 _text_c_at 是居中，会把标题压到左侧序号圆上）
		if got:
			_text(c, Vector2(r.position.x + 66.0, y + 36.0), str(f["title"]), 20,
				Color(0.96, 0.98, 1.0), 2)
			_wrap_text_left(c, Vector2(r.position.x + 66.0, y + 62.0), str(f["text"]),
				Color(0.82, 0.90, 0.98), 820.0, 17)
		else:
			_text(c, Vector2(r.position.x + 66.0, y + 36.0), "？ ？ ？", 20,
				Color(0.34, 0.42, 0.5), 2)
			_text(c, Vector2(r.position.x + 66.0, y + 62.0), "尚 未 拾 得", 15,
				Color(0.30, 0.38, 0.46), 3)

	# 翻幕箭头
	var lr: Rect2 = game.CODEX_LEFT if game != null and is_instance_valid(game) else Rect2(40, 330, 56, 90)
	var rr2: Rect2 = game.CODEX_RIGHT if game != null and is_instance_valid(game) else Rect2(1184, 330, 56, 90)
	for pair in [[lr, "‹"], [rr2, "›"]]:
		var r: Rect2 = pair[0]
		c.draw_rect(r, Color(0.06, 0.09, 0.12, 0.9))
		_draw_rect_edge(c, r, Color(0.5, 0.66, 0.82, 0.8), 1.4)
		_text_rc(c, r, r.get_center().y + 14.0, str(pair[1]), 34, Color(0.82, 0.92, 1.0))

	# 返回
	var br: Rect2 = game.CODEX_BACK if game != null and is_instance_valid(game) else Rect2(490, 656, 300, 46)
	c.draw_rect(br, Color(0.07, 0.10, 0.14, 0.95))
	_draw_rect_edge(c, br, Color(0.55, 0.72, 0.88, 0.85), 1.6)
	_text_rc(c, br, br.position.y + 30.0, "返 回" if touch_mode else "返 回（空格 / Esc）", 17,
		Color(0.86, 0.94, 1.0))


## 已收集的碎片 id 列表（图鉴判定用）
func _owned_ids() -> Array:
	var out := []
	for f in LoreScript.FRAGMENTS:
		if Cfg.has_fragment(str(f["id"])):
			out.append(str(f["id"]))
	return out


## 左对齐的多行文字（图鉴用，_wrap_text 是按卡片居中的）
func _wrap_text_left(c: Control, pos: Vector2, txt: String, col: Color,
		max_w: float, size: int) -> void:
	if font == null:
		return
	var line := ""
	var y := pos.y
	for ch in txt:
		var probe := line + str(ch)
		if font.get_string_size(probe, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w:
			c.draw_string(font, Vector2(pos.x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
			y += float(size) + 6.0
			line = str(ch)
		else:
			line = probe
	if line != "":
		c.draw_string(font, Vector2(pos.x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _draw_reward(c: Control) -> void:
	c.draw_rect(Rect2(0, 0, 1280, 720), Color(0.02, 0.03, 0.05, 0.74))
	var title := "房 间 已 清 · 选 一 件 法 宝"
	var hint := "← → 选 择　·　空格 / J 确 认"
	var tcol := Color(0.92, 0.97, 1.0)
	if game != null and is_instance_valid(game) and str(game.reward_title) != "":
		title = str(game.reward_title)
		tcol = Color(1.0, 0.86, 0.62)
		# R21 修：以前「reward_title 非空」等价于替换页，R21 掉落页也有标题 —— 改按 state 分流，
		# 否则掉落页会显示「选一件弃掉」的替换页提示
		hint = "← → 选 一 件 弃 掉　·　空格 / J 确 认" if str(game.state) == "replace" \
			else "← → 选 择　·　空格 / J 确 认"
	_text_c(c, 176, title, 34, tcol)
	_text_c(c, 218, hint, 18, Color(0.6, 0.74, 0.88))
	if game != null and is_instance_valid(game) and str(game.pending_relic) != "":
		var nd: Dictionary = RelicScript.by_id(str(game.pending_relic))
		if not nd.is_empty():
			_text_c(c, 252, "新 法 宝：「%s」 %s" % [str(nd.get("name", "?")), str(nd.get("desc", ""))],
				16, Color(0.86, 0.94, 1.0))
	# R16：替换页顶部的「花道蕴扩格」按钮（道蕴够才亮）
	if game != null and is_instance_valid(game) and str(game.pending_relic) != "":
		var er: Rect2 = game.REPLACE_EXPAND
		var afford: bool = game.can_expand_now()
		var ecol := Color(0.95, 0.84, 0.52) if afford else Color(0.42, 0.48, 0.56)
		c.draw_rect(er, Color(0.06, 0.08, 0.11, 0.96))
		_draw_rect_edge(c, er, ecol, 2.0 if afford else 1.2)
		var etxt := "F / 点此：花 %d 道 蕴 把 %s 位 扩 到 %d 格" % [
			int(game.player.SLOT_EXPAND_COST) if game.player != null else 45,
			RelicScript.slot_name(str(game.replace_slot)),
			(game.player.slot_cap(str(game.replace_slot)) + 1) if game.player != null else 4]
		if not afford:
			etxt = "道 蕴 不 足 · 需 %d" % (int(game.player.SLOT_EXPAND_COST) if game.player != null else 45)
		_text_c(c, er.position.y + 30.0, etxt, 16, ecol)
	var cards := []
	var rects := []
	if game != null and is_instance_valid(game):
		cards = game.reward_cards
		rects = game.reward_rects
	if rects.is_empty():
		rects = [Rect2(186, 296, 282, 232), Rect2(499, 296, 282, 232), Rect2(812, 296, 282, 232)]
	for i in rects.size():
		var r: Rect2 = rects[i]
		var sel := false
		if game != null and is_instance_valid(game):
			sel = (i == game.pick_sel)
		var dat: Dictionary = {}
		if i < cards.size():
			dat = cards[i]
		var col := Color(0.6, 0.9, 1.0)
		if not dat.is_empty():
			col = RelicScript.color_of(dat)
		if sel:
			c.draw_rect(r.grow(7.0), Color(0.16, 0.24, 0.32, 0.95))
		c.draw_rect(r, Color(0.05, 0.07, 0.1, 0.96))
		var edge := col if sel else Color(0.3, 0.42, 0.52, 0.8)
		_draw_rect_edge(c, r, edge, 3.0 if sel else 1.5)
		var ic := r.get_center() + Vector2(0, -56.0)
		c.draw_circle(ic, 34.0, col * 0.22)
		c.draw_arc(ic, 34.0, 0.0, TAU, 40, col, 2.5, true)
		if not dat.is_empty():
			_text_rc(c, r, r.position.y + 124, str(dat.get("name", "?")), 24, col)
			var stag := RelicScript.set_of(str(dat.get("id", "")))
			if stag != "":
				_text_rc(c, r, r.position.y + 146, RelicScript.set_title(stag), 13,
					RelicScript.set_color(stag), 4)
			_wrap_text(c, r, str(dat.get("desc", "")), Color(0.86, 0.92, 1.0), 168.0)
		else:
			_text_rc(c, r, r.position.y + 124, "— 无 更 多 —", 20, Color(0.5, 0.62, 0.74))
		if sel:
			# R30：选中标记从卡片底部移到顶部 —— 12 件新法宝里有 3 行文案的（反震 / 阴眼），
			# 第三行正好压在原来的「▶ 选中 ◀」上（和 R29 武器卡同一个病，同一个治法）
			_text_rc(c, r, r.position.y + 18.0, "▶ 选 中 ◀", 13, Color(1.0, 0.95, 0.7))


func _draw_weapon(c: Control) -> void:
	c.draw_rect(Rect2(0, 0, 1280, 720), Color(0.01, 0.015, 0.022, 0.62))
	_text_c(c, 152, "选 一 把 兵 器", 38, Color(0.92, 0.97, 1.0))
	var sel := 0
	var seedtxt := ""
	var dailytxt := ""
	var rects := []
	if game != null and is_instance_valid(game):
		sel = int(game.weapon_sel)
		seedtxt = "种 子  %d" % int(game.run_seed)
		dailytxt = str(game.daily_line())
		rects = game.WPN_RECTS
	if dailytxt != "":
		_text_c(c, 188, dailytxt + "　·　" + seedtxt, 17, Color(1.0, 0.86, 0.5))
	else:
		_text_c(c, 188, seedtxt + "　·　每 局 随 机", 17, Color(0.62, 0.76, 0.9))
	for i in rects.size():
		var r: Rect2 = rects[i]
		var w: Dictionary = WeaponScript.LIST[i] if i < WeaponScript.LIST.size() else {}
		if w.is_empty():
			continue
		var on := (i == sel)
		var col: Color = WeaponScript.color_of(w)
		if on:
			c.draw_rect(r.grow(8.0), Color(0.16, 0.24, 0.32, 0.95))
		c.draw_rect(r, Color(0.05, 0.07, 0.1, 0.96))
		_draw_rect_edge(c, r, col if on else Color(0.3, 0.42, 0.52, 0.8), 3.0 if on else 1.5)
		# 武器图标（R29：从 +54 下移到 +62、半径收到 26 —— 原来的选中标记会压住图标顶边）
		var ic := r.position + Vector2(r.size.x * 0.5, 62.0)
		c.draw_circle(ic, 26.0, Color(col.r, col.g, col.b, 0.18))
		c.draw_arc(ic, 26.0, 0.0, TAU, 40, col, 2.0, true)
		_weapon_icon(c, ic, str(w["id"]), col)
		if on:
			# 选中标记放卡片顶部，把底部整条让给数值条（原来在底部会和第三行数值打架）
			_text_rc(c, r, r.position.y + 20.0, "▶ 选 中 ◀", 12, Color(1.0, 0.95, 0.7))
		_text_rc(c, r, r.position.y + 112, str(w["name"]), 25, col)
		_text_rc(c, r, r.position.y + 132, "「" + str(w["tag"]) + "」", 14, Color(0.78, 0.88, 0.98))
		_wrap_text(c, r, str(w["desc"]), Color(0.86, 0.92, 1.0), 152.0, 14)
		# 数值条（R29：第三行可由武器表覆盖 —— 符剑显示「符力」而不是「灵力」）
		var stats := [
			["刀 锋", float(w["reach"]) / 1.45],
			["攻 速", float(w["speed"]) / 1.25],
			[str(w.get("stat3_name", "灵 力")),
				float(w.get("stat3_val", 1.0 - (float(w["stam"]) - 0.8) / 0.35))],
		]
		var st_y := r.end.y - 44.0
		for st in stats:
			_text(c, Vector2(r.position.x + 18.0, st_y), str(st[0]), 12, Color(0.62, 0.74, 0.86), 3)
			var bar := Rect2(r.position.x + 68.0, st_y - 8.0, 150.0, 7.0)
			c.draw_rect(bar, Color(0.10, 0.13, 0.16))
			var f: float = clampf(float(st[1]), 0.05, 1.0)
			c.draw_rect(Rect2(bar.position.x, bar.position.y, bar.size.x * f, bar.size.y),
				Color(col.r, col.g, col.b, 0.85))
			st_y += 17.0
	_text_c(c, 690, "← → 选 择　·　空 格 / J 出 发", 19, Color(0.72, 0.86, 0.98))
	# R14：选中兵器的法宝小字（叙事选择，而非纯数值选择）
	if sel >= 0 and sel < WeaponScript.LIST.size():
		var lw: Dictionary = WeaponScript.LIST[sel]
		var ltxt := str(lw.get("lore", ""))
		if ltxt != "":
			_text_c(c, 713, "· " + ltxt + " ·", 14, Color(0.82, 0.75, 0.55))


func _weapon_icon(c: Control, o: Vector2, id: String, col: Color) -> void:
	match id:
		"spear":
			c.draw_line(o + Vector2(-16, 14), o + Vector2(16, -16), Color(0.62, 0.46, 0.30), 3.0, true)
			c.draw_colored_polygon(PackedVector2Array([
				o + Vector2(16, -16), o + Vector2(26, -26), o + Vector2(12, -12),
			]), Color(0.9, 0.94, 1.0))
			c.draw_line(o + Vector2(-14, 8), o + Vector2(-20, 16), Color(0.86, 0.28, 0.26), 2.4)
		"dual":
			c.draw_line(o + Vector2(-4, 16), o + Vector2(8, -16), col, 2.6, true)
			c.draw_line(o + Vector2(10, 14), o + Vector2(-8, -14), Color(0.72, 0.80, 0.90), 2.6, true)
		"rune":
			# R29 符剑：窄剑 + 剑身三道符（横向纸条 + 朱砂点，不遮住剑脊）
			c.draw_line(o + Vector2(-2, 18), o + Vector2(2, -20), Color(0.88, 0.92, 0.98), 2.6, true)
			c.draw_line(o + Vector2(-9, 12), o + Vector2(6, 12), Color(0.46, 0.38, 0.56), 2.6)
			for k in 3:
				var cy := 8.0 - float(k) * 7.0
				c.draw_rect(Rect2(o.x - 5.0, o.y + cy - 1.8, 10.0, 3.6),
					Color(0.86, 0.74, 1.0, 0.95))
				c.draw_circle(Vector2(o.x, o.y + cy), 1.1, Color(0.80, 0.16, 0.20))
		_:
			c.draw_line(o + Vector2(-2, 18), o + Vector2(2, -20), Color(0.86, 0.92, 1.0), 3.0, true)
			c.draw_line(o + Vector2(-9, 12), o + Vector2(6, 12), Color(0.42, 0.50, 0.60), 3.0)


func _draw_branch(c: Control) -> void:
	c.draw_rect(Rect2(0, 0, 1280, 720), Color(0.02, 0.03, 0.05, 0.76))
	_text_c(c, 190, "岔 路 · 选 一 条 走", 36, Color(0.92, 0.97, 1.0))
	_text_c(c, 228, "← → 选 择　·　空 格 / J 确 认", 17, Color(0.6, 0.74, 0.88))
	var sel := 0
	var rects := []
	if game != null and is_instance_valid(game):
		sel = int(game.branch_sel)
		rects = game.ROUTE_RECTS
	for i in rects.size():
		var r: Rect2 = rects[i]
		var route: Dictionary = RoomScript.ROUTES[i] if i < RoomScript.ROUTES.size() else {}
		if route.is_empty():
			continue
		var on := (i == sel)
		var col: Color = RoomScript.route_color(route)
		if on:
			c.draw_rect(r.grow(8.0), Color(0.16, 0.24, 0.32, 0.95))
		c.draw_rect(r, Color(0.05, 0.07, 0.1, 0.96))
		_draw_rect_edge(c, r, col if on else Color(0.3, 0.42, 0.52, 0.8), 3.0 if on else 1.5)
		var ic := r.position + Vector2(r.size.x * 0.5, 76.0)
		c.draw_circle(ic, 40.0, Color(col.r, col.g, col.b, 0.16))
		c.draw_arc(ic, 40.0, 0.0, TAU, 40, col, 2.4, true)
		if i == 0:
			c.draw_line(ic + Vector2(-16, 18), ic + Vector2(0, -18), col, 3.0, true)
			c.draw_line(ic + Vector2(0, -18), ic + Vector2(16, 18), col, 3.0, true)
		else:
			c.draw_colored_polygon(PackedVector2Array([
				ic + Vector2(-14, 20), ic + Vector2(0, -22), ic + Vector2(14, 20),
			]), Color(col.r, col.g, col.b, 0.9))
		_text_rc(c, r, r.position.y + 148, str(route["name"]), 28, col)
		_wrap_text(c, r, str(route["desc"]), Color(0.86, 0.92, 1.0), 176.0)
		if on:
			_text_rc(c, r, r.end.y - 18.0, "▶ 选 中 ◀", 15, Color(1.0, 0.95, 0.7))


func _draw_event(c: Control) -> void:
	var kind := ""
	var sel := 0
	var items := []
	if game != null and is_instance_valid(game):
		kind = str(game.event_kind)
		sel = int(game.event_sel)
		items = game.shop_items
	if kind == "shop":
		_draw_shop(c, sel, items)
		return
	# 宝箱
	c.draw_rect(Rect2(0, 0, 1280, 720), Color(0.02, 0.03, 0.05, 0.74))
	_text_c(c, 186, "秘 藏 · 宝 箱", 38, Color(0.95, 0.9, 0.72))
	_text_c(c, 224, "箱 盖 上 刻 着 一 行 小 字：留 给 走 得 更 远 的 人", 17, Color(0.68, 0.8, 0.92))
	var bc := Vector2(640, 336)
	c.draw_circle(bc, 74.0, Color(0.95, 0.82, 0.45, 0.06))
	c.draw_rect(Rect2(bc.x - 54, bc.y - 10, 108, 54), Color(0.30, 0.22, 0.14))
	c.draw_rect(Rect2(bc.x - 58, bc.y - 24, 116, 18), Color(0.38, 0.28, 0.17))
	c.draw_rect(Rect2(bc.x - 58, bc.y - 24, 116, 18), Color(0.95, 0.82, 0.45, 0.25), false, 1.5)
	for k in 3:
		c.draw_rect(Rect2(bc.x - 50 + k * 36, bc.y + 2, 26, 30), Color(0.44, 0.33, 0.20, 0.55))
	c.draw_circle(bc + Vector2(0, 2), 7.0, Color(0.98, 0.88, 0.55))
	var btns := []
	if game != null and is_instance_valid(game):
		btns = game.EVENT_BTNS
	var labels := ["打 开 宝 箱", "不 碰 它"]
	var subs := ["随机法宝 + 20 道蕴 + 丹药", "回复 1 点气血"]
	for i in btns.size():
		var r: Rect2 = btns[i]
		var on := (i == sel)
		if on:
			c.draw_rect(r.grow(4.0), Color(0.18, 0.26, 0.34, 0.95))
		c.draw_rect(r, Color(0.05, 0.07, 0.1, 0.96))
		_draw_rect_edge(c, r, Color(0.95, 0.84, 0.5) if on else Color(0.3, 0.42, 0.52, 0.8), 2.5 if on else 1.2)
		_text_rc(c, r, r.position.y + 26, labels[i], 20, Color(0.96, 0.99, 1.0) if on else Color(0.74, 0.86, 0.96))
		_text_rc(c, r, r.position.y + 46, subs[i], 13, Color(0.62, 0.76, 0.9), 3)
	_text_c(c, 620, "← → 选 择　·　空 格 / J 确 认", 16, Color(0.6, 0.74, 0.88))


func _draw_shop(c: Control, sel: int, items: Array) -> void:
	c.draw_rect(Rect2(0, 0, 1280, 720), Color(0.02, 0.03, 0.05, 0.80))
	_text_c(c, 152, "冷 雾 商 队", 38, Color(0.85, 0.92, 1.0))
	var soul := 0.0
	if player and is_instance_valid(player):
		soul = player.soul
	_text_c(c, 190, "只 收 道 蕴 · 你 有 %.0f" % soul, 18, Color(0.65, 0.9, 1.0))
	var rows := []
	if game != null and is_instance_valid(game):
		rows = game.SHOP_ROWS
	for i in rows.size():
		var r: Rect2 = rows[i]
		var on := (i == sel)
		if on:
			c.draw_rect(r.grow(3.0), Color(0.18, 0.26, 0.34, 0.95))
		c.draw_rect(r, Color(0.05, 0.07, 0.1, 0.96))
		if i >= items.size():
			_draw_rect_edge(c, r, Color(0.24, 0.32, 0.40, 0.7), 1.2)
			_text(c, Vector2(r.position.x + 20.0, r.position.y + 36.0), "— 已 售 罄 —", 18,
				Color(0.45, 0.55, 0.65))
			continue
		var it: Dictionary = items[i]
		var price := int(it.get("price", 30))
		var sold := bool(it.get("sold", false))
		var nm := "?"
		var sub := ""
		var col := Color(0.3, 0.42, 0.52)
		var glyph := ""
		if it.has("item"):
			# R32a/R32b：丹药 / 符箓货架 —— 与法宝同一行高，靠前缀与圆内单字区分
			var iid := str((it["item"] as Dictionary).get("id", ""))
			nm = ConsumeScript.name_of(iid)
			sub = ("［符 箓］" if ConsumeScript.is_talisman(iid) else "［丹 药］") \
				+ ConsumeScript.desc_of(iid)
			col = ConsumeScript.tint_of(iid)
			glyph = ConsumeScript.short_of(iid)
		else:
			var relic: Dictionary = it.get("relic", {})
			nm = str(relic.get("name", "?"))
			sub = str(relic.get("desc", ""))
			var stag := RelicScript.set_of(str(relic.get("id", "")))
			if stag != "":
				sub = "［" + RelicScript.set_title(stag) + "］" + sub
			col = RelicScript.color_of(relic)
		if sold:
			col = col.darkened(0.55)
		_draw_rect_edge(c, r, col if on else Color(0.3, 0.42, 0.52, 0.8), 2.0 if on else 1.2)
		c.draw_circle(r.position + Vector2(34, 29), 16.0, Color(col.r, col.g, col.b, 0.22))
		c.draw_arc(r.position + Vector2(34, 29), 16.0, 0.0, TAU, 24, col, 1.8, true)
		if glyph != "":
			_text_c_at(c, r.position + Vector2(34, 35), glyph, 17, col, 3)
		_text(c, Vector2(r.position.x + 62.0, r.position.y + 26.0), nm, 19, col)
		_text(c, Vector2(r.position.x + 62.0, r.position.y + 46.0), sub, 13, Color(0.72, 0.84, 0.94), 3)
		var ptxt := "已 售" if sold else "%d 道 蕴" % price
		var pcol := Color(0.5, 0.55, 0.6) if sold else (Color(0.7, 0.95, 1.0) if soul >= price else Color(0.95, 0.55, 0.5))
		var psz := font.get_string_size(ptxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17)
		_text(c, Vector2(r.end.x - 24.0 - psz.x, r.position.y + 36.0), ptxt, 17, pcol)
	if game != null and is_instance_valid(game):
		var lr: Rect2 = game.BTN_SHOP_LEAVE
		var on2 := (sel >= rows.size())
		if on2:
			c.draw_rect(lr.grow(4.0), Color(0.18, 0.26, 0.34, 0.95))
		c.draw_rect(lr, Color(0.05, 0.07, 0.1, 0.96))
		_draw_rect_edge(c, lr, Color(0.62, 0.82, 1.0) if on2 else Color(0.3, 0.42, 0.52, 0.8), 2.0)
		_text_c(c, lr.position.y + 34, "离 开", 20, Color(0.96, 0.99, 1.0))
	_text_c(c, 620, "↑↓ 选 择　·　空 格 / J 购 买　·　点 屏 幕 也 行", 16, Color(0.6, 0.74, 0.88))


func _draw_clear(c: Control) -> void:
	c.draw_rect(Rect2(0, 0, 1280, 720), Color(0.01, 0.03, 0.05, 0.62))
	_text_c(c, 268, "飞 升", 54, Color(0.92, 0.97, 1.0))
	var lv := "镇 钟 廊"
	if level_name != "":
		lv = level_name
	_text_c(c, 338, lv + " 已 清 除 —— 更 深 处 等 着 你", 22, Color(0.7, 0.85, 0.95))
	var blink := 0.5 + 0.5 * sin(_t * 4.0)
	_text_c(c, 420, "点 击 屏 幕 / 按 空 格 继 续" if touch_mode else "按 空 格 / J 继 续", 24, Color(0.85, 0.92, 1.0, blink))

	# R28：今日道劫的破劫评分明细 + 名次（普通关卡结算不显示）
	if game != null and is_instance_valid(game) and bool(game.daily_mode):
		var pr := Rect2(390, 470, 500, 176)
		c.draw_rect(pr, Color(0.04, 0.06, 0.09, 0.92))
		_draw_rect_edge(c, pr, Color(0.62, 0.52, 0.28, 0.85), 1.6)
		_text_rc(c, pr, pr.position.y + 30.0, "道 劫 评 分", 20, Color(0.98, 0.88, 0.6))
		var secs: float = float(Cfg.daily_time)
		var dmg_n: int = int(Cfg.daily_dmg)
		var lines := [
			"用 时   %d 分 %02d 秒" % [int(secs) / 60, int(secs) % 60],
			"受 击   %s" % ("无 伤" if dmg_n <= 0 else "%d 次" % dmg_n),
			"剩 血   %d 格" % maxi(0, int(Cfg.daily_hp)),
		]
		for i in lines.size():
			_text(c, Vector2(pr.position.x + 60.0, pr.position.y + 64.0 + 26.0 * float(i)),
				str(lines[i]), 15, Color(0.82, 0.90, 0.98, 0.95), 3)
		_text(c, Vector2(pr.position.x + 320.0, pr.position.y + 64.0),
			"%d 分" % int(game.daily_score_now), 30, Color(1.0, 0.92, 0.66), 5)
		var rank := int(game.daily_rank)
		_text(c, Vector2(pr.position.x + 320.0, pr.position.y + 100.0),
			("榜 第 %d" % rank) if rank > 0 else "未 入 榜", 15,
			Color(0.72, 0.95, 0.82) if rank > 0 else Color(0.55, 0.64, 0.74), 3)
		var bst := Cfg.best_daily_score()
		_text(c, Vector2(pr.position.x + 320.0, pr.position.y + 128.0),
			"最 佳 %d" % bst, 14, Color(0.68, 0.78, 0.9, 0.9), 3)
		_text(c, Vector2(pr.position.x + 60.0, pr.position.y + 152.0),
			"评 分 = 进度 72 + 飞升 80 + 用时 + 无伤 120 + 剩血 ×20", 12,
			Color(0.5, 0.6, 0.72, 0.85), 3)


func _draw_setting(c: Control) -> void:
	c.draw_rect(Rect2(0, 0, 1280, 720), Color(0.02, 0.03, 0.05, 0.84))
	_text_c(c, 124, "设 置", 40, Color(0.92, 0.97, 1.0))
	var rows := ["master", "sfx", "shake", "fullscreen", "touch", "touch_size", "touch_edit",
		"slot0", "slot1", "slot2", "back"]
	var y0 := 196.0
	var dy := 40.0
	var sel := 0
	var mact := 0
	var smsg := ""
	if game != null and is_instance_valid(game):
		sel = game.menu_sel
		mact = game.menu_action
		smsg = game._slot_msg
	for i in rows.size():
		var row: String = rows[i]
		var y := y0 + float(i) * dy
		var on := (i == sel)
		if on:
			c.draw_rect(Rect2(300, y - 26, 680, 36), Color(0.18, 0.26, 0.34, 0.9))
		var label := ""
		var val := ""
		match row:
			"master":
				label = "主 音 量"; val = "%.0f%%" % (Cfg.master * 100.0)
			"sfx":
				label = "音 效 音 量"; val = "%.0f%%" % (Cfg.sfx * 100.0)
			"shake":
				label = "震 屏 强 度"; val = "%.0f%%" % (Cfg.shake / 1.5 * 100.0)
			"fullscreen":
				label = "全 屏"; val = "开" if Cfg.fullscreen else "关"
			"touch":
				label = "手 机 按 键"; val = "开" if Cfg.touch_ui else "关"
			"touch_size":
				label = "按 键 大 小"; val = "%.0f%%" % (Cfg.touch_scale * 100.0)
			"touch_edit":
				label = "调 整 按 键 位 置"; val = "进 入"
			"back":
				label = "返 回"; val = ""
			_:
				if row.begins_with("slot"):
					var si := int(row.substr(4, 1))
					label = "存 档 %d" % (si + 1)
					val = Cfg.slot_info(si)
					if on:
						var acts := ["存 档", "读 档", "删 档"]
						val += "　［" + acts[mact] + "］"
		_text(c, Vector2(316, y + 6), label, 20, Color(0.92, 0.97, 1.0) if on else Color(0.7, 0.82, 0.92))
		if val != "":
			var sz := font.get_string_size(val, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
			_text(c, Vector2(956 - sz.x, y + 6), val, 18, Color(0.85, 0.92, 1.0))
		if on:
			_text(c, Vector2(300, y + 6), "◀", 18, Color(1.0, 0.9, 0.6))
			_text(c, Vector2(964, y + 6), "▶", 18, Color(1.0, 0.9, 0.6))
	if smsg != "":
		_text_c(c, 596, smsg, 22, Color(1.0, 0.92, 0.6))
	_text_c(c, 636, "↑↓ 选择　←→ 调整（存档行：←→ 切换 存 / 读 / 删）　O / Tab 返回", 16, Color(0.6, 0.74, 0.86))


func _draw_rect_edge(c: Control, r: Rect2, col: Color, w: float) -> void:
	c.draw_line(Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), col, w)
	c.draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), col, w)
	c.draw_line(Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y), col, w)
	c.draw_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.position.y), col, w)


func _wrap_text(c: Control, r: Rect2, txt: String, col: Color, y0: float = 150.0, size: int = 15) -> void:
	var maxw := r.size.x - 30.0
	var line := ""
	var y := r.position.y + y0
	for ch in txt:
		var test := line + ch
		if font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > maxw and line != "":
			_text(c, Vector2(r.position.x + 15.0, y), line, size, col)
			y += size + 5.0
			line = ch
		else:
			line = test
	if line != "":
		_text(c, Vector2(r.position.x + 15.0, y), line, size, col)


func _mask(c: Control, center: Vector2, r: float, alive: bool) -> void:
	var fill := Color(0.92, 0.96, 1.0) if alive else Color(0.13, 0.16, 0.2)
	var rim := Color(0.75, 0.88, 1.0, 0.9) if alive else Color(0.28, 0.34, 0.42, 0.8)
	# 角
	c.draw_colored_polygon(PackedVector2Array([
		center + Vector2(-3, -6), center + Vector2(-9, -17), center + Vector2(0, -7),
	]), fill)
	c.draw_colored_polygon(PackedVector2Array([
		center + Vector2(3, -6), center + Vector2(9, -17), center + Vector2(0, -7),
	]), fill)
	# 脸
	_ellipse(c, center, r * 0.82, r, fill, 20)
	if alive:
		_ellipse(c, center + Vector2(-3.4, 0.5), 1.9, 2.6, Color(0.05, 0.07, 0.1), 10)
		_ellipse(c, center + Vector2(3.4, 0.5), 1.9, 2.6, Color(0.05, 0.07, 0.1), 10)
	else:
		c.draw_arc(center, r * 0.92, 0, TAU, 20, rim, 1.2, true)


func _ellipse(c: Control, center: Vector2, rx: float, ry: float, col: Color, pts: int) -> void:
	var arr := PackedVector2Array()
	for i in pts:
		var a := TAU * float(i) / float(pts)
		arr.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	c.draw_colored_polygon(arr, col)


## R25：终局演出用的线性淡入曲线 —— t 从 a 到 b 归一化到 0..1
static func _ramp(t: float, a: float, b: float) -> float:
	if b <= a:
		return 1.0 if t >= b else 0.0
	return clampf((t - a) / (b - a), 0.0, 1.0)


## R25：钟摆停摆角（弧度）—— 衰减余弦，约 5 秒后 |角度| < 0.02 视为停摆
static func pendulum_angle(t: float) -> float:
	return 0.55 * cos(4.2 * t) * exp(-1.4 * t)


## R25：终局演出当前阶段（0 遮罩标题 / 1 合页 / 2 统计+钟摆 / 3 结语 / 4 落款提示）
static func ending_stage(t: float) -> int:
	if t < 0.7:
		return 0
	elif t < 1.1:
		return 1
	elif t < 2.5:
		return 2
	elif t < 3.4:
		return 3
	return 4


func _text(c: Control, pos: Vector2, txt: String, size: int, col: Color, outline: int = 6) -> void:
	if outline > 0:
		c.draw_string_outline(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
			outline, Color(0, 0, 0, col.a * 0.85))
	c.draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## R38：结算页的业力行 —— 「业 力 +3 · 人 道」+ 一句短评。
## 颜色随分支走：天道青绿 / 人道素白 / 魔道赤红。
## 三结局不动真结局演出：真结局是「你走到了哪里」，业力是「你一路怎么走」。
func _draw_karma_line(c: Control, y: float, with_line: bool = true) -> void:
	var k := int(Game.karma)
	var b := Game.karma_branch()
	var col := Color(0.86, 0.90, 0.94, 0.95)
	if b == 0:
		col = Color(0.72, 0.95, 0.84, 0.95)
	elif b == 2:
		col = Color(1.0, 0.62, 0.58, 0.95)
	var sign_s := "+" if k > 0 else ""
	_text_c(c, y, "业 力 %s%d · %s" % [sign_s, k, Game.karma_branch_name()], 20, col, 5)
	if with_line:
		_text_c(c, y + 26.0, Game.karma_line(), 17, Color(col.r, col.g, col.b, 0.70), 4)


func _text_c(c: Control, y: float, txt: String, size: int, col: Color, outline: int = 6) -> void:
	var sz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	_text(c, Vector2((1280.0 - sz.x) * 0.5, y), txt, size, col, outline)


## 在指定矩形内水平居中（_text_c 是整屏居中，卡片 / 列表行必须用这个，否则全叠在屏幕中间）
func _text_rc(c: Control, r: Rect2, y: float, txt: String, size: int, col: Color, outline: int = 6) -> void:
	var sz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	_text(c, Vector2(r.get_center().x - sz.x * 0.5, y), txt, size, col, outline)


## R33a：右对齐（经脉页的价格列 —— 价格长短不一，左对齐会参差）
func _text_r(c: Control, xr: float, y: float, txt: String, size: int, col: Color,
		outline: int = 3) -> void:
	var sz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	_text(c, Vector2(xr - sz.x, y), txt, size, col, outline)


## R16：以 pos 为水平中心画字（图鉴页的序号圈 / 标题用）
func _text_c_at(c: Control, pos: Vector2, txt: String, size: int, col: Color,
		outline: int = 6) -> void:
	var sz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	_text(c, Vector2(pos.x - sz.x * 0.5, pos.y), txt, size, col, outline)
