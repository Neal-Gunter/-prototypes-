extends RefCounted
## 肉鸽地图（R10）：一关 = 一张 3×2 的房间网格，玩家在房间里自由走动、清场、走门去下一间。
##
## 布局（row 0 靠镜头 / row 1 靠后墙）：
##      row 1 :  [3] 墓室回廊   [4] 精英祭坛   [5] Boss 门厅
##      row 0 :  [0] 入口       [1] 战斗厅     [2] 秘藏/商队
## 邻接：同一行左右相连，同一列上下（前/后）相连。
## 起点固定 index 0，Boss 固定 index 5 —— 玩家自己选路线绕过去。

const SpaceScript := preload("res://scripts/space.gd")

const COLS := 3
const ROWS := 2
const ROOM_COUNT := COLS * ROWS

const KIND_START := "start"
const KIND_BATTLE := "battle"
const KIND_ELITE := "elite"
const KIND_CHEST := "chest"
const KIND_SHOP := "shop"
const KIND_TRAP := "trap"
const KIND_BOSS := "boss"

## 兼容旧接口（岔路页已废弃，保留常量以免旧引用报错）
const ROUTES := [
	{"id": "steady", "name": "稳 路", "desc": "敌人 -1 · 清场回复 1 点气血", "wave": -1, "heal": 1, "soul": 0, "rich": false, "hue": 0.42},
	{"id": "peril", "name": "险 路", "desc": "敌人 +2 · 清场道蕴 +30 · 法宝 4 选 1", "wave": 2, "heal": 0, "soul": 30, "rich": true, "hue": 0.02},
]

## 地板范围（所有房间共用同一块竞技场）
const GROUND_Y := SpaceScript.FLOOR_NEAR_Y
const AIR_Y := SpaceScript.FLOOR_FAR_Y

