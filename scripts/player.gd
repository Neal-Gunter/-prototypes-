extends CharacterBody2D
## 玩家：小骑士。
## 移动 / 二段跳 / 蹬墙攀爬 / 冲刺 / 三段连斩 / 格挡 / 空中下劈 / 聚集治疗

signal died

const WeaponScript := preload("res://scripts/weapons.gd")
const RelicScript := preload("res://scripts/relics.gd")
const InscribeScript := preload("res://scripts/inscribe.gd")
const ConsumeScript := preload("res://scripts/consumable.gd")
const MeridianScript := preload("res://scripts/meridian.gd")
const SpaceScript := preload("res://scripts/space.gd")

const SPEED := 235.0
const ACCEL := 2400.0
const AIR_ACCEL := 1500.0
const FRICTION := 2800.0
const GRAVITY := 1680.0
const MAX_FALL := 1000.0
const JUMP_V := -600.0
const DOUBLE_JUMP_V := -550.0
const COYOTE := 0.10
const BUFFER := 0.12
const DASH_SPEED := 680.0
const DASH_TIME := 0.16
const DASH_CD := 0.42
## 悟道·剑意交锋的「停手门槛」：上一次挥砍结束到这一刀起手必须间隔 ≥ 这个时间，
## 否则算「连打」，不触发悟道·剑意交锋（R10 需求）
const PERFECT_GAP := 0.30
const MAX_HP := 5
const FOCUS_TIME := 0.85

# 攀爬
const CLIMB_UP := 125.0
const CLIMB_DOWN := 170.0
const WALL_JUMP_X := 340.0
const WALL_JUMP_Y := -575.0

# 格挡 / 护体罡气（R11 · 只狼式「躯干值」）
const GUARD_MOVE_MUL := 0.32
const MAX_POSTURE := 100          # 护体罡气条上限（满 → 道心失守）
const POSTURE_GUARD := 18         # 普通格挡涨自身护体罡气
const POSTURE_HIT := 25           # 被击中（未格挡）涨自身护体罡气
const POSTURE_PERFECT_GUARD := 12 # 精准格挡削减自身护体罡气
const BROKEN_TIME := 1.2          # 道心失守（玩家）窗口：不可行动
const PERFECT_GUARD := 0.15

# 灵力（一切主动动作都要花灵力）
const MAX_STAMINA := 100.0
const STAM_ATK := 9.0          # 兜底：武器表读不到时的每段灵力（R12 起真值在 weapons.gd 的 combo 里）
const STAM_JUMP := 8.0
const STAM_DJUMP := 14.0
const STAM_DASH := 20.0
const STAM_GUARD_HIT := 9.0    # 挡下一刀
const STAM_GUARD_DRAIN := 11.0 # 每秒举盾
const STAM_CLIMB_DRAIN := 7.0  # 每秒攀爬
const STAM_REGEN := 24.0
const STAM_REGEN_IDLE := 40.0
const STAM_DELAY := 0.55
const STAM_EXHAUST := 0.55

# ---------------------------------------------------------------- R29 符力（符剑专属）
## 第 4 把武器「符剑」不吃灵力：远程两段吃「符力」，近战第三段吃灵力。
## 这是全项目第二个资源条 —— 唯一有「弹药管理」的武器。
## 数值取向：满 5 格、每秒回 1.1 → 空仓到满约 4.5 秒；一套连招（2 符）净耗约 1 格，
## 也就是「连打四五套就要歇一口」。原规划写的 0.5/秒太慢（每符等 2 秒），
## 会把符剑变成「站着等回蓝」的武器，故上调到 1.1。
const RUNE_MAX := 5.0
const RUNE_REGEN := 1.1
const RUNE_COST := 1.0       # 每段远程符击消耗
const RUNE_SHOT_SPEED := 620.0
const RUNE_LIFE := 1.6
const RUNE_ULT_SHOTS := 8    # 符阵·万剑：一次布阵射 8 道
const RUNE_BLAST_RADIUS := 80.0   # 符爆处决的波及半径

# 攻速成长：开局手慢，越打越快（最近 10 秒的出刀次数决定热度）
const ATK_SPD_MIN := 0.78        # 初始攻速倍率（1.0 = 以前的手感，这里故意压慢）
const ATK_SPD_MAX := 1.34        # 上限
const HEAT_WINDOW := 10.0        # 统计窗口：最近 10 秒
const HEAT_FULL_HITS := 26.0     # 窗口内 26 刀 = 满热度（连续进攻约 20 秒打满）
const HEAT_RISE := 0.62          # 热度上升速度 / 秒
const HEAT_FALL := 0.30          # 热度下降速度 / 秒
const HEAT_IDLE := 5.0           # 5 秒没砍中敌人 → 开始掉

# 蓄力大招 / 剑气纵横（这两招既不能剑意交锋，也不能被弹反）
const HEAVY_MIN := 0.40          # 按住多久成「凝罡·开山」
const ULT_TIME := 1.15           # 按住多久成「剑气纵横」
const STAM_HEAVY := 22.0
const STAM_ULT := 46.0
const HEAVY_DMG := 3
const ULT_DMG := 5
const ULT_RADIUS := 210.0

enum { ATK_NONE, ATK_WINDUP, ATK_ACTIVE, ATK_RECOVER }

## 三段连斩：wind=抬刀 act=判定 rec=收刀 dmg=伤害 w/h=刀锋判定框
## R12 起这张表只作**兜底**：真正生效的是 weapons.gd 里每把武器自己的 combo 表，
## 由 _stage_data() 取。保留它是因为空表 / 旧存档读不到武器数据时不至于崩。
const STAGES := [
	{"wind": 0.045, "act": 0.11, "rec": 0.13, "dmg": 1, "w": 66.0, "h": 58.0},
	{"wind": 0.030, "act": 0.12, "rec": 0.14, "dmg": 1, "w": 74.0, "h": 64.0},
	{"wind": 0.055, "act": 0.17, "rec": 0.24, "dmg": 2, "w": 90.0, "h": 78.0},
]

## R12 长枪「距离惩罚」：目标离得比这还近 → 枪杆打不出伤害，本段 -1
const SPEAR_DEAD_ZONE := 52.0
## R12 长枪「自动追击」：出刀时前方这个距离内有人，前冲力翻倍
const SPEAR_LUNGE_RANGE := 190.0
const SPEAR_LUNGE_MUL := 1.85

var facing := 1
var atk := ATK_NONE
var atk_t := 0.0
var atk_down := false
var stage := 0
var queued := false
var hit_targets: Array = []
var has_pogo := false

## R33a：经脉等级（节点 id → 0..3）。_ready 时从 Cfg 取引用；
## 自测可以直接赋成假字典，不碰存档、不落盘。
var mer: Dictionary = {}

var dash_t := 0.0
var dash_cd := 0.0
var air_dash_used := false
var invuln := 0.0
var shield_layers := 0      # R35 玄龟灵兽 / 盾傀儡：挡 1 次伤害的护盾层
var hp := MAX_HP
var soul := 0.0
var focus_t := 0.0
var focus_active := false
var stun := 0.0
var dead := false
var flash := 0.0
var can_act := true
## 2.5D：深度 0（贴镜头）~ 1（贴后墙）
var depth := SpaceScript.PLAYER_Z
var _depth_fx := 0.0
## R10：平面移动 —— 冲刺方向 + 悟道·剑意交锋的「停手」判定
var _dash_dir := Vector2.RIGHT
var perfect_ready := true      # 这一刀是不是「停手之后」的干净起手
var _atk_end_t := -99.0        # 上一次挥砍结束的时刻

# 攀爬状态
var on_wall_state := false
var wall_dir := 0
var wall_lock := 0.0
var jumps_left := 2
var climb_fx_t := 0.0

# 格挡状态
var guarding := false
var guard_t := 0.0
var posture := 0
var posture_cd := 0.0
var broken_t := 0.0          # 道心失守窗口剩余时间（>0 即道心失守）
var guard_flash := 0.0

# 灵力状态
var stamina := MAX_STAMINA
var exhausted := false
var _stam_wait := 0.0
var _exh_t := 0.0
var _exh_cd := 0.0

## R29 符力（符剑专属的第二个资源条，与灵力互不干涉）
var rune_power := RUNE_MAX

# ---------------------------------------------------------------- R30 扩容法宝的运行时状态
## 残心：连续几段没被打断（挨打归零）
var _chain_stages := 0
## 追风：刚取消收刀的剩余秒数（>0 = 下一刀首段 +2）
var _after_cancel_t := 0.0
## 追风：取消锁（>0 = 这段时间内不许再取消）
var _no_cancel_t := 0.0
## 会心：上一次 attack_damage() 是否暴击（main 读它飘字）
var _last_crit := false

## R30 会心：基础 5%，阴眼在阴界 +20% / 阳界 -10%。
## 没有阴眼时暴击率恒为 0 —— 会心是「法宝给的机制」，不是全局底层改动，
## 这样不装阴眼时战斗手感与 R29 完全一致。
const CRIT_BASE := 0.05
const CRIT_MULT := 2

# ---------------------------------------------------------------- R31 兵器铭刻
## 精铁：洗练货币。精英怪掉落，**局内有效、不进存档**。
var iron := 0
## 铭刻按武器分开记：weapon_id → [槽0 词条 id 或 "", 槽1 ...]
var inscriptions := {}
## 「反 铭」用：完美弹反成功后 1 秒内的伤害加成窗口
var _parry_buff_t := 0.0

# ---------------------------------------------------------------- R32a 丹药 / 快捷格
## 3 个快捷格，每格 {} 或 {"id": 丹药 id, "n": 数量}。
## 只存 id 与数量 —— 效果全部在 use_quick() 里分派，main 只负责飘字与音效。
var quick: Array = [{}, {}, {}]
## 两次服丹之间的最小间隔（防连点把血刷满）
var _quick_cd := 0.0
## 破境丹窗口：>0 时伤害 +2，同时受伤 +1
var _pojing_t := 0.0
## 九转丹：本局只保一次命
var _jiuzhuan_used := false

# 攻速成长状态
var heat := 0.0
var _atk_log: Array = []
var _heat_idle := 0.0
var hurt_age := 0.0      # 距离上次受伤过了多久（Boss3 用来判断"十秒没打到人"）

# 蓄力 / 剑气纵横
var hv := 0              # 0 无  1 蓄力中  2 挥出
var hv_t := 0.0
var hv_level := 0
var charge := 0.0        # 0..1，给 HUD 画蓄力环
var _ult_done := false
# R18b：专属绝招的多段调度
var _ult_cfg: Dictionary = {}
var _ult_left := 0
var _ult_gap := 0.0
var _ult_timer := 0.0
var _ult_idx := 0

# 肉鸽法宝
var relics: Array = []
var _blood_count := 0
var weapon := "sword"      # 武器 / 流派：sword / spear / dual / rune

signal ult_burst(pos: Vector2, radius: float, dmg: int)
## R18b 直线型绝招（剑 / 枪）：矩形刀路，dir 只用于击退方向
signal ult_strike(pos: Vector2, size: Vector2, dir: int, dmg: int)
## R29 符剑：远程符击 / 符阵·万剑 —— 由 main 生成符箓弹幕
signal talisman_shot(pos: Vector2, dir: Vector2, dmg: int)
## R32b 火符：身前一道火墙（矩形），dir 决定方向
signal talisman_fire(pos: Vector2, size: Vector2, dir: int, dmg: int)
## R32b 雷符：count 道天雷，每道 dmg 点
signal talisman_thunder(count: int, dmg: int)
## R32b 召符：召一只纸人助战 life 秒
signal talisman_summon(life: float)
## R32b 封符：全场定身 dur 秒（Boss 由 enemy.freeze 内部打折）
signal talisman_seal(dur: float)
## R30 反震：格挡成功时广播一次，由 main 找最近敌人反弹（player 不持有 enemies 列表）
signal guard_reflect(pos: Vector2)
## R26：绝招开施通知（无参数）—— 无相·心魔用它做「影·反制」
signal ult_started
## R13 飞剑：连招最后一段甩出去，由 main 生成实体
signal flying_sword(pos: Vector2, dir: Vector2, dmg: int, count: int)

