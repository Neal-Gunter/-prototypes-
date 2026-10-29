extends CharacterBody2D
## 敌人：0=道兵傀儡 1=阴魂（飞行） 2=镇钟力士（Boss） 3=剑冢守（三阶段 Boss）
##       4=前世身（三阶段 Boss，体型小、招式多） 5=魔渊分身
##       6=尸解仙·无相（关卡三 Boss，重甲慢速） 7=域外天魔（关卡四 最终 Boss）
##       14=无相·心魔（关卡五 Boss，复制玩家的武器与法宝）

signal killed(enemy)
signal fired(pos: Vector2, dir: Vector2, speed: float)
signal parried(enemy)
signal phase_changed(enemy, phase)
signal aoe(pos: Vector2, radius: float)
signal summon(pos: Vector2, count: int)
## R22 完全体镜像：无相·心魔把 R18b 三武器绝招反推成敌人版（判定与玩家的同形）
signal mirror_strike(pos: Vector2, size: Vector2, dir: int)
signal mirror_burst(pos: Vector2, radius: float)
## R37 轮回使：现场召 n 个「旧影」（由 main 按玩家最近的轨迹生成）
signal echo_call(pos: Vector2, count: int)
## R38：道心失守窗口自然结束、敌人还活着 —— 你没下手，记一次「放走」
signal spared(enemy)

enum { IDLE, CHASE, WINDUP, ATTACK, RECOVER, STAGGER, DEAD, DEFEND, DODGE, RANGED, PHASE, BLINK, AOE, FUSE, MIRROR_ULT }

const KIND_SENTINEL := 0
const KIND_FLYER := 1
const KIND_BOSS := 2
const KIND_BOSS2 := 3
const KIND_BOSS3 := 4
const KIND_CLONE := 5
const KIND_BOSS4 := 6   # 尸解仙·无相
const KIND_BOSS5 := 7   # 域外天魔（最终）
# ---------------------------------------------------------------- R18 精英
## 精英不新增机制，只把现有机制换个问法：
##   剑修傀儡→破防（罡气极厚，得用凝罡·开山）/ 符修→入阴（符从阳界来）
##   丹修→处决（自爆前 2s 可处决）/ 怨灵→阴阳界（只在阴界可见）
##   纸人→AOE（分身多但血薄）/ 尸傀→读招（预判出刀，得用取消窗口骗）
const KIND_JIANXIU := 8    # 剑修傀儡（阳）
const KIND_FUXIU := 9      # 符修（阳）
const KIND_DANXIU := 10    # 丹修（阳）
const KIND_YUANLING := 11  # 怨灵（阴，锁在阴界）
const KIND_ZHIREN := 12    # 纸人（两界通，分身多）
const KIND_SHIJUI := 13    # 尸傀（阳，读招）

## R19b：第 5 关「心魔境」的关底 —— 镜子里的你。
## 它不写死招式，而是**读玩家的武器**决定射程 / 出招速度 / 伤害，
## 二阶段再「复制法宝」：借法宝的护盾与飞剑。三阶段的「三武器同用」留给 R19c。
const KIND_BOSS6 := 14     # 无相·心魔（复制玩家的武器与法宝）
const KIND_BOSS7 := 15     # 符祖（R36：远程，画符封路）
const KIND_BOSS8 := 16     # 轮回使（R37：近身压迫 + 召「旧影」复现你的走位）
const KIND_BOSS9 := 17     # 钟楼旧主（R39：隐藏 Boss · 慢而重的体修，教完美弹反）
const ELITE_NAMES := {
	KIND_JIANXIU: "剑 修 傀 儡",
	KIND_FUXIU: "符 修",
	KIND_DANXIU: "丹 修",
	KIND_YUANLING: "怨 灵",
	KIND_ZHIREN: "纸 人",
	KIND_SHIJUI: "尸 傀",
}

## 精英护体罡气上限（覆盖默认的 max(55, hp*8)）
const ELITE_POSTURE := {
	KIND_JIANXIU: 120.0,
	KIND_FUXIU: 40.0,
	KIND_DANXIU: 60.0,
	KIND_YUANLING: 30.0,
	KIND_ZHIREN: 10.0,
	KIND_SHIJUI: 100.0,
}

# ---------------------------------------------------------------- R18 行为变奏
## 同一 kind 换「性格」，不改 kind、不改刷怪表。同一只敌人最多挂 1 个变奏。
const VAR_NONE := 0
const VAR_SHIELD := 1   # 护盾型：额外 30 点护盾，连续攻击打破
const VAR_SUMMON := 2   # 召唤型：每 8 秒召一只纸人
const VAR_BOMB := 3     # 自爆型：近身 2 秒后自爆（可处决）
const VAR_READ := 4     # 读招型：玩家出刀就提前格挡
const VAR_RAGE := 5     # 狂暴型：血量 < 30% 攻速 ×1.5

const VAR_NAMES := {
	VAR_SHIELD: "护 盾",
	VAR_SUMMON: "召 唤",
	VAR_BOMB: "自 爆",
	VAR_READ: "读 招",
	VAR_RAGE: "狂 暴",
}

const ELITE_REPLACE_CHANCE := 0.15   # 普通房间 15% 换一只精英
const SHIELD_AMOUNT := 30.0          # 护盾总点数
const SHIELD_HIT_COST := 10.0        # 每点伤害削掉的护盾（轻击 3 下 / 重击 1 下）
const SHIELD_REGEN := 4.0            # 多久没挨打，护盾回满
const FUSE_TIME := 2.0               # 自爆倒计时 = 可处决窗口
const YIN_DEPTH := 0.88              # 怨灵锁在阴界（阳界打不到，得入阴）
const ELITE_SUMMON_CD := 8.0         # 召唤型 / 纸人 的召唤间隔

const SpaceScript := preload("res://scripts/space.gd")
const WeaponScript := preload("res://scripts/weapons.gd")

const PARRY_CHANCE := 0.5
## R12：护体罡气会回落 —— 让「连招压制」变成需要维持的东西，而不是必然累积
const POSTURE_HOLD := 2.2    # 多久没被打才开始回落
const POSTURE_DECAY := 0.16  # 每秒回落 16% 的护体罡气上限
const CLONE_LIFE := 20.0      # 分身存在 20 秒
const AOE_RADIUS := 250.0     # 范围攻击半径（跳起来或冲刺出圈都能躲）
const NO_HURT_TRIGGER := 10.0 # 玩家 10 秒没掉血 → 放范围攻击

var kind := KIND_SENTINEL
var hp := 3
var max_hp := 3
var facing := -1
var state := IDLE
var st := 0.0
var atk_age := 0.0
var scale_f := 1.0
var flash := 0.0
var dead := false
var home := Vector2.ZERO
var patrol_range := 140.0
var player: Node = null
var fx: Node = null
var is_boss := false
## R14：记忆回响（上一次轮回的自己）——暗色剪影，轮廓光取玩家当前武器配色
var is_echo := false
var echo_hue := 0.56
## 2.5D：深度 0（贴镜头）~ 1（贴后墙）；杂兵会往玩家那条刀路靠
var depth := 0.55

var windup_t := 0.44
var attack_t := 0.16
var recover_t := 0.5
var attack_range := 118.0
var aggro_range := 430.0
var move_speed := 92.0
var lunge_speed := 250.0
var dmg := 1
var combo := 0
var stagger_t := 0.85

# 硬直度（剑意交锋 / 格挡累积，打满 = 长硬直）
var stagger_max := 90.0
var stagger_meter := 0.0
var _stagger_idle := 0.0
var _stagger_flash := 0.0
var posture := 0.0          # R11 护体罡气（可被处决的「躯干值」）
var max_posture := 100.0
var broken_t := 0.0          # 道心失守窗口（>0 可被处决）
var _posture_idle := 0.0     # R12：距上次涨护体罡气过了多久（超过 POSTURE_HOLD 开始回落）

# 三阶段 Boss
var phase := 1
var phase_max := 1
var berserk := false
var berserk_t := 0.0
var berserk_cd := 0.0
var defend_t := 0.0
var defend_hits := 0
## R10：所有 Boss 都会格挡 —— 这是「下一次可以举盾」的冷却
var _defend_cd := 0.0
var ranged_cd := 0.0
var unblockable := false
var invuln_t := 0.0
var arena := Vector2(-99999.0, 99999.0)

# 前世身专用
var blink_cd := 0.0
var aoe_cd := 0.0
var clone_cd := 0.0
var _queue_skill := ""
var _aoe_t := 0.0
var ghost := false        # 分身：半透明
var clashed := false      # 本次挥砍是否已经拼过刀（悟道·剑意交锋只认第一刀）

## R16 浮空：上挑把敌人挑起来（air_stun > 0 期间不行动、受击加伤、视觉上抬）
var air_stun := 0.0
var _air_lift := 0.0
const AIR_LIFT := 30.0        # 挑起来后整体上抬多少像素
const AIR_LIFT_SPD := 220.0   # 上抬 / 落下的速度
const AIR_HURT_MUL := 1.3     # 浮空时受到的伤害倍率

## R32b 封符：定身（frozen_t > 0 期间完全不动、不推进 AI，但照常吃伤害）
var frozen_t := 0.0

var _life := -1.0         # 分身剩余寿命

# ---------------------------------------------------------------- R18 精英 / 变奏
var variant := VAR_NONE
var shield := 0.0          # 护盾型的护盾值
var _shield_idle := 0.0
var _fuse_t := 0.0         # 自爆倒计时
var _fuse_canceled := false
var _elite_cd := 0.0       # 精英专属技能冷却
var _summon_cd := 0.0      # 召唤型冷却
var _var_cd := 0.0         # 变奏冷却
var _bolt_done := false    # RANGED 状态里「已经放出去了」
var rage_mul := 1.0        # 狂暴型的攻速倍率（1.0 = 正常）
var mini := false          # 纸人分身：血更薄、不放技能

# ---------------------------------------------------------------- R19b 镜像（复制玩家的 Build）
var mirror_weapon := ""    # 复制来的武器 id（""= 不是镜像）
var mirror_relics := 0     # 复制来的法宝数量
var mirror_ult_cd := 0.0   # R22「影·绝招」的冷却（R19b 的借宝走自己的节奏，不复用）
# R26：绝招反制概率 —— 玩家开大的瞬间，二阶段且影·绝招就绪时同步反制（测试可改 1.0）
var counter_chance := 0.45
# R22：绝招多段调度（形状 / 段数 / 间隔全部照抄 WeaponScript.ult_of）
var mult_cfg: Dictionary = {}
var mult_left := 0
var mult_idx := 0
var mult_t := 0.0

var _t := 0.0
var _cd := 0.0
var _death_t := -1.0
var _bob_t := 0.0
var _dive_dir := Vector2.ZERO
var _dodge_dir := 0.0
var _alert := 0.0
var _intent_cd := 0.0
var _trail: Array = []