const LEVELS := [
	{
		"name": "镇 钟 廊",
		"start": Vector2(650.0, 700.0),
		"rooms": [
			{"name": "回廊 · 入 口", "col": 0, "row": 0, "kind": KIND_START, "wave": 0},
			{"name": "钟 室 · 前 厅", "col": 1, "row": 0, "kind": KIND_BATTLE, "wave": 2},
			{"name": "秘 藏 · 石 龛", "col": 2, "row": 0, "kind": KIND_CHEST, "wave": 0},
			{"name": "断 崖 · 回 廊", "col": 0, "row": 1, "kind": KIND_BATTLE, "wave": 3},
			{"name": "石 柱 · 祭 坛", "col": 1, "row": 1, "kind": KIND_ELITE, "wave": 4},
			{"name": "守 卫 · 大 剑", "col": 2, "row": 1, "kind": KIND_BOSS, "wave": 0, "boss": 2},
		],
	},
	{
		"name": "剑 冢 阶",
		"start": Vector2(650.0, 700.0),
		"rooms": [
			{"name": "深 渊 · 前 厅", "col": 0, "row": 0, "kind": KIND_START, "wave": 0},
			{"name": "剑 冢 · 廊 道", "col": 1, "row": 0, "kind": KIND_BATTLE, "wave": 3},
			{"name": "冷 雾 · 商 队", "col": 2, "row": 0, "kind": KIND_SHOP, "wave": 0},
			{"name": "深 渊 · 阶 梯", "col": 0, "row": 1, "kind": KIND_TRAP, "wave": 3},
			{"name": "影 刃 · 祭 坛", "col": 1, "row": 1, "kind": KIND_ELITE, "wave": 4},
			{"name": "剑 主 · 深 渊", "col": 2, "row": 1, "kind": KIND_BOSS, "wave": 0, "boss": 3},
		],
	},
	{
		"name": "尸 解 墓 道",
		"start": Vector2(650.0, 700.0),
		"rooms": [
			{"name": "墓 道 · 入 口", "col": 0, "row": 0, "kind": KIND_START, "wave": 0},
			{"name": "石 椁 · 回 廊", "col": 1, "row": 0, "kind": KIND_BATTLE, "wave": 3},
			{"name": "铁 钉 · 陷 阱", "col": 2, "row": 0, "kind": KIND_TRAP, "wave": 3},
			{"name": "铁 链 · 深 井", "col": 0, "row": 1, "kind": KIND_BATTLE, "wave": 4, "echo": true},
			{"name": "玄 铁 · 祭 坛", "col": 1, "row": 1, "kind": KIND_ELITE, "wave": 5},
			{"name": "尸 解 仙 · 墓 室", "col": 2, "row": 1, "kind": KIND_BOSS, "wave": 0, "boss": 6},
		],
	},
	{
		"name": "天 门",
		"start": Vector2(650.0, 700.0),
		"rooms": [
			{"name": "门 · 前 庭", "col": 0, "row": 0, "kind": KIND_START, "wave": 0},
			{"name": "界 隙 · 回 廊", "col": 1, "row": 0, "kind": KIND_BATTLE, "wave": 4},
			{"name": "无 光 · 商 队", "col": 2, "row": 0, "kind": KIND_SHOP, "wave": 0},
			{"name": "门 扉 · 长 阶", "col": 0, "row": 1, "kind": KIND_BATTLE, "wave": 4},
			{"name": "玄 界 · 祭 坛", "col": 1, "row": 1, "kind": KIND_ELITE, "wave": 5},
			{"name": "域 外 天 魔", "col": 2, "row": 1, "kind": KIND_BOSS, "wave": 0, "boss": 7},
		],
	},
	# R36：第 6 关「符箓秘境」。seals = 这间房地面上的符阵数量
	# （踩上触发一次：奇数位增益回灵力 / 偶数位减益灼烧 1 点）。
	# 插在「心魔境」之前 —— 心魔境必须还是最后一关，真结局挂在终章上。
	{
		"name": "符 箓 秘 境",
		"start": Vector2(650.0, 700.0),
		"rooms": [
			{"name": "符 阵 · 前 庭", "col": 0, "row": 0, "kind": KIND_START, "wave": 0},
			{"name": "朱 砂 · 回 廊", "col": 1, "row": 0, "kind": KIND_BATTLE, "wave": 4, "seals": 3},
			{"name": "秘 藏 · 符 龛", "col": 2, "row": 0, "kind": KIND_CHEST, "wave": 0},
			{"name": "残 符 · 深 处", "col": 0, "row": 1, "kind": KIND_TRAP, "wave": 3, "seals": 2},
			{"name": "符 祖 · 祭 坛", "col": 1, "row": 1, "kind": KIND_ELITE, "wave": 5, "seals": 3},
			{"name": "符 祖 · 殿", "col": 2, "row": 1, "kind": KIND_BOSS, "wave": 0, "boss": 15, "seals": 2},
		],
	},
	# R37：第 7 关「轮回台」。echoes = 这间房开场就站着几个「旧影」
	# （半透明的影子，沿玩家最近几秒的轨迹走）。关底是轮回使，它会现场召旧影。
	# 同样插在「心魔境」之前 —— 真结局必须还是最后一关。
	{
		"name": "轮 回 台",
		"start": Vector2(650.0, 700.0),
		"rooms": [
			{"name": "轮 回 · 前 庭", "col": 0, "row": 0, "kind": KIND_START, "wave": 0},
			{"name": "旧 影 · 回 廊", "col": 1, "row": 0, "kind": KIND_BATTLE, "wave": 4, "echoes": 2},
			{"name": "秘 藏 · 轮 藏", "col": 2, "row": 0, "kind": KIND_CHEST, "wave": 0},
			{"name": "因 果 · 深 处", "col": 0, "row": 1, "kind": KIND_TRAP, "wave": 3, "echoes": 2},
			{"name": "轮 回 使 · 祭 坛", "col": 1, "row": 1, "kind": KIND_ELITE, "wave": 5, "echoes": 3},
			{"name": "轮 回 使 · 台", "col": 2, "row": 1, "kind": KIND_BOSS, "wave": 0, "boss": 16},
		],
	},
	# R19b：第 7 关「心魔境」。mirror = 这间房额外站一个「镜子里的你」，
	# 它的武器与法宝从玩家身上抄（见 main._apply_mirror）。
	# 关底不是新的招式表，而是**你自己的 Build**：无相·心魔。
	{
		"name": "心 魔 境",
		"start": Vector2(650.0, 700.0),
		"rooms": [
			{"name": "镜 · 前 庭", "col": 0, "row": 0, "kind": KIND_START, "wave": 0},
			{"name": "镜 · 回 廊", "col": 1, "row": 0, "kind": KIND_BATTLE, "wave": 4, "mirror": true},
			{"name": "镜 · 秘 藏", "col": 2, "row": 0, "kind": KIND_CHEST, "wave": 0},
			{"name": "心 · 深 处", "col": 0, "row": 1, "kind": KIND_BATTLE, "wave": 4, "mirror": true},
			{"name": "心 · 祭 坛", "col": 1, "row": 1, "kind": KIND_ELITE, "wave": 5, "mirror": true},
			{"name": "无 相 · 心 魔", "col": 2, "row": 1, "kind": KIND_BOSS, "wave": 0, "boss": 14},
		],
	},
]