var _coyote := 0.0
var _buffer := 0.0
var _t := 0.0
var _trail: Array = []
var _fx: Node = null
var _air_fx := 0.0
var _col: CollisionShape2D = null
## R12：长枪自动追击需要知道前方有没有敌人，由 main 注入（返回 enemies 数组）
var enemy_provider := Callable()


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var cs := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = 11.0
	cap.height = 46.0
	cs.shape = cap
	cs.position = Vector2(0, 0)
	add_child(cs)
	_col = cs
	z_index = SpaceScript.z_order(depth)
	mer = Cfg.meridian_lv


func setup(fx_node: Node) -> void:
	_fx = fx_node


func _process(delta: float) -> void:
	_t += delta
	if flash > 0.0:
		flash = maxf(0.0, flash - delta * 5.0)
	guard_flash = maxf(0.0, guard_flash - delta * 3.5)
	_air_fx = maxf(0.0, _air_fx - delta)
	var a := 1.0
	if invuln > 0.0:
		a = 0.5 + 0.3 * sin(_t * 34.0)
	modulate = Color(1.0 + flash * 2.2, 1.0 - flash * 0.35, 1.0 - flash * 0.35, a)
	queue_redraw()


# ------------------------------------------------------------------ 物理（R10：地板平面）
## 不再是横版跳跃：整块房间地板就是一个 2D 平面，x 左右、y 里外。
## global_position 直接就是脚下落点，深度由 y 推导（见 space.gd）。
func _physics_process(delta: float) -> void:
	if dead:
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		_advance(delta)
		return

	_tick(delta)
	var busy := stun > 0.0 or not can_act

	# --- 输入：360 度摇杆优先，其次键盘
	var iv := Vector2.ZERO
	if not busy:
		iv = input_vec()
	var mag := minf(iv.length(), 1.0)
	if mag > 0.001:
		iv = iv.normalized() * mag
	else:
		iv = Vector2.ZERO

	if focus_active and mag > 0.25:
		focus_active = false
		focus_t = 0.0
	var mv := Vector2.ZERO if focus_active else iv

	# --- 冲刺（沿输入方向，没有输入就朝面向）
	if dash_t > 0.0:
		dash_t -= delta
		velocity = _dash_dir * DASH_SPEED
		_trail.append(global_position)
		if _trail.size() > 6:
			_trail.pop_front()
		if dash_t <= 0.0:
			velocity *= 0.32
		_advance(delta)
		return

	_trail.clear()

	# --- R12 取消窗口：收刀后段可被闪避 / 格挡打断
	#     这是「连招手感的刹车」：剑收刀早、退得掉；枪收刀晚、一刀砍空就得站着挨
	if can_cancel():
		if Input.is_action_just_pressed("dash") or Input.is_action_pressed("guard"):
			_cancel_attack()

	# --- 格挡姿态
	var want_guard := Input.is_action_pressed("guard") and not busy and atk == ATK_NONE \
		and dash_t <= 0.0 and not focus_active
	if want_guard:
		if not drain(STAM_GUARD_DRAIN * delta * guard_stam_mul()):
			want_guard = false
	if want_guard:
		if not guarding:
			guard_t = 0.0
		guarding = true
		guard_t += delta
	else:
		guarding = false
		guard_t = 0.0

	# --- 冲刺起手
	if not busy and atk == ATK_NONE and dash_cd <= 0.0 and Input.is_action_just_pressed("dash"):
		if spend(STAM_DASH * MeridianScript.dash_cost_mul(mer)):
			_start_dash(mv)

	# --- 挥刀 / 连段
	if hv == 0 and not busy and Input.is_action_just_pressed("attack"):
		if atk == ATK_NONE:
			_start_stage(1, true)
		elif stage < combo_len():
			queued = true

	# --- 凝罡·开山 / 剑气纵横（按住 heavy 蓄力，松手出招；这两招不能剑意交锋也不能被弹反）
	if hv == 0 and not busy and atk == ATK_NONE and not guarding and not focus_active \
			and Input.is_action_pressed("heavy"):
		hv = 1
		hv_t = 0.0
		hv_level = 0
		_ult_done = false
	if hv == 1:
		var cmul := 1.4 if has_relic("core") else 1.0
		hv_t += delta * cmul
		charge = clampf(hv_t / ULT_TIME, 0.0, 1.0)
		hv_level = 2 if hv_t >= ULT_TIME else (1 if hv_t >= HEAVY_MIN else 0)
		velocity = velocity.move_toward(Vector2.ZERO, 1100.0 * delta)
		if _fx and hv_t > HEAVY_MIN and randf() < 0.45:
			_fx.sparks(global_position + Vector2(randf_range(-26, 26), randf_range(-30, 6)),
				Vector2.UP, 1, Color(1.0, 0.82, 0.45, 0.9), 0.4)
		if not Input.is_action_pressed("heavy"):
			if hv_level >= 1:
				_fire_heavy(hv_level)
			else:
				hv = 0
				charge = 0.0
	elif hv == 2:
		hv_t += delta
		if hv_level == 2:
			_ult_tick(delta)
		var hdur := 0.34 if hv_level == 1 else _ult_total_time()
		if hv_t >= hdur:
			hv = 0
			hv_level = 0
			charge = 0.0

	# --- 平面移动
	var mul := 1.0
	if atk != ATK_NONE:
		mul = 0.42
	if hv == 1:
		mul = 0.4
	if guarding:
		mul = GUARD_MOVE_MUL
	if focus_active:
		mul = 0.0
	var target := mv * speed_now() * mul
	velocity = velocity.move_toward(target, ACCEL * delta)
	if mag > 0.15 and atk == ATK_NONE and not focus_active and absf(iv.x) > 0.12:
		facing = 1 if iv.x > 0.0 else -1

	# --- 攻击推进
	if atk != ATK_NONE:
		atk_t += delta
		var tt := _stage_t()
		match atk:
			ATK_WINDUP:
				if atk_t >= tt.x:
					atk = ATK_ACTIVE
					atk_t = 0.0
					SFX.play_rand("slash", 0.9 + stage * 0.06, 1.12, -7.0)
					# R29 符剑：远程段出手 = 射出一道符（没有刀锋判定，见 attack_rect）
					if _stage_is_ranged():
						_fire_talisman()
					# R13 飞剑轴：连招最后一段出手瞬间甩出飞剑（有飞剑类法宝才成立）
					elif stage >= combo_len() and flying_count() > 0:
						_fire_flying()
			ATK_ACTIVE:
				if atk_t >= tt.y:
					if queued and stage < combo_len() and _start_stage(stage + 1, true):
						pass
					else:
						queued = false
						atk = ATK_RECOVER
						atk_t = 0.0
			ATK_RECOVER:
				if queued and stage < combo_len() and atk_t >= 0.04:
					if not _start_stage(stage + 1, true):
						queued = false
				elif atk_t >= tt.z:
					atk = ATK_NONE
					atk_t = 0.0
					stage = 0
					queued = false
					_atk_end_t = _t          # 记录收刀时刻，用于「连打不算悟道·剑意交锋」

	# --- 道心失守窗口
	if broken_t > 0.0:
		broken_t = maxf(0.0, broken_t - delta)

	# --- R30 计时器（追风）
	if _after_cancel_t > 0.0:
		_after_cancel_t = maxf(0.0, _after_cancel_t - delta)
	if _no_cancel_t > 0.0:
		_no_cancel_t = maxf(0.0, _no_cancel_t - delta)
	# R31 反铭：完美弹反后的 1 秒伤害窗口
	if _parry_buff_t > 0.0:
		_parry_buff_t = maxf(0.0, _parry_buff_t - delta)

	# --- 护体罡气恢复（不在受压窗口内时缓慢回落）
	if posture > 0:
		posture_cd -= delta
		if posture_cd <= 0.0:
			posture = maxi(0, posture - 1)
			# R30 龟息：回落慢 20%（0.12 → 0.15 秒一点）
			posture_cd = 0.15 if has_relic("guixi") else 0.12

	# --- 聚集治疗（站定不动才回血）
	if (not busy) and atk == ATK_NONE and not guarding and Input.is_action_pressed("focus") \
			and mag < 0.2 and soul >= heal_cost() and hp < max_hp():
		if not focus_active:
			focus_active = true
			focus_t = 0.0
		focus_t += delta
		if _fx and randf() < 0.25:
			_fx.sparks(global_position + Vector2(randf_range(-16, 16), randf_range(-24, 10)),
				Vector2.UP, 1, Color(0.7, 0.95, 1.0, 0.9), 0.35)
		if focus_t >= FOCUS_TIME:
			hp += 1
			soul -= heal_cost()
			focus_t = 0.0
			focus_active = false
			SFX.play("heal", 1.0, -3.0)
			if _fx:
				_fx.ring(global_position, 10.0, 70.0, Color(0.7, 0.95, 1.0), 0.45, 3.0)
				_fx.text(global_position + Vector2(0, -46), "回复", Color(0.8, 0.95, 1.0), 20)
	else:
		focus_active = false
		focus_t = 0.0

	_advance(delta)


## 读输入：摇杆（触屏 360 度）优先，否则 A/D + W/S（或 Q/E）
func input_vec() -> Vector2:
	var v := Vector2.ZERO
	if Game != null and is_instance_valid(Game):
		v = Game.stick
	if v.length() > 0.14:
		return v
	var x := Input.get_axis("left", "right")
	var y := Input.get_axis("depth_in", "depth_out")   # W / Q = -1 → 往里（y 减小）
	return Vector2(x, y)


## 把速度落到位置上：夹在房间地板内，深度与 z_index 跟着 y 走
func _advance(delta: float) -> void:
	var np := global_position + velocity * delta
	np.x = clampf(np.x, SpaceScript.ROOM_X0 + 14.0, SpaceScript.ROOM_X1 - 14.0)
	np.y = clampf(np.y, SpaceScript.FLOOR_FAR_Y + 10.0, SpaceScript.FLOOR_NEAR_Y - 4.0)
	global_position = np
	depth = SpaceScript.depth_of(np.y)
	z_index = SpaceScript.z_order(depth)
	# 里外走位时脚下扬尘
	if absf(velocity.y) > 40.0:
		_depth_fx -= delta
		if _depth_fx <= 0.0:
			_depth_fx = 0.18
			if _fx:
				_fx.dust(global_position + Vector2(-facing * 8.0, 4), 1)
	else:
		_depth_fx = 0.0



func _tick(delta: float) -> void:
	invuln = maxf(0.0, invuln - delta)
	dash_cd = maxf(0.0, dash_cd - delta)
	stun = maxf(0.0, stun - delta)
	wall_lock = maxf(0.0, wall_lock - delta)
	hurt_age += delta
	# R32a 丹药计时
	_quick_cd = maxf(0.0, _quick_cd - delta)
	_pojing_t = maxf(0.0, _pojing_t - delta)

	# --- 攻速成长
	_heat_idle += delta
	while not _atk_log.is_empty() and _t - float(_atk_log[0]) > HEAT_WINDOW:
		_atk_log.pop_front()
	var target := clampf(float(_atk_log.size()) / HEAT_FULL_HITS, 0.0, 1.0)
	if _heat_idle > HEAT_IDLE:
		target = 0.0
	var rise := HEAT_RISE * (1.5 if has_relic("wind") else 1.0) \
		* MeridianScript.heat_rise_mul(mer)
	if target > heat:
		heat = minf(target, heat + rise * delta)
	else:
		heat = maxf(target, heat - HEAT_FALL * MeridianScript.heat_fall_mul(mer) * delta)

	# --- 灵力恢复
	if _stam_wait > 0.0:
		_stam_wait -= delta
	else:
		var rate := STAM_REGEN
		if absf(velocity.length()) < 24.0 and atk == ATK_NONE and not guarding:
			rate = STAM_REGEN_IDLE
		# R33a 聚灵：回灵力更快（只改回复速度，不改上限）
		rate *= MeridianScript.stamina_regen_mul(mer)
		stamina = minf(max_stamina(), stamina + rate * delta)
	_exh_cd = maxf(0.0, _exh_cd - delta)
	if _exh_t > 0.0:
		_exh_t -= delta
		if _exh_t <= 0.0:
			exhausted = false

	# --- R29 符力恢复：只有符剑用得上，但不看「停手 / 举盾」—— 符力是弹药，不是力气
	if weapon == "rune":
		rune_power = minf(rune_max(), rune_power + RUNE_REGEN
			* MeridianScript.rune_regen_mul(mer) * delta)