func setup(k: int, pos: Vector2, p: Node, fx_node: Node) -> void:
	kind = k
	player = p
	fx = fx_node
	home = pos
	global_position = pos
	z_index = 15
	if kind == KIND_SENTINEL:
		hp = 3
		max_hp = 3
		scale_f = 1.0
		windup_t = 0.44
		attack_t = 0.16
		recover_t = 0.5
		attack_range = 118.0
		move_speed = 92.0
		lunge_speed = 250.0
		dmg = 1
	elif kind == KIND_FLYER:
		hp = 2
		max_hp = 2
		scale_f = 0.85
		windup_t = 0.5
		attack_t = 0.42
		recover_t = 0.85
		attack_range = 300.0
		aggro_range = 400.0
		move_speed = 85.0
		lunge_speed = 520.0
		dmg = 1
		z_index = 16
	elif kind == KIND_BOSS2:
		is_boss = true
		hp = 12
		max_hp = 12
		phase = 1
		phase_max = 3
		scale_f = 1.7
		windup_t = 0.36
		attack_t = 0.18
		recover_t = 0.36
		attack_range = 168.0
		aggro_range = 1000.0
		move_speed = 118.0
		lunge_speed = 330.0
		dmg = 2
		stagger_max = 150.0
		z_index = 18
	elif kind == KIND_BOSS3:
		is_boss = true
		hp = 10
		max_hp = 10
		phase = 1
		phase_max = 3
		scale_f = 1.12          # 体型明显比剑冢守小
		windup_t = 0.26
		attack_t = 0.16
		recover_t = 0.30
		attack_range = 136.0
		aggro_range = 1100.0
		move_speed = 152.0
		lunge_speed = 400.0
		dmg = 2
		stagger_max = 120.0
		z_index = 19
	elif kind == KIND_BOSS4:
		# 尸解仙·无相：重甲、慢、伤害高、不远程、防御多
		is_boss = true
		hp = 14
		max_hp = 14
		phase = 1
		phase_max = 2
		scale_f = 1.95
		windup_t = 0.46
		attack_t = 0.22
		recover_t = 0.42
		attack_range = 186.0
		aggro_range = 1000.0
		move_speed = 88.0
		lunge_speed = 300.0
		dmg = 3
		stagger_max = 200.0
		z_index = 18
	elif kind == KIND_BOSS5:
		# 域外天魔：最终 Boss，最快、招式最全
		is_boss = true
		hp = 13
		max_hp = 13
		phase = 1
		phase_max = 3
		scale_f = 1.32
		windup_t = 0.24
		attack_t = 0.15
		recover_t = 0.28
		attack_range = 148.0
		aggro_range = 1300.0
		move_speed = 168.0
		lunge_speed = 430.0
		dmg = 2
		stagger_max = 135.0
		z_index = 20
	elif kind == KIND_CLONE:
		hp = 2
		max_hp = 2
		scale_f = 0.92
		windup_t = 0.34
		attack_t = 0.15
		recover_t = 0.32
		attack_range = 118.0
		aggro_range = 900.0
		move_speed = 168.0
		lunge_speed = 300.0
		dmg = 1
		stagger_max = 55.0
		ghost = true
		_life = CLONE_LIFE
		z_index = 17
	elif kind == KIND_BOSS6:
		# 无相·心魔：**体型与玩家一致**（它就是镜子里的你），数值只是底子，
		# 真正的射程 / 出招速度 / 伤害由 make_mirror() 从玩家的武器抄过来。
		is_boss = true
		hp = 12
		max_hp = 12
		phase = 1
		phase_max = 2
		scale_f = 1.0
		windup_t = 0.28
		attack_t = 0.15
		recover_t = 0.30
		attack_range = 152.0
		aggro_range = 1200.0
		move_speed = 150.0
		lunge_speed = 380.0
		dmg = 2
		stagger_max = 130.0
		z_index = 19
	elif kind == KIND_BOSS7:
		# R36 符祖：**远程 Boss** —— 不进身，站在中距离画符齐射；
		# 玩家压太近就往后退，周期性「画符封路」（地面符爆）。
		is_boss = true
		hp = 16
		max_hp = 16
		phase = 1
		phase_max = 2
		scale_f = 1.42
		windup_t = 0.34
		attack_t = 0.16
		recover_t = 0.42
		attack_range = 132.0      # 近身也能拍一下（被逼到墙角时）
		aggro_range = 1200.0
		move_speed = 118.0
		lunge_speed = 300.0
		dmg = 2
		stagger_max = 150.0
		z_index = 19
	elif kind == KIND_BOSS8:
		# R37 轮回使：**近身压迫型** —— 与上一关的符祖正好相反。
		# 它不远程，只是贴得极紧（比普通 Boss 快），并且每隔几秒召一批「旧影」，
		# 那些影子会沿玩家刚才的轨迹走 —— 所以「一直绕圈」反而会被自己困住。
		is_boss = true
		hp = 18
		max_hp = 18
		phase = 1
		phase_max = 2
		scale_f = 1.34
		windup_t = 0.30
		attack_t = 0.15
		recover_t = 0.34
		attack_range = 150.0
		aggro_range = 1200.0
		move_speed = 172.0       # 全场最快的 Boss：跑不掉的压迫感
		lunge_speed = 430.0
		dmg = 2
		stagger_max = 140.0
		z_index = 19
	elif kind == KIND_BOSS9:
		# R39 钟楼旧主：**隐藏 Boss** —— 全作第一个「招式完全可预测」的 Boss。
		# 他不读招、不瞬移、不远程、不防御，只有一记慢刀；但硬直条 190 砍不动，
		# 所以正解只有一个：**站住，等他抬手，弹**。
		# 前摇 0.62s（见 _windup_now）是刻意拉长的 —— 慢到你看得清，才谈得上「练」。
		is_boss = true
		hp = 20
		max_hp = 20
		phase = 1
		phase_max = 2
		scale_f = 1.55           # 全作最大的体型：一眼看出「这是旧主」
		windup_t = 0.62
		attack_t = 0.16
		recover_t = 0.52         # 收招也慢 —— 弹反后的反击窗口给得很足
		attack_range = 112.0
		aggro_range = 1200.0
		move_speed = 96.0        # 全场最慢的 Boss：他不需要追，是你要上来
		lunge_speed = 340.0
		dmg = 2
		stagger_max = 190.0      # 最高的硬直条：平砍几乎推不动，只能弹
		z_index = 19
	# ------------------------------------------------ R18 精英（都不是 Boss）
	elif kind == KIND_JIANXIU:
		# 剑修傀儡：罡气极厚（120），平砍几乎推不动 → 逼玩家用凝罡·开山
		hp = 8
		max_hp = 8
		scale_f = 1.08
		windup_t = 0.42
		attack_t = 0.16
		recover_t = 0.42
		attack_range = 134.0
		aggro_range = 620.0
		move_speed = 96.0
		lunge_speed = 240.0
		dmg = 2
		stagger_max = 130.0
		z_index = 17
	elif kind == KIND_FUXIU:
		# 符修：血薄、罡气低，但贴符从远处来 → 逼玩家入阴躲
		hp = 5
		max_hp = 5
		scale_f = 0.98
		windup_t = 0.40
		attack_t = 0.16
		recover_t = 0.46
		attack_range = 118.0
		aggro_range = 700.0
		move_speed = 104.0
		lunge_speed = 210.0
		dmg = 1
		stagger_max = 90.0
		z_index = 17
	elif kind == KIND_DANXIU:
		# 丹修：会炼丹回血，血量过半就点炉自爆（2 秒倒计时 = 可处决窗口）
		hp = 6
		max_hp = 6
		scale_f = 1.0
		windup_t = 0.44
		attack_t = 0.18
		recover_t = 0.50
		attack_range = 120.0
		aggro_range = 560.0
		move_speed = 88.0
		lunge_speed = 210.0
		dmg = 2
		stagger_max = 95.0
		z_index = 17
	elif kind == KIND_YUANLING:
		# 怨灵：锁在阴界（YIN_DEPTH），阳界既看不见也打不到
		hp = 4
		max_hp = 4
		scale_f = 0.96
		windup_t = 0.46
		attack_t = 0.18
		recover_t = 0.55
		attack_range = 128.0
		aggro_range = 640.0
		move_speed = 82.0
		lunge_speed = 230.0
		dmg = 2
		stagger_max = 80.0
		ghost = true
		depth = YIN_DEPTH
		z_index = 19
	elif kind == KIND_ZHIREN:
		# 纸人：血 2、罡气 10，会分身 → 教玩家用剑气纵横清场
		hp = 2
		max_hp = 2
		scale_f = 0.86
		windup_t = 0.30
		attack_t = 0.14
		recover_t = 0.34
		attack_range = 110.0
		aggro_range = 660.0
		move_speed = 120.0
		lunge_speed = 260.0
		dmg = 1
		stagger_max = 60.0
		z_index = 16
	elif kind == KIND_SHIJUI:
		# 尸傀：血最厚、会预判出刀与抓取 → 教玩家用取消窗口骗招
		hp = 12
		max_hp = 12
		scale_f = 1.20
		windup_t = 0.50
		attack_t = 0.20
		recover_t = 0.44
		attack_range = 152.0
		aggro_range = 600.0
		move_speed = 84.0
		lunge_speed = 250.0
		dmg = 3
		stagger_max = 150.0
		z_index = 18
	else:
		is_boss = true
		hp = 12
		max_hp = 12
		scale_f = 1.75
		windup_t = 0.38
		attack_t = 0.2
		recover_t = 0.34
		attack_range = 178.0
		aggro_range = 900.0
		move_speed = 110.0
		lunge_speed = 300.0
		dmg = 2
		stagger_max = 130.0
		z_index = 18

	if kind == KIND_SENTINEL:
		stagger_max = 90.0
	elif kind == KIND_FLYER:
		stagger_max = 70.0

	# R11：护体罡气上限随血量缩放（Boss 更高，普通怪给下限保证可处决）
	max_posture = maxf(55.0, float(max_hp) * 8.0)
	# R18：精英的罡气上限是手调的（剑修傀儡 120 / 纸人 10），不吃血量缩放
	if ELITE_POSTURE.has(kind):
		max_posture = float(ELITE_POSTURE[kind])

	# 碰撞
	var cs := CollisionShape2D.new()
	if kind == KIND_FLYER:
		var c := CircleShape2D.new()
		c.radius = 15.0 * scale_f
		cs.shape = c
		collision_mask = 1
	else:
		var cap := CapsuleShape2D.new()
		cap.radius = 13.0 * scale_f
		cap.height = 44.0 * scale_f
		cs.shape = cap
		collision_mask = 1
	collision_layer = 4
	add_child(cs)


## R14：把这只敌人变成「记忆回响」——暗色剪影，轮廓光取玩家武器色
## 保持 is_boss=false（不触发关卡结算），只是更耐打、更有压迫感
func make_echo(hue: float, hp_bonus: int = 6) -> void:
	is_echo = true
	echo_hue = clampf(hue, 0.0, 1.0)
	hp += hp_bonus
	max_hp += hp_bonus
	scale_f *= 1.08
	stagger_max *= 1.25
	max_posture = maxf(55.0, float(max_hp) * 8.0)
	queue_redraw()


## R19b：把这只敌人变成「镜子里的你」—— 外形走记忆回响的暗色剪影，
## 数值**从玩家的武器抄**：射程 / 出招速度 / 伤害各抄一项。
## 这样三把武器在敌人身上也能读出差别（长枪的镜像够得远但慢，双刀的镜像贴脸很快）。
## relics_n = 玩家当前法宝数：每 2 件 +1 血、每件 +6 硬直上限（不抄具体效果，只抄「厚」）
func make_mirror(wid: String, relics_n: int = 0) -> void:
	mirror_weapon = wid
	mirror_relics = maxi(0, relics_n)
	# 暗色剪影 + 武器色的眼与轮廓光（复用 R14 记忆回响的表现）
	var hue: float = float(WeaponScript.by_id(wid).get("hue", 0.56))
	make_echo(hue, 0)
	# 武器三项：射程 / 出招速度 / 伤害
	var rm: float = WeaponScript.reach_mul(wid)
	var sm: float = WeaponScript.speed_mul(wid)
	attack_range = 152.0 * rm
	# 出招速度倍率：>1 更快（windup 更短），<1 更慢
	windup_t = maxf(0.12, windup_t / maxf(0.4, sm))
	recover_t = maxf(0.12, recover_t / maxf(0.4, sm))
	dmg = maxi(1, dmg + WeaponScript.dmg_add(wid))
	# 法宝：只抄「厚」，不抄具体效果
	hp += int(mirror_relics / 2)
	max_hp += int(mirror_relics / 2)
	stagger_max += float(mirror_relics) * 6.0
	max_posture = maxf(max_posture, float(max_hp) * 9.0)
	queue_redraw()


# ---------------------------------------------------------------- R18 精英 / 变奏
## 精英判定：kind >= 8 就是精英（Boss 仍是 2/3/4/6/7，不冲突）
## R19b：KIND_BOSS6=14 的编号落在精英区间里，必须显式排除，否则会被当成精英走 _elite_ai
func is_elite() -> bool:
	# 注意：Boss 的编号（14/15/16）都落在 KIND_JIANXIU(8) 之后的区间里，
	# 所以这里必须**排除整个 Boss 家族**，不能只排 BOSS6。
	# R36 只排了 BOSS6 → 符祖(15) 一直在走 _elite_ai，五连扇形/后退走位全没生效；
	# R37 加轮回使(16) 时才发现。用 is_boss_family() 兜住，以后加 Boss 不必再改这里。
	return kind >= KIND_JIANXIU and not is_boss_family()


func elite_name() -> String:
	return str(ELITE_NAMES.get(kind, ""))


func variant_name() -> String:
	return str(VAR_NAMES.get(variant, ""))


## 给普通小怪挂一个「性格」。精英不挂（精英本身已经有专属机制，避免叠乘失控）
func set_variant(v: int) -> void:
	if v == VAR_NONE or is_elite():
		return
	variant = v
	if v == VAR_SHIELD:
		shield = SHIELD_AMOUNT
	queue_redraw()


## 纸人分身：血更薄、不放技能、也不挂变奏
func make_mini() -> void:
	mini = true
	hp = 1
	max_hp = 1
	scale_f *= 0.82
	max_posture = 6.0
	move_speed *= 1.15
	_elite_cd = 99.0        # 分身不再放技能
	_summon_cd = 99.0
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if flash > 0.0:
		flash = maxf(0.0, flash - delta * 5.0)
	_alert = maxf(0.0, _alert - delta * 1.6)
	if state == DODGE:
		_trail.append(global_position)
		if _trail.size() > 5:
			_trail.pop_front()
	elif not _trail.is_empty():
		_trail.clear()
	# R12：护体罡气回落 —— 停手 2.2 秒后开始掉，逼玩家把连招打完
	_decay_posture(delta)
	var a := 1.0
	if dead:
		_death_t += delta
		a = clampf(1.0 - _death_t / 0.45, 0.0, 1.0)
		if _death_t > 0.5:
			queue_free()
	modulate = Color(1.0 + flash * 2.4, 1.0 - flash * 0.4, 1.0 - flash * 0.45, a)
	if ghost and not dead:
		var ga := 0.52 + 0.14 * sin(_t * 9.0)
		if _life >= 0.0 and _life < 2.5:
			ga *= maxf(0.0, _life / 2.5)
		modulate.a = ga
	queue_redraw()


## 2.5D：把深度往玩家那条刀路上靠 —— 追人 / 出招时几乎对齐，
## 站着待机或被打硬直时保持原深度（这样玩家能靠「里外走位」拉开刀路）。
func _update_depth(delta: float) -> void:
	# R18：怨灵锁在阴界 —— 阳界（z 小）打不到它，玩家必须入阴才够得着
	if kind == KIND_YUANLING:
		depth = move_toward(depth, YIN_DEPTH, 1.2 * delta)
		z_index = SpaceScript.z_order(depth)
		return
	var pz := 0.5
	if player != null and is_instance_valid(player):
		pz = float(player.depth)
	var target := depth
	var sp := 0.85
	if kind == KIND_FLYER:
		target = depth                      # 飞行单位不换道
	elif is_boss_family():
		target = clampf(pz, 0.20, 0.80)     # Boss 体型大，只在中间一段慢慢挪
		sp = 0.45
	elif state == CHASE:
		target = SpaceScript.clamp_z(pz)
		sp = 1.15
	elif state == WINDUP or state == ATTACK:
		target = SpaceScript.clamp_z(pz)
		sp = 1.90                           # 出刀前迅速对齐，保证刀能砍到
	elif state == RECOVER or state == DEFEND:
		target = SpaceScript.clamp_z(pz)
		sp = 0.70
	elif state == IDLE:
		# 待机时如果玩家已经靠近，也慢慢靠过去 —— 否则玩家在别的深度打不到它，会以为卡住
		var near := 320.0
		if player != null and is_instance_valid(player):
			if absf(float(player.global_position.x) - global_position.x) < near:
				target = SpaceScript.clamp_z(pz)
				sp = 0.55
	elif state == STAGGER or state == DODGE:
		target = depth
	if absf(target - depth) > 0.002:
		depth = move_toward(depth, target, sp * delta)
	z_index = SpaceScript.z_order(depth)


func _physics_process(delta: float) -> void:
	if dead:
		return
	st += delta
	_cd = maxf(0.0, _cd - delta)
	_defend_cd = maxf(0.0, _defend_cd - delta)
	mirror_ult_cd = maxf(0.0, mirror_ult_cd - delta)
	invuln_t = maxf(0.0, invuln_t - delta)
	_stagger_flash = maxf(0.0, _stagger_flash - delta * 2.0)
	# R16：浮空计时与上抬插值（挑起时快速上抬，落地时慢一点落回）
	if air_stun > 0.0:
		air_stun = maxf(0.0, air_stun - delta)
		_air_lift = minf(AIR_LIFT, _air_lift + AIR_LIFT_SPD * delta)
	else:
		_air_lift = maxf(0.0, _air_lift - AIR_LIFT_SPD * 0.7 * delta)
	_update_depth(delta)

	# R32b 封符：定身期间不推进任何 AI，只走计时与位移归零（照常吃伤害）
	if frozen_t > 0.0:
		frozen_t = maxf(0.0, frozen_t - delta)
		velocity = Vector2.ZERO
		queue_redraw()
		return

	# 分身寿命
	if _life >= 0.0:
		_life -= delta
		if _life <= 0.0:
			if fx:
				fx.burst(global_position, 12, Color(0.55, 0.75, 1.0), 0.7)
			_die()
			return

	# 硬直度自然衰减
	_stagger_idle = maxf(0.0, _stagger_idle - delta)
	if _stagger_idle <= 0.0 and stagger_meter > 0.0:
		stagger_meter = maxf(0.0, stagger_meter - 13.0 * delta)
	if broken_t > 0.0:
		broken_t = maxf(0.0, broken_t - delta)
		# R38：窗口自己走完而你一直没下手 —— 这一命是放走的（不是打死，也不是处决）
		if broken_t <= 0.0 and not dead:
			spared.emit(self)

	# 狂暴计时（硬直中也走时间）
	if berserk_t > 0.0:
		berserk_t -= delta
		if berserk_t <= 0.0:
			berserk = false
			if fx and kind == KIND_BOSS2:
				fx.text(global_position + Vector2(0, -96.0 * scale_f), "平息", Color(0.72, 0.76, 0.9), 18)

	if state == STAGGER:
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
		if st >= stagger_t:
			_set_state(RECOVER)
		_advance(delta)
		return

	# R18：行为变奏（护盾回满 / 狂暴 / 召唤 / 自爆 / 读招）对所有非 Boss 小怪生效
	if _tick_variant(delta):
		_advance(delta)
		return

	if is_elite():
		_elite_ai(delta)
	elif is_boss_family():
		_boss2_ai(delta)
	elif kind == KIND_FLYER:
		_flyer_ai(delta)
	else:
		_ground_ai(delta)

	_advance(delta)


