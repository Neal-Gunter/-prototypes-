extends RefCounted
## 武器 / 流派：三种武器各有刀锋长度、攻速、伤害、灵力消耗的取舍。
## 数值全部由 player.gd 读取，换武器不改任何判定逻辑，只改参数与外观。
##
## R12 连招模组层：每把武器带一套**独立的段位表** `combo`，
## 不再共用 player.gd 里那张全局 STAGES。段位表字段：
##   wind   抬刀时间      act  判定时间      rec  收刀时间
##   dmg    基础伤害      w/h  刀锋判定框     stam 本段灵力
##   tag    动作标签      posture 护体罡气压制（占敌方护体罡气上限的比例）
##   cancel 取消窗口（收刀进行到该比例后，可被闪避 / 格挡打断）

## 动作标签（R12 延展）：法宝可以围绕标签触发
const TAG_SLASH := "slash"    # 斩击
const TAG_THRUST := "thrust"  # 突刺
const TAG_SPIN := "spin"      # 回旋
const TAG_UP := "up"          # R16 上挑：把敌人挑到空中（浮空硬直）
const TAG_DOWN := "down"      # R16 下劈：对浮空目标额外加伤并砸落
const TAG_RANGED := "ranged"  # R29 符击：远程段，不产生刀锋判定，改为射出一道符

const TAG_NAMES := {
	"slash": "斩 击",
	"thrust": "突 刺",
	"spin": "回 旋",
	"up": "上 挑",
	"down": "下 劈",
	"ranged": "符 击",
}

## R16：浮空相关常量
const AIR_STUN_TIME := 0.55   # 上挑造成的浮空时长（够接一段下劈，接不了无限循环）

const LIST := [
	{
		"id": "sword", "name": "单 手 剑", "tag": "守 钟 本 命 剑",
		"desc": "三段连斩，收刀最早可取消 —— 打不过就退得掉。",
		"lore": "钟楼最后一任守卫的法宝，剑上还有铜锈",
		"dmg": 0, "reach": 1.0, "speed": 1.0, "stam": 1.0, "hue": 0.56,
		"ult": {"id": "line", "name": "剑 心 · 一 线", "shots": 1, "dmg": 6,
			"len": 560.0, "thick": 84.0, "gap": 0.0, "radius": 0.0, "lunge": 0.0},
		"combo": [
			{"wind": 0.045, "act": 0.11, "rec": 0.13, "dmg": 1, "w": 66.0, "h": 58.0,
				"stam": 9.0, "tag": TAG_SLASH, "posture": 0.05, "cancel": 0.30},
			{"wind": 0.030, "act": 0.12, "rec": 0.14, "dmg": 1, "w": 74.0, "h": 64.0,
				"stam": 11.0, "tag": TAG_UP, "posture": 0.06, "cancel": 0.32},
			{"wind": 0.055, "act": 0.17, "rec": 0.24, "dmg": 2, "w": 90.0, "h": 78.0,
				"stam": 16.0, "tag": TAG_DOWN, "posture": 0.10, "cancel": 0.35},
		],
	},
	{
		"id": "spear", "name": "长 枪", "tag": "剑 冢 罡 枪",
		"desc": "长锋 45%，出刀自动前追；贴脸打不出伤害，收刀难取消。",
		"lore": "断剑阶守卫的法宝，他守到最后一级，没退",
		"dmg": 1, "reach": 1.45, "speed": 0.82, "stam": 1.15, "hue": 0.10,
		"ult": {"id": "lance", "name": "枪 出 如 龙", "shots": 3, "dmg": 2,
			"len": 190.0, "thick": 58.0, "gap": 0.075, "radius": 0.0, "lunge": 300.0},
		"combo": [
			{"wind": 0.075, "act": 0.10, "rec": 0.16, "dmg": 1, "w": 74.0, "h": 46.0,
				"stam": 11.0, "tag": TAG_THRUST, "posture": 0.06, "cancel": 0.72},
			{"wind": 0.065, "act": 0.11, "rec": 0.17, "dmg": 1, "w": 84.0, "h": 48.0,
				"stam": 13.0, "tag": TAG_THRUST, "posture": 0.07, "cancel": 0.74},
			{"wind": 0.090, "act": 0.15, "rec": 0.28, "dmg": 2, "w": 104.0, "h": 56.0,
				"stam": 19.0, "tag": TAG_UP, "posture": 0.12, "cancel": 0.78},
		],
	},
	{
		"id": "dual", "name": "双 刀", "tag": "双 生 剑",
		"desc": "四段连舞，护体罡气压制最高 —— 砍不死人，但能砍到「道心失守」。",
		"lore": "墓道双生子的法宝，两把刀，墓里只剩一把",
		"dmg": -1, "reach": 0.88, "speed": 1.25, "stam": 0.80, "hue": 0.92,
		"ult": {"id": "spin", "name": "双 生 · 旋 刃", "shots": 6, "dmg": 1,
			"len": 0.0, "thick": 0.0, "gap": 0.085, "radius": 132.0, "lunge": 0.0},
		"combo": [
			{"wind": 0.030, "act": 0.085, "rec": 0.105, "dmg": 1, "w": 58.0, "h": 52.0,
				"stam": 6.0, "tag": TAG_SLASH, "posture": 0.08, "cancel": 0.55},
			{"wind": 0.026, "act": 0.090, "rec": 0.110, "dmg": 1, "w": 62.0, "h": 56.0,
				"stam": 7.0, "tag": TAG_UP, "posture": 0.09, "cancel": 0.58},
			{"wind": 0.040, "act": 0.110, "rec": 0.150, "dmg": 1, "w": 76.0, "h": 70.0,
				"stam": 10.0, "tag": TAG_SPIN, "posture": 0.12, "cancel": 0.62},
			{"wind": 0.050, "act": 0.140, "rec": 0.220, "dmg": 2, "w": 84.0, "h": 74.0,
				"stam": 14.0, "tag": TAG_DOWN, "posture": 0.15, "cancel": 0.65},
		],
	},
	# ---------------------------------------------------------------- R29 第 4 把：符剑
	# 前三把是「近战三态」（剑均衡 / 枪空间 / 双刀压制），这把补「想站远一点打」。
	# 唯一一把不吃灵力的武器：远程段吃「符力」（player.gd 的独立资源），近战段吃灵力。
	# 代价：单段伤害最低（远程 1 / 近战 2）、架势压制最低（0.18）—— 安全换输出。
	{
		"id": "rune", "name": "符 剑", "tag": "符 箓 本 命",
		"desc": "两段符击远射，第三段贴身剑斩",
		"lore": "符箓秘境里封着的一把剑，剑身贴满还没引爆的符",
		"dmg": 0, "reach": 1.02, "speed": 0.95, "stam": 0.55, "hue": 0.78,
		"stat3_name": "符 力", "stat3_val": 0.72,
		"ult": {"id": "array", "name": "符 阵 · 万 剑", "shots": 8, "dmg": 2,
			"len": 0.0, "thick": 0.0, "gap": 0.155, "radius": 0.0, "lunge": 0.0},
		"combo": [
			{"wind": 0.055, "act": 0.10, "rec": 0.15, "dmg": 1, "w": 58.0, "h": 50.0,
				"stam": 0.0, "tag": TAG_RANGED, "posture": 0.04, "cancel": 0.40, "ranged": true},
			{"wind": 0.050, "act": 0.10, "rec": 0.16, "dmg": 1, "w": 58.0, "h": 50.0,
				"stam": 0.0, "tag": TAG_RANGED, "posture": 0.04, "cancel": 0.45, "ranged": true},
			{"wind": 0.065, "act": 0.14, "rec": 0.22, "dmg": 2, "w": 86.0, "h": 70.0,
				"stam": 13.0, "tag": TAG_SLASH, "posture": 0.10, "cancel": 0.50},
		],
	},
]


