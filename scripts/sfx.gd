extends Node
## 程序化音效播放池。

const NAMES := [
	"slash", "clash", "clash_perfect", "hit", "hurt", "jump",
	"land", "dash", "death", "heal", "boss", "gate", "thunder",
]

var streams := {}
var _players: Array = []
var _idx := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in NAMES:
		var p := "res://sfx/%s.wav" % n
		if ResourceLoader.exists(p):
			streams[n] = load(p)
	for i in 18:
		var ap := AudioStreamPlayer.new()
		add_child(ap)
		_players.append(ap)


func play(n: String, pitch: float = 1.0, vol_db: float = 0.0) -> void:
	if not streams.has(n):
		return
	if _players.is_empty():
		return
	var ap: AudioStreamPlayer = _players[_idx]
	_idx = (_idx + 1) % _players.size()
	ap.stream = streams[n]
	ap.pitch_scale = clampf(pitch, 0.3, 3.0)
	ap.volume_db = vol_db
	ap.play()


func play_rand(n: String, lo: float = 0.92, hi: float = 1.08, vol_db: float = 0.0) -> void:
	play(n, randf_range(lo, hi), vol_db)
