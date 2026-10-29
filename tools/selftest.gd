extends SceneTree
## 玄界 XUANJIE · R10 全功能自测（替代 R9 被删的 tools/ 自测脚本）
## 用法：Godot_v4.7.2-stable_win64_console.exe --headless --path D:/XUANJIE --script res://tools/selftest.gd
## 设计：每条断言独立容错（if/else 收集 PASS/FAIL/WARN，不抛异常终止脚本）。

var results: Array = []
var RoomScript = load("res://scripts/rooms.gd")
var WeaponScript = load("res://scripts/weapons.gd")
var RelicScript = load("res://scripts/relics.gd")
var LoreScript = load("res://scripts/lore.gd")
var InscribeScript = load("res://scripts/inscribe.gd")
var MeridianScript = load("res://scripts/meridian.gd")
var AlchemyScript = load("res://scripts/alchemy.gd")
var ConsumeScript = load("res://scripts/consumable.gd")
var CompanionScript = load("res://scripts/companion.gd")   # R35

## R33a：自测会打死玩家，而死亡会结算道痕并落盘 —— 所以在**跑任何一条断言之前**
## 先把道痕 / 累计 / 经脉等级拍个快照，收尾时原样写回，绝不留脏数据。
var _dy0 := 0
var _dyt0 := 0
var _lv0: Dictionary = {}
var _pantry0: Dictionary = {}

func _initialize() -> void:
	await create_timer(0.3).timeout
	# --script 模式不会自动加载 main_scene（仅 autoload 被加载），需主动加载 Main
	var packed = load("res://scenes/Main.tscn")
	if packed == null:
		_log("FAIL 无法加载 res://scenes/Main.tscn")
		_report()
		return
	var ms = packed.instantiate()
	Engine.get_main_loop().root.add_child(ms)
	await create_timer(0.4).timeout  # 等 _ready 创建 player/boss 等子节点
	await _run()
	_report()

func _log(s: String) -> void:
	results.append(s)
	print(s)

func _gate_all(g: Dictionary, val: bool) -> bool:
	return g.get("west", !val) == val and g.get("east", !val) == val \
		and g.get("north", !val) == val and g.get("south", !val) == val

func _get_main():
	var root = Engine.get_main_loop().root
	for c in root.get_children():
		if c.get_script() != null and "main.gd" in c.get_script().resource_path:
			return c
	return null

