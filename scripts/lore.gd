extends RefCounted
## 剧情碎片：法宝、Boss、事件房各留一段文字，拼起来就是玄界的世界观。
## 只做收集与展示，不影响战斗数值。
##
## R16：12 条碎片按「四幕」重编（act 1~4，每幕 3 条）。
## 幕只是**阅读顺序**，不影响掉落来源（Boss / 事件房该掉哪条还是哪条）。

const FRAGMENTS := [
	# ---------------- 第一幕 · 钟未停 ----------------
	{"id": "L01", "act": 1, "title": "残 卷 · 道 钟", "text": "镇钟廊的道钟从来没有响过。尸解仙说，钟一响，天门就该闭了。"},
	{"id": "L02", "act": 1, "title": "残 卷 · 道 骨", "text": "镇钟力士生前是铸钟的匠人。他把自己的道骨熔进了钟壁，所以它挥剑时总有金铁的回声。"},
	{"id": "L06", "act": 1, "title": "残 卷 · 天 门", "text": "天门不是门，是一道缝。缝这边是活人的阳世，缝那边在看着这边。"},
	# ---------------- 第二幕 · 守门人 ----------------
	{"id": "L03", "act": 2, "title": "残 卷 · 魔 影", "text": "剑冢守没有影子。它把影子押给了魔渊，换来三副不会坏的道躯。"},
	{"id": "L05", "act": 2, "title": "残 卷 · 剑 冢", "text": "尸解墓道里没有尸身，只有一排排插在地上的飞剑。尸解仙每日拂拭一遍，拂了两百年。"},
	{"id": "L10", "act": 2, "title": "残 卷 · 禁 制", "text": "禁制房的铁钉每隔七息升起一次。布阵的修士算过，七息刚好够一个人犹豫。"},
	# ---------------- 第三幕 · 走到底的人 ----------------
	{"id": "L04", "act": 3, "title": "残 卷 · 前 世", "text": "前世身是第一个走到天门的人。他没回来，但回廊里多了一个和他一样挥剑的影子。"},
	{"id": "L08", "act": 3, "title": "残 卷 · 负 匣 人", "text": "那个负匣人不收铜钱，只收道蕴。他说道蕴是唯一不会贬值的东西。"},
	{"id": "L09", "act": 3, "title": "残 卷 · 宝 箱", "text": "宝箱里装的不是宝物，是上一个人的法宝。他把它留在这里，盼下一个人比自己走得远。"},
	# ---------------- 第四幕 · 域外天魔 ----------------
	{"id": "L07", "act": 4, "title": "残 卷 · 天 魔", "text": "域外天魔没有名字。它用过很多名字，每一个都刻在别人的墓碑上。"},
	{"id": "L11", "act": 4, "title": "残 卷 · 暖 雪", "text": "暖雪落下来的时候，玄界会短暂地安静。所有的影子都会停手，抬头看一会儿。"},
	{"id": "L12", "act": 4, "title": "残 卷 · 归 剑", "text": "剑意交锋的人不会死。他们只是把自己的剑留在了下一间房里。"},
	# ---------------- 第五幕 · 镜中人（R24：打赢无相·心魔才掉，全游戏第 13 卷） ----------------
	{"id": "L13", "act": 5, "title": "残 卷 · 镜", "text": "镜子里站着的不是倒影。他替你记着你不肯记的事——包括你的名字。你打赢他的那天，他没有输，他只是把一直替你拿着的东西，放回了你手里。"},
]

const RELIC_LORE := {
	"edge": "锋刃：越薄的刀越容易断，但握刀的人不在乎。",
	"wind": "疾风：风不会停，停了就不是风了。",
	"lung": "铁肺：在水下待久了，人会忘记自己在呼吸。",
	"blood": "嗜血：血是热的，刀是冷的，所以刀要喝热的。",
	"sheath": "剑鞘：鞘比刀更懂刀，因为它见过刀最安静的样子。",
	"feather": "轻身：把重量留在原地，人就快了。",
	"thunder": "雷印：雷落在同一个地方两次，第一次是警告。",
	"core": "蓄能：等得越久，出手越重。人生也是这样。",
	"wall": "铁壁：站住不动，也是一种反击。",
	"soul": "灵息：道蕴烧起来是青色的，像很远的灯。",
	"reach": "长锋：够得着，就不必靠近。",
	"guardian": "守心：护住心口的人，才敢往前走。",
}

const BOSS_LORE := {
	2: "L02",
	3: "L03",
	4: "L04",
	6: "L05",
	7: "L07",
	14: "L13",
}

