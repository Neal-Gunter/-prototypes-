extends RefCounted
## 肉鸽法宝表。效果实现在 player.gd / main.gd 里（用 player.has_relic(id) 判断）。
##
## R13 位次系统：法宝按「本位次」归到 剑 / 体 / 灵 三个位次，
## 每个位次最多放 SLOT_CAP 件 —— 满了就必须替换（`main._enter_replace`）。
## 位次满了会解锁流派名（剑修 / 壁守 / 灵御），跨位组合还能解锁飞剑流。
##
## `kind` 是法宝的「类别」，跨位联动靠它判断：
##   melee 近战 / guard 守御 / soul 道蕴 / ranged 飞剑

const SLOT_ORDER := ["blade", "wall", "spirit"]
const SLOT_CAP := 3        # 每个位次的默认容量
const SLOT_CAP_EX := 4     # R16：花道蕴扩容后的上限
const SLOT_NAMES := {"blade": "剑", "wall": "体", "spirit": "灵"}

## R16：二次质变 —— 「位次装满」+「指定法宝」同时成立时的额外效果。
## 与套装 3 件质变叠加：套装管「同一个位次拿 3 件」，这里管「满位 + 某件指定法宝」。
## 每条都要求「A 位满 + B 位有某件」—— 跨位次才算叠加，同位次不算。
const COMBO_MUTATION := {
	"blade": {"need": "sheath", "need_set": "wall",
		"name": "鞘 中 藏 锋", "desc": "取消窗口再宽 15%"},
	"wall": {"need": "soul", "need_set": "spirit",
		"name": "不 动 如 山", "desc": "格挡灵力消耗 -30%"},
	"spirit": {"need": "reach", "need_set": "blade",
		"name": "灵 息 不 灭", "desc": "道蕴获取再 ×1.3"},
}

const KIND_MELEE := "melee"
const KIND_GUARD := "guard"
const KIND_SOUL := "soul"
const KIND_RANGED := "ranged"

const SETS := {
	"blade": {"name": "剑 道", "need": 3, "hue": 0.02,
		"desc": "每段伤害再 +1，剑意交锋硬直 +10"},
	"wall": {"name": "体 道", "need": 3, "hue": 0.58,
		"desc": "护体罡气上限 +20，精准格挡 +0.06s，受伤无敌 +0.3s"},
	"spirit": {"name": "灵 道", "need": 3, "hue": 0.50,
		"desc": "道蕴获取 +25%，剑气纵横范围 +40%"},
}

