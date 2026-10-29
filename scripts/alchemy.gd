extends RefCounted
## R33c：丹房 —— 局外合成。扣「道痕」产丹药 / 符箓，产物进「跨局背包」，
## 下一局开局自动带进快捷格。
##
## 设计铁律（见 docs/纵深扩展总纲.md 第六节）：
##   ① **不新增货币**：道痕同时是经脉和丹房的钱 —— 「攒着点经脉」还是「换药保这一局」，
##      这个取舍本身就是丹房存在的意义。多印一种货币，取舍就没了。
##   ② **不新增格子**：跨局背包上限 9 = 3 格 × 3 叠，正好是一局的全部携带量。
##      背包永远不会比「能带进局的」更大，所以不存在「存着不用」的囤积玩法。
##   ③ **带进局就归这一局**：开局注入快捷格后背包清空，局内用掉就没了，死了也不还。
##      肉鸽的痛感必须保住，否则丹房会变成「无限补给」。
##
## 这里**不持有状态**：配方是常量，背包在 Cfg.pantry。
## 所有函数都是 static，自测可以直接验真值。

const ConsumeScript := preload("res://scripts/consumable.gd")

## 合成价 = 商队价 × 这个比例。
## 为什么打折：道痕比道蕴稀有得多（一局通关 80 道痕，而一局道蕴常有几百），
## 照抄商队价会让丹房变成「买不起的橱窗」。
const PRICE_MUL := 0.5

## 跨局背包总件数上限（= 快捷格 3 × 每格叠 3）
const PANTRY_CAP := 9


## 12 张方子：6 味丹 + 6 张符，顺序 = 页面顺序（4 列 × 3 行，行优先）
static func recipes() -> Array:
	var out: Array = []
	for p in ConsumeScript.PILLS:
		out.append(_rec(p, "pill"))
	for t in ConsumeScript.TALISMANS:
		out.append(_rec(t, "talisman"))
	return out


static func _rec(it: Dictionary, kind: String) -> Dictionary:
	return {
		"id": str(it["id"]),
		"name": str(it["name"]),
		"short": str(it["short"]),
		"desc": str(it["desc"]),
		"tint": it["tint"],
		"kind": kind,
		"cost": int(round(float(it["price"]) * PRICE_MUL)),
	}


static func recipe(id: String) -> Dictionary:
	for r in recipes():
		if str(r["id"]) == id:
			return r
	return {}


static func index_of(id: String) -> int:
	var all: Array = recipes()
	for i in all.size():
		if str(all[i]["id"]) == id:
			return i
	return -1


## 一张方子的道痕价
static func cost_of(id: String) -> int:
	var r := recipe(id)
	return int(r["cost"]) if not r.is_empty() else -1


## 丹药方 / 符箓方各几张（页面上分组显示用）
static func count_of(kind: String) -> int:
	var n := 0
	for r in recipes():
		if str(r["kind"]) == kind:
			n += 1
	return n