## 花灵力：不够就进入「力竭」，返回 false
func spend(cost: float) -> bool:
	if stamina + 0.001 < cost:
		_exhaust()
		return false
	stamina = maxf(0.0, stamina - cost)
	_stam_wait = STAM_DELAY * MeridianScript.stam_delay_mul(mer)
	return true


## 持续消耗（每秒），返回是否还撑得住
func drain(cost: float) -> bool:
	if stamina <= 0.001:
		return false
	stamina = maxf(0.0, stamina - cost)
	_stam_wait = STAM_DELAY * MeridianScript.stam_delay_mul(mer)
	if stamina <= 0.001:
		return false
	return true


func _exhaust() -> void:
	exhausted = true
	_exh_t = STAM_EXHAUST
	if _exh_cd > 0.0:
		return
	_exh_cd = 0.9
	if _fx:
		_fx.text(global_position + Vector2(0, -54), "力 竭", Color(1.0, 0.72, 0.45), 19, 32)
		_fx.dust(global_position + Vector2(0, 20), 4)
	SFX.play_rand("land", 1.5, 1.62, -20.0)


func stamina_frac() -> float:
	return clampf(stamina / max_stamina(), 0.0, 1.0)


# ------------------------------------------------------------------ 法宝
## R13 位次：剑 / 体 / 灵 三个槽，每槽默认 SLOT_CAP 件；满了必须替换
## R16：容量改成每槽独立、可扩容（花道蕴把某一位次扩到 SLOT_CAP_EX）
var slots := {"blade": [], "wall": [], "spirit": []}
var slot_caps := {"blade": RelicScript.SLOT_CAP, "wall": RelicScript.SLOT_CAP,
	"spirit": RelicScript.SLOT_CAP}

## R16：扩一次格要多少道蕴
const SLOT_EXPAND_COST := 45.0


func has_relic(id: String) -> bool:
	return relics.has(id)


## 放入本位次。返回 false = 该位次已满（调用方需要走替换流程）
func add_relic(id: String) -> bool:
	if id == "":
		return true
	if relics.has(id):
		return true
	var sl := RelicScript.slot_of(id)
	if not slots.has(sl):
		sl = "blade"
	if slots[sl].size() >= slot_cap(sl):
		return false
	relics.append(id)
	slots[sl].append(id)
	_on_relic_gained(id)
	return true


## 拿到的瞬间就生效的一次性效果
func _on_relic_gained(id: String) -> void:
	if id == "soul":
		soul = minf(soul + 40.0, Game.MAX_SOUL)
	# R21：影息 = 灵息的镜像副本，同样拿到即 +40 道蕴（与灵息可叠加）
	if id == "soul_shadow":
		soul = minf(soul + 40.0, Game.MAX_SOUL)
	if id == "lung":
		stamina = max_stamina()
	# R30：铁衣 +2 / 聚灵 -1 —— 上限变了，当前血量要跟着夹紧（+2 时顺便补满这 2 点）
	if id == "tieyi":
		hp = mini(hp + 2, max_hp())
	if id == "juling":
		hp = mini(hp, max_hp())


## R13 替换：先丢掉 old_id，再把 new_id 放进它的位次
func swap_relic(old_id: String, new_id: String) -> bool:
	if not relics.has(old_id):
		return false
	relics.erase(old_id)
	for k in slots.keys():
		slots[k].erase(old_id)
	return add_relic(new_id)


## 新开一局清空（R13 顺手修：此前开局从不清 relics，法宝会跨局累积）
func reset_relics() -> void:
	relics.clear()
	for k in slots.keys():
		slots[k].clear()
		slot_caps[k] = RelicScript.SLOT_CAP
	_blood_count = 0


func slot_list(slot: String) -> Array:
	return slots.get(slot, [])


func slot_used(slot: String) -> int:
	return slot_list(slot).size()


## R16：某位次当前的容量（3 或扩容后的 4）
func slot_cap(slot: String) -> int:
	return int(slot_caps.get(slot, RelicScript.SLOT_CAP))


func slot_full(slot: String) -> bool:
	return slot_used(slot) >= slot_cap(slot)


## R16：位次扩容 —— 装满之后才能扩，扩完多一格。返回是否真的扩了
func can_expand_slot(slot: String) -> bool:
	return slot_cap(slot) < RelicScript.SLOT_CAP_EX and slot_full(slot)


## 扩容（不扣道蕴，扣费由调用方做，便于商店 / 替换页共用）
func expand_slot(slot: String) -> bool:
	if not can_expand_slot(slot):
		return false
	slot_caps[slot] = slot_cap(slot) + 1
	return true


## 三槽全部装满
func slots_all_full() -> bool:
	for k in RelicScript.SLOT_ORDER:
		if not slot_full(str(k)):
			return false
	return true


# ------------------------------------------------------------------ R13 飞剑轴
## 手里有几件「飞剑类」法宝（0 = 没有飞剑）
func flying_count() -> int:
	return RelicScript.count_kind_in(relics, RelicScript.KIND_RANGED)


## 飞剑流：刃位有飞剑类 + 灵位至少 2 件道蕴类 → 跨位联动成立
func is_flying_build() -> bool:
	if RelicScript.count_kind_in(slot_list("blade"), RelicScript.KIND_RANGED) <= 0:
		return false
	return RelicScript.count_kind_in(slot_list("spirit"), RelicScript.KIND_SOUL) >= 2


## 飞剑伤害：基础 1 + 穿云 + 飞剑流
func flying_damage() -> int:
	var d := 1
	if has_relic("pierce"):
		d += 1
	if is_flying_build():
		d += 1
	# R30 剑匣：飞剑伤害 +1（约 +50%）。条件是「你真有飞剑」——
	# 剑匣自己 kind 是 melee，不会替你把飞剑流打开。
	if has_relic("jianxia") and flying_count() > 0:
		d += 1
	return d


## 一道飞剑：最后由 main 生成实体
func _fire_flying() -> void:
	var n := flying_count()
	if n <= 0:
		return
	var dir := Vector2(float(facing), 0.0)
	flying_sword.emit(global_position + Vector2(float(facing) * 34.0, -12.0), dir,
		flying_damage(), n)


# ---------------------------------------------------------------- R29 符剑 · 符击
## 当前这一段是不是远程段（远程段没有刀锋判定，只有一道符）
func _stage_is_ranged() -> bool:
	if stage <= 0:
		return false
	return bool(_stage_data().get("ranged", false))


## 射出一道符：伤害沿用 attack_damage()，所以锋刃 / 剑道套装 / 锋影全都照吃
func _fire_talisman() -> void:
	var dir := Vector2(float(facing), 0.0)
	talisman_shot.emit(global_position + Vector2(float(facing) * 26.0, -14.0), dir,
		attack_damage())
	SFX.play("slash", 1.42, -9.0)
	if _fx:
		_fx.ring(global_position + Vector2(float(facing) * 26.0, -14.0), 4.0, 18.0,
			Color(0.86, 0.74, 1.0), 0.18, 2.0)



## 流派名（Build 身份）：位次装满 + 跨位联动决定
func build_title() -> String:
	if is_flying_build():
		return "飞 剑 流"
	if slot_full("blade"):
		return "剑 修"
	if slot_full("wall"):
		return "体 修"
	if slot_full("spirit"):
		return "灵 御"
	return "散 修"


# ------------------------------------------------------------------ 套装
## 某个套系已经拿了几件
func set_count(tag: String) -> int:
	var n := 0
	for id in relics:
		if RelicScript.set_of(str(id)) == tag:
			n += 1
	return n


## 同套系拿满 3 件 → 质变
func has_set(tag: String) -> bool:
	return set_count(tag) >= 3


## R16：二次质变是否成立（A 位装满 + B 位有指定法宝）
func has_mutation(slot: String) -> bool:
	var m: Dictionary = RelicScript.COMBO_MUTATION.get(slot, {})
	if m.is_empty():
		return false
	if not slot_full(slot):
		return false
	return has_relic(str(m.get("need", "")))


## R16：当前成立的二次质变名（HUD 流派行后面追加）
func mutation_titles() -> Array:
	var out := []
	for k in RelicScript.SLOT_ORDER:
		if has_mutation(str(k)):
			out.append(str(RelicScript.COMBO_MUTATION[k]["name"]))
	return out


func soul_mul() -> float:
	var m := 1.25 if has_set("spirit") else 1.0
	# R33a 道蕴：经脉加成（与法宝 / 位次乘算）
	m *= MeridianScript.soul_mul(mer)
	# R13 灵御（灵位装满）：再 ×1.2
	if slot_full("spirit"):
		m *= 1.2
	# R16 灵息不灭（灵位满 + 刃位有长锋）：再 ×1.3
	if has_mutation("spirit"):
		m *= 1.3
	# R30 聚灵：道蕴 +30%（代价是气血上限 -1，见 max_hp）
	if has_relic("juling"):
		m *= 1.3
	return m


func ult_radius() -> float:
	var base := float(_ult_cfg.get("radius", ULT_RADIUS)) if not _ult_cfg.is_empty() else ULT_RADIUS
	if base <= 0.0:
		base = ULT_RADIUS
	return base * (1.4 if has_set("spirit") else 1.0)


# ------------------------------------------------------------------ 武器
func set_weapon(id: String) -> void:
	weapon = id


func weapon_name() -> String:
	return WeaponScript.name_of(weapon)


## R14：当前武器配色（供「记忆回响」暗色剪影取轮廓光）
func weapon_hue() -> float:
	return float(WeaponScript.by_id(weapon).get("hue", 0.56))


func max_stamina() -> float:
	return MAX_STAMINA + (25.0 if has_relic("lung") else 0.0) \
		+ MeridianScript.stamina_bonus(mer)


# ---------------------------------------------------------------- R30 气血上限
## 气血上限不能再直接用常量 MAX_HP：铁衣 +2、聚灵 -1。
func max_hp() -> int:
	var m := MAX_HP
	if has_relic("tieyi"):
		m += 2
	if has_relic("juling"):
		m -= 1
	if has_relic("pact"):
		m -= 1
	# R38 魔剑：代价是气血上限 -1（处决伤害翻倍换的）
	if has_relic("magic"):
		m -= 1
	return maxi(1, m)


# ---------------------------------------------------------------- R35 同伴辅助接口
## 加护盾层（玄龟灵兽 / 盾傀儡给的「挡 1 次」）。上限 5 层，避免叠太多。
func add_shield(n: int) -> void:
	shield_layers = mini(5, shield_layers + maxi(0, n))


## 回灵力（青鸟灵兽用）。封顶 max_stamina()，不为负。
func add_stamina(n: float) -> void:
	stamina = clampf(stamina + n, 0.0, max_stamina())


## 软回血（青鸟 2 级以上用）：不满才回，不超上限。
func add_hp_soft(n: int) -> void:
	if hp < max_hp():
		hp = mini(max_hp(), hp + maxi(0, n))


# ---------------------------------------------------------------- R30 阴 / 阳 与 会心
## 阴界 = 贴后墙（depth 大）；阳界 = 贴镜头（depth 小）。HUD 左侧那条竖条就是这个刻度。
func in_yin() -> bool:
	return depth >= 0.5


func in_yang() -> bool:
	return depth < 0.5


## 暴击率。没有阴眼 = 0（会心只从法宝来，不装就跟以前一模一样）
func crit_chance() -> float:
	if not has_relic("yinyan"):
		return 0.0
	var c := CRIT_BASE + (0.20 if in_yin() else -0.10)
	return clampf(c, 0.0, 0.95)


## main 在调用 attack_damage() 之后读它，决定要不要飘「会 心」
func last_crit() -> bool:
	return _last_crit


# ---------------------------------------------------------------- R31 兵器铭刻
## 当前武器的两个槽（第一次访问时自动建）。返回的是**数组本体**，
## 所以调用方改它等于改铭刻 —— 洗练 / 铭刻都走 forge_slot / reforge_slot，不直接改。
func inscribe_slots() -> Array:
	if not inscriptions.has(weapon):
		var a: Array = []
		for _i in InscribeScript.SLOTS:
			a.append("")
		inscriptions[weapon] = a
	return inscriptions[weapon]


## 某把武器有没有某条词条（默认查当前武器）
func has_inscribe(id: String, weapon_id: String = "") -> bool:
	var w := weapon if weapon_id == "" else weapon_id
	if not inscriptions.has(w):
		return false
	return (inscriptions[w] as Array).has(id)


func inscribe_count() -> int:
	var n := 0
	for it in inscribe_slots():
		if str(it) != "":
			n += 1
	return n