static func by_id(id: String) -> Dictionary:
	for w in LIST:
		if str(w["id"]) == id:
			return w
	return LIST[0]


static func index_of(id: String) -> int:
	for i in LIST.size():
		if str(LIST[i]["id"]) == id:
			return i
	return 0


static func name_of(id: String) -> String:
	return str(by_id(id)["name"])


static func reach_mul(id: String) -> float:
	return float(by_id(id).get("reach", 1.0))


static func speed_mul(id: String) -> float:
	return float(by_id(id).get("speed", 1.0))


static func stam_mul(id: String) -> float:
	return float(by_id(id).get("stam", 1.0))


static func dmg_add(id: String) -> int:
	return int(by_id(id).get("dmg", 0))


## R18b 专属绝招：三把武器各一种**形态**，总伤害与灵力消耗完全相同，
## 只有「形状」不同 —— 一轮只改一个手感变量。
##   line  直线贯穿（剑）  /  lance 三段推进（枪）  /  spin 原地旋风（双刀）
## 字段：shots 段数 · dmg 每段伤害 · gap 段间隔 · len/thick 直线尺寸 · radius 旋风半径 · lunge 前冲
static func ult_of(id: String) -> Dictionary:
	var u: Dictionary = by_id(id).get("ult", {})
	if u.is_empty():
		return {"id": "spin", "name": "剑 气 纵 横", "shots": 1, "dmg": 6,
			"len": 0.0, "thick": 0.0, "gap": 0.0, "radius": 210.0, "lunge": 0.0}
	return u


static func ult_name(id: String) -> String:
	return str(ult_of(id).get("name", "剑 气 纵 横"))


static func color_of(w: Dictionary) -> Color:
	return Color.from_hsv(float(w.get("hue", 0.56)), 0.42, 1.0)


# ---------------------------------------------------------------- R12 连招模组
## 某把武器的整套段位表
static func combo_of(id: String) -> Array:
	return by_id(id).get("combo", [])


## 某把武器一共几段（剑/枪 3 段，双刀 4 段）
static func combo_len(id: String) -> int:
	return combo_of(id).size()


## 某把武器第 n 段（n 从 1 开始，越界自动夹紧）
static func stage_of(id: String, n: int) -> Dictionary:
	var arr := combo_of(id)
	if arr.is_empty():
		return {}
	return arr[clampi(n - 1, 0, arr.size() - 1)]


## 标签的中文名（HUD 用）
static func tag_name(tag: String) -> String:
	return str(TAG_NAMES.get(tag, ""))


## 整套连招的护体罡气压制总量（占敌方护体罡气上限的比例，给 HUD / 自测做展示）
static func combo_posture(id: String) -> float:
	var s := 0.0
	for st in combo_of(id):
		s += float(st.get("posture", 0.0))
	return s


# ---------------------------------------------------------------- R29 符剑 · 符力
## 某一段是不是远程段（远程段不产生刀锋判定，改为射出一道符）
static func stage_is_ranged(id: String, n: int) -> bool:
	return bool(stage_of(id, n).get("ranged", false))


## 这把武器有没有远程段（HUD / 自测用来判断要不要画符力条）
static func has_ranged_stage(id: String) -> bool:
	for st in combo_of(id):
		if bool(st.get("ranged", false)):
			return true
	return false


## 连招里一共几段远程（符剑 = 2）
static func ranged_count(id: String) -> int:
	var n := 0
	for st in combo_of(id):
		if bool(st.get("ranged", false)):
			n += 1
	return n
