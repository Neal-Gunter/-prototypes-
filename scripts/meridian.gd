extends RefCounted
## R33a：经脉天赋树（局外永久成长）—— 纯数据 + 纯函数。
##
## 设计铁律（见 docs/纵深扩展总纲.md 第六节）：
##   ① 不改肉鸽随机性：只动「基础手感」，不动「这局拿到什么法宝」
##   ② 不能碾压难度：每级 ≤ +10%，满 12 条经脉 ≈ 多一条命的强度
##   ③ 每个节点 3 级，数值写死在 vals 里，不做公式外推 —— 玩家看到的就是真值
##
## 这里**不持有状态**：等级字典由 Cfg.meridian_lv 管（跨局存档）。
## 所有聚合函数都显式收 lv: Dictionary，所以自测可以传任意假字典，不碰存档。

const MAX_LV := 3
## 升到 1 / 2 / 3 级各要多少「道痕」
const COSTS := [20, 40, 70]
## 洗点返还比例（返还已投入的 70%）
const RESPEC_BACK := 0.70

## 三脉
const MERS := [
	{"id": "jian", "name": "剑 脉", "sub": "剑系 / 飞剑 / 剑意交锋", "tint": Color(0.72, 0.88, 1.0)},
	{"id": "ti", "name": "体 脉", "sub": "气血 / 罡气 / 格挡", "tint": Color(1.0, 0.78, 0.62)},
	{"id": "ling", "name": "灵 脉", "sub": "道蕴 / 符丹 / 灵御", "tint": Color(0.68, 0.96, 0.80)},
]

## 24 条经脉：3 脉 × 8 条，每条 3 级。
## vals 是该节点 1 / 2 / 3 级的真值；单位由 kind 决定（pct = 百分比 / flat = 点数）。
## 排列顺序 = 页面顺序：每脉 8 条，前 4 条左列、后 4 条右列（列优先，见 mer_node_rects）。
const NODES := [
	# ---------------------------------------------------------------- 剑脉（左列）
	{"id": "jian_feng", "name": "剑 锋", "mer": "jian", "kind": "pct",
		"vals": [5.0, 10.0, 15.0], "desc": "收刀后可取消窗口提前 %s"},
	{"id": "yu_jian", "name": "御 剑", "mer": "jian", "kind": "pct",
		"vals": [7.0, 14.0, 21.0], "desc": "符击飞行速度 +%s",
		"l3": "满级：符击穿透 1 个敌人"},
	{"id": "jian_xin", "name": "剑 心", "mer": "jian", "kind": "pct",
		"vals": [6.0, 12.0, 18.0], "desc": "剑意交锋完美窗口 +%s"},
	{"id": "jian_ying", "name": "剑 影", "mer": "jian", "kind": "pct",
		"vals": [8.0, 16.0, 24.0], "desc": "冲刺灵力消耗 −%s"},
	# ---------------------------------------------------------------- 剑脉（右列 · R33b）
	{"id": "chu_feng", "name": "出 锋", "mer": "jian", "kind": "pct",
		"vals": [6.0, 12.0, 18.0], "desc": "出刀前冲距离 +%s"},
	{"id": "dao_feng", "name": "刀 锋", "mer": "jian", "kind": "pct",
		"vals": [4.0, 8.0, 12.0], "desc": "刀锋判定范围 +%s"},
	{"id": "kuai_jian", "name": "快 剑", "mer": "jian", "kind": "pct",
		"vals": [3.0, 6.0, 9.0], "desc": "攻速成长上限 +%s"},
	{"id": "qi_mai", "name": "气 脉", "mer": "jian", "kind": "pct",
		"vals": [8.0, 16.0, 24.0], "desc": "热度上升速度 +%s",
		"l3": "满级：热度回落速度 −50%"},
	# ---------------------------------------------------------------- 体脉（左列）
	{"id": "xue_qi", "name": "血 气", "mer": "ti", "kind": "pct",
		"vals": [8.0, 16.0, 24.0], "desc": "受伤后无敌帧 +%s"},
	{"id": "gang_qi", "name": "罡 气", "mer": "ti", "kind": "flat",
		"vals": [6.0, 12.0, 18.0], "desc": "护体罡气上限 +%s"},
	{"id": "ge_dang", "name": "格 挡", "mer": "ti", "kind": "pct",
		"vals": [8.0, 16.0, 24.0], "desc": "格挡灵力消耗 −%s"},
	{"id": "ti_po", "name": "体 魄", "mer": "ti", "kind": "pct",
		"vals": [3.0, 6.0, 9.0], "desc": "移速 +%s"},
	# ---------------------------------------------------------------- 体脉（右列 · R33b）
	{"id": "tie_gu", "name": "铁 骨", "mer": "ti", "kind": "pct",
		"vals": [10.0, 20.0, 30.0], "desc": "挡刀后的硬直 −%s"},
	{"id": "zhen_qi", "name": "真 气", "mer": "ti", "kind": "pct",
		"vals": [10.0, 20.0, 30.0], "desc": "精准格挡后罡气驻留 +%s"},
	{"id": "ti_ren", "name": "体 韧", "mer": "ti", "kind": "pct",
		"vals": [10.0, 20.0, 30.0], "desc": "灵力延迟回复 −%s"},
	{"id": "ning_shen", "name": "凝 神", "mer": "ti", "kind": "pct",
		"vals": [6.0, 12.0, 18.0], "desc": "精准格挡判定窗口 +%s"},
	# ---------------------------------------------------------------- 灵脉（左列）
	{"id": "ling_xi", "name": "灵 息", "mer": "ling", "kind": "flat",
		"vals": [8.0, 16.0, 24.0], "desc": "灵力上限 +%s"},
	{"id": "ju_ling", "name": "聚 灵", "mer": "ling", "kind": "pct",
		"vals": [7.0, 14.0, 21.0], "desc": "灵力回复 +%s"},
	{"id": "fu_dan", "name": "符 丹", "mer": "ling", "kind": "pct",
		"vals": [10.0, 20.0, 30.0], "desc": "服丹 / 甩符冷却 −%s",
		"l3": "满级：开新局送 1 粒随机丹药"},
	{"id": "dao_yun", "name": "道 蕴", "mer": "ling", "kind": "pct",
		"vals": [6.0, 12.0, 18.0], "desc": "道蕴获取 +%s",
		"l3": "满级：开新局 +10 道蕴"},
	# ---------------------------------------------------------------- 灵脉（右列 · R33b）
	{"id": "fu_li", "name": "符 力", "mer": "ling", "kind": "pct",
		"vals": [7.0, 14.0, 21.0], "desc": "符力回复 +%s"},
	{"id": "ling_guan", "name": "灵 贯", "mer": "ling", "kind": "flat",
		"vals": [1.0, 2.0, 3.0], "desc": "符力上限 +%s"},
	{"id": "shen_xing", "name": "神 行", "mer": "ling", "kind": "pct",
		"vals": [6.0, 12.0, 18.0], "desc": "冲刺冷却 −%s"},
	{"id": "dan_huo", "name": "丹 火", "mer": "ling", "kind": "pct",
		"vals": [8.0, 16.0, 24.0], "desc": "打坐回血的道蕴消耗 −%s"},
]