func add_iron(n: int) -> void:
	iron = maxi(0, iron + n)


## 空槽刻一条：扣精铁、随机抽一条「这把武器能出、两槽里还没有」的词条。
## 槽满 / 精铁不够 / 池子抽干都返回 false（调用方负责提示）。
func forge_slot(i: int, rng: RandomNumberGenerator) -> bool:
	var slots := inscribe_slots()
	if i < 0 or i >= slots.size():
		return false
	if str(slots[i]) != "":
		return false
	if iron < InscribeScript.COST_FORGE:
		return false
	var id := InscribeScript.roll(rng, weapon, slots)
	if id == "":
		return false
	iron -= InscribeScript.COST_FORGE
	slots[i] = id
	return true


## 洗练：把已有词条重 roll 一条（会排除另一槽已有的，保证两槽不重复）
func reforge_slot(i: int, rng: RandomNumberGenerator) -> bool:
	var slots := inscribe_slots()
	if i < 0 or i >= slots.size():
		return false
	if str(slots[i]) == "":
		return false
	if iron < InscribeScript.COST_REFORGE:
		return false
	var taken: Array = []
	for k in slots.size():
		if k != i and str(slots[k]) != "":
			taken.append(str(slots[k]))
	var id := InscribeScript.roll(rng, weapon, taken)
	if id == "":
		return false
	iron -= InscribeScript.COST_REFORGE
	slots[i] = id
	return true


## 一局重开 / 读档：精铁与铭刻一起清（铭刻是局内构筑，不进存档）
func reset_inscribe() -> void:
	iron = 0
	inscriptions.clear()
	_parry_buff_t = 0.0


# ---------------------------------------------------------------- R32a 丹药 / 快捷格
## 一局重开：丹药是局内资源，同样不进存档
func reset_quick() -> void:
	quick = [{}, {}, {}]
	_quick_cd = 0.0
	_pojing_t = 0.0
	_jiuzhuan_used = false


func quick_slot(i: int) -> Dictionary:
	if i < 0 or i >= quick.size():
		return {}
	return quick[i]


func quick_id(i: int) -> String:
	return str(quick_slot(i).get("id", ""))


func quick_count(i: int) -> int:
	return int(quick_slot(i).get("n", 0))


## 服丹冷却剩余（HUD 画遮罩用）
func quick_cd() -> float:
	return _quick_cd


## 破境丹窗口剩余秒数（HUD 提示用）
func pojing_left() -> float:
	return _pojing_t


## 剩几个空格（宝箱 / 商人用来判断「还装得下吗」）
func quick_free() -> int:
	var k := 0
	for s in quick:
		if (s as Dictionary).is_empty():
			k += 1
	return k


## 进丹药：先叠到同 id 的格子，再找空格。返回是否吃下（满了就是 false）。
func add_pill(id: String, n: int = 1) -> bool:
	if not ConsumeScript.is_pill(id) or n <= 0:
		return false
	return add_item(id, n)


## R32b：快捷格不认「丹」还是「符」—— 只认 id，丹药与符箓混装同一组格子
func add_item(id: String, n: int = 1) -> bool:
	if not ConsumeScript.is_item(id) or n <= 0:
		return false
	var stacked_full := false
	for i in quick.size():
		var s: Dictionary = quick[i]
		if str(s.get("id", "")) == id:
			if int(s.get("n", 0)) >= ConsumeScript.STACK:
				# 同 id 已经叠满：不再另开一格（三格是硬上限，不许同一种占两格）
				stacked_full = true
				continue
			s["n"] = mini(int(s.get("n", 0)) + n, ConsumeScript.STACK)
			return true
	if stacked_full:
		return false
	for i in quick.size():
		if (quick[i] as Dictionary).is_empty():
			quick[i] = {"id": id, "n": mini(n, ConsumeScript.STACK)}
			return true
	return false


## 从快捷格扣掉一个指定丹药（九转丹自动触发用）
func _consume_pill(id: String) -> bool:
	for i in quick.size():
		var s: Dictionary = quick[i]
		if str(s.get("id", "")) == id and int(s.get("n", 0)) > 0:
			var left := int(s["n"]) - 1
			if left <= 0:
				quick[i] = {}
			else:
				s["n"] = left
			return true
	return false


## 洗髓：把负面状态一次清干净（护体罡气 / 道心失守 / 力竭 / 破境丹的受伤惩罚）
func _clear_debuff() -> void:
	posture = 0
	posture_cd = 0.0
	broken_t = 0.0
	stun = 0.0
	exhausted = false
	_exh_t = 0.0
	_exh_cd = 0.0
	_stam_wait = 0.0
	_pojing_t = 0.0
	flash = 0.0


## 用第 i 格。返回 {"ok": bool, "id": String, "msg": String}
## 失败也要说清楚原因（空槽 / 冷却 / 血满 / 灵力满 / 罡气本来就干净），
## 否则玩家会以为「点了没反应」。
func use_quick(i: int) -> Dictionary:
	if i < 0 or i >= quick.size():
		return {"ok": false, "id": "", "msg": ""}
	var s: Dictionary = quick[i]
	var id := str(s.get("id", ""))
	if id == "":
		return {"ok": false, "id": "", "msg": "第 %d 格 是 空 的" % (i + 1)}
	if _quick_cd > 0.0 or dead:
		return {"ok": false, "id": id, "msg": ""}
	# R32b：符箓走另一条分派 —— 落世界的那一半由 main 接信号
	if ConsumeScript.is_talisman(id):
		return _use_talisman(i, id)
	match id:
		"huichun":
			if hp >= max_hp():
				return {"ok": false, "id": id, "msg": "气 血 已 满"}
			hp = mini(hp + 2, max_hp())
		"juling":
			if stamina >= max_stamina() - 0.5:
				return {"ok": false, "id": id, "msg": "灵 力 已 满"}
			stamina = minf(max_stamina(), stamina + 50.0)
			exhausted = false
			_exh_t = 0.0
		"gangqi":
			if posture <= 0:
				return {"ok": false, "id": id, "msg": "护 体 罡 气 本 就 是 干 净 的"}
			posture = maxi(0, posture - 40)
			posture_cd = 0.0
		"pojing":
			_pojing_t = 10.0
		"xisui":
			_clear_debuff()
		"jiuzhuan":
			# 九转丹是「致死时自动触发」的，主动吃没有意义 —— 明说，别让玩家白吞
			return {"ok": false, "id": id, "msg": "九 转 丹 · 致 死 时 自 动 触 发"}
		_:
			return {"ok": false, "id": id, "msg": ""}
	# 吃下去才扣数量
	_spend_slot(i)
	if _fx:
		_fx.ring(global_position, 6.0, 44.0, ConsumeScript.tint_of(id), 0.35, 3.0)
		_fx.text(global_position + Vector2(0, -52.0), ConsumeScript.name_of(id),
			ConsumeScript.tint_of(id), 16, 34)
	SFX.play("heal", 1.15, -6.0)
	return {"ok": true, "id": id, "msg": ConsumeScript.name_of(id)}


## 扣掉第 i 格的一个，并起服丹冷却
func _spend_slot(i: int) -> void:
	var s: Dictionary = quick[i]
	var left := int(s.get("n", 1)) - 1
	if left <= 0:
		quick[i] = {}
	else:
		s["n"] = left
	_quick_cd = ConsumeScript.USE_CD * MeridianScript.item_cd_mul(mer)


## R32b：六张符的分派。玩家侧能自己完成的（无敌 / 位移）就地做完，
## 要落世界的（火墙 / 天雷 / 纸人 / 定身）发信号给 main —— 和绝招同一套写法。
func _use_talisman(i: int, id: String) -> Dictionary:
	var v := ConsumeScript.val_of(id)
	match id:
		"huo":
			talisman_fire.emit(global_position, Vector2(200.0, 96.0), facing, int(v))
		"lei":
			talisman_thunder.emit(5, int(v))
		"shu":
			invuln = maxf(invuln, v)
			if _fx:
				_fx.ring(global_position, 14.0, 96.0, Color(0.62, 0.92, 1.0), 0.45, 4.0)
		"dun":
			# 贴墙时拒绝：不然白白吃掉一张符，玩家只会觉得「这符坏了」
			var from := global_position.x
			var to := clampf(from + float(facing) * v,
				SpaceScript.ROOM_X0 + 16.0, SpaceScript.ROOM_X1 - 16.0)
			if absf(to - from) < 60.0:
				return {"ok": false, "id": id, "msg": "前 方 无 路"}
			if _fx:
				_fx.burst(global_position, 18, Color(0.80, 0.74, 1.0), 1.0)
				_fx.ring(global_position, 8.0, 60.0, Color(0.80, 0.74, 1.0), 0.3, 3.0)
			global_position.x = to
			invuln = maxf(invuln, 0.35)
			if _fx:
				_fx.burst(global_position, 18, Color(0.80, 0.74, 1.0), 1.0)
				_fx.ring(global_position, 8.0, 72.0, Color(0.86, 0.80, 1.0), 0.35, 3.0)
			SFX.play("dash", 1.0, -4.0)
		"zhao":
			talisman_summon.emit(v)
		"feng":
			talisman_seal.emit(v)
		_:
			return {"ok": false, "id": id, "msg": ""}
	_spend_slot(i)
	if _fx:
		_fx.text(global_position + Vector2(0, -56.0), ConsumeScript.name_of(id),
			ConsumeScript.tint_of(id), 17, 36)
	SFX.play("gate", 1.35, -6.0)
	return {"ok": true, "id": id, "msg": ConsumeScript.name_of(id)}


# ---- 词条效果（乘区集中在这里，接入点只调函数，不散落魔法数）
## 疾铭：取消窗口提前 5%
func inscribe_cancel_mul() -> float:
	return 0.95 if has_inscribe("cancel") else 1.0


## 长铭：刀锋判定范围 +6%
func inscribe_reach_mul() -> float:
	return 1.06 if has_inscribe("span") else 1.0


## 快铭：出招速度 +5%（只改段位时长，不改攻速成长 / HUD 读数）
func inscribe_tempo_mul() -> float:
	return 1.05 if has_inscribe("tempo") else 1.0


## 省铭：出刀灵力消耗 -8%
func inscribe_stam_mul() -> float:
	return 0.92 if has_inscribe("stam") else 1.0


## 压铭：架势压制 +10%
func inscribe_posture_mul() -> float:
	return 1.10 if has_inscribe("press") else 1.0


## 迅符：符击飞行速度 +15%
func talisman_speed() -> float:
	return RUNE_SHOT_SPEED * (1.15 if has_inscribe("runev") else 1.0) \
		* MeridianScript.feijian_speed_mul(mer)


# ---------------------------------------------------------------- R29 符力接口
## 符力上限（R30「符囊」+2 / R31「符铭」+1；不带符剑时两者都无效，因为用不到符力）
func rune_max() -> float:
	var m := RUNE_MAX
	if has_relic("funang"):
		m += 2.0
	if has_inscribe("rune1"):
		m += 1.0
	# R33b 灵贯：符力上限加成（符力只有 5 点，+3 已经是六成，所以按点数给、不按百分比）
	return m + MeridianScript.rune_bonus(mer)


func rune_frac() -> float:
	return clampf(rune_power / maxf(0.001, rune_max()), 0.0, 1.0)


func rune_is_full() -> bool:
	return rune_power >= rune_max() - 0.001


## 这把武器用不用符力（HUD 画不画符力条靠它判断）
func uses_rune() -> bool:
	return WeaponScript.has_ranged_stage(weapon)


## 花符力：不够就返回 false（不进入力竭 —— 符力不是力气，空了只是打不出符）
func spend_rune(cost: float) -> bool:
	if rune_power + 0.0001 < cost:
		return false
	rune_power = maxf(0.0, rune_power - cost)
	return true


func speed_now() -> float:
	var m := 1.12 if has_relic("feather") else 1.0
	# R30 铁衣：气血 +2 的代价是移速 -10%
	if has_relic("tieyi"):
		m *= 0.9
	# R33a 体魄：经脉是局外成长，最后再乘 —— 与法宝的代价互不干扰
	m *= MeridianScript.move_mul(mer)
	return SPEED * m