## R19a 序章「钟楼」：3 间房，线性，无 Boss，**不占主线进度**。
## fixed = 这一间固定刷什么（不走随机波次），用来保证教学顺序。
const PROLOGUE := {
	"name": "钟 楼 · 序 章",
	"start": Vector2(650.0, 700.0),
	"rooms": [
		{"name": "钟 楼 · 一 层", "col": 0, "row": 0, "kind": KIND_BATTLE, "wave": 1, "fixed": [0]},
		{"name": "钟 楼 · 二 层", "col": 1, "row": 0, "kind": KIND_BATTLE, "wave": 2, "fixed": [0, 0]},
		{"name": "钟 楼 · 三 层", "col": 2, "row": 0, "kind": KIND_BATTLE, "wave": 1, "fixed": [11]},
	],
}


static func prologue_rooms() -> Array:
	return PROLOGUE["rooms"]


static func prologue_name() -> String:
	return str(PROLOGUE["name"])


## R39 隐藏 Boss 房「钟楼 · 顶阁」—— 只有**无伤走完序章三间**才会开。
## 单独一份，不并进 PROLOGUE：序章本身仍是「三间教学」，顶阁是额外加的一层。
## 为什么不做成第 4 间常驻房：那会让每个新玩家都撞上隐藏 Boss，
## 「隐藏」就没了。触发权在 main._finish_prologue()。
const PROLOGUE_MASTER := {
	"name": "钟 楼 · 顶 阁", "col": 3, "row": 0,
	"kind": KIND_BOSS, "wave": 0, "boss": 17,
}


static func prologue_master_room() -> Dictionary:
	return PROLOGUE_MASTER


## 序章是「一条线」：第 i 间只连前后两间，不走 3×2 网格。
## total 不传时按标准序章（3 间）算；进了顶阁之后 rooms 变 4 个元素，要显式传。
static func prologue_neighbors(i: int, total: int = -1) -> Dictionary:
	var out := {"west": false, "east": false, "north": false, "south": false}
	var n: int = total if total > 0 else PROLOGUE["rooms"].size()
	if i > 0:
		out["west"] = true
	if i < n - 1:
		out["east"] = true
	return out


static func level_count() -> int:
	return LEVELS.size()


## 终章关卡下标（= 最后一关）。真结局挂在它上面；R36 加关后仍是「心魔境」。
static func finale_level() -> int:
	return LEVELS.size() - 1


static func level_name(i: int) -> String:
	if i < 0 or i >= LEVELS.size():
		return "?"
	return str(LEVELS[i]["name"])


static func rooms_of(i: int) -> Array:
	if i < 0 or i >= LEVELS.size():
		return []
	return LEVELS[i]["rooms"]


static func start_pos(i: int) -> Vector2:
	if i < 0 or i >= LEVELS.size():
		return Vector2(650.0, 700.0)
	return LEVELS[i]["start"]


static func room_kind(room: Dictionary) -> String:
	return str(room.get("kind", KIND_BATTLE))


## 某间房的四向邻居：{"west": idx, "east": idx, "north": idx, "south": idx}
## north = 后排（row + 1，靠后墙），south = 前排（row - 1，靠镜头）
static func neighbors(level_index: int, room_index: int) -> Dictionary:
	var out := {}
	var rs := rooms_of(level_index)
	if room_index < 0 or room_index >= rs.size():
		return out
	var col := int(rs[room_index]["col"])
	var row := int(rs[room_index]["row"])
	for j in rs.size():
		if j == room_index:
			continue
		var c := int(rs[j]["col"])
		var r := int(rs[j]["row"])
		if r == row and c == col - 1:
			out["west"] = j
		elif r == row and c == col + 1:
			out["east"] = j
		elif c == col and r == row + 1:
			out["north"] = j
		elif c == col and r == row - 1:
			out["south"] = j
	return out


static func route_by_id(id: String) -> Dictionary:
	for r in ROUTES:
		if str(r["id"]) == id:
			return r
	return {}


static func route_color(r: Dictionary) -> Color:
	return Color.from_hsv(float(r.get("hue", 0.4)), 0.5, 1.0)


## 每日种子：按本地日期取一个稳定的整数种子
static func daily_seed() -> int:
	var d := Time.get_date_dict_from_system()
	var key := "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]
	var h := 2166136261
	for i in key.length():
		h = int((h ^ key.unicode_at(i)) * 16777619) & 0x7fffffff
	return h & 0x7fffffff


static func today_key() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]