## R10：平面落地 —— x 由速度推，y 由深度决定（深度又被 _update_depth 拉向玩家）
func _advance(delta: float) -> void:
	if kind == KIND_FLYER:
		# 飞行单位自己管 y（悬停 / 俯冲），只是夹在地板范围内
		global_position += velocity * delta
		global_position.x = clampf(global_position.x, arena.x, arena.y)
		global_position.y = clampf(global_position.y,
			SpaceScript.FLOOR_FAR_Y + 4.0, SpaceScript.FLOOR_NEAR_Y - 4.0)
		depth = SpaceScript.depth_of(global_position.y)
	else:
		global_position.x += velocity.x * delta
		global_position.x = clampf(global_position.x, arena.x, arena.y)
		global_position.y = SpaceScript.y_of(depth)
	z_index = SpaceScript.z_order(depth)


# ------------------------------------------------------------------ AI
func _player_ok() -> bool:
	return player != null and is_instance_valid(player) and not player.dead


func _ground_ai(delta: float) -> void:
	var dx: float = player.global_position.x - global_position.x
	var dy: float = player.global_position.y - global_position.y
	var dist: float = absf(dx)

	match state:
		IDLE, CHASE:
			if _player_ok() and dist < aggro_range and absf(dy) < 220.0:
				state = CHASE
				facing = 1 if dx > 0.0 else -1
				if _alert <= 0.0 and dist < aggro_range * 0.8:
					_alert = 1.0
					if fx:
						fx.text(global_position + Vector2(0, -60.0 * scale_f), "!", Color(1.0, 0.4, 0.45), 26)
			if state == CHASE:
				# R10：所有 Boss 都会格挡 —— 玩家举刀压上来时有概率架盾
				if is_boss and _defend_cd <= 0.0 and dist < attack_range * 2.4 \
						and _player_ok() and player.is_swinging() and randf() < 0.30:
					_defend_cd = randf_range(2.6, 4.2)
					_start_defend()
					return
				if dist < attack_range and _cd <= 0.0:
					_set_state(WINDUP)
				else:
					var want := facing * move_speed * rage_mul
					if not _ground_ahead():
						want = 0.0
					velocity.x = move_toward(velocity.x, want, 900.0 * delta)
					if dist < attack_range * 1.4:
						velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
			else:
				var target_x := home.x + sin(_t * 0.7) * patrol_range
				var d := target_x - global_position.x
				if absf(d) > 8.0:
					facing = 1 if d > 0.0 else -1
					velocity.x = move_toward(velocity.x, facing * move_speed * 0.55, 700.0 * delta)
				else:
					velocity.x = move_toward(velocity.x, 0.0, 700.0 * delta)
			velocity.y = minf(velocity.y + 1680.0 * delta, 900.0)

		WINDUP:
			velocity.x = move_toward(velocity.x, 0.0, 1600.0 * delta)
			velocity.y = minf(velocity.y + 1680.0 * delta, 900.0)
			if _player_ok():
				var d2: float = player.global_position.x - global_position.x
				if absf(d2) > 6.0 and st < windup_t * 0.7:
					facing = 1 if d2 > 0.0 else -1
			if st >= windup_t / rage_mul:
				_set_state(ATTACK)
				SFX.play_rand("slash", 0.72, 0.86, -2.0)
				Game.add_shake(2.5)

		ATTACK:
			atk_age = st
			var dir := 1.0 if facing > 0 else -1.0
			velocity.x = dir * lunge_speed
			velocity.y = minf(velocity.y + 1680.0 * delta, 900.0)
			if st >= attack_t:
				_set_state(RECOVER)

		RECOVER:
			atk_age = 99.0
			unblockable = false
			velocity.x = move_toward(velocity.x, 0.0, 1200.0 * delta)
			velocity.y = minf(velocity.y + 1680.0 * delta, 900.0)
			if st >= recover_t:
				combo += 1
				var close: bool = false
				if _player_ok():
					close = absf(player.global_position.x - global_position.x) < attack_range * 1.3
				if is_boss and combo < 3 and close and randf() < 0.85:
					windup_t = 0.24
					_set_state(WINDUP)
				else:
					combo = 0
					windup_t = 0.38 if is_boss else 0.44
					_cd = randf_range(0.25, 0.7) if is_boss else randf_range(0.5, 1.2)
					_set_state(CHASE)

		DEFEND:
			# R10：镇钟力士也会架盾格挡（其余 Boss 走 _boss2_ai 的同名状态）
			atk_age = 99.0
			velocity.x = move_toward(velocity.x, 0.0, 1800.0 * delta)
			velocity.y = move_toward(velocity.y, 0.0, 900.0 * delta)
			if _player_ok() and absf(dx) > 6.0:
				facing = 1 if dx > 0.0 else -1
			if st >= defend_t:
				combo = 0
				_cd = randf_range(0.2, 0.5)
				_set_state(CHASE)


# ------------------------------------------------------------------ R18 精英 AI
## 精英不写六套 AI：近战仍是 _ground_ai，这里只负责「专属技能」与几个额外状态。
## 每个精英的专属技能都对应一条现有机制，玩家打完就复习了一遍。
func _elite_ai(delta: float) -> void:
	var dx := 0.0
	var dist := 9999.0
	if _player_ok():
		dx = float(player.global_position.x) - global_position.x
		dist = absf(dx)

	_elite_cd = maxf(0.0, _elite_cd - delta)
	ranged_cd = maxf(0.0, ranged_cd - delta)
	aoe_cd = maxf(0.0, aoe_cd - delta)
	_summon_cd = maxf(0.0, _summon_cd - delta)

	# 自爆（丹修自己的、或自爆型变奏）优先，倒计时期间不干别的
	if _fuse_step(delta):
		return

	# 召唤（纸人）：每 8 秒放 3 只纸人分身，逼玩家用剑气纵横清场
	if kind == KIND_ZHIREN and not mini and _summon_cd <= 0.0 and _player_ok():
		_summon_cd = ELITE_SUMMON_CD
		summon.emit(global_position, 3)
		if fx:
			fx.ring(global_position, 8.0, 110.0, Color(0.95, 0.92, 0.78), 0.4, 3.0)
			fx.text(global_position + Vector2(0, -96.0 * scale_f), "剪 纸 成 人",
				Color(0.96, 0.92, 0.76), 21, 40)
		SFX.play("heal", 1.3, -10.0)
		return

	match state:
		RANGED:
			velocity.x = move_toward(velocity.x, 0.0, 1400.0 * delta)
			velocity.y = minf(velocity.y + 1680.0 * delta, 900.0)
			if _player_ok() and absf(dx) > 6.0:
				facing = 1 if dx > 0.0 else -1
			if st >= 0.38 and not _bolt_done:
				_bolt_done = true
				_elite_fire()
			if st >= 0.72:
				_cd = randf_range(0.4, 0.9)
				_set_state(CHASE)
			return
		AOE:
			velocity.x = move_toward(velocity.x, 0.0, 2200.0 * delta)
			velocity.y = minf(velocity.y + 1680.0 * delta, 900.0)
			if _player_ok() and absf(dx) > 6.0:
				facing = 1 if dx > 0.0 else -1
			if st >= 0.85:
				aoe.emit(global_position, AOE_RADIUS * 0.8)
				_cd = 0.3
				_set_state(RECOVER)
			return

	# 近战照旧走通用逻辑
	_ground_ai(delta)
	# 通用逻辑没接管这一帧（还在追人）→ 看看要不要插一个专属技能
	if state == CHASE and _player_ok():
		_elite_try_special(dist)


## 精英专属技能（按 kind 分派）。返回 true 表示这一帧已经换状态了。
func _elite_try_special(dist: float) -> bool:
	if mini:
		return false
	match kind:
		KIND_JIANXIU:
			# 剑阵（范围）+ 双持飞剑（两连发）：罡气厚，得用凝罡·开山破
			if aoe_cd <= 0.0 and dist < AOE_RADIUS * 1.6:
				_start_aoe()
				return true
			if ranged_cd <= 0.0 and dist > 150.0:
				ranged_cd = 6.0
				_bolt_done = false
				_set_state(RANGED)
				return true
		KIND_FUXIU:
			# 贴符（三连扇形）+ 符墙（举符格挡）
			if ranged_cd <= 0.0 and dist > 110.0:
				ranged_cd = 4.2
				_bolt_done = false
				_set_state(RANGED)
				return true
			if _defend_cd <= 0.0 and dist < 190.0:
				_start_defend()
				return true
		KIND_DANXIU:
			# 炼丹回气（远处）+ 丹炉自爆（近身、血过半）
			if _elite_cd <= 0.0 and dist < 175.0 and hp <= int(ceil(float(max_hp) * 0.55)):
				_start_fuse()
				return true
			if _elite_cd <= 0.0 and dist > 210.0 and hp < max_hp:
				_elite_cd = 7.0
				hp = mini(hp + 2, max_hp)
				if fx:
					fx.ring(global_position, 6.0, 74.0, Color(1.0, 0.62, 0.45), 0.45, 3.0)
					fx.text(global_position + Vector2(0, -92.0 * scale_f), "炼 丹 · 回 气",
						Color(1.0, 0.72, 0.5), 20, 36)
				SFX.play("heal", 1.1, -12.0)
		KIND_YUANLING:
			# 阴气弹：从阴界打过来，阳界看不见（玩家得入阴才躲得开 / 打得到）
			if ranged_cd <= 0.0:
				ranged_cd = 3.4
				_bolt_done = false
				_set_state(RANGED)
				return true
		KIND_SHIJUI:
			# 预判出刀（提前架住）+ 抓取（不可格挡，得闪）
			if _defend_cd <= 0.0 and _player_ok() and player.is_swinging() and randf() < 0.8:
				_defend_cd = 2.6
				_start_defend()
				return true
			if _elite_cd <= 0.0 and dist < 210.0:
				_elite_cd = 5.5
				unblockable = true
				_begin_windup(1.15)
				if fx:
					fx.text(global_position + Vector2(0, -98.0 * scale_f), "抓 取",
						Color(0.9, 0.55, 0.45), 20, 34)
				return true
	return false


## RANGED 状态下真正把东西放出去（符修是三连扇形）
func _elite_fire() -> void:
	match kind:
		KIND_FUXIU:
			_fire_fan(3, 0.22)
		KIND_JIANXIU:
			_fire_fan(2, 0.10)
		_:
			_fire_bolt()


## 扇形齐射：n 发，相邻两发夹角 spread（弧度）
func _fire_fan(n: int, spread: float) -> void:
	var origin := global_position + Vector2(float(facing) * 26.0 * scale_f, -18.0 * scale_f)
	var base := Vector2(float(facing), 0.0)
	if _player_ok():
		base = (player.global_position + Vector2(0, -8) - origin).normalized()
	var half := spread * float(n - 1) * 0.5
	for i in n:
		var ang := -half + spread * float(i)
		fired.emit(origin, base.rotated(ang), 330.0)
	if fx:
		fx.ring(origin, 5.0, 48.0, Color(0.9, 0.62, 0.4), 0.28, 2.6)
	SFX.play_rand("dash", 0.66, 0.8, -6.0)
	Game.add_shake(3.0)


# ------------------------------------------------------------------ R18 行为变奏
## 每帧 tick 一次，返回 true 表示「这一帧已经被变奏接管」，跳过常规 AI
func _tick_variant(delta: float) -> bool:
	if variant == VAR_NONE:
		return false
	_shield_idle += delta
	match variant:
		VAR_SHIELD:
			# 护盾：不挨打 4 秒回满 → 逼玩家连续打，别打一下就跑
			if shield < SHIELD_AMOUNT and _shield_idle >= SHIELD_REGEN:
				shield = SHIELD_AMOUNT
				if fx:
					fx.ring(global_position, 6.0, 56.0, Color(0.62, 0.86, 1.0), 0.3, 2.0)
		VAR_RAGE:
			if not berserk and hp <= int(ceil(float(max_hp) * 0.3)):
				_enter_rage()
		VAR_SUMMON:
			_summon_cd = maxf(0.0, _summon_cd - delta)
			if _summon_cd <= 0.0 and _player_ok() and state != STAGGER:
				_summon_cd = ELITE_SUMMON_CD
				summon.emit(global_position, 1)
				if fx:
					fx.text(global_position + Vector2(0, -92.0 * scale_f), "召 唤",
						Color(0.86, 0.92, 1.0), 19, 32)
		VAR_READ:
			_var_cd = maxf(0.0, _var_cd - delta)
			if _var_cd <= 0.0 and state == CHASE and _player_ok() \
					and player.is_swinging() and randf() < 0.55:
				_var_cd = 2.8
				_start_defend()
				return true
		VAR_BOMB:
			if state == FUSE:
				return _fuse_step(delta)
			_var_cd = maxf(0.0, _var_cd - delta)
			if _var_cd <= 0.0 and state == CHASE and _player_ok():
				var dx: float = absf(float(player.global_position.x) - global_position.x)
				if dx < 96.0:
					_var_cd = 99.0
					_start_fuse()
					return true
	return false


## 自爆倒计时：FUSE 状态本身 = 可处决窗口
func _start_fuse() -> void:
	_fuse_t = 0.0
	_fuse_canceled = false
	broken_t = FUSE_TIME          # 倒计时期间 is_broken() 为真 → 可处决
	posture = max_posture
	_set_state(FUSE)
	velocity = Vector2.ZERO
	if fx:
		fx.ring(global_position, 8.0, 96.0, Color(1.0, 0.55, 0.35), 0.5, 3.5)
		fx.text(global_position + Vector2(0, -104.0 * scale_f), "丹 炉 欲 爆",
			Color(1.0, 0.6, 0.4), 22, 42)
	SFX.play("boss", 1.5, -9.0)


func _fuse_step(delta: float) -> bool:
	if state != FUSE:
		return false
	velocity.x = move_toward(velocity.x, 0.0, 1600.0 * delta)
	velocity.y = minf(velocity.y + 1680.0 * delta, 900.0)
	_fuse_t += delta
	if _fuse_t >= FUSE_TIME:
		_explode()
	return true


func _explode() -> void:
	if dead:
		return
	if fx:
		fx.ring(global_position, 14.0, 190.0, Color(1.0, 0.6, 0.35), 0.5, 5.0)
		fx.burst(global_position, 30, Color(1.0, 0.7, 0.4), 1.2)
		fx.text(global_position + Vector2(0, -110.0 * scale_f), "自 爆", Color(1.0, 0.62, 0.4), 26, 46)
	aoe.emit(global_position, 165.0)
	Game.add_shake(14.0)
	Game.hitstop(0.08, 0.03)
	SFX.play("boss", 1.1, -4.0)
	hp = 0
	_die()


func _enter_rage() -> void:
	berserk = true
	rage_mul = 1.5
	if fx:
		fx.ring(global_position, 10.0, 150.0, Color(1.0, 0.35, 0.3), 0.5, 4.0)
		fx.text(global_position + Vector2(0, -100.0 * scale_f), "狂 暴", Color(1.0, 0.45, 0.4), 24, 44)
	SFX.play("boss", 1.2, -8.0)


# ------------------------------------------------------------------ 三阶段 Boss
## 招式等级：剑冢守 = 1/2/3 阶段；前世身 = 3/4/5
## （前世身的一阶段就等于剑冢守的三阶段，再往上叠新招）
## 会闪现 / 震波 / 分身的「刺客型」Boss（前世身、域外天魔）
func is_blade_boss() -> bool:
	return kind == KIND_BOSS3 or kind == KIND_BOSS5


## Boss 家族（统一走 _boss2_ai）
func is_boss_family() -> bool:
	return kind == KIND_BOSS2 or kind == KIND_BOSS3 or kind == KIND_BOSS4 \
		or kind == KIND_BOSS5 or kind == KIND_BOSS6 or kind == KIND_BOSS7 \
		or kind == KIND_BOSS8 or kind == KIND_BOSS9


