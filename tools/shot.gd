extends SceneTree
## 截图小工具（R17 起用于「一屏不超过 2 个新词」的人工验收留档）
##
##   godot --path D:\XUANJIE --resolution 1280x720 --script res://tools/shot.gd \
##       -- --out=res://预览_R17_标题.png --frames=20
##
##   --call=_enter_level:0,_enter_room:0,_enter_pause
##       逗号分隔，按顺序每帧调一个；"方法:参数" 里的参数是整数就转 int，否则当字符串
##
## 注意：必须**不带 --headless**（要真的渲染一帧）。窗口会闪一下再自动退出。

var _f := 0
var _target := 20
var _out := "res://预览_R17_标题.png"
var _calls: Array = []
var _arg := ""
var _argi := 0
var _has_argi := false
var _main: Node = null


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--frames="):
			_target = int(a.substr(9))
		elif a.begins_with("--call="):
			for m in a.substr(7).split(",", false):
				_calls.append(str(m))
		elif a.begins_with("--arg="):
			_arg = a.substr(6)
		elif a.begins_with("--argi="):
			_argi = int(a.substr(7))
			_has_argi = true
	var ps: PackedScene = load("res://scenes/Main.tscn")
	if ps == null:
		print("[shot] 载入 Main.tscn 失败")
		quit(1)
		return
	_main = ps.instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_f += 1
	# 第 4 帧开始驱动（等 _ready 跑完），每帧调一个，给状态机留出时间
	if _f >= 4 and _f < 4 + _calls.size():
		var spec := str(_calls[_f - 4])
		var m := spec
		var has := false
		var val := ""
		var k := spec.find(":")
		if k >= 0:
			m = spec.substr(0, k)
			val = spec.substr(k + 1)
			has = true
		if _main != null and _main.has_method(m):
			if has:
				_main.call(m, val.to_int() if val.is_valid_int() else val)
			else:
				_main.call(m)
			print("[shot] call %s(%s)" % [m, val])
		else:
			print("[shot] 没有方法 [%s] len=%d spec=[%s] main=%s" % [m, m.length(), spec, str(_main)])
		return false
	if _f < _target:
		return false
	var img: Image = root.get_texture().get_image()
	if img == null:
		print("[shot] 取不到画面")
		quit(1)
		return true
	var err := img.save_png(_out)
	print("[shot] %s → %s (%dx%d)" % [str(err), _out, img.get_width(), img.get_height()])
	quit(0)
	return true