## R13：剑鞘与壁之套从「+1 格」改成「+20 护体罡气」—— R11 把护体罡气从 3 格改成 0–100 后，
## 原来那句 +1 等于只加了 1 点，等于没有。
func posture_max() -> int:
	# R21：剑鞘 / 影鞘（镜像副本）可叠加，各 +20
	var m := MAX_POSTURE + (20 if has_relic("sheath") else 0) \
		+ (20 if has_relic("sheath_shadow") else 0) + (15 if has_set("wall") else 0)
	# R30 断念：交锋压制更狠，代价是自身罡气上限 -15
	if has_relic("duannian"):
		m -= 15
	# R33a 罡气：先算上限，再给经脉加成（不会被断念的 -15 吃掉）
	m += MeridianScript.posture_bonus(mer)
	return maxi(20, m)


func perfect_guard_time() -> float:
	var t := PERFECT_GUARD + (0.08 if has_relic("wall") else 0.0) + (0.06 if has_set("wall") else 0.0)
	# R13 壁守（壁位装满）：再 +0.04
	if slot_full("wall"):
		t += 0.04
	# R33b 凝神：判定窗口更宽（只放宽「挡下瞬间」的判定，不改挡刀的灵力消耗）
	return t * MeridianScript.perfect_guard_mul(mer)


## R16 不动如山（壁位满 + 灵位有灵息）：格挡灵力消耗 -30%
func guard_stam_mul() -> float:
	var m := 0.70 if has_mutation("wall") else 1.0
	# R33a 格挡：举盾与挡刀都更省（同一把尺子，不拆两套）
	m *= MeridianScript.guard_drain_mul(mer)
	return m


func heal_cost() -> float:
	# R21：灵息 / 影息（镜像副本）可叠加，各 -8
	var c := Game.SOUL_HEAL_COST - (8.0 if has_relic("soul") else 0.0) \
		- (8.0 if has_relic("soul_shadow") else 0.0)
	# R33b 丹火：打坐回血更省道蕴（只降价，不改回血量与耗时）
	return c * MeridianScript.heal_cost_mul(mer)


# ------------------------------------------------------------------ 蓄力 / 剑气纵横
func _fire_heavy(level: int) -> void:
	var cost := STAM_ULT if level >= 2 else STAM_HEAVY
	if not spend(cost):
		hv = 0
		hv_level = 0
		charge = 0.0
		return
	hv = 2
	hv_t = 0.0
	hv_level = level
	_ult_done = false
	hit_targets.clear()
	atk = ATK_NONE
	atk_t = 0.0
	stage = 0
	queued = false
	if level >= 2:
		invuln = maxf(invuln, 0.62)
		Game.hitstop(0.12, 0.02)
		Game.add_shake(12.0)
		SFX.play("clash_perfect", 0.72, -2.0)
		_ult_begin()
	else:
		velocity.x = float(facing) * 380.0
		Game.hitstop(0.07, 0.03)
		Game.add_shake(8.0)
		SFX.play("slash", 0.62, -2.0)
	if _fx:
		_fx.ring(global_position, 8.0, 96.0 if level < 2 else 170.0, Color(1.0, 0.8, 0.42), 0.35, 3.0)
		_fx.text(global_position + Vector2(0, -56),
			"凝 罡 · 开 山" if level < 2 else WeaponScript.ult_name(weapon),
			Color(1.0, 0.85, 0.5), 22 if level < 2 else 30, 40)


# ---------------------------------------------------------------- R18b 专属绝招
## 读当前武器的绝招形态，开始逐段放。三把武器消耗与总伤害相同，只有形状不同。
func _ult_begin() -> void:
	ult_started.emit()   # R26：先广播开施 —— 无相·心魔的「影·反制」监听这个
	_ult_cfg = WeaponScript.ult_of(weapon)
	_ult_left = int(_ult_cfg.get("shots", 1))
	_ult_gap = float(_ult_cfg.get("gap", 0.0))
	_ult_timer = 0.0
	_ult_idx = 0
	_ult_done = false


func _ult_total_time() -> float:
	var shots := maxi(1, int(_ult_cfg.get("shots", 1)))
	return maxf(0.62, float(shots - 1) * _ult_gap + 0.52)


func _ult_tick(delta: float) -> void:
	if _ult_left <= 0:
		return
	_ult_timer -= delta
	# 第一段立即出手；之后按 gap 排队
	while _ult_left > 0 and _ult_timer <= 0.0:
		_ult_fire_one(_ult_idx)
		_ult_idx += 1
		_ult_left -= 1
		_ult_timer += maxf(0.016, _ult_gap)
	if _ult_left <= 0:
		_ult_done = true


func _ult_fire_one(i: int) -> void:
	var id := str(_ult_cfg.get("id", "line"))
	var dmg := int(_ult_cfg.get("dmg", ULT_DMG))
	var dir := facing
	if id == "spin":
		# 双刀：原地六段旋风，范围小、段数多
		ult_burst.emit(global_position, ult_radius(), dmg)
		Game.add_shake(5.0)
		SFX.play("slash", 1.18, -7.0)
		if _fx:
			_fx.ring(global_position, 18.0, ult_radius(), Color(1.0, 0.86, 0.52), 0.24, 4.0)
		return
	if id == "array":
		# R29 符剑：在身前布一个符阵，阵不动，符自己按扇形飞出去。
		# 与剑（一条直线）/ 枪（三段推进）/ 双刀（原地一圈）区分：这是唯一「持续输出」的绝招。
		var origin := global_position + Vector2(float(dir) * 44.0, -34.0)
		var spread := -0.22 + 0.055 * float(i)
		talisman_shot.emit(origin, Vector2(float(dir), spread), dmg)
		if i == 0:
			Game.add_shake(11.0)
			SFX.play("boss", 1.52, -7.0)
			if _fx:
				_fx.ring(origin, 8.0, 104.0, Color(0.86, 0.74, 1.0), 0.40, 4.0)
				_fx.burst(origin, 14, Color(0.90, 0.80, 1.0), 1.0)
		else:
			SFX.play("slash", 1.55, -11.0)
			if _fx:
				_fx.ring(origin, 2.0, 26.0, Color(0.86, 0.74, 1.0), 0.14, 2.0)
		return
	# 剑 / 枪：矩形刀路
	var ln := float(_ult_cfg.get("len", 480.0))
	var th := float(_ult_cfg.get("thick", 76.0))
	var step := ln * 0.85 if id == "lance" else 0.0
	var c := global_position + Vector2(float(dir) * (40.0 + ln * 0.5 + step * float(i)), -10.0)
	ult_strike.emit(c, Vector2(ln, th), dir, dmg)
	if id == "lance":
		# 枪：每段往前顶一步，位移就是这把武器的语言
		velocity.x = float(dir) * float(_ult_cfg.get("lunge", 300.0))
		invuln = maxf(invuln, 0.16)
		Game.add_shake(4.0)
		SFX.play("slash", 1.30, -8.0)
	else:
		Game.add_shake(14.0)
		SFX.play("boss", 1.35, -6.0)
	if _fx:
		# 直线刀光与矩形判定同形，玩家看到多长就打多远
		_fx.beam(c, Vector2(ln, th * 1.7), dir, Color(1.0, 0.90, 0.58), 0.30)
		_fx.burst(c + Vector2(float(dir) * ln * 0.32, 0.0), 12, Color(1.0, 0.92, 0.66), 1.1)


func is_heavy_active() -> bool:
	return hv == 2


## R18：凝罡·开山 对护体罡气的压制（占敌方上限的比例）—— 3 下逼出「道心失守」
## 精英「剑修傀儡」罡气 120、平砍只推得动一点点，就是靠这一条破的
const HEAVY_POSTURE_FRAC := 0.34


func is_charging() -> bool:
	return hv == 1


func charge_frac() -> float:
	return clampf(charge, 0.0, 1.0)


## 凝罡·开山的刀锋判定（剑气纵横走 ult_burst 信号，这里返回空）
func heavy_rect() -> Rect2:
	if hv != 2 or hv_level >= 2:
		return Rect2()
	var w := 152.0 * (1.18 if has_relic("reach") else 1.0) * WeaponScript.reach_mul(weapon)
	var x := global_position.x + 8.0
	if facing < 0:
		x = global_position.x - 8.0 - w
	return Rect2(x, global_position.y - 92.0, w, 136.0)


func heavy_damage() -> int:
	return ULT_DMG if hv_level >= 2 else HEAVY_DMG


## 当前攻速倍率（ATK_SPD_MIN ~ ATK_SPD_MAX）
func atk_speed() -> float:
	# R33b 快剑：抬「顶」不抬「底」—— 起手依旧慢，只是连打能爬得更高
	var cap := (ATK_SPD_MAX + (0.12 if has_relic("wind") else 0.0)) \
		* MeridianScript.atk_cap_mul(mer)
	return lerpf(ATK_SPD_MIN, cap, clampf(heat, 0.0, 1.0)) * WeaponScript.speed_mul(weapon)


func heat_frac() -> float:
	return clampf(heat, 0.0, 1.0)


## 当前段位的三段时长（抬刀 / 判定 / 收刀），已按攻速缩放
func _stage_t() -> Vector3:
	var sd := _stage_data()
	# R31 快铭：出招速度 +5%（只缩段位时长，不动 atk_speed 的成长与 HUD 读数）
	var sp := atk_speed() * inscribe_tempo_mul()
	return Vector3(float(sd["wind"]) / sp, float(sd["act"]) / sp, float(sd["rec"]) / sp)


# ---------------------------------------------------------------- R12 连招模组
## 当前武器的段位表（weapons.gd 里每把武器各一套）
func combo_len() -> int:
	var n := WeaponScript.combo_len(weapon)
	return n if n > 0 else STAGES.size()


## 当前段位的数据（拿不到武器表时退回旧 STAGES）
func _stage_data() -> Dictionary:
	var sd := WeaponScript.stage_of(weapon, maxi(stage, 1))
	if sd.is_empty():
		return STAGES[clampi(stage - 1, 0, STAGES.size() - 1)]
	return sd


## 当前段的动作标签：slash 斩击 / thrust 突刺 / spin 回旋
func attack_tag() -> String:
	if stage <= 0:
		return WeaponScript.TAG_SLASH
	return str(_stage_data().get("tag", WeaponScript.TAG_SLASH))


## 当前段的护体罡气压制（占敌方护体罡气上限的比例）。命中时由 main 换算成绝对值
func attack_posture_frac() -> float:
	if stage <= 0:
		return 0.0
	var v := float(_stage_data().get("posture", 0.0))
	if attack_tag() == WeaponScript.TAG_SPIN and has_relic("twist"):
		v *= 1.45
	# R13 剑修（刃位装满）：全段压制再 +20%
	if slot_full("blade"):
		v *= 1.2
	# R31 压铭：架势压制 +10%
	return v * inscribe_posture_mul()


## R12 取消窗口：收刀进行到 cancel 比例后，本段后摇可被闪避 / 格挡打断
func can_cancel() -> bool:
	# R30 追风：刚取消过就锁 0.5 秒，不能连着取消刷首段伤害
	if _no_cancel_t > 0.0:
		return false
	if atk != ATK_RECOVER or stage <= 0:
		return false
	var tt := _stage_t()
	var ct := float(_stage_data().get("cancel", 1.0))
	if attack_tag() == WeaponScript.TAG_THRUST and has_relic("stake"):
		ct *= 0.70
	# R16 鞘中藏锋（刃位满 + 壁位有剑鞘）：取消窗口再提前 15%
	if has_mutation("blade"):
		ct *= 0.85
	# R31 疾铭：取消窗口提前 5%
	ct *= inscribe_cancel_mul()
	# R33a 剑锋：经脉再提前一档
	ct *= MeridianScript.cancel_mul(mer)
	return atk_t >= tt.z * ct


## 主动打断当前段（取消后摇）。不算「停手」，所以不给悟道·剑意交锋资格
func _cancel_attack() -> void:
	atk = ATK_NONE
	atk_t = 0.0
	stage = 0
	queued = false
	hit_targets.clear()
	_atk_end_t = _t
	# R30 追风：取消成功 → 下一刀首段 +2；代价是这 0.5 秒内不许再取消
	if has_relic("zhuifeng"):
		_after_cancel_t = 0.5
		_no_cancel_t = 0.5


## 长枪自动追击用：前方有没有能打的敌人（只给前冲加力，不做索敌转向）
func _has_target_ahead(max_dx: float) -> bool:
	if not enemy_provider.is_valid():
		return false
	var list = enemy_provider.call()
	if list == null:
		return false
	for e in list:
		if e == null or not is_instance_valid(e) or bool(e.dead):
			continue
		var dx: float = e.global_position.x - global_position.x
		if signf(dx) == float(facing) and absf(dx) <= max_dx:
			return true
	return false