func _tier() -> int:
	if is_blade_boss():
		return phase + 2
	return phase


func _windup_now() -> float:
	# R39 钟楼旧主：前摇**故意拉长**到 0.62（普通 Boss 是 0.21~0.36）。
	# 他存在的意义是教完美弹反 —— 慢到玩家看得清抬手，才谈得上「练」。
	# 注意：这一条必须放在 _tier() 之前，否则二阶段 tier 变高会把前摇压回 0.21。
	if kind == KIND_BOSS9:
		return 0.62 if not berserk else 0.50
	var t := _tier()
	var w := 0.36
	if t >= 2:
		w = 0.30
	if t >= 3:
		w = 0.26
	if t >= 4:
		w = 0.23
	if t >= 5:
		w = 0.21
	if berserk:
		w *= 0.78
	if kind == KIND_BOSS4:
		w *= 1.32
	elif kind == KIND_BOSS5:
		w *= 0.86
	elif kind == KIND_BOSS6 and mirror_weapon != "":
		# R19b：出招速度也抄玩家的武器（双刀 1.25 → 更快，长枪 0.82 → 更慢）
		w /= maxf(0.4, WeaponScript.speed_mul(mirror_weapon))
	return w


func _begin_windup(mul: float) -> void:
	windup_t = maxf(0.12, _windup_now() * mul)
	_set_state(WINDUP)


func _boss2_ai(delta: float) -> void:
	var dx: float = 0.0
	var dist := 9999.0
	if _player_ok():
		dx = player.global_position.x - global_position.x
		dist = absf(dx)

	berserk_cd = maxf(0.0, berserk_cd - delta)
	ranged_cd = maxf(0.0, ranged_cd - delta)
	_intent_cd = maxf(0.0, _intent_cd - delta)
	blink_cd = maxf(0.0, blink_cd - delta)
	aoe_cd = maxf(0.0, aoe_cd - delta)
	clone_cd = maxf(0.0, clone_cd - delta)

	match state:
		IDLE, CHASE:
			if _player_ok() and dist < aggro_range:
				state = CHASE
				if absf(dx) > 8.0:
					facing = 1 if dx > 0.0 else -1
				if _alert <= 0.0 and dist < aggro_range * 0.7:
					_alert = 1.0
					if fx:
						fx.text(global_position + Vector2(0, -76.0 * scale_f), "!", Color(1.0, 0.4, 0.45), 30)
			if state == CHASE:
				# R39 钟楼旧主：慢速逼近 → 进圈**停住** → 出慢刀。
				# 停住是为了给玩家留出弹反距离：贴脸会让玩家看不清抬手。
				if kind == KIND_BOSS9:
					var want9 := float(facing) * move_speed
					if dist < attack_range * 0.78:
						want9 = 0.0
					velocity.x = move_toward(velocity.x, want9, 620.0 * delta)
					velocity.y = minf(velocity.y + 1680.0 * delta, 900.0)
					if dist < attack_range and _cd <= 0.0:
						_decide()
					return
				# R36 符祖：远程 —— 中距离画符齐射 + 周期性地面符爆（「画符封路」）
				if kind == KIND_BOSS7:
					if ranged_cd <= 0.0 and _player_ok():
						ranged_cd = 2.6
						_bolt_done = false
						_set_state(RANGED)
						return
					if aoe_cd <= 0.0 and _player_ok() and dist < 440.0:
						_start_aoe()
						return
					var want7 := 0.0
					if dist < 210.0:
						want7 = -float(facing) * move_speed * 0.95
					elif dist > 340.0:
						want7 = float(facing) * move_speed * 0.7
					velocity.x = move_toward(velocity.x, want7, 900.0 * delta)
					velocity.y = minf(velocity.y + 1680.0 * delta, 900.0)
					return
				# R37 轮回使：近身压迫 + 周期性召「旧影」。
				# 注意这里**不 return** —— 召唤只是插一段演出，追击不中断，
				# 否则它会站在原地被白打（R36 符祖的 return 是远程走位需要，别照抄）。
				if kind == KIND_BOSS8 and clone_cd <= 0.0 and _player_ok():
					clone_cd = 7.5 if phase < 2 else 5.5
					echo_call.emit(global_position, 2 if phase < 2 else 3)
					if fx:
						fx.text(global_position + Vector2(0, -86.0 * scale_f), "旧 影",
							Color(0.78, 0.66, 1.0), 18, 34)
					Game.add_shake(3.0)
				# 前世身：玩家 10 秒没受伤 → 立刻放范围攻击（贴近了才放）
				if is_blade_boss() and aoe_cd <= 0.0 and _player_ok() \
						and float(player.hurt_age) >= NO_HURT_TRIGGER and dist < AOE_RADIUS * 1.7:
					_start_aoe()
					return
				# 三阶段：分身
				if _tier() >= 5 and clone_cd <= 0.0 and _player_ok():
					_start_clones()
					return
				if _tier() >= 3 and berserk_cd <= 0.0 and not berserk and dist < 460.0:
					_start_berserk()
					return
				if dist < attack_range * 1.1 and _cd <= 0.0:
					_decide()
				else:
					var want := float(facing) * move_speed * (1.32 if berserk else 1.0)
					if not _ground_ahead():
						want = 0.0
					velocity.x = move_toward(velocity.x, want, 1000.0 * delta)
					if dist < attack_range * 1.5:
						velocity.x = move_toward(velocity.x, 0.0, 1200.0 * delta)
			velocity.y = minf(velocity.y + 1680.0 * delta, 900.0)

		WINDUP:
			velocity.x = move_toward(velocity.x, 0.0, 1700.0 * delta)
			velocity.y = minf(velocity.y + 1680.0 * delta, 900.0)
			if _player_ok() and st < windup_t * 0.65 and absf(dx) > 6.0:
				facing = 1 if dx > 0.0 else -1
			if st >= windup_t:
				_set_state(ATTACK)
				SFX.play_rand("slash", 0.62 if berserk else 0.68, 0.8, -2.0)
				Game.add_shake(5.0 if berserk else 3.0)

		ATTACK:
			atk_age = st
			velocity.x = float(facing) * lunge_speed * (1.25 if berserk else 1.0)
			velocity.y = minf(velocity.y + 1680.0 * delta, 900.0)
			if st >= attack_t:
				_set_state(RECOVER)

		RECOVER:
			atk_age = 99.0
			unblockable = false
			velocity.x = move_toward(velocity.x, 0.0, 1300.0 * delta)
			velocity.y = minf(velocity.y + 1680.0 * delta, 900.0)
			if st >= recover_t * (0.8 if berserk else 1.0):
				if _consume_queued():
					return
				combo += 1
				var maxc := 2 if _tier() <= 1 else 3
				var close := false
				if _player_ok():
					close = absf(dx) < attack_range * 1.45
				if combo < maxc and close and randf() < 0.9:
					_begin_windup(0.82)
				else:
					combo = 0
					_cd = randf_range(0.18, 0.45) if _tier() >= 2 else randf_range(0.3, 0.7)
					_set_state(CHASE)

		DEFEND:
			velocity.x = move_toward(velocity.x, 0.0, 2200.0 * delta)
			velocity.y = minf(velocity.y + 1680.0 * delta, 900.0)
			if _player_ok() and absf(dx) > 6.0:
				facing = 1 if dx > 0.0 else -1
			if st >= defend_t:
				if _consume_queued():
					return
				combo = 0
				_begin_windup(0.72)

		DODGE:
			velocity.x = _dodge_dir * 560.0
			velocity.y = minf(velocity.y + 1680.0 * delta, 900.0)
			global_position.x = clampf(global_position.x, arena.x, arena.y)
			if st >= 0.3:
				if _consume_queued():
					return
				_cd = 0.1
				_set_state(CHASE)

		RANGED:
			velocity.x = move_toward(velocity.x, 0.0, 1400.0 * delta)
			velocity.y = minf(velocity.y + 1680.0 * delta, 900.0)
			if _player_ok() and absf(dx) > 6.0:
				facing = 1 if dx > 0.0 else -1
			if st >= 0.46:
				# R19b：无相·心魔二阶段「借宝」放的是三连扇形（法宝的「攻」那半）
				if kind == KIND_BOSS6 and phase >= 2:
					_fire_fan(3, 0.22)
				elif kind == KIND_BOSS7:
					# R36 符祖：五连扇形（画符齐射）
					_fire_fan(5, 0.15)
				else:
					_fire_bolt()
				if _consume_queued():
					return
				_set_state(RECOVER)

		BLINK:
			velocity = Vector2.ZERO
			if st >= 0.24:
				_do_blink()

		AOE:
			velocity.x = move_toward(velocity.x, 0.0, 2400.0 * delta)
			velocity.y = minf(velocity.y + 1680.0 * delta, 900.0)
			if _player_ok() and absf(dx) > 6.0:
				facing = 1 if dx > 0.0 else -1
			_aoe_t += delta
			if st >= 0.85:
				aoe.emit(global_position, AOE_RADIUS)
				if _consume_queued():
					return
				_cd = 0.3
				_set_state(RECOVER)

		# R22：影·绝招 —— 与玩家绝招同构的多段施放（line 一段 / lance 三段 / spin 六段）
		# R26：旋刃是移动版 —— 施放期间缓缓逼向玩家；剑 / 枪维持定身
		MIRROR_ULT:
			velocity.y = minf(velocity.y + 1680.0 * delta, 900.0)
			velocity.x = move_toward(velocity.x,
				mirror_chase_vx(dx, str(mult_cfg.get("id", ""))), 900.0 * delta)
			if _player_ok() and absf(dx) > 6.0:
				facing = 1 if dx > 0.0 else -1
			mult_t -= delta
			while mult_left > 0 and mult_t <= 0.0:
				_mult_fire_one(mult_idx)
				mult_idx += 1
				mult_left -= 1
				mult_t += maxf(0.016, float(mult_cfg.get("gap", 0.30)))
			if mult_left <= 0:
				_cd = 0.4
				_set_state(RECOVER)

		PHASE:
			velocity.x = move_toward(velocity.x, 0.0, 2400.0 * delta)
			velocity.y = minf(velocity.y + 1680.0 * delta, 900.0)
			if st >= 1.5:
				_cd = 0.5
				_set_state(CHASE)


## 出招决策：三阶段有 50% 概率先「读指令」
func _decide() -> void:
	unblockable = false
	# R39 钟楼旧主：**只有一记慢刀**。不读招、不瞬移、不远程、不防御。
	# 这是全作唯一「招式完全可预测」的 Boss —— 他的作用是让玩家练弹反，
	# 而不是让玩家猜。所以这条必须抢在所有分支前面 return。
	if kind == KIND_BOSS9:
		_begin_windup(1.0)
		return
	var t := _tier()
	# 前世身：血量 20% 以下，每次出招同时放两个技能
	if is_blade_boss() and hp <= int(ceil(float(max_hp) * 0.2)):
		var pool := _skill_pool()
		var first := str(pool.pick_random())
		_queue_skill = str(pool.pick_random())
		if fx:
			fx.text(global_position + Vector2(0, -112.0 * scale_f), "双 技", Color(1.0, 0.5, 0.42), 22, 34)
			fx.ring(global_position, 8.0, 90.0, Color(1.0, 0.45, 0.35), 0.3, 3.0)
		_run_skill(first)
		return
	# R22：完全体镜像 —— 二阶段冷却好了就有概率把玩家的绝招原样甩回来
	if kind == KIND_BOSS6 and phase >= 2 and mirror_weapon != "" \
			and mirror_ult_cd <= 0.0 and randf() < 0.40:
		_start_mirror_ult()
		return
	if t >= 3 and _intent_cd <= 0.0 and randf() < 0.5 and _read_intent():
		_intent_cd = 1.6
		return
	if t >= 4 and blink_cd <= 0.0 and randf() < 0.42:
		_start_blink()
		return
	if t >= 2 and kind != KIND_BOSS4 and ranged_cd <= 0.0 and randf() < 0.30:
		_start_ranged()
		return
	if t >= 2 and randf() < (0.34 if kind == KIND_BOSS4 else 0.18):
		_start_defend()
		return
	_begin_windup(1.0)


func _skill_pool() -> Array:
	var t := _tier()
	var pool := ["attack", "attack", "aoe"]
	if t >= 2:
		pool.append("ranged")
		pool.append("defend")
	if t >= 3:
		pool.append("dodge")
		pool.append("berserk")
	if t >= 4:
		pool.append("blink")
	# R19b：无相·心魔二阶段「复制法宝」——多一招「借宝」（飞剑齐射 + 护盾）
	if kind == KIND_BOSS6 and phase >= 2:
		pool.append("borrow")
		pool.append("borrow")
		# R22：完全体镜像 —— 「影·绝招」也进池（是否真放由冷却闸门管）
		pool.append("mirror_ult")
	return pool


func _run_skill(n: String) -> void:
	match n:
		"ranged":
			_start_ranged()
		"defend":
			_start_defend()
		"dodge":
			_start_dodge()
		"blink":
			_start_blink()
		"aoe":
			_start_aoe()
		"berserk":
			if berserk:
				_begin_windup(0.7)
			else:
				_start_berserk()
		"borrow":
			_start_borrow()
		"mirror_ult":
			if mirror_ult_cd <= 0.0 and mirror_weapon != "":
				_start_mirror_ult()
			else:
				_begin_windup(0.85)
		_:
			_begin_windup(0.85)


func _consume_queued() -> bool:
	if _queue_skill == "":
		return false
	var s := _queue_skill
	_queue_skill = ""
	_run_skill(s)
	return true


## 读取玩家当前动作并给出针对性应对
func _read_intent() -> bool:
	if not _player_ok():
		return false
	var intent := "idle"
	if player.atk != 0:
		intent = "attack"
	elif player.is_guarding():
		intent = "guard"
	elif player.dash_t > 0.0:
		intent = "dash"
	elif not player.is_on_floor():
		intent = "air"
	match intent:
		"attack":
			_show_intent("读招 · 闪")
			_start_dodge()
			return true
		"guard":
			_show_intent("读招 · 破防")
			unblockable = true
			_begin_windup(0.95)
			return true
		"dash":
			_show_intent("读招 · 挡")
			_start_defend()
			return true
		"air":
			_show_intent("读招 · 对空")
			_begin_windup(0.72)
			return true
	return false


func _show_intent(txt: String) -> void:
	if fx:
		fx.text(global_position + Vector2(0, -102.0 * scale_f), txt, Color(0.86, 0.62, 1.0), 21, 40)
		fx.ring(global_position + Vector2(0, -18.0 * scale_f), 6.0, 72.0, Color(0.78, 0.55, 1.0), 0.3, 2.0)
	SFX.play("heal", 1.6, -15.0)


func _start_defend() -> void:
	defend_hits = 0
	defend_t = 0.9 if _tier() >= 3 else 0.75
	_defend_cd = randf_range(2.2, 3.8)
	_set_state(DEFEND)
	if fx:
		fx.ring(global_position, 8.0, 64.0, Color(0.55, 0.78, 1.0), 0.3, 2.5)
	SFX.play("gate", 1.35, -14.0)


func _start_dodge() -> void:
	var away := 1.0
	if _player_ok() and player.global_position.x > global_position.x:
		away = -1.0
	if global_position.x + away * 100.0 < arena.x or global_position.x + away * 100.0 > arena.y:
		away = -away
	_dodge_dir = away
	invuln_t = 0.32
	_trail.clear()
	_set_state(DODGE)
	if fx:
		fx.dust(global_position + Vector2(0, 16), 6)
	SFX.play_rand("dash", 0.72, 0.88, -8.0)