## R14：Boss 三句话（战前 / 战中二阶段 / 临终）
const BOSS_LINES := {
	2: {"before": "道钟停之前，谁都不许过天门。", "mid": "你听——钟在裂。", "death": "……替我，听一次完整的道钟。"},
	3: {"before": "我守的不是天门，是门后的东西别出来。", "mid": "它在我识海里说话，你听见了吗？", "death": "天门……别开。"},
	6: {"before": "你也是被录进这道钟的，对吧？", "mid": "我记得你。上一世你死在第 7 间房。", "death": "这一世……记得钟声。"},
	7: {"before": "你不是第一个走到天门的。", "mid": "你是第一个还记得钟声的。", "death": "那就……再录一次吧。"},
	14: {"before": "你练了这么久，就是为了让我站得这么稳。", "mid": "你带的法宝，我也有一份。", "death": "输给自己的感觉……原来是这样的。"},
	# R39 钟楼旧主：隐藏 Boss，教的是「完美弹反」—— 所以他说的三句都在讲「等」
	17: {"before": "钟楼里只有一条规矩：别人抬手，你就等着。",
		"mid": "快是学不会的。慢才会。",
		"death": "记住这一下——不是我打的，是你自己挡的。"},
}

## R14：负匣人（商人）台词，按关卡切换
const MERCHANT_LINES := [
	"残卷？我有。拿道蕴来换。",
	"你身上的残卷比我多了……你到底是谁？",
	"别开天门。我求你别开。",
	"道钟的响声……你还听得见吗？",
	"镜子里那个不收道蕴。它只想要你的名字。",
]

## R14：残碑（起始房）文本，按关卡切换
const STELE_LINES := [
	"碑上刻着：道钟未停，仙路未断。",
	"碑上刻着：守门的人先兵解了，天门还立着。",
	"碑上刻着：这里埋的不是尸骨，是名字。",
	"碑上刻着：走到天门的人，都不记得自己是谁。",
	"碑上刻着：镜子里的那个，比你早到一步。",
]

## R15：残影引导者（Boss 房）—— 一个站在门边的淡影，只说一句话。
## 它是「上一个走到底的人」留下的一点残响：只给提示，不给答案。
const GUIDE_LINES := [
	"它不回头。你斩它背后。",
	"它的剑有两段。第二段才是真的。",
	"天门开的时候，别站在门口。",
	"别数你斩了几下。数它还能站起来几次。",
	"它握的是你的剑。你退半步，它就够不着。",
]


static func by_id(id: String) -> Dictionary:
	for f in FRAGMENTS:
		if str(f["id"]) == id:
			return f
	return {}


static func relic_lore(relic_id: String) -> Dictionary:
	if RELIC_LORE.has(relic_id):
		return by_id(str(RELIC_LORE[relic_id]))
	return {}


static func boss_lore(kind: int) -> Dictionary:
	if BOSS_LORE.has(kind):
		return by_id(str(BOSS_LORE[kind]))
	return {}


static func event_lore(kind: String) -> Dictionary:
	match kind:
		"chest":
			return by_id("L09")
		"shop":
			return by_id("L08")
		"trap":
			return by_id("L10")
	return {}


## R14：Boss 台词（slot = "before" / "mid" / "death"）
static func boss_line(kind: int, slot: String) -> String:
	if BOSS_LINES.has(kind):
		return str(BOSS_LINES[kind].get(slot, ""))
	return ""


## R14：负匣人台词（按关卡）
static func merchant_line(level: int) -> String:
	if MERCHANT_LINES.is_empty():
		return ""
	return str(MERCHANT_LINES[clampi(level, 0, MERCHANT_LINES.size() - 1)])


## R14：残碑文本（按关卡）
static func stele_line(level: int) -> String:
	if STELE_LINES.is_empty():
		return ""
	return str(STELE_LINES[clampi(level, 0, STELE_LINES.size() - 1)])


## R15：残影引导者台词（按关卡）
## R19a 序章「钟楼」—— 三间房三句教学。
## 只教「已经存在」的三个动作：走 / 挡 / 入阴，不引入任何新机制。
const PROLOGUE_LINES := [
	"先学会走。前面那只道兵不会还手，斩了它。",
	"它抬手的时候你也抬手。刀撞刀，叫剑意交锋；挡下来，罡气会涨。",
	"它不是死了，是躲进了阴界。入阴（Q / 摇杆上推），再斩它一次。",
	# R39：顶阁那一间（序章的第 4 间，只有无伤才会走到）
	"……你一路没让刀碰到自己。那就再学一样：等他抬手，站住，弹。",
]


static func prologue_line(i: int) -> String:
	if PROLOGUE_LINES.is_empty():
		return ""
	return str(PROLOGUE_LINES[clampi(i, 0, PROLOGUE_LINES.size() - 1)])


static func guide_line(level: int) -> String:
	if GUIDE_LINES.is_empty():
		return ""
	return str(GUIDE_LINES[clampi(level, 0, GUIDE_LINES.size() - 1)])


## R16：残卷碎片的总幕数 / 某幕是否已全部收集（图鉴用）
static func act_done(act: int, owned: Array) -> bool:
	var fs := fragments_of_act(act)
	if fs.is_empty():
		return false
	for f in fs:
		if not owned.has(str(f["id"])):
			return false
	return true


