extends RefCounted
## R32a/R32b：消耗品表 —— 丹药（吃）与符箓（扔）。
##
## 设计约束（见 docs/纵深扩展总纲.md 第五节）：
##   · 快捷格 **3 个是硬上限，丹药与符箓共用** —— 带什么，本身就是构筑的一部分；
##   · 每格最多叠 3 个；效果大多带代价或条件，消耗品不能替代操作；
##   · 走快捷格（键盘 1/2/3 + 触屏点格子），不占主动技能位。

## 快捷格数量（硬上限，不给扩容）
const SLOTS := 3
## 每格最多叠几个
const STACK := 3
## 两次使用之间的最小间隔：防连点把血刷满
const USE_CD := 0.9

## 六味丹药。short 是快捷格上画的那个字（格子只有 44px，画不下全名）。
const PILLS := [
	{"id": "huichun", "name": "回 春 丹", "short": "春", "desc": "回 2 点气血",
		"price": 38, "tint": Color(1.0, 0.55, 0.58)},
	{"id": "juling", "name": "聚 灵 丹", "short": "灵", "desc": "回 50 灵力",
		"price": 26, "tint": Color(0.55, 0.92, 0.72)},
	{"id": "gangqi", "name": "罡 气 丹", "short": "罡", "desc": "护体罡气 −40",
		"price": 24, "tint": Color(0.62, 0.82, 1.0)},
	{"id": "pojing", "name": "破 境 丹", "short": "境", "desc": "10 秒伤害 +2，受伤 +1",
		"price": 55, "tint": Color(1.0, 0.78, 0.42)},
	{"id": "xisui", "name": "洗 髓 丹", "short": "髓", "desc": "清除全部负面状态",
		"price": 34, "tint": Color(0.78, 0.68, 1.0)},
	{"id": "jiuzhuan", "name": "九 转 丹", "short": "转", "desc": "致死时自动复活一次（本局一次）",
		"price": 90, "tint": Color(1.0, 0.88, 0.55)},
]


static func is_pill(id: String) -> bool:
	for p in PILLS:
		if str(p["id"]) == id:
			return true
	return false


# ---------------------------------------------------------------- R32b 符箓
## 六张符。`val` 是各符自己的参数（伤害 / 时长 / 数量），
## 效果分派在 player.use_quick() 里，落世界的那一半由 main 接信号。
const TALISMANS := [
	{"id": "huo", "name": "火 符", "short": "火", "desc": "前方 200 火墙 · 2 点",
		"price": 30, "tint": Color(1.0, 0.56, 0.30), "val": 2},
	{"id": "lei", "name": "雷 符", "short": "雷", "desc": "天雷 5 道 · 每道 1 点",
		"price": 34, "tint": Color(0.72, 0.88, 1.0), "val": 1},
	{"id": "shu", "name": "盾 符", "short": "盾", "desc": "3 秒无敌",
		"price": 44, "tint": Color(0.62, 0.92, 1.0), "val": 3.0},
	{"id": "dun", "name": "遁 符", "short": "遁", "desc": "向前闪现 300",
		"price": 28, "tint": Color(0.78, 0.72, 1.0), "val": 300.0},
	{"id": "zhao", "name": "召 符", "short": "召", "desc": "纸人助战 10 秒",
		"price": 48, "tint": Color(0.96, 0.90, 0.66), "val": 10.0},
	{"id": "feng", "name": "封 符", "short": "封", "desc": "定身全场 2 秒（Boss 减半）",
		"price": 40, "tint": Color(0.66, 0.86, 0.96), "val": 2.0},
]


static func is_talisman(id: String) -> bool:
	for t in TALISMANS:
		if str(t["id"]) == id:
			return true
	return false


## 快捷格里能放的任何东西（丹药或符箓）
static func is_item(id: String) -> bool:
	return is_pill(id) or is_talisman(id)


static func talisman(id: String) -> Dictionary:
	for t in TALISMANS:
		if str(t["id"]) == id:
			return t
	return {}


## 统一的取项：先查丹药，再查符箓
static func item(id: String) -> Dictionary:
	var p := pill(id)
	if not p.is_empty():
		return p
	return talisman(id)


## 该项的参数（符箓的伤害 / 时长 / 数量；丹药没有 val，返回 0）
static func val_of(id: String) -> float:
	return float(item(id).get("val", 0.0))


static func pill(id: String) -> Dictionary:
	for p in PILLS:
		if str(p["id"]) == id:
			return p
	return {}


static func name_of(id: String) -> String:
	return str(item(id).get("name", "丹"))


static func short_of(id: String) -> String:
	return str(item(id).get("short", "丹"))


static func desc_of(id: String) -> String:
	return str(item(id).get("desc", ""))


static func price_of(id: String) -> int:
	return int(item(id).get("price", 30))


static func tint_of(id: String) -> Color:
	var t: Variant = item(id).get("tint", Color(0.9, 0.9, 0.9))
	return t as Color


static func ids() -> Array:
	var out: Array = []
	for p in PILLS:
		out.append(str(p["id"]))
	return out


static func talisman_ids() -> Array:
	var out: Array = []
	for t in TALISMANS:
		out.append(str(t["id"]))
	return out


## 随机一味（宝箱 / 精英掉落 / 商人货架共用）
static func roll(rng: RandomNumberGenerator) -> String:
	var pool := ids()
	if pool.is_empty():
		return ""
	return str(pool[rng.randi_range(0, pool.size() - 1)])


## 随机一张符（商队第 5 行 / 精英掉落 / Boss 掉落共用）
static func roll_talisman(rng: RandomNumberGenerator) -> String:
	var pool := talisman_ids()
	if pool.is_empty():
		return ""
	return str(pool[rng.randi_range(0, pool.size() - 1)])


## 掉落权重：九转丹太强，不能跟回春丹同概率
static func roll_drop(rng: RandomNumberGenerator) -> String:
	var r := rng.randf()
	if r < 0.10:
		return "jiuzhuan"
	if r < 0.34:
		return "huichun"
	if r < 0.56:
		return "juling"
	if r < 0.74:
		return "gangqi"
	if r < 0.90:
		return "xisui"
	return "pojing"