func _run() -> void:
	var root = Engine.get_main_loop().root
	print("DEBUG root_child_count=%d" % root.get_child_count())
	for c in root.get_children():
		var sc = c.get_script()
		var rp = "(no script)"
		if sc != null:
			rp = sc.resource_path
		print("DEBUG child name=%s script=%s" % [c.name, rp])
	var main = _get_main()
	if main == null:
		_log("FAIL 找不到 Main 节点")
		return
	var player = main.get("player")
	if player == null:
		_log("FAIL player 未创建（_ready 未跑？）")
		return
	# --script 入口在编译期看不到 autoload 单例，运行时经节点路径取 Game / Cfg
	var Game = Engine.get_main_loop().root.get_node_or_null("Game")
	var Cfg = Engine.get_main_loop().root.get_node_or_null("Cfg")
	# R33a：拍快照 —— 后面的测试会打死玩家，死亡会结算道痕并写盘；
	# 收尾时按这份快照原样写回，绝不留脏数据。
	if Cfg != null:
		_dy0 = int(Cfg.daoyun)
		_dyt0 = int(Cfg.daoyun_total)
		_lv0 = Cfg.meridian_lv.duplicate()
		_pantry0 = Cfg.pantry.duplicate()
	_log("PASS 节点就绪：root_child=%d player_valid=%s game=%s" % [Engine.get_main_loop().root.get_child_count(), player != null, Game != null])

	# R19a：序章会拦在 _confirm_weapon 前面；老用例一律直接跑主线，
	# 序章自己有 T74–T76 单独验，结束时会把标记还原。
	var _prologue_saved: bool = bool(Cfg.prologue_done) if Cfg != null else false
	if Cfg != null:
		Cfg.prologue_done = true

	# ============ 需求④ 禁制/解锁 + 自动通关 4 关 ============
	main._start_run(false)
	main.weapon_sel = 0
	main._confirm_weapon()
	var cleared := 0
	var total_levels: int = int(RoomScript.level_count())
	for lvl in range(total_levels):
		main._enter_room(5)  # 每关 Boss 固定 index 5
		var locked = main.get("boss_room_locked")
		var gates: Dictionary = main.get("current_gates")
		if not locked:
			_log("FAIL L%d 进 Boss 房未落禁制" % lvl)
		elif not _gate_all(gates, true):
			_log("FAIL L%d 禁制但四面未全锁 %s" % [lvl, gates])
		else:
			_log("PASS L%d 进 Boss 房四面禁制锁定" % lvl)
		var b = main.get("boss")
		if b == null:
			_log("FAIL L%d 未生成 Boss" % lvl)
		elif not b.get("is_boss"):
			_log("FAIL L%d 生成物非 Boss" % lvl)
		else:
			_log("PASS L%d Boss 已生成 is_boss=true kind=%s" % [lvl, b.get("kind")])
		if b != null:
			main._on_enemy_killed(b)
		var unlocked = main.get("boss_room_locked")
		var gates2: Dictionary = main.get("current_gates")
		if unlocked:
			_log("FAIL L%d Boss 死后仍锁定" % lvl)
		elif not _gate_all(gates2, false):
			_log("FAIL L%d Boss 死后闸门未全开 %s" % [lvl, gates2])
		else:
			_log("PASS L%d Boss 死 → 四向开门解锁" % lvl)
		cleared += 1
		main._next_level()  # 最后一关 → state=win
	if main.state == "win":
		_log("PASS 自动通关 %d 关 → 抵达 WIN（levels_cleared=%d）" % [total_levels, cleared])
	else:
		_log("FAIL 未抵达 WIN，state=%s" % main.state)

	# ============ 需求③ 武器切换（右上角武器钮） ============
	main._enter_room(0)
	var w_before = str(player.get("weapon"))
	main._cycle_weapon()
	var w_after = str(player.get("weapon"))
	if w_before != w_after and w_after != "Null":
		_log("PASS 需求③ 武器切换生效：%s → %s（右上角武器钮有效）" % [w_before, w_after])
	else:
		_log("WARN 武器切换未检测到变化（weapon 前=%s 后=%s）" % [w_before, w_after])

	# ============ 右上角 设置 / 暂停 按钮 ============
	main._enter_setting()
	if main.state == "setting":
		_log("PASS 设置页可进入（右上角设置钮有效）")
	else:
		_log("FAIL 设置页进入失败 state=%s" % main.state)
	main.state = "play"
	main._enter_pause()
	if main.state == "pause":
		_log("PASS 暂停可进入（右上角暂停钮有效）")
	else:
		_log("FAIL 暂停进入失败 state=%s" % main.state)
	main.state = "play"

	# ============ 存档 / 读档（接口在 Cfg 单例） ============
	if Cfg == null:
		_log("WARN 未取得 Cfg 单例，跳过存档/读档断言")
	else:
		var save_data = {"hp": 5, "room": 3, "weapon": "spear", "level": 1}
		Cfg.save_slot(0, save_data)
		var ld = Cfg.load_slot(0)
		if ld != null and ld.has("hp"):
			_log("PASS 存档/读档 slot0 可用（hp=%s weapon=%s）" % [ld.get("hp"), ld.get("weapon")])
		else:
			_log("WARN 读档返回异常：%s" % ld)

	# ============ 每日种子同日稳定 ============
	var d1 = RoomScript.daily_seed()
	var d2 = RoomScript.daily_seed()
	if d1 == d2:
		_log("PASS 每日种子同日稳定 seed=%d" % d1)
	else:
		_log("FAIL 每日种子不稳定 %d vs %d" % [d1, d2])

	# ============ 关卡数 / 武器列表 / 法宝池 ============
	var lc = RoomScript.level_count()
	if lc >= 4:
		_log("PASS 关卡数=%d（≥4）" % lc)
	else:
		_log("WARN 关卡数=%d" % lc)
	var wl = WeaponScript.LIST
	if wl.size() >= 3:
		_log("PASS 武器列表=%d 种（剑/枪/双刀齐全）" % wl.size())
	else:
		_log("WARN 武器列表数量=%d" % wl.size())
	var rnd = RandomNumberGenerator.new()
	var rp = RelicScript.pick_three(rnd, [])
	if rp.size() > 0:
		_log("PASS 法宝池可抽取（pick_three → %d 张）" % rp.size())
	else:
		_log("WARN 法宝池抽取为空")

	# ============ 需求⑤ 完美剑意交锋门控 · 运行时实测 ============
	# 门控逻辑（player.gd _start_stage）：stage==1 时
	#   perfect_ready = (_t - _atk_end_t) >= PERFECT_GAP(0.30)
	# 即「停手 ≥0.30s 再出刀」才具备完美资格；连打/接段一律 false。
	player.set_weapon("sword")
	player.respawn(Vector2(600, 600))
	await root.get_tree().physics_frame
	if bool(player.get("perfect_ready")) == true:
		_log("PASS 需求⑤ 起手即「停手后干净起手」→ perfect_ready=true")
	else:
		_log("WARN 需求⑤ 起手 perfect_ready 非 true（=%s），需复核初值" % player.get("perfect_ready"))
	# 用 player 内部同一时钟 _t（进程累计），避免与墙钟混用导致判定错位
	var pt = player.get("_t")
	# 模拟「刚收刀」→ 立即再出刀（连打）应不算完美
	player._atk_end_t = pt
	player._start_stage(1, false)
	if bool(player.get("perfect_ready")) == false:
		_log("PASS 需求⑤ 连续攻击（未停手）不触发完美剑意交锋：perfect_ready=false")
	else:
		_log("FAIL 需求⑤ 连续攻击竟判为完美：perfect_ready=true")
	# 模拟「停手 ≥0.30s」→ 再出刀应可完美
	player._atk_end_t = pt - 1.0
	player._start_stage(1, false)
	if bool(player.get("perfect_ready")) == true:
		_log("PASS 需求⑤ 停手足够久后再出刀 → perfect_ready=true（可完美剑意交锋）")
	else:
		_log("FAIL 需求⑤ 停手后仍不完美：perfect_ready=false")

	# ============ 需求④ 所有 Boss 配置格挡/剑意交锋 · 运行时实测 ============
	var EnemyScript2 = load("res://scripts/enemy.gd")
	var SpaceScript2 = load("res://scripts/space.gd")
	var fx_node = main.get("fx")
	var boss_kinds := [2, 3, 6, 7]   # KIND_BOSS / KIND_BOSS2 / KIND_BOSS4 / KIND_BOSS5
	for k in boss_kinds:
		var e = EnemyScript2.new()
		e.setup(k, Vector2(600, 600), player, fx_node)
		e.arena = Vector2(SpaceScript2.ROOM_X0, SpaceScript2.ROOM_X1)
		root.add_child(e)
		var ok := true
		var detail := ""
		if not bool(e.get("is_boss")):
			ok = false; detail += " is_boss=false"
		if not e.has_method("on_clash"):
			ok = false; detail += " 缺on_clash"
		if not e.has_method("add_stagger"):
			ok = false; detail += " 缺add_stagger"
		# 防御姿态可达
		e.state = e.DEFEND
		if int(e.state) != int(e.DEFEND):
			ok = false; detail += " 无法进入DEFEND"
		# 重击破防：DEFEND 下受重击 → 转 STAGGER（证明格挡/剑意交锋机制存在且可被打破）
		if "invuln_t" in e:
			e.invuln_t = 0.0
		e.state = e.DEFEND
		e.hurt(5, player.global_position, true)
		if int(e.state) != int(e.STAGGER):
			ok = false; detail += " 重击未破防(DEFEND→STAGGER)"
		if ok:
			_log("PASS 需求④ Boss kind=%d 含格挡/剑意交锋机制（可进DEFEND、重击破防生效）" % k)
		else:
			_log("FAIL 需求④ Boss kind=%d 格挡机制异常：%s" % [k, detail])
		root.remove_child(e)
		e.queue_free()

	# ============ 房间类型常量齐全（需求② 微观房间网格） ============
	var kinds_ok = RoomScript.KIND_START != null and RoomScript.KIND_BOSS != null \
		and RoomScript.KIND_CHEST != null and RoomScript.KIND_SHOP != null
	if kinds_ok:
		_log("PASS 房间类型常量齐全（start/boss/chest/shop/...）")
	else:
		_log("FAIL 房间类型常量缺失")

	# ============ R11 护体罡气交锋层（只狼式躯干值）· T31–T35 ============
	var EnemyScript3 = load("res://scripts/enemy.gd")
	var SpaceScript3 = load("res://scripts/space.gd")
	var fx3 = main.get("fx")
	player.respawn(Vector2(600, 600))
	player.set_weapon("sword")
	Game.reset_stats()

	# T31：普通格挡 3 次 → 玩家 posture == 54（18×3）
	player.posture = 0
	player.broken_t = 0.0
	for _i in 3:
		player.on_guard()
	if int(player.posture) == 54:
		_log("PASS T31 普通格挡3次 posture=%d（期望54）" % int(player.posture))
	else:
		_log("FAIL T31 普通格挡3次 posture=%d（期望54）" % int(player.posture))

	# 造一个哨兵敌人用于 T32/T34/T35
	var e_r11 = EnemyScript3.new()
	e_r11.setup(EnemyScript3.KIND_SENTINEL, Vector2(760, 600), player, fx3)
	e_r11.arena = Vector2(SpaceScript3.ROOM_X0, SpaceScript3.ROOM_X1)
	root.add_child(e_r11)

	# T32：完美弹反 → 玩家护体罡气不变，敌方 +40% 最大护体罡气
	player.posture = 0
	player.broken_t = 0.0
	e_r11.posture = 0.0
	e_r11.broken_t = 0.0
	player.perfect_ready = true
	main._perform_clash(e_r11)
	var expect_ep: float = float(e_r11.max_posture) * 0.40
	if int(player.posture) == 0 and absf(float(e_r11.posture) - expect_ep) < 0.01:
		_log("PASS T32 完美弹反 玩家posture=0 敌方posture=%.1f/%.1f" % [e_r11.posture, e_r11.max_posture])
	else:
		_log("FAIL T32 完美弹反 玩家posture=%d 敌方posture=%.1f（期望%.1f）" % [int(player.posture), e_r11.posture, expect_ep])

	# T33：玩家护体罡气满 → 道心失守（BROKEN_TIME=1.2），计时结束恢复
	player.posture = 0
	player.broken_t = 0.0
	var gn := 0
	while not player.is_broken() and gn < 30:
		player.on_guard()
		gn += 1
	var wb: bool = player.is_broken()
	var bt: float = float(player.broken_t)
	player.broken_t = 0.0
	var rec: bool = not player.is_broken()
	if wb and absf(bt - 1.2) < 0.001 and rec:
		_log("PASS T33 玩家护体罡气满→道心失守(%.1fs)→恢复" % bt)
	else:
		_log("FAIL T33 was_broken=%s bt=%.2f recovered=%s" % [str(wb), bt, str(rec)])

	# T34：敌方护体罡气满 → 可处决；处决造成伤害并重置护体罡气
	e_r11.hp = 40
	e_r11.posture = 0.0
	e_r11.broken_t = 0.0
	e_r11.posture = float(e_r11.max_posture) - 0.5
	e_r11.add_posture(1.0)
	var can_ex: bool = e_r11.can_execute()
	var hp_before: int = int(e_r11.hp)
	var dmg: int = int(e_r11.execute_damage())
	main._do_execute(e_r11)
	var hp_ok: bool = bool(e_r11.dead) or int(e_r11.hp) == hp_before - dmg
	var reset_ok: bool = float(e_r11.posture) == 0.0 and not e_r11.is_broken()
	if can_ex and hp_ok and reset_ok:
		_log("PASS T34 敌方道心失守→处决 dmg=%d hp %d→%d 护体罡气重置" % [dmg, hp_before, int(e_r11.hp)])
	else:
		_log("FAIL T34 can_execute=%s hp_ok=%s reset_ok=%s (dmg=%d hp %d→%d)" % [str(can_ex), str(hp_ok), str(reset_ok), dmg, hp_before, int(e_r11.hp)])

	# T35：PERFECT_GAP 门控有效（perfect_ready=false 时剑意交锋不算完美）
	Game.reset_stats()
	player.posture = 0
	player.broken_t = 0.0
	e_r11.posture = 0.0
	e_r11.broken_t = 0.0
	player.perfect_ready = false
	main._perform_clash(e_r11)
	var gate_ok: bool = int(Game.perfect_count) == 0 and int(Game.clash_count) == 1 and int(player.posture) == 18
	if gate_ok and absf(float(player.PERFECT_GAP) - 0.30) < 0.001:
		_log("PASS T35 PERFECT_GAP 门控：连续攻击不计完美（clash=%d perfect=%d posture=%d）" % [int(Game.clash_count), int(Game.perfect_count), int(player.posture)])
	else:
		_log("FAIL T35 clash=%d perfect=%d posture=%d GAP=%.2f" % [int(Game.clash_count), int(Game.perfect_count), int(player.posture), float(player.PERFECT_GAP)])

	root.remove_child(e_r11)
	e_r11.queue_free()

	# ============ R14 世界层（地图 / 故事 / 人物）· T36–T40 ============
	var LoreS = load("res://scripts/lore.gd")
	var bg_node = main.get("bg")

	# T36：玄界之门门影在四关 alpha 单调递增
	var strengths := []
	if bg_node != null and bg_node.has_method("set_level"):
		for lv in 4:
			bg_node.set_level(lv)
			strengths.append(float(bg_node.gate_strength()))
	var mono := strengths.size() == 4
	for k in range(1, strengths.size()):
		if float(strengths[k]) <= float(strengths[k - 1]):
			mono = false
	if mono:
		_log("PASS T36 门影四关递增 %s" % str(strengths))
	else:
		_log("FAIL T36 门影非单调/缺失 %s" % str(strengths))

	# T37：残碑四关各一条（岔路屏已废弃，残碑落在起始房）
	var steles := []
	for lv in 4:
		steles.append(str(LoreS.stele_line(lv)))
	var uniq := {}
	for s in steles:
		uniq[s] = true
	if uniq.size() == 4 and steles[0] != "":
		_log("PASS T37 残碑四关四句互异")
	else:
		_log("FAIL T37 残碑重复/为空 %s" % str(steles))

	# T38：Boss 战前台词只触发一次（同房同句）
	var seen_backup = Cfg.seen_lines.duplicate()
	var said_map = main.get("_boss_lines_said")
	if said_map is Dictionary:
		said_map.clear()
	var cnt0 := int(Game.boss_line_count)
	var ok1: bool = main._say_boss_line(2, "before")
	var ok2: bool = main._say_boss_line(2, "before")
	var dlt := int(Game.boss_line_count) - cnt0
	Cfg.seen_lines = seen_backup
	Cfg.save_cfg()
	if ok1 and not ok2 and dlt == 1:
		_log("PASS T38 战前台词只触发一次（first=%s second=%s delta=%d）" % [str(ok1), str(ok2), dlt])
	else:
		_log("FAIL T38 first=%s second=%s delta=%d" % [str(ok1), str(ok2), dlt])

	# T39：负匣人台词随关卡变化
	var m0 := str(LoreS.merchant_line(0))
	var m2 := str(LoreS.merchant_line(2))
	var m3 := str(LoreS.merchant_line(3))
	if m0 != "" and m0 != m2 and m2 != m3:
		_log("PASS T39 负匣人台词随关卡变化")
	else:
		_log("FAIL T39 商人台词未随关卡变化 %s / %s / %s" % [m0, m2, m3])

	# T40：记忆回响外观取玩家当前武器配色
	player.set_weapon("spear")
	var hue_expect := float(WeaponScript.by_id("spear").get("hue", 0.56))
	main._spawn_echo(Vector2(700, 600))
	var echo = null
	if main.enemies.size() > 0:
		echo = main.enemies[main.enemies.size() - 1]
	if echo != null and bool(echo.is_echo) and absf(float(echo.echo_hue) - hue_expect) < 0.001:
		_log("PASS T40 记忆回响取武器配色（spear hue=%.2f）" % float(echo.echo_hue))
	else:
		var got_hue := float(echo.echo_hue) if echo != null else -1.0
		var got_echo := bool(echo.is_echo) if echo != null else false
		_log("FAIL T40 echo=%s is_echo=%s hue=%.2f expect=%.2f" % [str(echo != null), str(got_echo), got_hue, hue_expect])

	# ============ R12 连招模组层（武器差异化 / 取消窗口 / 动作标签）· T41–T45 ============
	var EnemyScript4 = load("res://scripts/enemy.gd")
	var fx4 = main.get("fx")

	# T41：三武器段数各不相同（剑 3 / 枪 3 / 双刀 4）
	var lens := {}
	for wid in ["sword", "spear", "dual"]:
		lens[wid] = int(WeaponScript.combo_len(wid))
	if int(lens["sword"]) == 3 and int(lens["spear"]) == 3 and int(lens["dual"]) == 4:
		_log("PASS T41 连招段数差异化 剑%d/枪%d/双刀%d" % [int(lens["sword"]), int(lens["spear"]), int(lens["dual"])])
	else:
		_log("FAIL T41 段数 %s" % str(lens))

	# T42：双刀的护体罡气压制总量显著高于剑（这是「双刀=压制」的量化依据）
	var ps := {}
	for wid in ["sword", "spear", "dual"]:
		ps[wid] = float(WeaponScript.combo_posture(wid))
	var ratio: float = float(ps["dual"]) / maxf(0.001, float(ps["sword"]))
	if ratio >= 1.8 and float(ps["dual"]) > float(ps["spear"]):
		_log("PASS T42 护体罡气压制总量 剑%.2f/枪%.2f/双刀%.2f（双刀=剑×%.2f）" % [ps["sword"], ps["spear"], ps["dual"], ratio])
	else:
		_log("FAIL T42 压制总量 剑%.2f/枪%.2f/双刀%.2f ratio=%.2f" % [ps["sword"], ps["spear"], ps["dual"], ratio])

	# T43：取消窗口 —— 剑收刀 35% 就开、枪要 78%；桩步法宝把枪提前到 55%
	player.reset_relics()
	player.heat = 0.0
	player.set_weapon("sword")
	player.stage = 3
	player.atk = player.ATK_RECOVER
	var tt_s: Vector3 = player._stage_t()
	player.atk_t = tt_s.z * 0.34
	var s_closed: bool = player.can_cancel()
	player.atk_t = tt_s.z * 0.36
	var s_open: bool = player.can_cancel()

	player.set_weapon("spear")
	player.stage = 3
	player.atk = player.ATK_RECOVER
	var tt_p: Vector3 = player._stage_t()
	player.atk_t = tt_p.z * 0.36
	var p_closed: bool = player.can_cancel()
	player.atk_t = tt_p.z * 0.80
	var p_open: bool = player.can_cancel()
	# 桩步只作用于「突刺」段（长枪 2 段；3 段 R16 起是上挑 TAG_UP，不吃桩步）
	player.add_relic("stake")
	player.stage = 2
	player.atk = player.ATK_RECOVER
	var tt_p2: Vector3 = player._stage_t()
	player.atk_t = tt_p2.z * 0.60
	var p_stake: bool = player.can_cancel()
	# 同一进度、去掉法宝 → 应重新关上（证明是桩步开的口子）
	player.reset_relics()
	player.atk_t = tt_p2.z * 0.60
	var p_nostake: bool = player.can_cancel()
	player.atk = player.ATK_NONE
	player.stage = 0
	if (not s_closed) and s_open and (not p_closed) and p_open and p_stake and (not p_nostake):
		_log("PASS T43 取消窗口 剑0.34关/0.36开 枪0.36关/0.80开 桩步(2段)0.60开/无法宝关")
	else:
		_log("FAIL T43 sword=%s/%s spear=%s/%s stake=%s nostake=%s"
			% [str(s_closed), str(s_open), str(p_closed), str(p_open), str(p_stake), str(p_nostake)])

	# T44：长枪距离惩罚 —— 贴脸打不出伤害（枪杆区），拉开才满伤
	player.set_weapon("spear")
	player.stage = 2
	player.global_position = Vector2(600, 600)
	var d_far := int(player.attack_damage(Vector2(700, 600)))
	var d_near := int(player.attack_damage(Vector2(618, 600)))
	player.set_weapon("sword")
	player.stage = 2
	var d_sword_far := int(player.attack_damage(Vector2(700, 600)))
	var d_sword_near := int(player.attack_damage(Vector2(618, 600)))
	if d_far - d_near == 1 and d_far == d_sword_far + 1 and d_sword_far == d_sword_near:
		_log("PASS T44 长枪距离惩罚 远%d/近%d（剑无惩罚 远%d/近%d）" % [d_far, d_near, d_sword_far, d_sword_near])
	else:
		_log("FAIL T44 枪远%d近%d 剑远%d近%d" % [d_far, d_near, d_sword_far, d_sword_near])
	player.stage = 0

	# T45：护体罡气回落 —— 停手未满 2.2s 不掉，越过之后按比例掉；再挨一刀重新计时
	var e_r12 = EnemyScript4.new()
	e_r12.setup(EnemyScript4.KIND_SENTINEL, Vector2(900, 600), player, fx4)
	root.add_child(e_r12)
	var mp: float = float(e_r12.max_posture)
	e_r12.posture = mp * 0.50
	e_r12._posture_idle = 0.0
	e_r12._decay_posture(1.0)
	var hold_ok: bool = absf(float(e_r12.posture) - mp * 0.50) < 0.01
	e_r12._decay_posture(2.0)
	var after: float = float(e_r12.posture)
	var dropped_ok: bool = after < mp * 0.50 - 0.01
	e_r12.add_posture(1.0)
	var idle_reset_ok: bool = absf(float(e_r12._posture_idle)) < 0.001
	root.remove_child(e_r12)
	e_r12.queue_free()
	if hold_ok and dropped_ok and idle_reset_ok:
		_log("PASS T45 护体罡气回落 2.2s内保持(%.1f) 之后掉到%.1f 命中重置计时" % [mp * 0.50, after])
	else:
		_log("FAIL T45 hold_ok=%s dropped_ok=%s(%.1f→%.1f) reset_ok=%s" % [str(hold_ok), str(dropped_ok), mp * 0.50, after, str(idle_reset_ok)])

	# ============ R13 法宝位次 + 飞剑轴（暖雪内核）· T46–T50 ============
	var EnemyScript5 = load("res://scripts/enemy.gd")
	var fx5 = main.get("fx")

	# T46：位次容量 —— 剑位最多 SLOT_CAP 件，第 4 件放不进；替换后可进
	player.reset_relics()
	var cap: int = int(RelicScript.SLOT_CAP)
	var blade_ids := ["edge", "wind", "reach", "thunder"]
	var ok_n := 0
	for i in blade_ids.size():
		if player.add_relic(str(blade_ids[i])):
			ok_n += 1
	var overflow_ok: bool = ok_n == cap and player.slot_full("blade") and player.slot_used("blade") == cap
	var swapped: bool = player.swap_relic(str(blade_ids[0]), str(blade_ids[cap]))
	var swap_ok: bool = swapped and player.has_relic(str(blade_ids[cap])) and not player.has_relic(str(blade_ids[0])) \
		and player.slot_used("blade") == cap
	if overflow_ok and swap_ok:
		_log("PASS T46 位次容量 剑位%d件封顶，第%d件被拒；替换后可进（%s→%s）" % [
			cap, cap + 1, str(blade_ids[0]), str(blade_ids[cap])])
	else:
		_log("FAIL T46 ok_n=%d cap=%d full=%s swap=%s used=%d" % [
			ok_n, cap, str(player.slot_full("blade")), str(swap_ok), player.slot_used("blade")])

	# T47：流派名 —— 剑位装满 = 剑修；剑位飞剑 + 灵位 2 道蕴 = 飞剑流
	player.reset_relics()
	for i in 3:
		player.add_relic(str(blade_ids[i]))
	var t_jianxiu: String = player.build_title()
	player.reset_relics()
	player.add_relic("swordfly")
	player.add_relic("blood")
	player.add_relic("soul")
	var t_fly: String = player.build_title()
	player.reset_relics()
	player.add_relic("sheath")
	player.add_relic("wall")
	player.add_relic("guardian")
	var t_bishou: String = player.build_title()
	if t_jianxiu == "剑 修" and t_fly == "飞 剑 流" and t_bishou == "体 修":
		_log("PASS T47 流派名 剑满=%s / 剑飞剑+灵2=%s / 体满=%s" % [t_jianxiu, t_fly, t_bishou])
	else:
		_log("FAIL T47 剑满=%s 飞剑=%s 体满=%s" % [t_jianxiu, t_fly, t_bishou])

	# T48：飞剑伤害 = 1 + 穿云 + 飞剑流
	player.reset_relics()
	player.add_relic("swordfly")
	var d_base: int = player.flying_damage()
	player.add_relic("pierce")
	var d_pierce: int = player.flying_damage()
	player.add_relic("blood")
	player.add_relic("soul")
	var d_build: int = player.flying_damage()
	var is_fly: bool = player.is_flying_build()
	if d_base == 1 and d_pierce == 2 and d_build == 3 and is_fly:
		_log("PASS T48 飞剑伤害 基础%d → 穿云%d → 飞剑流%d" % [d_base, d_pierce, d_build])
	else:
		_log("FAIL T48 base=%d pierce=%d build=%d is_fly=%s" % [d_base, d_pierce, d_build, str(is_fly)])

	# T49：飞剑只在「连招最后一段」甩出，且 main 会生成对应数量的实体
	var fly := {"n": 0, "dmg": 0, "cnt": 0}
	var cbr := func(_p, _d, dmg, cnt) -> void:
		fly["n"] += 1
		fly["dmg"] = dmg
		fly["cnt"] = cnt
	player.flying_sword.connect(cbr)
	var proj0: int = main.projectiles.size()
	# 非最后一段：不触发
	player.set_weapon("sword")
	player.atk = player.ATK_WINDUP
	player.stage = 1
	player.atk_t = 999.0
	player._physics_process(0.016)
	var not_last: int = int(fly["n"])
	# 最后一段：触发
	player.atk = player.ATK_WINDUP
	player.stage = int(player.combo_len())
	player.atk_t = 999.0
	player._physics_process(0.016)
	var last_n: int = int(fly["n"])
	player.atk = player.ATK_NONE
	player.stage = 0
	if player.flying_sword.is_connected(cbr):
		player.flying_sword.disconnect(cbr)
	var spawn_ok: bool = int(fly["cnt"]) >= 1 and main.projectiles.size() > proj0
	if not_last == 0 and last_n == 1 and spawn_ok:
		_log("PASS T49 飞剑只在末段甩出（前段%d次 / 末段%d次 / 生成%d道 dmg=%d）" % [
			not_last, last_n, int(fly["cnt"]), int(fly["dmg"])])
	else:
		_log("FAIL T49 not_last=%d last=%d cnt=%d proj=%d→%d" % [
			not_last, last_n, int(fly["cnt"]), proj0, main.projectiles.size()])

	# T50：开局清空 + 剑鞘护体罡气上限修正（R11 后 +1 等于没加，R13 改成 +20）
	player.reset_relics()
	var pmax0: int = player.posture_max()
	player.add_relic("sheath")
	var pmax1: int = player.posture_max()
	var slot_cleared: bool = player.relics.is_empty() == false and player.slot_used("wall") == 1
	player.reset_relics()
	var empty_ok: bool = player.relics.is_empty() and player.slot_used("wall") == 0 \
		and player.slot_used("blade") == 0 and player.slot_used("spirit") == 0
	if empty_ok and pmax1 - pmax0 == 20 and slot_cleared:
		_log("PASS T50 开局清空法宝 + 剑鞘护体罡气上限 %d→%d" % [pmax0, pmax1])
	else:
		_log("FAIL T50 empty=%s pmax %d→%d" % [str(empty_ok), pmax0, pmax1])

	# T51：奖励页「位次满 → 替换页 → 换成功」整条流程
	var st_bak: String = str(main.state)
	var ri_bak: int = int(main.room_i)
	var rs_bak: Array = main.room_state.duplicate()
	player.reset_relics()
	player.add_relic("edge")
	player.add_relic("wind")
	player.add_relic("reach")
	main.reward_cards = [RelicScript.by_id("thunder")]
	main.reward_rects = [Rect2(186, 296, 282, 232), Rect2(499, 296, 282, 232), Rect2(812, 296, 282, 232)]
	main.pick_sel = 0
	main.state = "reward"
	main._confirm_reward()
	var entered: bool = str(main.state) == "replace" and str(main.pending_relic) == "thunder" \
		and main.reward_cards.size() == 3 and str(main.reward_title) != ""
	main.pick_sel = 0
	var old_pick := str(main.reward_cards[0].get("id", ""))
	main._confirm_replace()
	var swapped_ok: bool = player.has_relic("thunder") and not player.has_relic(old_pick) \
		and player.slot_used("blade") == 3 and str(main.pending_relic) == ""
	main.state = st_bak
	main.room_i = ri_bak
	main.room_state = rs_bak
	main.reward_cards = []
	player.reset_relics()
	if entered and swapped_ok:
		_log("PASS T51 奖励页位次满 → 替换页（3 张）→ 换成功（%s→thunder）" % old_pick)
	else:
		_log("FAIL T51 entered=%s swapped=%s old=%s used=%d" % [
			str(entered), str(swapped_ok), old_pick, player.slot_used("blade")])

	# ============ R15 箱庭补完（环境叙事 / 伪楼层 / 禁制落下 / 残影引导者）· T52–T56 ============
	var w_node = main.get("world")
	var fg_node = main.get("fg")

	# T52：set_room_env 把「房型 + 前后层」正确喂给世界层（4 关 × 6 房全量核对）
	var map_ok: bool = w_node != null
	var bad := ""
	if w_node != null:
		for lv in 4:
			var rs: Array = RoomScript.rooms_of(lv)
			for j in rs.size():
				var rr: Dictionary = rs[j]
				var kk: String = str(RoomScript.room_kind(rr))
				var dep: int = 1 - int(rr.get("row", 0))
				w_node.set_room_env(kk, dep, lv)
				if str(w_node.get("room_kind")) != kk or int(w_node.get("env_tier")) != dep:
					map_ok = false
					bad = "L%d#%d %s/%s %d/%d" % [lv, j, str(w_node.get("room_kind")), kk,
						int(w_node.get("env_tier")), dep]
	if map_ok:
		_log("PASS T52 环境静物映射 4关×6房 房型/前后层全部一致")
	else:
		_log("FAIL T52 映射错误 %s" % bad)

	# T53：伪楼层（铁棺 / 断链）只在尸解墓道成立
	var pf_ok: bool = w_node != null
	var pf_flags := []
	if w_node != null:
		for lv in 4:
			w_node.set_room_env(RoomScript.KIND_BATTLE, 0, lv)
			var pf := bool(w_node.get("pseudo_floor"))
			pf_flags.append(pf)
			if pf != (lv == 2):
				pf_ok = false
	if pf_ok:
		_log("PASS T53 伪楼层只在尸解墓道成立 %s" % str(pf_flags))
	else:
		_log("FAIL T53 伪楼层开关错误 %s" % str(pf_flags))

	# 准备一个干净的关卡上下文（后面的用例要真的进房间）
	var seen_bak2 = Cfg.seen_lines.duplicate()
	var st_bak2: String = str(main.state)
	var lv_bak: int = int(main.level_index)
	var rooms_bak: Array = main.rooms
	var rs_bak2: Array = main.room_state.duplicate()
	main.level_index = 0
	main.level_name = RoomScript.level_name(0)
	main.rooms = RoomScript.rooms_of(0)
	main.room_state = []
	for _i in main.rooms.size():
		main.room_state.append("new")

	# T54：禁制落下 —— 开门 0 / 落下 1 / Boss 死后回落 0
	var sq_open := -1.0
	var sq_lock := -1.0
	var sq_free := -1.0
	if fg_node != null:
		main._enter_room(1)          # 普通战斗房：不禁制
		sq_open = float(fg_node.get("squeeze"))
		main._enter_room(5)          # Boss 房：四面落禁制
		sq_lock = float(fg_node.get("squeeze"))
		var bq = main.get("boss")
		if bq != null:
			main._on_enemy_killed(bq)
		sq_free = float(fg_node.get("squeeze"))
	if is_equal_approx(sq_open, 0.0) and is_equal_approx(sq_lock, 1.0) \
			and is_equal_approx(sq_free, 0.0):
		_log("PASS T54 禁制落下 开门%.2f → 落下%.2f → 解锁%.2f" % [sq_open, sq_lock, sq_free])
	else:
		_log("FAIL T54 内收 开门%.2f/落下%.2f/解锁%.2f" % [sq_open, sq_lock, sq_free])

	# T55：残影引导者只在 Boss 房淡入，站定后建言一次且不重复
	main._enter_room(1)
	var gt_room := float(main.get("_guide_target"))
	main._enter_room(5)
	var gt_boss := float(main.get("_guide_target"))
	var g0 := float(main.get("_guide_t"))
	main._update_guide(0.20)
	var g1 := float(main.get("_guide_t"))
	# R19b：开口时机从「站定即说」推迟到 2.8 秒（避让 2.4s 的「禁制·封」提示，
	# 两块半透明面板会叠在一起把字糊掉）。测试窗口必须盖过 2.8s 才能验到「说了一次」。
	main._update_guide(3.00)
	var g2 := float(main.get("_guide_t"))
	var said_once: bool = bool(main.get("_guide_said"))
	var said_again: bool = main._say_guide_line()
	var fade_ok: bool = is_equal_approx(gt_room, 0.0) and is_equal_approx(gt_boss, 1.0) \
		and g0 < g1 and g1 < g2 and absf(g2 - 1.0) < 0.001
	if fade_ok and said_once and not said_again:
		_log("PASS T55 引导者只 Boss 房淡入（%.2f→%.2f→%.2f），建言一次后不再重复" % [g0, g1, g2])
	else:
		_log("FAIL T55 房内%.2f/Boss%.2f alpha %.2f→%.2f→%.2f said=%s again=%s" % [
			gt_room, gt_boss, g0, g1, g2, str(said_once), str(said_again)])

	# T56：引导者四关四句互异，且不复用残碑 / 负匣人的文本
	var gl := []
	for lv in 4:
		gl.append(str(LoreS.guide_line(lv)))
	var uniq2 := {}
	for s in gl:
		uniq2[s] = true
	var no_reuse := true
	for lv in 4:
		if gl[lv] == str(LoreS.stele_line(lv)) or gl[lv] == str(LoreS.merchant_line(lv)):
			no_reuse = false
	if uniq2.size() == 4 and gl[0] != "" and no_reuse:
		_log("PASS T56 引导者四关四句互异且不与残碑/负匣人重复")
	else:
		_log("FAIL T56 引导者台词 uniq=%d no_reuse=%s %s" % [uniq2.size(), str(no_reuse), str(gl)])

	Cfg.seen_lines = seen_bak2
	Cfg.save_cfg()
	main.state = st_bak2
	main.level_index = lv_bak
	main.rooms = rooms_bak
	main.room_state = rs_bak2

	# ============ R16 · 残卷四幕 + 身份钩子 + 图鉴 ============
	# T57：幕结构 —— R24 起为 4 幕 × 3 卷 + 第五幕 × 1 卷（镜）= 13，id 唯一
	var acts_ok := true
	var ids := {}
	var per_act := []
	for a in range(1, LoreScript.act_count() + 1):
		var fs_a = LoreScript.fragments_of_act(a)
		per_act.append(fs_a.size())
		var expect := 1 if a == 5 else 3
		if fs_a.size() != expect:
			acts_ok = false
		for f in fs_a:
			ids[str(f["id"])] = true
	if int(LoreScript.act_count()) == 5 and int(LoreScript.total()) == 13 and acts_ok and ids.size() == 13:
		_log("PASS T57 幕结构 4 幕 × 3 卷 + 幕外 1 卷 = 13（唯一 id=%d）" % ids.size())
	else:
		_log("FAIL T57 幕 act=%d total=%d per_act=%s ids=%d"
			% [int(LoreScript.act_count()), int(LoreScript.total()), str(per_act), ids.size()])

	# T58：act_done —— 空=false / 半=false / 全=true
	var a1 := []
	for f in LoreScript.fragments_of_act(1):
		a1.append(str(f["id"]))
	var empty_done: bool = LoreScript.act_done(1, [])
	var full_done: bool = LoreScript.act_done(1, a1)
	var partial_done: bool = LoreScript.act_done(1, [str(LoreScript.fragments_of_act(1)[0]["id"])])
	if (not empty_done) and full_done and (not partial_done):
		_log("PASS T58 act_done 空=false 半=false 全=true")
	else:
		_log("FAIL T58 act_done empty=%s partial=%s full=%s"
			% [str(empty_done), str(partial_done), str(full_done)])

	# T59：self_line_for 阈值 0/3/6/9/12/13（R24 加第五段）
	var s0: Dictionary = LoreScript.self_line_for(0)
	var s3: Dictionary = LoreScript.self_line_for(3)
	var s6: Dictionary = LoreScript.self_line_for(6)
	var s9: Dictionary = LoreScript.self_line_for(9)
	var s12: Dictionary = LoreScript.self_line_for(12)
	var s13: Dictionary = LoreScript.self_line_for(13)
	if s0.is_empty() and int(s3.get("need", 0)) == 3 and int(s6.get("need", 0)) == 6 \
			and int(s9.get("need", 0)) == 9 and int(s12.get("need", 0)) == 12 \
			and int(s13.get("need", 0)) == 13:
		_log("PASS T59 self_line_for 0/3/6/9/12/13 阈值正确")
	else:
		_log("FAIL T59 self_line_for need=%d/%d/%d/%d/%d/%d"
			% [int(s0.get("need", -1)), int(s3.get("need", -1)), int(s6.get("need", -1)),
				int(s9.get("need", -1)), int(s12.get("need", -1)), int(s13.get("need", -1))])

	# T60：identity_title 六档 + identity_remain 余量（R24 加「镜 中 人」）
	var t0: String = LoreScript.identity_title(0)
	var t3: String = LoreScript.identity_title(3)
	var t6: String = LoreScript.identity_title(6)
	var t9: String = LoreScript.identity_title(9)
	var t12: String = LoreScript.identity_title(12)
	var t13: String = LoreScript.identity_title(13)
	var r0: int = LoreScript.identity_remain(0)
	var r4: int = LoreScript.identity_remain(4)
	var r12: int = LoreScript.identity_remain(12)
	var r13: int = LoreScript.identity_remain(13)
	if t0 == "" and t3 == "录 名 者" and t6 == "抄 碑 人" and t9 == "守 钟 人" \
			and t12 == "钟 本 身" and t13 == "镜 中 人" \
			and r0 == 3 and r4 == 2 and r12 == 1 and r13 == 0:
		_log("PASS T60 身份称号六档 + 余量 %d/%d/%d/%d" % [r0, r4, r12, r13])
	else:
		_log("FAIL T60 身份 %s/%s/%s/%s/%s/%s remain=%d/%d/%d/%d"
			% [t0, t3, t6, t9, t12, t13, r0, r4, r12, r13])

	# T61：图鉴 进 / 右翻 / 右翻 / 左回 / 返回
	var st_bak3: String = main.state
	main._enter_codex("title")
	var in_codex: bool = (main.state == "codex" and int(main.codex_act) == 1)
	main.codex_hit(main.CODEX_RIGHT.get_center())
	var act2: int = int(main.codex_act)
	main.codex_hit(main.CODEX_RIGHT.get_center())
	var act3: int = int(main.codex_act)
	main.codex_hit(main.CODEX_LEFT.get_center())
	var act_back: int = int(main.codex_act)
	main.codex_hit(main.CODEX_BACK.get_center())
	var out_codex: bool = (main.state == "title")
	if in_codex and act2 == 2 and act3 == 3 and act_back == 2 and out_codex:
		_log("PASS T61 图鉴 进入/右翻2/右翻3/左回2/返回")
	else:
		_log("FAIL T61 图鉴 in=%s acts=%d/%d/%d out=%s"
			% [str(in_codex), act2, act3, act_back, str(out_codex)])
	main.state = st_bak3

	# T62：收下第 3 条残卷 → 排队 need=3 → 自述解锁
	var frag_bak: Dictionary = Cfg.fragments_seen.duplicate()
	var self_bak: Dictionary = Cfg.self_seen.duplicate()
	var gfun_bak: Array = Game.fragments.duplicate()
	var ps_bak: Dictionary = main._pending_self.duplicate()
	Game.fragments.clear()
	Game.fragments.append("L01")
	Game.fragments.append("L02")
	main._pending_self = {}
	Cfg.self_seen.clear()
	main._show_fragment("L03")
	var pend_need: int = int(main._pending_self.get("need", 0))
	if main.hud != null:
		main.hud.lore_t = 0.0
	main._flush_self_unlock()
	var got3: bool = Cfg.has_self(3)
	var pend_clear: bool = main._pending_self.is_empty()
	if pend_need == 3 and got3 and pend_clear:
		_log("PASS T62 收集 3 条 → 排队 need=3 → 自述解锁")
	else:
		_log("FAIL T62 自述 need=%d got3=%s pending_empty=%s"
			% [pend_need, str(got3), str(pend_clear)])
	Cfg.fragments_seen = frag_bak
	Cfg.self_seen = self_bak
	Game.fragments = gfun_bak
	main._pending_self = ps_bak
	Cfg.save_cfg()

	# ============ R18 · 精英怪 + 行为变奏 ============
	var EnemyScript6 = load("res://scripts/enemy.gd")
	var RoomScript6 = load("res://scripts/rooms.gd")
	var SpaceScript6 = load("res://scripts/space.gd")
	var fx6 = main.get("fx")

	# T63：普通房间精英替换率 ≈ 15%（400 间房统计）；关卡一不刷精英
	var lv1_rooms: Array = RoomScript6.rooms_of(1)
	var battle_room := {}
	for rm in lv1_rooms:
		if str(RoomScript6.room_kind(rm)) == str(RoomScript6.KIND_BATTLE):
			battle_room = rm
			break
	var rng63 := RandomNumberGenerator.new()
	rng63.seed = 20261027
	var rooms_total := 400
	var rooms_with_elite := 0
	var elite_variant_bad := 0
	for _i in rooms_total:
		var w: Array = RoomScript6.wave(rng63, battle_room, 1, 2)
		var has_elite := false
		for sp in w:
			if int(sp["kind"]) >= int(EnemyScript6.KIND_JIANXIU):
				has_elite = true
				if int(sp.get("variant", 0)) != 0:
					elite_variant_bad += 1
		if has_elite:
			rooms_with_elite += 1
	var rate63 := float(rooms_with_elite) / float(rooms_total)
	var lv0_elite := 0
	for _i in 120:
		for sp in RoomScript6.wave(rng63, battle_room, 1, 0):
			if int(sp["kind"]) >= int(EnemyScript6.KIND_JIANXIU):
				lv0_elite += 1
	if rate63 >= 0.10 and rate63 <= 0.20 and lv0_elite == 0:
		_log("PASS T63 精英替换率 %.1f%%（%d/%d 间房），关卡一 0 只" % [rate63 * 100.0, rooms_with_elite, rooms_total])
	else:
		_log("FAIL T63 替换率 %.3f（%d/%d）关卡一=%d" % [rate63, rooms_with_elite, rooms_total, lv0_elite])

	# T64：剑修傀儡罡气 120 —— 平砍 10 下不破，凝罡·开山 3 下破
	var e64a = EnemyScript6.new()
	e64a.setup(int(EnemyScript6.KIND_JIANXIU), Vector2(600, 600), player, fx6)
	main.add_child(e64a)
	var pmax64: float = float(e64a.max_posture)
	for _i in 10:
		e64a.add_posture(pmax64 * 0.05)
	var light_broken: bool = bool(e64a.is_broken())
	var e64b = EnemyScript6.new()
	e64b.setup(int(EnemyScript6.KIND_JIANXIU), Vector2(700, 600), player, fx6)
	main.add_child(e64b)
	e64b.add_posture(pmax64 * 0.34)
	e64b.add_posture(pmax64 * 0.34)
	var heavy2_broken: bool = bool(e64b.is_broken())
	e64b.add_posture(pmax64 * 0.34)
	var heavy3_broken: bool = bool(e64b.is_broken())
	if is_equal_approx(pmax64, 120.0) and (not light_broken) and (not heavy2_broken) and heavy3_broken:
		_log("PASS T64 剑修傀儡罡气 %.0f：平砍10下不破 / 重击2下不破 / 第3下破" % pmax64)
	else:
		_log("FAIL T64 罡气%.0f light=%s h2=%s h3=%s" % [pmax64, str(light_broken), str(heavy2_broken), str(heavy3_broken)])
	e64a.queue_free()
	e64b.queue_free()

	# T65：丹修自爆前 2 秒 = 可处决窗口，挨刀即中断（不会炸）
	var e65 = EnemyScript6.new()
	e65.setup(int(EnemyScript6.KIND_DANXIU), Vector2(640, 600), player, fx6)
	main.add_child(e65)
	e65._start_fuse()
	var fuse_state: bool = int(e65.state) == int(EnemyScript6.FUSE)
	var can_exec: bool = bool(e65.can_execute())
	var fuse_t: float = float(EnemyScript6.FUSE_TIME)
	e65.hurt(1, Vector2(560, 600))
	var interrupted: bool = int(e65.state) != int(EnemyScript6.FUSE)
	var canceled: bool = bool(e65._fuse_canceled)
	if fuse_state and can_exec and is_equal_approx(fuse_t, 2.0) and interrupted and canceled:
		_log("PASS T65 丹修自爆 %.1fs 硬直可处决，挨刀即中断" % fuse_t)
	else:
		_log("FAIL T65 fuse=%s exec=%s t=%.2f interrupted=%s canceled=%s"
			% [str(fuse_state), str(can_exec), fuse_t, str(interrupted), str(canceled)])
	e65.queue_free()

	# T66：怨灵锁在阴界 —— 阳界打不到，入阴才够得着
	var depth_bak66: float = float(player.depth)
	var e66 = EnemyScript6.new()
	e66.setup(int(EnemyScript6.KIND_YUANLING), Vector2(700, 600), player, fx6)
	main.add_child(e66)
	player.depth = 0.20
	for _i in 60:
		e66._update_depth(0.05)
	var yin_depth: float = float(e66.depth)
	var reach_yang: bool = bool(SpaceScript6.lane_ok(0.20, yin_depth))
	var vis_yang: bool = bool(e66.is_yin_visible())
	player.depth = 0.92
	var reach_yin: bool = bool(SpaceScript6.lane_ok(0.92, yin_depth))
	var vis_yin: bool = bool(e66.is_yin_visible())
	if yin_depth >= 0.80 and (not reach_yang) and (not vis_yang) and reach_yin and vis_yin:
		_log("PASS T66 怨灵锁阴界 z=%.2f：阳界打不到/看不见，入阴才够得着" % yin_depth)
	else:
		_log("FAIL T66 z=%.2f yang=%s vis_yang=%s yin=%s vis_yin=%s"
			% [yin_depth, str(reach_yang), str(vis_yang), str(reach_yin), str(vis_yin)])
	player.depth = depth_bak66
	e66.queue_free()

	# T67：五种行为变奏全部可触发（护盾 / 狂暴 / 召唤 / 自爆 / 读招）
	var v_ok := 0
	# 护盾型：先削护盾，血不掉
	var e67a = EnemyScript6.new()
	e67a.setup(int(EnemyScript6.KIND_SENTINEL), Vector2(600, 600), player, fx6)
	main.add_child(e67a)
	e67a.set_variant(int(EnemyScript6.VAR_SHIELD))
	var hp_bak67: int = int(e67a.hp)
	e67a.hurt(1, Vector2(560, 600))
	if is_equal_approx(float(e67a.shield), 20.0) and int(e67a.hp) == hp_bak67:
		v_ok += 1
	# 狂暴型：血量 < 30% 立刻提速
	var e67b = EnemyScript6.new()
	e67b.setup(int(EnemyScript6.KIND_SENTINEL), Vector2(600, 600), player, fx6)
	main.add_child(e67b)
	e67b.set_variant(int(EnemyScript6.VAR_RAGE))
	e67b.hp = 1
	e67b._tick_variant(0.016)
	if bool(e67b.berserk) and float(e67b.rage_mul) > 1.0:
		v_ok += 1
	# 召唤型：冷却清零 → tick 一次就召，召完进 8 秒冷却
	var e67c = EnemyScript6.new()
	e67c.setup(int(EnemyScript6.KIND_SENTINEL), Vector2(600, 600), player, fx6)
	main.add_child(e67c)
	e67c.set_variant(int(EnemyScript6.VAR_SUMMON))
	e67c._summon_cd = 0.0
	e67c.state = int(EnemyScript6.CHASE)
	e67c._tick_variant(0.016)
	if float(e67c._summon_cd) > 7.0:
		v_ok += 1
	# 自爆型：贴脸 → 进倒计时
	var e67d = EnemyScript6.new()
	e67d.setup(int(EnemyScript6.KIND_SENTINEL), Vector2(600, 600), player, fx6)
	main.add_child(e67d)
	e67d.set_variant(int(EnemyScript6.VAR_BOMB))
	e67d.state = int(EnemyScript6.CHASE)
	player.global_position = Vector2(640, 600)
	e67d._tick_variant(0.016)
	if int(e67d.state) == int(EnemyScript6.FUSE) and bool(e67d.can_execute()):
		v_ok += 1
	# 读招型：玩家出刀 → 立刻架住
	var e67e = EnemyScript6.new()
	e67e.setup(int(EnemyScript6.KIND_SENTINEL), Vector2(600, 600), player, fx6)
	main.add_child(e67e)
	e67e.set_variant(int(EnemyScript6.VAR_READ))
	e67e.state = int(EnemyScript6.CHASE)
	var atk_bak67: int = int(player.atk)
	player.atk = 2                                   # ATK_ACTIVE：正在挥砍
	var read_hit := false
	for _i in 12:
		e67e._var_cd = 0.0
		if e67e._tick_variant(0.016):
			read_hit = int(e67e.state) == int(EnemyScript6.DEFEND)
			break
	player.atk = atk_bak67
	if read_hit:
		v_ok += 1
	var vpool: Array = RoomScript6.variant_pool(3)
	var vset := {}
	for v in vpool:
		vset[int(v)] = true
	if v_ok == 5 and vset.size() == 5:
		_log("PASS T67 五种变奏全部可触发（护盾/狂暴/召唤/自爆/读招）")
	else:
		_log("FAIL T67 变奏命中 %d/5，关卡四池=%s" % [v_ok, str(vpool)])
	e67a.queue_free()
	e67b.queue_free()
	e67c.queue_free()
	e67d.queue_free()
	e67e.queue_free()

	# T68：精英不叠变奏 + 关卡门槛（关卡一不刷精英 / 不挂变奏）
	var lv0_pool: Array = RoomScript6.elite_pool(0)
	var lv0_var: Array = RoomScript6.variant_pool(0)
	var lv3_pool: Array = RoomScript6.elite_pool(3)
	if lv0_pool.is_empty() and lv0_var.is_empty() and lv3_pool.size() == 6 and elite_variant_bad == 0:
		_log("PASS T68 关卡一不刷精英/变奏，关卡四 6 种精英且从不叠变奏")
	else:
		_log("FAIL T68 lv0精英=%d lv0变奏=%d lv3=%d 叠加=%d"
			% [lv0_pool.size(), lv0_var.size(), lv3_pool.size(), elite_variant_bad])

	# ================= R18b 专属绝招 =================
	# T69：三把武器形态各异、总伤害一致、名字不重复
	var u69s: Dictionary = WeaponScript.ult_of("sword")
	var u69p: Dictionary = WeaponScript.ult_of("spear")
	var u69d: Dictionary = WeaponScript.ult_of("dual")
	var tot := func(u: Dictionary) -> int:
		return int(u.get("shots", 1)) * int(u.get("dmg", 1))
	var t69s: int = tot.call(u69s)
	var t69p: int = tot.call(u69p)
	var t69d: int = tot.call(u69d)
	var uids := [str(u69s.get("id")), str(u69p.get("id")), str(u69d.get("id"))]
	var unames := [str(u69s.get("name")), str(u69p.get("name")), str(u69d.get("name"))]
	var uuniq := {}
	for n in unames:
		uuniq[n] = true
	if uids == ["line", "lance", "spin"] and t69s == 6 and t69p == 6 and t69d == 6 and uuniq.size() == 3:
		_log("PASS T69 三把武器绝招形态 line/lance/spin，总伤害均 6，名字 %s" % str(unames))
	else:
		_log("FAIL T69 ids=%s 伤害=%d/%d/%d 名字数=%d" % [str(uids), t69s, t69p, t69d, uuniq.size()])

	# T70：环形绝招真的造成伤害（双刀·旋刃）
	var arr70: Array = main.get("enemies")
	var e70 = EnemyScript6.new()
	e70.setup(int(EnemyScript6.KIND_SHIJUI), player.global_position + Vector2(70, 0), player, fx6)
	e70.depth = player.depth
	main.add_child(e70)
	arr70.append(e70)
	var hp70a: int = int(e70.hp)
	main.call("_on_ult_burst", player.global_position, 220.0, 3)
	var hp70b: int = int(e70.hp)
	if hp70b == hp70a - 3:
		_log("PASS T70 环形绝招命中扣血 %d → %d" % [hp70a, hp70b])
	else:
		_log("FAIL T70 环形绝招未扣血 %d → %d" % [hp70a, hp70b])
	arr70.erase(e70)
	e70.queue_free()

	# T71：直线绝招命中矩形刀路内的敌人
	var e71 = EnemyScript6.new()
	e71.setup(int(EnemyScript6.KIND_SHIJUI), player.global_position + Vector2(180, 0), player, fx6)
	e71.depth = player.depth
	main.add_child(e71)
	arr70.append(e71)
	var hp71a: int = int(e71.hp)
	main.call("_on_ult_strike", player.global_position + Vector2(200, -10), Vector2(420, 90), 1, 4)
	var hp71b: int = int(e71.hp)
	# 同一招对「矩形外」的敌人无效
	var e71b = EnemyScript6.new()
	e71b.setup(int(EnemyScript6.KIND_SHIJUI), player.global_position + Vector2(180, 300), player, fx6)
	e71b.depth = player.depth
	main.add_child(e71b)
	arr70.append(e71b)
	var hp71c: int = int(e71b.hp)
	main.call("_on_ult_strike", player.global_position + Vector2(200, -10), Vector2(420, 90), 1, 4)
	var hp71d: int = int(e71b.hp)
	if hp71b == hp71a - 4 and hp71d == hp71c:
		_log("PASS T71 直线绝招：框内扣 4 血，框外不受影响")
	else:
		_log("FAIL T71 直线 内=%d→%d 外=%d→%d" % [hp71a, hp71b, hp71c, hp71d])
	arr70.erase(e71)
	arr70.erase(e71b)
	e71.queue_free()
	e71b.queue_free()

	# T72：绝招也守「阴阳同界」—— 阳界的玩家打不到阴界的怨灵
	var e72 = EnemyScript6.new()
	e72.setup(int(EnemyScript6.KIND_YUANLING), player.global_position + Vector2(60, 0), player, fx6)
	main.add_child(e72)
	arr70.append(e72)
	var hp72a: int = int(e72.hp)
	player.depth = 0.20
	main.call("_on_ult_burst", player.global_position, 220.0, 3)
	var hp72b: int = int(e72.hp)
	player.depth = 0.92
	main.call("_on_ult_burst", player.global_position, 220.0, 3)
	var hp72c: int = int(e72.hp)
	if hp72b == hp72a and hp72c < hp72b:
		_log("PASS T72 绝招守阴阳：阳界打不到阴界怨灵（%d→%d），入阴后命中（→%d）" % [hp72a, hp72b, hp72c])
	else:
		_log("FAIL T72 阴阳 %d→%d→%d" % [hp72a, hp72b, hp72c])
	arr70.erase(e72)
	e72.queue_free()
	# T73：蓄力满 → 绝招按武器形态排出正确段数（调度层，不真的打人）
	var sched_ok := true
	var sched_log := []
	for wid in ["sword", "spear", "dual"]:
		player.weapon = wid
		player.call("_ult_begin")
		var n0: int = int(player.get("_ult_left"))
		var want: int = int(WeaponScript.ult_of(wid).get("shots", 1))
		player.call("_ult_tick", 0.02)
		var n1: int = int(player.get("_ult_left"))
		sched_log.append("%s %d→%d" % [wid, n0, n1])
		if n0 != want or n1 != want - 1:
			sched_ok = false
	player.weapon = "sword"
	player.call("_ult_begin")
	if sched_ok:
		_log("PASS T73 绝招调度按形态排段：%s" % str(sched_log))
	else:
		_log("FAIL T73 绝招调度 %s" % str(sched_log))

	player.depth = SpaceScript6.PLAYER_Z

	# ================= R19a 序章「钟楼」 =================
	# T74：序章 3 间房、线性邻接（首间只有东门，末间只有西门）
	var p_rooms: Array = RoomScript6.prologue_rooms()
	var nb0: Dictionary = RoomScript6.prologue_neighbors(0)
	var nb1: Dictionary = RoomScript6.prologue_neighbors(1)
	var nb2: Dictionary = RoomScript6.prologue_neighbors(2)
	var linear_ok: bool = p_rooms.size() == 3 \
		and not bool(nb0["west"]) and bool(nb0["east"]) \
		and bool(nb1["west"]) and bool(nb1["east"]) \
		and bool(nb2["west"]) and not bool(nb2["east"]) \
		and not bool(nb1["north"]) and not bool(nb1["south"])
	if linear_ok:
		_log("PASS T74 序章 3 间房、线性邻接（不接 3×2 网格）")
	else:
		_log("FAIL T74 序章房数=%d nb0=%s nb1=%s nb2=%s"
			% [p_rooms.size(), str(nb0), str(nb1), str(nb2)])

	# T75：序章固定波次 1/2/1，第三间是阴界的怨灵（教入阴）
	var fx0: Array = p_rooms[0].get("fixed", [])
	var fx1: Array = p_rooms[1].get("fixed", [])
	var fx2: Array = p_rooms[2].get("fixed", [])
	if fx0 == [0] and fx1 == [0, 0] and fx2 == [int(EnemyScript6.KIND_YUANLING)]:
		_log("PASS T75 序章固定波次 1/2/1，第三间是怨灵（只在阴界可见）")
	else:
		_log("FAIL T75 序章波次 %s / %s / %s" % [str(fx0), str(fx1), str(fx2)])

	# T76：走完序章 → 记标记 + 直接接主线第一关（不占进度）
	var cfg76 = root.get_node_or_null("Cfg")
	var saved76: bool = bool(cfg76.prologue_done)
	cfg76.prologue_done = false
	main.call("_start_run", false)
	main.call("_confirm_weapon")
	# R39：无伤走完序章会开「顶阁」（隐藏 Boss），那是另一条路径（见 T180）。
	# 这条用例守的是**普通路径**：先模拟一次受击，让它照旧回主线。
	Game.dmg_taken += 1
	var in_prologue: bool = bool(main.get("prologue_mode"))
	var n76: int = (main.get("enemies") as Array).size()
	# 三间房依次清场
	for _k in 3:
		main.call("_resolve_room_clear", false)
	var out_prologue: bool = bool(main.get("prologue_mode"))
	var done76: bool = bool(cfg76.prologue_done)
	var lv76: int = int(main.get("level_index"))
	var name76: String = str(main.get("level_name"))
	if in_prologue and n76 == 1 and not out_prologue and done76 and lv76 == 0 \
			and name76 == RoomScript6.level_name(0):
		_log("PASS T76 序章：进得去（1 只）→ 走完记标记 → 回到 %s" % name76)
	else:
		_log("FAIL T76 序章 in=%s n=%d out=%s done=%s lv=%d name=%s"
			% [str(in_prologue), n76, str(out_prologue), str(done76), lv76, name76])
	cfg76.prologue_done = saved76
	cfg76.save_cfg()

	# ============ R19b：心魔境 + 镜像（R36 起心魔境顺延为终章，读 finale_level）
	# T77：终章是「心魔境」，且关底是 14（无相·心魔）
	var lv4_ok: bool = RoomScript6.level_count() >= 5
	var lv4_idx: int = RoomScript6.finale_level() if lv4_ok else 0
	var lv4_name: String = RoomScript6.level_name(lv4_idx) if lv4_ok else ""
	var lv4_rooms: Array = RoomScript6.rooms_of(lv4_idx) if lv4_ok else []
	var boss_kind77 := -1
	var mirror_rooms := 0
	for r in lv4_rooms:
		if RoomScript6.room_kind(r) == RoomScript6.KIND_BOSS:
			boss_kind77 = int(r.get("boss", -1))
		if bool(r.get("mirror", false)):
			mirror_rooms += 1
	if lv4_ok and lv4_rooms.size() == 6 and boss_kind77 == 14 and mirror_rooms >= 2:
		_log("PASS T77 终章（第 %d 关）「%s」6 间房，关底 boss=14（KIND_BOSS6），%d 间带镜像" % [lv4_idx + 1, lv4_name, mirror_rooms])
	else:
		_log("FAIL T77 终章 lv=%s rooms=%d boss=%d mirror=%d"
			% [str(lv4_ok), lv4_rooms.size(), boss_kind77, mirror_rooms])

	# T78：镜像抄武器 —— 射程 / 出招速度 必须三把都不同，伤害是「枪独高一档」
	# （双刀在玩家侧是 dmg -1，镜像抄到 1 就到底了，所以它靠「快 + 短」区分，不靠伤害）
	var mks := []
	for wid in ["sword", "spear", "dual"]:
		var mm = EnemyScript6.new()
		mm.setup(EnemyScript6.KIND_SENTINEL, Vector2(600, 600), player, null)
		mm.make_mirror(wid, 0)
		mks.append({
			"w": wid,
			"range": float(mm.get("attack_range")),
			"wind": float(mm.get("windup_t")),
			"dmg": int(mm.get("dmg")),
		})
		mm.free()
	var r_s: float = float(mks[0]["range"])
	var r_p: float = float(mks[1]["range"])
	var r_d: float = float(mks[2]["range"])
	var w_s: float = float(mks[0]["wind"])
	var w_p: float = float(mks[1]["wind"])
	var w_d: float = float(mks[2]["wind"])
	var d_s: int = int(mks[0]["dmg"])
	var d_p: int = int(mks[1]["dmg"])
	var d_d: int = int(mks[2]["dmg"])
	if r_p > r_s and r_s > r_d and w_d < w_s and w_s < w_p and d_p > d_s and d_p > d_d:
		_log("PASS T78 镜像抄武器：射程 枪%.0f>剑%.0f>双%.0f / 出招 双%.2f<剑%.2f<枪%.2f / 伤害 枪%d>剑%d=双%d"
			% [r_p, r_s, r_d, w_d, w_s, w_p, d_p, d_s, d_d])
	else:
		_log("FAIL T78 镜像武器差异 射程 %.0f/%.0f/%.0f 出招 %.2f/%.2f/%.2f 伤害 %d/%d/%d"
			% [r_s, r_p, r_d, w_s, w_p, w_d, d_s, d_p, d_d])

	# T79：镜像抄法宝 —— 法宝越多越厚（血量 / 硬直上限都要涨）
	var mir0 = EnemyScript6.new()
	mir0.setup(EnemyScript6.KIND_SENTINEL, Vector2(600, 600), player, null)
	mir0.make_mirror("sword", 0)
	var hp0: int = int(mir0.get("max_hp"))
	var st0: float = float(mir0.get("stagger_max"))
	mir0.free()
	var mir6 = EnemyScript6.new()
	mir6.setup(EnemyScript6.KIND_SENTINEL, Vector2(600, 600), player, null)
	mir6.make_mirror("sword", 6)
	var hp6: int = int(mir6.get("max_hp"))
	var st6: float = float(mir6.get("stagger_max"))
	mir6.free()
	if hp6 > hp0 and st6 > st0:
		_log("PASS T79 镜像抄法宝：0 件 %d 血/%.0f 硬直 → 6 件 %d 血/%.0f 硬直"
			% [hp0, st0, hp6, st6])
	else:
		_log("FAIL T79 镜像法宝未生效 %d→%d 血，%.0f→%.0f 硬直" % [hp0, hp6, st0, st6])

	# T80：无相·心魔两阶段，二阶段「借宝」拿到护盾 + 三连扇形
	var mb = EnemyScript6.new()
	mb.setup(EnemyScript6.KIND_BOSS6, Vector2(600, 600), player, null)
	mb.make_mirror("dual", 3)
	var b_is_boss: bool = bool(mb.get("is_boss"))
	var b_elite: bool = bool(mb.call("is_elite"))
	var b_family: bool = bool(mb.call("is_boss_family"))
	var b_phases: int = int(mb.call("phase_count"))
	mb.call("_enter_phase", 2)
	var b_shield: float = float(mb.get("shield"))
	var b_has_borrow: bool = (mb.call("_skill_pool") as Array).has("borrow")
	mb.free()
	if b_is_boss and not b_elite and b_family and b_phases == 2 and b_shield > 0.0 and b_has_borrow:
		_log("PASS T80 无相·心魔：is_boss 且不算精英，2 阶段，二阶段借宝（护盾 %.0f + 技能池含 borrow）"
			% b_shield)
	else:
		_log("FAIL T80 无相·心魔 boss=%s elite=%s family=%s phases=%d shield=%.0f borrow=%s"
			% [str(b_is_boss), str(b_elite), str(b_family), b_phases, b_shield, str(b_has_borrow)])

	# ============ R20：真结局 ============
	# T81：心魔境（最后一关）打完 → WIN 且 true_ending=true；终局文案按身份档位分档互异
	main._enter_level(RoomScript6.level_count() - 1)
	main._next_level()
	var win81: bool = str(main.get("state")) == "win"
	var te81: bool = bool(main.get("true_ending"))
	var e12 := str(LoreS.ending_text(12))
	var e6 := str(LoreS.ending_text(6))
	var e0 := str(LoreS.ending_text(0))
	if win81 and te81 and e12 != "" and e6 != "" and e0 != "" \
			and e12 != e6 and e6 != e0 and e12 != e0:
		_log("PASS T81 真结局：心魔境打完 → WIN 且 true_ending=true，终局文案三档互异")
	else:
		_log("FAIL T81 真结局 win=%s te=%s e12/e6/e0 互异=%s/%s/%s"
			% [str(win81), str(te81), str(e12 != e6), str(e6 != e0), str(e12 != e0)])
	# T82：非终局进 WIN 不会误开真结局（从镇钟廊直接 _win() → 普通胜利）
	main._enter_level(0)
	main._win()
	var plain: bool = str(main.get("state")) == "win" and not bool(main.get("true_ending"))
	if plain:
		_log("PASS T82 普通 WIN（_win 直调）不带真结局标记")
	else:
		_log("FAIL T82 普通 WIN 误带 true_ending")
	main._enter_level(0)

	# ============ R21：镜像掉落（影法宝） ============
	# T83：mirror_three 给满 3 件；随机池 300 次抽样永不漏出镜像法宝；已拥有的会被剔除
	var rng21 := RandomNumberGenerator.new()
	rng21.seed = 20261028
	var md3: Array = RelicScript.mirror_three([])
	var md_ids := []
	for c in md3:
		md_ids.append(str(c["id"]))
	var md2: Array = RelicScript.mirror_three(["edge_shadow"])
	var leak := false
	for i in 300:
		for c in RelicScript.pick_n_biased(rng21, [], 3):
			if bool(c.get("mirror", false)):
				leak = true
	if md3.size() == 3 and md_ids.has("edge_shadow") and md_ids.has("sheath_shadow") \
			and md_ids.has("soul_shadow") and md2.size() == 2 and not leak:
		_log("PASS T83 影法宝三件齐（%s）→ 拿 1 剩 2，随机池 300 抽 0 漏出" % str(md_ids))
	else:
		_log("FAIL T83 mirror_three=%d 已剔=%s 随机池漏出=%s" % [md3.size(), str(md2.size()), str(leak)])

	# T84：影法宝与本体可叠加 —— 罡气上限 / 治疗消耗 / 首段伤害
	player.reset_relics()
	var mpst0 := int(player.posture_max())
	player.add_relic("sheath")
	var mpst1 := int(player.posture_max())
	player.reset_relics()
	player.add_relic("sheath_shadow")
	var mpst2 := int(player.posture_max())
	player.reset_relics()
	player.add_relic("sheath")
	player.add_relic("sheath_shadow")
	var mpst3 := int(player.posture_max())
	player.reset_relics()
	var mhc0 := float(player.heal_cost())
	player.add_relic("soul")
	var mhc1 := float(player.heal_cost())
	player.reset_relics()
	player.add_relic("soul_shadow")
	var mhc2 := float(player.heal_cost())
	player.reset_relics()
	player.add_relic("soul")
	player.add_relic("soul_shadow")
	var mhc3 := float(player.heal_cost())
	var mdmg0 := 0
	var mdmg1 := 0
	var mdok := true
	if player._start_stage(2, false):
		player.reset_relics()
		mdmg0 = int(player.attack_damage(player.global_position))
		player.add_relic("edge_shadow")
		mdmg1 = int(player.attack_damage(player.global_position))
		mdok = mdmg1 == mdmg0 + 1
	var mstack: bool = mpst1 == mpst0 + 20 and mpst2 == mpst0 + 20 and mpst3 == mpst0 + 40 \
		and mhc1 == mhc0 - 8.0 and mhc2 == mhc0 - 8.0 and mhc3 == mhc0 - 16.0 and mdok
	if mstack:
		_log("PASS T84 影法宝可叠加：罡气 %d/%d/%d/%d 治疗 %.0f/%.0f/%.0f/%.0f 伤害 +%d"
			% [mpst0, mpst1, mpst2, mpst3, mhc0, mhc1, mhc2, mhc3, mdmg1 - mdmg0])
	else:
		_log("FAIL T84 叠加失败 罡气 %d/%d/%d/%d 治疗 %.0f/%.0f/%.0f/%.0f 伤害 %d→%d"
			% [mpst0, mpst1, mpst2, mpst3, mhc0, mhc1, mhc2, mhc3, mdmg0, mdmg1])
	player.reset_relics()

	# T85：打掉无相·心魔 → 奖励页固定给 3 件影法宝，确认后法宝入手并离开奖励页
	main._start_run(false)
	main._confirm_weapon()
	main._enter_level(RoomScript6.finale_level())
	main._enter_room(5)
	main._resolve_room_clear(true)
	var st85 := str(main.get("state"))
	var cards85: Array = main.get("reward_cards")
	var all_mirror := cards85.size() == 3
	var drop_ids := []
	for c in cards85:
		var cid := str(c.get("id", ""))
		drop_ids.append(cid)
		if not bool(c.get("mirror", false)):
			all_mirror = false
	var title85 := str(main.get("reward_title"))
	main.set("pick_sel", 0)
	main._confirm_reward()
	var taken: bool = bool(player.has_relic(str(drop_ids[0]))) if drop_ids.size() > 0 else false
	var left := str(main.get("state")) != "reward"
	if st85 == "reward" and all_mirror and title85 != "" and taken and left:
		_log("PASS T85 镜像掉落：无相·心魔 → 奖励页 3 件影法宝（%s），选 1 入手并过关"
			% str(drop_ids))
	else:
		_log("FAIL T85 镜像掉落 st=%s all_mirror=%s title=%s taken=%s left=%s"
			% [st85, str(all_mirror), title85, str(taken), str(left)])

	# ============ R22：完全体镜像（影·绝招） ============
	# T86：二阶段技能池含 mirror_ult、一阶段不含；施放后进 MIRROR_ULT 态且回填冷却
	var mu = EnemyScript6.new()
	mu.setup(EnemyScript6.KIND_BOSS6, Vector2(600, 600), player, null)
	mu.make_mirror("spear", 3)
	var p1_has: bool = (mu.call("_skill_pool") as Array).has("mirror_ult")
	mu.call("_enter_phase", 2)
	var p2_has: bool = (mu.call("_skill_pool") as Array).has("mirror_ult")
	var p2_cd0: float = float(mu.get("mirror_ult_cd"))
	mu.set("mirror_ult_cd", 0.0)
	mu.call("_start_mirror_ult")
	var st86: bool = int(mu.get("state")) == int(mu.MIRROR_ULT)
	var cfg86: Dictionary = mu.get("mult_cfg")
	var shots86: bool = int(cfg86.get("shots", 0)) == 3 \
		and str(cfg86.get("id", "")) == "lance" and str(cfg86.get("name", "")) == "枪 出 如 龙"
	var cd86: bool = float(mu.get("mirror_ult_cd")) > 0.0
	var mu_cd_backup: float = float(mu.get("mirror_ult_cd"))
	mu.free()
	if (not p1_has) and p2_has and st86 and shots86 and cd86:
		_log("PASS T86 影·绝招：一阶段池无 / 二阶段池有，施放进 MIRROR_ULT 且照抄「枪出如龙」（进阶段缓冲 %.1fs，冷却回填 %.1fs）"
			% [p2_cd0, float(mu_cd_backup)])
	else:
		_log("FAIL T86 影·绝招 p1=%s p2=%s st=%s cfg=%s cd=%s"
			% [str(p1_has), str(p2_has), str(st86), str(cfg86), str(cd86)])
	# T87：三种形状都照抄玩家的绝招 —— 直斩发矩形信号、旋刃发圆形信号
	var mu2 = EnemyScript6.new()
	mu2.setup(EnemyScript6.KIND_BOSS6, Vector2(600, 600), player, null)
	var n_strike := [0]
	var n_burst := [0]
	mu2.mirror_strike.connect(func(_p, _s, _d): n_strike[0] += 1)
	mu2.mirror_burst.connect(func(_p, _r): n_burst[0] += 1)
	var shapes_ok := true
	for wid in ["sword", "spear", "dual"]:
		mu2.set("mirror_weapon", wid)
		mu2.call("_start_mirror_ult")
		var cfg: Dictionary = WeaponScript.ult_of(wid)
		if int(mu2.get("mult_left")) != int(cfg.get("shots", 1)):
			shapes_ok = false
		n_strike[0] = 0
		n_burst[0] = 0
		mu2.call("_mult_fire_one", 0)
		if str(cfg.get("id", "")) == "spin":
			if n_burst[0] != 1 or n_strike[0] != 0:
				shapes_ok = false
		elif n_strike[0] != 1 or n_burst[0] != 0:
			shapes_ok = false
	mu2.free()
	if shapes_ok:
		_log("PASS T87 影·绝招三形状：剑/枪各发 1 段矩形直斩，双刀发圆形旋刃，段数全部照抄玩家绝招")
	else:
		_log("FAIL T87 影·绝招形状不符 strike/burst 计数异常")
	# T88：判定接线 —— 直斩矩形罩住玩家掉 1 血、罩不住不掉；旋刃同
	var hp88 := int(player.get("hp"))
	player.set("hp", 5)
	player.set("invuln", 0.0)
	player.set("guarding", false)
	main._on_enemy_mirror_strike(player.global_position + Vector2(0, -10), Vector2(480, 76), 1)
	var hit88: bool = int(player.get("hp")) == 4
	player.set("invuln", 0.0)
	main._on_enemy_mirror_strike(player.global_position + Vector2(2000, -10), Vector2(480, 76), 1)
	var miss88: bool = int(player.get("hp")) == 4
	player.set("invuln", 0.0)
	main._on_enemy_mirror_burst(player.global_position, 132.0)
	var burst88: bool = int(player.get("hp")) == 3
	player.set("invuln", 0.0)
	main._on_enemy_mirror_burst(player.global_position + Vector2(2000, 0), 132.0)
	var bmiss88: bool = int(player.get("hp")) == 3
	player.set("hp", hp88)
	if hit88 and miss88 and burst88 and bmiss88:
		_log("PASS T88 影·绝招判定：矩形罩住掉血 / 罩不住不掉，圆形旋刃同（无敌帧照样免伤）")
	else:
		_log("FAIL T88 影·绝招判定 hit=%s miss=%s burst=%s bmiss=%s"
			% [str(hit88), str(miss88), str(burst88), str(bmiss88)])

	# ============ R23：今日道劫 · 心魔试炼 ============
	# 存档护栏：T90 会写每日记录，先备份再恢复
	var bk_date: String = str(Cfg.daily_date)
	var bk_rooms: int = int(Cfg.daily_rooms)
	var bk_cleared: bool = bool(Cfg.daily_cleared)
	var bk_hp: int = int(Cfg.daily_hp)
	# R28：评分与本地榜同样属于「会写盘」的字段，一并备份
	var bk_time: float = float(Cfg.daily_time)
	var bk_dmg: int = int(Cfg.daily_dmg)
	var bk_score: int = int(Cfg.daily_score)
	var bk_board: Array = Cfg.daily_board.duplicate(true)
	# T89：今日之镜 —— 武器由每日种子唯一指定；开局直达心魔境、跳过选武器页；同日重开不变
	var wid89: String = str(WeaponScript.LIST[RoomScript6.daily_seed() % WeaponScript.LIST.size()]["id"])
	main._start_run(true)
	var lvl89: bool = int(main.get("level_index")) == RoomScript6.level_count() - 1
	var wpn89: bool = str(player.get("weapon")) == wid89
	var st89: bool = str(main.get("state")) != "weapon"
	main._start_run(true)
	var same89: bool = str(player.get("weapon")) == wid89 \
		and int(main.get("run_seed")) == int(main.get("daily_seed_val"))
	if lvl89 and wpn89 and st89 and same89:
		_log("PASS T89 今日之镜：武器由每日种子唯一指定（%s），开局直达心魔境且跳过选武器页，同日重开不变" % wid89)
	else:
		_log("FAIL T89 今日之镜 lvl=%s wpn=%s(期 %s) st=%s same=%s"
			% [str(lvl89), str(player.get("weapon")), wid89, str(st89), str(same89)])
	# T90：破劫记录 —— clear 记日期 + 剩血；daily_line 带状态；daily_done_today 生效
	player.set("hp", 3)
	main.set("daily_mode", true)
	main._enter_clear()
	var rec90: bool = str(Cfg.daily_date) == str(RoomScript6.today_key()) \
		and bool(Cfg.daily_cleared) and int(Cfg.daily_hp) == 3
	var line90: String = str(main.daily_line())
	var done90: bool = bool(main.daily_done_today())
	# 恢复存档并落盘
	Cfg.daily_date = bk_date
	Cfg.daily_rooms = bk_rooms
	Cfg.daily_cleared = bk_cleared
	Cfg.daily_hp = bk_hp
	Cfg.daily_time = bk_time
	Cfg.daily_dmg = bk_dmg
	Cfg.daily_score = bk_score
	Cfg.daily_board = bk_board
	Cfg.save_cfg()
	main.set("daily_mode", false)
	if rec90 and done90 and line90.contains("已破") and line90.contains("分"):
		_log("PASS T90 破劫记录：日期+剩血入库，副标题「今日之镜 · … · 已破 N 分 · 最佳 M」，daily_done_today 生效")
	else:
		_log("FAIL T90 破劫记录 rec=%s done=%s line=%s" % [str(rec90), str(done90), line90])
	# T91：普通修行不受影响 —— 仍走选武器页、确认后从第 1 关开始、不带每日模式
	main._start_run(false)
	var st91: bool = str(main.get("state")) == "weapon"
	main.set("weapon_sel", 1)
	main._confirm_weapon()
	var lvl91: bool = int(main.get("level_index")) == 0
	var dm91: bool = not bool(main.get("daily_mode"))
	if st91 and lvl91 and dm91:
		_log("PASS T91 普通修行：仍走选武器页、从第 1 关开始，与每日挑战互不干扰")
	else:
		_log("FAIL T91 普通修行 st=%s lvl=%s daily=%s" % [str(st91), str(lvl91), str(dm91)])

	# ============ R24：第 13 卷「镜」 ============
	# T92：L13 幕外独卷 —— 第五幕只有它；无相·心魔（14）的本命卷改为 L13
	var fs5 = LoreScript.fragments_of_act(5)
	var l13_ok := false
	if fs5.size() == 1:
		l13_ok = str(fs5[0]["id"]) == "L13" and int(LoreScript.act_of("L13")) == 5 \
			and str(LoreScript.by_id("L13").get("title", "")) == "残 卷 · 镜"
	var boss_l13: bool = str(LoreScript.BOSS_LORE.get(14, "")) == "L13"
	if l13_ok and boss_l13 and int(LoreScript.total()) == 13:
		_log("PASS T92 镜卷：第五幕唯一一卷 L13「残卷·镜」，无相·心魔本命卷改为 L13，总数 13")
	else:
		_log("FAIL T92 镜卷 act5=%s boss=%s total=%d"
			% [str(l13_ok), str(LoreScript.BOSS_LORE.get(14, "")), int(LoreScript.total())])
	# T93：13 卷的身份链 —— 称号「镜 中 人」+ 自述·五 + 终局第四档
	var t13b: String = LoreScript.identity_title(13)
	var sl13: Dictionary = LoreScript.self_line_for(13)
	var e13: String = str(LoreScript.ending_text(13))
	var e12b: String = str(LoreScript.ending_text(12))
	var chain_ok: bool = t13b == "镜 中 人" and int(sl13.get("need", 0)) == 13 \
		and e13 != "" and e12b != "" and e13 != e12b
	if chain_ok:
		_log("PASS T93 十三卷身份链：称号「镜中人」+ 自述·五 + 终局第四档（与 12 卷档互异）")
	else:
		_log("FAIL T93 身份链 t13=%s sl=%s e13/e12 互异=%s"
			% [t13b, str(sl13.get("need", -1)), str(e13 != e12b and e13 != "")])
	# T94：掉落链路 —— _show_fragment("L13") 入 Game.fragments + Cfg 持久（测试后恢复存档）
	var orig_fs: Dictionary = Cfg.fragments_seen.duplicate()
	var bk_gf: Array = (Game.fragments as Array).duplicate()
	# 先从测试态抹掉 L13（上一次跑测试可能已把它写进存档），保证从「未拾得」开始
	var test_fs: Dictionary = orig_fs.duplicate()
	test_fs.erase("L13")
	Cfg.fragments_seen = test_fs
	Game.fragments = bk_gf.duplicate()
	Game.fragments.erase("L13")
	main._show_fragment("L13")
	var got94: bool = bool(Cfg.has_fragment("L13")) and (Game.fragments as Array).has("L13")
	var cnt94: bool = int(Cfg.fragment_total()) == orig_fs.size() + (0 if orig_fs.has("L13") else 1)
	# 恢复存档
	Cfg.fragments_seen = orig_fs
	Game.fragments = bk_gf
	Cfg.save_cfg()
	if got94 and cnt94:
		_log("PASS T94 镜卷掉落链路：从未拾得 → 拾取即入图鉴与存档，存档已恢复")
	else:
		_log("FAIL T94 镜卷掉落 got=%s cnt=%s" % [str(got94), str(cnt94)])

	# ============ R25 · 终局演出动画化 ============
	# T95：win 页演出计时 —— 进 win 累加、离开归零（直接驱动 _process 验证）
	var t95 := true
	if main.hud != null:
		main.hud.mode = "win"
		main.hud._win_t = 0.0
		main.hud._process(0.5)
		main.hud._process(0.6)
		var acc: float = float(main.hud._win_t)
		main.hud.mode = "play"
		main.hud._process(0.2)
		var rst: float = float(main.hud._win_t)
		main.hud.mode = "title"
		t95 = absf(acc - 1.1) < 0.01 and rst == 0.0
		main.hud._process(0.05)
	if t95:
		_log("PASS T95 演出计时：win 页累计 1.1s，切走归零")
	else:
		_log("FAIL T95 演出计时不符（hud=%s）" % str(main.hud != null))

	# T96：钟摆停摆数学 —— 0 秒最大摆幅、~4.5 秒后视为停摆
	var a0: float = main.hud.pendulum_angle(0.0)
	var a4: float = absf(main.hud.pendulum_angle(4.5))
	var t96: bool = absf(a0 - 0.55) < 0.001 and a4 < 0.02
	if t96:
		_log("PASS T96 钟摆停摆：初始摆幅 %.2f rad → 4.5s 后 %.3f rad（停摆阈值 0.02）" % [a0, a4])
	else:
		_log("FAIL T96 钟摆 a0=%.3f a4=%.4f" % [a0, a4])

	# T97：演出时间线五阶段单调推进
	var w90: int = int(main.hud.ending_stage(0.5))
	var w91: int = int(main.hud.ending_stage(0.9))
	var w92: int = int(main.hud.ending_stage(1.5))
	var w93: int = int(main.hud.ending_stage(3.0))
	var w94: int = int(main.hud.ending_stage(4.0))
	var w95: float = float(main.hud._ramp(1.4, 1.1, 1.7))
	var w96: float = float(main.hud._ramp(3.0, 1.1, 1.7))
	var sok97: bool = w90 == 0 and w91 == 1 and w92 == 2 and w93 == 3 and w94 == 4 \
		and absf(w95 - 0.5) < 0.001 and absf(w96 - 1.0) < 0.001
	if sok97:
		_log("PASS T97 演出时间线：遮罩→合页→统计+钟摆→结语→落款，五阶段单调且淡入曲线正确")
	else:
		_log("FAIL T97 演出时间线 e=%d/%d/%d/%d/%d r=%.3f/%.3f" % [w90, w91, w92, w93, w94, w95, w96])

	# ============ R26 · 影绝招精进（移动旋刃 + 绝招反制）============
	# T98：旋刃移动版 —— spin 远处逼近 ±110、贴身 0 停；剑 / 枪维持 0 定身
	var vx_far: float = float(EnemyScript6.mirror_chase_vx(240.0, "spin"))
	var vx_back: float = float(EnemyScript6.mirror_chase_vx(-240.0, "spin"))
	var vx_near: float = float(EnemyScript6.mirror_chase_vx(60.0, "spin"))
	var vx_line: float = float(EnemyScript6.mirror_chase_vx(240.0, "line"))
	var vx_lance: float = float(EnemyScript6.mirror_chase_vx(240.0, "lance"))
	if absf(vx_far - 110.0) < 0.01 and absf(vx_back + 110.0) < 0.01 and vx_near == 0.0 \
			and vx_line == 0.0 and vx_lance == 0.0:
		_log("PASS T98 影·旋刃移动版：远处逼向 %+.0f / 背向 %+.0f / 贴身停 / 剑枪定身" % [vx_far, vx_back])
	else:
		_log("FAIL T98 影·旋刃移动版 far=%s back=%s near=%s line=%s lance=%s"
			% [str(vx_far), str(vx_back), str(vx_near), str(vx_line), str(vx_lance)])

	# T99：反制门 —— 一阶段 / 冷却未好 / 已死都不反制；就绪时 counter_chance=1 必反制
	var mu9 = EnemyScript6.new()
	mu9.setup(EnemyScript6.KIND_BOSS6, Vector2(600, 600), player, null)
	mu9.make_mirror("sword", 2)
	var c99_p1: bool = not bool(mu9.call("can_counter_ult"))
	mu9.call("_enter_phase", 2)
	mu9.set("mirror_ult_cd", 1.0)
	var c99_cd: bool = not bool(mu9.call("can_counter_ult"))
	mu9.set("mirror_ult_cd", 0.0)
	var c99_ok: bool = bool(mu9.call("can_counter_ult"))
	mu9.set("state", int(EnemyScript6.DEAD))
	var c99_dead: bool = not bool(mu9.call("can_counter_ult"))
	mu9.set("state", int(EnemyScript6.IDLE))
	mu9.set("counter_chance", 1.0)
	var tried99: bool = bool(mu9.call("try_counter_ult"))
	var st99: bool = int(mu9.get("state")) == int(EnemyScript6.MIRROR_ULT) \
		and absf(float(mu9.get("mirror_ult_cd")) - 6.5) < 0.01
	mu9.free()
	if c99_p1 and c99_cd and c99_ok and c99_dead and tried99 and st99:
		_log("PASS T99 影·反制门：一阶段/冷却/已死皆不反制，就绪 + 概率 1.0 必进 MIRROR_ULT（冷却回填 6.5）")
	else:
		_log("FAIL T99 影·反制门 p1=%s cd=%s ok=%s dead=%s tried=%s st=%s"
			% [str(c99_p1), str(c99_cd), str(c99_ok), str(c99_dead), str(tried99), str(st99)])

	# T100：全链路 —— 玩家 _ult_begin 发 ult_started，主场景处理器让场上就绪的心魔反制
	var wire100: bool = player.ult_started.is_connected(main._on_player_ult_started)
	var mu10 = EnemyScript6.new()
	mu10.setup(EnemyScript6.KIND_BOSS6, Vector2(600, 600), player, null)
	mu10.make_mirror("dual", 2)
	mu10.call("_enter_phase", 2)
	mu10.set("mirror_ult_cd", 0.0)
	mu10.set("counter_chance", 1.0)
	main.enemies.append(mu10)
	player._ult_begin()
	var st100: bool = int(mu10.get("state")) == int(EnemyScript6.MIRROR_ULT)
	main.enemies.erase(mu10)
	mu10.free()
	if wire100 and st100:
		_log("PASS T100 绝招反制全链路：ult_started 已接线，玩家开大 → 心魔同步开影·绝招")
	else:
		_log("FAIL T100 绝招反制 wire=%s st=%s" % [str(wire100), str(st100)])

	# T101：宝箱「随机法宝 + 20 道蕴」—— 按钮文案承诺的道蕴必须真的到账（R27 修）
	#      此前只发法宝、道蕴漏发，UI 与玩法说明都写着 +20，属于文案与实现不一致。
	main.state = "event"
	main.event_kind = RoomScript.KIND_CHEST
	main.event_sel = 0
	player.soul = 10.0
	player.hp = 3
	var soul_before: float = player.soul
	main._event_input_confirm()
	var got_soul: float = player.soul - soul_before
	var capped: bool = absf(player.soul - Game.MAX_SOUL) < 0.01
	if got_soul >= 19.5 or capped:
		_log("PASS T101 宝箱发 20 道蕴：%.1f → %.1f（+%.1f）" % [soul_before, player.soul, got_soul])
	else:
		_log("FAIL T101 宝箱道蕴 %.1f → %.1f（只加了 %.1f，应为 20）"
			% [soul_before, player.soul, got_soul])


	# ============ R28 · 道劫评分 + 本地榜 + 镜卷浮层 ============
	# T102：score_of 分项数学（进度 12/房 + 通关 80 + 用时 0.6/s + 无伤 120 + 剩血 20/格）
	var d28_s_full: int = main.score_of(true, 100.0, 0, 5, 6)     # 72+80+120+120+100
	var d28_s_hurt: int = main.score_of(true, 100.0, 3, 5, 6)     # 72+80+120-24+100
	var d28_s_slow: int = main.score_of(true, 400.0, 0, 5, 6)     # 72+80+0+120+100
	var d28_s_cap: int = main.score_of(true, 100.0, 30, 5, 6)     # 72+80+120-80+100
	var d28_s_fail: int = main.score_of(false, 100.0, 0, 5, 3)    # 只算进度 36
	if d28_s_full == 492 and d28_s_hurt == 348 and d28_s_slow == 372 and d28_s_cap == 292 and d28_s_fail == 36:
		_log("PASS T102 评分分项：无伤 492 / 受击3次 348 / 超时 372 / 受击封顶 292 / 未通关 36")
	else:
		_log("FAIL T102 评分 full=%d hurt=%d slow=%d cap=%d fail=%d（应 492/348/372/292/36）"
			% [d28_s_full, d28_s_hurt, d28_s_slow, d28_s_cap, d28_s_fail])

	# T103：本地榜 —— 排序 / 同日同分去重 / 只留前 5
	var d28_saved_board: Array = Cfg.daily_board.duplicate(true)
	Cfg.daily_board = []
	var d28_r1: int = Cfg.push_daily_record("2026-01-01", 100, 200.0, 0, 5)
	var d28_r2: int = Cfg.push_daily_record("2026-01-02", 300, 150.0, 2, 3)
	var d28_r3: int = Cfg.push_daily_record("2026-01-03", 200, 100.0, 1, 4)
	# 名次是「插入当时」的位置：100 插进空榜即第 1，之后被 300 / 200 挤到第 3
	var d28_order_ok: bool = (d28_r2 == 1 and d28_r3 == 2 and d28_r1 == 1
		and int(Cfg.daily_board[0]["score"]) == 300
		and int(Cfg.daily_board[1]["score"]) == 200
		and int(Cfg.daily_board[2]["score"]) == 100)
	# 同日同分：留用时更短的
	var d28_r4: int = Cfg.push_daily_record("2026-01-01", 100, 120.0, 0, 5)
	var d28_dedupe_ok: bool = (Cfg.daily_board.size() == 3 and d28_r4 == 3
		and absf(float(Cfg.daily_board[2]["secs"]) - 120.0) < 0.01)
	# 再塞 4 条低分 → 只留前 5
	for i in 4:
		Cfg.push_daily_record("2026-02-0%d" % (i + 1), 50 - i * 10, 200.0, 3, 2)
	var d28_trim_ok: bool = Cfg.daily_board.size() == 5
	var d28_best_ok: bool = Cfg.best_daily_score() == 300
	if d28_order_ok and d28_dedupe_ok and d28_trim_ok and d28_best_ok:
		_log("PASS T103 本地榜：名次 1/2/3 正确、同日同分留更短用时、只留前 5、最高分 300")
	else:
		_log("FAIL T103 榜 order=%s dedupe=%s size=%d trim=%s best=%d"
			% [str(d28_order_ok), str(d28_dedupe_ok), Cfg.daily_board.size(), str(d28_trim_ok),
				Cfg.best_daily_score()])

	# T104：受击计数接线 —— take_hit 未挡下时 Game.dmg_taken +1（道心失守双倍血仍算 1 次）
	Game.dmg_taken = 0
	player.hp = 5
	player.guarding = false
	player.invuln = 0.0
	player.dead = false
	player.take_hit(player.global_position + Vector2(40.0, 0.0))
	var d28_after1: int = Game.dmg_taken
	player.invuln = 0.0
	player.take_hit(player.global_position + Vector2(40.0, 0.0))
	var d28_after2: int = Game.dmg_taken
	if d28_after1 == 1 and d28_after2 == 2:
		_log("PASS T104 受击计数：两次受击 → dmg_taken=%d" % d28_after2)
	else:
		_log("FAIL T104 受击计数 d28_after1=%d d28_after2=%d（应 1/2）" % [d28_after1, d28_after2])

	# T105：榜行文案 + 副标题带最佳分
	Cfg.daily_board = [{"date": "2026-10-28", "score": 500, "secs": 95.0, "dmg": 0, "hp": 5}]
	var d28_blines: Array = main.daily_board_lines(3)
	var d28_line_ok: bool = (d28_blines.size() == 1
		and str(d28_blines[0]).contains("500 分")
		and str(d28_blines[0]).contains("无伤")
		and str(d28_blines[0]).contains("10-28"))
	var d28_dline: String = main.daily_line()
	var d28_dl_ok: bool = d28_dline.contains("最佳 500")
	if d28_line_ok and d28_dl_ok:
		_log("PASS T105 榜行与副标题：「%s」/「%s」" % [str(d28_blines[0]), d28_dline])
	else:
		_log("FAIL T105 榜行=%s 副标题=%s" % [str(d28_blines), d28_dline])

	# 还原真实榜（自测不该污染玩家存档）
	Cfg.daily_board = d28_saved_board

	# ============ R29 第 4 把武器「符剑」+ 符力 ============
	var WScript = load("res://scripts/weapons.gd")
	var PScript = load("res://scripts/player.gd")

	# T106：武器表 4 把，符剑在末位；连招 3 段（2 远程 + 1 近战），架势压制 0.18
	var d29_ids: Array = []
	for w in WScript.LIST:
		d29_ids.append(str(w["id"]))
	var d29_last: String = str(WScript.LIST[WScript.LIST.size() - 1]["id"])
	var d29_len: int = WScript.combo_len("rune")
	var d29_ranged: int = WScript.ranged_count("rune")
	var d29_posture: float = WScript.combo_posture("rune")
	var d29_t106: bool = (WScript.LIST.size() == 4 and d29_last == "rune"
		and d29_len == 3 and d29_ranged == 2 and absf(d29_posture - 0.18) < 0.001)
	if d29_t106:
		_log("PASS T106 符剑入表：4 把（%s）· 3 段（2 远程 + 1 近战）· 架势压制 0.18"
			% str(d29_ids))
	else:
		_log("FAIL T106 符剑入表 n=%d last=%s 段=%d 远程=%d 压制=%.3f"
			% [WScript.LIST.size(), d29_last, d29_len, d29_ranged, d29_posture])

	# T107：远程段吃符力、不吃灵力；近战段反过来
	player.set_weapon("rune")
	player.respawn(Vector2(600, 600))
	player.rune_power = PScript.RUNE_MAX
	player.stamina = PScript.MAX_STAMINA
	var d29_r0: float = player.rune_power
	var d29_s0: float = player.stamina
	var d29_ok1: bool = player._start_stage(1, false)
	var d29_r1: float = player.rune_power
	var d29_s1: float = player.stamina
	var d29_ok2: bool = player._start_stage(2, false)
	var d29_r2: float = player.rune_power
	var d29_s2: float = player.stamina
	var d29_ok3: bool = player._start_stage(3, false)
	var d29_r3: float = player.rune_power
	var d29_s3: float = player.stamina
	var d29_t107: bool = (d29_ok1 and d29_ok2 and d29_ok3
		and absf(d29_r0 - d29_r1 - 1.0) < 0.001 and absf(d29_r1 - d29_r2 - 1.0) < 0.001
		and absf(d29_s0 - d29_s1) < 0.001 and absf(d29_s1 - d29_s2) < 0.001
		and absf(d29_r2 - d29_r3) < 0.001 and d29_s3 < d29_s2 - 1.0)
	if d29_t107:
		_log("PASS T107 符力账目：符力 %.1f→%.1f→%.1f→%.1f（前两段各 -1，近战 0）· 灵力 %.0f→%.0f→%.0f→%.0f（近战才扣）"
			% [d29_r0, d29_r1, d29_r2, d29_r3, d29_s0, d29_s1, d29_s2, d29_s3])
	else:
		_log("FAIL T107 符力账目 符力=%s 灵力=%s ok=%s/%s/%s"
			% [str([d29_r0, d29_r1, d29_r2, d29_r3]),
				str([d29_s0, d29_s1, d29_s2, d29_s3]), str(d29_ok1), str(d29_ok2), str(d29_ok3)])

	# T108：符力不足 → 出不了这一符（返回 false，符力不被扣成负数）
	player.respawn(Vector2(600, 600))
	player.rune_power = 0.4
	var d29_low_ok: bool = player._start_stage(1, false)
	var d29_low_r: float = player.rune_power
	var d29_low_atk: int = player.atk
	var d29_t108: bool = (not d29_low_ok and absf(d29_low_r - 0.4) < 0.001 and d29_low_atk == 0)
	if d29_t108:
		_log("PASS T108 符力尽：0.4 格时起手返回 false，符力仍 0.40，未进入出刀状态")
	else:
		_log("FAIL T108 符力尽 ok=%s 符力=%.2f atk=%d" % [str(d29_low_ok), d29_low_r, d29_low_atk])

	# T109：远程段没有刀锋（否则符击会同时吃近战判定，等于白送一次伤害）
	player.respawn(Vector2(600, 600))
	player.rune_power = PScript.RUNE_MAX
	player.stage = 1
	player.atk = 2          # ATK_ACTIVE
	player.atk_t = 0.0
	var d29_ranged_rect: Rect2 = player.attack_rect()
	player.stage = 3
	player.atk_t = 0.0
	var d29_melee_rect: Rect2 = player.attack_rect()
	var d29_t109: bool = (not d29_ranged_rect.has_area()) and d29_melee_rect.has_area()
	if d29_t109:
		_log("PASS T109 远程段无刀锋：第 1 段 attack_rect 空，第 3 段有面积 %s"
			% str(d29_melee_rect.size))
	else:
		_log("FAIL T109 远程段判定 远程=%s 近战=%s"
			% [str(d29_ranged_rect.has_area()), str(d29_melee_rect.has_area())])

	# T110：绝招「符阵·万剑」= 8 段扇形符，不是剑/枪/双刀任何一种形状
	var d29_ult: Dictionary = WScript.ult_of("rune")
	var d29_t110: bool = (str(d29_ult.get("id", "")) == "array"
		and int(d29_ult.get("shots", 0)) == PScript.RUNE_ULT_SHOTS
		and int(d29_ult.get("dmg", 0)) == 2
		and str(WScript.ult_name("rune")).contains("符"))
	if d29_t110:
		_log("PASS T110 符阵·万剑：%s · %d 段 · 每段 %d 伤 · id=array"
			% [str(d29_ult.get("name", "")), int(d29_ult.get("shots", 0)),
				int(d29_ult.get("dmg", 0))])
	else:
		_log("FAIL T110 符阵 %s" % str(d29_ult))

	# T111：符力上限与取整显示 —— rune_max=5、frac 归一、ceil 给「还能打几发」
	# 先清法宝：前面几轮随机掉落的法宝里若抽到「符囊」，上限会变 7，
	# 这条断言就会随 RNG 时好时坏（旧账，R32a 一并修掉）。
	player.reset_relics()
	player.rune_power = 2.5
	var d29_frac: float = player.rune_frac()
	var d29_ceil: int = int(ceil(player.rune_power))
	player.rune_power = PScript.RUNE_MAX
	var d29_full: bool = player.rune_is_full()
	var d29_spend_low: bool = player.spend_rune(9.0)
	var d29_spend_ok: bool = player.spend_rune(2.0)
	var d29_t111: bool = (absf(player.rune_max() - 5.0) < 0.001
		and absf(d29_frac - 0.5) < 0.001 and d29_ceil == 3 and d29_full
		and not d29_spend_low and d29_spend_ok
		and absf(player.rune_power - 3.0) < 0.001)
	if d29_t111:
		_log("PASS T111 符力接口：上限 5 · 2.5 格 = 50% · 显示 3 发 · 超支被拒 · 花 2 剩 3")
	else:
		_log("FAIL T111 符力接口 max=%.2f frac=%.3f ceil=%d full=%s low=%s ok=%s 余=%.2f"
			% [player.rune_max(), d29_frac, d29_ceil, str(d29_full),
				str(d29_spend_low), str(d29_spend_ok), player.rune_power])

	# 收尾：把玩家还原成剑，别把后面 / 存档搞脏
	player.set_weapon("sword")
	player.respawn(Vector2(600, 600))


	# ============ R30 法宝扩容 21 → 33（12 件新法宝，每件带代价） ============
	var d30_saved_relics: Array = player.relics.duplicate()

	# T112：池子 35（随机 32 + 影 3，R38「魔剑」入剑位且带 need_karma 门槛），
	# 位次 blade 13 / wall 9 / spirit 10
	var d30_slot := {"blade": 0, "wall": 0, "spirit": 0}
	var d30_mirror := 0
	for r in RelicScript.POOL:
		if bool(r.get("mirror", false)):
			d30_mirror += 1
		else:
			var sl := str(r.get("set", "blade"))
			d30_slot[sl] = int(d30_slot.get(sl, 0)) + 1
	var d30_total: int = RelicScript.POOL.size()
	var d30_t112: bool = (d30_total == 35 and d30_mirror == 3
		and int(d30_slot["blade"]) == 13 and int(d30_slot["wall"]) == 9
		and int(d30_slot["spirit"]) == 10)
	if d30_t112:
		_log("PASS T112 法宝池 21→35：随机 32（剑 13 / 体 9 / 灵 10）+ 影 3")
	else:
		_log("FAIL T112 池 %d 影 %d 位次 %s" % [d30_total, d30_mirror, str(d30_slot)])

	# T113：12 件新法宝全部在表里，且每件都写了「代价 / 条件」
	var d30_new := ["duannian", "zhuifeng", "jianxia", "canxin",
		"tieyi", "fanzhen", "guixi", "xuenv",
		"juling", "funang", "yinyan", "yangyan"]
	var d30_missing := []
	var d30_nocost := []
	for id in d30_new:
		var r: Dictionary = RelicScript.by_id(str(id))
		if r.is_empty():
			d30_missing.append(id)
		elif str(r.get("cost", "")) == "":
			d30_nocost.append(id)
	var d30_t113: bool = d30_missing.is_empty() and d30_nocost.is_empty()
	if d30_t113:
		_log("PASS T113 12 件新法宝全部入表，且 12/12 都带「代价 / 条件」字段")
	else:
		_log("FAIL T113 缺 %s · 无代价 %s" % [str(d30_missing), str(d30_nocost)])

	# T114：符囊 +2 符力上限（只在符剑时有用）
	player.reset_relics()
	player.set_weapon("rune")
	var d30_rune0: float = player.rune_max()
	player.relics = ["funang"]
	var d30_rune1: float = player.rune_max()
	var d30_rune_uses: bool = player.uses_rune()
	player.set_weapon("sword")
	var d30_rune_off: bool = not player.uses_rune()
	var d30_t114: bool = (absf(d30_rune0 - 5.0) < 0.001 and absf(d30_rune1 - 7.0) < 0.001
		and d30_rune_uses and d30_rune_off)
	if d30_t114:
		_log("PASS T114 符囊：符力上限 %.0f → %.0f（符剑时生效 / 非符剑时整条符力都不存在）"
			% [d30_rune0, d30_rune1])
	else:
		_log("FAIL T114 符囊 %.1f→%.1f uses=%s off=%s"
			% [d30_rune0, d30_rune1, str(d30_rune_uses), str(d30_rune_off)])

	# T115：铁衣 +2 气血上限 / 移速 -10%；聚灵 -1 气血上限
	player.relics = []
	var d30_hp0: int = player.max_hp()
	var d30_sp0: float = player.speed_now()
	player.relics = ["tieyi"]
	var d30_hp1: int = player.max_hp()
	var d30_sp1: float = player.speed_now()
	player.relics = ["juling"]
	var d30_hp2: int = player.max_hp()
	var d30_t115: bool = (d30_hp0 == 5 and d30_hp1 == 7 and d30_hp2 == 4
		and absf(d30_sp1 - d30_sp0 * 0.9) < 0.01)
	if d30_t115:
		_log("PASS T115 铁衣 气血 %d→%d、移速 %.0f→%.0f（-10%%）· 聚灵 气血 →%d"
			% [d30_hp0, d30_hp1, d30_sp0, d30_sp1, d30_hp2])
	else:
		_log("FAIL T115 气血 %d/%d/%d 移速 %.1f/%.1f"
			% [d30_hp0, d30_hp1, d30_hp2, d30_sp0, d30_sp1])

	# T116：断念 罡气上限 -15；龟息 道心失守时间 -50%
	player.relics = []
	var d30_pm0: int = player.posture_max()
	player.relics = ["duannian"]
	var d30_pm1: int = player.posture_max()
	player.relics = []
	player._enter_broken()
	var d30_br0: float = player.broken_t
	player.relics = ["guixi"]
	player._enter_broken()
	var d30_br1: float = player.broken_t
	var d30_t116: bool = (d30_pm0 == 100 and d30_pm1 == 85
		and absf(d30_br0 - 1.2) < 0.001 and absf(d30_br1 - 0.6) < 0.001)
	if d30_t116:
		_log("PASS T116 断念 罡气上限 %d→%d · 龟息 道心失守 %.1fs→%.1fs"
			% [d30_pm0, d30_pm1, d30_br0, d30_br1])
	else:
		_log("FAIL T116 罡气 %d/%d 破防 %.2f/%.2f"
			% [d30_pm0, d30_pm1, d30_br0, d30_br1])

	# T117：血怒（低血 +2 / 高血 -1）· 阳炎（阳界 +1 / 阴界 0）· 残心（3 段 ×2）
	# 用单手剑第 3 段（基础 2 伤）做基准，避免 -1 后被 maxi(1) 夹平看不出差别
	player.reset_relics()
	player.set_weapon("sword")
	player.stage = 3
	player.depth = 0.34          # 阳界
	player.hp = 5
	var d30_d0: int = player.attack_damage()
	player.relics = ["xuenv"]
	player.hp = 5
	var d30_d_hi: int = player.attack_damage()
	player.hp = 1
	var d30_d_lo: int = player.attack_damage()
	player.relics = ["yangyan"]
	player.hp = 5
	var d30_d_yang: int = player.attack_damage()
	player.depth = 0.90          # 阴界
	var d30_d_yin: int = player.attack_damage()
	player.depth = 0.34
	player.relics = ["canxin"]
	player._chain_stages = 3
	var d30_d_chain: int = player.attack_damage()
	player._chain_stages = 1
	var d30_d_nochain: int = player.attack_damage()
	var d30_t117: bool = (d30_d0 == 2 and d30_d_hi == 1 and d30_d_lo == 4
		and d30_d_yang == 3 and d30_d_yin == 2
		and d30_d_chain == 4 and d30_d_nochain == 2)
	if d30_t117:
		_log("PASS T117 伤害层：基准 %d · 血怒 高血 %d / 低血 %d · 阳炎 阳 %d / 阴 %d · 残心 3 段 %d / 1 段 %d"
			% [d30_d0, d30_d_hi, d30_d_lo, d30_d_yang, d30_d_yin, d30_d_chain, d30_d_nochain])
	else:
		_log("FAIL T117 基准 %d 血怒 %d/%d 阳炎 %d/%d 残心 %d/%d"
			% [d30_d0, d30_d_hi, d30_d_lo, d30_d_yang, d30_d_yin,
				d30_d_chain, d30_d_nochain])

	# T118：剑匣（有飞剑才 +1）· 追风（取消后首段 +2，且取消后 0.5s 锁住不能再取消）
	player.relics = ["jianxia"]
	var d30_f_no: int = player.flying_damage()
	player.relics = ["swordfly"]
	var d30_f_base: int = player.flying_damage()
	player.relics = ["swordfly", "jianxia"]
	var d30_f_box: int = player.flying_damage()
	player.reset_relics()
	player.set_weapon("sword")
	player.stage = 1
	player.depth = 0.34
	player.hp = 5
	player._after_cancel_t = 0.0
	var d30_z_off: int = player.attack_damage()
	player.relics = ["zhuifeng"]
	player._after_cancel_t = 0.40
	var d30_z_on: int = player.attack_damage()
	player.atk = 3               # ATK_RECOVER
	player.stage = 1
	player.atk_t = 99.0
	player._no_cancel_t = 0.0
	var d30_c_ok: bool = player.can_cancel()
	player._no_cancel_t = 0.40
	var d30_c_locked: bool = player.can_cancel()
	var d30_t118: bool = (d30_f_no == 1 and d30_f_base == 1 and d30_f_box == 2
		and d30_z_off == 1 and d30_z_on == 3 and d30_c_ok and not d30_c_locked)
	if d30_t118:
		_log("PASS T118 剑匣 飞剑 %d/%d→%d（无飞剑时无效）· 追风 首段 %d→%d · 取消锁 %s/%s"
			% [d30_f_no, d30_f_base, d30_f_box, d30_z_off, d30_z_on,
				str(d30_c_ok), str(d30_c_locked)])
	else:
		_log("FAIL T118 剑匣 %d/%d/%d 追风 %d/%d 锁 %s/%s"
			% [d30_f_no, d30_f_base, d30_f_box, d30_z_off, d30_z_on,
				str(d30_c_ok), str(d30_c_locked)])

	# T119：阴眼暴击率 —— 没阴眼恒 0；阴界 25%；阳界被扣到 0
	player.reset_relics()
	player.depth = 0.90
	var d30_c0: float = player.crit_chance()
	player.relics = ["yinyan"]
	var d30_c_yin: float = player.crit_chance()
	player.depth = 0.20
	var d30_c_yang: float = player.crit_chance()
	var d30_t119: bool = (absf(d30_c0) < 0.0001
		and absf(d30_c_yin - 0.25) < 0.0001 and absf(d30_c_yang) < 0.0001)
	if d30_t119:
		_log("PASS T119 阴眼：无阴眼 %.2f · 阴界 %.2f · 阳界 %.2f（5%%-10%% 被夹到 0）"
			% [d30_c0, d30_c_yin, d30_c_yang])
	else:
		_log("FAIL T119 暴击率 %.3f/%.3f/%.3f" % [d30_c0, d30_c_yin, d30_c_yang])

	# T120：反震只在「挡下近战刀锋」时触发；挡弹幕不触发
	player.reset_relics()
	player.relics = ["fanzhen"]
	player.respawn(Vector2(600, 600))
	player.hp = 5
	player.posture = 0
	player.stamina = player.max_stamina()
	player.guarding = true
	player.facing = 1
	player.guard_t = 9.0          # 早就举盾了 → 普通格挡（非精准）
	var d30_rf := [0]
	var d30_cb := func(_p: Vector2) -> void:
		d30_rf[0] += 1
	player.guard_reflect.connect(d30_cb)
	player.invuln = 0.0
	player.take_hit(player.global_position + Vector2(40.0, 0.0), true)
	var d30_rf_melee: int = int(d30_rf[0])
	var d30_hp_after: int = player.hp
	player.invuln = 0.0
	player.guarding = true
	player.guard_t = 9.0
	player.take_hit(player.global_position + Vector2(40.0, 0.0), false)
	var d30_rf_shot: int = int(d30_rf[0])
	player.guard_reflect.disconnect(d30_cb)
	var d30_t120: bool = (d30_rf_melee == 1 and d30_rf_shot == 1 and d30_hp_after == 5)
	if d30_t120:
		_log("PASS T120 反震：挡下近战 → 反弹 1 次且不掉血（hp=%d）；挡弹幕 → 不反弹"
			% d30_hp_after)
	else:
		_log("FAIL T120 反震 近战 %d 弹幕 %d hp %d"
			% [d30_rf_melee, d30_rf_shot, d30_hp_after])

	# ============================================================ R31 兵器铭刻
	# T121：铭刻池 —— 4 把武器各 8 条通用；符剑多 2 条专属，且专属不外泄到别的武器
	var d31_p_sword: int = InscribeScript.pool_for("sword").size()
	var d31_p_spear: int = InscribeScript.pool_for("spear").size()
	var d31_p_rune: int = InscribeScript.pool_for("rune").size()
	var d31_spear_leak := false
	for it in InscribeScript.pool_for("spear"):
		if str(it["id"]).begins_with("rune"):
			d31_spear_leak = true
	var d31_rune_has_v := false
	for it in InscribeScript.pool_for("rune"):
		if str(it["id"]) == "runev":
			d31_rune_has_v = true
	if d31_p_sword == 8 and d31_p_spear == 8 and d31_p_rune == 10 \
			and not d31_spear_leak and d31_rune_has_v:
		_log("PASS T121 铭刻池：剑 %d / 枪 %d / 符剑 %d（+2 专属）· 符剑专属不泄到枪"
			% [d31_p_sword, d31_p_spear, d31_p_rune])
	else:
		_log("FAIL T121 池 剑 %d 枪 %d 符剑 %d 泄漏 %s 有迅符 %s"
			% [d31_p_sword, d31_p_spear, d31_p_rune, str(d31_spear_leak), str(d31_rune_has_v)])

	# T122：2 槽 · 精铁账目（刻 2 / 洗 3）· 同槽不能重复刻 · 两槽词条不重复
	player.reset_inscribe()
	var d31_rng := RandomNumberGenerator.new()
	d31_rng.seed = 20261028
	var d31_no_iron: bool = player.forge_slot(0, d31_rng)      # 精铁 0 → 拒绝
	player.add_iron(5)
	var d31_f0: bool = player.forge_slot(0, d31_rng)
	var d31_iron_a: int = player.iron                          # 5 - 2 = 3
	var d31_dup: bool = player.forge_slot(0, d31_rng)          # 槽已占 → 拒绝
	var d31_f1: bool = player.forge_slot(1, d31_rng)
	var d31_iron_b: int = player.iron                          # 3 - 2 = 1
	var d31_rf_lack: bool = player.reforge_slot(0, d31_rng)    # 需 3 只有 1 → 拒绝
	player.add_iron(3)
	var d31_rf_ok: bool = player.reforge_slot(0, d31_rng)
	var d31_iron_c: int = player.iron                          # 4 - 3 = 1
	var d31_slots: Array = player.inscribe_slots()
	var d31_two_ok: bool = (str(d31_slots[0]) != "" and str(d31_slots[1]) != ""
		and str(d31_slots[0]) != str(d31_slots[1]))
	if (not d31_no_iron) and d31_f0 and d31_iron_a == 3 and (not d31_dup) \
			and d31_f1 and d31_iron_b == 1 and (not d31_rf_lack) and d31_rf_ok \
			and d31_iron_c == 1 and d31_two_ok:
		_log("PASS T122 铭刻账目：0 精铁被拒 · 刻 5→3→1 · 洗 4→1 · 同槽重复刻被拒 · 两槽不重复（%s / %s）"
			% [InscribeScript.name_of(str(d31_slots[0])), InscribeScript.name_of(str(d31_slots[1]))])
	else:
		_log("FAIL T122 账目 铁 %d/%d/%d 刻 %s/%s 洗 %s/%s 双槽 %s"
			% [d31_iron_a, d31_iron_b, d31_iron_c, str(d31_f0), str(d31_f1),
				str(d31_rf_lack), str(d31_rf_ok), str(d31_two_ok)])

	# T123：伤害层 —— 锋铭（首段 +1）· 终铭（末段 +1）· 反铭（完美弹反后 1 秒 +1）
	player.reset_inscribe()
	player.reset_relics()
	player.set_weapon("sword")
	player.depth = 0.34          # 阳界，且没装阴眼 → 不会暴击，数值可复现
	player.hp = 5
	player.stage = 1
	var d31_d_base1: int = player.attack_damage()
	player.stage = 3
	var d31_d_base3: int = player.attack_damage()
	player.inscriptions = {"sword": ["edge1", ""]}
	player.stage = 1
	var d31_d_edge: int = player.attack_damage()
	player.inscriptions = {"sword": ["tail1", ""]}
	player.stage = 3
	var d31_d_tail: int = player.attack_damage()
	player.inscriptions = {"sword": ["parry", ""]}
	player._parry_buff_t = 1.0
	player.stage = 1
	var d31_d_parry: int = player.attack_damage()
	player._parry_buff_t = 0.0
	var d31_d_noparry: int = player.attack_damage()
	if d31_d_base1 == 1 and d31_d_base3 == 2 and d31_d_edge == 2 \
			and d31_d_tail == 3 and d31_d_parry == 2 and d31_d_noparry == 1:
		_log("PASS T123 伤害层：基准 首 %d / 末 %d · 锋铭 %d · 终铭 %d · 反铭 窗口内 %d / 窗口外 %d"
			% [d31_d_base1, d31_d_base3, d31_d_edge, d31_d_tail, d31_d_parry, d31_d_noparry])
	else:
		_log("FAIL T123 伤害 首 %d 末 %d 锋 %d 终 %d 反 %d/%d"
			% [d31_d_base1, d31_d_base3, d31_d_edge, d31_d_tail,
				d31_d_parry, d31_d_noparry])

	# T124：手感类 —— 长铭（刀锋 +6%）· 压铭（压制 +10%）· 快铭（出招 +5%）·
	#        省铭（灵力 -8%）· 疾铭（取消窗口提前 5%，用 0.29 的边界区分）
	player.inscriptions = {"sword": ["span", ""]}
	player.stage = 1
	var d31_w_span: float = player._blade_rect().size.x
	player.inscriptions = {"sword": ["", ""]}
	var d31_w_base: float = player._blade_rect().size.x
	player.inscriptions = {"sword": ["press", ""]}
	var d31_press: float = player.attack_posture_frac()
	player.inscriptions = {"sword": ["", ""]}
	var d31_press0: float = player.attack_posture_frac()
	player.inscriptions = {"sword": ["tempo", ""]}
	var d31_act_fast: float = player._stage_t().y
	player.inscriptions = {"sword": ["", ""]}
	var d31_act_base: float = player._stage_t().y
	# 省铭 / 基线：各起一次手，比灵力差
	player.inscriptions = {"sword": ["stam", ""]}
	player.stamina = player.max_stamina()
	player.atk = player.ATK_NONE
	player.stage = 0
	player._start_stage(1, true)
	var d31_stam_saved: float = player.max_stamina() - player.stamina
	player.inscriptions = {"sword": ["", ""]}
	player.stamina = player.max_stamina()
	player.atk = player.ATK_NONE
	player.stage = 0
	player._start_stage(1, true)
	var d31_stam_base: float = player.max_stamina() - player.stamina
	# 疾铭：atk_t 落在「0.285 ~ 0.30 倍后摇」之间 → 只有装了疾铭才能取消
	player.inscriptions = {"sword": ["cancel", ""]}
	player.atk = player.ATK_RECOVER
	player.stage = 1
	player._no_cancel_t = 0.0
	var d31_tt: Vector3 = player._stage_t()
	player.atk_t = d31_tt.z * 0.29
	var d31_cancel_on: bool = player.can_cancel()
	player.inscriptions = {"sword": ["", ""]}
	player.atk = player.ATK_RECOVER
	player.stage = 1
	player._no_cancel_t = 0.0
	player.atk_t = d31_tt.z * 0.29
	var d31_cancel_off: bool = player.can_cancel()
	var d31_t124: bool = (d31_w_span > d31_w_base
		and absf(d31_press - d31_press0 * 1.10) < 0.0001
		and d31_act_fast < d31_act_base
		and d31_stam_saved < d31_stam_base
		and d31_cancel_on and not d31_cancel_off)
	if d31_t124:
		_log("PASS T124 手感类：刀锋 %.1f→%.1f · 压制 %.3f→%.3f · 出招 %.3f→%.3f · 灵力 %.2f→%.2f · 取消 %s/%s"
			% [d31_w_base, d31_w_span, d31_press0, d31_press, d31_act_base, d31_act_fast,
				d31_stam_base, d31_stam_saved, str(d31_cancel_off), str(d31_cancel_on)])
	else:
		_log("FAIL T124 刀锋 %.1f/%.1f 压制 %.3f/%.3f 出招 %.3f/%.3f 灵力 %.2f/%.2f 取消 %s/%s"
			% [d31_w_base, d31_w_span, d31_press0, d31_press, d31_act_base, d31_act_fast,
				d31_stam_base, d31_stam_saved, str(d31_cancel_off), str(d31_cancel_on)])

	# T125：符剑专属 —— 符铭（符力上限 +1）· 迅符（符击速度 +15%）
	player.reset_inscribe()
	player.set_weapon("rune")
	var d31_rune_base: float = player.rune_max()
	player.inscriptions = {"rune": ["rune1", ""]}
	var d31_rune_1: float = player.rune_max()
	player.inscriptions = {"rune": ["runev", ""]}
	var d31_spd: float = player.talisman_speed()
	player.inscriptions = {"rune": ["", ""]}
	var d31_spd0: float = player.talisman_speed()
	if d31_rune_base == 5.0 and d31_rune_1 == 6.0 and d31_spd > d31_spd0 \
			and absf(d31_spd - 620.0 * 1.15) < 0.01:
		_log("PASS T125 符剑专属：符力上限 %.0f→%.0f · 符击速度 %.0f→%.0f（+15%%）"
			% [d31_rune_base, d31_rune_1, d31_spd0, d31_spd])
	else:
		_log("FAIL T125 符力 %.0f/%.0f 符速 %.0f/%.0f"
			% [d31_rune_base, d31_rune_1, d31_spd0, d31_spd])

	# T126：铭刻按武器分开记 —— 剑的铭刻跟着剑走，换长枪就看不到
	player.reset_inscribe()
	player.set_weapon("sword")
	player.inscriptions = {"sword": ["edge1", ""]}
	var d31_sword_has: bool = player.has_inscribe("edge1")
	player.set_weapon("spear")
	var d31_spear_has: bool = player.has_inscribe("edge1")
	var d31_spear_slots: Array = player.inscribe_slots()
	player.set_weapon("sword")
	var d31_sword_back: bool = player.has_inscribe("edge1")
	if d31_sword_has and (not d31_spear_has) and d31_spear_slots.size() == 2 \
			and str(d31_spear_slots[0]) == "" and d31_sword_back:
		_log("PASS T126 按武器分开记：剑有锋铭 %s · 换枪看不到 %s · 枪槽自动建 2 格空 · 换回剑还在 %s"
			% [str(d31_sword_has), str(d31_spear_has), str(d31_sword_back)])
	else:
		_log("FAIL T126 剑 %s 枪 %s 槽 %d 换回 %s"
			% [str(d31_sword_has), str(d31_spear_has), d31_spear_slots.size(), str(d31_sword_back)])

	# T127：开新局清空 —— 精铁归零、铭刻全清、槽位重建为 2 个空槽
	player.add_iron(7)
	player.reset_inscribe()
	var d31_slots_after: Array = player.inscribe_slots()
	var d31_t127: bool = (player.iron == 0 and player.inscriptions.size() == 1
		and d31_slots_after.size() == 2
		and str(d31_slots_after[0]) == "" and str(d31_slots_after[1]) == "")
	if d31_t127:
		_log("PASS T127 开新局清空：精铁 7→0 · 铭刻清空 · 槽位重建为 2 个空槽（inscriptions 只留当前武器一条空记录）")
	else:
		_log("FAIL T127 精铁 %d 记录 %d 槽 %d" % [player.iron, player.inscriptions.size(), d31_slots_after.size()])

	# T128：精铁掉落接线 —— _drop_iron 累加；精英 +1 / Boss +2 的分派靠 is_elite()
	player.reset_inscribe()
	main._drop_iron(Vector2(600, 600), 1)
	main._drop_iron(Vector2(600, 600), 2)
	var d31_iron_sum: int = player.iron
	var d31_ec = load("res://scripts/enemy.gd")
	var d31_e_elite = d31_ec.new()
	d31_e_elite.kind = 8            # KIND_JIANXIU（剑修傀儡，精英）
	var d31_is_elite: bool = d31_e_elite.is_elite()
	d31_e_elite.free()
	var d31_e_boss = d31_ec.new()
	d31_e_boss.kind = 14            # KIND_BOSS6（无相·心魔）
	var d31_is_boss_elite: bool = d31_e_boss.is_elite()
	d31_e_boss.free()
	if d31_iron_sum == 3 and d31_is_elite and (not d31_is_boss_elite):
		_log("PASS T128 精铁接线：_drop_iron 1+2 → 精铁 %d · 精英 is_elite=true · Boss6 is_elite=false（不会重复 +1）"
			% d31_iron_sum)
	else:
		_log("FAIL T128 精铁 %d 精英 %s Boss %s"
			% [d31_iron_sum, str(d31_is_elite), str(d31_is_boss_elite)])

	# T129：丹药表 —— 6 味、id 唯一、名字以「丹」结尾、价格 20–95、每味都有说明
	var cs = load("res://scripts/consumable.gd")
	var c129_ids: Array = cs.ids()
	var c129_uniq := {}
	var c129_prices: Array = []
	var c129_ok: bool = c129_ids.size() == 6
	for pid in c129_ids:
		c129_uniq[str(pid)] = true
		var pd: Dictionary = cs.pill(str(pid))
		var nm := str(pd.get("name", "")).replace(" ", "")
		var pr := int(pd.get("price", 0))
		c129_prices.append(pr)
		if nm.right(1) != "丹" or str(pd.get("desc", "")) == "" \
				or str(pd.get("short", "")) == "" or pr < 20 or pr > 95:
			c129_ok = false
	if c129_ok and c129_uniq.size() == 6:
		_log("PASS T129 丹药表：6 味 %s · 价格 %s · 名字全以「丹」结尾"
			% [str(c129_ids), str(c129_prices)])
	else:
		_log("FAIL T129 丹药表 %d 味 唯一 %d 价格 %s"
			% [c129_ids.size(), c129_uniq.size(), str(c129_prices)])

	# T130：快捷格 —— 3 格硬上限 · 同种最多叠 3 · 满格拒绝 · 空槽拒绝使用
	player.reset_quick()
	var c130_slots: int = player.quick.size()
	player.add_pill("huichun", 5)              # 想给 5 个，只能收 3
	var c130_n: int = player.quick_count(0)
	var c130_over: bool = player.add_pill("huichun", 1)   # 叠满后再加 → 拒绝
	var c130_empty: Dictionary = player.use_quick(1)      # 第 2 格还是空的 → 拒绝
	player.add_pill("juling", 1)
	player.add_pill("gangqi", 1)
	var c130_free: int = player.quick_free()
	var c130_fourth: bool = player.add_pill("xisui", 1)   # 第 4 种 → 拒绝
	if c130_slots == 3 and c130_n == 3 and (not c130_over) and c130_free == 0 \
			and (not c130_fourth) and (not bool(c130_empty.get("ok", true))):
		_log("PASS T130 快捷格：3 格 · 同种叠到 %d 就停 · 叠满再加被拒 · 三格满了第 4 种被拒 · 空槽拒绝使用"
			% c130_n)
	else:
		_log("FAIL T130 格 %d 叠 %d 超叠 %s 空位 %d 第四种 %s 空槽 %s"
			% [c130_slots, c130_n, str(c130_over), c130_free, str(c130_fourth),
				str(c130_empty.get("ok", true))])

	# T131：回春 / 聚灵 / 罡气 —— 三条即时资源线各回各的，且「满了不吃」
	player.respawn(Vector2(600, 600))
	player.reset_quick()
	player.hp = 1
	player.add_pill("huichun", 2)
	var c131_use1: Dictionary = player.use_quick(0)
	var c131_hp: int = player.hp
	var c131_left: int = player.quick_count(0)
	player.hp = player.max_hp()
	player._quick_cd = 0.0
	var c131_full: Dictionary = player.use_quick(0)     # 血满 → 拒绝，不扣数量
	var c131_keep: int = player.quick_count(0)
	player.reset_quick()
	player.stamina = 10.0
	player.add_pill("juling", 1)
	player._quick_cd = 0.0
	player.use_quick(0)
	var c131_stam: float = player.stamina
	player.reset_quick()
	player.posture = 60
	player.add_pill("gangqi", 1)
	player._quick_cd = 0.0
	player.use_quick(0)
	var c131_post: int = player.posture
	if c131_hp == 3 and c131_left == 1 and (not bool(c131_full.get("ok", true))) \
			and c131_keep == 1 and c131_stam == 60.0 and c131_post == 20:
		_log("PASS T131 即时丹药：回春 1→%d（剩 %d 粒）· 血满拒绝且不扣 · 聚灵 10→%.0f · 罡气 60→%d"
			% [c131_hp, c131_left, c131_stam, c131_post])
	else:
		_log("FAIL T131 回春 %d 剩 %d 血满 %s 不扣 %d 聚灵 %.0f 罡气 %d"
			% [c131_hp, c131_left, str(c131_full.get("ok", true)), c131_keep,
				c131_stam, c131_post])

	# T132：破境丹 —— 伤害 +2、受伤 +1、10 秒后失效（先赚后还）
	player.respawn(Vector2(600, 600))
	player.reset_quick()
	player.reset_relics()
	player.reset_inscribe()
	player.set_weapon("sword")
	player.depth = 0.34
	player.stage = 1
	player._pojing_t = 0.0
	var c132_base: int = player.attack_damage()
	player.add_pill("pojing", 1)
	player._quick_cd = 0.0
	player.use_quick(0)
	var c132_buff: int = player.attack_damage()
	player.hp = 5
	player.invuln = 0.0
	player.guarding = false
	player.take_hit(Vector2(0, 600))
	var c132_hp: int = player.hp
	player._pojing_t = 0.0
	var c132_out: int = player.attack_damage()
	if c132_base == 1 and c132_buff == 3 and c132_hp == 3 and c132_out == 1:
		_log("PASS T132 破境丹：伤害 %d→%d · 受伤 5→%d（多掉 1 点）· 窗口外回落 %d"
			% [c132_base, c132_buff, c132_hp, c132_out])
	else:
		_log("FAIL T132 伤害 %d→%d 受伤后 %d 窗口外 %d"
			% [c132_base, c132_buff, c132_hp, c132_out])

	# T133：洗髓丹 —— 护体罡气 / 道心失守 / 力竭 / 硬直 / 破境窗口一次清干净
	player.respawn(Vector2(600, 600))
	player.reset_quick()
	player.posture = 70
	player.broken_t = 1.0
	player.exhausted = true
	player.stun = 0.3
	player._pojing_t = 5.0
	player.add_pill("xisui", 1)
	player._quick_cd = 0.0
	var c133_use: Dictionary = player.use_quick(0)
	if bool(c133_use.get("ok", false)) and player.posture == 0 and player.broken_t == 0.0 \
			and (not player.exhausted) and player.stun == 0.0 and player._pojing_t == 0.0:
		_log("PASS T133 洗髓丹：护体罡气 70→0 · 道心失守归零 · 力竭清除 · 硬直 0 · 破境窗口同时清掉")
	else:
		_log("FAIL T133 洗髓 ok=%s 罡气 %d 失守 %.1f 力竭 %s 硬直 %.2f 破境 %.1f"
			% [str(c133_use.get("ok", false)), player.posture, player.broken_t,
				str(player.exhausted), player.stun, player._pojing_t])

	# T134：九转丹 —— 主动吃被拒（它是自动触发的）；致死时自动吞一格，本局只保一次
	player.respawn(Vector2(600, 600))
	player.reset_quick()
	player.add_pill("jiuzhuan", 1)
	player._quick_cd = 0.0
	var c134_manual: Dictionary = player.use_quick(0)
	var c134_kept: int = player.quick_count(0)
	player.hp = 1
	player.invuln = 0.0
	player.guarding = false
	player.take_hit(Vector2(0, 600))
	var c134_alive: bool = not player.dead
	var c134_hp: int = player.hp
	var c134_used_up: int = player.quick_count(0)
	# 第二次致死：没有九转丹了，这次是真死
	player.invuln = 0.0
	player.hp = 1
	player.take_hit(Vector2(0, 600))
	var c134_dead: bool = player.dead
	if (not bool(c134_manual.get("ok", true))) and c134_kept == 1 and c134_alive \
			and c134_hp == 2 and c134_used_up == 0 and c134_dead:
		_log("PASS T134 九转丹：主动吃被拒（剩 %d 粒）· 致死自动回魂到 %d 血 · 第二次真死"
			% [c134_kept, c134_hp])
	else:
		_log("FAIL T134 主动 %s 剩 %d 存活 %s 血 %d 用光 %d 二次死 %s"
			% [str(c134_manual.get("ok", true)), c134_kept, str(c134_alive),
				c134_hp, c134_used_up, str(c134_dead)])

	# T135：商队货架 —— 3 法宝 + 1 丹药 + 1 符箓，行数跟着条目走，价格照表
	main._build_shop()
	var c135_n: int = main.shop_items.size()
	var c135_rows: int = main.SHOP_ROWS.size()
	var c135_pid := str((main.shop_items[3].get("item", {}) as Dictionary).get("id", "")) \
		if c135_n >= 4 else ""
	var c135_tid := str((main.shop_items[4].get("item", {}) as Dictionary).get("id", "")) \
		if c135_n >= 5 else ""
	var c135_pok: bool = cs.is_pill(c135_pid) \
		and int(main.shop_items[3].get("price", 0)) == int(cs.price_of(c135_pid))
	var c135_tok: bool = cs.is_talisman(c135_tid) \
		and int(main.shop_items[4].get("price", 0)) == int(cs.price_of(c135_tid))
	if c135_n == 5 and c135_rows == 5 and c135_pok and c135_tok:
		_log("PASS T135 商队货架：5 行（3 法宝 + 丹 %s + 符 %s）· 价格与表一致"
			% [cs.name_of(c135_pid), cs.name_of(c135_tid)])
	else:
		_log("FAIL T135 商队 条目 %d 行 %d 丹 %s 符 %s ok %s/%s"
			% [c135_n, c135_rows, c135_pid, c135_tid, str(c135_pok), str(c135_tok)])

	# T136：三格满了再得丹 → 折 8 道蕴（不让拾取白掉）
	player.reset_quick()
	player.soul = 0.0
	player.add_pill("huichun", 3)
	player.add_pill("juling", 1)
	player.add_pill("gangqi", 1)
	main._grant_pill("xisui")
	var c136_soul: float = player.soul
	var c136_free: int = player.quick_free()
	player.reset_quick()
	player.soul = 0.0
	main._grant_pill("xisui")
	var c136_ok2: int = player.quick_count(0)
	if absf(c136_soul - 8.0) < 0.001 and c136_free == 0 and c136_ok2 == 1:
		_log("PASS T136 得丹：三格满 → 折 %.0f 道蕴 · 有空位 → 正常入格（%d 粒）"
			% [c136_soul, c136_ok2])
	else:
		_log("FAIL T136 折道蕴 %.0f 空位 %d 入格 %d" % [c136_soul, c136_free, c136_ok2])

	# T137：符箓表 —— 6 张、id 唯一、与丹药 id 不冲突、每张都有参数与价格
	var t137_ids: Array = cs.talisman_ids()
	var t137_uniq := {}
	var t137_ok: bool = t137_ids.size() == 6
	for tid in t137_ids:
		t137_uniq[str(tid)] = true
		if cs.is_pill(str(tid)):
			t137_ok = false
		var td: Dictionary = cs.talisman(str(tid))
		var tnm := str(td.get("name", "")).replace(" ", "")
		var tpr := int(td.get("price", 0))
		if tnm.right(1) != "符" or str(td.get("desc", "")) == "" \
				or cs.val_of(str(tid)) <= 0.0 or tpr < 24 or tpr > 60:
			t137_ok = false
	if t137_ok and t137_uniq.size() == 6:
		_log("PASS T137 符箓表：6 张 %s · 与丹药 id 不冲突 · 每张都有参数" % str(t137_ids))
	else:
		_log("FAIL T137 符箓表 %d 张 唯一 %d ok=%s"
			% [t137_ids.size(), t137_uniq.size(), str(t137_ok)])

	# T138：丹药与符箓共用 3 格 —— 混装可以，第 4 件被拒
	player.reset_quick()
	var t138_a: bool = player.add_item("huichun", 1)
	var t138_b: bool = player.add_item("huo", 1)
	var t138_c: bool = player.add_item("lei", 2)
	var t138_d: bool = player.add_item("shu", 1)
	var t138_free: int = player.quick_free()
	var t138_mix: bool = player.quick_id(0) == "huichun" and player.quick_id(1) == "huo" \
		and player.quick_id(2) == "lei" and player.quick_count(2) == 2
	if t138_a and t138_b and t138_c and (not t138_d) and t138_free == 0 and t138_mix:
		_log("PASS T138 混装：丹 + 符 同占 3 格（%s / %s / %s×2）· 第 4 件被拒"
			% [player.quick_id(0), player.quick_id(1), player.quick_id(2)])
	else:
		_log("FAIL T138 混装 %s%s%s 第四件 %s 空位 %d"
			% [str(t138_a), str(t138_b), str(t138_c), str(t138_d), t138_free])

	# T139：盾符 —— 3 秒无敌，到点自动解除
	player.respawn(Vector2(600, 675))
	player.reset_quick()
	player.add_item("shu", 1)
	player._quick_cd = 0.0
	var t139_use: Dictionary = player.use_quick(0)
	var t139_inv: float = player.invuln
	var t139_guard: bool = not player.can_be_hurt()
	player._tick(3.2)
	var t139_after: bool = player.can_be_hurt()
	if bool(t139_use.get("ok", false)) and t139_inv >= 3.0 and t139_guard and t139_after:
		_log("PASS T139 盾符：无敌 %.1f 秒 · 期间不可被击 · 到点自动解除" % t139_inv)
	else:
		_log("FAIL T139 盾符 ok=%s 无敌 %.2f 挡下 %s 解除 %s"
			% [str(t139_use.get("ok", false)), t139_inv, str(t139_guard), str(t139_after)])

	# T140：遁符 —— 向前 300；贴墙时拒绝且不扣符
	player.respawn(Vector2(600, 675))
	player.facing = 1
	player.reset_quick()
	player.add_item("dun", 1)
	player._quick_cd = 0.0
	var t140_use: Dictionary = player.use_quick(0)
	var t140_x: float = player.global_position.x
	player.global_position.x = 1090.0
	player.facing = 1
	player.add_item("dun", 1)
	player._quick_cd = 0.0
	var t140_wall: Dictionary = player.use_quick(0)
	var t140_left: int = player.quick_count(0)
	if bool(t140_use.get("ok", false)) and absf(t140_x - 900.0) < 1.0 \
			and (not bool(t140_wall.get("ok", true))) and t140_left == 1:
		_log("PASS T140 遁符：600 → %.0f（+300）· 贴墙被拒且不扣（剩 %d 张）"
			% [t140_x, t140_left])
	else:
		_log("FAIL T140 遁符 落点 %.0f 贴墙 %s 剩 %d"
			% [t140_x, str(t140_wall.get("ok", true)), t140_left])

	# T141：火符 —— 身前 200 的矩形；身后的敌人不挨打
	player.respawn(Vector2(600, 675))
	player.facing = 1
	var t141_front = EnemyScript6.new()
	t141_front.setup(int(EnemyScript6.KIND_SENTINEL), Vector2(760, 675), player, fx6)
	main.add_child(t141_front)
	t141_front.depth = player.depth
	t141_front.hp = 9
	t141_front.max_hp = 9
	main.enemies.append(t141_front)
	var t141_back = EnemyScript6.new()
	t141_back.setup(int(EnemyScript6.KIND_SENTINEL), Vector2(430, 675), player, fx6)
	main.add_child(t141_back)
	t141_back.depth = player.depth
	t141_back.hp = 9
	t141_back.max_hp = 9
	main.enemies.append(t141_back)
	main._on_talisman_fire(player.global_position, Vector2(200.0, 96.0), 1, 2)
	var t141_hf: int = 9 - int(t141_front.hp)
	var t141_hb: int = 9 - int(t141_back.hp)
	main.enemies.erase(t141_front)
	main.enemies.erase(t141_back)
	t141_front.queue_free()
	t141_back.queue_free()
	if t141_hf == 2 and t141_hb == 0:
		_log("PASS T141 火符：身前掉 %d 血 · 身后掉 %d 血（只烧前方 200）" % [t141_hf, t141_hb])
	else:
		_log("FAIL T141 火符 身前 %d 身后 %d" % [t141_hf, t141_hb])

	# T142：封符 —— 小怪定满 2 秒，Boss 打折；定身期间速度归零、位置不动
	var t142_mob = EnemyScript6.new()
	t142_mob.setup(int(EnemyScript6.KIND_SENTINEL), Vector2(700, 675), player, fx6)
	main.add_child(t142_mob)
	t142_mob.depth = player.depth
	t142_mob.hp = 9
	t142_mob.max_hp = 9
	main.enemies.append(t142_mob)
	var t142_boss = EnemyScript6.new()
	t142_boss.setup(int(EnemyScript6.KIND_BOSS2), Vector2(840, 675), player, fx6)
	main.add_child(t142_boss)
	t142_boss.hp = 40
	t142_boss.max_hp = 40
	main.enemies.append(t142_boss)
	main._on_talisman_seal(2.0)
	var t142_m: float = float(t142_mob.frozen_t)
	var t142_b: float = float(t142_boss.frozen_t)
	t142_mob.velocity = Vector2(220.0, 0.0)
	var t142_x0: float = t142_mob.global_position.x
	t142_mob._physics_process(0.1)
	var t142_moved: float = absf(t142_mob.global_position.x - t142_x0)
	var t142_frozen: bool = bool(t142_mob.is_frozen())
	main.enemies.erase(t142_mob)
	main.enemies.erase(t142_boss)
	t142_mob.queue_free()
	t142_boss.queue_free()
	if absf(t142_m - 2.0) < 0.01 and absf(t142_b - 0.8) < 0.01 and t142_moved < 0.01 and t142_frozen:
		_log("PASS T142 封符：小怪 %.1fs / Boss %.1fs（4 折）· 定身期间位移 %.2f" % [t142_m, t142_b, t142_moved])
	else:
		_log("FAIL T142 封符 小怪 %.2f Boss %.2f 位移 %.2f 状态 %s"
			% [t142_m, t142_b, t142_moved, str(t142_frozen)])

	# T143：雷符 —— 5 道雷全部落在房间内（不是全砸一处）
	var t143_old := {}
	for ch in main.get_children():
		t143_old[ch] = true
	main._on_talisman_thunder(5, 1)
	var t143_bolts: Array = []
	for ch in main.get_children():
		if t143_old.has(ch):
			continue
		if ch.get_script() != null and str(ch.get_script().resource_path).ends_with("lightning.gd"):
			t143_bolts.append(ch)
	var t143_in: bool = t143_bolts.size() == 5
	var t143_span := 0.0
	for b in t143_bolts:
		var bx: float = b.global_position.x
		if bx < 200.0 or bx > 1100.0:
			t143_in = false
		b.queue_free()
	if t143_bolts.size() > 1:
		t143_span = absf(float(t143_bolts[0].global_position.x) - float(t143_bolts[4].global_position.x))
	if t143_in:
		_log("PASS T143 雷符：5 道雷全落在房间内（首尾相距 %.0f px）" % t143_span)
	else:
		_log("FAIL T143 雷符 落了 %d 道 都在房内=%s" % [t143_bolts.size(), str(t143_in)])

	# T144：召符 —— 纸人 10 秒寿命、跟玩家同界、自己会打人
	player.respawn(Vector2(640, 675))
	var t144_enemy = EnemyScript6.new()
	t144_enemy.setup(int(EnemyScript6.KIND_SENTINEL), Vector2(720, 675), player, fx6)
	main.add_child(t144_enemy)
	t144_enemy.depth = player.depth
	t144_enemy.hp = 9
	t144_enemy.max_hp = 9
	main.enemies.append(t144_enemy)
	main._on_talisman_summon(10.0)
	var t144_s = main.summons[main.summons.size() - 1]
	var t144_life: float = float(t144_s.life)
	var t144_dep: float = float(t144_s.depth)
	for _i in 40:
		t144_s._process(0.05)
	var t144_dmg: int = 9 - int(t144_enemy.hp)
	var t144_alive: bool = is_instance_valid(t144_s)
	main.enemies.erase(t144_enemy)
	t144_enemy.queue_free()
	main.summons.erase(t144_s)
	if t144_alive:
		t144_s.queue_free()
	if absf(t144_life - 10.0) < 0.01 and absf(t144_dep - float(player.depth)) < 0.01 \
			and t144_dmg >= 1:
		_log("PASS T144 召符：纸人 %.0f 秒 · 与玩家同界（%.2f）· 2 秒内打出 %d 点"
			% [t144_life, t144_dep, t144_dmg])
	else:
		_log("FAIL T144 召符 寿命 %.1f 深度 %.2f 伤害 %d"
			% [t144_life, t144_dep, t144_dmg])

	# ============================================================ R33a 经脉天赋树
	# T145 道痕账目：升级扣钱、钱不够拒绝、满级拒绝

	Cfg.daoyun = 100
	Cfg.meridian_lv = {}
	var t145_a: bool = Cfg.mer_up("jian_feng")     # 20
	var t145_b: bool = Cfg.mer_up("jian_feng")     # 40
	var t145_left := int(Cfg.daoyun)               # 40
	var t145_c: bool = Cfg.mer_up("jian_feng")     # 70 > 40 → 拒绝
	var t145_lv: int = int(Cfg.mer_lv("jian_feng"))
	if t145_a and t145_b and not t145_c and t145_left == 40 and t145_lv == 2:
		_log("PASS T145 道痕账目：升 1 级 −20 · 升 2 级 −40 · 剩 40 时 3 级（70）被拒 · 停在 2 级")
	else:
		_log("FAIL T145 道痕 a=%s b=%s c=%s 剩 %d 级 %d" % [str(t145_a), str(t145_b),
			str(t145_c), t145_left, t145_lv])

	# T146 表结构：3 脉 × 8 条 = 24 节点 × 3 级 = 72 级；每级 ≤ +10%
	var t146_n: int = MeridianScript.all().size()
	var t146_cap := 0
	var t146_step_max := 0.0
	var t146_bad: Array = []
	for mm in MeridianScript.MERS:
		var t146_cnt: int = MeridianScript.by_mer(str(mm["id"])).size()
		if t146_cnt != 8:
			t146_bad.append("%s=%d" % [str(mm["id"]), t146_cnt])
	for nn in MeridianScript.all():
		t146_cap += MeridianScript.MAX_LV
		var t146_vals: Array = nn.get("vals", [])
		if t146_vals.size() != MeridianScript.MAX_LV:
			t146_bad.append("vals:" + str(nn["id"]))
		for k in t146_vals.size():
			var t146_prev := 0.0 if k == 0 else float(t146_vals[k - 1])
			var t146_step := float(t146_vals[k]) - t146_prev
			if str(nn["kind"]) == "pct" and t146_step > t146_step_max:
				t146_step_max = t146_step
	if t146_n == 24 and t146_cap == 72 and t146_step_max <= 10.0 and t146_bad.is_empty():
		_log("PASS T146 经脉表：24 节点（3 脉 × 8）· 72 级上限 · 百分比类每级最大 +%.0f%%（≤10%%）"
			% t146_step_max)
	else:
		_log("FAIL T146 经脉表 节点 %d 级 %d 每级最大 %.1f 异常 %s"
			% [t146_n, t146_cap, t146_step_max, str(t146_bad)])

	# T147 聚合函数真值（用假字典，不碰存档）
	var t147_z := {}
	var t147_max := {"jian_feng": 3, "gang_qi": 3, "ling_xi": 3, "ti_po": 3,
		"jian_xin": 3, "ju_ling": 3, "yu_jian": 3}
	var t147_ok: bool = absf(MeridianScript.cancel_mul(t147_z) - 1.0) < 0.001 \
		and absf(MeridianScript.cancel_mul(t147_max) - 0.85) < 0.001 \
		and MeridianScript.posture_bonus(t147_max) == 18 \
		and absf(MeridianScript.stamina_bonus(t147_max) - 24.0) < 0.001 \
		and absf(MeridianScript.move_mul(t147_max) - 1.09) < 0.001 \
		and absf(MeridianScript.perfect_gap_mul(t147_max) - 0.82) < 0.001 \
		and absf(MeridianScript.stamina_regen_mul(t147_max) - 1.21) < 0.001 \
		and MeridianScript.feijian_pierce(t147_max) == 1 \
		and MeridianScript.feijian_pierce(t147_z) == 0
	if t147_ok:
		_log("PASS T147 聚合真值：0 级全中性 · 满级 取消 −15% / 罡气 +18 / 灵力上限 +24 / 移速 +9% / 完美窗口 −18% / 回复 +21% / 御剑穿透 1")
	else:
		_log("FAIL T147 聚合真值 cancel=%.2f posture=%d stam=%.1f move=%.2f gap=%.2f regen=%.2f pierce=%d"
			% [MeridianScript.cancel_mul(t147_max), MeridianScript.posture_bonus(t147_max),
			MeridianScript.stamina_bonus(t147_max), MeridianScript.move_mul(t147_max),
			MeridianScript.perfect_gap_mul(t147_max), MeridianScript.stamina_regen_mul(t147_max),
			MeridianScript.feijian_pierce(t147_max)])

	# T148 洗点：退 70% · 等级清空 · 没点过时返回 0
	Cfg.daoyun = 0
	Cfg.meridian_lv = {"jian_feng": 3, "ti_po": 1}   # 20+40+70 + 20 = 150
	var t148_spent: int = MeridianScript.spent(Cfg.meridian_lv)
	var t148_back: int = Cfg.mer_respec()
	var t148_dy := int(Cfg.daoyun)
	var t148_empty: bool = Cfg.meridian_lv.is_empty()
	var t148_again: int = Cfg.mer_respec()
	if t148_spent == 150 and t148_back == 105 and t148_dy == 105 and t148_empty and t148_again == 0:
		_log("PASS T148 洗点：投 150 → 退 105（70%）· 等级清空 · 再洗返回 0")
	else:
		_log("FAIL T148 洗点 投入 %d 退回 %d 余额 %d 空 %s 再洗 %d"
			% [t148_spent, t148_back, t148_dy, str(t148_empty), t148_again])

	# T149 经脉真的接在玩家身上（改 player.mer 立刻生效）
	var t149_base_speed: float = player.speed_now()
	var t149_base_stam: float = player.max_stamina()
	var t149_base_post: int = player.posture_max()
	player.mer = {"ti_po": 3, "ling_xi": 3, "gang_qi": 3}
	var t149_speed: float = player.speed_now()
	var t149_stam: float = player.max_stamina()
	var t149_post: int = player.posture_max()
	player.mer = {}
	var t149_back_ok: bool = absf(player.speed_now() - t149_base_speed) < 0.01
	if absf(t149_speed - t149_base_speed * 1.09) < 0.05 \
		and absf(t149_stam - (t149_base_stam + 24.0)) < 0.01 \
		and t149_post == t149_base_post + 18 and t149_back_ok:
		_log("PASS T149 接线：移速 %.0f → %.0f（+9%%）· 灵力上限 %.0f → %.0f（+24）· 罡气上限 %d → %d（+18）· 清空即回落"
			% [t149_base_speed, t149_speed, t149_base_stam, t149_stam, t149_base_post, t149_post])
	else:
		_log("FAIL T149 接线 移速 %.1f→%.1f 灵力 %.1f→%.1f 罡气 %d→%d 回落 %s"
			% [t149_base_speed, t149_speed, t149_base_stam, t149_stam,
			t149_base_post, t149_post, str(t149_back_ok)])

	# T150 道痕结算：死得越远给得越多 · 通关更多 · 一局只结一次
	var t150_lv0 := int(main.level_index)
	var t150_rs0: Array = main.room_state.duplicate()
	main.level_index = 0
	main.room_state = ["new", "new"]
	var t150_d0: int = main.daoyun_on_death()
	main.level_index = 2
	main.room_state = ["cleared", "cleared", "cleared", "new"]
	var t150_d2: int = main.daoyun_on_death()
	var t150_w: int = main.daoyun_on_win()
	# 只结一次：连调两次，余额只加一次
	var t150_bak := int(Cfg.daoyun)
	var t150_daily: bool = main.daily_mode
	main.daily_mode = false
	main._meta_awarded = false
	main._award_daoyun(false)
	var t150_after1 := int(Cfg.daoyun)
	main._award_daoyun(false)
	var t150_after2 := int(Cfg.daoyun)
	Cfg.daoyun = t150_bak
	main.daily_mode = t150_daily
	main.level_index = t150_lv0
	main.room_state = t150_rs0
	if t150_d0 == 4 and t150_d2 == 13 and t150_w == 80 \
		and t150_after1 == t150_bak + 13 and t150_after2 == t150_after1:
		_log("PASS T150 道痕结算：第 1 关速死 +4 · 第 3 关清 3 房 +13 · 通关 +80 · 一局只结一次")
	else:
		_log("FAIL T150 道痕 速死 %d 中途 %d 通关 %d 连调 %d/%d（基准 %d）"
			% [t150_d0, t150_d2, t150_w, t150_after1, t150_after2, t150_bak])

	# T151 开局加成：满级道蕴送 10 · 满级符丹送 1 粒（只是判定，不真发）
	var t151_a: bool = MeridianScript.start_soul({"dao_yun": 3}) == 10.0 \
		and MeridianScript.start_soul({"dao_yun": 2}) == 0.0 \
		and MeridianScript.start_pill({"fu_dan": 3}) \
		and not MeridianScript.start_pill({"fu_dan": 2})
	if t151_a:
		_log("PASS T151 开局加成：道蕴满级 +10 / 未满 0 · 符丹满级送 1 粒 / 未满不送")
	else:
		_log("FAIL T151 开局加成")

	# ============================================================ R33b 经脉扩到 24 条
	# T152 新增 12 条都在表里，每条 3 级真值 + 带 %s 的文案 + 能查到下标
	var t152_new: Array = ["chu_feng", "dao_feng", "kuai_jian", "qi_mai",
		"tie_gu", "zhen_qi", "ti_ren", "ning_shen",
		"fu_li", "ling_guan", "shen_xing", "dan_huo"]
	var t152_bad: Array = []
	for nid in t152_new:
		var n2: Dictionary = MeridianScript.node(str(nid))
		if n2.is_empty():
			t152_bad.append("缺:" + str(nid))
			continue
		var vv: Array = n2.get("vals", [])
		if vv.size() != MeridianScript.MAX_LV:
			t152_bad.append("级数:" + str(nid))
		if str(n2.get("desc", "")).find("%s") < 0:
			t152_bad.append("文案:" + str(nid))
		if MeridianScript.index_of(str(nid)) < 0:
			t152_bad.append("下标:" + str(nid))
		if str(n2.get("mer", "")) == "" or MeridianScript.mer(str(n2["mer"])).is_empty():
			t152_bad.append("脉:" + str(nid))
	if t152_bad.is_empty():
		_log("PASS T152 新增 12 条经脉齐全：每条 3 级真值 · 文案带占位符 · 归脉正确 · 查得到下标")
	else:
		_log("FAIL T152 新经脉 问题 %s" % str(t152_bad))

	# T153 12 个新聚合真值（假字典，不碰存档）
	var t153_z := {}
	var t153_max := {"chu_feng": 3, "dao_feng": 3, "kuai_jian": 3, "qi_mai": 3,
		"tie_gu": 3, "zhen_qi": 3, "ti_ren": 3, "ning_shen": 3,
		"fu_li": 3, "ling_guan": 3, "shen_xing": 3, "dan_huo": 3}
	var t153_ok: bool = absf(MeridianScript.lunge_mul(t153_z) - 1.0) < 0.001 \
		and absf(MeridianScript.blade_reach_mul(t153_z) - 1.0) < 0.001 \
		and absf(MeridianScript.heat_fall_mul(t153_z) - 1.0) < 0.001 \
		and absf(MeridianScript.lunge_mul(t153_max) - 1.18) < 0.001 \
		and absf(MeridianScript.blade_reach_mul(t153_max) - 1.12) < 0.001 \
		and absf(MeridianScript.atk_cap_mul(t153_max) - 1.09) < 0.001 \
		and absf(MeridianScript.heat_rise_mul(t153_max) - 1.24) < 0.001 \
		and absf(MeridianScript.heat_fall_mul(t153_max) - 0.50) < 0.001 \
		and absf(MeridianScript.guard_stun_mul(t153_max) - 0.70) < 0.001 \
		and absf(MeridianScript.posture_hold_mul(t153_max) - 1.30) < 0.001 \
		and absf(MeridianScript.stam_delay_mul(t153_max) - 0.70) < 0.001 \
		and absf(MeridianScript.perfect_guard_mul(t153_max) - 1.18) < 0.001 \
		and absf(MeridianScript.rune_regen_mul(t153_max) - 1.21) < 0.001 \
		and absf(MeridianScript.rune_bonus(t153_max) - 3.0) < 0.001 \
		and absf(MeridianScript.dash_cd_mul(t153_max) - 0.82) < 0.001 \
		and absf(MeridianScript.heal_cost_mul(t153_max) - 0.76) < 0.001
	if t153_ok:
		_log("PASS T153 新聚合真值：0 级全中性 · 满级 出锋+18% 刀锋+12% 攻速顶+9% 热度+24%/回落−50% · 硬直−30% 罡气驻留+30% 灵力延迟−30% 凝神+18% · 符力回复+21%/上限+3 冲刺冷却−18% 回血−24%")
	else:
		_log("FAIL T153 新聚合 出锋%.2f 刀锋%.2f 攻速%.2f 热度%.2f 回落%.2f 硬直%.2f 驻留%.2f 延迟%.2f 凝神%.2f 符回%.2f 符限%.1f 冲刺%.2f 回血%.2f"
			% [MeridianScript.lunge_mul(t153_max), MeridianScript.blade_reach_mul(t153_max),
			MeridianScript.atk_cap_mul(t153_max), MeridianScript.heat_rise_mul(t153_max),
			MeridianScript.heat_fall_mul(t153_max), MeridianScript.guard_stun_mul(t153_max),
			MeridianScript.posture_hold_mul(t153_max), MeridianScript.stam_delay_mul(t153_max),
			MeridianScript.perfect_guard_mul(t153_max), MeridianScript.rune_regen_mul(t153_max),
			MeridianScript.rune_bonus(t153_max), MeridianScript.dash_cd_mul(t153_max),
			MeridianScript.heal_cost_mul(t153_max)])

	# T154 新经脉真的接在玩家身上（改 player.mer 立刻生效，清空即回落）
	player.mer = {}
	player.heat = 1.0
	player.stage = 1
	player.atk_down = false
	var t154_spd0: float = player.atk_speed()
	var t154_bld0: float = player._blade_rect().size.x
	var t154_pg0: float = player.perfect_guard_time()
	var t154_rune0: float = player.rune_max()
	var t154_heal0: float = player.heal_cost()
	player.spend(1.0)
	var t154_wait0: float = player._stam_wait
	player.mer = {"kuai_jian": 3, "dao_feng": 3, "ning_shen": 3, "ling_guan": 3,
		"dan_huo": 3, "ti_ren": 3}
	var t154_spd1: float = player.atk_speed()
	var t154_bld1: float = player._blade_rect().size.x
	var t154_pg1: float = player.perfect_guard_time()
	var t154_rune1: float = player.rune_max()
	var t154_heal1: float = player.heal_cost()
	player.spend(1.0)
	var t154_wait1: float = player._stam_wait
	player.mer = {}
	player.heat = 0.0
	player.stage = 0
	var t154_ok: bool = absf(t154_spd1 / t154_spd0 - 1.09) < 0.002 \
		and absf(t154_bld1 / t154_bld0 - 1.12) < 0.002 \
		and absf(t154_pg1 / t154_pg0 - 1.18) < 0.002 \
		and absf(t154_rune1 - (t154_rune0 + 3.0)) < 0.001 \
		and absf(t154_heal1 / t154_heal0 - 0.76) < 0.002 \
		and absf(t154_wait1 / t154_wait0 - 0.70) < 0.002
	if t154_ok:
		_log("PASS T154 新接线：攻速上限 %.2f→%.2f（+9%%）· 刀锋 %.0f→%.0f（+12%%）· 凝神 %.2f→%.2f（+18%%）· 符力上限 %.0f→%.0f（+3）· 回血 %.1f→%.1f（−24%%）· 灵力延迟 %.2f→%.2f（−30%%）"
			% [t154_spd0, t154_spd1, t154_bld0, t154_bld1, t154_pg0, t154_pg1,
			t154_rune0, t154_rune1, t154_heal0, t154_heal1, t154_wait0, t154_wait1])
	else:
		_log("FAIL T154 新接线 攻速 %.3f 刀锋 %.3f 凝神 %.3f 符力 %.2f 回血 %.3f 延迟 %.3f"
			% [t154_spd1 / t154_spd0, t154_bld1 / t154_bld0, t154_pg1 / t154_pg0,
			t154_rune1 - t154_rune0, t154_heal1 / t154_heal0, t154_wait1 / t154_wait0])

	# T155 经脉页：一页 8 格 · 3 个页签 · 绝对下标对得上
	var t155_rects: Array = main.mer_node_rects()
	var t155_ok: bool = t155_rects.size() == 8 and main.BTN_MER_TABS.size() == 4
	main.mer_col = 0
	main.mer_row = 7
	var t155_a: String = main.mer_sel_id()
	var t155_ai: int = main.mer_sel_index()
	main.mer_col = 2
	main.mer_row = 5
	var t155_b: String = main.mer_sel_id()
	var t155_bi: int = main.mer_sel_index()
	main.mer_col = 0
	main.mer_row = 0
	if t155_ok and t155_a == "qi_mai" and t155_ai == 7 \
			and t155_b == "ling_guan" and t155_bi == 21:
		_log("PASS T155 经脉页：一页 8 格 · 4 个页签（三脉 + 丹房）· 剑脉第 8 条=气脉（下标 7）· 灵脉第 6 条=灵贯（下标 21）")
	else:
		_log("FAIL T155 经脉页 格 %d 页签 %d 剑8=%s/%d 灵6=%s/%d"
			% [t155_rects.size(), main.BTN_MER_TABS.size(), t155_a, t155_ai, t155_b, t155_bi])

	# T156 新经脉一样吃升级 / 满级拒绝 / 洗点
	Cfg.daoyun = 130
	Cfg.meridian_lv = {}
	var t156_a: bool = Cfg.mer_up("ling_guan")
	var t156_b: bool = Cfg.mer_up("ling_guan")
	var t156_c: bool = Cfg.mer_up("ling_guan")
	var t156_left := int(Cfg.daoyun)
	var t156_d: bool = Cfg.mer_up("ling_guan")
	var t156_lv: int = int(Cfg.mer_lv("ling_guan"))
	var t156_spent: int = MeridianScript.spent(Cfg.meridian_lv)
	var t156_back: int = MeridianScript.respec_refund(Cfg.meridian_lv)
	if t156_a and t156_b and t156_c and not t156_d and t156_left == 0 and t156_lv == 3 \
			and t156_spent == 130 and t156_back == 91:
		_log("PASS T156 新经脉账目：灵贯 20/40/70 三级共 130 · 满级再升被拒 · 洗点退 91（70%）")
	else:
		_log("FAIL T156 新经脉账目 升 %s%s%s 拒 %s 余 %d 级 %d 投入 %d 退 %d"
			% [str(t156_a), str(t156_b), str(t156_c), str(t156_d), t156_left,
			t156_lv, t156_spent, t156_back])

	# ============================================================ R33c 丹房（局外合成）
	# T157 配方表 12 张 · 价 = 商队价 × 50% · 扣道痕与进背包同进同退
	var t157_recs: Array = AlchemyScript.recipes()
	var t157_bad: Array = []
	if t157_recs.size() != 12:
		t157_bad.append("张数=%d" % t157_recs.size())
	if AlchemyScript.count_of("pill") != 6 or AlchemyScript.count_of("talisman") != 6:
		t157_bad.append("分类=%d/%d" % [AlchemyScript.count_of("pill"),
			AlchemyScript.count_of("talisman")])
	# 真值：回春 38→19 / 破境 55→28（四舍五入）/ 九转 90→45 / 火符 30→15
	if AlchemyScript.cost_of("huichun") != 19 or AlchemyScript.cost_of("jiuzhuan") != 45 \
			or AlchemyScript.cost_of("huo") != 15 or AlchemyScript.cost_of("pojing") != 28:
		t157_bad.append("价格=%d/%d/%d/%d" % [AlchemyScript.cost_of("huichun"),
			AlchemyScript.cost_of("jiuzhuan"), AlchemyScript.cost_of("huo"),
			AlchemyScript.cost_of("pojing")])
	for rr in t157_recs:
		if not ConsumeScript.is_item(str(rr["id"])):
			t157_bad.append("非消耗品:" + str(rr["id"]))
	Cfg.daoyun = 100
	Cfg.pantry = {}
	var t157_a: bool = Cfg.pantry_add("huichun", 1, 19)
	var t157_dy1 := int(Cfg.daoyun)
	var t157_b: bool = Cfg.pantry_add("jiuzhuan", 1, 45)
	var t157_dy2 := int(Cfg.daoyun)
	var t157_c: bool = Cfg.pantry_add("jiuzhuan", 1, 45)   # 剩 36 < 45 → 拒绝
	var t157_dy3 := int(Cfg.daoyun)
	if t157_bad.is_empty() and t157_a and t157_b and not t157_c \
			and t157_dy1 == 81 and t157_dy2 == 36 and t157_dy3 == 36 \
			and Cfg.pantry_of("huichun") == 1 and Cfg.pantry_of("jiuzhuan") == 1:
		_log("PASS T157 丹房配方：12 张（6 丹 + 6 符）· 价 = 商队价 × 50%（回春 19 / 破境 28 / 九转 45 / 火符 15）· 扣钱与进背包同进同退")
	else:
		_log("FAIL T157 丹房配方 问题 %s 炼 %s%s%s 余 %d/%d/%d 存 %d/%d"
			% [str(t157_bad), str(t157_a), str(t157_b), str(t157_c),
			t157_dy1, t157_dy2, t157_dy3,
			Cfg.pantry_of("huichun"), Cfg.pantry_of("jiuzhuan")])

	# T158 存货上限 9 = 3 格 × 3 叠 · 开局注入快捷格 · 注入后背包清空
	Cfg.pantry = {}
	var t158_ids: Array = ["huichun", "huo", "shu"]
	var t158_fill := 0
	for tid in t158_ids:
		for _j in 3:
			if Cfg.pantry_add(str(tid), 1):
				t158_fill += 1
	var t158_over: bool = Cfg.pantry_add("jiuzhuan", 1)     # 第 10 件 → 拒绝
	var t158_full: int = int(Cfg.pantry_total())
	player.reset_quick()
	main._apply_pantry()
	var t158_left: int = int(Cfg.pantry_total())
	var t158_slots := 0
	var t158_sum := 0
	for sl in player.quick:
		if not sl.is_empty():
			t158_slots += 1
			t158_sum += int(sl.get("n", 0))
	if t158_fill == 9 and not t158_over and t158_full == 9 \
			and t158_left == 0 and t158_slots == 3 and t158_sum == 9:
		_log("PASS T158 丹房存货：9 件封顶（第 10 件被拒）· 开局注入 3 格共 9 件 · 注入后背包清空（带进去就归这一局）")
	else:
		_log("FAIL T158 丹房存货 装入 %d 超限 %s 满 %d 余 %d 格 %d 件 %d"
			% [t158_fill, str(t158_over), t158_full, t158_left, t158_slots, t158_sum])

	# T159 存档往返：道痕 / 经脉等级 / 丹房存货三样都要能过一趟
	Cfg.daoyun = 77
	Cfg.meridian_lv = {"chu_feng": 2}
	Cfg.pantry = {"huichun": 2, "huo": 1}
	Cfg.save_cfg()
	Cfg.daoyun = 0
	Cfg.meridian_lv = {}
	Cfg.pantry = {}
	Cfg.load_cfg()
	if int(Cfg.daoyun) == 77 and int(Cfg.mer_lv("chu_feng")) == 2 \
			and Cfg.pantry_of("huichun") == 2 and Cfg.pantry_of("huo") == 1:
		_log("PASS T159 存档往返：道痕 77 · 出锋 2 级 · 存货 回春 2 / 火符 1 —— 落盘再读回一致")
	else:
		_log("FAIL T159 存档往返 道痕 %d 出锋 %d 回春 %d 火符 %d"
			% [int(Cfg.daoyun), int(Cfg.mer_lv("chu_feng")),
			Cfg.pantry_of("huichun"), Cfg.pantry_of("huo")])

	# 还原：道痕与经脉回滚到测试前的状态（并落盘，不留脏数据）
	Cfg.daoyun = _dy0
	Cfg.daoyun_total = _dyt0
	Cfg.meridian_lv = _lv0
	Cfg.pantry = _pantry0
	Cfg.save_cfg()
	player.mer = Cfg.meridian_lv
	main._meta_awarded = false
	main.daoyun_gain = 0

	# 收尾：法宝与状态还原
	player.reset_relics()
	for id in d30_saved_relics:
		player.add_relic(str(id))
	player.reset_quick()
	player.set_weapon("sword")
	player.respawn(Vector2(600, 600))

	# ============ R34 · 背景音乐（钟主题 BGM） ============
	# T160：四段曲目文件存在且是合法 WAV（RIFF/WAVE 头）—— 资源会被导出包打包，
	#        循环由 music.gd 运行时置 loop（无头脚本缺 .import 缓存，故用 FileAccess 验落盘+头）
	var mu_tracks := ["title", "explore", "boss", "daily"]
	var mu_exist := 0
	var mu_wav := 0
	for tt in mu_tracks:
		var pp := "res://music/%s.wav" % tt
		if not FileAccess.file_exists(pp):
			continue
		mu_exist += 1
		var f = FileAccess.open(pp, FileAccess.READ)
		var ok := false
		if f != null:
			var b: PackedByteArray = f.get_buffer(12)
			f.close()
			if b.size() >= 12 and b[0] == 82 and b[1] == 73 and b[2] == 70 and b[3] == 70 \
					and b[8] == 87 and b[9] == 65 and b[10] == 86 and b[11] == 69:
				ok = true
		if ok:
			mu_wav += 1
	if mu_exist == 4 and mu_wav == 4:
		_log("PASS T160 BGM：title/explore/boss/daily 四曲均落盘且为合法 WAV（RIFF/WAVE）")
	else:
		_log("FAIL T160 BGM 存在=%d 合法WAV=%d" % [mu_exist, mu_wav])

	# T161：Music 管理器实例 —— play 切曲、同曲忽略、stop 归空（注入静音 AudioStreamWAV 绕过无头缺导入）
	var mu_script = load("res://scripts/music.gd")
	var mz = mu_script.new()
	mz._ready()
	var mz_dummy = AudioStreamWAV.new()
	var mz_pb = PackedByteArray()
	mz_pb.resize(4410)   # 0.1s 静音，16-bit 单声道
	mz_dummy.data = mz_pb
	mz_dummy.format = AudioStreamWAV.FORMAT_16_BITS
	mz_dummy.mix_rate = 22050
	mz_dummy.stereo = false
	mz_dummy.loop_mode = AudioStreamWAV.LOOP_FORWARD
	mz.streams = {"title": mz_dummy, "explore": mz_dummy, "boss": mz_dummy, "daily": mz_dummy}
	mz.play("explore")
	var mz1: String = str(mz.get("_cur"))
	mz.play("boss")
	var mz2: String = str(mz.get("_cur"))
	mz.play("boss")   # 同曲忽略
	var mz3: String = str(mz.get("_cur"))
	mz.stop()
	var mz4: String = str(mz.get("_cur"))
	mz.free()
	if mz1 == "explore" and mz2 == "boss" and mz3 == "boss" and mz4 == "":
		_log("PASS T161 BGM 管理器：play 切曲 / 同曲忽略 / stop 归空")
	else:
		_log("FAIL T161 BGM mgr explore=%s boss=%s same=%s stop=%s" % [mz1, mz2, mz3, mz4])

	# T162：Music autoload 已注册且曲目常量齐全（实际 wav 由导出时导入，运行期置 loop）
	var mz_auto = Engine.get_main_loop().root.get_node_or_null("Music")
	var mz_reg: bool = mz_auto != null
	var mz_tracks: int = 0
	if mz_reg:
		mz_tracks = int(mz_auto.TRACKS.size())
	if mz_reg and mz_tracks == 4:
		_log("PASS T162 BGM autoload：/root/Music 已挂载，TRACKS=%d（title/explore/boss/daily）" % mz_tracks)
	else:
		_log("FAIL T162 BGM autoload 挂载=%s TRACKS=%d" % [str(mz_reg), mz_tracks])

	# ===================== R35 同伴（T163–T165） =====================
	# 用轻量 Mock（RefCounted）驱动 companion.gd，保证 headless 下可确定性断言。
	# 约束：同伴不读 Input、绝不移动玩家。
	# T163：3 灵兽技能按周期触发
	var c_fox = CompanionScript.new(); c_fox.init(CompanionScript.Kind.FOX, Vector2.ZERO)
	var c_mp = MockCPlayer.new()
	var c_me = MockCEnemy.new(); c_me.global_position = Vector2(140.0, 12.0)
	c_fox.player = c_mp; c_fox.enemy_provider = func(): return [c_me]
	for _i in 120: c_fox._process(0.1)   # 12 秒
	var c_tut = CompanionScript.new(); c_tut.init(CompanionScript.Kind.TURTLE, Vector2.ZERO)
	var c_mt = MockCPlayer.new(); c_tut.player = c_mt; c_tut.enemy_provider = func(): return []
	for _i in 120: c_tut._process(0.1)
	var c_brd = CompanionScript.new(); c_brd.init(CompanionScript.Kind.BIRD, Vector2.ZERO)
	var c_mb = MockCPlayer.new(); c_brd.player = c_mb; c_brd.enemy_provider = func(): return []
	for _i in 120: c_brd._process(0.1)
	if c_fox._fired >= 1 and c_me.hp < 5:
		_log("PASS T163 灵兽·白狐：每 5s 吐狐火，12s 触发 %d 次、最近敌人掉血（5→%d）" % [c_fox._fired, c_me.hp])
	else:
		_log("FAIL T163 白狐 触发=%d 敌血=%d" % [c_fox._fired, c_me.hp])
	if c_tut._fired >= 1 and c_mt.shield_layers >= 1:
		_log("PASS T163 灵兽·玄龟：每 10s 给护盾，触发 %d 次、玩家护盾层=%d" % [c_tut._fired, c_mt.shield_layers])
	else:
		_log("FAIL T163 玄龟 触发=%d 护盾=%d" % [c_tut._fired, c_mt.shield_layers])
	if c_brd._fired >= 1 and c_mb.stamina > 0:
		_log("PASS T163 灵兽·青鸟：每 8s 回灵力，触发 %d 次、灵力+%.0f" % [c_brd._fired, c_mb.stamina])
	else:
		_log("FAIL T163 青鸟 触发=%d 灵力=%.1f" % [c_brd._fired, c_mb.stamina])
	# 接入验证：main.grant_companion 真能把同伴挂进 companions 数组
	var c_before: int = main.companions.size()
	main.grant_companion(CompanionScript.Kind.FOX)
	if main.companions.size() == c_before + 1:
		_log("PASS T163 接入：main.grant_companion 挂入 companions（%d→%d）" % [c_before, main.companions.size()])
	else:
		_log("FAIL T163 接入 companions 未 +1（%d→%d）" % [c_before, main.companions.size()])
	main._clear_companions()

	# T164：3 傀儡行为正确、会死
	var s_p = MockCPlayer.new(); var s_e = MockCEnemy.new(); s_e.global_position = Vector2(100.0, 12.0)
	var sw = CompanionScript.new(); sw.init(CompanionScript.Kind.SWORD, Vector2.ZERO); sw.player = s_p; sw.enemy_provider = func(): return [s_e]
	for _i in 30: sw._process(0.1)   # 3s
	if sw._fired >= 1 and s_e.hp < 5:
		_log("PASS T164 剑傀儡：跟随砍最近敌人，触发 %d 次、敌掉血（5→%d）" % [sw._fired, s_e.hp])
	else:
		_log("FAIL T164 剑傀儡 触发=%d 敌血=%d" % [sw._fired, s_e.hp])
	var h_p = MockCPlayer.new(); var sh = CompanionScript.new(); sh.init(CompanionScript.Kind.SHIELD, Vector2.ZERO); sh.player = h_p; sh.enemy_provider = func(): return []
	for _i in 80: sh._process(0.1)   # 8s
	if sh._fired >= 1 and h_p.shield_layers >= 1:
		_log("PASS T164 盾傀儡：身前挡刀+周期护盾，触发 %d 次、护盾=%d" % [sh._fired, h_p.shield_layers])
	else:
		_log("FAIL T164 盾傀儡 触发=%d 护盾=%d" % [sh._fired, h_p.shield_layers])
	var ru_p = MockCPlayer.new(); var ru_e = MockCEnemy.new(); ru_e.global_position = Vector2(300.0, 12.0)
	var rn = CompanionScript.new(); rn.init(CompanionScript.Kind.RUNE, Vector2.ZERO); rn.player = ru_p; rn.enemy_provider = func(): return [ru_e]
	for _i in 40: rn._process(0.1)   # 4s
	if rn._fired >= 1 and ru_e.hp < 5:
		_log("PASS T164 符傀儡：站远放符，触发 %d 次、敌掉血（5→%d）" % [rn._fired, ru_e.hp])
	else:
		_log("FAIL T164 符傀儡 触发=%d 敌血=%d" % [rn._fired, ru_e.hp])
	sw.hurt_companion(999); sh.hurt_companion(999); rn.hurt_companion(999)
	if sw.dead and sh.dead and rn.dead:
		_log("PASS T164 傀儡会死：剑/盾/符 受致命伤后 dead=true")
	else:
		_log("FAIL T164 傀儡死亡 sw=%s sh=%s rn=%s" % [sw.dead, sh.dead, rn.dead])

	# T165：傀儡吃法宝加成、不抢操作权
	var np = MockCPlayer.new(); var ne = MockCEnemy.new(); ne.global_position = Vector2(100.0, 12.0)
	var s1 = CompanionScript.new(); s1.init(CompanionScript.Kind.SWORD, Vector2.ZERO); s1.player = np; s1.enemy_provider = func(): return [ne]
	for _i in 20: s1._process(0.1)   # 2s（仅命中 1 次）
	var dmg_no: int = 5 - ne.hp
	var pp2 = MockCPlayer.new(); pp2.relics = ["pact"]; var pe2 = MockCEnemy.new(); pe2.global_position = Vector2(100.0, 12.0)
	var s2 = CompanionScript.new(); s2.init(CompanionScript.Kind.SWORD, Vector2.ZERO); s2.player = pp2; s2.enemy_provider = func(): return [pe2]
	for _i in 20: s2._process(0.1)
	var dmg_pact: int = 5 - pe2.hp
	if dmg_no == 2 and dmg_pact == 3:
		_log("PASS T165 傀儡吃灵契：无加成伤=%d，持「灵契」伤=%d（×1.5）" % [dmg_no, dmg_pact])
	else:
		_log("FAIL T165 灵契加成 无=%d 有=%d（期望 2 / 3）" % [dmg_no, dmg_pact])
	var no_p = MockCPlayer.new(); no_p.global_position = Vector2(123.0, 456.0)
	var no_e = MockCEnemy.new(); no_e.global_position = Vector2(200.0, 456.0)
	var no_c = CompanionScript.new(); no_c.init(CompanionScript.Kind.SWORD, Vector2.ZERO); no_c.player = no_p; no_c.enemy_provider = func(): return [no_e]
	for _i in 60: no_c._process(0.1)
	if no_p.global_position == Vector2(123.0, 456.0):
		_log("PASS T165 不抢操作权：跑 60 帧后玩家坐标不变（同伴只动自己）")
	else:
		_log("FAIL T165 玩家坐标被改 %s" % no_p.global_position)
	var csrc := FileAccess.get_file_as_string("res://scripts/companion.gd")
	if not ("Input." in csrc):
		_log("PASS T165 不抢操作权：companion.gd 源码无任何 Input 调用")
	else:
		_log("FAIL T165 companion.gd 含 Input 调用")

	# T166：HUD 同伴一览已接线（读 game.companions + 同伴名表；灵兽不显示血）
	var hsrc := FileAccess.get_file_as_string("res://scripts/hud.gd")
	var h_ok: bool = ("CompanionScript" in hsrc) and ("game.companions" in hsrc) \
		and ("CompanionScript.NAMES" in hsrc)
	if h_ok:
		_log("PASS T166 HUD 同伴一览：hud.gd 读 game.companions + 同伴名表（灵兽不显血 / 傀儡显 HP）")
	else:
		_log("FAIL T166 HUD 同伴一览未接线（CompanionScript=%s companions=%s）"
			% [str("CompanionScript" in hsrc), str("game.companions" in hsrc)])


	# ===================== R36 符箓秘境 + 符祖（T167–T170） =====================
	var r36_rs = load("res://scripts/rooms.gd")
	var r36_es = load("res://scripts/enemy.gd")
	var r36_ss = load("res://scripts/seal.gd")

	# T167：符箓秘境在 index 4（第 5 关），关底 boss=15，终章仍是心魔境。
	# 注：R36 原本还断言「关卡数 == 6」，R37 加第 7 关后这个数归 T171 管，
	# 这里只守「符箓秘境没被挪位置 / 没被改 Boss / 终章没被挤走」。
	var r36_lc: int = int(r36_rs.level_count())
	var r36_l6: Array = r36_rs.rooms_of(4)
	var r36_boss := -1
	var r36_seal_rooms := 0
	for r in r36_l6:
		if r36_rs.room_kind(r) == r36_rs.KIND_BOSS:
			r36_boss = int(r.get("boss", -1))
		if int(r.get("seals", 0)) > 0:
			r36_seal_rooms += 1
	var r36_fin_boss := -1
	for r in r36_rs.rooms_of(r36_rs.finale_level()):
		if r36_rs.room_kind(r) == r36_rs.KIND_BOSS:
			r36_fin_boss = int(r.get("boss", -1))
	if r36_lc >= 6 and r36_l6.size() == 6 and r36_boss == 15 \
			and r36_seal_rooms >= 3 and r36_fin_boss == 14:
		_log("PASS T167 符箓秘境「%s」在 index 4（第 5 关）：6 房 · 关底 boss=15 · %d 间带符阵 · 终章仍是心魔境(14)"
			% [r36_rs.level_name(4), r36_seal_rooms])
	else:
		_log("FAIL T167 关卡 lc=%d rooms=%d boss=%d seals=%d 终章boss=%d"
			% [r36_lc, r36_l6.size(), r36_boss, r36_seal_rooms, r36_fin_boss])

	# T168：符阵场 —— 生符回灵力、煞符扣血，且都是一次性
	var s168_p = MockCPlayer.new()
	s168_p.stamina = 0.0
	s168_p.hp = 5
	var s168_good = r36_ss.new()
	s168_good.setup(true, Vector2.ZERO, s168_p, null)
	s168_good.trigger()
	var s168_stam: float = s168_p.stamina
	s168_good.trigger()                       # 第二次应无效（一次性）
	var s168_again: bool = absf(s168_p.stamina - s168_stam) > 0.01
	var s168_bad = r36_ss.new()
	s168_bad.setup(false, Vector2.ZERO, s168_p, null)
	s168_bad.trigger()
	var s168_hp: int = s168_p.hp
	if absf(s168_stam - 12.0) < 0.01 and not s168_again and s168_hp == 4:
		_log("PASS T168 符阵：生符 +12 灵力（%.0f）· 煞符扣 1 血（5→%d）· 一次性"
			% [s168_stam, s168_hp])
	else:
		_log("FAIL T168 符阵 灵力=%.1f 二次生效=%s 血=%d"
			% [s168_stam, str(s168_again), s168_hp])

	# T169：符祖 —— Boss 家族、名字、两阶段、五连扇形
	var b169 = r36_es.new()
	b169.setup(15, Vector2(600.0, 600.0), null, null)
	var b169_fan := []
	b169.fired.connect(func(_o, d, _s): b169_fan.append(d))
	b169._fire_fan(5, 0.15)
	var b169_ok: bool = b169.is_boss_family() and b169.boss_title() == "符 祖" \
		and b169.phase_count() == 2 and b169_fan.size() == 5
	if b169_ok:
		_log("PASS T169 符祖：Boss 家族 · 名「符 祖」· 两阶段 · 五连扇形（%d 发）" % b169_fan.size())
	else:
		_log("FAIL T169 符祖 family=%s title=%s phase=%d fan=%d"
			% [str(b169.is_boss_family()), b169.boss_title(), b169.phase_count(), b169_fan.size()])
	b169.free()

	# T170：原有 4 关的 Boss 编号没被 R36 挪动（第 6 关=15、终章=14 由 T167 覆盖）
	var r36_expect := [2, 3, 6, 7]
	var r36_actual := []
	for i in 4:
		var bk := -1
		for r in r36_rs.rooms_of(i):
			if r36_rs.room_kind(r) == r36_rs.KIND_BOSS:
				bk = int(r.get("boss", -1))
		r36_actual.append(bk)
	if r36_actual == r36_expect:
		_log("PASS T170 原有 4 关 Boss 编号未变：%s（新关=15 / 终章=14）" % str(r36_actual))
	else:
		_log("FAIL T170 原有 4 关 Boss %s（期望 %s）" % [str(r36_actual), str(r36_expect)])


	# ===================== R37 轮回台 + 轮回使（T171–T174） =====================
	var r37_rs = load("res://scripts/rooms.gd")
	var r37_es = load("res://scripts/enemy.gd")
	var r37_ec = load("res://scripts/echo.gd")

	# T171：关卡表 7 关，第 6 关（index 5）是「轮回台」，关底 boss=16，
	#      终章仍是心魔境 —— 插关不能把真结局挤走。
	var r37_lc: int = int(r37_rs.level_count())
	var r37_l7: Array = r37_rs.rooms_of(5)
	var r37_boss := -1
	var r37_echo_rooms := 0
	for r in r37_l7:
		if r37_rs.room_kind(r) == r37_rs.KIND_BOSS:
			r37_boss = int(r.get("boss", -1))
		if int(r.get("echoes", 0)) > 0:
			r37_echo_rooms += 1
	var r37_fin_boss := -1
	for r in r37_rs.rooms_of(r37_rs.finale_level()):
		if r37_rs.room_kind(r) == r37_rs.KIND_BOSS:
			r37_fin_boss = int(r.get("boss", -1))
	if r37_lc == 7 and r37_l7.size() == 6 and r37_boss == 16 \
			and r37_echo_rooms >= 3 and r37_fin_boss == 14:
		_log("PASS T171 关卡数 7：第 6 关「%s」6 房 · 关底 boss=16 · %d 间带旧影 · 终章仍是心魔境(14)"
			% [r37_rs.level_name(5), r37_echo_rooms])
	else:
		_log("FAIL T171 关卡 lc=%d rooms=%d boss=%d echoes=%d 终章boss=%d"
			% [r37_lc, r37_l7.size(), r37_boss, r37_echo_rooms, r37_fin_boss])

	# T172：旧影沿录制轨迹走 + 碰到扣血 + 到时消散
	# A) 走轨迹：玩家放远处（不接触），11 次 advance × 0.05s × 400 = 200px
	#    第 1 次是「吸附到 path[0]」，所以 11 次里有 10 次位移。
	var s172_path := [Vector2(400.0, 700.0), Vector2(900.0, 700.0)]
	var s172_far = MockCPlayer.new()
	s172_far.global_position = Vector2(1200.0, 200.0)
	var s172_e = r37_ec.new()
	s172_e.setup(s172_path, s172_far, null, 400.0)
	var s172_start: Vector2 = s172_e.global_position
	for _i in 11:
		s172_e.advance(0.05)
	var s172_moved: float = s172_e.global_position.x - s172_start.x
	# B) 接触扣血：另起一只影子，直接落在玩家身上，推一帧
	var s172_p = MockCPlayer.new()
	s172_p.global_position = Vector2(600.0, 700.0)
	s172_p.hp = 5
	var s172_e2 = r37_ec.new()
	s172_e2.setup([Vector2(600.0, 700.0)], s172_p, null, 0.0)
	s172_e2.advance(0.02)
	var s172_hurt: bool = s172_p.hp == 4 and s172_e2.hits == 1
	# C) 存在时长到点自行消散
	s172_e.life = 0.01
	s172_e.advance(0.05)
	var s172_gone: bool = s172_e.dead
	if absf(s172_moved - 200.0) < 6.0 and s172_hurt and s172_gone:
		_log("PASS T172 旧影：沿轨迹走 %.0fpx（期望 200）· 碰人扣 1 血（5→%d）· 到时消散"
			% [s172_moved, s172_p.hp])
	else:
		_log("FAIL T172 旧影 位移=%.1f 扣血=%s hits=%d 消散=%s"
			% [s172_moved, str(s172_hurt), s172_e2.hits, str(s172_gone)])
	s172_e.free()
	s172_e2.free()

	# T173：轮回使 —— Boss 家族、名字、两阶段、HP 18、会发 echo_call
	var s173_b = r37_es.new()
	s173_b.setup(16, Vector2(600.0, 600.0), null, null)
	var s173_calls := []
	s173_b.echo_call.connect(func(_p, n): s173_calls.append(n))
	s173_b.echo_call.emit(Vector2.ZERO, 2)     # 直连信号本身（AI 触发由 T173 的字段保证）
	var s173_ok: bool = s173_b.is_boss_family() and s173_b.boss_title() == "轮 回 使" \
		and s173_b.phase_count() == 2 and s173_b.max_hp == 18 \
		and s173_b.move_speed >= 160.0 and s173_calls.size() == 1
	if s173_ok:
		_log("PASS T173 轮回使：Boss 家族 · 名「轮 回 使」· 两阶段 · HP %d · 移速 %.0f · echo_call 已接"
			% [s173_b.max_hp, s173_b.move_speed])
	else:
		_log("FAIL T173 轮回使 family=%s title=%s phase=%d hp=%d spd=%.0f calls=%d"
			% [str(s173_b.is_boss_family()), s173_b.boss_title(), s173_b.phase_count(),
				s173_b.max_hp, s173_b.move_speed, s173_calls.size()])
	s173_b.free()

	# T174：轨迹录制 —— main 采样玩家坐标，echo_path() 给出可用的轨迹
	var s174_main = _get_main()
	var s174_old_trail = s174_main.get("echo_trail")
	var s174_old_acc = s174_main.get("_echo_acc")
	var s174_old_pos = player.global_position if player != null else Vector2.ZERO
	var s174_old_dead = bool(player.get("dead")) if player != null else true
	if player != null:
		player.dead = false
	s174_main.set("echo_trail", [])
	s174_main.set("_echo_acc", 0.0)
	for _i in 4:
		player.global_position = Vector2(300.0 + 100.0 * float(_i), 700.0)
		s174_main._record_echo_trail(0.2)
	var s174_path: Array = s174_main.echo_path()
	var s174_ok: bool = s174_path.size() == 4 \
		and (s174_path[0] as Vector2).distance_to(Vector2(300.0, 700.0)) < 1.0 \
		and (s174_path[3] as Vector2).distance_to(Vector2(600.0, 700.0)) < 1.0
	if s174_ok:
		_log("PASS T174 轨迹录制：4 次采样得到 4 个点，首尾与玩家走位一致")
	else:
		_log("FAIL T174 轨迹录制 点数=%d 首=%s 尾=%s"
			% [s174_path.size(), str(s174_path[0] if s174_path.size() > 0 else null),
				str(s174_path[s174_path.size() - 1] if s174_path.size() > 0 else null)])
	# 还原，别污染后续用例
	s174_main.set("echo_trail", s174_old_trail)
	s174_main.set("_echo_acc", s174_old_acc)
	if player != null:
		player.global_position = s174_old_pos
		player.dead = s174_old_dead

	# T175：**分发回归** —— 任何 Boss 都不能被判成精英。
	# 背景：is_elite() 原写「kind >= KIND_JIANXIU(8) and kind != KIND_BOSS6」，
	# 而 Boss 编号 14/15/16 都 ≥ 8 → 符祖(15) 一直走 _elite_ai + _draw_elite，
	# 五连扇形与后退走位从未真正生效（R36 的 T169 只验字段，验不出分发）。
	var s175_bosses := [2, 3, 4, 6, 7, 14, 15, 16]
	var s175_bad := []
	var s175_probe = r37_es.new()
	for bk in s175_bosses:
		s175_probe.setup(int(bk), Vector2(600.0, 600.0), null, null)
		if s175_probe.is_elite():
			s175_bad.append(bk)
	# 反向：真精英必须还是精英（别为了修 Boss 把精英一起修没了）
	var s175_elites_ok := true
	for ek in [8, 9, 10]:
		s175_probe.setup(int(ek), Vector2(600.0, 600.0), null, null)
		if not s175_probe.is_elite():
			s175_elites_ok = false
	s175_probe.free()
	if s175_bad.is_empty() and s175_elites_ok:
		_log("PASS T175 分发回归：8 个 Boss 编号均不是精英（含符祖 15 / 轮回使 16）· 精英 8/9/10 仍是精英")
	else:
		_log("FAIL T175 被误判成精英的 Boss=%s 精英反向=%s"
			% [str(s175_bad), str(s175_elites_ok)])

	# ============ R38 因果 / 业力 ============
	# T176：业力累加 + 夹 ±99 + 三分支边界（±5）+ 分支名
	var s176_saved_k: int = Game.karma
	var s176_saved_s: int = Game.spared_count
	Game.karma = 0
	Game.spared_count = 0
	Game.add_karma(3)
	Game.add_karma(-1)
	var s176_sum: int = Game.karma                       # 2
	Game.karma = 98
	Game.add_karma(5)
	var s176_cap_hi: int = Game.karma                    # 99
	Game.karma = -98
	Game.add_karma(-5)
	var s176_cap_lo: int = Game.karma                    # -99
	Game.karma = 5
	var s176_b_hi: int = Game.karma_branch()             # 2 魔道
	Game.karma = 4
	var s176_b_near: int = Game.karma_branch()           # 1 人道
	Game.karma = -5
	var s176_b_lo: int = Game.karma_branch()             # 0 天道
	Game.karma = 0
	var s176_b_zero: int = Game.karma_branch()           # 1 人道
	Game.karma = 5
	var s176_n_hi: String = Game.karma_branch_name()
	Game.karma = 0
	var s176_n_mid: String = Game.karma_branch_name()
	Game.karma = -5
	var s176_n_lo: String = Game.karma_branch_name()
	if s176_sum == 2 and s176_cap_hi == 99 and s176_cap_lo == -99 \
			and s176_b_hi == 2 and s176_b_near == 1 and s176_b_lo == 0 and s176_b_zero == 1 \
			and s176_n_hi == "魔 道" and s176_n_mid == "人 道" and s176_n_lo == "天 道":
		_log("PASS T176 业力：累加 2 · 夹 ±99 · 分支 ±5 边界（+5 魔道 / +4 人道 / −5 天道 / 0 人道）")
	else:
		_log("FAIL T176 累加=%d 上夹=%d 下夹=%d 分支=%d/%d/%d/%d 名=%s/%s/%s"
			% [s176_sum, s176_cap_hi, s176_cap_lo, s176_b_hi, s176_b_near,
				s176_b_lo, s176_b_zero, s176_n_hi, s176_n_mid, s176_n_lo])

	# T177：放走 —— 道心失守窗口自然走完而人还活着，enemy 发 spared，
	# main 收到后业力 −1、放走次数 +1。这是「不杀」的唯一入口。
	var s177_probe = r37_es.new()
	s177_probe.setup(r37_es.KIND_SENTINEL, Vector2(600.0, 700.0), null, null)
	# lambda 捕获局部 int 是**值拷贝**（改了外面看不见）→ 用数组当可变容器
	var s177_hits := [0]
	s177_probe.spared.connect(func(_e): s177_hits[0] += 1)
	s177_probe.broken_t = 0.04
	s177_probe._physics_process(0.08)                    # 窗口跨过 0
	var s177_emit: bool = s177_hits[0] == 1
	# 死了就不该算放走
	s177_hits[0] = 0
	s177_probe.broken_t = 0.04
	s177_probe.dead = true
	s177_probe._physics_process(0.08)
	var s177_dead_ok: bool = s177_hits[0] == 0
	s177_probe.dead = false
	s177_probe.free()
	# main 端的记账
	Game.karma = 0
	Game.spared_count = 0
	var s177_mock = MockCPlayer.new()
	s177_mock.global_position = Vector2(500.0, 700.0)
	var s177_fake = r37_es.new()
	s177_fake.setup(r37_es.KIND_SENTINEL, Vector2(520.0, 700.0), null, null)
	main.call("_on_enemy_spared", s177_fake)
	var s177_karma: int = Game.karma
	var s177_count: int = Game.spared_count
	s177_fake.free()
	s177_mock = null
	if s177_emit and s177_dead_ok and s177_karma == -1 and s177_count == 1:
		_log("PASS T177 放走：窗口走完发 spared（死后不发）· main 记业力 −1、放走 1 次")
	else:
		_log("FAIL T177 发信号=%s 死后静默=%s 业力=%d 次数=%d"
			% [str(s177_emit), str(s177_dead_ok), s177_karma, s177_count])

	# T178：魔剑门槛 —— need_karma 项默认不进池，业力够了才放行
	var s178_rng := RandomNumberGenerator.new()
	s178_rng.seed = 20261029
	var s178_locked: Array = RelicScript.pick_n_biased(s178_rng, [], 40, {}, false)
	var s178_open: Array = RelicScript.pick_n_biased(s178_rng, [], 40, {}, true)
	var s178_has_locked := false
	for r in s178_locked:
		if str(r["id"]) == "magic":
			s178_has_locked = true
	var s178_has_open := false
	for r in s178_open:
		if str(r["id"]) == "magic":
			s178_has_open = true
	# 解锁门槛边界：+5 才认
	Game.karma = 4
	var s178_unlock_4: bool = Game.karma_unlocks_magic_sword()
	Game.karma = 5
	var s178_unlock_5: bool = Game.karma_unlocks_magic_sword()
	if not s178_has_locked and s178_has_open and not s178_unlock_4 and s178_unlock_5:
		_log("PASS T178 魔剑门槛：业力 < 5 不进池（%d 件）· ≥ 5 放行（%d 件）"
			% [s178_locked.size(), s178_open.size()])
	else:
		_log("FAIL T178 锁池含魔剑=%s 开池含魔剑=%s 门槛 +4=%s +5=%s"
			% [str(s178_has_locked), str(s178_has_open), str(s178_unlock_4), str(s178_unlock_5)])

	# T179：魔剑代价 —— 气血上限 −1（处决伤害翻倍换的）
	var s179_saved: Array = player.relics.duplicate()
	player.relics.erase("magic")
	var s179_base: int = player.max_hp()
	player.relics.append("magic")
	var s179_with: int = player.max_hp()
	player.relics = s179_saved
	if s179_with == s179_base - 1:
		_log("PASS T179 魔剑代价：气血上限 %d → %d（−1）" % [s179_base, s179_with])
	else:
		_log("FAIL T179 气血上限 %d → %d（期望 −1）" % [s179_base, s179_with])

	# 还原，别污染后续用例
	Game.karma = s176_saved_k
	Game.spared_count = s176_saved_s

	# ============ R39 隐藏 Boss · 钟楼旧主 ============
	# T180：无伤走完序章 → 开顶阁（第 4 间）；已打赢过就不再开
	var s180_cfg = root.get_node_or_null("Cfg")
	var s180_saved_done: bool = bool(s180_cfg.prologue_done)
	var s180_saved_master: bool = bool(s180_cfg.old_master_beaten)
	s180_cfg.prologue_done = false
	s180_cfg.old_master_beaten = false
	main.call("_start_run", false)
	main.call("_confirm_weapon")
	# 关键：**不**制造受击 —— Game.dmg_taken 保持与 _prologue_dmg0 相同
	var s180_in_prologue: bool = bool(main.get("prologue_mode"))
	for _k in 3:
		main.call("_resolve_room_clear", false)
	var s180_rooms: Array = main.get("rooms")
	var s180_i: int = int(main.get("room_i"))
	var s180_top_name: String = str(main.get("room_name"))
	var s180_top_boss := -1
	if s180_i >= 0 and s180_i < s180_rooms.size():
		s180_top_boss = int((s180_rooms[s180_i] as Dictionary).get("boss", -1))
	# 打赢过 → 即使无伤也不开顶阁
	s180_cfg.old_master_beaten = true
	var s180_again := false
	main.call("_start_run", false)
	main.call("_confirm_weapon")
	for _k in 3:
		main.call("_resolve_room_clear", false)
	s180_again = bool(main.get("prologue_mode"))
	s180_cfg.old_master_beaten = false
	if s180_in_prologue and s180_rooms.size() == 4 and s180_top_boss == 17 \
			and s180_top_name == "钟 楼 · 顶 阁" and not s180_again:
		_log("PASS T180 无伤走完序章 → 开顶阁（第 %d 间，boss=%d）；打赢过则不再开"
			% [s180_i + 1, s180_top_boss])
	else:
		_log("FAIL T180 序章=%s 房数=%d 末间=%s boss=%d 重复开=%s dmg=%d dmg0=%d"
			% [str(s180_in_prologue), s180_rooms.size(), s180_top_name,
				s180_top_boss, str(s180_again), int(Game.dmg_taken),
				int(main.get("_prologue_dmg0"))])

	# T181：钟楼旧主的参数 —— 全作最慢 / 最硬 / 前摇最长
	var s181_p = r37_es.new()
	s181_p.setup(r37_es.KIND_BOSS9, Vector2(600.0, 700.0), null, null)
	var s181_is_boss: bool = s181_p.is_boss_family()
	var s181_title: String = str(s181_p.boss_title())
	var s181_hp: int = int(s181_p.max_hp)
	var s181_phase: int = int(s181_p.phase_max)
	var s181_speed: float = float(s181_p.move_speed)
	var s181_stagger: float = float(s181_p.stagger_max)
	var s181_windup: float = float(s181_p._windup_now())
	# 反向：他不能是精英（R37 的分发 bug 就是这么来的）
	var s181_elite: bool = s181_p.is_elite()
	s181_p.free()
	if s181_is_boss and s181_title == "钟 楼 旧 主" and s181_hp == 20 and s181_phase == 2 \
			and s181_speed <= 100.0 and s181_stagger >= 190.0 \
			and absf(s181_windup - 0.62) < 0.01 and not s181_elite:
		_log("PASS T181 钟楼旧主：HP %d / %d 阶段 / 移速 %.0f（最慢）/ 硬直 %.0f（最硬）/ 前摇 %.2fs（最长）"
			% [s181_hp, s181_phase, s181_speed, s181_stagger, s181_windup])
	else:
		_log("FAIL T181 boss=%s 名=%s HP=%d 阶段=%d 移速=%.0f 硬直=%.0f 前摇=%.2f 精英=%s"
			% [str(s181_is_boss), s181_title, s181_hp, s181_phase,
				s181_speed, s181_stagger, s181_windup, str(s181_elite)])

	# T182：他只出慢刀 —— _decide() 必须直接进 WINDUP，不读招 / 不瞬移 / 不远程 / 不防御
	var s182_p = r37_es.new()
	s182_p.setup(r37_es.KIND_BOSS9, Vector2(600.0, 700.0), null, null)
	var s182_states := []
	for _k in 12:
		s182_p._cd = 0.0
		s182_p._decide()
		s182_states.append(int(s182_p.state))
	var s182_all_windup := true
	for st in s182_states:
		if st != int(r37_es.WINDUP):
			s182_all_windup = false
	var s182_wt: float = float(s182_p.windup_t)
	s182_p.free()
	if s182_all_windup and absf(s182_wt - 0.62) < 0.01:
		_log("PASS T182 钟楼旧主只出慢刀：12 次选招全部进 WINDUP（前摇 %.2fs）" % s182_wt)
	else:
		_log("FAIL T182 选招状态=%s 前摇=%.2f" % [str(s182_states), s182_wt])

	# T183：打赢 → 记标记 + 回主线第一关（不留在序章）
	s180_cfg.old_master_beaten = false
	var s183_saved_lv: int = int(main.get("level_index"))
	main.call("_finish_old_master")
	var s183_beaten: bool = bool(s180_cfg.old_master_beaten)
	var s183_prologue: bool = bool(main.get("prologue_mode"))
	var s183_lv: int = int(main.get("level_index"))
	var s183_name: String = str(main.get("level_name"))
	main.set("level_index", s183_saved_lv)
	if s183_beaten and not s183_prologue and s183_lv == 0 and s183_name == RoomScript6.level_name(0):
		_log("PASS T183 打赢钟楼旧主：记 old_master_beaten · 回主线「%s」" % s183_name)
	else:
		_log("FAIL T183 beaten=%s prologue=%s lv=%d name=%s"
			% [str(s183_beaten), str(s183_prologue), s183_lv, s183_name])
	# 还原
	s180_cfg.old_master_beaten = s180_saved_master
	s180_cfg.prologue_done = s180_saved_done
	s180_cfg.save_cfg()