const POOL := [
	{"id": "edge", "name": "锋 刃", "desc": "三段连斩每段伤害 +1", "hue": 0.02, "set": "blade", "kind": KIND_MELEE},
	{"id": "wind", "name": "疾 风", "desc": "攻速上限 +0.12，热度涨得更快", "hue": 0.55, "set": "blade", "kind": KIND_MELEE},
	{"id": "reach", "name": "长 锋", "desc": "刀锋判定范围 +18%", "hue": 0.12, "set": "blade", "kind": KIND_MELEE},
	{"id": "thunder", "name": "雷 印", "desc": "剑意交锋额外 +10 硬直度", "hue": 0.14, "set": "blade", "kind": KIND_MELEE},

	{"id": "sheath", "name": "剑 鞘", "desc": "护体罡气上限 +20（能多挡一刀再破）", "hue": 0.62, "set": "wall", "kind": KIND_GUARD},
	{"id": "wall", "name": "铁 壁", "desc": "精准格挡窗口 +0.08 秒", "hue": 0.58, "set": "wall", "kind": KIND_GUARD},
	{"id": "guardian", "name": "守 心", "desc": "受伤后无敌时间 +0.4 秒", "hue": 0.68, "set": "wall", "kind": KIND_GUARD},
	{"id": "lung", "name": "铁 肺", "desc": "灵力上限 +25，恢复更快", "hue": 0.33, "set": "wall", "kind": KIND_GUARD},

	{"id": "blood", "name": "嗜 血", "desc": "每命中 3 刀回复 1 点气血", "hue": 0.0, "set": "spirit", "kind": KIND_SOUL},
	{"id": "soul", "name": "灵 息", "desc": "开局道蕴 +40，治疗消耗 -8", "hue": 0.5, "set": "spirit", "kind": KIND_SOUL},
	{"id": "core", "name": "蓄 能", "desc": "蓄力速度 +40%，剑气纵横更早成", "hue": 0.09, "set": "spirit", "kind": KIND_SOUL},
	{"id": "feather", "name": "轻 身", "desc": "移动速度 +12%", "hue": 0.45, "set": "spirit", "kind": KIND_SOUL},

	# R12 标签化法宝：不认武器，只认「这一段是什么动作」
	{"id": "twist", "name": "回 锋", "desc": "「回旋」段护体罡气压制 +45%（双刀第三、四段）", "hue": 0.30, "set": "blade", "kind": KIND_MELEE},
	{"id": "stake", "name": "桩 步", "desc": "「突刺」段取消窗口提前 30%（长枪收刀不再干站着）", "hue": 0.08, "set": "wall", "kind": KIND_GUARD},
	{"id": "hum", "name": "余 音", "desc": "「斩击」段命中额外 +2 道蕴", "hue": 0.50, "set": "spirit", "kind": KIND_SOUL},

	# R13 飞剑轴：刃位的远程类法宝。有任意一件 → 连招最后一段会甩出一道飞剑
	{"id": "swordfly", "name": "飞 剑", "desc": "连招最后一段额外射出一道飞剑（伤害 1）", "hue": 0.52, "set": "blade", "kind": KIND_RANGED},
	{"id": "swarm", "name": "剑 群", "desc": "飞剑 +1 道，伤害 +1", "hue": 0.56, "set": "blade", "kind": KIND_RANGED},
	{"id": "pierce", "name": "穿 云", "desc": "飞剑伤害 +1，命中回 3 道蕴", "hue": 0.60, "set": "blade", "kind": KIND_RANGED},

	# R21 镜像法宝：打赢无相·心魔的专属掉落（三选一）。
	# "mirror": true = 不进随机池（pick_n_biased 会跳过），普通奖励 / 宝箱 / 商人永远抽不到。
	# 主题是「镜子里的你把你的法宝也抄了一份」——效果与本体相同，可与本体叠加。
	{"id": "edge_shadow", "name": "影 锋", "desc": "锋刃的镜像：三段连斩每段伤害 +1（可与锋刃叠加）", "hue": 0.02, "set": "blade", "kind": KIND_MELEE, "mirror": true},
	{"id": "sheath_shadow", "name": "影 鞘", "desc": "剑鞘的镜像：护体罡气上限 +20（可与剑鞘叠加）", "hue": 0.62, "set": "wall", "kind": KIND_GUARD, "mirror": true},
	{"id": "soul_shadow", "name": "影 息", "desc": "灵息的镜像：拿到即 +40 道蕴，治疗消耗 -8（可与灵息叠加）", "hue": 0.5, "set": "spirit", "kind": KIND_SOUL, "mirror": true},

	# ================================================================ R30 扩容 12 件
	# 设计铁律：**每件都带代价或条件，不做纯加法**。
	# 这样 30 件随机池里每一件都在问玩家「你愿意付什么代价」，
	# 而不是「哪件数字大拿哪件」。位次容量仍是 3（可扩 4），
	# 所以组合数从 C(8,3) 量级涨到 C(12,3) 量级 —— 深度来自选择，不来自数值。

	# --- 剑位 +4（刃）
	{"id": "duannian", "name": "断 念", "desc": "剑意交锋把敌方罡气推得更多（40%→55%）；自身罡气上限 -15",
		"hue": 0.03, "set": "blade", "kind": KIND_MELEE, "cost": "罡气上限 -15"},
	{"id": "zhuifeng", "name": "追 风", "desc": "取消收刀后再出刀，首段伤害 +2；代价是取消后 0.5 秒内不能再取消",
		"hue": 0.07, "set": "blade", "kind": KIND_MELEE, "cost": "取消后有 0.5 秒硬直"},
	{"id": "jianxia", "name": "剑 匣", "desc": "飞剑类法宝伤害 +1（约 +50%）；没有飞剑类法宝时完全无效",
		"hue": 0.54, "set": "blade", "kind": KIND_MELEE, "cost": "非飞剑流时无效"},
	{"id": "canxin", "name": "残 心", "desc": "连续 3 段不被打断，第 3 段伤害 ×2；中途挨打则重新计数",
		"hue": 0.95, "set": "blade", "kind": KIND_MELEE, "cost": "挨打就清零"},

	# --- 体位 +4（壁）
	{"id": "tieyi", "name": "铁 衣", "desc": "气血上限 +2；移速 -10%",
		"hue": 0.60, "set": "wall", "kind": KIND_GUARD, "cost": "移速 -10%"},
	{"id": "fanzhen", "name": "反 震", "desc": "格挡成功时反弹 1 点伤害给最近的敌人；只对近战刀锋有效，挡弹幕不反弹",
		"hue": 0.66, "set": "wall", "kind": KIND_GUARD, "cost": "对远程弹幕无效"},
	{"id": "guixi", "name": "龟 息", "desc": "道心失守时间 -50%；护体罡气自然回落 -20%",
		"hue": 0.40, "set": "wall", "kind": KIND_GUARD, "cost": "罡气回落更慢"},
	{"id": "xuenv", "name": "血 怒", "desc": "气血低于 30% 时伤害 +2；高于 30% 时伤害 -1",
		"hue": 0.99, "set": "wall", "kind": KIND_GUARD, "cost": "满血时反而更弱"},

	# --- 灵位 +4（灵）
	{"id": "juling", "name": "聚 灵", "desc": "道蕴获取 +30%；气血上限 -1",
		"hue": 0.48, "set": "spirit", "kind": KIND_SOUL, "cost": "气血上限 -1"},
	{"id": "funang", "name": "符 囊", "desc": "符力上限 +2（7 格）；不带符剑时完全无效",
		"hue": 0.78, "set": "spirit", "kind": KIND_SOUL, "cost": "非符剑时无效"},
	{"id": "yinyan", "name": "阴 眼", "desc": "站在阴界时暴击率 +20%；站在阳界时暴击率 -10%",
		"hue": 0.72, "set": "spirit", "kind": KIND_SOUL, "cost": "阳界反而扣暴击"},
	{"id": "yangyan", "name": "阳 炎", "desc": "站在阳界时每次命中附加 1 点灼烧；站在阴界时完全无效",
		"hue": 0.09, "set": "spirit", "kind": KIND_SOUL, "cost": "阴界时无效"},

	# R35 同伴联动：唯一一件「给你的同伴加伤」的法宝 —— 让傀儡 / 灵兽的输出更值。
	# 代价沿 R30 铁律：气血上限 -1（同伴强了，你自己脆一点）。
	{"id": "pact", "name": "灵 契", "desc": "同伴（灵兽 / 傀儡）伤害 +50%；代价是气血上限 -1",
		"hue": 0.46, "set": "spirit", "kind": KIND_SOUL, "cost": "气血上限 -1"},

	# R38 魔剑：只认业力重的人 —— 处决流的核心件。
	# 正反馈闭环：处决越多 → 业力越高 → 越容易在奖励里遇到它 → 处决更强 → 更魔。
	# `need_karma` 由调用方（main）判断，本文件不引用 Game，保持纯函数、可单测。
	{"id": "magic", "name": "魔 剑", "desc": "处决伤害 ×2，处决后回 1 点气血；代价是气血上限 -1",
		"hue": 0.98, "set": "blade", "kind": KIND_MELEE, "cost": "气血上限 -1",
		"need_karma": 5},
]