func _post_move(was_floor: bool, vy_before: float) -> void:
	if not was_floor and is_on_floor() and vy_before > 280.0:
		SFX.play_rand("land", 0.88, 1.06, -11.0)
		if _fx:
			_fx.dust(global_position + Vector2(0, 22), 6)


func _update_wall(was_floor: bool, ix: float, busy: bool) -> void:
	on_wall_state = false
	wall_dir = 0
	if was_floor or busy or wall_lock > 0.0:
		return
	if not is_on_wall():
		return
	var n := get_wall_normal()
	if n.x < -0.5:
		wall_dir = 1
	elif n.x > 0.5:
		wall_dir = -1
	else:
		return
	if ix * float(wall_dir) <= 0.3:
		return
	on_wall_state = true


## 攀爬翻越：头顶上方有立足点时直接翻上岩壁顶端
func _try_mantle() -> bool:
	if _col == null:
		return false
	var probe := global_position + Vector2(wall_dir * 26.0, -46.0)
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _col.shape
	params.transform = Transform2D(0.0, probe)
	params.collision_mask = 1
	params.exclude = [get_rid()]
	var hits := get_world_2d().direct_space_state.intersect_shape(params, 1)
	if not hits.is_empty():
		return false
	global_position = probe
	velocity = Vector2(wall_dir * 70.0, -30.0)
	wall_lock = 0.28
	on_wall_state = false
	if _fx:
		_fx.dust(global_position + Vector2(-wall_dir * 10.0, 20.0), 5)
	SFX.play_rand("land", 1.05, 1.2, -12.0)
	return true


func _start_dash(dir: Vector2) -> void:
	if dir.length() > 0.2:
		_dash_dir = dir.normalized()
		if absf(_dash_dir.x) > 0.12:
			facing = 1 if _dash_dir.x > 0.0 else -1
	else:
		_dash_dir = Vector2(float(facing), 0.0)
	dash_t = DASH_TIME
	dash_cd = DASH_CD * MeridianScript.dash_cd_mul(mer)
	atk = ATK_NONE
	atk_t = 0.0
	stage = 0
	queued = false
	_atk_end_t = _t
	focus_active = false
	focus_t = 0.0
	SFX.play_rand("dash", 0.94, 1.08, -6.0)
	if _fx:
		_fx.dust(global_position + Vector2(0, 14), 6)


func _start_attack(was_floor: bool) -> void:
	_start_stage(1, was_floor)


## 起手一段：灵力不够就出不了刀，返回 false
func _start_stage(n: int, was_floor: bool) -> bool:
	var lim := combo_len()
	var idx := clampi(n, 1, lim)
	var sd := _stage_data_of(idx)
	# R29 符剑：远程段吃符力、不吃灵力；近战段反过来。两套资源互不替代。
	if bool(sd.get("ranged", false)):
		if not spend_rune(RUNE_COST):
			if _fx:
				_fx.text(global_position + Vector2(0, -40.0), "符 力 尽", Color(0.86, 0.74, 1.0), 16, 34)
			return false
	else:
		# R31 省铭：出刀灵力消耗 -8%
		var cost := (float(sd.get("stam", STAM_ATK)) * WeaponScript.stam_mul(weapon)
			* inscribe_stam_mul())
		if not spend(cost):
			return false
	_atk_log.append(_t)
	# R30 残心：段数链。第 1 段起手重置为 1，之后每接一段 +1；挨打归零（见 take_hit）
	_chain_stages = 1 if idx == 1 else _chain_stages + 1
	stage = idx
	queued = false
	atk = ATK_WINDUP
	atk_t = 0.0
	hit_targets.clear()
	has_pogo = false
	focus_active = false
	focus_t = 0.0
	if stage == 1:
		# R10：悟道·剑意交锋要求「停手后再出手」—— 连打 / 接段一律不算
		perfect_ready = (_t - _atk_end_t) >= PERFECT_GAP * MeridianScript.perfect_gap_mul(mer)
		atk_down = false
	else:
		perfect_ready = false
		atk_down = false
	# 出刀前冲：一次性推力，越往后的段越猛
	var push := 200.0 + 34.0 * float(stage)
	# R33b 出锋：出刀前冲更远（只加推力，不改段位时长 —— 前冲和攻速是两件事）
	push *= MeridianScript.lunge_mul(mer)
	# R12 长枪自动追击：前方有人时多送一截（降低操作门槛，但只在出刀那一刻给力）
	if weapon == "spear" and _has_target_ahead(SPEAR_LUNGE_RANGE):
		push *= SPEAR_LUNGE_MUL
	velocity.x += float(facing) * push
	velocity.x = clampf(velocity.x, -SPEED * 1.5, SPEED * 1.5)
	return true


## 取某把武器第 n 段的原始数据（不依赖当前 stage，起手时用）
func _stage_data_of(n: int) -> Dictionary:
	var sd := WeaponScript.stage_of(weapon, n)
	if sd.is_empty():
		return STAGES[clampi(n - 1, 0, STAGES.size() - 1)]
	return sd


# ------------------------------------------------------------------ 对外接口
func is_attack_active() -> bool:
	return atk == ATK_ACTIVE


func attack_age() -> float:
	return atk_t


## R12：target_pos 传入目标位置后，长枪会算「距离惩罚」——贴脸时枪杆没杀伤
func attack_damage(target_pos: Variant = null) -> int:
	if stage <= 0:
		return 1
	var d := int(_stage_data()["dmg"])
	d += WeaponScript.dmg_add(weapon)
	# R21：锋刃 / 影锋（镜像副本）可叠加，各 +1
	if has_relic("edge"):
		d += 1
	if has_relic("edge_shadow"):
		d += 1
	if has_set("blade"):
		d += 1
	# 长枪距离惩罚：太近（枪杆区域）打不出伤害
	if weapon == "spear" and target_pos != null:
		var tp: Vector2 = target_pos
		if absf(tp.x - global_position.x) < SPEAR_DEAD_ZONE:
			d -= 1

	# ---- R30 扩容法宝的伤害层（顺序固定，方便对账）
	# 追风：取消收刀后 0.5 秒内再出的这一刀，首段 +2
	if has_relic("zhuifeng") and stage == 1 and _after_cancel_t > 0.0:
		d += 2
	# 血怒：气血低于 30% 时 +2，高于 30% 时 -1
	if has_relic("xuenv"):
		var low := float(hp) < float(max_hp()) * 0.30
		d += 2 if low else -1
	# 阳炎：站在阳界时附加 1 点灼烧（阴界无效）
	if has_relic("yangyan") and in_yang():
		d += 1
	# 残心：连续 3 段不被打断，第 3 段伤害 ×2
	if has_relic("canxin") and stage == 3 and _chain_stages >= 3:
		d *= 2

	# ---- R31 铭刻的伤害层（也放在 maxi 之前，和法宝同一个池子算）
	# 锋铭：首段 +1
	if has_inscribe("edge1") and stage == 1:
		d += 1
	# 终铭：末段 +1
	if has_inscribe("tail1") and stage >= combo_len():
		d += 1
	# 反铭：完美弹反后 1 秒内 +1
	if has_inscribe("parry") and _parry_buff_t > 0.0:
		d += 1

	# ---- R32a 破境丹：10 秒内伤害 +2（代价在 take_hit 里：受伤也 +1）
	if _pojing_t > 0.0:
		d += 2

	d = maxi(1, d)

	# 会心：一次出手滚一次（没有阴眼时暴击率恒为 0，这里等于不做任何事）
	_last_crit = false
	if crit_chance() > 0.0 and randf() < crit_chance():
		_last_crit = true
		d *= CRIT_MULT
	return d


func combo_stage() -> int:
	return stage


func attack_rect() -> Rect2:
	if atk != ATK_ACTIVE:
		return Rect2()
	# R29 符剑远程段：没有刀锋，只有一道飞出去的符
	if _stage_is_ranged():
		return Rect2()
	return _blade_rect()


## 剑意交锋判定用：只要已经出刀（举刀或挥砍）刀锋就存在
## 凝罡·开山 / 剑气纵横不参与剑意交锋，所以这里直接返回空
func clash_rect() -> Rect2:
	if hv != 0:
		return Rect2()
	if atk != ATK_ACTIVE and atk != ATK_WINDUP:
		return Rect2()
	# R29 符剑远程段：符飞出去了，手里没刀锋 —— 也弹不回落幕弹
	if _stage_is_ranged():
		return Rect2()
	return _blade_rect()


func is_swinging() -> bool:
	return atk == ATK_ACTIVE


func _blade_rect() -> Rect2:
	if atk_down:
		return Rect2(global_position.x - 34.0, global_position.y + 8.0, 68.0, 58.0)
	var sd: Dictionary = _stage_data()
	var rk := (1.18 if has_relic("reach") else 1.0) * WeaponScript.reach_mul(weapon) \
		* inscribe_reach_mul()
	# R33b 刀锋：判定范围放大（宽高同比，不给长枪这种长兵器额外开小灶）
	rk *= MeridianScript.blade_reach_mul(mer)
	var w: float = float(sd["w"]) * rk
	var h: float = float(sd["h"]) * minf(rk, 1.2)
	var x := global_position.x + 6.0
	if facing < 0:
		x = global_position.x - 6.0 - w
	return Rect2(x, global_position.y - h * 0.62, w, h)


func hurt_rect() -> Rect2:
	return Rect2(global_position.x - 10.0, global_position.y - 21.0, 20.0, 42.0)


func can_be_hurt() -> bool:
	return invuln <= 0.0 and not dead


func facing_towards(pos: Vector2) -> bool:
	var d := signf(pos.x - global_position.x)
	return d == 0.0 or d == float(facing)


func is_guarding() -> bool:
	return guarding


func guard_age() -> float:
	return guard_t


## 护体罡气交锋（R11）：把「格挡 / 剑意交锋」升级为只狼式双向护体罡气压力
func on_guard() -> void:
	posture += POSTURE_GUARD
	posture_cd = 3.0
	if posture >= posture_max():
		posture = 0
		_enter_broken()


func on_perfect_parry() -> void:
	# 完美弹反：自身护体罡气不涨（零风险高收益）；敌方护体罡气由 main._perform_clash 推动
	pass


func on_hit_taken() -> void:
	posture += POSTURE_HIT
	posture_cd = 3.0
	if posture >= posture_max():
		posture = 0
		_enter_broken()


func is_broken() -> bool:
	return broken_t > 0.0


func _enter_broken() -> void:
	# R30 龟息：道心失守窗口 -50%（代价是罡气自然回落更慢，见 _physics_process）
	var t := BROKEN_TIME * (0.5 if has_relic("guixi") else 1.0)
	posture = 0
	broken_t = t
	stun = t
	guarding = false
	atk = ATK_NONE


## 返回：0=没挡住 1=格挡 2=精准格挡 3=破防
func try_block(from_pos: Vector2) -> int:
	if not guarding:
		return 0
	if not facing_towards(from_pos):
		return 0
	var perfect := guard_t <= perfect_guard_time()
	guard_flash = 1.0
	# 挡刀本身也要花灵力；灵力见底时挡不住 → 直接破防
	if not drain(STAM_GUARD_HIT * (0.4 if perfect else 1.0) * guard_stam_mul()):
		posture = posture_max()
		_enter_broken()
		invuln = maxf(invuln, 0.5)
		velocity = Vector2(-facing * 260.0, -180.0)
		_exhaust()
		return 3
	if perfect:
		posture = maxi(0, posture - POSTURE_PERFECT_GUARD)
		# R33b 真气：精准格挡后罡气「不回落」的时间更长
		posture_cd = 2.0 * MeridianScript.posture_hold_mul(mer)
		velocity.x = -facing * 130.0
		invuln = maxf(invuln, 0.35)
		guard_t = perfect_guard_time() + 0.01
		return 2
	on_guard()                       # 普通格挡：自身护体罡气 +18（满 → 道心失守）
	if is_broken():
		invuln = maxf(invuln, 0.9)
		velocity = Vector2(-facing * 280.0, -240.0)
		return 3
	velocity.x = -facing * 230.0
	invuln = maxf(invuln, 0.4)
	# R33b 铁骨：挡下之后自己的硬直更短，能更早反击
	stun = 0.16 * MeridianScript.guard_stun_mul(mer)
	return 1


