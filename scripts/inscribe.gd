extends RefCounted
## R31 兵器铭刻表。效果实现在 player.gd 里（用 player.has_inscribe(id) 判断）。
##
## 与法宝的区别（这是本轮最重要的一条设计边界）：
##   法宝 = 改「你这个人」（气血 / 移速 / 道蕴 / 位次流派）
##   铭刻 = 只改「这把兵器」（取消窗口 / 段位伤害 / 刀锋长度 / 符力）
##
## 所以铭刻**按武器分开记**：剑的铭刻跟着剑走，换成长枪就看不到剑的铭刻。
## 每把武器 2 个槽，同一条词条不会在同一把武器上出现两次。
##
## 精铁（iron）是洗练货币，**局内有效、不进存档** —— 和法宝一样是一局的东西。

const SLOTS := 2
const COST_FORGE := 2      # 空槽刻一条
const COST_REFORGE := 3    # 已有词条洗一次（重 roll）

## 通用词条（4 把武器都能出）
const COMMON := [
	{"id": "edge1", "name": "锋 铭", "desc": "首段伤害 +1", "hue": 0.02, "short": "首 +1"},
	{"id": "tail1", "name": "终 铭", "desc": "连招末段伤害 +1", "hue": 0.06, "short": "末 +1"},
	{"id": "cancel", "name": "疾 铭", "desc": "取消窗口提前 5%", "hue": 0.55, "short": "取消 -5%"},
	{"id": "parry", "name": "反 铭", "desc": "完美弹反后 1 秒内伤害 +1", "hue": 0.60, "short": "弹反 +1"},
	{"id": "press", "name": "压 铭", "desc": "护体罡气压制 +10%", "hue": 0.11, "short": "罡气压制 +10%"},
	{"id": "stam", "name": "省 铭", "desc": "出刀灵力消耗 -8%", "hue": 0.33, "short": "灵力 -8%"},
	{"id": "span", "name": "长 铭", "desc": "刀锋判定范围 +6%", "hue": 0.12, "short": "刀锋 +6%"},
	{"id": "tempo", "name": "快 铭", "desc": "出招速度 +5%（前摇 / 判定 / 后摇一起快）", "hue": 0.45, "short": "出招 +5%"},
]

## 符剑专属词条 —— 只出现在符剑的铭刻池里。
## 没有这一支，新武器在铭刻系统里就是二等公民（总纲明确要求）。
const RUNE_ONLY := [
	{"id": "rune1", "name": "符 铭", "desc": "符力上限 +1（5 → 6）", "hue": 0.78, "short": "符力 +1"},
	{"id": "runev", "name": "迅 符", "desc": "符击飞行速度 +15%", "hue": 0.74, "short": "符速 +15%"},
]


## 某把武器能出的词条（符剑 = 通用 + 专属）
static func pool_for(weapon_id: String) -> Array:
	var out: Array = COMMON.duplicate(true)
	if weapon_id == "rune":
		out.append_array(RUNE_ONLY.duplicate(true))
	return out


static func by_id(id: String) -> Dictionary:
	for r in COMMON:
		if str(r["id"]) == id:
			return r
	for r in RUNE_ONLY:
		if str(r["id"]) == id:
			return r
	return {}


static func name_of(id: String) -> String:
	return str(by_id(id).get("name", "—"))


static func desc_of(id: String) -> String:
	return str(by_id(id).get("desc", ""))


static func hue_of(id: String) -> float:
	return float(by_id(id).get("hue", 0.5))


## 随机抽一条「这把武器能出、且两个槽里还没有」的词条。抽不到（池子抽干）返回 ""
static func roll(rng: RandomNumberGenerator, weapon_id: String, taken: Array) -> String:
	var cand: Array = []
	for it in pool_for(weapon_id):
		if not taken.has(str(it["id"])):
			cand.append(it)
	if cand.is_empty():
		return ""
	return str(cand[rng.randi_range(0, cand.size() - 1)]["id"])