static func by_id(id: String) -> Dictionary:
	for r in POOL:
		if str(r["id"]) == id:
			return r
	return {}


static func color_of(r: Dictionary) -> Color:
	var h := float(r.get("hue", 0.5))
	return Color.from_hsv(h, 0.55, 1.0)


static func set_of(id: String) -> String:
	var r := by_id(id)
	return str(r.get("set", ""))


static func set_info(tag: String) -> Dictionary:
	return SETS.get(tag, {})


## 注意：不要叫 set_name —— 会与 Script 内置的 set_name() 撞名，
## 静态调用时会被引擎原生方法截走并返回 null。
static func set_title(tag: String) -> String:
	var s: Dictionary = SETS.get(tag, {})
	return str(s.get("name", ""))


static func set_color(tag: String) -> Color:
	var s: Dictionary = SETS.get(tag, {})
	return Color.from_hsv(float(s.get("hue", 0.5)), 0.5, 1.0)


## 抽 3 个还没拿过的法宝
static func pick_three(rng: RandomNumberGenerator, owned: Array) -> Array:
	return pick_n(rng, owned, 3)


## 抽 n 个还没拿过的法宝（险路 4 选 1 用）
static func pick_n(rng: RandomNumberGenerator, owned: Array, n: int) -> Array:
	return pick_n_biased(rng, owned, n, {})