## melee: 是不是近战刀锋（R30 反震只对近战生效；弹幕传 false）
func take_hit(from_pos: Vector2, melee: bool = true) -> bool:
	if not can_be_hurt():
		return false
	# R35：护盾层优先抵消一次伤害（玄龟灵兽 / 盾傀儡给的「挡 1 次」）。
	# 完全挡下，不计受伤、不进受击流程；给一点短无敌避免同帧连吃。
	if shield_layers > 0:
		shield_layers -= 1
		invuln = maxf(invuln, 0.25)
		if _fx:
			_fx.text(global_position + Vector2(0, -56.0), "护 盾 挡",
				Color(0.7, 0.92, 1.0), 18, 30)
		SFX.play("clash", 0.9, -8.0)
		return false
	# 格挡：举盾且朝向来袭方向 → 走格挡判定（普通格挡 / 精准格挡 / 破防），不进受击
	if guarding and facing_towards(from_pos):
		var r := try_block(from_pos)
		if r != 0:
			# R30 反震：挡下近战刀锋时反弹 1 点给最近的敌人（挡弹幕不反弹）
			if has_relic("fanzhen") and melee and (r == 1 or r == 2):
				guard_reflect.emit(from_pos)
			# R31 反铭：完美弹反（r == 2）成功 → 开 1 秒伤害窗口
			if r == 2:
				_parry_buff_t = 1.0
			return true
	# 未挡下 → 正常受击：掉 1 血、自身护体罡气 +25、道心失守时被打 ×1.5
	# R30 残心：挨打就断了连段链
	_chain_stages = 0
	hp -= 1
	# R32a 破境丹的代价：窗口内受伤也 +1（先赚后还，破境就是拿命换刀）
	if _pojing_t > 0.0:
		hp -= 1
	if is_broken():
		hp -= 1
	# R28：无伤评分用 —— 一次受击算一次（道心失守挨的双倍血仍算一次）
	if Game != null and is_instance_valid(Game):
		Game.dmg_taken += 1
	invuln = (1.15 + (0.4 if has_relic("guardian") else 0.0) + (0.3 if has_set("wall") else 0.0)) \
		* MeridianScript.hurt_invuln_mul(mer)
	flash = 1.0
	hurt_age = 0.0
	var dir := signf(global_position.x - from_pos.x)
	if dir == 0.0:
		dir = -facing
	velocity = Vector2(dir * 300.0, -330.0)
	stun = 0.34
	atk = ATK_NONE
	atk_t = 0.0
	stage = 0
	queued = false
	guarding = false
	on_hit_taken()
	focus_active = false
	focus_t = 0.0
	Game.hurt_flash = 1.0
	Game.add_shake(12.0)
	Game.hitstop(0.07, 0.04)
	SFX.play("hurt", 1.0, -2.0)
	if _fx:
		_fx.burst(global_position, 16, Color(1.0, 0.35, 0.4), 0.9)
		_fx.ring(global_position, 8.0, 58.0, Color(1.0, 0.4, 0.45), 0.3, 3.0)
	if hp <= 0:
		hp = 0
		die()
	return true


func on_clash(enemy_pos: Vector2) -> void:
	stun = 0.17
	atk = ATK_RECOVER
	atk_t = 0.0
	var dir := signf(global_position.x - enemy_pos.x)
	if dir == 0.0:
		dir = -facing
	velocity = Vector2(dir * 255.0, -165.0)
	invuln = maxf(invuln, 0.4)
	focus_active = false


func register_hit(enemy: Node) -> bool:
	if hit_targets.has(enemy):
		return false
	hit_targets.append(enemy)
	soul = minf(soul + Game.SOUL_PER_HIT * soul_mul(), Game.MAX_SOUL)
	# R12 余音：斩击段额外回道蕴（标签化法宝的示范：法宝读「这一段是什么动作」）
	if attack_tag() == WeaponScript.TAG_SLASH and has_relic("hum"):
		soul = minf(soul + 2.0, Game.MAX_SOUL)
	Game.hit_count += 1
	_heat_idle = 0.0
	if has_relic("blood"):
		_blood_count += 1
		if _blood_count >= 3:
			_blood_count = 0
			if hp < max_hp():
				hp += 1
				if _fx:
					_fx.text(global_position + Vector2(0, -48), "+1", Color(1.0, 0.55, 0.55), 18, 30)
	if atk_down and not has_pogo:
		has_pogo = true
		velocity.y = -440.0
		return true
	return false


func die() -> void:
	if dead:
		return
	# R32a 九转丹：本局第一次致死时自动吞掉一格，改成「重伤」而不是死。
	# 这是唯一的「自动触发」丹药 —— 主动吃没有意义，所以 use_quick 里明确拒绝。
	if not _jiuzhuan_used and _consume_pill("jiuzhuan"):
		_jiuzhuan_used = true
		hp = 2
		invuln = 2.0
		stun = 0.0
		posture = 0
		posture_cd = 0.0
		broken_t = 0.0
		_pojing_t = 0.0
		guarding = false
		Game.add_shake(18.0)
		Game.hitstop(0.2, 0.03)
		SFX.play("heal", 0.9, 2.0)
		if _fx:
			_fx.ring(global_position, 12.0, 180.0, Color(1.0, 0.88, 0.55), 0.7, 6.0)
			_fx.burst(global_position, 34, Color(1.0, 0.9, 0.6), 1.3)
			_fx.text(global_position + Vector2(0, -78.0), "九 转 · 回 魂",
				Color(1.0, 0.9, 0.6), 26, 60)
		return
	dead = true
	atk = ATK_NONE
	stage = 0
	guarding = false
	focus_active = false
	Game.add_shake(16.0)
	Game.hitstop(0.12, 0.02)
	SFX.play("death", 1.0, 0.0)
	if _fx:
		_fx.burst(global_position, 30, Color(0.8, 0.9, 1.0), 1.1)
		_fx.ring(global_position, 10.0, 110.0, Color(0.9, 0.95, 1.0), 0.5, 4.0)
	died.emit()


func respawn(pos: Vector2) -> void:
	global_position = Vector2(
		clampf(pos.x, SpaceScript.ROOM_X0 + 14.0, SpaceScript.ROOM_X1 - 14.0),
		clampf(pos.y, SpaceScript.FLOOR_FAR_Y + 10.0, SpaceScript.FLOOR_NEAR_Y - 4.0))
	velocity = Vector2.ZERO
	depth = SpaceScript.depth_of(global_position.y)
	dead = false
	hp = max_hp()
	invuln = 1.0
	stun = 0.0
	atk = ATK_NONE
	atk_t = 0.0
	stage = 0
	queued = false
	guarding = false
	posture = 0
	posture_cd = 0.0
	broken_t = 0.0
	on_wall_state = false
	wall_dir = 0
	wall_lock = 0.0
	jumps_left = 2
	focus_active = false
	focus_t = 0.0
	stamina = max_stamina()
	exhausted = false
	_stam_wait = 0.0
	_exh_t = 0.0
	_exh_cd = 0.0
	rune_power = rune_max()   # R29：换房 / 复活回满符力
	# R32a：丹药留着（局内资源），但冷却与破境窗口随复活清掉
	_quick_cd = 0.0
	_pojing_t = 0.0
	heat = 0.0
	_atk_log.clear()
	_heat_idle = 0.0
	hurt_age = 0.0
	hv = 0
	hv_t = 0.0
	hv_level = 0
	charge = 0.0
	_ult_done = false
	flash = 0.0
	_trail.clear()
	z_index = SpaceScript.z_order(depth)
	perfect_ready = true
	_atk_end_t = -99.0


# ------------------------------------------------------------------ 绘制
func _nail_angle() -> float:
	if atk_down:
		return 84.0
	var tt := _stage_t()
	match atk:
		ATK_WINDUP:
			if stage == 2:
				return 78.0
			if stage == 3:
				return -100.0
			return -74.0
		ATK_ACTIVE:
			var p := clampf(atk_t / tt.y, 0.0, 1.0)
			if stage == 2:
				return lerpf(78.0, -66.0, ease(p, 0.32))
			if stage == 3:
				return lerpf(-100.0, 260.0, ease(p, 0.22))
			return lerpf(-74.0, 60.0, ease(p, 0.32))
		ATK_RECOVER:
			var p := clampf(atk_t / tt.z, 0.0, 1.0)
			if stage == 3:
				return 260.0
			return lerpf(60.0, 0.0, p)
	return 0.0