func _start_ranged() -> void:
	ranged_cd = randf_range(3.2, 5.0)
	_set_state(RANGED)
	if fx:
		fx.ring(global_position + Vector2(float(facing) * 26.0 * scale_f, -18.0 * scale_f), 4.0, 34.0,
			Color(0.8, 0.5, 1.0), 0.25, 2.0)


func _fire_bolt() -> void:
	var origin := global_position + Vector2(float(facing) * 26.0 * scale_f, -18.0 * scale_f)
	var dir := Vector2(float(facing), 0.0)
	if _player_ok():
		dir = (player.global_position + Vector2(0, -8) - origin).normalized()
	fired.emit(origin, dir, 340.0 if not berserk else 400.0)
	SFX.play_rand("dash", 0.66, 0.8, -6.0)
	Game.add_shake(3.0)
	if fx:
		fx.ring(origin, 5.0, 46.0, Color(0.85, 0.55, 1.0), 0.28, 2.6)


## 闪现：原地消失，出现在玩家背后，然后随机接一招
func _start_blink() -> void:
	blink_cd = randf_range(2.6, 4.4)
	combo = 0
	_set_state(BLINK)
	if fx:
		fx.ring(global_position, 10.0, 76.0, Color(0.45, 0.72, 1.0), 0.24, 3.0)
		fx.text(global_position + Vector2(0, -100.0 * scale_f), "闪 现", Color(0.6, 0.85, 1.0), 19, 30)
	SFX.play("gate", 1.5, -18.0)


func _do_blink() -> void:
	if not _player_ok():
		_set_state(CHASE)
		return
	# 玩家背后 = 朝向的反方向
	var side := -float(player.facing)
	var tx: float = float(player.global_position.x) + side * 62.0
	tx = clampf(tx, arena.x + 40.0, arena.y - 40.0)
	if fx:
		fx.burst(global_position, 14, Color(0.45, 0.75, 1.0), 0.9)
	global_position = Vector2(tx, float(player.global_position.y) - 2.0)
	facing = 1 if float(player.global_position.x) > global_position.x else -1
	if fx:
		fx.burst(global_position, 22, Color(0.6, 0.9, 1.0), 1.2)
		fx.ring(global_position, 8.0, 104.0, Color(0.7, 0.95, 1.0), 0.34, 3.5)
		# 突进劈
		fx.arc(global_position, 0.0, TAU, 40.0, Color(0.7, 0.95, 1.0, 0.5), 0.2)
	SFX.play_rand("dash", 0.5, 0.68, -3.0)
	Game.add_shake(7.0)
	invuln_t = 0.12
	# 随机接一招
	var r := randf()
	if r < 0.44:
		_begin_windup(0.6)
	elif r < 0.70:
		unblockable = true
		_begin_windup(0.78)
	elif r < 0.86:
		_start_ranged()
	else:
		_start_aoe()


## 范围震波：玩家 10 秒没受伤时触发，必须跳起来躲
func _start_aoe() -> void:
	aoe_cd = 9.0
	combo = 0
	_aoe_t = 0.0
	_set_state(AOE)
	if fx:
		fx.ring(global_position + Vector2(0, 12), 10.0, AOE_RADIUS, Color(1.0, 0.58, 0.32), 0.85, 3.0)
		fx.text(global_position + Vector2(0, -104.0 * scale_f), "范 围 震 波", Color(1.0, 0.72, 0.42), 22, 46)
	SFX.play("boss", 1.4, -7.0)
	Game.add_shake(6.0)


## 分身：三阶段才解锁，一次放两个，持续 20 秒
func _start_clones() -> void:
	clone_cd = 13.0
	combo = 0
	_cd = 0.75
	invuln_t = 0.3
	summon.emit(global_position, 2)
	if fx:
		fx.ring(global_position, 12.0, 150.0, Color(0.5, 0.9, 1.0), 0.5, 4.0)
		fx.burst(global_position, 24, Color(0.55, 0.9, 1.0), 1.2)
		fx.text(global_position + Vector2(0, -110.0 * scale_f), "分 身", Color(0.65, 0.95, 1.0), 24, 44)
	SFX.play("boss", 1.15, -6.0)
	Game.add_shake(11.0)


func _start_berserk() -> void:
	berserk = true
	berserk_t = 4.5
	berserk_cd = 9.5
	combo = 0
	_cd = 0.15
	_set_state(CHASE)
	if fx:
		fx.ring(global_position, 10.0, 190.0, Color(1.0, 0.32, 0.3), 0.55, 5.0)
		fx.burst(global_position, 26, Color(1.0, 0.4, 0.38), 1.1)
		fx.text(global_position + Vector2(0, -104.0 * scale_f), "狂 暴", Color(1.0, 0.45, 0.4), 28, 50)
	Game.add_shake(13.0)
	Game.hitstop(0.09, 0.03)


## R19b：无相·心魔二阶段「借 宝」——把玩家的法宝也借过来用：
## 一层护盾（法宝的「守」）+ 三连飞剑（法宝的「攻」）。
## 这是「复制法宝」的表现层实现：不逐件还原 12 种法宝，只抄它们的两端。
func _start_borrow() -> void:
	mirror_ult_cd = 7.5
	combo = 0
	shield = maxf(shield, 34.0)
	_cd = 0.55
	invuln_t = 0.16
	_set_state(RANGED)
	ranged_cd = 0.9
	_bolt_done = false
	if fx:
		fx.ring(global_position, 12.0, 170.0, Color(0.72, 0.62, 1.0), 0.5, 4.0)
		fx.text(global_position + Vector2(0, -108.0 * scale_f), "借 宝", Color(0.78, 0.72, 1.0), 24, 46)
	SFX.play("boss", 1.05, -6.0)
	Game.add_shake(9.0)
	SFX.play("boss", 1.2, -5.0)


## R22：无相·心魔二阶段「影 · 绝招」——完全体镜像的最后一层：
## R18b 给玩家的三把武器专属绝招，现在镜子里的它也会。
## 形状 / 段数 / 间隔 / 前冲距离全部照抄 WeaponScript.ult_of(mirror_weapon)：
##   剑·剑心一线 → 一道 560×84 贯穿直斩
##   枪·枪出如龙 → 三段 190×58 突刺，每段往前顶 300
##   双刀·双生旋刃 → 原地 132 半径六段旋风
## 反制不变：绝招打的是矩形 / 圆形判定，冲刺无敌帧照样能穿，格挡朝对了也能挡。
## R26：影·绝招期间的目标横速 —— 旋刃（spin）是移动版，缓缓逼向玩家；剑 / 枪定身
static func mirror_chase_vx(dx: float, ult_id: String) -> float:
	if ult_id != "spin" or absf(dx) <= 90.0:
		return 0.0
	return signf(dx) * 110.0


## R26：反制门 —— 二阶段无相·心魔且影·绝招已就绪时才可能反制（确定性部分）
func can_counter_ult() -> bool:
	return kind == KIND_BOSS6 and phase >= 2 and state != DEAD \
		and mirror_ult_cd <= 0.0 and mirror_weapon != ""


## R26：绝招反制 —— 玩家开大瞬间调用；过门后按 counter_chance 掷骰，中则同步开影·绝招
func try_counter_ult() -> bool:
	if not can_counter_ult() or randf() >= counter_chance:
		return false
	_start_mirror_ult()
	if fx:
		fx.text(global_position + Vector2(0, -150.0 * scale_f),
			"影 · 反 制", Color(0.9, 0.62, 1.0), 20, 40)
	return true


func _start_mirror_ult() -> void:
	mirror_ult_cd = 6.5
	combo = 0
	mult_cfg = WeaponScript.ult_of(mirror_weapon)
	mult_left = maxi(1, int(mult_cfg.get("shots", 1)))
	mult_idx = 0
	mult_t = 0.0
	_set_state(MIRROR_ULT)
	if fx:
		fx.ring(global_position, 10.0, 160.0, Color(0.78, 0.72, 1.0), 0.55, 4.0)
		fx.text(global_position + Vector2(0, -122.0 * scale_f),
			"影 · " + WeaponScript.ult_name(mirror_weapon), Color(0.85, 0.78, 1.0), 24, 48)
	SFX.play("boss", 1.1, -6.0)
	Game.add_shake(7.0)


func _mult_fire_one(i: int) -> void:
	var id := str(mult_cfg.get("id", "spin"))
	if id == "spin":
		mirror_burst.emit(global_position, float(mult_cfg.get("radius", 132.0)))
		if fx:
			fx.ring(global_position, 18.0, float(mult_cfg.get("radius", 132.0)),
				Color(0.80, 0.74, 1.0), 0.26, 4.0)
		SFX.play("slash", 1.18, -7.0)
		Game.add_shake(4.0)
		return
	if id == "array":
		# R29：玩家换符剑后，影·绝招也得跟着变 —— 照抄成扇形射符。
		# 不补这一支的话 len/thick 都是 0，影·绝招会变成「放了但零判定」的空招。
		var spread := -0.22 + 0.055 * float(i)
		fired.emit(global_position + Vector2(float(facing) * 44.0, -34.0),
			Vector2(float(facing), spread), 520.0)
		SFX.play("slash", 1.55, -11.0)
		if i == 0:
			Game.add_shake(9.0)
			if fx:
				fx.ring(global_position + Vector2(float(facing) * 44.0, -34.0), 8.0, 96.0,
					Color(0.85, 0.78, 1.0), 0.34, 3.0)
		return
	var ln := float(mult_cfg.get("len", 480.0))
	var th := float(mult_cfg.get("thick", 76.0))
	var step := ln * 0.85 if id == "lance" else 0.0
	var c := global_position + Vector2(float(facing) * (40.0 + ln * 0.5 + step * float(i)), -10.0)
	mirror_strike.emit(c, Vector2(ln, th), facing)
	if id == "lance":
		# 枪：与玩家同款的前冲位移
		velocity.x = float(facing) * float(mult_cfg.get("lunge", 300.0))
		invuln_t = maxf(invuln_t, 0.10)
		SFX.play("slash", 1.30, -8.0)
		Game.add_shake(4.0)
	else:
		SFX.play("boss", 1.35, -6.0)
		Game.add_shake(12.0)
	if fx:
		fx.beam(c, Vector2(ln, th * 1.7), facing, Color(0.82, 0.76, 1.0), 0.30)
		fx.burst(c + Vector2(float(facing) * ln * 0.32, 0.0), 12, Color(0.86, 0.80, 1.0), 1.1)


func _enter_phase(p: int) -> void:
	phase = p
	hp = max_hp
	combo = 0
	berserk = false
	berserk_t = 0.0
	berserk_cd = 6.5
	ranged_cd = 1.6
	stagger_meter = 0.0
	_stagger_idle = 0.0
	unblockable = false
	invuln_t = 0.0
	blink_cd = 1.2
	aoe_cd = 2.5
	clone_cd = 3.0
	_queue_skill = ""
	_set_state(PHASE)
	if fx:
		fx.ring(global_position, 12.0, 300.0, Color(1.0, 0.35, 0.42), 0.9, 6.0)
		fx.ring(global_position, 6.0, 180.0, Color(1.0, 0.9, 0.85), 0.7, 4.0)
		fx.burst(global_position, 44, Color(1.0, 0.45, 0.5), 1.6)
		fx.text(global_position + Vector2(0, -118.0 * scale_f), "第 %d 阶 段" % p, Color(1.0, 0.62, 0.6), 34, 62)
	Game.add_shake(20.0)
	Game.hitstop(0.18, 0.02)
	SFX.play("boss", 0.78, -2.0)
	# R19b：无相·心魔二阶段 = 「复制法宝」。不逐件还原 12 种法宝，
	# 只抄法宝的两端：一层护盾（守）+ 三连飞剑（攻，见 RANGED 分支）。
	if kind == KIND_BOSS6 and p >= 2:
		shield = maxf(shield, 34.0)
		_shield_idle = 0.0
		move_speed *= 1.08
		mirror_ult_cd = 2.2   # R22：进二阶段先给 2.2 秒缓冲，「影·绝招」随后才会来
		if fx:
			fx.text(global_position + Vector2(0, -150.0 * scale_f), "法 宝 · 借",
				Color(0.80, 0.72, 1.0), 24, 46)
	phase_changed.emit(self, p)


func _flyer_ai(delta: float) -> void:
	var dx: float = player.global_position.x - global_position.x
	var dy: float = player.global_position.y - global_position.y
	var dist: float = Vector2(dx, dy).length()

	match state:
		IDLE, CHASE:
			var hover := home + Vector2(sin(_t * 1.1) * 26.0, sin(_t * 1.7) * 14.0)
			if _player_ok() and dist < aggro_range:
				state = CHASE
				hover = player.global_position + Vector2(-signf(dx) * 110.0, -80.0)
			var to := hover - global_position
			velocity = velocity.lerp(to.limit_length(move_speed * 2.4), 2.4 * delta)
			if absf(dx) > 4.0:
				facing = 1 if dx > 0.0 else -1
			if state == CHASE and dist < attack_range and _cd <= 0.0:
				_set_state(WINDUP)

		WINDUP:
			velocity = velocity.lerp(Vector2(-signf(dx) * 40.0, -20.0), 4.0 * delta)
			if _player_ok():
				facing = 1 if dx > 0.0 else -1
			if st >= windup_t:
				if _player_ok():
					_dive_dir = (player.global_position - global_position).normalized()
				else:
					_dive_dir = Vector2(facing, 0)
				_set_state(ATTACK)
				SFX.play_rand("dash", 0.8, 0.95, -4.0)

		ATTACK:
			atk_age = st
			velocity = _dive_dir * lunge_speed
			if st >= attack_t:
				_set_state(RECOVER)

		RECOVER:
			atk_age = 99.0
			velocity = velocity.lerp(Vector2.ZERO, 2.0 * delta)
			if st >= recover_t:
				_cd = randf_range(0.6, 1.4)
				_set_state(CHASE)


## R10：房间地板是连续的，脚下永远有地 —— 不再需要射线探地
func _ground_ahead() -> bool:
	return true


func _set_state(s: int) -> void:
	state = s
	st = 0.0
	if s == ATTACK:
		atk_age = 0.0
		clashed = false
	if s == STAGGER:
		combo = 0
		unblockable = false
		defend_t = 0.0


# ------------------------------------------------------------------ 战斗接口
func is_alive() -> bool:
	return not dead


func boss_title() -> String:
	match kind:
		KIND_BOSS3:
			return "前 世 身"
		KIND_BOSS2:
			return "剑 冢 守"
		KIND_BOSS4:
			return "尸 解 仙 · 无 相"
		KIND_BOSS5:
			return "域 外 天 魔"
		KIND_BOSS6:
			return "无 相 · 心 魔"
		KIND_BOSS7:
			return "符 祖"
		KIND_BOSS8:
			return "轮 回 使"
		KIND_BOSS9:
			return "钟 楼 旧 主"
	return "镇 钟 力 士"


func phase_count() -> int:
	return phase_max


func current_phase() -> int:
	return phase


func stagger_frac() -> float:
	return clampf(stagger_meter / stagger_max, 0.0, 1.0)


func is_unblockable() -> bool:
	return unblockable and state == ATTACK