## R16：流派专属池分层 —— 按「各占几格」给权重，抽取偏向你已经在走的那条路。
## slot_bias: {"blade": 1.6, "wall": 1.0, "spirit": 0.4}
## 空字典 = 纯随机（与旧行为完全一致）。
## R21：镜像法宝（"mirror": true）永不进随机池 —— 它们只从无相·心魔的掉落里来。
## R38：门槛法宝（"need_karma": N）默认也不进池 —— 只有 allow_karma 为真时才放行。
## 为什么要这个开关：relics.gd 是纯静态表，不能读 Game（否则单测要拖 autoload 进来）；
## 业力门槛由调用方判断后传进来。
static func pick_n_biased(rng: RandomNumberGenerator, owned: Array, n: int,
		slot_bias: Dictionary = {}, allow_karma: bool = false) -> Array:
	var pool := []
	for r in POOL:
		if bool(r.get("mirror", false)):
			continue
		if int(r.get("need_karma", 0)) > 0 and not allow_karma:
			continue
		if not owned.has(str(r["id"])):
			pool.append(r)
	if pool.is_empty():
		for r in POOL:
			if bool(r.get("mirror", false)):
				continue
			if int(r.get("need_karma", 0)) > 0 and not allow_karma:
				continue
			pool.append(r)
	var out := []
	while out.size() < n and not pool.is_empty():
		var i := _weighted_index(rng, pool, slot_bias)
		out.append(pool[i])
		pool.remove_at(i)
	return out


## R21：无相·心魔的专属掉落 —— 「影」系法宝三选一（已拥有的剔除）。
## 三件都在时返回空数组（调用方会退回普通过关）。
static func mirror_three(owned: Array) -> Array:
	var out := []
	for r in POOL:
		if bool(r.get("mirror", false)) and not owned.has(str(r["id"])):
			out.append(r)
	return out


## 按位次权重挑一个下标（权重 <=0 的项不会入选；全部为 0 时退回均匀）
static func _weighted_index(rng: RandomNumberGenerator, pool: Array,
		slot_bias: Dictionary) -> int:
	if slot_bias.is_empty():
		return rng.randi_range(0, pool.size() - 1)
	var total := 0.0
	var ws := []
	for r in pool:
		var sl := str(r.get("set", "blade"))
		var w := maxf(0.01, float(slot_bias.get(sl, 1.0)))
		ws.append(w)
		total += w
	if total <= 0.0:
		return rng.randi_range(0, pool.size() - 1)
	var roll := rng.randf() * total
	for i in ws.size():
		roll -= float(ws[i])
		if roll <= 0.0:
			return i
	return pool.size() - 1


# ---------------------------------------------------------------- R13 位次
## 法宝的本位次（剑 / 体 / 灵）
static func slot_of(id: String) -> String:
	var sl := str(by_id(id).get("set", "blade"))
	return sl if SLOT_NAMES.has(sl) else "blade"


static func slot_name(slot: String) -> String:
	return str(SLOT_NAMES.get(slot, "?"))


## 法宝类别：melee / guard / soul / ranged
static func kind_of(id: String) -> String:
	return str(by_id(id).get("kind", KIND_MELEE))


static func is_ranged(id: String) -> bool:
	return kind_of(id) == KIND_RANGED


## 池子里所有指定类别的法宝 id
static func ids_of_kind(kind: String) -> Array:
	var out := []
	for r in POOL:
		if str(r.get("kind", KIND_MELEE)) == kind:
			out.append(str(r["id"]))
	return out


## 某个位次里，属于指定类别的有几件
static func count_kind_in(slot_list: Array, kind: String) -> int:
	var n := 0
	for id in slot_list:
		if kind_of(str(id)) == kind:
			n += 1
	return n