## R16：四幕的标题与引导语（图鉴页按幕分组，标题下压一行小字）
const ACT_NAMES := ["一 · 钟 未 停", "二 · 守 门 人", "三 · 走 到 底 的 人", "四 · 域 外 天 魔", "五 · 镜 中 人"]

const ACT_INTROS := [
	"第一幕：钟还在，路还没断。有人在这里数过数。",
	"第二幕：守门的人比门先坏。他们守着的东西，未必想被守住。",
	"第三幕：走到底的人一个也没回来。他们的东西留在了箱子里。",
	"第四幕：你终于走到缝前面。缝那边一直在看你。",
	"第五幕：这一卷不在十二卷之数。它只交给打赢镜子的人。",
]

## R16：主角自述 —— 每收集 3 条碎片解锁一段（3 / 6 / 9 / 12）。
## 这是「你到底是谁」的钩子：一路都是别人的故事，最后才轮到自己的名字。
const SELF_LINES := [
	{"need": 3, "title": "自 述 · 一", "text": "我不记得自己是谁。我只记得钟声——不是听见，是记得。"},
	{"need": 6, "title": "自 述 · 二", "text": "这些残卷上的字，我读得比自己的名字熟。也许我抄过它们。"},
	{"need": 9, "title": "自 述 · 三", "text": "尸解仙擦了两百年的剑，我认得每一把的锈。我从没走过这条路，可我记得每个拐角。"},
	{"need": 12, "title": "自 述 · 四", "text": "走到底的人都不记得自己是谁——因为名字被抄走了。抄它们的人，是我。我不是来飞升的，我是来录名的。"},
	{"need": 13, "title": "自 述 · 五", "text": "他替我拿了那么久的名字，居然一点没磨损。原来镜子不是来抢的——是怕我弄丢。现在，归我了。"},
]

## R16：身份称号（按已收集碎片数）。显示在 HUD 血面具下方，随进度变化。
const IDENTITY_TIERS := [
	{"need": 0, "name": ""},
	{"need": 3, "name": "录 名 者"},
	{"need": 6, "name": "抄 碑 人"},
	{"need": 9, "name": "守 钟 人"},
	{"need": 12, "name": "钟 本 身"},
	{"need": 13, "name": "镜 中 人"},
]


static func total() -> int:
	return FRAGMENTS.size()


# ---------------------------------------------------------------- R16 四幕
## 四幕的标题与引导语
static func act_name(act: int) -> String:
	if ACT_NAMES.is_empty():
		return ""
	return str(ACT_NAMES[clampi(act - 1, 0, ACT_NAMES.size() - 1)])


static func act_intro(act: int) -> String:
	if ACT_INTROS.is_empty():
		return ""
	return str(ACT_INTROS[clampi(act - 1, 0, ACT_INTROS.size() - 1)])


## 某一幕的 3 条碎片
static func fragments_of_act(act: int) -> Array:
	var out := []
	for f in FRAGMENTS:
		if int(f.get("act", 1)) == act:
			out.append(f)
	return out


static func act_of(id: String) -> int:
	return int(by_id(id).get("act", 1))


## 全部幕数（图鉴页循环用）
static func act_count() -> int:
	return ACT_NAMES.size()


# ---------------------------------------------------------------- R16 身份钩子
## 已收集 n 条时该解锁的自述（没有则返回空字典）
static func self_line_for(n: int) -> Dictionary:
	var best := {}
	for s in SELF_LINES:
		if n >= int(s["need"]):
			best = s
	return best


## 已收集 n 条时的身份称号（不足 3 条返回空串）
static func identity_title(n: int) -> String:
	var name := ""
	for t in IDENTITY_TIERS:
		if n >= int(t["need"]):
			name = str(t["name"])
	return name


## 下一个身份门槛还差几条（已满返回 0）
static func identity_remain(n: int) -> int:
	for t in IDENTITY_TIERS:
		var need := int(t["need"])
		if n < need:
			return need - n
	return 0


# ---------------------------------------------------------------- R20 真结局
## 打完心魔境的终局一句话（按身份档位）：钟收走了多少名字，结局就怎么说。
## 12 条（钟本身）收束「录名者」钩子；6–11 条收一半；0–5 条留一个开放的钟声。
const ENDING_LINES := [
	{"need": 13, "text": "镜子里空了。名字回到了你身上，钟声停在了半空——这一次，不是钟放你走，是你自己走出来的。"},
	{"need": 12, "text": "钟声停了。残卷合上——第一页写着的，是你自己的名字。"},
	{"need": 6, "text": "你把残卷一页页放回钟楼。有些名字你抄了下来，有些名字，你放过了。"},
	{"need": 0, "text": "钟声还在响。下一个走进钟楼的人，会在碑上读到你的字。"},
]


static func ending_text(n: int) -> String:
	for e in ENDING_LINES:
		if n >= int(e["need"]):
			return str(e["text"])
	return ""