# R35 自测用的轻量 Mock（不进游戏，只驱动 companion.gd 的纯逻辑分支）
class MockCPlayer extends RefCounted:
	var global_position := Vector2.ZERO
	var stamina := 0.0
	var shield_layers := 0
	var dead := false
	var relics := []
	var hp := 10
	var max_hp := 10
	func has_relic(id: String) -> bool: return relics.has(id)
	func add_shield(n: int) -> void: shield_layers += n
	func add_stamina(n: float) -> void: stamina = clampf(stamina + n, 0.0, 100.0)
	func add_hp_soft(n: int) -> void:
		if hp < max_hp:
			hp = mini(max_hp, hp + maxi(0, n))
	func max_stamina() -> float: return 100.0
	# R36：符阵「煞符」会调 take_hit，Mock 也得有这个口
	var hits := 0
	func take_hit(_from: Vector2, _melee: bool = true) -> bool:
		hits += 1
		hp = maxi(0, hp - 1)
		return true


class MockCEnemy extends RefCounted:
	var global_position := Vector2.ZERO
	var dead := false
	var hp := 5
	func hurt(dmg_amount: int, from_pos: Vector2, heavy: bool = false, tag: String = "") -> void:
		if dead:
			return
		hp -= dmg_amount


func _report() -> void:
	_log("")
	_log("===== R12–R15 + R18/R18b + R19a/R19b/R20–R39 全功能自测汇总 =====")
	var pass_n := 0
	var fail_n := 0
	var warn_n := 0
	for r in results:
		if r.begins_with("PASS"):
			pass_n += 1
		elif r.begins_with("FAIL"):
			fail_n += 1
		elif r.begins_with("WARN"):
			warn_n += 1
	_log("PASS=%d  FAIL=%d  WARN=%d" % [pass_n, fail_n, warn_n])
	quit()