## 剑意交锋 / 格挡成功 → 累积硬直度，打满触发长硬直
func add_stagger(v: float) -> bool:
	if dead or state == PHASE:
		return false
	stagger_meter = minf(stagger_max, stagger_meter + v)
	_stagger_idle = 1.5
	_stagger_flash = 1.0
	if stagger_meter >= stagger_max - 0.01:
		stagger_meter = 0.0
		_stagger_idle = 0.0
		if kind == KIND_BOSS3:
			stagger_t = 1.5
		elif kind == KIND_BOSS5:
			stagger_t = 1.4
		elif kind == KIND_BOSS2:
			stagger_t = 1.6
		elif kind == KIND_BOSS4:
			stagger_t = 1.9
		else:
			stagger_t = 1.9 if is_boss else 2.2
		_set_state(STAGGER)
		velocity.x = -facing * 150.0
		if kind != KIND_FLYER:
			velocity.y = -90.0
		if fx:
			fx.ring(global_position, 10.0, 150.0, Color(1.0, 0.85, 0.45), 0.5, 4.0)
			fx.text(global_position + Vector2(0, -72.0 * scale_f), "硬 直 打 破", Color(1.0, 0.86, 0.5), 26, 46)
			fx.burst(global_position, 22, Color(1.0, 0.9, 0.6), 1.0)
		SFX.play("clash_perfect", 0.7, -3.0)
		Game.add_shake(14.0)
		Game.hitstop(0.11, 0.02)
		Game.break_count += 1
		return true
	return false


## 护体罡气交锋（R11）：可被处决的「躯干值」
func add_posture(v: float) -> void:
	if dead:
		return
	_posture_idle = 0.0
	posture = minf(max_posture, posture + v)
	if posture >= max_posture - 0.001:
		_enter_broken()


## R12：护体罡气回落。停手 POSTURE_HOLD 秒后按 POSTURE_DECAY 的比例往掉。
## 单独抽成函数是为了自测能直接喂 delta（不必真等 2 秒）。
func _decay_posture(delta: float) -> void:
	if posture <= 0.0 or broken_t > 0.0 or dead:
		_posture_idle = 0.0
		return
	_posture_idle += delta
	if _posture_idle >= POSTURE_HOLD:
		posture = maxf(0.0, posture - max_posture * POSTURE_DECAY * delta)
func is_broken() -> bool:
	return broken_t > 0.0
func _enter_broken() -> void:
	posture = 0.0
	broken_t = 1.2 if is_boss else 2.0
	_set_state(STAGGER)
	stagger_t = broken_t
	velocity = Vector2.ZERO
	if fx:
		fx.ring(global_position, 12.0, 170.0, Color(1.0, 0.4, 0.4), 0.55, 4.0)
		fx.text(global_position + Vector2(0, -78.0 * scale_f), "道 心 失 守", Color(1.0, 0.45, 0.45), 28, 50)
		SFX.play("clash_perfect", 0.6, -4.0)
func can_execute() -> bool:
	return is_broken() and not dead
func execute_damage() -> int:
	return maxi(1, int(ceil(float(hp) * (0.15 if is_boss else 0.25))))
func reset_posture() -> void:
	posture = 0.0
	broken_t = 0.0
func posture_frac() -> float:
	return clampf(posture / maxf(1.0, max_posture), 0.0, 1.0)


func attack_rect() -> Rect2:
	if state != ATTACK or dead:
		return Rect2()
	if kind == KIND_FLYER:
		var r := 32.0 * scale_f
		return Rect2(global_position - Vector2(r, r), Vector2(r, r) * 2.0)
	var w := 80.0 * scale_f
	var h := 66.0 * scale_f
	var x := global_position.x + 4.0 * scale_f
	if facing < 0:
		x = global_position.x - 4.0 * scale_f - w
	return Rect2(x, global_position.y - 36.0 * scale_f, w, h)


func hurt_rect() -> Rect2:
	var w := 34.0 * scale_f
	var h := 50.0 * scale_f
	if kind == KIND_FLYER:
		w = 30.0 * scale_f
		h = 30.0 * scale_f
	return Rect2(global_position.x - w * 0.5, global_position.y - h * 0.5 - 2.0, w, h)


func attack_age() -> float:
	return atk_age


## R16：是否被挑在空中
func is_airborne() -> bool:
	return air_stun > 0.0


## R32b 封符：定身。Boss 抗性高 —— 时长打 4 折，不然一张符就能白嫖半条血。
func freeze(t: float) -> void:
	if dead or t <= 0.0:
		return
	var real := t
	if is_boss_family():
		real = t * 0.4
	frozen_t = maxf(frozen_t, real)
	velocity = Vector2.ZERO
	combo = 0
	_cd = maxf(_cd, real)
	if fx:
		fx.ring(global_position, 8.0, 46.0 * scale_f, Color(0.66, 0.86, 0.96), 0.35, 3.0)
		fx.text(global_position + Vector2(0, -86.0 * scale_f), "封",
			Color(0.72, 0.90, 1.0), 22, 34)
	SFX.play("clash", 1.6, -10.0)


func is_frozen() -> bool:
	return frozen_t > 0.0


## R16 上挑：把敌人挑起来，期间等同硬直
func add_air_stun(t: float) -> void:
	if dead or t <= 0.0:
		return
	air_stun = maxf(air_stun, t)
	if state != STAGGER and state != PHASE:
		_set_state(STAGGER)
		stagger_t = maxf(stagger_t, t)
	velocity.x *= 0.3
	if kind != KIND_FLYER:
		velocity.y = 0.0


func on_clash(perfect: bool, heavy: bool = false) -> void:
	clashed = true
	_set_state(STAGGER)
	stagger_t = 1.3 if heavy else (0.62 if is_boss else 0.9)
	if perfect:
		stagger_t += 0.18
	velocity.x = -facing * (320.0 if is_boss else 250.0)
	if kind != KIND_FLYER:
		velocity.y = -120.0
	flash = 1.0
	if perfect:
		Game.hitstop(0.12, 0.02)
	else:
		Game.hitstop(0.07, 0.03)


## 被格挡/破防打出的硬直
func stagger(dur: float) -> void:
	if dead:
		return
	_set_state(STAGGER)
	stagger_t = dur
	velocity.x = -facing * (180.0 if is_boss else 210.0)
	if kind != KIND_FLYER:
		velocity.y = -80.0
	flash = 1.0


func hurt(dmg_amount: int, from_pos: Vector2, heavy: bool = false, tag: String = "") -> void:
	if dead:
		return
	if state == PHASE:
		return
	# R16 浮空：被挑在空中时受击加伤；下劈把浮空目标直接砸下来（额外 +2）
	var airborne: bool = is_airborne()
	if airborne:
		dmg_amount = int(ceil(float(dmg_amount) * AIR_HURT_MUL))
	if tag == "down" and airborne:
		dmg_amount += 2
		air_stun = 0.0
		if fx:
			fx.text(global_position + Vector2(0, -92.0 * scale_f), "砸 落", Color(1.0, 0.86, 0.5), 20, 36)
			fx.ring(global_position + Vector2(0, 10.0), 6.0, 76.0, Color(1.0, 0.86, 0.55), 0.3, 3.0)
		Game.add_shake(7.0)
	if invuln_t > 0.0:
		if fx:
			fx.text(global_position + Vector2(0, -76.0 * scale_f), "闪避", Color(0.7, 0.86, 1.0), 18, 30)
		return
	# R18 护盾型：先削护盾，护盾没破之前一点血都不掉
	if shield > 0.0:
		shield = maxf(0.0, shield - maxf(1.0, float(dmg_amount)) * SHIELD_HIT_COST)
		_shield_idle = 0.0
		flash = 0.6
		if fx:
			fx.sparks(global_position + Vector2(0, -16.0 * scale_f), Vector2.UP, 8,
				Color(0.62, 0.88, 1.0), 0.6)
			if shield <= 0.0:
				fx.ring(global_position, 8.0, 96.0, Color(0.7, 0.92, 1.0), 0.35, 3.0)
				fx.text(global_position + Vector2(0, -84.0 * scale_f), "护 盾 破",
					Color(0.72, 0.92, 1.0), 21, 38)
			else:
				fx.text(global_position + Vector2(0, -84.0 * scale_f), "护 盾 %d" % int(shield),
					Color(0.62, 0.84, 1.0), 18, 30)
		SFX.play("clash", 0.8, -8.0)
		Game.add_shake(3.0)
		return
	# R18 丹修 / 自爆型：倒计时里挨刀 = 自爆被打断（处决就在这里生效）
	if state == FUSE:
		_fuse_canceled = true
		broken_t = 0.0
		_set_state(STAGGER)
		stagger_t = 1.3
		if fx:
			fx.ring(global_position, 10.0, 130.0, Color(1.0, 0.85, 0.45), 0.4, 3.5)
			fx.text(global_position + Vector2(0, -100.0 * scale_f), "自 爆 中 断",
				Color(1.0, 0.86, 0.5), 22, 40)
		SFX.play("clash_perfect", 0.8, -3.0)
		Game.add_shake(9.0)
	# 凝罡·开山 / 剑气纵横：直接砸开防御，既挡不住也弹反不了
	if state == DEFEND and heavy:
		defend_t = 0.0
		defend_hits = 0
		if fx:
			fx.ring(global_position, 8.0, 110.0, Color(1.0, 0.82, 0.45), 0.35, 4.0)
			fx.text(global_position + Vector2(0, -84.0 * scale_f), "破 防", Color(1.0, 0.85, 0.5), 24, 40)
		SFX.play("clash_perfect", 0.68, -3.0)
		Game.add_shake(10.0)
		_set_state(STAGGER)
		stagger_t = 0.7

	# 防御姿态：挡下攻击；三阶段以上有 50% 概率弹反
	if state == DEFEND:
		defend_hits += 1
		# R16：敌方读标签 —— Boss 对「突刺」有明显招架倾向，逼玩家换段
		var pc := PARRY_CHANCE
		if tag == "thrust":
			pc = minf(0.92, pc * 1.7)
		if _tier() >= 3 and randf() < pc:
			unblockable = false
			_set_state(RECOVER)
			if fx:
				fx.ring(global_position, 8.0, 96.0, Color(1.0, 0.85, 0.4), 0.35, 3.5)
				fx.text(global_position + Vector2(0, -82.0 * scale_f), "弹 反", Color(1.0, 0.88, 0.45), 26, 46)
			SFX.play("clash_perfect", 0.85, -2.0)
			Game.add_shake(12.0)
			Game.hitstop(0.1, 0.02)
			parried.emit(self)
			return
		if fx:
			fx.sparks(global_position + Vector2(-float(facing) * 20.0, -12.0), Vector2.UP, 10,
				Color(0.6, 0.86, 1.0), 0.7)
			fx.text(global_position + Vector2(0, -82.0 * scale_f), "挡 下", Color(0.72, 0.9, 1.0), 20, 34)
		SFX.play("clash", 0.7, -9.0)
		Game.add_shake(4.0)
		velocity.x = -float(facing) * 70.0
		if defend_hits >= 2:
			defend_t = 0.0
		return

	hp -= dmg_amount
	flash = 1.0
	var dir := signf(global_position.x - from_pos.x)
	if dir == 0.0:
		dir = -facing
	velocity.x = dir * (120.0 if is_boss else 220.0)
	if kind != KIND_FLYER:
		velocity.y = -80.0
	if fx:
		fx.burst(global_position, 10, Color(0.95, 0.85, 0.6), 0.7)
	SFX.play_rand("hit", 0.9, 1.15, -4.0)
	Game.add_shake(4.0)
	Game.hitstop(0.045, 0.06)
	if hp <= 0:
		if is_boss_family() and phase < phase_max:
			_enter_phase(phase + 1)
			return
		_die()


func _die() -> void:
	dead = true
	_death_t = 0.0
	collision_layer = 0
	collision_mask = 0
	if fx:
		fx.burst(global_position, 34 if is_boss else 18, Color(0.85, 0.95, 1.0), 1.2)
		fx.ring(global_position, 10.0, 120.0 if is_boss else 70.0, Color(0.9, 0.97, 1.0), 0.5, 3.5)
	SFX.play("death", 1.15 if not is_boss else 0.7, -2.0)
	Game.add_shake(10.0 if is_boss else 5.0)
	killed.emit(self)


func reset(pos: Vector2) -> void:
	global_position = pos
	velocity = Vector2.ZERO
	hp = max_hp
	dead = false
	_death_t = -1.0
	flash = 0.0
	state = IDLE
	st = 0.0
	combo = 0
	stagger_t = 0.62 if is_boss else 0.9
	stagger_meter = 0.0
	_stagger_idle = 0.0
	_stagger_flash = 0.0
	posture = 0.0
	broken_t = 0.0
	phase = 1
	berserk = false
	berserk_t = 0.0
	berserk_cd = 0.0
	defend_t = 0.0
	defend_hits = 0
	ranged_cd = 0.0
	unblockable = false
	invuln_t = 0.0
	_intent_cd = 0.0
	blink_cd = 0.0
	aoe_cd = 0.0
	clone_cd = 0.0
	_queue_skill = ""
	_aoe_t = 0.0
	_life = CLONE_LIFE if kind == KIND_CLONE else -1.0
	_trail.clear()
	_cd = 0.0
	collision_layer = 4
	collision_mask = 1
	modulate = Color.WHITE


# ------------------------------------------------------------------ 绘制
func _blade_angle() -> float:
	match state:
		WINDUP:
			var p := clampf(st / windup_t, 0.0, 1.0)
			return lerpf(26.0, -102.0, ease(p, 0.5))
		ATTACK:
			var p := clampf(st / attack_t, 0.0, 1.0)
			return lerpf(-102.0, 52.0, ease(p, 0.25))
		RECOVER:
			var p := clampf(st / recover_t, 0.0, 1.0)
			return lerpf(52.0, 26.0, p)
		STAGGER:
			return 70.0
	return 26.0


