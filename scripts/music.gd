extends Node
## R34：背景音乐管理 —— 钟主题环境 BGM，按场景切换并交叉淡入淡出，循环播放。
## 曲目：title / explore / boss / daily（res://music/*.wav，程序化生成）。

const TRACKS := ["title", "explore", "boss", "daily"]
var streams := {}
var _a: AudioStreamPlayer
var _b: AudioStreamPlayer
var _active: AudioStreamPlayer = null   # 当前正在播的播放器
var _fade_in: AudioStreamPlayer = null  # 正在淡入的播放器
var _fade_out: AudioStreamPlayer = null # 正在淡出的旧播放器
var _cur := ""                          # 当前曲目名（与 _active 同步，供测试/状态用）
var _vol := -9.0                        # 总音量 dB
var _muted := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for t in TRACKS:
		var p := "res://music/%s.wav" % t
		if ResourceLoader.exists(p):
			var s = load(p)
			if s is AudioStreamWAV:
				s.loop_mode = AudioStreamWAV.LOOP_FORWARD   # 整段循环，loop 点由生成时保证无缝
			streams[t] = s
	_a = AudioStreamPlayer.new(); add_child(_a); _a.volume_db = -80.0
	_b = AudioStreamPlayer.new(); add_child(_b); _b.volume_db = -80.0

## 切到某曲目：同曲忽略；否则旧曲淡出、新曲淡入
func play(track: String) -> void:
	if not streams.has(track):
		return
	var s = streams[track]
	if s == null:
		return
	if _cur == track:
		return
	var incoming: AudioStreamPlayer = _b if _active == _a else _a
	if _active != null and _active.playing:
		_fade_out = _active
	_active = incoming
	_cur = track
	incoming.stream = streams[track]
	incoming.volume_db = -80.0
	incoming.play()
	_fade_in = incoming

## 停止全部（淡出当前曲）
func stop() -> void:
	if _active != null and _active.playing:
		_fade_out = _active
	_active = null
	_cur = ""
	_fade_in = null

func set_volume(db: float) -> void:
	_vol = db

func toggle_mute() -> bool:
	_muted = not _muted
	if _muted:
		_a.volume_db = -80.0
		_b.volume_db = -80.0
	return _muted

func _process(delta: float) -> void:
	if _fade_in != null and _fade_in.playing:
		_fade_in.volume_db = move_toward(_fade_in.volume_db, _vol, 70.0 * delta)
		if absf(_fade_in.volume_db - _vol) < 0.5:
			_fade_in.volume_db = _vol
			_fade_in = null
	if _fade_out != null:
		_fade_out.volume_db = move_toward(_fade_out.volume_db, -80.0, 70.0 * delta)
		if _fade_out.volume_db <= -79.0:
			_fade_out.stop()
			_fade_out = null