# ---------------------------------------------------------------- 查表
static func all() -> Array:
	return NODES


static func node(id: String) -> Dictionary:
	for n in NODES:
		if str(n["id"]) == id:
			return n
	return {}


static func mer(id: String) -> Dictionary:
	for m in MERS:
		if str(m["id"]) == id:
			return m
	return {}


static func by_mer(mer_id: String) -> Array:
	var out: Array = []
	for n in NODES:
		if str(n["mer"]) == mer_id:
			out.append(n)
	return out


static func index_of(id: String) -> int:
	for i in NODES.size():
		if str(NODES[i]["id"]) == id:
			return i
	return -1


## 当前等级（0 = 未点）
static func level_of(lv: Dictionary, id: String) -> int:
	return clampi(int(lv.get(id, 0)), 0, MAX_LV)


## 从 cur 级升到 cur+1 级要多少道痕；已满级返回 -1
static func cost(id: String, cur: int) -> int:
	if node(id).is_empty():
		return -1
	if cur >= MAX_LV:
		return -1
	return int(COSTS[clampi(cur, 0, MAX_LV - 1)])


## 当前等级对应的真值（0 级 = 0）
static func val_of(lv: Dictionary, id: String) -> float:
	var l := level_of(lv, id)
	if l <= 0:
		return 0.0
	var vals: Array = node(id).get("vals", [])
	if l > vals.size():
		return 0.0
	return float(vals[l - 1])


## 百分比类 → 小数（15 → 0.15）
static func frac_of(lv: Dictionary, id: String) -> float:
	return val_of(lv, id) * 0.01


## 这一级的效果文案（%s 替换成真值；未点显示「未 点」）
static func desc_of(lv: Dictionary, id: String) -> String:
	var n := node(id)
	if n.is_empty():
		return ""
	var l := level_of(lv, id)
	if l <= 0:
		return str(n["desc"]).replace("%s", "—")
	return str(n["desc"]).replace("%s", _fmt(val_of(lv, id)))


static func _fmt(v: float) -> String:
	if absf(v - roundf(v)) < 0.01:
		return "%d" % int(roundf(v))
	return "%.1f" % v


## 全树已点级数（0 ~ 72）
static func total_lv(lv: Dictionary) -> int:
	var t := 0
	for n in NODES:
		t += level_of(lv, str(n["id"]))
	return t


## 全树已投入的道痕
static func spent(lv: Dictionary) -> int:
	var t := 0
	for n in NODES:
		var id := str(n["id"])
		var l := level_of(lv, id)
		for i in l:
			t += int(COSTS[i])
	return t


## 洗点能退回多少（向下取整）
static func respec_refund(lv: Dictionary) -> int:
	return int(floor(float(spent(lv)) * RESPEC_BACK))