func _draw() -> void:
	if dead:
		return
	# 2.5D：整只角色按深度上移 + 缩放（原点在脚底，所以影子会跟着一起走）
	SpaceScript.apply_draw(self, depth)

	var bob := 0.0
	if absf(velocity.x) > 25.0 or absf(velocity.y) > 25.0:
		bob = sin(_t * 17.0) * 1.5
	var o := Vector2(0, bob)
	var dark := Color(0.055, 0.072, 0.098)
	var rim := Color(0.30, 0.52, 0.72, 0.9)

	# 柔光，让主角从暗处浮出来（多层圆模拟径向渐变）
	for i in range(6, 0, -1):
		draw_circle(o + Vector2(0, -8), 8.0 + i * 6.0, Color(0.45, 0.72, 1.0, 0.009))

	# 2.5D：脚下的接地阴影（越靠里越淡越小）
	_shadow(Vector2(0, 3.0), 19.0 * SpaceScript.scale_of(depth), 5.5 * SpaceScript.scale_of(depth),
		SpaceScript.shadow_alpha(depth))

	# 蓄力 / 剑气纵横
	if hv == 1:
		var cc := charge_frac()
		var ccol := Color(1.0, 0.72, 0.35) if hv_level < 2 else Color(1.0, 0.9, 0.55)
		draw_arc(o, 30.0, -PI * 0.5, -PI * 0.5 + TAU * cc, 40, ccol, 3.0, true)
		draw_circle(o + Vector2(0, -8), 9.0 + 26.0 * cc, Color(ccol.r, ccol.g, ccol.b, 0.08 + 0.16 * cc))
		if hv_level >= 2:
			draw_arc(o, 41.0, 0.0, TAU, 40, Color(1.0, 0.95, 0.7, 0.45 + 0.3 * sin(_t * 18.0)), 2.0, true)
	elif hv == 2:
		var hp2 := clampf(hv_t / (0.34 if hv_level == 1 else 0.62), 0.0, 1.0)
		if hv_level == 1:
			_draw_band(o, -100.0, 92.0, 96.0, 40.0, Color(1.0, 0.85, 0.45, (1.0 - hp2) * 0.8))
		else:
			draw_circle(o, ult_radius() * (0.45 + 0.55 * hp2), Color(1.0, 0.88, 0.5, (1.0 - hp2) * 0.22))
			draw_arc(o, ult_radius() * (0.55 + 0.45 * hp2), 0.0, TAU, 48,
				Color(1.0, 0.9, 0.6, (1.0 - hp2) * 0.85), 4.0, true)

	# 冲刺残影
	for i in _trail.size():
		var tp: Vector2 = _trail[i] - global_position
		var a := 0.10 * (float(i + 1) / _trail.size())
		_draw_body(tp + o, Color(0.45, 0.75, 0.95, a), Color(0.5, 0.8, 1.0, a), false)

	# 出刀残影：挥砍 / 凝罡·开山 / 剑气纵横时留两层淡影，强化打击的「甩出去」感
	var ghost := 0
	if atk == ATK_ACTIVE:
		ghost = 2
	elif hv == 2:
		ghost = 2
	for i in ghost:
		var gx := -facing * (7.0 + 10.0 * float(i))
		var ga := (0.17 if atk == ATK_ACTIVE else 0.22) * (1.0 - 0.45 * float(i))
		_draw_body(o + Vector2(gx, 0), Color(0.55, 0.8, 1.0, ga),
			Color(0.62, 0.86, 1.0, ga), false)

	# 二段跳：背后的双翼残光
	if _air_fx > 0.0:
		var k: float = _air_fx / 0.34
		for side in [-1.0, 1.0]:
			var w := PackedVector2Array([
				o + Vector2(0, -6),
				o + Vector2(side * 26.0, -22.0 - 10.0 * (1.0 - k)),
				o + Vector2(side * 20.0, 4.0),
			])
			draw_colored_polygon(w, Color(0.75, 0.93, 1.0, 0.28 * k))

	# 聚集光环
	if focus_active:
		var p := clampf(focus_t / FOCUS_TIME, 0.0, 1.0)
		draw_circle(o, 22.0 + p * 16.0, Color(0.55, 0.9, 1.0, 0.10 + 0.12 * p))
		draw_arc(o, 26.0 + p * 20.0, -PI * 0.5, -PI * 0.5 + TAU * p, 32, Color(0.8, 0.97, 1.0, 0.85), 2.5, true)

	_draw_body(o, dark, rim, true)

	# 面具
	var head := o + Vector2(0, -14.5)
	var white := Color(0.93, 0.95, 0.98)
	draw_circle(head, 11.0, white)
	var horn_l := PackedVector2Array([
		head + Vector2(-2.6, -8.6), head + Vector2(-11.2, -19.6),
		head + Vector2(-15.2, -21.6), head + Vector2(-9.2, -5.4),
	])
	var horn_r := PackedVector2Array([
		head + Vector2(2.6, -8.6), head + Vector2(11.2, -19.6),
		head + Vector2(15.2, -21.6), head + Vector2(9.2, -5.4),
	])
	draw_colored_polygon(horn_l, white)
	draw_colored_polygon(horn_r, white)
	var eye := Color(0.04, 0.06, 0.09)
	draw_circle(head + Vector2(-3.9, 0.8), 2.7, eye)
	draw_circle(head + Vector2(3.9, 0.8), 2.7, eye)

	# 攀爬时贴在墙上的手
	if on_wall_state:
		draw_circle(o + Vector2(wall_dir * 9.0, -16.0), 2.6, Color(0.85, 0.9, 0.96))
		draw_circle(o + Vector2(wall_dir * 8.0, 2.0), 2.4, Color(0.75, 0.82, 0.9))

	# 格挡：竖直举刀 + 前方护盾弧
	if guarding:
		var gt := o + Vector2(facing * 13.0, -2.0)
		draw_line(gt + Vector2(0, -26), gt + Vector2(0, 24), Color(0.55, 0.85, 1.0, 0.12), 12.0, true)
		draw_colored_polygon(PackedVector2Array([
			gt + Vector2(-2.2, -26), gt + Vector2(2.2, -26),
			gt + Vector2(1.4, 24), gt + Vector2(-1.4, 24),
		]), Color(0.82, 0.88, 0.95))
		draw_line(gt + Vector2(-4, -20), gt + Vector2(4, -20), Color(0.42, 0.50, 0.60), 2.4)
		var ca := 0.0 if facing > 0 else PI
		var pulse := 0.30 + 0.18 * sin(_t * 9.0) + guard_flash * 0.5
		draw_arc(o + Vector2(facing * 4.0, -4.0), 25.0, ca - 0.95, ca + 0.95, 20,
			Color(0.62, 0.88, 1.0, pulse), 3.0, true)

	# 武器（格挡时已经画过竖刀）
	if not guarding:
		var hand := o + Vector2(facing * 4.0, -2.0)
		var a := deg_to_rad(_nail_angle())
		var dirv := Vector2(facing * cos(a), sin(a)).normalized()
		var perp := Vector2(-dirv.y, dirv.x)
		match weapon:
			"spear":
				_draw_spear(hand, dirv, perp)
			"dual":
				_draw_dual(hand, dirv, perp)
			"rune":
				_draw_rune(hand, dirv, perp)
			_:
				_draw_sword(hand, dirv, perp)

	# 刀光
	if atk == ATK_ACTIVE:
		var tt := _stage_t()
		var p := clampf(atk_t / tt.y, 0.0, 1.0)
		var alpha := (1.0 - p * 0.72) * 0.85
		var col := Color(0.85, 0.96, 1.0, alpha)
		if stage == 3:
			col = Color(1.0, 0.93, 0.72, alpha)
		# R29 符剑远程段：手里不甩刀光，改成一枚符在指尖亮一下（符已经飞出去了）
		if _stage_is_ranged():
			var rc := Color(0.86, 0.74, 1.0, alpha)
			var gp := o + Vector2(float(facing) * 26.0, -14.0)
			var rr := Rect2(gp.x - 5.0, gp.y - 7.0, 10.0, 14.0)
			draw_rect(rr, Color(rc.r, rc.g, rc.b, alpha * 0.55))
			draw_rect(rr, rc, false, 1.2)
			draw_line(rr.position + Vector2(2.0, 4.0), rr.position + Vector2(8.0, 4.0), rc, 1.0)
			draw_line(rr.position + Vector2(5.0, 2.0), rr.position + Vector2(5.0, 10.0), rc, 1.0)
			draw_circle(gp, 13.0 * (1.0 - p) + 3.0, Color(rc.r, rc.g, rc.b, alpha * 0.30))
		elif atk_down:
			_draw_band(o + Vector2(0, 6), 30.0, 150.0, 52.0, 26.0, col)
		elif stage == 2:
			_draw_band(o, 84.0, _nail_angle(), 60.0, 28.0, col)
		elif stage == 3:
			_draw_band(o, -100.0, _nail_angle(), 68.0, 24.0, col)
			draw_arc(o, 68.0, 0.0, TAU, 40, Color(1.0, 0.93, 0.7, alpha * 0.35), 3.0, true)
		else:
			_draw_band(o, -80.0, _nail_angle(), 56.0, 26.0, col)


## R29 符剑：窄剑 + 剑身五张符。符按剩余符力点亮 —— 不看 HUD 也知道还能打几发。
func _draw_rune(hand: Vector2, dirv: Vector2, perp: Vector2) -> void:
	var tip := hand + dirv * 42.0
	var pp := perp * 2.0
	var rc := Color(0.86, 0.74, 1.0)
	draw_line(hand, tip, Color(0.86, 0.74, 1.0, 0.10), 11.0, true)
	draw_colored_polygon(PackedVector2Array([
		hand + pp, tip + pp * 0.28, tip - pp * 0.28, hand - pp,
	]), Color(0.87, 0.90, 0.96))
	draw_line(tip + pp * 0.28, tip - pp * 0.28, Color(0.97, 0.99, 1.0), 1.8)
	draw_line(hand - pp * 3.0, hand + pp * 3.0, Color(0.44, 0.36, 0.54), 2.4)
	var slots := int(RUNE_MAX)
	for i in slots:
		var c := hand.lerp(tip, 0.26 + 0.155 * float(i))
		var lit := rune_power >= float(i) + 0.999
		var col := rc if lit else Color(0.52, 0.52, 0.60)
		var a := 0.85 if lit else 0.40
		draw_rect(Rect2(c.x - 1.9, c.y - 3.0, 3.8, 6.0), Color(col.r, col.g, col.b, a))
		if lit:
			draw_line(c + Vector2(0, -1.5), c + Vector2(0, 1.5), Color(1, 1, 1, 0.85), 1.0)


func _draw_sword(hand: Vector2, dirv: Vector2, perp: Vector2) -> void:
	var tip := hand + dirv * 40.0
	var pp := perp * 2.1
	draw_line(hand, tip, Color(0.55, 0.85, 1.0, 0.10), 10.0, true)
	draw_colored_polygon(PackedVector2Array([
		hand + pp, tip + pp * 0.30, tip - pp * 0.30, hand - pp,
	]), Color(0.80, 0.86, 0.93))
	draw_line(tip + pp * 0.30, tip - pp * 0.30, Color(0.95, 0.99, 1.0), 2.0)
	draw_line(hand - pp * 3.2, hand + pp * 3.2, Color(0.42, 0.50, 0.60), 2.4)


## 长枪：木杆 + 窄刃 + 红缨
func _draw_spear(hand: Vector2, dirv: Vector2, perp: Vector2) -> void:
	var butt := hand - dirv * 18.0
	var neck := hand + dirv * 50.0
	var tip := hand + dirv * 64.0
	var pp := perp * 1.7
	draw_line(hand, neck, Color(0.55, 0.85, 1.0, 0.08), 9.0, true)
	draw_line(butt, neck, Color(0.40, 0.29, 0.20), 3.4, true)
	draw_line(butt, neck, Color(0.66, 0.49, 0.32, 0.55), 1.2, true)
	draw_colored_polygon(PackedVector2Array([
		neck + pp * 2.0, tip, neck - pp * 2.0, neck - pp * 0.6,
	]), Color(0.87, 0.91, 0.97))
	draw_line(neck + pp * 2.0, tip, Color(0.99, 1.0, 1.0), 1.4)
	var sway := sin(_t * 13.0) * 2.2
	draw_colored_polygon(PackedVector2Array([
		neck - dirv * 2.0 + pp * 1.4,
		neck - dirv * 12.0 + perp * (5.0 + sway),
		neck - dirv * 15.0 - perp * 3.2,
	]), Color(0.86, 0.28, 0.26, 0.85))


## 双刀：主手 + 反手两把短刃
func _draw_dual(hand: Vector2, dirv: Vector2, perp: Vector2) -> void:
	var off := hand - dirv * 5.0 - perp * 5.5
	_short_blade(hand, dirv, perp, 30.0, Color(0.88, 0.92, 0.98))
	_short_blade(off, (dirv + perp * 0.40).normalized(), perp, 25.0, Color(0.72, 0.80, 0.90))


func _short_blade(hand: Vector2, dirv: Vector2, perp: Vector2, len: float, col: Color) -> void:
	var tip := hand + dirv * len
	var pp := perp * 1.8
	draw_line(hand, tip, Color(0.55, 0.85, 1.0, 0.07), 8.0, true)
	draw_colored_polygon(PackedVector2Array([
		hand + pp, tip + pp * 0.35, tip - pp * 0.35, hand - pp,
	]), col)
	draw_line(tip + pp * 0.35, tip - pp * 0.35, Color(0.97, 0.99, 1.0), 1.6)
	draw_line(hand - pp * 2.8, hand + pp * 2.8, Color(0.42, 0.50, 0.60), 2.0)


func _draw_body(o: Vector2, body: Color, rim: Color, detail: bool) -> void:
	var back := -facing
	var sway := sin(_t * 9.0) * 1.8
	var cape := PackedVector2Array([
		o + Vector2(back * 5.0, -13.0),
		o + Vector2(back * 13.0, -3.0),
		o + Vector2(back * (17.0 + sway), 11.0),
		o + Vector2(back * (11.0 + sway), 22.0),
		o + Vector2(back * 1.0, 19.0),
	])
	draw_colored_polygon(cape, body.darkened(0.25))

	var cloak := PackedVector2Array([
		o + Vector2(-8.5, -16.0), o + Vector2(-13.5, -3.0), o + Vector2(-12.5, 9.0),
		o + Vector2(-8.5, 21.0), o + Vector2(0.0, 23.0), o + Vector2(8.5, 21.0),
		o + Vector2(12.5, 9.0), o + Vector2(13.5, -3.0), o + Vector2(8.5, -16.0),
	])
	draw_colored_polygon(cloak, body)
	if detail:
		var closed := cloak.duplicate()
		closed.append(cloak[0])
		draw_polyline(closed, rim, 1.4, true)
		draw_line(o + Vector2(-4, 18), o + Vector2(-3, 23), Color(0.02, 0.03, 0.04), 1.6)
		draw_line(o + Vector2(4, 18), o + Vector2(3, 23), Color(0.02, 0.03, 0.04), 1.6)
		draw_circle(o + Vector2(0, -1), 2.2, Color(0.45, 0.8, 1.0, 0.35))


func _shadow(center: Vector2, rx: float, ry: float, a: float) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var ang := TAU * float(i) / 20.0
		pts.append(center + Vector2(cos(ang) * rx, sin(ang) * ry))
	draw_colored_polygon(pts, Color(0.0, 0.0, 0.0, a))


func _draw_band(center: Vector2, a0_deg: float, a1_deg: float, r_out: float, r_in: float, col: Color) -> void:
	var steps := 16
	var pts := PackedVector2Array()
	for i in range(steps + 1):
		var ang: float = deg_to_rad(lerpf(a0_deg, a1_deg, float(i) / steps))
		pts.append(center + Vector2(facing * cos(ang), sin(ang)) * r_out)
	for i in range(steps, -1, -1):
		var ang: float = deg_to_rad(lerpf(a0_deg, a1_deg, float(i) / steps))
		pts.append(center + Vector2(facing * cos(ang), sin(ang)) * r_in)
	if pts.size() >= 3:
		draw_colored_polygon(pts, col)
