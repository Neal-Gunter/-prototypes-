extends Node2D
## 玄界 · 中央控制器（R10 重建版）
##
## 这是游戏的「大脑」：状态机 + 房间推进 + 剑意交锋 / 命中检测 + 所有节点的接线。
## 卫星脚本（player / enemy / hud / touch / world / rooms / space / fx）都已实现各自逻辑，
## 本文件只负责把它们串起来，并在这里落地 R10 的两条新需求：
##
##   · 需求④：Boss 房间进入后四周自动禁制落下锁住，战胜 Boss 后才开门放行
##   · 需求⑤：持续攻击（连段 / 没停手）不触发「悟道·剑意交锋」—— 完美判定复用 player.perfect_ready
##
## 节点全部由本脚本在 _ready 里 preload + add_child 创建（Main.tscn 只有一个空 Main 节点）。

const SpaceScript := preload("res://scripts/space.gd")
const WorldScript := preload("res://scripts/world.gd")
const FxScript := preload("res://scripts/fx.gd")
const HudScript := preload("res://scripts/hud.gd")
const TouchScript := preload("res://scripts/touch.gd")
const PlayerScript := preload("res://scripts/player.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const BgScript := preload("res://scripts/bg.gd")
const FgScript := preload("res://scripts/fg.gd")
const ProjectileScript := preload("res://scripts/projectile.gd")
const LightningScript := preload("res://scripts/lightning.gd")
const RoomScript := preload("res://scripts/rooms.gd")
const WeaponScript := preload("res://scripts/weapons.gd")
const RelicScript := preload("res://scripts/relics.gd")
const LoreScript := preload("res://scripts/lore.gd")
const InscribeScript := preload("res://scripts/inscribe.gd")
const ConsumeScript := preload("res://scripts/consumable.gd")
const SummonScript := preload("res://scripts/summon.gd")
const CompanionScript := preload("res://scripts/companion.gd")   # R35 同伴
const EggScript := preload("res://scripts/egg.gd")               # R35 灵兽蛋
const SealScript := preload("res://scripts/seal.gd")             # R36 地面符阵
const EchoScript := preload("res://scripts/echo.gd")             # R37 旧影（轮回台）
const MeridianScript := preload("res://scripts/meridian.gd")
const AlchemyScript := preload("res://scripts/alchemy.gd")

## 与 player.gd 的 enum { ATK_NONE, ATK_WINDUP, ATK_ACTIVE, ATK_RECOVER } 对齐
const ATK_NONE := 0

# ----------------------------------------------------------------- 节点引用
var world
var fx
var hud
var touch
var bg
var fg
var cam: Camera2D
var player
var boss
var enemies: Array = []
var projectiles: Array = []
## R32b：召符唤出的纸人（同一时间可以有好几只，但它们会自己散掉）
var summons: Array = []
## R35：灵兽 / 傀儡（同伴）。跨房间保留（不像 summons 每间清），只在回标题 / 死亡时清空。
var companions: Array = []
## R35：灵兽蛋拾取物（每间房清，纯房间内掉落）
var eggs: Array = []
## R36：地面符阵（每间房清，符箓秘境专属）
var seals: Array = []
## R37：旧影（每间房清，轮回台专属）
var echoes: Array = []
## R37：玩家最近几秒的坐标轨迹 —— 旧影就沿它走。
## 环形缓冲，每 ECHO_SAMPLE 采一次，保留 ECHO_KEEP 个点（约 4 秒）。
const ECHO_SAMPLE := 0.1
const ECHO_KEEP := 40
var echo_trail: Array = []
var _echo_acc := 0.0

# ----------------------------------------------------------------- 状态机
var state := "title"
var prev_state := "title"

# ----------------------------------------------------------------- 关卡 / 房间
var level_index := 0
var rooms: Array = []          # 当前关卡的房间数组（来自 RoomScript）
var room_i := 0
var room_state: Array = []     # 每间房状态："new" / "cleared"
var room_resolved := false     # 当前房间是否已结算（避免每帧重复触发清场）
var current_doors: Dictionary = {}   # 哪些方向有邻居（能开门）
var current_gates: Dictionary = {}   # 各方向闸门是否落下（true = 锁）
var level_name := ""
var room_name := ""

# ----------------------------------------------------------------- 菜单选择
var title_sel := 0
var weapon_sel := 0
var run_seed := 0
var daily_seed_val := 0
var daily_mode := false
## R19a：序章「钟楼」模式 —— 3 间线性房、无 Boss、不占主线进度
var prologue_mode := false
var rng := RandomNumberGenerator.new()

var reward_cards: Array = []
var reward_rects: Array = []
var pick_sel := 0
## R13 位次：奖励页标题（替换页会换文案）
var reward_title := ""
var pending_relic := ""      # 等待替换的新法宝 id
var replace_slot := ""       # 它要进的位次

var branch_sel := 0
var event_kind := ""
var event_sel := 0
var shop_items: Array = []

var menu_sel := 0
var menu_action := 0
var _slot_msg := ""

# HUD 引用的矩形常量（位置与 hud.gd 各绘制函数对齐）
## R16：标题页 4 行 —— 多了「残卷图鉴」（整体上移，给底部操作提示留位）
## R33a：加第 5 行「经 脉」，行高 56 / 间距 60，整体上移到 368 起，
## 底部操作提示仍在 684 / 704 —— 五行落在 368..664，留 20 缝不压提示。
var BTN_TITLE: Array = [Rect2(490, 368, 300, 56), Rect2(490, 428, 300, 56),
	Rect2(490, 488, 300, 56), Rect2(490, 548, 300, 56), Rect2(490, 608, 300, 56)]
## R29：武器卡片布局按武器表数量动态算 —— 加第 4 把武器不用再手改坐标
var WPN_RECTS: Array = []
var ROUTE_RECTS: Array = [Rect2(286, 260, 360, 232), Rect2(666, 260, 360, 232)]
var EVENT_BTNS: Array = [Rect2(440, 380, 400, 56), Rect2(440, 450, 400, 56)]
var SHOP_ROWS: Array = [Rect2(300, 210, 680, 58), Rect2(300, 278, 680, 58), Rect2(300, 346, 680, 58)]
var BTN_SHOP_LEAVE := Rect2(490, 628, 300, 56)
## R16：替换页顶部的「花道蕴扩格」按钮
var REPLACE_EXPAND := Rect2(430, 208, 420, 46)
## R16：图鉴页的翻幕箭头与返回
var CODEX_LEFT := Rect2(40, 330, 56, 90)
var CODEX_RIGHT := Rect2(1184, 330, 56, 90)
var CODEX_BACK := Rect2(490, 656, 300, 46)
## R16：暂停页底部的「残卷图鉴」入口（键盘 C / 触屏点此）
## R31：和「兵器铭刻」并排 —— 各 380 宽，中间留 40 缝
var BTN_PAUSE_FORGE := Rect2(240, 686, 380, 30)
var BTN_PAUSE_CODEX := Rect2(660, 686, 380, 30)

# R31 铭刻页状态
var forge_sel := 0          # 当前选中的槽（0 / 1）
var forge_msg := ""         # 页内一行反馈（刻上了 / 精铁不够 …）
var forge_msg_t := 0.0
## 铭刻页底部两个按钮（触屏用；键盘是 空格 与 Esc/M）
var BTN_FORGE_ACTION := Rect2(390, 560, 250, 44)
var BTN_FORGE_BACK := Rect2(660, 560, 230, 44)

# R33a 经脉页状态（3 脉 × 8 条，meridian_sel = mer_col * 8 + mer_row）
# R33b 起：一页只显示一脉的 8 条（2 列 × 4 行），mer_col 变成「页签」
var mer_col := 0
var mer_row := 0
var mer_msg := ""
var mer_msg_t := 0.0
var meridian_from := "title"
## 经脉页底部两个按钮（触屏用；键盘是 R 洗点 / Esc 返回）
var BTN_MER_RESPEC := Rect2(390, 662, 250, 44)
var BTN_MER_BACK := Rect2(660, 662, 230, 44)
## 顶部页签：1 剑脉 / 2 体脉 / 3 灵脉 / 4 丹房（触屏用；键盘是 1 / 2 / 3 / 4）
var BTN_MER_TABS := [Rect2(365, 150, 130, 34), Rect2(505, 150, 130, 34),
	Rect2(645, 150, 130, 34), Rect2(785, 150, 130, 34)]
## 丹房页签在 mer_col 里的下标
const MER_TAB_ALCH := 3
## 丹房页只有一个「返回」按钮，居中
var BTN_ALCH_BACK := Rect2(490, 662, 300, 44)
## 本局结算到手的道痕（死亡 / 胜利页显示）
var daoyun_gain := 0
var _meta_awarded := false

# 战斗统计显示用
var combo_hits := 0
var _combo_t := 0.0

# 触摸模式
var touch_mode := false

# 陷阱计时
var _trap_t := 0.0

# 需求④：当前是否在 Boss 锁定房
var boss_room_locked := false

# R14：本间房内已播过的 Boss 台词（"kind:slot" → true），换房即清空
var _boss_lines_said := {}

# R15：残影引导者 —— 进入 Boss 房后淡入；建言只播一次（走 Cfg.seen_lines）
var _guide_t := 0.0          # 当前可见度（0~1，平滑跟随目标）
var _guide_target := 0.0     # 目标可见度
var _guide_said := false     # 本间房是否已经说过话
var _guide_line_t := 0.0     # 进房后多久才开口（先让它「站住」再说话）

# R16：排队等浮层播完的主角自述（碎片浮层 + 自述不能同时发）
var _pending_self: Dictionary = {}
# R16：图鉴页当前翻到第几幕
var codex_act := 1

# R28：破劫评分 —— 只累计「play」状态的时间（菜单 / 暂停 / 结算都不算）
var _run_t := 0.0
# R28：本次破劫的名次（0 = 没进榜）与分数，供结算页显示
var daily_rank := 0
var daily_score_now := 0

# R20：真结局 —— 打完心魔境的 WIN 页换成终局文案（按身份档位给结语）
var true_ending := false


func _ready() -> void:
	_build_wpn_rects()
	_setup_nodes()
	_to_title()


## R29：按武器表算卡片矩形。4 把武器时卡片 282 宽、间距 30，正好铺满 1218。
func _build_wpn_rects() -> void:
	var n := maxi(1, WeaponScript.LIST.size())
	var gap := 30.0
	var w := minf(282.0, (1220.0 - gap * float(n - 1)) / float(n))
	var total := w * float(n) + gap * float(n - 1)
	var x := (1280.0 - total) * 0.5
	WPN_RECTS.clear()
	for i in n:
		WPN_RECTS.append(Rect2(x + float(i) * (w + gap), 240.0, w, 232.0))


# ============================================================ 节点创建与接线
func _setup_nodes() -> void:
	bg = BgScript.new(); add_child(bg)
	world = WorldScript.new(); add_child(world)
	fg = FgScript.new(); add_child(fg)
	fg.z_index = 80

	fx = FxScript.new(); add_child(fx)

	cam = Camera2D.new()
	cam.global_position = SpaceScript.CAM_POS
	add_child(cam)
	bg.cam = cam
	fg.cam = cam

	hud = HudScript.new(); add_child(hud)
	touch = TouchScript.new(); add_child(touch)

	# 触屏设备上虚拟按键是唯一输入方式，必须常开；
	# 桌面端才由设置里的「手机按键」开关决定（R19 修：APK 点不动屏幕）
	touch_mode = touch.can_touch or Cfg.touch_ui
	touch.game = self
	touch.set_shown(touch_mode)

	# 双向接线：卫星脚本通过 .game 回调本控制器
	hud.game = self

	# 玩家只创建一次，之后跨房间复用
	player = PlayerScript.new()
	player.setup(fx)
	# R12：长枪自动追击要知道前方有没有人 —— 注入一个只读回调，避免 player 反向依赖 main
	player.enemy_provider = func() -> Array: return enemies
	add_child(player)
	player.died.connect(_on_player_died)
	player.flying_sword.connect(_on_flying_sword)
	# R29 符剑：符击 / 符阵·万剑 共用同一个弹幕生成器
	player.talisman_shot.connect(_on_talisman_shot)
	# R30 反震：格挡成功时由 player 广播，这里找最近的敌人反弹
	player.guard_reflect.connect(_on_guard_reflect)
	# R18b：绝招此前只有信号、没有接收者（等于零伤害），这里接上
	player.ult_burst.connect(_on_ult_burst)
	player.ult_strike.connect(_on_ult_strike)
	player.ult_started.connect(_on_player_ult_started)
	# R32b：六张符 —— 玩家侧做不了的「落世界」那一半接在这里
	player.talisman_fire.connect(_on_talisman_fire)
	player.talisman_thunder.connect(_on_talisman_thunder)
	player.talisman_summon.connect(_on_talisman_summon)
	player.talisman_seal.connect(_on_talisman_seal)


# ============================================================ 状态切换
func _to_title() -> void:
	state = "title"
	title_sel = 0
	prev_state = "title"
	Music.play("title")
	if player:
		player.visible = false
	Game.reset_stats()
	rooms = []
	enemies.clear()
	projectiles.clear()
	_clear_companions()      # R35：回标题清掉所有同伴
	boss = null
	boss_room_locked = false


## R33a：开局经脉加成 —— 只给「起手资源」，不动任何随机性
## R33c：把跨局背包里的东西带进这一局 —— 开局注入快捷格，然后背包清空。
## 「带进局就归这一局」：局内用掉就没了，死了也不会还回来（肉鸽的痛感要保住）。
func _apply_pantry() -> void:
	var bag: Dictionary = Cfg.pantry_take_all()
	if bag.is_empty():
		return
	# 注意用 add_item 而不是 add_pill：背包里符箓也装得下，add_pill 只认丹药
	for id in bag.keys():
		player.add_item(str(id), int(bag[id]))


func _apply_meridian_start() -> void:
	var lv: Dictionary = Cfg.meridian_lv
	var extra := MeridianScript.start_soul(lv)
	if extra > 0.0:
		player.soul = minf(player.soul + extra, Game.MAX_SOUL)
	if MeridianScript.start_pill(lv):
		_grant_item(ConsumeScript.roll(rng))


## R33a：这一局死了能拿多少道痕（走得越远越多，但永远不会是 0 ——
## 肉鸽的「输了也变强一点」必须当场兑现，不能等到通关）
func daoyun_on_death() -> int:
	var cleared := 0
	for st in room_state:
		if str(st) == "cleared":
			cleared += 1
	return 4 + 4 * level_index + int(cleared / 3)


## R33a：通关（含真结局）的道痕 —— 一次通关 ≈ 三条经脉一级
func daoyun_on_win() -> int:
	return 60 + 10 * level_index


## R33a：结算道痕（一局只结一次；今日道劫 ×1.5）
func _award_daoyun(is_win: bool) -> void:
	if _meta_awarded:
		return
	_meta_awarded = true
	var n := daoyun_on_win() if is_win else daoyun_on_death()
	if daily_mode:
		n = int(round(float(n) * 1.5))
	daoyun_gain = Cfg.add_daoyun(n)


func _start_run(daily: bool) -> void:
	daily_mode = daily
	if daily:
		daily_seed_val = RoomScript.daily_seed()
		run_seed = daily_seed_val
	else:
		run_seed = randi()
	rng.seed = run_seed
	Game.reset_stats()
	_run_t = 0.0
	daily_rank = 0
	daily_score_now = 0
	level_index = 0
	# R20：每局开始先清掉上一局的真结局标记
	true_ending = false
	player.visible = true
	player.reset_relics()
	player.reset_inscribe()   # R31：铭刻与精铁是局内构筑，开新局清空
	player.reset_quick()      # R32a：丹药同样是局内资源，开新局清空
	player.respawn(Vector2(650.0, 700.0))
	# R33a：道蕴是局内的钱 —— 开新局归零（以前会跨局累积，顺手修掉）
	player.soul = 0.0
	daoyun_gain = 0
	_meta_awarded = false
	# R33c：丹房存货先注入（背包上限就是一局能带的量），再发经脉的符丹加成
	_apply_pantry()
	_apply_meridian_start()
	if daily:
		# R23：今日道劫 · 心魔试炼 —— 武器由每日种子指定（今日之镜），
		# 跳过选武器页，直达心魔境。进去就照镜子。
		player.set_weapon(daily_weapon_id())
		_confirm_weapon()
		return
	player.set_weapon("sword")
	_enter_weapon_select()


## R23：今日之镜 —— 今日道劫用哪把武器由每日种子唯一决定（同日稳定）
func daily_weapon_id() -> String:
	return str(WeaponScript.LIST[RoomScript.daily_seed() % WeaponScript.LIST.size()]["id"])


## R23：今天的今日道劫破没破（日期对上且记录为已通关）
func daily_done_today() -> bool:
	return Cfg.daily_date == RoomScript.today_key() and Cfg.daily_cleared


func _enter_weapon_select() -> void:
	state = "weapon"
	weapon_sel = 0


func _confirm_weapon() -> void:
	if not daily_mode:
		var w: Dictionary = WeaponScript.LIST[weapon_sel]
		player.set_weapon(str(w["id"]))
	# R23：今日道劫直达心魔境 —— 「读 Build」的挑战容器，进去就照镜子
	level_index = RoomScript.level_count() - 1 if daily_mode else 0
	# R19a：没走过序章的玩家，先上钟楼学三件事，再进镇钟廊
	if not Cfg.prologue_done and not daily_mode:
		_enter_prologue()
		return
	_enter_level(level_index)


func _enter_level(idx: int) -> void:
	level_index = idx
	# R20：进任何一关都清掉真结局标记 —— 它只在「最后一关打完的 WIN 页」有意义，
	# 不清的话重开 / 换关会带着上一局的标记（T82 抓出来的）
	true_ending = false
	level_name = RoomScript.level_name(idx)
	rooms = RoomScript.rooms_of(idx)
	room_state = []
	for _i in rooms.size():
		room_state.append("new")
	# R14：背景「玄界之门」引力点随关卡增强
	if bg != null and bg.has_method("set_level"):
		bg.set_level(idx)
	# 房间 0 永远是 start
	_enter_room(0)


## R19a：进序章 —— 3 间房，线性推进，没有 Boss、没有奖励卡
func _enter_prologue() -> void:
	prologue_mode = true
	level_index = 0
	level_name = RoomScript.prologue_name()
	rooms = RoomScript.prologue_rooms()
	room_state = []
	for _i in rooms.size():
		room_state.append("new")
	if bg != null and bg.has_method("set_level"):
		bg.set_level(0)
	# 顶部本来就会显示「钟楼 · 序章」，这里不再叠一条提示（会和残影台词面板打架）
	_enter_room(0)


## 序章走完 → 记一笔（不再自动进）→ 直接接上主线第一关
func _finish_prologue() -> void:
	prologue_mode = false
	Cfg.prologue_done = true
	Cfg.save_cfg()
	if hud != null:
		hud.show_prompt("序 章 · 完 · 钟 还 在 响", 2.4)
	level_index = 0
	_enter_level(level_index)


func _enter_room(i: int) -> void:
	room_i = i
	room_resolved = false
	combo_hits = 0
	_boss_lines_said.clear()
	# R15：引导者每间房重置（进 Boss 房才重新淡入）
	_guide_t = 0.0
	_guide_target = 0.0
	_guide_said = false
	_guide_line_t = 0.0
	var r: Dictionary = rooms[i]
	room_name = str(r.get("name", ""))
	var kind: String = RoomScript.room_kind(r)

	# 清掉上一间的敌人与弹幕
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()
	for p in projectiles:
		if is_instance_valid(p):
			p.queue_free()
	projectiles.clear()
	# R32b：召符的纸人不跨房（它只活在这一间里）
	for s in summons:
		if is_instance_valid(s):
			s.queue_free()
	summons.clear()
	# R35：灵兽蛋是房间内掉落，进新房先清掉上一间的
	for e in eggs:
		if is_instance_valid(e):
			e.queue_free()
	eggs.clear()
	# R36：地面符阵也是房间内物件，进新房先清
	_clear_seals()
	# R37：旧影同理
	_clear_echoes()
	boss = null
	boss_room_locked = false

	# R15：把「这一间该摆什么静物」一并交给世界层与前景层。
	# depth：0 = 偏里（靠后墙，row 1），1 = 偏外（靠镜头，row 0）。
	# 关卡三的伪上下层靠它区分「上排铁棺 / 下排断链」。
	var row := int(r.get("row", 0))
	var depth := 1 - row
	world.set_room_env(kind, depth, level_index)
	# R36：符箓秘境的房间铺地面符阵（生符 / 煞符交替）
	_spawn_seals(r)
	# R37：轮回台的房间开场就站几个旧影
	_spawn_echoes(r)
	if fg != null and fg.has_method("set_tier"):
		fg.set_tier(depth)

	player.respawn(RoomScript.start_pos(level_index) if i == 0 else Vector2(650.0, 700.0))

	# 哪几个方向有邻居 → 决定门口
	current_doors = _door_map(i)

	# 进入即禁制落下：需求④ —— 只有 Boss 房四面禁制落下锁住，击败 Boss 后才开门。
	# 非 Boss 房默认开门（但「清场才能推进」由奖励/事件界面控制，仍无法提前离开）。
	var is_boss := kind == RoomScript.KIND_BOSS
	if is_boss:
		_set_gates(true)
		boss_room_locked = true
		if hud:
			hud.show_prompt("%s · 禁 制 · 封" % str(_boss_name(r)), 2.4)
		SFX.play("gate", 1.3, -10.0)
		Game.add_shake(14.0)
		# R14：禁制落下即触发 Boss「战前一句话」（每房一次）
		_say_boss_line(int(r.get("boss", 2)), "before")
		# R15：门边浮出残影引导者，站定之后才开口
		_guide_target = 1.0
		# R19b：禁制提示要 2.4 秒，引导者提前开口会和它叠在同一块面板上（字糊成一片），
		# 所以把「站住再说话」往后推到 2.8 秒 —— 提示先退场，再轮到建言。
		_guide_line_t = 2.8
	else:
		_set_gates(false)
		# R19a：序章每间房都有一位「前尘残影」站在门边教一句话
		if prologue_mode:
			_guide_target = 1.0
			_guide_line_t = 1.2

	# R34：背景音乐按场景切换（Boss 房→boss，道劫→daily，其余→explore）
	if is_boss:
		Music.play("boss")
	elif daily_mode:
		Music.play("daily")
	else:
		Music.play("explore")

	# 生成房间内容
	_spawn_room_content(r, i)

	state = "play"

	# 无敌人的事件房（宝箱 / 商队）直接进事件屏，不与敌人战斗
	if enemies.is_empty() and (kind == RoomScript.KIND_CHEST or kind == RoomScript.KIND_SHOP):
		event_kind = kind
		event_sel = 0
		if kind == RoomScript.KIND_SHOP:
			_build_shop()
			_show_merchant()
		room_resolved = true
		state = "event"
	# 无敌人的非事件房（起点房等）：没有可战斗目标，直接标记已清场并进入下一间，
	# 否则会卡在 play 状态无处可去（本工程房间推进完全由 UI 触发，无「走门」逻辑）。
	elif enemies.is_empty():
		if kind == RoomScript.KIND_START:
			_show_stele()
		room_resolved = true
		room_state[room_i] = "cleared"
		_next_room()


func _door_map(i: int) -> Dictionary:
	var out := {"west": false, "east": false, "north": false, "south": false}
	var nb: Dictionary = RoomScript.prologue_neighbors(i) if prologue_mode \
		else RoomScript.neighbors(level_index, i)
	for k in nb.keys():
		out[k] = true
	return out


## 需求④：统一设置四面闸门。locked=true → 四面禁制落下；false → 全部开门
func _set_gates(locked: bool) -> void:
	current_gates = {"west": locked, "east": locked, "north": locked, "south": locked}
	world.set_doors(current_doors, current_gates)
	# R15：禁制落下时近景石柱往画面中间内收 —— 门关上，空间也跟着变窄
	if fg != null and fg.has_method("set_squeeze"):
		fg.set_squeeze(1.0 if locked else 0.0)


# ============================================================ R14 世界层：台词
## Boss 三句话。返回是否真的播了（同一间房、同一句只播一次）
func _say_boss_line(kind: int, slot: String, as_prompt: bool = false) -> bool:
	var key := "%d:%s" % [kind, slot]
	if bool(_boss_lines_said.get(key, false)):
		return false
	var txt := LoreScript.boss_line(kind, slot)
	if txt == "" or hud == null:
		return false
	_boss_lines_said[key] = true
	var seen := Cfg.has_seen_line(key)
	Cfg.mark_seen_line(key)
	var body := txt
	if seen and slot != "death":
		body = txt.substr(0, mini(txt.length(), 8)) + "…"
	var title := "战 前"
	if slot == "mid":
		title = "战 中"
	elif slot == "death":
		title = "临 终"
	if as_prompt:
		hud.show_prompt("「%s」" % body, 4.5 if not seen else 3.0)
	else:
		hud.show_lore(title, body, 5.0 if not seen else 3.2)
	Game.boss_line_count += 1
	return true


## Boss 进入二阶段 → 战中台词
func _on_enemy_phase(e, p: int) -> void:
	if e != boss or int(p) != 2:
		return
	_say_boss_line(int(e.kind), "mid")


## 起始房残碑（岔路屏已废弃，残碑改落在每关入口）
func _show_stele() -> void:
	if hud == null:
		return
	var key := "stele:%d" % level_index
	var seen := Cfg.has_seen_line(key)
	Cfg.mark_seen_line(key)
	var txt := LoreScript.stele_line(level_index)
	if seen:
		txt = txt.substr(0, mini(txt.length(), 9)) + "…"
	hud.show_lore("残 碑", txt, 6.0 if not seen else 3.5)


## 负匣人（商人）台词，随关卡变化
func _show_merchant() -> void:
	if hud == null:
		return
	var key := "merchant:%d" % level_index
	var seen := Cfg.has_seen_line(key)
	Cfg.mark_seen_line(key)
	var txt := LoreScript.merchant_line(level_index)
	hud.show_lore("负 匣 人", txt, 5.5 if not seen else 3.0)
	# R16：商队房的残卷只记账不弹窗 —— 免得盖掉负匣人的台词
	if not Game.fragments.has("L08"):
		Game.fragments.append("L08")
	Cfg.mark_fragment("L08")
	_queue_self_unlock()


# ============================================================ R16 残卷与身份
## 收下一条碎片：记进本局 + 永久图鉴，并把文字浮出来（重复拿到只显示开头）
func _show_fragment(id: String) -> void:
	if id == "" or hud == null:
		return
	var f: Dictionary = LoreScript.by_id(id)
	if f.is_empty():
		return
	var first := not Cfg.has_fragment(id)
	if not Game.fragments.has(id):
		Game.fragments.append(id)
	Cfg.mark_fragment(id)
	var txt := str(f["text"])
	if not first:
		txt = txt.substr(0, mini(txt.length(), 10)) + "…"
	if id == "L13":
		# R28：镜卷是幕外之卷，用大卡 + 紫金配色单独呈现（普通残卷只有一行）
		hud.show_lore(str(f["title"]), txt, 9.0 if first else 4.0, Color(0.86, 0.74, 1.0))
	else:
		hud.show_lore(str(f["title"]), txt, 6.0 if first else 3.2)
	_queue_self_unlock()


## 碎片够 3/6/9/12 条 → 排一段主角自述（跨局只播一次）
func _queue_self_unlock() -> void:
	var sl: Dictionary = LoreScript.self_line_for(Game.fragments.size())
	if sl.is_empty():
		return
	var need := int(sl["need"])
	if Cfg.has_self(need):
		return
	# 只排「还差得最远的那一段」，避免一次跳两级
	_pending_self = sl


## 等碎片浮层播完再播自述 —— 两个 show_lore 同时发会互相覆盖
func _flush_self_unlock() -> void:
	if _pending_self.is_empty() or hud == null:
		return
	if hud.lore_t > 0.15:
		return
	var need := int(_pending_self["need"])
	Cfg.mark_self(need)
	Game.self_unlocks += 1
	hud.show_lore(str(_pending_self["title"]), str(_pending_self["text"]), 7.0)
	SFX.play("gate", 1.5, -12.0)
	_pending_self = {}


## R16：抽卡权重 —— 你已经在走的位次更容易出，已满的位次几乎不出
func _slot_bias() -> Dictionary:
	var out := {}
	for k in RelicScript.SLOT_ORDER:
		var sl := str(k)
		var used: int = int(player.slot_used(sl))
		var cap: int = int(player.slot_cap(sl))
		if used >= cap:
			out[sl] = 0.12          # 满了：几乎不出（出了也只是替换素材）
		elif used >= cap - 1:
			out[sl] = 1.70          # 差一格：明显加权，帮你装满
		elif used > 0:
			out[sl] = 1.15
		else:
			out[sl] = 1.0
	# 飞剑流已成立 → 远程类再抬一档（池子分层）
	if player.is_flying_build():
		out["blade"] = float(out.get("blade", 1.0)) * 1.25
	return out


# ============================================================ R15 残影引导者
## 淡入 / 淡出 + 站定后开口。引导者只活在 Boss 房，出房即散。
func _update_guide(delta: float) -> void:
	# 1) 可见度平滑跟随目标（淡入约 0.7 秒）
	if absf(_guide_t - _guide_target) > 0.001:
		_guide_t = move_toward(_guide_t, _guide_target, delta * 1.45)
		if world != null and world.has_method("set_guide_alpha"):
			world.set_guide_alpha(_guide_t)
	# 2) 站定之后才说话（只播一次）
	if _guide_line_t > 0.0:
		_guide_line_t -= delta
		if _guide_line_t <= 0.0 and not _guide_said and state == "play":
			_say_guide_line()


## 残影引导者建言。返回是否真的播了（同一关只播一次，二周目只给省略号）
func _say_guide_line() -> bool:
	if _guide_said or hud == null:
		return false
	_guide_said = true
	var txt := ""
	var key := ""
	if prologue_mode:
		txt = LoreScript.prologue_line(room_i)
		key = "prologue:%d" % room_i
	else:
		txt = LoreScript.guide_line(level_index)
		key = "guide:%d" % level_index
	if txt == "":
		return false
	var seen := Cfg.has_seen_line(key)
	Cfg.mark_seen_line(key)
	if seen:
		txt = txt.substr(0, mini(txt.length(), 6)) + "…"
	var who := "前 尘 残 影" if prologue_mode else "残 影 引 导 者"
	hud.show_lore(who, txt, 5.0 if not seen else 3.2)
	return true


func _spawn_room_content(r: Dictionary, i: int) -> void:
	var kind: String = RoomScript.room_kind(r)
	if kind == RoomScript.KIND_START:
		return
	if kind == RoomScript.KIND_BOSS:
		var bk := int(r.get("boss", 2))
		# R19b：关底不再跟玩家刷在同一个点上（以前 Boss 就站在玩家身上，
		# 体型大的还能靠轮廓分出来，体型跟玩家一样大的「无相·心魔」就完全糊在一起了）。
		# 现在固定站到玩家的另一侧，离得开一点。
		var bx := 650.0
		if player != null and is_instance_valid(player):
			bx = player.global_position.x + 300.0
			if bx > SpaceScript.ROOM_X1 - 170.0:
				bx = player.global_position.x - 300.0
			bx = clampf(bx, SpaceScript.ROOM_X0 + 170.0, SpaceScript.ROOM_X1 - 170.0)
		var eb: Node = _spawn_enemy(bk, Vector2(bx, 600.0))
		# R19b：心魔境的关底是「镜子里的你」——武器与法宝都抄玩家的
		if bk == EnemyScript.KIND_BOSS6 and eb != null:
			_apply_mirror(eb)
		return
	# R19a：序章用固定波次（保证教学顺序），位置也写死
	if r.has("fixed"):
		var fx_list: Array = r["fixed"]
		for k in fx_list.size():
			_spawn_enemy(int(fx_list[k]), Vector2(760.0 + float(k) * 120.0, 620.0))
		world.extra_spikes = []
		return
	# 战斗 / 精英 / 陷阱：撒一波敌人
	var list: Array = RoomScript.wave(rng, r, i, level_index)
	for spec in list:
		_spawn_enemy(int(spec["kind"]), Vector2(spec["pos"].x, spec["pos"].y),
			int(spec.get("variant", 0)))
	# R14：记忆回响（关卡三深井房的「上一次轮回的自己」）
	if bool(r.get("echo", false)):
		_spawn_echo(Vector2(780.0, 600.0))
	# R19b：心魔境 —— 每间房再站一个「镜子里的你」：武器与法宝都抄玩家的
	if bool(r.get("mirror", false)):
		var m: Node = _spawn_enemy(EnemyScript.KIND_SENTINEL, Vector2(880.0, 600.0))
		if m != null:
			_apply_mirror(m)
	# R35：精英房掉一颗灵兽蛋（0~5 = 6 种同伴随机），玩家走到附近即获得
	if kind == RoomScript.KIND_ELITE:
		_spawn_egg(rng.randi_range(0, 5), Vector2(1080.0, 600.0))
	# 陷阱房：地刺
	if kind == RoomScript.KIND_TRAP:
		world.extra_spikes = RoomScript.trap_hazards(r)
		# R16：陷阱房落一条残卷（此前 event_lore 定义了却没接线）
		_show_fragment("L10")
	else:
		world.extra_spikes = []


func _spawn_enemy(kind: int, pos: Vector2, variant: int = 0) -> Node:
	var e := EnemyScript.new()
	e.setup(kind, pos, player, fx)
	e.arena = Vector2(SpaceScript.ROOM_X0, SpaceScript.ROOM_X1)
	# R18：行为变奏（护盾 / 召唤 / 自爆 / 读招 / 狂暴）
	if variant != 0:
		e.set_variant(variant)
	add_child(e)
	e.killed.connect(_on_enemy_killed)
	e.fired.connect(_on_enemy_fired)
	e.summon.connect(_on_enemy_summon.bind(e))
	e.aoe.connect(_on_enemy_aoe)
	e.parried.connect(_on_enemy_parried)
	e.phase_changed.connect(_on_enemy_phase)
	e.mirror_strike.connect(_on_enemy_mirror_strike)
	e.mirror_burst.connect(_on_enemy_mirror_burst)
	# R37：轮回使召旧影
	e.echo_call.connect(_on_enemy_echo_call)
	# R38：道心失守窗口走完没下手 → 业力 −1
	e.spared.connect(_on_enemy_spared)
	enemies.append(e)
	if e.is_boss:
		boss = e
	elif e.is_elite():
		_reveal_elite_name(e)   # R18：第一次见到某种精英，头顶浮一次名字
	return e


## R18：精英名字只在「第一次遇见这一种」时浮一次，之后不再打扰
## 走 Cfg.seen_lines 的既有机制，不新增存档字段
func _reveal_elite_name(e) -> void:
	if e == null or fx == null:
		return
	var key := "elite_%d" % int(e.kind)
	if Cfg.has_seen_line(key):
		return
	Cfg.mark_seen_line(key)
	fx.text(e.global_position + Vector2(0, -112.0 * float(e.scale_f)),
		String(e.elite_name()), Color(0.88, 0.94, 1.0), 20, 44)


# ============================================================ R35 同伴 / 灵兽蛋
## 获得一只同伴：创建节点、注入引用、挂到场景树。同伴跨房间保留，直到回标题 / 死亡。
func grant_companion(k: int) -> Node:
	if CompanionScript == null:
		return null
	var pos := Vector2(650.0, 600.0)
	if player != null and is_instance_valid(player):
		pos = player.global_position
	var c := CompanionScript.new()
	c.init(k, pos)
	c.player = player
	c.fx = fx
	c.main_ref = self
	c.enemy_provider = func() -> Array: return enemies
	add_child(c)
	c.queue_redraw()
	companions.append(c)
	if hud != null and hud.has_method("on_companions_changed"):
		hud.on_companions_changed(companions)
	if fx != null:
		fx.text(c.global_position + Vector2(0, -44.0),
			"获 得 · " + CompanionScript.NAMES.get(k, "同 伴"),
			Color.from_hsv(CompanionScript.HUES.get(k, 0.5), 0.6, 1.0), 20, 36)
	SFX.play("heal", 0.9, 2.0)
	return c


## 掉一颗灵兽蛋（精英房用）。玩家走到附近即获得随机同伴。
func _spawn_egg(k: int, pos: Vector2) -> void:
	if EggScript == null:
		return
	var egg := EggScript.new()
	egg.kind = k
	egg.global_position = pos
	add_child(egg)
	eggs.append(egg)


## 同伴（符傀儡）放符：复用弹幕通道（talisman）。
func _spawn_companion_shot(pos: Vector2, dir: Vector2, dmg: int) -> void:
	if ProjectileScript == null:
		return
	var p := ProjectileScript.new()
	var hue := 0.78
	if player != null and is_instance_valid(player):
		hue = player.weapon_hue()
	p.setup_talisman(pos, dir, 600.0, maxi(1, dmg), hue)
	add_child(p)
	projectiles.append(p)


## R36：铺一间房的地面符阵。奇数位「生符」（回灵力）/ 偶数位「煞符」（灼烧 1 点）。
## 位置撒在地板中段，避开门口（x 两端各留 180），也别压在出生点上。
func _spawn_seals(r: Dictionary) -> void:
	if SealScript == null:
		return
	var n := int(r.get("seals", 0))
	if n <= 0:
		return
	var x0: float = SpaceScript.ROOM_X0 + 180.0
	var x1: float = SpaceScript.ROOM_X1 - 180.0
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		var px := lerpf(x0, x1, t)
		# 前后交错：偶数位靠里、奇数位靠外，逼玩家在两界之间来回走
		var py: float = SpaceScript.FLOOR_FAR_Y + 52.0 if i % 2 == 0 \
			else SpaceScript.FLOOR_NEAR_Y - 52.0
		var s := SealScript.new()
		s.setup(i % 2 == 1, Vector2(px, py), player, fx)
		add_child(s)
		seals.append(s)


## R36：清空地面符阵（进新房 / 回标题）
func _clear_seals() -> void:
	for s in seals:
		if is_instance_valid(s):
			s.queue_free()
	seals.clear()


# ============================================================ R37 轮回台 · 旧影
## 采一次玩家坐标进环形缓冲。只在 play 状态采 —— 菜单里站着不动不算「走位」。
func _record_echo_trail(delta: float) -> void:
	if player == null or not is_instance_valid(player) or player.dead:
		return
	_echo_acc += delta
	if _echo_acc < ECHO_SAMPLE:
		return
	_echo_acc = 0.0
	echo_trail.append(player.global_position)
	while echo_trail.size() > ECHO_KEEP:
		echo_trail.pop_front()


## 给轮回使 / 房间用的轨迹快照（拷贝一份，免得调用方改到缓冲）
func echo_path() -> Array:
	var out: Array = []
	for v in echo_trail:
		out.append(v)
	return out


## 沿玩家最近的轨迹生成 n 个旧影。轨迹太短（刚进房）就退化成「朝玩家飘」，
## 由 echo.gd 自己处理（path.size() < MIN_PATH）。
func _spawn_echoes_at(pos: Vector2, n: int) -> void:
	if EchoScript == null or n <= 0:
		return
	var path := echo_path()
	# 从轨迹里取一段错开起点，让几只影子不重叠在同一点
	var base: int = path.size() / maxi(1, n)
	for i in n:
		var rot: Array = []
		if path.size() >= 2:
			var off: int = (base * i) % path.size()
			for k in path.size():
				rot.append(path[(off + k) % path.size()])
		var e := EchoScript.new()
		e.setup(rot, player, fx, 330.0 + 40.0 * float(i))
		if rot.size() < 2:
			# 没有轨迹可循：从召唤点散开，朝玩家飘
			e.global_position = pos + Vector2(-70.0 + 70.0 * float(i), -30.0)
		add_child(e)
		echoes.append(e)


## 房间开场的旧影（rooms 里的 "echoes" 字段）。位置与符阵错开，不叠在一起。
func _spawn_echoes(r: Dictionary) -> void:
	var n := int(r.get("echoes", 0))
	if n <= 0:
		return
	var x0: float = SpaceScript.ROOM_X0 + 240.0
	var x1: float = SpaceScript.ROOM_X1 - 240.0
	for i in n:
		var t: float = (float(i) + 0.5) / float(n)
		var px: float = lerpf(x0, x1, t)
		var py: float = SpaceScript.FLOOR_FAR_Y + 70.0 if i % 2 == 0 \
			else SpaceScript.FLOOR_NEAR_Y - 70.0
		_spawn_echoes_at(Vector2(px, py), 1)


## R37：清空旧影（进新房 / 回标题）
func _clear_echoes() -> void:
	for e in echoes:
		if is_instance_valid(e):
			e.queue_free()
	echoes.clear()


## 清空同伴（回标题 / 死亡时调用）
func _clear_companions() -> void:
	for c in companions:
		if is_instance_valid(c):
			c.queue_free()
	companions.clear()
	for e in eggs:
		if is_instance_valid(e):
			e.queue_free()
	eggs.clear()
	_clear_seals()
	_clear_echoes()


## R18（开发用）：把六种精英一字排开 —— 截图 / 手感调试用，正常流程不会调用
func debug_spawn_elites() -> void:
	# 先清场：房间自带的杂兵会挡住精英，截图看不清
	for e in enemies.duplicate():
		e.queue_free()
	enemies.clear()
	boss = null
	if fx != null:
		fx.clear_all()   # 连房间自带的弹幕 / 范围提示一起清掉，截图才干净
	for i in 6:
		var e: Node = _spawn_enemy(EnemyScript.KIND_JIANXIU + i,
			Vector2(230.0 + float(i) * 118.0, 556.0))
		if e == null:
			continue
		e.set_physics_process(false)   # 冻住，纯为截图
		e.set("state", 0)
		e.queue_redraw()


## R19a（开发用）：直接进序章第 i 间房 —— 截图 / 手感调试用（不改存档标记）
func debug_prologue(i: int = 0) -> void:
	Cfg.prologue_done = false
	# 截图要看完整台词：先把「已见」抹掉（只在内存里，不改存档的其它键）
	for k in Cfg.seen_lines.keys():
		if str(k).begins_with("prologue:"):
			Cfg.seen_lines.erase(k)
	prologue_mode = false
	_start_run(false)
	player.set_weapon("sword")
	_enter_prologue()
	if i > 0 and i < rooms.size():
		_enter_room(i)


## R19b（开发用）：直接站到心魔境，把镜像摆出来 —— 截图 / 手感调试用
## （shot.gd 每次只能传一个参数，所以战斗房与关底拆成两个方法）
func debug_mirror(weapon_id: String = "sword") -> void:
	if player == null:
		return
	_start_run(false)
	player.set_weapon(weapon_id)
	_enter_level(RoomScript.finale_level())
	_enter_room(1)


func debug_mirror_boss(weapon_id: String = "sword") -> void:
	if player == null:
		return
	_start_run(false)
	player.set_weapon(weapon_id)
	_enter_level(RoomScript.finale_level())
	_enter_room(5)


## R22（开发用）：让无相·心魔直接开「影·绝招」—— 截图 / 验收用
func debug_mirror_ult(weapon_id: String = "spear") -> void:
	if player == null:
		return
	debug_mirror_boss(weapon_id)
	for e in enemies:
		if is_instance_valid(e) and int(e.get("kind")) == 14:
			e.set("phase", 2)
			e.set("mirror_ult_cd", 0.0)
			e.call("_start_mirror_ult")


## R23（开发用）：直接进今日道劫（今日之镜 · 心魔试炼开局）—— 截图 / 验收用
func debug_daily() -> void:
	_start_run(true)


## R24（开发用）：直接翻到图鉴第五幕（镜）—— 截图 / 验收用
func debug_codex5() -> void:
	_enter_codex("title")
	codex_act = 5
	# 只在内存里点亮 L13（不调 save_cfg，不落盘），截图用
	Cfg.fragments_seen["L13"] = true
	Game.fragments.append("L13")


## R19b（开发用）：清场，只留一个「镜子里的你」站到画面中间 —— 截图用
func debug_mirror_only(weapon_id: String = "sword") -> void:
	if player == null:
		return
	# 截图要看完整文案：把本关的「已见」抹掉（只在内存里，不动存档其它键）
	for k in ["stele:4", "guide:4"]:
		Cfg.seen_lines.erase(k)
	_start_run(false)
	player.set_weapon(weapon_id)
	_enter_level(RoomScript.finale_level())
	_enter_room(1)


## R20（开发用）：直接把 WIN 页置成真结局态 —— 截图 / 验收用，正常流程不会调用
func debug_ending() -> void:
	if player == null:
		return
	_start_run(false)
	_confirm_weapon()
	_enter_level(RoomScript.finale_level())
	_enter_room(5)
	_next_level()


## R21（开发用）：直接把奖励页置成「影法宝掉落」态 —— 截图 / 验收用
func debug_mirror_drop() -> void:
	if player == null:
		return
	_start_run(false)
	_confirm_weapon()
	_enter_level(RoomScript.finale_level())
	_enter_room(5)
	_resolve_room_clear(true)
	for e in enemies.duplicate():
		e.queue_free()
	enemies.clear()
	boss = null
	if fx != null:
		fx.clear_all()
	player.global_position.x = 420.0
	var m: Node = _spawn_enemy(EnemyScript.KIND_SENTINEL, Vector2(760.0, 600.0))
	if m != null:
		_apply_mirror(m)
		m.set_physics_process(false)


## R18b（开发用）：立刻放一次当前武器的绝招 —— 截图 / 手感调试用
func debug_ult(id: String = "sword") -> void:
	if player == null:
		return
	player.set_weapon(id)
	player.facing = 1
	player.hv = 2
	player.hv_level = 2
	player.hv_t = 0.0
	player.call("_ult_begin")


## R32a（开发用）：三格塞满不同丹药 —— 截图验证快捷格排版 / 名字 / 数量
func debug_pills() -> void:
	if player == null:
		return
	_start_run(false)
	player.add_pill("huichun", 2)
	player.add_pill("pojing", 1)
	player.add_pill("jiuzhuan", 1)
	_enter_level(0)
	_enter_room(1)


## R32b（开发用）：三格塞满符 —— 截图验证快捷格对符箓的排版（单字 / 名字 / 说明）
func debug_talismans() -> void:
	if player == null:
		return
	_start_run(false)
	player.add_item("huo", 2)
	player.add_item("zhao", 1)
	player.add_item("feng", 1)
	_enter_level(0)
	_enter_room(1)


## R32b（开发用）：当场放一张召符 + 一张火符 + 一张封符 —— 截图验证纸人 / 火墙 / 霜环
func debug_talisman_fx() -> void:
	if player == null:
		return
	_start_run(false)
	player.add_item("huo", 2)
	player.add_item("zhao", 1)
	player.add_item("feng", 1)
	_enter_level(0)
	_enter_room(1)
	player.facing = 1
	_on_talisman_summon(10.0)
	_on_talisman_fire(player.global_position, Vector2(200.0, 96.0), 1, 2)
	_on_talisman_seal(2.0)


## R32a（开发用）：直接站到商队 —— 截图验证第 4 行「丹药货架」
func debug_shop() -> void:
	if player == null:
		return
	_start_run(false)
	_enter_level(1)
	_enter_room(2)


## R18（开发用）：五种行为变奏一字排开 —— 截图验证徽记 / 护盾环 / 自爆倒计时
func debug_spawn_variants() -> void:
	for e in enemies.duplicate():
		e.queue_free()
	enemies.clear()
	boss = null
	if fx != null:
		fx.clear_all()
	for i in 5:
		var e: Node = _spawn_enemy(EnemyScript.KIND_SENTINEL,
			Vector2(250.0 + float(i) * 130.0, 556.0), i + 1)
		if e == null:
			continue
		e.set_physics_process(false)
		e.set("state", 0)
		if i + 1 == EnemyScript.VAR_BOMB:
			e.call("_start_fuse")   # 让倒计时环走到一半，截图能看到
		e.queue_redraw()


## R18（开发用）：把玩家按到阴界 —— 截图验证「怨灵只在阴界现形」
func debug_player_yin() -> void:
	if player != null:
		player.set_physics_process(false)
		player.depth = 0.92
		player.queue_redraw()
	for e in enemies:
		e.queue_redraw()


## R14：记忆回响 —— 暗色剪影，轮廓光取玩家当前武器配色
func _spawn_echo(pos: Vector2) -> void:
	var e := EnemyScript.new()
	e.setup(EnemyScript.KIND_SENTINEL, pos, player, fx)
	e.arena = Vector2(SpaceScript.ROOM_X0, SpaceScript.ROOM_X1)
	e.make_echo(player.weapon_hue() if player != null else 0.56)
	add_child(e)
	e.killed.connect(_on_enemy_killed)
	e.fired.connect(_on_enemy_fired)
	e.summon.connect(_on_enemy_summon.bind(e))
	e.aoe.connect(_on_enemy_aoe)
	e.parried.connect(_on_enemy_parried)
	e.phase_changed.connect(_on_enemy_phase)
	e.mirror_strike.connect(_on_enemy_mirror_strike)
	e.mirror_burst.connect(_on_enemy_mirror_burst)
	e.spared.connect(_on_enemy_spared)
	enemies.append(e)


## R19b：把一只敌人变成「镜子里的你」——武器与法宝都从玩家身上抄一份。
## 只抄「读得出来的那部分」：射程 / 出招速度 / 伤害（武器）+ 厚度（法宝数量）。
## 换武器之后新刷出来的镜像会跟着换，已经在场上的不会——镜像记的是「进来时的你」。
func _apply_mirror(e) -> void:
	if e == null or player == null or not is_instance_valid(e):
		return
	var wid := "sword"
	var rn := 0
	if is_instance_valid(player):
		wid = str(player.weapon)
		var rel = player.get("relics")
		if rel is Array:
			rn = rel.size()
	e.make_mirror(wid, rn)


# ============================================================ R18b 绝招结算
## R26：绝招反制 —— 玩家开大瞬间，场上二阶段无相·心魔若影·绝招就绪则按概率同步反制
func _on_player_ult_started() -> void:
	for e in enemies:
		if is_instance_valid(e) and e.has_method("try_counter_ult") and e.call("try_counter_ult"):
			break


## 环形绝招（双刀·旋刃；也是没有配置时的兜底「剑气纵横」）
func _on_ult_burst(pos: Vector2, radius: float, dmg: int) -> void:
	if fx != null:
		fx.ring(pos, 12.0, radius * 1.15, Color(1.0, 0.86, 0.5), 0.42, 6.0)
	for e in enemies.duplicate():
		if not _ult_hittable(e):
			continue
		if e.global_position.distance_to(pos) > radius:
			continue
		_ult_hit(e, dmg, pos)


## 直线绝招（剑·一线 / 枪·如龙）
func _on_ult_strike(pos: Vector2, size: Vector2, dir: int, dmg: int) -> void:
	var r := Rect2(pos - size * 0.5, size)
	if fx != null:
		# 只补一点末端闪光；刀光本身由 player 的 beam 画（形状与判定一致）
		fx.burst(pos + Vector2(float(dir) * size.x * 0.42, 0.0), 10, Color(1.0, 0.9, 0.62), 1.2)
	for e in enemies.duplicate():
		if not _ult_hittable(e):
			continue
		if not r.intersects(e.hurt_rect()):
			continue
		_ult_hit(e, dmg, pos + Vector2(float(dir) * size.x * 0.5, 0.0))


## 绝招能不能打到它：死了不算、阴阳不同界不算（守住核心教学，绝招也不例外）
func _ult_hittable(e) -> bool:
	if e == null or not is_instance_valid(e) or e.dead:
		return false
	if player != null and not SpaceScript.lane_ok(player.depth, e.depth):
		return false
	return true


func _ult_hit(e, dmg: int, from: Vector2) -> void:
	if e.can_execute():
		_do_execute(e)
	else:
		e.hurt(dmg, from, true)
		e.add_posture(e.max_posture * 0.18)
		e.add_stagger(26.0)
	player.register_hit(e)
	if fx != null:
		fx.sparks(e.global_position, Vector2.UP, 5, Color(1.0, 0.9, 0.62), 1.1)


# ============================================================ R32b 符箓（落世界的那一半）
## 火符：身前一道火墙（矩形）。命中走和绝招同一条路 —— 处决 / 罡气 / 阴阳同界都照规矩。
func _on_talisman_fire(pos: Vector2, size: Vector2, dir: int, dmg: int) -> void:
	var center := pos + Vector2(float(dir) * size.x * 0.5, 0.0)
	var r := Rect2(center - size * 0.5, size)
	if fx != null:
		fx.beam(center, size, dir, Color(1.0, 0.55, 0.26), 0.45)
		fx.burst(center + Vector2(0, -16.0), 16, Color(1.0, 0.64, 0.30), 1.1)
	Game.add_shake(5.0)
	SFX.play("thunder", 1.4, -14.0)
	for e in enemies.duplicate():
		if not _ult_hittable(e):
			continue
		if not r.intersects(e.hurt_rect()):
			continue
		_ult_hit(e, dmg, center)


## 雷符：5 道天雷随机落点，警示时间错开 0.13 秒 —— 不是同时炸，是一串
func _on_talisman_thunder(count: int, dmg: int) -> void:
	for i in count:
		var x := rng.randf_range(SpaceScript.ROOM_X0 + 70.0, SpaceScript.ROOM_X1 - 70.0)
		var ln := LightningScript.new()
		ln.setup(x, SpaceScript.FLOOR_NEAR_Y, 0.40 + 0.13 * float(i))
		add_child(ln)
		ln.struck.connect(_on_talisman_bolt.bind(dmg))


## 雷符落点：只打敌人，不打玩家（和 Boss 的天雷正好相反）
func _on_talisman_bolt(x: float, radius: float, dmg: int) -> void:
	for e in enemies.duplicate():
		if not _ult_hittable(e):
			continue
		if absf(e.global_position.x - x) > radius + 24.0:
			continue
		_ult_hit(e, dmg, Vector2(x, e.global_position.y - 40.0))


## 召符：纸人跟着你、自动打人，10 秒后自己散掉（不抢操作权）
func _on_talisman_summon(life: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var s := SummonScript.new()
	add_child(s)
	s.setup(self, player, fx, life)
	summons.append(s)
	if fx != null:
		fx.ring(player.global_position, 8.0, 64.0, Color(0.96, 0.90, 0.70), 0.35, 3.0)


## 封符：全场定身（Boss 的折扣在 enemy.freeze 里，一张符封不住 Boss 两秒）
func _on_talisman_seal(dur: float) -> void:
	var n := 0
	for e in enemies.duplicate():
		if e == null or not is_instance_valid(e) or e.dead:
			continue
		e.freeze(dur)
		n += 1
	if fx != null and player != null and is_instance_valid(player):
		# 一圈小冲击波就够 —— 半径开太大（420）会把整块屏幕盖住，
		# 真正表示「封住了谁」的是每只敌人身上的霜环
		fx.ring(player.global_position, 14.0, 170.0, Color(0.66, 0.86, 0.96), 0.45, 3.5)
	if n == 0 and hud != null:
		hud.show_prompt("场 上 无 人 可 封", 1.2)


## 纸人的一击：走统一入口，所以「处决 / 护体罡气 / 阴阳同界」对它一视同仁
func summon_strike(s: Node, target: Node, dmg: int) -> void:
	if target == null or not is_instance_valid(target) or target.dead:
		return
	if s == null or not is_instance_valid(s):
		return
	_ult_hit(target, dmg, s.global_position)


# ============================================================ 敌人信号
func _on_enemy_killed(e) -> void:
	if not is_instance_valid(e):
		return
	enemies.erase(e)
	# R31：精铁只从「精英 / Boss」来 —— 杂兵不掉，避免刷小怪刷满铭刻
	if e.is_elite():
		_drop_iron(e.global_position, 1)
		# R32a：精英有 35% 掉一粒丹药（权重版，九转丹很少见）
		if rng.randf() < 0.35:
			_grant_random_pill(true)
		# R32b：另有 18% 掉一张符
		if rng.randf() < 0.18:
			_grant_random_talisman()
	var was_boss: bool = (e == boss)
	if was_boss:
		_drop_iron(e.global_position, 2)
		# R32a：Boss 必掉一粒丹；R32b：再必掉一张符
		_grant_random_pill(true)
		_grant_random_talisman()
		boss = null
		# 需求④：Boss 死 → 解除锁定、开门
		if boss_room_locked:
			boss_room_locked = false
			_set_gates(false)
			if hud:
				hud.show_prompt("门 锁 解 除", 2.0)
			SFX.play("gate", 1.1, -4.0)
		# R14：Boss 临终一句话（走顶部提示，不覆盖下方的碎片 lore）
		_say_boss_line(int(e.kind), "death", true)
		# 掉落一段剧情（R16：走统一的碎片收集，进图鉴）
		_show_fragment(str(LoreScript.BOSS_LORE.get(int(e.kind), "")))
		# Boss 死 → 关卡通过结算（无论是否还有召唤出的分身）
		_resolve_room_clear(true)
		return

	# 非 Boss（含 Boss 召唤出的分身）：
	#  · Boss 房在 Boss 死前绝不结算（否则会提前开门 / 发奖励）
	#  · 普通房则等所有敌人清空后才结算
	if boss_room_locked:
		return
	if enemies.is_empty():
		_resolve_room_clear(false)


## R38：道心失守的窗口自己走完了，敌人还活着 —— 玩家选择不下手。
## 记一次「放走」：业力 −1（往天道走）。
## 这不是惩罚，是一种代价不同的活法：少一份处决收益，换一份清白。
func _on_enemy_spared(e) -> void:
	if not is_instance_valid(e) or e.dead:
		return
	Game.spared_count += 1
	Game.add_karma(-1)
	if fx:
		fx.text(e.global_position + Vector2(0, -78.0 * e.scale_f), "放 走",
			Color(0.70, 0.92, 0.80), 22, 46)


func _on_enemy_fired(pos: Vector2, dir: Vector2, speed: float) -> void:
	var p := ProjectileScript.new()
	p.setup(pos, dir, speed)
	add_child(p)
	projectiles.append(p)


## R13 飞剑流：连招最后一段甩出 1~3 道飞剑，略作纵向散开
func _on_flying_sword(pos: Vector2, dir: Vector2, dmg: int, count: int) -> void:
	var n := clampi(count, 1, 3)
	var hue := 0.56
	if player != null and is_instance_valid(player):
		hue = player.weapon_hue()
	for i in n:
		var off := 0.0
		if n > 1:
			off = (float(i) - float(n - 1) * 0.5) * 0.16
		var p := ProjectileScript.new()
		p.setup_sword(pos + Vector2(0.0, off * 90.0), dir + Vector2(0.0, off * 0.5), 720.0, dmg, hue)
		p.pierce = player != null and is_instance_valid(player) and player.has_relic("pierce")
		add_child(p)
		projectiles.append(p)
	SFX.play("slash", 1.25, -6.0)


## R29 符剑：射出一道纸符。符击与符阵·万剑都走这里，只是伤害不同。
## 不穿透（符炸了就没了），但判定比飞剑略大 —— 远程武器总得有点容错。
## R30 反震：挡下近战刀锋后，把 1 点伤害弹回挥刀的那只。
## from_pos 就是来袭者的位置（敌人近战传的是 e.global_position），所以按「离 from_pos 最近」找。
func _on_guard_reflect(from_pos: Vector2) -> void:
	if player == null or not is_instance_valid(player):
		return
	var best = null
	var bd := 130.0
	for e in enemies:
		if not is_instance_valid(e) or e.dead:
			continue
		var d: float = e.global_position.distance_to(from_pos)
		if d <= bd:
			bd = d
			best = e
	if best == null:
		return
	best.hurt(1, player.global_position, false)
	best.add_stagger(10.0)
	if fx != null:
		fx.burst(best.global_position, 10, Color(0.74, 0.88, 1.0), 0.8)
		fx.text(best.global_position + Vector2(0.0, -62.0 * best.scale_f), "反 震",
			Color(0.74, 0.88, 1.0), 18, 34)
	SFX.play("clash", 1.35, -9.0)


func _on_talisman_shot(pos: Vector2, dir: Vector2, dmg: int) -> void:
	var hue := 0.78
	if player != null and is_instance_valid(player):
		hue = player.weapon_hue()
	var spd := 620.0
	if player != null and is_instance_valid(player):
		spd = player.talisman_speed()   # R31 迅符：+15%
	var p := ProjectileScript.new()
	p.setup_talisman(pos, dir, spd, maxi(1, dmg), hue)
	# R33a 御剑（满级）：符击穿透 1 个敌人 —— 用的是飞剑早就留好的 pierce 通道
	if player != null and is_instance_valid(player) \
			and MeridianScript.feijian_pierce(player.mer) > 0:
		p.pierce = true
	add_child(p)
	projectiles.append(p)


func _on_enemy_summon(pos: Vector2, count: int, src = null) -> void:
	# R18：纸人剪出来的还是纸人（血 1、不放技能）；其余敌人照旧召魔渊分身
	var paper: bool = src != null and is_instance_valid(src) \
		and int(src.get("kind")) == EnemyScript.KIND_ZHIREN
	for _i in count:
		var off := Vector2(rng.randf_range(-90.0, 90.0), rng.randf_range(-50.0, 30.0))
		if paper:
			var m: Node = _spawn_enemy(EnemyScript.KIND_ZHIREN, pos + off)
			if m != null and is_instance_valid(m):
				m.make_mini()
		else:
			_spawn_enemy(5, pos + off)  # 魔渊分身


func _on_enemy_aoe(pos: Vector2, radius: float) -> void:
	# Boss 范围震波：落下一道天雷警示（复用 lightning 表现），击中则扣血
	var ln := LightningScript.new()
	ln.setup(pos.x, pos.y)
	add_child(ln)
	ln.struck.connect(_on_lightning_struck)


## R22 完全体镜像：无相·心魔的「影·绝招」判定 —— 与玩家 ult_strike 同形的矩形
func _on_enemy_mirror_strike(pos: Vector2, size: Vector2, dir: int) -> void:
	if player == null or not is_instance_valid(player):
		return
	var r := Rect2(pos - size * 0.5, size)
	if fx != null:
		fx.burst(pos + Vector2(float(dir) * size.x * 0.42, 0.0), 10, Color(0.85, 0.78, 1.0), 1.2)
	if r.intersects(player.hurt_rect()) and player.can_be_hurt():
		player.take_hit(pos)


## R22：影·旋刃的圆形判定 —— 与玩家 ult_burst 同形的圆
func _on_enemy_mirror_burst(pos: Vector2, radius: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if fx != null:
		fx.ring(pos, 12.0, radius * 1.15, Color(0.85, 0.78, 1.0), 0.42, 6.0)
	if player.global_position.distance_to(pos) <= radius and player.can_be_hurt():
		player.take_hit(pos)


## R37：轮回使召旧影 —— 沿玩家最近的轨迹生成 n 个影子
func _on_enemy_echo_call(pos: Vector2, count: int) -> void:
	_spawn_echoes_at(pos, count)
	if fx != null:
		fx.ring(pos, 10.0, 120.0, Color(0.78, 0.66, 1.0), 0.4, 4.0)


func _on_lightning_struck(x: float, radius: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.global_position.distance_to(Vector2(x, player.global_position.y)) <= radius:
		player.take_hit(Vector2(x, player.global_position.y - 30.0))


func _on_enemy_parried(e: Node) -> void:
	Game.deflect_count += 1


func _on_player_died() -> void:
	_award_daoyun(false)
	_clear_companions()      # R35：死亡清掉所有同伴
	state = "dead"


# ============================================================ 房间结算
func _resolve_room_clear(was_boss: bool) -> void:
	if room_resolved:
		return
	room_resolved = true
	room_state[room_i] = "cleared"
	# 非 Boss 房：开门进奖励
	if not was_boss:
		_set_gates(false)
		# R19a：序章是教学，不给奖励卡，清完直接下一间
		if prologue_mode:
			_next_room()
			return
		_enter_reward()
	else:
		# Boss 房已击败 → 关卡通过
		# R21：无相·心魔（boss=14）打掉 → 必掉「影」系法宝三选一，选完再过关
		if int(rooms[room_i].get("boss", 2)) == EnemyScript.KIND_BOSS6:
			_enter_mirror_drop()
		else:
			_enter_clear()


## R21：镜像掉落 —— 复用奖励三选一的页面，但卡池固定为「影」系法宝。
## 主题：打赢镜子里的你，你的法宝得到淬炼。选完 _confirm_reward → _next_room → 过关。
func _enter_mirror_drop() -> void:
	reward_cards = RelicScript.mirror_three(player.relics)
	if reward_cards.is_empty():
		# 三件影法宝都拿过了（理论上一局只会掉一次，防御一下）→ 普通过关
		_enter_clear()
		return
	reward_rects = _reward_rects_for(reward_cards.size())
	pick_sel = 0
	reward_title = "镜 中 淬 炼 · 影 之 法 宝"
	pending_relic = ""
	replace_slot = ""
	state = "reward"


## R16：按张数排卡片 —— 3 张沿用旧布局，4 张（位次扩容后）自动收窄间距
func _reward_rects_for(n: int) -> Array:
	if n >= 4:
		var out := []
		for i in 4:
			out.append(Rect2(30.0 + float(i) * 312.0, 296.0, 282.0, 232.0))
		return out
	return [Rect2(186, 296, 282, 232), Rect2(499, 296, 282, 232), Rect2(812, 296, 282, 232)]


func _enter_reward() -> void:
	# R16：抽卡按流派分层 —— 已经在走的位次更容易出
	reward_cards = RelicScript.pick_n_biased(rng, player.relics, 3, _slot_bias(), Game.karma_unlocks_magic_sword())
	if reward_cards.is_empty():
		_next_room()
		return
	reward_rects = _reward_rects_for(reward_cards.size())
	pick_sel = 0
	reward_title = ""
	pending_relic = ""
	replace_slot = ""
	state = "reward"


func _confirm_reward() -> void:
	if pick_sel < reward_cards.size():
		var card: Dictionary = reward_cards[pick_sel]
		var rid := str(card.get("id", ""))
		# R13：本位次满了 → 先选一件弃掉，再放新的
		if rid != "" and not player.has_relic(rid) and player.slot_full(RelicScript.slot_of(rid)):
			_enter_replace(rid)
			return
		player.add_relic(rid)
	_next_room()


## R13：位次满了放不进去 → 化为道蕴（宝箱 / 商队不该白拿）
func _grant_relic_or_soul(id: String, refund: float = 15.0) -> bool:
	if id == "":
		return false
	if player.add_relic(id):
		return true
	player.soul = minf(player.soul + refund, Game.MAX_SOUL)
	hud.show_prompt("%s 位 已 满 · 化 为 道 蕴 +%d" % [
		RelicScript.slot_name(RelicScript.slot_of(id)), int(refund)], 2.2)
	return false


## R13 位次替换：把该位次现有的法宝摆成三张卡，选一件丢掉
func _enter_replace(new_id: String) -> void:
	pending_relic = new_id
	replace_slot = RelicScript.slot_of(new_id)
	reward_title = "%s 位 已 满 · 选 一 件 弃 掉" % RelicScript.slot_name(replace_slot)
	reward_cards = []
	for id in player.slot_list(replace_slot):
		var dat: Dictionary = RelicScript.by_id(str(id))
		if not dat.is_empty():
			reward_cards.append(dat)
	reward_rects = _reward_rects_for(reward_cards.size())
	pick_sel = 0
	state = "replace"


## R16：位次扩容 —— 花道蕴把这一位从 3 格扩到 4 格，新法宝直接放进去（不用再弃一件）
func can_expand_now() -> bool:
	return state == "replace" and replace_slot != "" \
		and player != null and player.can_expand_slot(replace_slot) \
		and player.soul >= player.SLOT_EXPAND_COST


func _expand_replace_slot() -> void:
	if not can_expand_now():
		if player != null and player.soul < player.SLOT_EXPAND_COST and hud != null:
			hud.show_prompt("道 蕴 不 足 · 需 %d" % int(player.SLOT_EXPAND_COST), 1.8)
		return
	var sl := replace_slot
	player.soul -= player.SLOT_EXPAND_COST
	player.expand_slot(sl)
	player.add_relic(pending_relic)
	if hud != null:
		hud.show_prompt("%s 位 扩 到 %d 格 · 法 宝 已 收 下" % [
			RelicScript.slot_name(sl), player.slot_cap(sl)], 2.4)
	SFX.play("heal", 1.0, -2.0)
	pending_relic = ""
	replace_slot = ""
	reward_title = ""
	_next_room()


func _confirm_replace() -> void:
	if pick_sel < reward_cards.size():
		var old_id := str(reward_cards[pick_sel].get("id", ""))
		player.swap_relic(old_id, pending_relic)
	pending_relic = ""
	replace_slot = ""
	reward_title = ""
	_next_room()


## 选下一个还没清场的邻居房间；若全清 → 关卡通过
func _next_room() -> void:
	if prologue_mode:
		if room_i + 1 < rooms.size():
			_enter_room(room_i + 1)
		else:
			_finish_prologue()
		return
	var nb: Dictionary = RoomScript.neighbors(level_index, room_i)
	var next_i := -1
	for k in nb.keys():
		var j: int = int(nb[k])
		if room_state[j] != "cleared":
			next_i = j
			break
	if next_i < 0:
		# 没有未清场的邻居，但本关还有别的房没清 → 找任意 new 房
		for j in rooms.size():
			if room_state[j] != "cleared":
				next_i = j
				break
	if next_i < 0:
		_enter_clear()
		return
	_enter_room(next_i)


## R28：破劫评分 —— 纯函数，便于自测；所有分项都写得明明白白
## cleared  是否通关（未通关只给进度分，时间 / 剩血 / 无伤都不算）
## secs     战斗用时（秒）      dmg  受击次数
## hp       剩余气血            rooms 已清房间数
static func score_of(cleared: bool, secs: float, dmg: int, hp: int, rooms: int) -> int:
	var sc := 0
	# ① 进度分：每清一间房 12 分（哪怕打输了也认，鼓励往前推）
	sc += maxi(0, rooms) * 12
	if not cleared:
		return maxi(0, sc)
	# ② 通关分
	sc += 80
	# ③ 用时：300 秒内线性给分，越快越多（300s 外为 0，不倒扣）
	sc += int(maxf(0.0, 300.0 - maxf(0.0, secs)) * 0.6)
	# ④ 无伤：一次没挨满 120；挨过则每次 −8，最多扣 80
	sc += 120 if dmg <= 0 else -mini(dmg * 8, 80)
	# ⑤ 剩血：每格 20
	sc += maxi(0, hp) * 20
	return maxi(0, sc)


## R28：把本次成绩写进本地榜（只对今日道劫生效）
func _submit_daily_score() -> void:
	var hp_now := int(player.hp) if player != null and is_instance_valid(player) else -1
	var dmg_now := int(Game.dmg_taken)
	var sc := score_of(true, _run_t, dmg_now, hp_now, 6)
	daily_score_now = sc
	Cfg.daily_time = _run_t
	Cfg.daily_dmg = dmg_now
	Cfg.daily_score = sc
	Cfg.daily_date = RoomScript.today_key()
	Cfg.daily_rooms = 6
	Cfg.daily_cleared = true
	Cfg.daily_hp = hp_now
	daily_rank = Cfg.push_daily_record(RoomScript.today_key(), sc, _run_t, dmg_now, hp_now)
	Cfg.save_cfg()


func _enter_clear() -> void:
	state = "clear"
	if daily_mode:
		# R28：破劫评分 + 本地榜（R23 只记了剩血，评分和榜是这轮补的）
		_submit_daily_score()


func _next_level() -> void:
	if level_index + 1 < RoomScript.level_count():
		_enter_level(level_index + 1)
	else:
		_award_daoyun(true)
		state = "win"
		# R20：心魔境（最后一关）打完 → 真结局。WIN 页按身份档位换终局文案。
		true_ending = level_index >= RoomScript.level_count() - 1


func _enter_setting() -> void:
	prev_state = state
	state = "setting"
	menu_sel = 0
	menu_action = 0
	_slot_msg = ""


func _enter_pause() -> void:
	if state != "play":
		return
	prev_state = state
	state = "pause"


func _die() -> void:
	_award_daoyun(false)
	state = "dead"


func _win() -> void:
	_award_daoyun(true)
	state = "win"


# ============================================================ 主循环
func _process(delta: float) -> void:
	# 同步 HUD 接线
	if hud:
		hud.mode = state
		hud.player = player
		hud.boss = boss
		hud.game = self
		hud.level_name = level_name
		hud.room_name = room_name
		hud.touch_mode = touch_mode

	# 键盘菜单输入（玩家自身的移动 / 攻击由 player.gd 直接读 InputMap）
	_do_input()
	# R31：铭刻页的反馈计时（不受 state 影响，退出页面时自然归零）
	if forge_msg_t > 0.0:
		forge_msg_t = maxf(0.0, forge_msg_t - delta)
	if mer_msg_t > 0.0:
		mer_msg_t = maxf(0.0, mer_msg_t - delta)

	_update_guide(delta)
	_flush_self_unlock()

	if state == "play":
		_run_t += delta
		_record_echo_trail(delta)
		_combat_checks(delta)
		_trap_check(delta)
		_collect_eggs()
		_update_projectiles()
		_update_combo(delta)
	# 其它状态也持续清理失效弹幕引用
	if state != "play":
		_update_projectiles()


# ============================================================ R35 灵兽蛋拾取
func _collect_eggs() -> void:
	if player == null or not is_instance_valid(player) or player.dead:
		return
	for i in eggs.size() - 1:
		var egg = eggs[i]
		if not is_instance_valid(egg):
			eggs.remove_at(i)
			continue
		if egg.global_position.distance_to(player.global_position) < 64.0:
			grant_companion(int(egg.kind))
			eggs.remove_at(i)
			egg.queue_free()


# ============================================================ 战斗检测（剑意交锋 / 命中）
func _combat_checks(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.dead:
		return

	# 1) 剑意交锋：玩家刀锋 vs 敌人攻击判定（enemy.attack_rect 仅在 ATTACK 帧非空，天然只判定攻击瞬间）
	for e in enemies:
		if not is_instance_valid(e) or e.dead:
			continue
		var er: Rect2 = e.attack_rect()
		if not er.has_area():
			continue
		var pr: Rect2 = player.clash_rect()
		if not pr.has_area():
			continue
		if pr.intersects(er) and not e.clashed:
			_perform_clash(e)

	# 1.5) 凝罡·开山 的刀锋：蓄力斩会把 atk 清空（不走连招），所以单独判一次 heavy_rect
	var hr: Rect2 = player.heavy_rect()
	if hr.has_area():
		for e in enemies:
			if not is_instance_valid(e) or e.dead:
				continue
			if hr.intersects(e.hurt_rect()) and not player.hit_targets.has(e):
				if e.can_execute():
					_do_execute(e)
				else:
					e.hurt(player.heavy_damage(), player.global_position, true)
					# R18：重击是破防的主力手段（护体罡气 3 下见底）
					e.add_posture(e.max_posture * player.HEAVY_POSTURE_FRAC)
					e.add_stagger(40.0)
				player.register_hit(e)

	# 2) 玩家攻击命中敌人（普通伤害 / 道心失守时处决）
	var par: Rect2 = player.attack_rect()
	if par.has_area():
		for e in enemies:
			if not is_instance_valid(e) or e.dead:
				continue
			if par.intersects(e.hurt_rect()) and not player.hit_targets.has(e):
				if e.can_execute():
					_do_execute(e)
				else:
					var heavy: bool = player.is_heavy_active()
					# R16：把动作标签传给敌人 —— 上挑造成浮空、下劈砸落浮空目标、突刺更容易被 Boss 招架
					var tg: String = "" if heavy else player.attack_tag()
					var dmg_now: int = player.attack_damage(e.global_position)
					e.hurt(dmg_now, player.global_position, heavy, tg)
					# R30 会心：attack_damage() 里滚过一次，这里只负责表现
					if player.last_crit() and fx != null:
						fx.text(e.global_position + Vector2(0.0, -72.0 * e.scale_f), "会 心",
							Color(1.0, 0.86, 0.42), 22, 46)
						SFX.play("clash_perfect", 1.22, -8.0)
					if tg == WeaponScript.TAG_UP and not e.dead:
						e.add_air_stun(WeaponScript.AIR_STUN_TIME)
					# R12：命中涨敌方护体罡气 —— 连招压制是逼出「道心失守」的第二条路（第一条是悟道·剑意交锋）
					var pf: float = player.attack_posture_frac()
					if pf > 0.0:
						e.add_posture(e.max_posture * pf)
				player.register_hit(e)

	# 4) 处决输入：道心失守敌人进入近身范围时按下处决（键盘 F / 触摸复用攻击）
	if Input.is_action_just_pressed("execute"):
		_try_execute()

	# 3) 敌人攻击命中玩家（非剑意交锋时）
	for e in enemies:
		if not is_instance_valid(e) or e.dead:
			continue
		var ear: Rect2 = e.attack_rect()
		if ear.has_area() == false:
			continue
		if ear.intersects(player.hurt_rect()):
			# 玩家正在格挡且朝向敌人 → 交给 player.take_hit 处理（内部含格挡）
			player.take_hit(e.global_position)


## 护体罡气交锋（R11）：剑意交锋 → 普通格挡涨自身护体罡气 / 完美弹反涨敌方护体罡气
## 需求⑤：持续攻击（连段 / 没停手）不触发悟道·剑意交锋。
## 完美资格由 player.perfect_ready 决定：必须「停手 ≥ PERFECT_GAP 后再出第一刀」才算。
func _perform_clash(e) -> void:
	e.clashed = true
	var perfect: bool = player.perfect_ready
	player.on_clash(e.global_position)
	e.on_clash(perfect)
	if perfect:
		# 完美弹反：玩家护体罡气不涨；敌方护体罡气大涨（可直接逼出道心失守）
		player.on_perfect_parry()
		# R30 断念：完美弹反的敌方罡气从 40% 提到 55%（代价是自身罡气上限 -15）
		var clash_push := 0.55 if player.has_relic("duannian") else 0.40
		e.add_posture(e.max_posture * clash_push)
		e.add_stagger(28.0)
		Game.perfect_count += 1
		player.soul = minf(player.soul + Game.SOUL_PER_PERFECT * player.soul_mul(), Game.MAX_SOUL)
		Game.perfect_flash = 1.0
		SFX.play("clash_perfect", 0.95, -1.0)
		if fx:
			fx.text(player.global_position + Vector2(0, -56), "悟 道 · 剑 意 交 锋", Color(1.0, 0.92, 0.6), 24, 44)
	else:
		# 普通格挡：玩家自身护体罡气上涨；敌方获得少量硬直
		player.on_guard()
		e.add_stagger(18.0)
		Game.clash_count += 1
		player.soul = minf(player.soul + Game.SOUL_PER_CLASH * player.soul_mul(), Game.MAX_SOUL)
		SFX.play("clash", 0.85, -3.0)
	Game.add_shake(11.0)
	Game.hitstop(0.09, 0.03)

	# 连斩计数（用于 HUD）
	combo_hits += 1
	Game.max_combo = maxi(Game.max_combo, combo_hits)


## 处决（R11）：道心失守敌人在近身范围内时，按下「处决」直接造成处决伤害并重置其护体罡气
func _try_execute() -> bool:
	var best = null
	var best_d := INF
	for e in enemies:
		if not is_instance_valid(e) or e.dead or not e.can_execute():
			continue
		var d: float = player.global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	if best != null and best_d <= 110.0:
		return _do_execute(best)
	return false


func _do_execute(e) -> bool:
	if e == null or not is_instance_valid(e) or e.dead or not e.can_execute():
		return false
	var dmg: int = e.execute_damage()
	# R38 魔剑：处决伤害翻倍，且处决完回 1 点气血（代价是气血上限 -1，见 player.max_hp）
	var has_magic: bool = player != null and is_instance_valid(player) and player.has_relic("magic")
	if has_magic:
		dmg *= 2
	e.hurt(dmg, player.global_position, false)
	e.reset_posture()
	# R29 符剑的处决是「符爆」：符在目标体内炸开，波及半径内其它敌人（各 1 点 + 重置罡气）
	if player != null and is_instance_valid(player) and player.weapon == "rune":
		var blast: float = PlayerScript.RUNE_BLAST_RADIUS
		for other in enemies:
			if other == e or not is_instance_valid(other) or other.dead:
				continue
			if other.global_position.distance_to(e.global_position) <= blast:
				other.hurt(1, e.global_position, false)
				other.reset_posture()
		if fx:
			fx.ring(e.global_position, 10.0, blast, Color(0.86, 0.74, 1.0), 0.32, 4.0)
			fx.burst(e.global_position, 16, Color(0.90, 0.80, 1.0), 1.2)
	if fx:
		fx.burst(e.global_position, 26, Color(1.0, 0.55, 0.55), 1.1)
		fx.text(e.global_position + Vector2(0, -84.0 * e.scale_f), "处 决", Color(1.0, 0.5, 0.5), 30, 54)
	SFX.play("clash_perfect", 0.9, 0.0)
	Game.add_shake(16.0)
	Game.hitstop(0.14, 0.02)
	Game.execute_count += 1
	# R38 魔剑：以杀养身 —— 处决后回 1 点（不超上限）
	if has_magic and player.hp < player.max_hp():
		player.hp = mini(player.hp + 1, player.max_hp())
	# R38：处决 = 赶尽杀绝，业力 +1（往魔道走）
	Game.add_karma(1)
	return true


func _trap_check(delta: float) -> void:
	if world.extra_spikes.is_empty():
		return
	_trap_t -= delta
	if _trap_t > 0.0:
		return
	for s in world.extra_spikes:
		var rc: Rect2 = s
		if rc.has_point(player.global_position):
			_trap_t = 0.55
			player.take_hit(Vector2(player.global_position.x, player.global_position.y - 30.0))
			return


func _update_projectiles() -> void:
	for i in range(projectiles.size() - 1, -1, -1):
		var p = projectiles[i]
		if not is_instance_valid(p):
			projectiles.remove_at(i)
			continue
		var rc: Rect2 = p.rect()
		if p.hostile:
			# 命中玩家
			if rc.intersects(player.hurt_rect()):
				# R30：弹幕不算近战刀锋 —— 反震对它无效
				player.take_hit(p.global_position, false)
				p.queue_free()
				projectiles.remove_at(i)
				continue
			# 玩家刀锋弹反
			if player.clash_rect().has_area() and rc.intersects(player.clash_rect()) \
					and not player.is_heavy_active():
				p.deflect()
		else:
			# 友方弹幕打敌人（R13 飞剑：伤害来自 player.flying_damage，穿云可穿透）
			for e in enemies:
				if not is_instance_valid(e) or e.dead:
					continue
				if p.already_hit(e):
					continue
				if rc.intersects(e.hurt_rect()):
					e.hurt(p.dmg, p.global_position, false)
					if player != null and is_instance_valid(player) and player.has_relic("pierce"):
						player.soul = minf(player.soul + 3.0, Game.MAX_SOUL)
					if p.pierce:
						p.mark_hit(e)
						continue
					p.queue_free()
					projectiles.remove_at(i)
					break


func _update_combo(delta: float) -> void:
	if player == null:
		return
	if player.atk == ATK_NONE:
		_combo_t += delta
		if _combo_t > 1.2:
			combo_hits = 0
	else:
		_combo_t = 0.0


# ============================================================ 键盘菜单输入
func _do_input() -> void:
	match state:
		"title":
			_title_input()
		"weapon":
			_weapon_input()
		"setting":
			_setting_input()
		"reward", "replace":
			_reward_input()
		"event":
			_event_input()
		"pause":
			_pause_input()
		"clear":
			_clear_input()
		"codex":
			_codex_input()
		"forge":
			_forge_input()
		"meridian":
			_meridian_input()
		"dead", "win":
			if Input.is_action_just_pressed("restart"):
				_start_run(daily_mode)
		"play":
			if Input.is_action_just_pressed("pause"):
				_enter_pause()
			elif Input.is_action_just_pressed("settings"):
				_enter_setting()
			# R32a：快捷格（键盘 1/2/3；触屏是左侧三颗钮，走同一套 action）
			for qi in range(3):
				if Input.is_action_just_pressed("quick%d" % (qi + 1)):
					_use_quick(qi)


func _title_input() -> void:
	if Input.is_action_just_pressed("up"):
		title_sel = (title_sel + 4) % 5
		SFX.play("slash", 0.7, -8.0)
	elif Input.is_action_just_pressed("down"):
		title_sel = (title_sel + 1) % 5
		SFX.play("slash", 0.7, -8.0)
	elif Input.is_action_just_pressed("start"):
		_confirm_title()


func _confirm_title() -> void:
	match title_sel:
		0:
			_start_run(false)
		1:
			_start_run(true)
		2:
			_enter_setting()
		3:
			_enter_codex("title")
		4:
			_enter_meridian("title")


# ============================================================ R16 残卷图鉴
## 图鉴是局外页面（标题页 / 暂停页都能进），翻幕看 12 条残卷
var codex_from := "title"


func _enter_codex(from_state: String) -> void:
	codex_from = from_state
	codex_act = 1
	state = "codex"


func _exit_codex() -> void:
	state = codex_from if codex_from != "" else "title"

# ============================================================ R33a 经脉（局外成长）
## 经脉页是**局外**页面：标题页第 5 行进，Esc 回标题页。
## 它不改本局的任何随机性 —— 只改基础手感，且每级 ≤ +10%。
## 洗点返还 70%，所以「点错了」不会毁档。

func _enter_meridian(from_state: String) -> void:
	meridian_from = from_state
	mer_msg = ""
	mer_msg_t = 0.0
	state = "meridian"


func _exit_meridian() -> void:
	state = meridian_from if meridian_from != "" else "title"


## 当前脉里的第几条（0..7）：2 列 × 4 行，列优先（0-3 左列 / 4-7 右列）
func mer_sel_row() -> int:
	return clampi(mer_row, 0, 7)


## 当前是第几脉（0..2）—— R33b 起它同时就是「页签」
func mer_sel_mer() -> int:
	return clampi(mer_col, 0, MeridianScript.MERS.size() - 1)


## 全树里的绝对下标（0..23）
func mer_sel_index() -> int:
	return mer_sel_mer() * 8 + mer_sel_row()


## 当前这一脉的 8 个节点矩形（2 列 × 4 行）—— hud 只负责画，判定在这里，两边共用一份
func mer_node_rects() -> Array:
	var out: Array = []
	for k in 8:
		var col := 0 if k < 4 else 1
		var row := k % 4
		out.append(Rect2(296.0 + 356.0 * float(col), 214.0 + 100.0 * float(row), 332.0, 88.0))
	return out


func mer_sel_id() -> String:
	if mer_col == MER_TAB_ALCH:
		return alch_sel_id()
	var nodes: Array = MeridianScript.by_mer(str(MeridianScript.MERS[mer_sel_mer()]["id"]))
	if nodes.is_empty():
		return ""
	return str(nodes[clampi(mer_sel_row(), 0, nodes.size() - 1)]["id"])


# ============================================================ R33c 丹房（局外合成）
## 丹房 12 张方子：4 列 × 3 行，行优先（0-3 第一行 / 4-7 第二行 / 8-11 第三行）
func alch_rects() -> Array:
	var out: Array = []
	for k in 12:
		var col := k % 4
		var row := 0 if k < 4 else (1 if k < 8 else 2)
		out.append(Rect2(124.0 + 264.0 * float(col), 214.0 + 124.0 * float(row), 240.0, 108.0))
	return out


## 丹房选中哪张方子（mer_row 在丹房页里是 0..11）
func alch_sel_row() -> int:
	return clampi(mer_row, 0, 11)


func alch_sel_id() -> String:
	var rec: Array = AlchemyScript.recipes()
	if rec.is_empty():
		return ""
	return str(rec[alch_sel_row()]["id"])


## 炼一份（成功 / 失败都返回一行原因 —— 不做「按了没反应」）
func alch_craft() -> String:
	var id := alch_sel_id()
	if id == "":
		return "丹 房 为 空"
	var r: Dictionary = AlchemyScript.recipe(id)
	if r.is_empty():
		return "没 有 这 张 方 子"
	var c := int(r["cost"])
	var have := Cfg.pantry_total()
	if have >= AlchemyScript.PANTRY_CAP:
		return "丹 房 已 满（%d / %d）· 先 带 进 一 局 再 炼" % [have, AlchemyScript.PANTRY_CAP]
	if Cfg.daoyun < c:
		return "道 痕 不 足 · 还 差 %d" % (c - Cfg.daoyun)
	if not Cfg.pantry_add(id, 1, c):
		return "道 痕 不 足"
	SFX.play("heal", 1.15, -5.0)
	return "炼 成 %s（−%d 道 痕）" % [str(r["name"]), c]


func _say_mer(t: String) -> void:
	mer_msg = t
	mer_msg_t = 2.4


## 升一级（成功返回一行反馈，失败也返回原因 —— 不做「按了没反应」）
func mer_upgrade() -> String:
	var id := mer_sel_id()
	if id == "":
		return "经 脉 表 为 空"
	var n: Dictionary = MeridianScript.node(id)
	var cur := Cfg.mer_lv(id)
	var c := MeridianScript.cost(id, cur)
	if c < 0:
		return "%s 已 满 级" % str(n.get("name", id))
	if Cfg.daoyun < c:
		return "道 痕 不 足 · 还 差 %d" % (c - Cfg.daoyun)
	if not Cfg.mer_up(id):
		return "道 痕 不 足"
	SFX.play("heal", 1.15, -5.0)
	# 玩家的 mer 是 Cfg.meridian_lv 的引用，升完立刻生效，不用重建玩家
	return "%s → %d 级（−%d 道 痕）" % [str(n.get("name", id)), cur + 1, c]


func mer_respec() -> String:
	var back := Cfg.mer_respec()
	if back <= 0:
		return "尚 未 点 过 经 脉"
	SFX.play("gate", 1.2, -6.0)
	return "已 洗 点 · 退 回 %d 道 痕" % back


func _meridian_input() -> void:
	var moved := false
	if mer_col == MER_TAB_ALCH:
		# 丹房：4 列 × 3 行，行优先
		var c0 := alch_sel_row() % 4
		var r0 := 0 if alch_sel_row() < 4 else (1 if alch_sel_row() < 8 else 2)
		if Input.is_action_just_pressed("left"):
			mer_row = r0 * 4 + posmod(c0 - 1, 4)
			moved = true
		elif Input.is_action_just_pressed("right"):
			mer_row = r0 * 4 + (c0 + 1) % 4
			moved = true
		elif Input.is_action_just_pressed("up"):
			mer_row = posmod(r0 - 1, 3) * 4 + c0
			moved = true
		elif Input.is_action_just_pressed("down"):
			mer_row = ((r0 + 1) % 3) * 4 + c0
			moved = true
	else:
		# 经脉：2 列 × 4 行，列优先；↑↓ 在本列内循环（左列 0-3 / 右列 4-7）
		if Input.is_action_just_pressed("up") or Input.is_action_just_pressed("down"):
			var step := -1 if Input.is_action_just_pressed("up") else 1
			var base := 0 if mer_sel_row() < 4 else 4
			mer_row = base + posmod(mer_sel_row() - base + step, 4)
			moved = true
		elif Input.is_action_just_pressed("left") or Input.is_action_just_pressed("right"):
			mer_row = (mer_sel_row() + 4) % 8
			moved = true
	# 1 / 2 / 3 / 4：切页签（4 = 丹房）
	var tab_keys: Array = ["quick1", "quick2", "quick3", "quick4"]
	for ti in tab_keys.size():
		if Input.is_action_just_pressed(str(tab_keys[ti])) and mer_col != ti:
			mer_col = ti
			mer_row = 0
			moved = true
	if moved:
		SFX.play("slash", 0.7, -8.0)
	if Input.is_action_just_pressed("start"):
		_say_mer(alch_craft() if mer_col == MER_TAB_ALCH else mer_upgrade())
	if Input.is_action_just_pressed("restart") and mer_col != MER_TAB_ALCH:
		_say_mer(mer_respec())
	if Input.is_action_just_pressed("pause"):
		_exit_meridian()


## 触屏：点一下选中，再点一下升级 / 合成（两下才花钱，防误触）
func mer_hit(pos: Vector2) -> bool:
	if state != "meridian":
		return false
	if mer_col == MER_TAB_ALCH:
		if BTN_ALCH_BACK.has_point(pos):
			_exit_meridian()
			return true
	else:
		if BTN_MER_BACK.has_point(pos):
			_exit_meridian()
			return true
		if BTN_MER_RESPEC.has_point(pos):
			_say_mer(mer_respec())
			return true
	# 页签
	for ti in BTN_MER_TABS.size():
		var tr: Rect2 = BTN_MER_TABS[ti]
		if tr.has_point(pos):
			if mer_col != ti:
				mer_col = ti
				mer_row = 0
				SFX.play("slash", 0.7, -8.0)
			return true
	# 当前页的格子（经脉 8 格 / 丹房 12 格）
	var alch := mer_col == MER_TAB_ALCH
	var rects: Array = alch_rects() if alch else mer_node_rects()
	var cur := alch_sel_row() if alch else mer_sel_row()
	for k in rects.size():
		var r: Rect2 = rects[k]
		if not r.has_point(pos):
			continue
		if cur == k:
			_say_mer(alch_craft() if alch else mer_upgrade())
		else:
			mer_row = k
			SFX.play("slash", 0.7, -8.0)
		return true
	return false


## R33a（开发用）：给一笔道痕并打开经脉页 —— 截图 / 验收用
func debug_meridian(amount: int = 200) -> void:
	Cfg.daoyun += amount
	_enter_meridian("title")


## R33b（开发用）：跳到「第几脉 : 第几格」—— 截图 / 验收用
## 参数走字符串（"2:5"），这样 shot.gd 的单参数调用也能用
func debug_mer_goto(spec: String) -> void:
	var parts := spec.split(":")
	if parts.size() >= 1 and parts[0].is_valid_int():
		mer_col = clampi(parts[0].to_int(), 0, MeridianScript.MERS.size() - 1)
	if parts.size() >= 2 and parts[1].is_valid_int():
		mer_row = clampi(parts[1].to_int(), 0, 7)


## R33c（开发用）：给一笔道痕并打开丹房页 —— 截图 / 验收用
func debug_alch(amount: int = 300) -> void:
	Cfg.daoyun += amount
	_enter_meridian("title")
	mer_col = MER_TAB_ALCH
	mer_row = 0


## R33a（开发用）：把道痕与经脉清零 —— 截图之后抹掉测试给的点数
func debug_meta_reset() -> void:
	Cfg.daoyun = 0
	Cfg.daoyun_total = 0
	Cfg.meridian_lv.clear()
	Cfg.save_cfg()
	player.mer = Cfg.meridian_lv



# ============================================================ R31 兵器铭刻
## 铭刻页从暂停页进（键盘 M / 触屏点「兵 器 铭 刻」）。
## 它不是一个「新系统」，只是把 player 身上的两格铭刻 + 精铁摆出来让人操作：
##   空槽 → 花 2 精铁刻一条随机词条
##   有词条 → 花 3 精铁洗练（重 roll，排除另一槽已有的）
## 精铁只从精英（+1）和 Boss（+2）来，杂兵不掉。

func _enter_forge() -> void:
	forge_sel = 0
	forge_msg = ""
	forge_msg_t = 0.0
	state = "forge"


func _exit_forge() -> void:
	state = "pause"


func _forge_input() -> void:
	if (Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("forge")
			or Input.is_action_just_pressed("codex")):
		_exit_forge()
		return
	if Input.is_action_just_pressed("left") or Input.is_action_just_pressed("up"):
		forge_sel = (forge_sel + 1) % InscribeScript.SLOTS
		SFX.play("slash", 0.7, -8.0)
	elif Input.is_action_just_pressed("right") or Input.is_action_just_pressed("down"):
		forge_sel = (forge_sel + InscribeScript.SLOTS - 1) % InscribeScript.SLOTS
		SFX.play("slash", 0.7, -8.0)
	elif Input.is_action_just_pressed("start") or Input.is_action_just_pressed("execute"):
		_forge_action()


## 刻 / 洗。两件事共用同一个键，按槽当前状态分派 —— 玩家只需要记「空格 = 动这个槽」
func _forge_action() -> void:
	if player == null or not is_instance_valid(player):
		return
	var slots: Array = player.inscribe_slots()
	var i := clampi(forge_sel, 0, slots.size() - 1)
	var had := str(slots[i]) != ""
	var ok := false
	if had:
		ok = player.reforge_slot(i, rng)
	else:
		ok = player.forge_slot(i, rng)
	if ok:
		var id := str(player.inscribe_slots()[i])
		forge_msg = ("洗 成 了 · %s" if had else "刻 上 了 · %s") % InscribeScript.name_of(id)
		SFX.play("clash_perfect", 1.05, -6.0)
		if fx != null:
			fx.text(player.global_position + Vector2(0, -86.0), forge_msg,
				Color(1.0, 0.92, 0.66), 18, 40)
	else:
		var need: int = InscribeScript.COST_REFORGE if had else InscribeScript.COST_FORGE
		if player.iron < need:
			forge_msg = "精 铁 不 足 · 需 %d（现有 %d）" % [need, player.iron]
		else:
			forge_msg = "词 条 已 满"
		SFX.play("hurt", 1.3, -12.0)
	forge_msg_t = 2.2


func forge_hit(pos: Vector2) -> bool:
	# 触屏：点两个槽选中，点底部按钮动它，点返回离开
	for i in InscribeScript.SLOTS:
		if _forge_slot_rect(i).has_point(pos):
			forge_sel = i
			return true
	if BTN_FORGE_ACTION.has_point(pos):
		_forge_action()
		return true
	if BTN_FORGE_BACK.has_point(pos):
		_exit_forge()
		return true
	return false


## 槽的矩形（HUD 绘制与触屏命中共用同一个算式，避免画一个点另一个）
func _forge_slot_rect(i: int) -> Rect2:
	return Rect2(230.0, 236.0 + float(i) * 132.0, 820.0, 112.0)


## 精铁掉落（精英 +1 / Boss +2）。走 Game 的飘字与音效，不做实体拾取 —— 
## 这是「结算式资源」，不是「地上捡的东西」，省掉一条拾取交互。
func _drop_iron(pos: Vector2, n: int) -> void:
	if player == null or not is_instance_valid(player):
		return
	player.add_iron(n)
	if fx != null:
		fx.text(pos + Vector2(0, -64.0), "精 铁 +%d" % n, Color(0.78, 0.86, 0.98), 16, 38)
	SFX.play("gate", 1.5, -14.0)


# ---------------------------------------------------------------- R32a 丹药 / 快捷格
## 吃一格丹药。成功 / 失败都给顶部提示 —— 失败不说话，玩家会以为「按了没反应」。
func _use_quick(i: int) -> void:
	if player == null or not is_instance_valid(player):
		return
	var r: Dictionary = player.use_quick(i)
	var msg := str(r.get("msg", ""))
	if bool(r.get("ok", false)):
		if hud:
			hud.show_prompt("服 丹 · %s" % msg, 1.4)
		return
	if msg != "":
		if hud:
			hud.show_prompt(msg, 1.2)
		SFX.play("gate", 1.6, -16.0)


## 进一个消耗品（丹药或符箓）：快捷格满了就折成 8 道蕴（不让拾取白掉）
func _grant_item(id: String) -> void:
	if player == null or not is_instance_valid(player):
		return
	if id == "":
		return
	var noun := "符" if ConsumeScript.is_talisman(id) else "丹"
	if player.add_item(id, 1):
		if fx != null:
			fx.text(player.global_position + Vector2(0, -70.0),
				"%s +1" % ConsumeScript.name_of(id), ConsumeScript.tint_of(id), 16, 40)
		if hud:
			hud.show_prompt("得 %s · %s" % [noun, ConsumeScript.name_of(id)], 1.6)
	else:
		player.soul = minf(player.soul + 8.0, Game.MAX_SOUL)
		if hud:
			hud.show_prompt("三 格 已 满 · 折 道 蕴 8", 1.8)
	SFX.play("heal", 1.25, -6.0)


## 兼容旧调用（自测 / 宝箱都走这条）
func _grant_pill(id: String) -> void:
	_grant_item(id)


## 随机掉一粒（精英 / Boss 用权重版，宝箱用均等版）
func _grant_random_pill(weighted: bool = false) -> void:
	var id := ConsumeScript.roll_drop(rng) if weighted else ConsumeScript.roll(rng)
	_grant_item(id)


## 随机掉一张符
func _grant_random_talisman() -> void:
	_grant_item(ConsumeScript.roll_talisman(rng))


func _codex_input() -> void:
	var n := LoreScript.act_count()
	if Input.is_action_just_pressed("left"):
		codex_act = (codex_act + n - 2) % n + 1
		SFX.play("slash", 0.7, -8.0)
	elif Input.is_action_just_pressed("right"):
		codex_act = codex_act % n + 1
		SFX.play("slash", 0.7, -8.0)
	elif Input.is_action_just_pressed("start") or Input.is_action_just_pressed("pause"):
		_exit_codex()


func codex_hit(pos: Vector2) -> bool:
	# 左右两个翻幕箭头 + 底部「返回」
	if CODEX_LEFT.has_point(pos):
		codex_act = (codex_act + LoreScript.act_count() - 2) % LoreScript.act_count() + 1
		return true
	if CODEX_RIGHT.has_point(pos):
		codex_act = codex_act % LoreScript.act_count() + 1
		return true
	if CODEX_BACK.has_point(pos):
		_exit_codex()
		return true
	return false


func _weapon_input() -> void:
	if Input.is_action_just_pressed("left"):
		weapon_sel = (weapon_sel + WeaponScript.LIST.size() - 1) % WeaponScript.LIST.size()
		SFX.play("slash", 0.7, -8.0)
	elif Input.is_action_just_pressed("right"):
		weapon_sel = (weapon_sel + 1) % WeaponScript.LIST.size()
		SFX.play("slash", 0.7, -8.0)
	elif Input.is_action_just_pressed("start"):
		_confirm_weapon()


func _setting_input() -> void:
	var rows := 11
	if Input.is_action_just_pressed("up"):
		menu_sel = (menu_sel + rows - 1) % rows
	elif Input.is_action_just_pressed("down"):
		menu_sel = (menu_sel + 1) % rows
	elif menu_sel < 7:
		# 数值项：← → 调整
		if Input.is_action_just_pressed("left"):
			_adj_setting(-1)
		elif Input.is_action_just_pressed("right"):
			_adj_setting(1)
	# 存档行（索引 7/8/9）← → 切换 存/读/删
	if menu_sel >= 7 and menu_sel <= 9:
		if Input.is_action_just_pressed("left"):
			menu_action = (menu_action + 2) % 3
		elif Input.is_action_just_pressed("right"):
			menu_action = (menu_action + 1) % 3
	if Input.is_action_just_pressed("start") or Input.is_action_just_pressed("settings"):
		# 存档行：执行当前动作
		if menu_sel >= 7 and menu_sel <= 9:
			_do_slot_action(menu_sel - 7)
		else:
			state = "play"


func _adj_setting(dir: int) -> void:
	match menu_sel:
		0: Cfg.master = clampf(Cfg.master + dir * 0.1, 0.0, 1.0)
		1: Cfg.sfx = clampf(Cfg.sfx + dir * 0.1, 0.0, 1.0)
		2: Cfg.shake = clampf(Cfg.shake + dir * 0.1, 0.0, 1.5)
		3: Cfg.fullscreen = not Cfg.fullscreen
		4: Cfg.touch_ui = not Cfg.touch_ui; touch.set_shown(Cfg.touch_ui or touch.forced)
		5: Cfg.touch_scale = clampf(Cfg.touch_scale + dir * 0.1, 0.7, 1.5)
		6:
			# 进入布局编辑
			touch.set_edit(true)
		_:
			return
	if menu_sel != 6:
		Cfg.save_cfg()


func _do_slot_action(slot: int) -> void:
	match menu_action:
		0:
			var data := {"level_name": level_name, "room": room_i + 1, "hp": player.hp if player else 5}
			if Cfg.save_slot(slot, data):
				_slot_msg = "已 存 档 %d" % (slot + 1)
		1:
			if Cfg.has_slot(slot):
				_slot_msg = "已 读 档 %d" % (slot + 1)
				# 读档：回到该关第一间（简化实现，仅提示）
		2:
			if Cfg.has_slot(slot):
				Cfg.erase_slot(slot)
				_slot_msg = "已 删 档 %d" % (slot + 1)


func _reward_input() -> void:
	var n := maxi(1, reward_cards.size())
	if Input.is_action_just_pressed("left"):
		pick_sel = (pick_sel + n - 1) % n
		SFX.play("slash", 0.7, -8.0)
	elif Input.is_action_just_pressed("right"):
		pick_sel = (pick_sel + 1) % n
		SFX.play("slash", 0.7, -8.0)
	elif state == "replace" and Input.is_action_just_pressed("execute"):
		# R16：替换页按处决键（F）花道蕴扩容
		_expand_replace_slot()
	elif Input.is_action_just_pressed("start"):
		if state == "replace":
			_confirm_replace()
		else:
			_confirm_reward()


func _event_input() -> void:
	if event_kind == RoomScript.KIND_CHEST:
		if Input.is_action_just_pressed("left"):
			event_sel = 0
		elif Input.is_action_just_pressed("right"):
			event_sel = 1
		elif Input.is_action_just_pressed("start"):
			_event_input_confirm()
	elif event_kind == RoomScript.KIND_SHOP:
		var n := shop_items.size() + 1
		if Input.is_action_just_pressed("up"):
			event_sel = (event_sel + n - 1) % n
		elif Input.is_action_just_pressed("down"):
			event_sel = (event_sel + 1) % n
		elif Input.is_action_just_pressed("start"):
			_event_input_confirm()
	elif Input.is_action_just_pressed("start"):
		_event_input_confirm()


func _pause_input() -> void:
	if Input.is_action_just_pressed("codex"):
		_enter_codex("pause")
		return
	if Input.is_action_just_pressed("forge"):
		_enter_forge()
		return
	if Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("start"):
		state = "play"


func _clear_input() -> void:
	if Input.is_action_just_pressed("start"):
		_next_level()


# ============================================================ 触摸点击路由（由 touch.gd 调用）
func title_hit(pos: Vector2) -> bool:
	for i in BTN_TITLE.size():
		if BTN_TITLE[i].has_point(pos):
			title_sel = i
			_confirm_title()
			return true
	return false


## R32a：左侧三个快捷格（触屏直接点格子 —— 格子本身就是按钮，不再另画圆钮）
func quick_hit(pos: Vector2) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	for i in player.quick.size():
		var box := Rect2(26.0, 292.0 + float(i) * 52.0, 46.0, 46.0).grow(8.0)
		if box.has_point(pos):
			_use_quick(i)
			return true
	return false


## 右上角三颗圆钮：pause / weapon / settings
func top_hit(pos: Vector2) -> bool:
	var btns := [
		{"id": "pause", "c": Vector2(1088.0, 38.0), "r": 24.0},
		{"id": "weapon", "c": Vector2(1156.0, 38.0), "r": 24.0},
		{"id": "settings", "c": Vector2(1224.0, 38.0), "r": 24.0},
	]
	for b in btns:
		if pos.distance_to(Vector2(b["c"])) <= float(b["r"]) * 1.22:
			match str(b["id"]):
				"pause":
					_enter_pause()
				"weapon":
					_cycle_weapon()
				"settings":
					_enter_setting()
			return true
	return false


## 需求③：右上角换武器钮 —— 按武器表顺序轮换（R29 起是 4 把，不再写死 3 把）
func _cycle_weapon() -> void:
	if player == null:
		return
	var ids: Array = []
	for w in WeaponScript.LIST:
		ids.append(str(w["id"]))
	var cur := ids.find(player.weapon)
	cur = (cur + 1) % ids.size()
	player.set_weapon(str(ids[cur]))
	if hud:
		hud.show_prompt("武 器 · %s" % player.weapon_name(), 1.6)
	SFX.play("slash", 0.8, -6.0)


func pause_hit(pos: Vector2) -> bool:
	if BTN_PAUSE_CODEX.has_point(pos):
		_enter_codex("pause")
		return true
	if BTN_PAUSE_FORGE.has_point(pos):
		_enter_forge()
		return true
	state = "play"
	return true


func setting_hit(pos: Vector2) -> void:
	# 复用键盘设定行的命中（简易：按区域选择菜单行）
	var rows := ["master", "sfx", "shake", "fullscreen", "touch", "touch_size", "touch_edit",
		"slot0", "slot1", "slot2", "back"]
	var y0 := 196.0
	var dy := 40.0
	for i in rows.size():
		var y := y0 + float(i) * dy
		if absf(pos.y - y) < 20.0:
			menu_sel = i
			if i == 6:
				touch.set_edit(true)
			elif i >= 7 and i <= 9:
				_do_slot_action(i - 7)
			elif i == 10:
				state = "play"
			else:
				_adj_setting(1)
			return
	# 点空白处返回
	if pos.y > 600.0:
		state = "play"


func weapon_hit(pos: Vector2) -> bool:
	for i in WPN_RECTS.size():
		if WPN_RECTS[i].has_point(pos):
			weapon_sel = i
			_confirm_weapon()
			return true
	return false


func branch_hit(pos: Vector2) -> bool:
	# 岔路屏已废弃（ROUTES 仅保留兼容），此处不进入分支，直接忽略
	return false


func event_hit(pos: Vector2) -> void:
	if event_kind == RoomScript.KIND_CHEST:
		for i in EVENT_BTNS.size():
			if EVENT_BTNS[i].has_point(pos):
				event_sel = i
				# 触发与键盘一致的确认
				_event_input_confirm()
				return
	elif event_kind == RoomScript.KIND_SHOP:
		for i in SHOP_ROWS.size():
			if SHOP_ROWS[i].has_point(pos):
				event_sel = i
				_event_input_confirm()
				return
		if BTN_SHOP_LEAVE.has_point(pos):
			event_sel = shop_items.size()
			_event_input_confirm()


func _event_input_confirm() -> void:
	# 复用键盘确认逻辑
	if event_kind == RoomScript.KIND_CHEST:
		if event_sel == 0:
			var pool := RelicScript.pick_n_biased(rng, player.relics, 3, _slot_bias(), Game.karma_unlocks_magic_sword())
			if pool.size() > 0:
				_grant_relic_or_soul(str(pool[0].get("id", "")))
			# R27：补上宝箱承诺的 20 道蕴 —— 按钮文案与玩法说明一直写着
			#      「随机法宝 + 20 道蕴」，但此前只发了法宝，道蕴漏了。
			player.soul = minf(player.soul + 20.0, Game.MAX_SOUL)
			# R32a：宝箱同时给一粒丹药 —— 消耗品的第一个稳定来源
			_grant_random_pill(false)
			if hud != null:
				hud.show_prompt("宝 箱 · 法 宝 + 道 蕴 20 + 丹 药", 2.0)
			_show_fragment("L09")
		else:
			if player.hp < player.max_hp():
				player.hp += 1
		_next_room()
	elif event_kind == RoomScript.KIND_SHOP:
		if event_sel >= shop_items.size():
			_next_room()
		else:
			var it: Dictionary = shop_items[event_sel]
			if not it.get("sold", false) and player.soul >= float(it.get("price", 30)):
				var price := float(it.get("price", 30))
				# R32a/R32b：丹药 / 符箓货架 —— 三格满了就不卖（不当场吞道蕴）
				if it.has("item"):
					var iid := str((it["item"] as Dictionary).get("id", ""))
					if not player.add_item(iid, 1):
						hud.show_prompt("三 格 已 满 · 先 用 掉 一 格", 2.0)
						return
					player.soul -= price
					it["sold"] = true
					SFX.play("heal", 1.0, -2.0)
					var noun := "符" if ConsumeScript.is_talisman(iid) else "丹"
					hud.show_prompt("得 %s · %s" % [noun, ConsumeScript.name_of(iid)], 1.6)
					return
				var rid := str(it.get("relic", {}).get("id", ""))
				player.soul -= price
				# R13：位次满了就买不了（不当场吞掉道蕴）
				if not player.add_relic(rid):
					player.soul = minf(player.soul + float(it.get("price", 30)), Game.MAX_SOUL)
					hud.show_prompt("%s 位 已 满 · 先 换 掉 一 件" % RelicScript.slot_name(RelicScript.slot_of(rid)), 2.0)
					return
				it["sold"] = true
				SFX.play("heal", 1.0, -2.0)


func reward_hit(pos: Vector2) -> bool:
	# R16：替换页顶部的「扩容」按钮优先判定
	if state == "replace" and REPLACE_EXPAND.has_point(pos):
		_expand_replace_slot()
		return true
	for i in reward_rects.size():
		if reward_rects[i].has_point(pos):
			pick_sel = i
			if state == "replace":
				_confirm_replace()
			else:
				_confirm_reward()
			return true
	return false


func clear_hit(pos: Vector2) -> void:
	_next_level()


func exit_touch_edit() -> void:
	touch.set_edit(false)


# ============================================================ HUD 引用的辅助接口
func _build_shop() -> void:
	shop_items = []
	var pool := RelicScript.pick_n_biased(rng, player.relics, 3, _slot_bias(), Game.karma_unlocks_magic_sword())
	for r in pool:
		shop_items.append({"relic": r, "price": 30, "sold": false})
	# R32a：第 4 行是丹药货架 —— 商队顺带卖一味丹，价格照丹药表走
	var pid := ConsumeScript.roll(rng)
	if pid != "":
		shop_items.append({"item": ConsumeScript.pill(pid),
			"price": ConsumeScript.price_of(pid), "sold": false})
	# R32b：第 5 行是符箓货架 —— 符比丹贵，也更容易断货（只有一张）
	var tid := ConsumeScript.roll_talisman(rng)
	if tid != "":
		shop_items.append({"item": ConsumeScript.talisman(tid),
			"price": ConsumeScript.price_of(tid), "sold": false})
	_layout_shop_rows(shop_items.size())


## 货架行数随条目变（R32a 起是 4 行：3 法宝 + 1 丹药）
func _layout_shop_rows(n: int) -> void:
	SHOP_ROWS = []
	for i in n:
		SHOP_ROWS.append(Rect2(300.0, 206.0 + float(i) * 68.0, 680.0, 58.0))


func daily_line() -> String:
	var wname := str(WeaponScript.by_id(daily_weapon_id()).get("name", ""))
	# R23：副标题升级为「今日之镜」—— 今日武器 + 破劫状态，进局前就能看到
	# R28：带上评分与历史最佳，让「今天打得比上次好吗」在进局前就有答案
	var best := Cfg.best_daily_score()
	var tail := (" · 最佳 %d" % best) if best > 0 else ""
	if daily_done_today():
		return "今日之镜 · %s · 已破 %d 分%s" % [wname, Cfg.daily_score, tail]
	return "今日之镜 · %s · 未破%s" % [wname, tail]


## R28：本地榜前三行（标题页 / 结算页共用）；空榜返回空数组
func daily_board_lines(n: int = 3) -> Array:
	var out := []
	for i in mini(n, Cfg.daily_board.size()):
		var it: Dictionary = Cfg.daily_board[i]
		out.append("%d. %s  %d 分  %d.%02d  %s" % [
			i + 1,
			str(it["date"]).substr(5),          # 只留 MM-DD
			int(it["score"]),
			int(float(it["secs"])) / 60, int(float(it["secs"])) % 60,
			"无伤" if int(it["dmg"]) <= 0 else "受击 %d" % int(it["dmg"])])
	return out


func _boss_name(r: Dictionary) -> String:
	var bk := int(r.get("boss", 2))
	match bk:
		2: return "镇 钟 力 士"
		3: return "剑 冢 守"
		4: return "前 世 身"
		6: return "尸 解 仙 · 无 相"
		7: return "域 外 天 魔"
		14: return "无 相 · 心 魔"
		15: return "符 祖"
		16: return "轮 回 使"
		_: return "Boss"