func _draw() -> void:
	var s := scale_f
	var o := Vector2.ZERO
	var body := Color(0.075, 0.085, 0.11)
	var eye := Color(1.0, 0.3, 0.34)

	# 2.5D：整只敌人按深度上移 + 缩放
	SpaceScript.apply_draw(self, depth)
	# R16：被挑在空中时整体上抬
	if _air_lift > 0.01:
		o.y -= _air_lift

	# R32b 封符：定身时罩一层霜环（照抄「浮空」的画法：不改判定，只加一层视觉）
	if frozen_t > 0.0:
		var fa := 0.32 + 0.22 * sin(_t * 10.0)
		draw_arc(o + Vector2(0, -16.0) * s, 32.0 * s, 0.0, TAU, 28,
			Color(0.66, 0.88, 1.0, fa), 2.4, true)
		draw_circle(o + Vector2(0, -16.0) * s, 27.0 * s, Color(0.55, 0.85, 1.0, 0.10))

	if kind == KIND_FLYER:
		_draw_flyer(o, s, body, eye)
		return

	if ghost:
		body = Color(0.14, 0.28, 0.42)
		eye = Color(0.72, 0.95, 1.0)

	if is_echo:
		# 暗色剪影 + 玩家武器色的眼与轮廓光
		body = Color(0.030, 0.034, 0.048)
		eye = Color.from_hsv(echo_hue, 0.82, 1.0)

	# 2.5D：接地阴影
	_shadow(Vector2(0, 26.0 * s), 18.0 * s, 5.2 * s, SpaceScript.shadow_alpha(depth))

	# R18：变奏标记 / 精英剪影（精英不走下面的杂兵画法，直接返回）
	if variant != VAR_NONE:
		_draw_variant_badge(o, s)
	if is_elite():
		_draw_elite(o, s)
		return

	# 闪现：只剩一团残光
	if state == BLINK:
		var bp := clampf(st / 0.24, 0.0, 1.0)
		draw_circle(o + Vector2(0, -10) * s, 30.0 * s * (0.6 + bp * 0.9),
			Color(0.55, 0.85, 1.0, 0.22 * (1.0 - bp)))
		draw_arc(o + Vector2(0, -10) * s, 26.0 * s * (1.0 + bp), 0.0, TAU, 26,
			Color(0.7, 0.95, 1.0, 0.55 * (1.0 - bp)), 2.0, true)
		return

	# 闪避残影
	for i in _trail.size():
		var tp: Vector2 = _trail[i] - global_position
		draw_circle(tp + Vector2(0, -6) * s, 15.0 * s, Color(0.55, 0.78, 1.0, 0.05 + 0.02 * float(i)))

	var bob := 0.0
	if state == IDLE or state == CHASE:
		bob = sin(_t * 5.0) * 1.2
	o.y += bob

	if is_boss:
		var aura := 0.35 + 0.25 * sin(_t * 3.0)
		var ac := Color(0.9, 0.2, 0.25)
		if kind == KIND_BOSS2:
			body = Color(0.115, 0.088, 0.155)
			eye = Color(0.82, 0.42, 1.0)
			ac = Color(0.75, 0.30, 1.0) if phase >= 2 else Color(0.85, 0.28, 0.5)
			if phase >= 3:
				ac = Color(1.0, 0.26, 0.45)
			if berserk:
				ac = Color(1.0, 0.32, 0.18)
				aura = 0.55 + 0.45 * sin(_t * 12.0)
		elif kind == KIND_BOSS3:
			body = Color(0.075, 0.10, 0.145)
			eye = Color(0.62, 0.96, 1.0)
			ac = Color(0.35, 0.80, 1.0)
			if phase == 2:
				ac = Color(0.42, 0.98, 0.92)
			elif phase >= 3:
				ac = Color(0.78, 0.58, 1.0)
			if berserk:
				ac = Color(1.0, 0.45, 0.22)
				aura = 0.55 + 0.45 * sin(_t * 12.0)
		elif kind == KIND_BOSS4:
			# 尸解仙：石青重甲 + 金铜符纹
			body = Color(0.14, 0.145, 0.16)
			eye = Color(1.0, 0.78, 0.35)
			ac = Color(0.92, 0.72, 0.34)
			if phase >= 2:
				ac = Color(1.0, 0.55, 0.28)
			if berserk:
				ac = Color(1.0, 0.40, 0.20)
				aura = 0.55 + 0.45 * sin(_t * 12.0)
		elif kind == KIND_BOSS5:
			# 域外天魔：墨紫 + 苍白眼
			body = Color(0.055, 0.045, 0.085)
			eye = Color(0.95, 0.93, 1.0)
			ac = Color(0.68, 0.42, 1.0)
			if phase == 2:
				ac = Color(0.45, 0.55, 1.0)
			elif phase >= 3:
				ac = Color(1.0, 0.35, 0.62)
			if berserk:
				ac = Color(1.0, 0.30, 0.18)
				aura = 0.55 + 0.45 * sin(_t * 12.0)
		elif kind == KIND_BOSS6:
			# 无相·心魔：**照着你画**——暗色剪影 + 你手里那把武器的颜色
			body = Color(0.028, 0.032, 0.046)
			eye = Color.from_hsv(echo_hue, 0.85, 1.0)
			ac = Color.from_hsv(echo_hue, 0.72, 0.95)
			if phase >= 2:
				# 二阶段「借宝」：轮廓光掺一点法宝的青色
				ac = ac.lerp(Color(0.55, 0.78, 1.0), 0.45)
		elif kind == KIND_BOSS9:
			# R39 钟楼旧主：**石灰 + 铜锈**的体修老匠 —— 全作最朴素的一只 Boss。
			# 他不发光、不邪气，只有一件洗得发白的旧袍和一双铜色的手。
			# 视觉上也刻意与其它 Boss 拉开：别人越到后面越「妖」，他越到后面越「旧」。
			body = Color(0.145, 0.132, 0.118)
			eye = Color(0.95, 0.78, 0.42)
			ac = Color(0.72, 0.60, 0.38)
			if phase >= 2:
				ac = Color(0.92, 0.62, 0.32)
			if berserk:
				ac = Color(1.0, 0.45, 0.22)
				aura = 0.55 + 0.45 * sin(_t * 12.0)
		draw_circle(o + Vector2(0, -10) * s, 46.0 * s, Color(ac.r, ac.g, ac.b, 0.030 * aura))
		draw_circle(o + Vector2(0, -10) * s, 30.0 * s, Color(ac.r, ac.g, ac.b, 0.045 * aura))
		# R19b：镜子本身 —— 身后一圈竖立的椭圆，越近越亮
		if kind == KIND_BOSS6:
			var mg := 0.42 + 0.20 * sin(_t * 2.2)
			draw_arc(o + Vector2(0, -6) * s, 52.0 * s, 0.0, TAU, 48,
				Color(ac.r, ac.g, ac.b, 0.16 + 0.10 * mg), 2.4, true)
			draw_arc(o + Vector2(0, -6) * s, 58.0 * s, _t * 0.6, _t * 0.6 + PI * 1.35, 30,
				Color(ac.r, ac.g, ac.b, 0.30), 1.6, true)
		if berserk:
			draw_arc(o + Vector2(0, -8) * s, 54.0 * s, _t * 3.0, _t * 3.0 + PI * 1.2, 24,
				Color(1.0, 0.35, 0.2, 0.35), 2.5, true)

	# 披风 / 躯干
	var back := -facing
	var cloak := PackedVector2Array([
		o + Vector2(-11, -20) * s, o + Vector2(-16, -4) * s, o + Vector2(-14, 12) * s,
		o + Vector2(-9, 25) * s, o + Vector2(9, 25) * s, o + Vector2(14, 12) * s,
		o + Vector2(16, -4) * s, o + Vector2(11, -20) * s,
	])
	draw_colored_polygon(cloak, body)
	var closed := cloak.duplicate()
	closed.append(cloak[0])
	draw_polyline(closed, Color(0.24, 0.33, 0.42, 0.65), 1.3, true)

	# 肩甲
	var shoulder := Color(0.13, 0.15, 0.19)
	draw_circle(o + Vector2(-9, -14) * s, 6.0 * s, shoulder)
	draw_circle(o + Vector2(9, -14) * s, 6.0 * s, shoulder)

	# 头
	var head := o + Vector2(0, -22) * s
	draw_circle(head, 10.0 * s, Color(0.09, 0.10, 0.13))
	# 角
	var horn_c := Color(0.16, 0.18, 0.23)
	draw_colored_polygon(PackedVector2Array([
		head + Vector2(-4, -6) * s, head + Vector2(-13, -20) * s, head + Vector2(-1, -8) * s,
	]), horn_c)
	draw_colored_polygon(PackedVector2Array([
		head + Vector2(4, -6) * s, head + Vector2(13, -20) * s, head + Vector2(1, -8) * s,
	]), horn_c)

	# 眼睛（蓄力时越来越亮）
	var glow := 0.0
	if state == WINDUP:
		glow = clampf(st / windup_t, 0.0, 1.0)
	var ec := eye
	ec = ec.lerp(Color(1.0, 0.95, 0.85), glow)
	draw_circle(head + Vector2(-4.2, 0.5) * s, (2.2 + glow * 1.4) * s, ec)
	draw_circle(head + Vector2(4.2, 0.5) * s, (2.2 + glow * 1.4) * s, ec)
	if glow > 0.05:
		draw_circle(head + Vector2(0, 0.5) * s, (12.0 + glow * 10.0) * s, Color(1.0, 0.25, 0.3, 0.06 * glow))

	# 蓄力提示弧
	if state == WINDUP:
		var p := clampf(st / windup_t, 0.0, 1.0)
		var rr := 30.0 * s
		draw_arc(o, rr, -PI * 0.5, -PI * 0.5 + TAU * p, 32, Color(1.0, 0.42, 0.45, 0.85), 2.5, true)
		# 刀路预示
		var a0 := deg_to_rad(-102.0)
		var a1 := deg_to_rad(52.0)
		var pts := PackedVector2Array()
		for i in range(13):
			var ang: float = lerpf(a0, a1, i / 12.0)
			pts.append(o + Vector2(facing * cos(ang), sin(ang)) * (46.0 * s))
		draw_polyline(pts, Color(1.0, 0.45, 0.45, 0.10 + 0.28 * p), 2.0, true)

	# 刀
	var hand := o + Vector2(facing * 6.0, -6.0) * s
	var a := deg_to_rad(_blade_angle())
	var dirv := Vector2(facing * cos(a), sin(a)).normalized()
	# R19b：无相·心魔的刀**按玩家那把武器画**——长枪长、双刀短而双持
	var blade_len := 52.0
	var dual_blade := false
	if kind == KIND_BOSS6 and mirror_weapon != "":
		blade_len = 52.0 * WeaponScript.reach_mul(mirror_weapon) * 1.30
		dual_blade = mirror_weapon == "dual"
	var tip := hand + dirv * blade_len * s
	var perp := Vector2(-dirv.y, dirv.x) * 2.6 * s
	var blade_col := Color(0.72, 0.76, 0.84)
	if kind == KIND_BOSS6:
		blade_col = Color.from_hsv(echo_hue, 0.35, 0.92)
	if state == WINDUP:
		blade_col = blade_col.lerp(Color(1.0, 0.55, 0.5), clampf(st / windup_t, 0.0, 1.0))
		draw_line(hand, tip, Color(1.0, 0.35, 0.35, 0.22), 12.0 * s, true)
	draw_line(hand, tip, Color(0.6, 0.85, 1.0, 0.08), 10.0 * s, true)
	draw_colored_polygon(PackedVector2Array([
		hand + perp, tip + perp * 0.3, tip - perp * 0.3, hand - perp,
	]), blade_col)
	if dual_blade:
		# 双刀的镜像：反手再一把（短一截，看起来像左右开弓）
		var hand2 := o + Vector2(-facing * 6.0, -4.0) * s
		var tip2 := hand2 + Vector2(-dirv.x, dirv.y) * blade_len * 0.86 * s
		draw_colored_polygon(PackedVector2Array([
			hand2 + perp, tip2 + perp * 0.3, tip2 - perp * 0.3, hand2 - perp,
		]), blade_col.darkened(0.18))

	# 攻击刀光
	if state == ATTACK:
		var p := clampf(st / attack_t, 0.0, 1.0)
		var alpha := (1.0 - p * 0.7) * 0.8
		var a1b := _blade_angle()
		var pts2 := PackedVector2Array()
		var steps := 14
		for i in range(steps + 1):
			var ang: float = deg_to_rad(lerpf(-102.0, a1b, float(i) / steps))
			pts2.append(o + Vector2(facing * cos(ang), sin(ang)) * (70.0 * s))
		for i in range(steps, -1, -1):
			var ang: float = deg_to_rad(lerpf(-102.0, a1b, float(i) / steps))
			pts2.append(o + Vector2(facing * cos(ang), sin(ang)) * (50.0 * s))
		if pts2.size() >= 3:
			draw_colored_polygon(pts2, Color(0.9, 0.93, 1.0, alpha * 0.45))

	# 尸解仙重甲横纹
	if kind == KIND_BOSS4:
		for i in 3:
			var yy := (-14.0 + float(i) * 10.0) * s
			draw_line(o + Vector2(-11.0 * s, yy), o + Vector2(11.0 * s, yy),
				Color(0.42, 0.40, 0.34, 0.55), 1.6)

	# Boss 血纹
	if is_boss:
		var pulse := 0.4 + 0.3 * sin(_t * 3.0)
		draw_line(o + Vector2(-6, -10) * s, o + Vector2(-2, 8) * s, Color(1.0, 0.3, 0.3, pulse), 2.0 * s)
		draw_line(o + Vector2(6, -10) * s, o + Vector2(3, 6) * s, Color(1.0, 0.3, 0.3, pulse), 2.0 * s)
		draw_arc(o, 34.0 * s, 0.0, TAU, 40, Color(0.9, 0.25, 0.3, 0.10), 4.0, true)

	# 防御 / 弹反姿态：正面护盾
	if state == DEFEND:
		var g := 0.55 + 0.45 * sin(_t * 9.0)
		var cx := o + Vector2(float(facing) * 22.0, -8.0) * s
		draw_arc(cx, 30.0 * s, -PI * 0.55, PI * 0.55, 22, Color(0.6, 0.86, 1.0, 0.55 + 0.25 * g), 3.0, true)
		draw_arc(cx, 24.0 * s, -PI * 0.45, PI * 0.45, 18, Color(0.85, 0.95, 1.0, 0.35), 1.6, true)
		if phase >= 3:
			draw_arc(cx, 36.0 * s, -PI * 0.5, PI * 0.5, 20, Color(1.0, 0.88, 0.45, 0.35 * g), 1.8, true)

	# 蓄力远程：手心聚球
	if state == RANGED:
		var p := clampf(st / 0.46, 0.0, 1.0)
		var hp2 := o + Vector2(float(facing) * 26.0, -18.0) * s
		draw_circle(hp2, (5.0 + 9.0 * p) * s, Color(0.85, 0.5, 1.0, 0.30 * p))
		draw_circle(hp2, (2.0 + 4.0 * p) * s, Color(0.95, 0.85, 1.0, 0.85 * p))

	# 范围震波：贴地扩散的警示圈（跳起来或冲出圈外才安全）
	if state == AOE:
		var ap := clampf(st / 0.85, 0.0, 1.0)
		var rr := lerpf(18.0, AOE_RADIUS, ease(ap, 0.45))
		var gx := Vector2(0, 20.0)
		var fill := PackedVector2Array()
		for i in 33:
			var a3 := TAU * float(i) / 32.0
			fill.append(gx + Vector2(cos(a3) * rr, sin(a3) * rr * 0.26))
		draw_colored_polygon(fill, Color(1.0, 0.55, 0.3, 0.04 + 0.09 * ap))
		var ringp := PackedVector2Array()
		for i in 49:
			var a2 := TAU * float(i) / 48.0
			ringp.append(gx + Vector2(cos(a2) * rr, sin(a2) * rr * 0.26))
		draw_polyline(ringp, Color(1.0, 0.62, 0.34, 0.45 + 0.4 * sin(_t * 20.0)), 3.0, true)
		var ring2 := PackedVector2Array()
		for i in 49:
			var a4 := TAU * float(i) / 48.0
			ring2.append(gx + Vector2(cos(a4) * rr * 0.6, sin(a4) * rr * 0.26 * 0.6))
		draw_polyline(ring2, Color(1.0, 0.72, 0.42, 0.30), 2.0, true)
		draw_circle(o + Vector2(0, -6) * s, 16.0 * s * (0.5 + ap), Color(1.0, 0.78, 0.45, 0.35 * ap))

	# 残血「双技」形态：外圈红环
	if is_boss and hp <= int(ceil(float(max_hp) * 0.2)):
		var er := (40.0 + 4.0 * sin(_t * 9.0)) * s
		draw_arc(o + Vector2(0, -10) * s, er, 0.0, TAU, 32, Color(1.0, 0.35, 0.3, 0.45), 2.0, true)

	# 硬直度条（头顶）
	if stagger_meter > 0.01 and not dead:
		var bw := 46.0 * s
		var by := -52.0 * s
		var fl := _stagger_flash
		draw_rect(Rect2(-bw * 0.5, by, bw, 4.0), Color(0.05, 0.06, 0.08, 0.85))
		draw_rect(Rect2(-bw * 0.5, by, bw * stagger_frac(), 4.0),
			Color(1.0, 0.78, 0.34).lerp(Color(1.0, 1.0, 0.85), fl * 0.6))
		draw_rect(Rect2(-bw * 0.5, by, bw * stagger_frac(), 1.2), Color(1, 1, 1, 0.35))