# ---------------------------------------------------------------- R18 精英 / 变奏
## 精英替换率（普通房间）：一间房 15% 概率把「一只小怪」换成精英
const ELITE_REPLACE_CHANCE := 0.15
const ELITE_MIN_LEVEL := 1        # 关卡二（剑冢阶）起才刷精英，第一关留给基础手感

## 精英池：按关卡解锁（index = 关卡序号，0 起）
const ELITE_POOL := [
	[],                                                          # 关卡一 镇钟廊：不刷
	[8, 9],                                                      # 关卡二 剑冢阶：剑修傀儡 / 符修
	[8, 9, 10, 12],                                              # 关卡三 尸解墓道：+ 丹修 / 纸人
	[8, 9, 10, 12, 11, 13],                                      # 关卡四 天门：全解锁（怨灵 / 尸傀）
]

## 行为变奏池：同一只敌人最多挂 1 个，按关卡解锁
## 1=护盾 2=召唤 3=自爆 4=读招 5=狂暴
const VARIANT_POOL := [
	[],                                                          # 关卡一：无
	[1],                                                         # 关卡二：护盾型
	[1, 2, 3],                                                   # 关卡三：+ 召唤 / 自爆
	[1, 2, 3, 4, 5],                                              # 关卡四：全解锁（+ 读招 / 狂暴）
]

## 每只普通杂兵带变奏的概率（精英不叠变奏，所以实际出现率略低于此值）
const VARIANT_CHANCE := 0.45


## 某关能刷哪些精英（关卡超出表尾 → 用最后一档）
static func elite_pool(lv: int) -> Array:
	if ELITE_POOL.is_empty() or lv < ELITE_MIN_LEVEL:
		return []
	return ELITE_POOL[clampi(lv, 0, ELITE_POOL.size() - 1)]


## 某关能挂哪些变奏
static func variant_pool(lv: int) -> Array:
	if VARIANT_POOL.is_empty():
		return []
	return VARIANT_POOL[clampi(lv, 0, VARIANT_POOL.size() - 1)]


## 生成一间房的敌人：{kind, pos, variant}
## 位置撒在整块地板上（不再是一条横线），由 main 负责避开玩家
## lv = 关卡序号（决定精英 / 变奏池），extra = 加减敌人数
static func wave(rng: RandomNumberGenerator, room: Dictionary, index: int,
		lv: int = 0, extra: int = 0) -> Array:
	var n := int(room.get("wave", 2)) + extra
	n = clampi(n, 0, 8)
	if n <= 0:
		return []
	var elite_room := room_kind(room) == KIND_ELITE
	var out := []
	for i in n:
		var px := rng.randf_range(SpaceScript.ROOM_X0 + 130.0, SpaceScript.ROOM_X1 - 130.0)
		var py := rng.randf_range(SpaceScript.FLOOR_FAR_Y + 30.0, SpaceScript.FLOOR_NEAR_Y - 26.0)
		var flyer := false
		var chance := 0.42 if elite_room else 0.28
		if index >= 1 and rng.randf() < chance:
			flyer = true
		out.append({"kind": 1 if flyer else 0, "pos": Vector2(px, py), "variant": 0})

	# R18 行为变奏：每只小怪各自掷一次（关卡一池子为空 → 全 0）
	var vpool := variant_pool(lv)
	if not vpool.is_empty():
		for spec in out:
			if rng.randf() < VARIANT_CHANCE:
				spec["variant"] = int(vpool[rng.randi_range(0, vpool.size() - 1)])

	# R18 精英：普通战斗房 15% 换一只（精英祭坛房本来就是精英房，不重复换）
	if not elite_room and n > 0 and index >= 1:
		var epool := elite_pool(lv)
		if not epool.is_empty() and rng.randf() < ELITE_REPLACE_CHANCE:
			var slot := rng.randi_range(0, out.size() - 1)
			var ek := int(epool[rng.randi_range(0, epool.size() - 1)])
			out[slot]["kind"] = ek
			out[slot]["variant"] = 0        # 精英不叠变奏
	return out


## 陷阱房：地刺摆在房间中段，绕开门口
static func trap_hazards(room: Dictionary) -> Array:
	var cx := (SpaceScript.ROOM_X0 + SpaceScript.ROOM_X1) * 0.5
	return [
		Rect2(cx - 210.0, SpaceScript.FLOOR_NEAR_Y - 168.0, 120.0, 40.0),
		Rect2(cx + 96.0, SpaceScript.FLOOR_NEAR_Y - 96.0, 120.0, 40.0),
		Rect2(cx - 60.0, SpaceScript.FLOOR_NEAR_Y - 44.0, 130.0, 40.0),
	]