# ---------------------------------------------------------------- 聚合：玩家侧
## 取消窗口倍率（< 1 = 更早可取消）
static func cancel_mul(lv: Dictionary) -> float:
	return 1.0 - frac_of(lv, "jian_feng")


## 符击飞行速度倍率
static func feijian_speed_mul(lv: Dictionary) -> float:
	return 1.0 + frac_of(lv, "yu_jian")


## 符击可穿透的敌人数量（0 = 不穿）
static func feijian_pierce(lv: Dictionary) -> int:
	return 1 if level_of(lv, "yu_jian") >= MAX_LV else 0


## 剑意交锋完美窗口倍率（< 1 = 窗口更宽，因为比的是「停手多久之后」）
static func perfect_gap_mul(lv: Dictionary) -> float:
	return 1.0 - frac_of(lv, "jian_xin")


## 冲刺灵力消耗倍率
static func dash_cost_mul(lv: Dictionary) -> float:
	return 1.0 - frac_of(lv, "jian_ying")


## 受伤后无敌帧倍率
static func hurt_invuln_mul(lv: Dictionary) -> float:
	return 1.0 + frac_of(lv, "xue_qi")


## 护体罡气上限加成（点数）
static func posture_bonus(lv: Dictionary) -> int:
	return int(roundf(val_of(lv, "gang_qi")))


## 举盾每秒灵力消耗倍率
static func guard_drain_mul(lv: Dictionary) -> float:
	return 1.0 - frac_of(lv, "ge_dang")


## 移速倍率
static func move_mul(lv: Dictionary) -> float:
	return 1.0 + frac_of(lv, "ti_po")


## 灵力上限加成（点数）
static func stamina_bonus(lv: Dictionary) -> float:
	return val_of(lv, "ling_xi")


## 灵力回复倍率
static func stamina_regen_mul(lv: Dictionary) -> float:
	return 1.0 + frac_of(lv, "ju_ling")


## 服丹 / 甩符冷却倍率
static func item_cd_mul(lv: Dictionary) -> float:
	return 1.0 - frac_of(lv, "fu_dan")


## 道蕴获取倍率
static func soul_mul(lv: Dictionary) -> float:
	return 1.0 + frac_of(lv, "dao_yun")


## 开新局送的起始道蕴
static func start_soul(lv: Dictionary) -> float:
	return 10.0 if level_of(lv, "dao_yun") >= MAX_LV else 0.0


## 开新局是否送 1 粒随机丹药
static func start_pill(lv: Dictionary) -> bool:
	return level_of(lv, "fu_dan") >= MAX_LV


# ---------------------------------------------------------------- 聚合：R33b 新增 12 条
## 出刀前冲距离倍率
static func lunge_mul(lv: Dictionary) -> float:
	return 1.0 + frac_of(lv, "chu_feng")


## 刀锋判定范围倍率（长宽同比放大，长边封顶由 _blade_rect 自己管）
static func blade_reach_mul(lv: Dictionary) -> float:
	return 1.0 + frac_of(lv, "dao_feng")


## 攻速成长上限倍率（只抬顶，不抬起步 —— 起手还是慢的）
static func atk_cap_mul(lv: Dictionary) -> float:
	return 1.0 + frac_of(lv, "kuai_jian")


## 热度上升速度倍率
static func heat_rise_mul(lv: Dictionary) -> float:
	return 1.0 + frac_of(lv, "qi_mai")


## 热度回落速度倍率（满级减半）
static func heat_fall_mul(lv: Dictionary) -> float:
	return 0.5 if level_of(lv, "qi_mai") >= MAX_LV else 1.0


## 挡刀后自身硬直倍率
static func guard_stun_mul(lv: Dictionary) -> float:
	return 1.0 - frac_of(lv, "tie_gu")


## 精准格挡后罡气「不回落」的驻留时间倍率
static func posture_hold_mul(lv: Dictionary) -> float:
	return 1.0 + frac_of(lv, "zhen_qi")


## 灵力延迟回复（花完灵力后要等多久才开始回）倍率
static func stam_delay_mul(lv: Dictionary) -> float:
	return 1.0 - frac_of(lv, "ti_ren")


## 精准格挡判定窗口倍率
static func perfect_guard_mul(lv: Dictionary) -> float:
	return 1.0 + frac_of(lv, "ning_shen")


## 符力回复倍率
static func rune_regen_mul(lv: Dictionary) -> float:
	return 1.0 + frac_of(lv, "fu_li")


## 符力上限加成（点数）
static func rune_bonus(lv: Dictionary) -> float:
	return val_of(lv, "ling_guan")


## 冲刺冷却倍率
static func dash_cd_mul(lv: Dictionary) -> float:
	return 1.0 - frac_of(lv, "shen_xing")


## 打坐回血的道蕴消耗倍率
static func heal_cost_mul(lv: Dictionary) -> float:
	return 1.0 - frac_of(lv, "dan_huo")
