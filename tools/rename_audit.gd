extends SceneTree
## R17 · 旧词审计
##
## 扫 res://scripts 下所有 .gd（注释先剥掉，只看真正会显示/生效的字符串），
## 命中「修仙化之前的旧词」就 push_warning，最后汇总。
##
## 用途：每次改文案后跑一次，确认「修仙化」没漏、也没被回滚。
##   D:\Godot\Godot_v4.7.2-stable_win64_console.exe --headless --path D:\XUANJIE \
##       --script res://tools/rename_audit.gd
##
## 退出码：0 = 零命中；1 = 有命中（CI / bat 里可以直接判）。
##
## 注意：单字「里 / 外」不能裸扫（「这里」「外面」满地都是），
## 所以只按带引号的字面量 "\"里\"" / "\"外\"" 精确抓深度条那两个标签。

const SCAN_DIRS := ["res://scripts"]

## 旧词表（左 = 修仙化之前的写法，右 = 现在的说法，只用于日志提示）
const OLD_TERMS := [
	# ---- Boss / 敌人改名 ----
	["大剑守卫", "镇钟力士"],
	["深渊剑主", "剑冢守"],
	["守陵人", "尸解仙·无相"],
	["玄界之影", "域外天魔"],
	["影渊剑客", "前世身"],
	["影渊", "魔渊 / 剑冢"],
	["哨兵", "道兵傀儡"],
	["游魂", "阴魂"],
	# ---- 数值 / 机制名词 ----
	["生命", "气血"],
	["耐力", "灵力"],
	["灵魂", "道蕴"],
	["架势", "护体罡气"],
	["破绽", "道心失守"],
	["拼刀", "剑意交锋"],
	["遗物", "法宝"],
	# ---- 界面 / 流程文案 ----
	["每日试炼", "今日道劫"],
	["落闸", "禁制"],
	["关卡一", "镇钟廊"],
	["关卡二", "剑冢阶"],
	["关卡三", "尸解墓道"],
	["关卡四", "天门"],
	["通关", "飞升"],
	# ---- 位次 / 套装 ----
	["刃 之 套", "剑道"],
	["壁 之 套", "体道"],
	["灵 之 套", "灵道"],
	["刃之套", "剑道"],
	["壁之套", "体道"],
	["灵之套", "灵道"],
	# ---- 深度轴的两个标签（精确到带引号的字面量）----
	["\"里\"", "\"阴\""],
	["\"外\"", "\"阳\""],
]

var _hits: Array = []


func _initialize() -> void:
	var files := 0
	for d in SCAN_DIRS:
		files += _scan_dir(str(d))
	_report(files)
	quit(0 if _hits.is_empty() else 1)


func _scan_dir(path: String) -> int:
	var da := DirAccess.open(path)
	if da == null:
		push_warning("[rename_audit] 打不开目录 %s" % path)
		return 0
	var n := 0
	for f in da.get_files():
		if not f.ends_with(".gd"):
			continue
		n += 1
		_scan_file(path.path_join(f))
	return n


func _scan_file(path: String) -> void:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		push_warning("[rename_audit] 打不开文件 %s" % path)
		return
	var ln := 0
	while not fa.eof_reached():
		var raw := fa.get_line()
		ln += 1
		var code := _strip_comment(raw)
		if code.strip_edges() == "":
			continue
		for pair in OLD_TERMS:
			var old := str(pair[0])
			if code.find(old) >= 0:
				_hits.append({"file": path, "line": ln, "old": old, "new": str(pair[1])})
				push_warning("[rename_audit] %s:%d 旧词「%s」→ 应为「%s」"
					% [path.get_file(), ln, old, str(pair[1])])
	fa.close()


## 把行尾注释切掉（引号内的 # 不算注释）
func _strip_comment(line: String) -> String:
	var in_str := false
	var esc := false
	var i := 0
	while i < line.length():
		var ch := line[i]
		if esc:
			esc = false
		elif ch == "\\":
			esc = true
		elif ch == "\"":
			in_str = not in_str
		elif ch == "#" and not in_str:
			return line.substr(0, i)
		i += 1
	return line


func _report(files: int) -> void:
	print("")
	print("========== R17 旧词审计 ==========")
	print("扫描 %d 个 .gd，旧词 %d 条" % [files, OLD_TERMS.size()])
	if _hits.is_empty():
		print("PASS R17 旧词审计：0 命中")
		print("==================================")
		return
	print("FAIL R17 旧词审计：%d 处命中" % _hits.size())
	for h in _hits:
		print("  %s:%d  「%s」→「%s」"
			% [str(h["file"]), int(h["line"]), str(h["old"]), str(h["new"])])
	print("==================================")