## R18：怨灵只在阴界「实体化」—— 阳界只剩一点残影（也打不到，见 lane_ok）
func is_yin_visible() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	return SpaceScript.lane_ok(float(player.depth), depth)


## R18：变奏标记 —— 头顶一枚小徽记，形状 + 颜色双编码（不读文字也能分出「这只不一样」）
func _draw_variant_badge(o: Vector2, s: float) -> void:
	var col := Color(0.7, 0.85, 1.0)
	match variant:
		VAR_SHIELD:
			col = Color(0.55, 0.86, 1.0)
		VAR_SUMMON:
			col = Color(0.72, 1.0, 0.72)
		VAR_BOMB:
			col = Color(1.0, 0.62, 0.34)
		VAR_READ:
			col = Color(0.86, 0.62, 1.0)
		VAR_RAGE:
			col = Color(1.0, 0.42, 0.38)
	var c := o + Vector2(0, -62.0) * s
	var pulse := 0.60 + 0.40 * sin(_t * 6.0)
	var a := 0.55 + 0.35 * pulse
	var cc := Color(col.r, col.g, col.b, a)
	var r := 8.0 * s
	# 底环：极淡，只负责让小徽记在暗底上不飘
	draw_arc(c, r, 0.0, TAU, 16, Color(col.r, col.g, col.b, 0.16), 1.0, true)
	match variant:
		VAR_SHIELD:
			# 六边形 —— 护盾
			var hex := PackedVector2Array()
			for i in 7:
				var ang := -PI * 0.5 + TAU * float(i) / 6.0
				hex.append(c + Vector2(cos(ang), sin(ang)) * r * 0.86)
			draw_polyline(hex, cc, 1.8, true)
		VAR_SUMMON:
			# 三个小点 —— 召来的东西
			for i in 3:
				var ang := -PI * 0.5 + TAU * float(i) / 3.0
				draw_circle(c + Vector2(cos(ang), sin(ang)) * r * 0.52, 2.1 * s, cc)
		VAR_BOMB:
			# 向下的三角 —— 要炸
			var tri := PackedVector2Array([
				c + Vector2(-r * 0.80, -r * 0.45),
				c + Vector2(r * 0.80, -r * 0.45),
				c + Vector2(0.0, r * 0.78)])
			draw_colored_polygon(tri, Color(col.r, col.g, col.b, a * 0.32))
			draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), cc, 1.6, true)
		VAR_READ:
			# 一只眼 —— 读招
			draw_arc(c + Vector2(0, -2.0) * s, r * 0.82, PI * 0.15, PI * 0.85, 10, cc, 1.6, true)
			draw_arc(c + Vector2(0, 2.0) * s, r * 0.82, -PI * 0.85, -PI * 0.15, 10, cc, 1.6, true)
			draw_circle(c, 2.2 * s, cc)
		VAR_RAGE:
			# 三根上挑的刺 —— 狂暴
			for i in 3:
				var dx := (float(i) - 1.0) * r * 0.55
				draw_line(c + Vector2(dx, r * 0.55), c + Vector2(dx, -r * 0.75), cc, 1.7, true)
	if variant == VAR_BOMB and state == FUSE:
		# 自爆倒计时：环越收越紧
		var k := clampf(_fuse_t / FUSE_TIME, 0.0, 1.0)
		draw_arc(c, 12.0 * s * (1.0 - k * 0.55), -PI * 0.5, -PI * 0.5 + TAU * k, 18,
			Color(1.0, 0.5, 0.28, 0.9), 2.2, true)


## R18：六种精英的剪影 —— 形状 + 颜色双编码，一眼分得清谁是谁
func _draw_elite(o: Vector2, s: float) -> void:
	var vis := 1.0
	if kind == KIND_YUANLING and not is_yin_visible():
		vis = 0.20
	var body := Color(0.10, 0.115, 0.145)
	var trim := Color(0.72, 0.82, 0.96)
	match kind:
		KIND_JIANXIU:
			body = Color(0.10, 0.115, 0.145)
			trim = Color(0.74, 0.82, 0.96)
		KIND_FUXIU:
			body = Color(0.145, 0.105, 0.070)
			trim = Color(1.0, 0.72, 0.36)
		KIND_DANXIU:
			body = Color(0.165, 0.075, 0.075)
			trim = Color(1.0, 0.46, 0.38)
		KIND_YUANLING:
			body = Color(0.065, 0.115, 0.150)
			trim = Color(0.60, 0.96, 0.96)
		KIND_ZHIREN:
			body = Color(0.195, 0.185, 0.150)
			trim = Color(0.96, 0.90, 0.70)
		KIND_SHIJUI:
			body = Color(0.100, 0.125, 0.100)
			trim = Color(0.64, 0.86, 0.52)

	var b := Color(body.r, body.g, body.b, vis)
	var t := Color(trim.r, trim.g, trim.b, vis)

	# 脚下的精英光环（比杂兵多一圈，玩家一眼知道「这只不一样」）
	draw_arc(o + Vector2(0, 24.0) * s, 22.0 * s, 0.0, TAU, 26,
		Color(t.r, t.g, t.b, 0.28 * vis), 1.8, true)

	match kind:
		KIND_JIANXIU:
			# 高瘦：窄肩 + 背后两把交叉的飞剑
			draw_colored_polygon(PackedVector2Array([
				o + Vector2(-9, -18) * s, o + Vector2(-13, 22) * s,
				o + Vector2(13, 22) * s, o + Vector2(9, -18) * s,
			]), b)
			for sx in [-1.0, 1.0]:
				draw_line(o + Vector2(sx * 4.0, -14) * s, o + Vector2(sx * 22.0, 20) * s,
					t, 2.4 * s, true)
				draw_line(o + Vector2(sx * 22.0, 20) * s, o + Vector2(sx * 26.0, 12) * s,
					Color(t.r, t.g, t.b, 0.6 * vis), 1.6 * s, true)
			draw_circle(o + Vector2(0, -24) * s, 8.0 * s, Color(0.09, 0.10, 0.13, vis))
			draw_arc(o + Vector2(0, -24) * s, 9.0 * s, 0.0, TAU, 16, t, 1.4, true)
		KIND_FUXIU:
			# 宽袍 + 手里一张符
			draw_colored_polygon(PackedVector2Array([
				o + Vector2(-11, -18) * s, o + Vector2(-19, 24) * s,
				o + Vector2(19, 24) * s, o + Vector2(11, -18) * s,
			]), b)
			var hand := o + Vector2(float(facing) * 16.0, -6.0) * s
			draw_rect(Rect2(hand + Vector2(-4, -7) * s, Vector2(8, 14) * s), t)
			draw_rect(Rect2(hand + Vector2(-4, -7) * s, Vector2(8, 14) * s),
				Color(1, 0.95, 0.8, vis), false, 1.0)
			draw_circle(o + Vector2(0, -24) * s, 8.0 * s, Color(0.11, 0.09, 0.07, vis))
			draw_arc(o + Vector2(0, -24) * s, 10.0 * s, -PI, 0.0, 14, t, 1.6, true)
		KIND_DANXIU:
			# 圆腹 + 腰上挂葫芦
			draw_circle(o + Vector2(0, 2) * s, 15.0 * s, b)
			draw_circle(o + Vector2(0, -18) * s, 8.0 * s, Color(0.11, 0.07, 0.07, vis))
			var gourd := o + Vector2(float(facing) * -16.0, 4.0) * s
			draw_circle(gourd, 6.5 * s, t)
			draw_circle(gourd + Vector2(0, -7) * s, 4.0 * s, t)
			draw_line(gourd + Vector2(0, -11) * s, gourd + Vector2(0, -14) * s,
				Color(t.r, t.g, t.b, 0.7 * vis), 1.6 * s, true)
			if state == FUSE:
				var k2 := clampf(_fuse_t / FUSE_TIME, 0.0, 1.0)
				draw_arc(o + Vector2(0, 2) * s, 20.0 * s, -PI * 0.5,
					-PI * 0.5 + TAU * k2, 20, Color(1.0, 0.5, 0.3, 0.9), 2.4, true)
		KIND_YUANLING:
			# 无腿：上半身实、下半身散成飘带
			draw_colored_polygon(PackedVector2Array([
				o + Vector2(-10, -20) * s, o + Vector2(-14, 6) * s,
				o + Vector2(-6, 18) * s, o + Vector2(0, 26) * s,
				o + Vector2(6, 18) * s, o + Vector2(14, 6) * s,
				o + Vector2(10, -20) * s,
			]), b)
			for i in 3:
				var yy := 8.0 + float(i) * 6.0
				var w := 12.0 - float(i) * 2.0
				draw_line(o + Vector2(-w, yy) * s, o + Vector2(w, yy) * s,
					Color(t.r, t.g, t.b, (0.5 - float(i) * 0.13) * vis), 1.4 * s, true)
			draw_circle(o + Vector2(0, -24) * s, 8.5 * s, Color(0.05, 0.09, 0.12, vis))
			draw_circle(o + Vector2(-3.2, -25) * s, 1.8 * s, Color(t.r, t.g, t.b, vis))
			draw_circle(o + Vector2(3.2, -25) * s, 1.8 * s, Color(t.r, t.g, t.b, vis))
		KIND_ZHIREN:
			# 纸片身：方形躯干 + 折角下摆 + 竹骨
			draw_colored_polygon(PackedVector2Array([
				o + Vector2(-11, -18) * s, o + Vector2(-11, 14) * s,
				o + Vector2(-4, 22) * s, o + Vector2(4, 22) * s,
				o + Vector2(11, 14) * s, o + Vector2(11, -18) * s,
			]), b)
			draw_line(o + Vector2(-11, -6) * s, o + Vector2(11, -6) * s,
				Color(t.r, t.g, t.b, 0.55 * vis), 1.2 * s, true)
			draw_line(o + Vector2(-11, 8) * s, o + Vector2(11, 8) * s,
				Color(t.r, t.g, t.b, 0.45 * vis), 1.2 * s, true)
			draw_line(o + Vector2(0, -18) * s, o + Vector2(0, 22) * s,
				Color(t.r, t.g, t.b, 0.35 * vis), 1.0 * s, true)
			draw_circle(o + Vector2(0, -26) * s, 7.0 * s, Color(0.13, 0.12, 0.10, vis))
			draw_line(o + Vector2(-3, -27) * s, o + Vector2(-1, -27) * s,
				Color(t.r, t.g, t.b, vis), 1.4 * s, true)
			draw_line(o + Vector2(1, -27) * s, o + Vector2(3, -27) * s,
				Color(t.r, t.g, t.b, vis), 1.4 * s, true)
		KIND_SHIJUI:
			# 佝偻宽肩 + 胸口缝合线
			draw_colored_polygon(PackedVector2Array([
				o + Vector2(-20, -14) * s, o + Vector2(-16, 24) * s,
				o + Vector2(16, 24) * s, o + Vector2(20, -14) * s,
			]), b)
			draw_circle(o + Vector2(0, -20) * s, 9.0 * s, Color(0.09, 0.10, 0.09, vis))
			for i in 3:
				var yy2 := -6.0 + float(i) * 7.0
				draw_line(o + Vector2(-7, yy2) * s, o + Vector2(7, yy2) * s,
					Color(t.r, t.g, t.b, 0.55 * vis), 1.3 * s, true)
			draw_line(o + Vector2(-13, -12) * s, o + Vector2(-20, 20) * s,
				Color(t.r, t.g, t.b, 0.35 * vis), 2.2 * s, true)
			draw_line(o + Vector2(13, -12) * s, o + Vector2(20, 20) * s,
				Color(t.r, t.g, t.b, 0.35 * vis), 2.2 * s, true)

	# 护体罡气环（精英专用：一眼看出「这只还能挨几下」）
	if posture > 0.5 and not dead:
		var pf := posture_frac()
		draw_arc(o + Vector2(0, -6) * s, 30.0 * s, -PI * 0.5, -PI * 0.5 + TAU * pf, 30,
			Color(0.55, 0.85, 1.0, 0.55 * vis), 2.2, true)
	# 护盾（变奏）
	if shield > 0.0:
		var sf := clampf(shield / SHIELD_AMOUNT, 0.0, 1.0)
		draw_arc(o + Vector2(0, -4) * s, 34.0 * s, 0.0, TAU, 30,
			Color(0.60, 0.88, 1.0, 0.30 + 0.35 * sf), 2.0 + 1.5 * sf, true)
	# 硬直度条（与杂兵同一套）
	if stagger_meter > 0.01 and not dead:
		var bw := 52.0 * s
		var by := -58.0 * s
		draw_rect(Rect2(-bw * 0.5, by, bw, 4.0), Color(0.05, 0.06, 0.08, 0.85))
		draw_rect(Rect2(-bw * 0.5, by, bw * stagger_frac(), 4.0),
			Color(1.0, 0.78, 0.34).lerp(Color(1.0, 1.0, 0.85), _stagger_flash * 0.6))


func _draw_flyer(o: Vector2, s: float, body: Color, eye: Color) -> void:

	var bob := sin(_t * 3.0) * 3.0
	o.y += bob
	# 翅膀
	var flap := sin(_t * 12.0) * 0.35
	for side in [-1.0, 1.0]:
		var w := PackedVector2Array([
			o + Vector2(0, -2) * s,
			o + Vector2(side * 26.0 * s, (-16.0 + flap * 22.0) * s),
			o + Vector2(side * 20.0 * s, 8.0 * s),
			o + Vector2(side * 6.0 * s, 6.0 * s),
		])
		draw_colored_polygon(w, Color(0.09, 0.11, 0.15, 0.95))
		draw_polyline(PackedVector2Array([w[0], w[1], w[2]]), Color(0.3, 0.45, 0.6, 0.5), 1.2, true)
	# 身体
	draw_circle(o, 13.0 * s, body)
	draw_circle(o, 13.0 * s, Color(0.2, 0.35, 0.5, 0.10))
	# 眼
	var glow := 0.0
	if state == WINDUP:
		glow = clampf(st / windup_t, 0.0, 1.0)
	var ec := eye.lerp(Color(1.0, 0.95, 0.85), glow)
	draw_circle(o + Vector2(facing * 2.0, -2.0) * s, (3.0 + glow * 1.6) * s, ec)
	if glow > 0.05:
		draw_circle(o, (18.0 + glow * 12.0) * s, Color(1.0, 0.25, 0.3, 0.07 * glow))
	if state == WINDUP:
		var p := clampf(st / windup_t, 0.0, 1.0)
		draw_arc(o, 22.0 * s, -PI * 0.5, -PI * 0.5 + TAU * p, 28, Color(1.0, 0.42, 0.45, 0.85), 2.2, true)
	if state == ATTACK:
		draw_circle(o, 26.0 * s, Color(0.85, 0.92, 1.0, 0.12))
	# 尾迹
	var tail := o - Vector2(facing * 14.0, 0) * s
	draw_line(tail, tail - Vector2(facing * 16.0, 0) * s, Color(0.5, 0.8, 1.0, 0.25), 3.0 * s, true)


func _shadow(center: Vector2, rx: float, ry: float, a: float) -> void:
	var pts := PackedVector2Array()
	for i in 18:
		var ang := TAU * float(i) / 18.0
		pts.append(center + Vector2(cos(ang) * rx, sin(ang) * ry))
	draw_colored_polygon(pts, Color(0.0, 0.0, 0.0, a))
