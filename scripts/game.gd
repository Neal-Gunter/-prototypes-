extends Node
## 全局：输入映射、时间缩放（顿帧 / 子弹时间）、震屏、全局状态。

const MAX_HP := 5
const MAX_SOUL := 99.0
const SOUL_PER_HIT := 8.0
const SOUL_PER_CLASH := 12.0
const SOUL_PER_PERFECT := 22.0
const SOUL_HEAL_COST := 33.0

var shake := 0.0
var hurt_flash := 0.0
var perfect_flash := 0.0

## R10：360 度摇杆输出（-1..1 的平面向量）。触屏摇杆写这里，玩家读这里。
## 键盘不用它 —— 玩家脚本里摇杆优先、键盘兜底。
var stick := Vector2.ZERO
## 摇杆是否正在被按住（HUD 用来决定要不要画摇杆底）
var stick_active := false

var _ts_end := 0
var _ts_active := false

# 统计
var clash_count := 0
var perfect_count := 0
var hit_count := 0
var guard_count := 0
var perfect_guard_count := 0
var max_combo := 0
var break_count := 0
var deflect_count := 0
var execute_count := 0          # R11：处决次数
## R38：业力（杀业）。**正 = 魔道，负 = 天道，0 附近 = 人道**。
## 处决 +1（赶尽杀绝）/ 普通击杀 0（各为其主）/ 放走 −1（手下留情）。
## 只在局内累计，每局清零；结局分支看它。
var karma := 0
var spared_count := 0           # R38：放走次数（道心失守窗口内没下手）
const KARMA_MAGIC := 5          # 业力 ≥ +5 → 魔道；≤ −5 → 天道
var boss_line_count := 0        # R14：Boss 台词触发次数（战前/战中/临终）
var fragments: Array = []       # R16：本局拿到的残卷碎片 id（图鉴总数走 Cfg.fragments_seen）
var self_unlocks := 0           # R16：本局新解锁的自述段数
var dmg_taken := 0              # R28：本局被击中次数（无伤评分用，一次受击算一次）


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	_setup_input()


func _setup_input() -> void:
	_action("left", [KEY_A, KEY_LEFT])
	_action("right", [KEY_D, KEY_RIGHT])
	_action("up", [KEY_W, KEY_UP])
	_action("down", [KEY_S, KEY_DOWN])
	_action("jump", [KEY_SPACE])
	_action("attack", [KEY_J, KEY_Z])
	_action("dash", [KEY_SHIFT])
	_action("guard", [KEY_L, KEY_SEMICOLON])
	_action("focus", [KEY_K])
	_action("heavy", [KEY_U, KEY_I])
	_action("execute", [KEY_F])          # R11：处决（道心失守敌人在近身范围时）
	_action("restart", [KEY_R])
	_action("pause", [KEY_ESCAPE])
	_action("start", [KEY_SPACE, KEY_ENTER])
	_action("settings", [KEY_O, KEY_TAB])
	_action("codex", [KEY_C])
	# R31：兵器铭刻页（M = 铭）
	_action("forge", [KEY_M])
	# R32a：快捷格 1/2/3（丹药 / 符箓共用三格）
	_action("quick1", [KEY_1])
	_action("quick2", [KEY_2])
	_action("quick3", [KEY_3])
	# R33c：4 只在局外页签用（丹房），局内不占快捷格
	_action("quick4", [KEY_4])
	_action("fullscreen", [KEY_F11])
	# 2.5D 平面移动：往里（远离镜头 / y 减小）/ 往外（贴近镜头 / y 增大）
	# 键盘同时给 W/S 与 Q/E 两套，摇杆走 Game.stick
	_action("depth_in", [KEY_Q, KEY_W, KEY_UP])
	_action("depth_out", [KEY_E, KEY_S, KEY_DOWN])


func _action(name: String, keys: Array) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name, 0.2)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		var exists := false
		for e in InputMap.action_get_events(name):
			if e is InputEventKey and e.physical_keycode == k:
				exists = true
				break
		if not exists:
			InputMap.action_add_event(name, ev)


# ---------------------------------------------------------------- 时间控制
func hitstop(duration: float = 0.075, scale: float = 0.02) -> void:
	_apply_timescale(scale, duration)


func slowmo(duration: float = 0.42, scale: float = 0.3) -> void:
	_apply_timescale(scale, duration)


func _apply_timescale(scale: float, duration: float) -> void:
	Engine.time_scale = scale
	_ts_active = true
	_ts_end = Time.get_ticks_msec() + int(duration * 1000.0)


func _process(delta: float) -> void:
	if _ts_active and Time.get_ticks_msec() >= _ts_end:
		Engine.time_scale = 1.0
		_ts_active = false
	shake = max(0.0, shake - 42.0 * delta)
	hurt_flash = max(0.0, hurt_flash - 2.2 * delta)
	perfect_flash = max(0.0, perfect_flash - 2.0 * delta)


func add_shake(v: float) -> void:
	var mul := 1.0
	if Cfg != null and is_instance_valid(Cfg):
		mul = Cfg.shake_mul()
	shake = min(shake + v * mul, 22.0)


func reset_stats() -> void:
	clash_count = 0
	perfect_count = 0
	hit_count = 0
	guard_count = 0
	perfect_guard_count = 0
	max_combo = 0
	break_count = 0
	deflect_count = 0
	execute_count = 0
	karma = 0
	spared_count = 0
	boss_line_count = 0
	fragments.clear()
	self_unlocks = 0
	dmg_taken = 0


# ---------------------------------------------------------------- R38 业力
## 记一笔业力（处决 +1 / 放走 −1）。夹在 ±99，避免极端局面把数字刷成笑话。
func add_karma(n: int) -> int:
	if n == 0:
		return karma
	karma = clampi(karma + n, -99, 99)
	return karma


## 结局分支：0 = 天道 / 1 = 人道 / 2 = 魔道
func karma_branch() -> int:
	if karma >= KARMA_MAGIC:
		return 2
	if karma <= -KARMA_MAGIC:
		return 0
	return 1


func karma_branch_name() -> String:
	match karma_branch():
		0: return "天 道"
		2: return "魔 道"
		_: return "人 道"


## 魔剑的解锁门槛：业力够重才认你。法宝池 / 商店都读这里。
func karma_unlocks_magic_sword() -> bool:
	return karma >= KARMA_MAGIC


## 业力 → 一句短评（结算页用，随分支换语气）
func karma_line() -> String:
	var b := karma_branch()
	if b == 2:
		return "剑下无活口　业火自焚身"
	if b == 0:
		return "道心不染　过手皆生"
	return "杀与不杀　各有其时"
