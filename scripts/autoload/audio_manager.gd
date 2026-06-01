extends Node
##
## Centralised audio. SFX pool + verified music start.
## Display/window concerns now live in DisplayManager.
##

const MASTER_BUS_NAME: String = "Master"
const MIN_AUDIBLE_LINEAR: float = 0.0001
const SFX_PLAYER_COUNT: int = 10
const MUSIC_VERIFY_DELAY: float = 0.35

const MUSIC_STREAMS: Dictionary = {
	"menu": preload("res://assets/audio/music/menu_loop.wav"),
	"run": preload("res://assets/audio/music/run_loop.wav"),
}
const SFX_STREAMS: Dictionary = {
	"shoot": preload("res://assets/audio/sfx/shoot.wav"),
	"enemy_hit": preload("res://assets/audio/sfx/enemy_hit.wav"),
	"enemy_die": preload("res://assets/audio/sfx/enemy_die.wav"),
	"xp_pickup": preload("res://assets/audio/sfx/xp_pickup.wav"),
	"card_pickup": preload("res://assets/audio/sfx/card_pickup.wav"),
	"player_hit": preload("res://assets/audio/sfx/player_hit.wav"),
	"player_defeat": preload("res://assets/audio/sfx/player_defeat.wav"),
	"level_up": preload("res://assets/audio/sfx/level_up.wav"),
	"hand_lock": preload("res://assets/audio/sfx/hand_lock.wav"),
	"boss_defeat": preload("res://assets/audio/sfx/boss_defeat.wav"),
	"ending_good": preload("res://assets/audio/sfx/ending_good.wav"),
	"ending_bad": preload("res://assets/audio/sfx/ending_bad.wav"),
}
const SFX_THROTTLES: Dictionary = {
	"shoot": 0.02,
	"enemy_hit": 0.03,
	"enemy_die": 0.04,
	"xp_pickup": 0.04,
	"card_pickup": 0.07,
	"player_hit": 0.10,
}
const MUSIC_GAIN_DB: Dictionary = {
	"menu": 4.0,
	"run": 2.0,
}
const SFX_GAIN_DB: Dictionary = {
	"shoot": 5.0,
	"enemy_hit": 6.0,
	"enemy_die": 4.0,
	"xp_pickup": 8.0,
	"card_pickup": 6.0,
	"player_hit": 5.0,
	"player_defeat": 3.0,
	"level_up": 4.0,
	"hand_lock": 4.0,
	"boss_defeat": 3.0,
	"ending_good": 3.0,
	"ending_bad": 3.0,
}

var _master_bus_index: int = -1
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_cursor: int = 0
var _sfx_last_played_at: Dictionary = {}
var _music_player: AudioStreamPlayer
var _current_music_id: String = ""


func _ready() -> void:
	_master_bus_index = AudioServer.get_bus_index(MASTER_BUS_NAME)
	_ensure_music_player()
	_ensure_sfx_players()
	apply_saved_volume()


# -- Volume ---------------------------------------------------------------

func apply_saved_volume() -> void:
	set_master_volume_percent(SaveManager.get_master_volume_percent(100), false)


func get_master_volume_percent() -> int:
	return SaveManager.get_master_volume_percent(100)


func set_master_volume_percent(percent: int, persist: bool = true) -> void:
	var safe_percent: int = clampi(percent, 0, 100)
	if _master_bus_index == -1:
		_master_bus_index = AudioServer.get_bus_index(MASTER_BUS_NAME)
	if _master_bus_index != -1:
		if safe_percent <= 0:
			AudioServer.set_bus_mute(_master_bus_index, true)
			AudioServer.set_bus_volume_db(_master_bus_index, linear_to_db(MIN_AUDIBLE_LINEAR))
		else:
			AudioServer.set_bus_mute(_master_bus_index, false)
			var linear: float = max(float(safe_percent) / 100.0, MIN_AUDIBLE_LINEAR)
			AudioServer.set_bus_volume_db(_master_bus_index, linear_to_db(linear))
	if persist:
		SaveManager.set_master_volume_percent(safe_percent)


# -- SFX ------------------------------------------------------------------

func play_sfx(sfx_id: String, pitch_scale: float = 1.0, volume_db: float = 0.0) -> void:
	var stream: AudioStream = SFX_STREAMS.get(sfx_id, null)
	if stream == null or _should_throttle_sfx(sfx_id):
		return
	if _sfx_players.is_empty():
		return
	var player: AudioStreamPlayer = _sfx_players[_sfx_cursor]
	_sfx_cursor = wrapi(_sfx_cursor + 1, 0, _sfx_players.size())
	player.stop()
	player.stream = stream
	player.pitch_scale = pitch_scale
	player.volume_db = volume_db + float(SFX_GAIN_DB.get(sfx_id, 0.0))
	player.play()


# -- Music ----------------------------------------------------------------

func play_music(music_id: String, base_volume_db: float = -14.0) -> void:
	var stream: AudioStream = MUSIC_STREAMS.get(music_id, null)
	if stream == null:
		return
	_ensure_music_player()
	if _current_music_id == music_id and _music_player.playing:
		return
	_current_music_id = music_id
	_music_player.stop()
	_music_player.stream = _make_looping_stream(stream)
	_music_player.volume_db = base_volume_db + float(MUSIC_GAIN_DB.get(music_id, 0.0))
	_music_player.play()
	call_deferred("_verify_music_playback", music_id)


func stop_music() -> void:
	_current_music_id = ""
	if _music_player != null:
		_music_player.stop()


# -- Music helpers --------------------------------------------------------

func _verify_music_playback(music_id: String) -> void:
	await get_tree().create_timer(MUSIC_VERIFY_DELAY, false, false, true).timeout
	if not is_instance_valid(_music_player) or _current_music_id != music_id:
		return
	var stuck: bool = (
		_music_player.stream != null
		and (_music_player.stream_paused
			or not _music_player.playing
			or _music_player.get_playback_position() < 0.05)
	)
	if stuck:
		_music_player.stop()
		_music_player.stream_paused = false
		_music_player.play()


func _ensure_sfx_players() -> void:
	if not _sfx_players.is_empty():
		return
	for _index in range(SFX_PLAYER_COUNT):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = MASTER_BUS_NAME
		add_child(player)
		_sfx_players.append(player)


func _ensure_music_player() -> void:
	if _music_player != null:
		return
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = MASTER_BUS_NAME
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music_player)


func _should_throttle_sfx(sfx_id: String) -> bool:
	if not SFX_THROTTLES.has(sfx_id):
		return false
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var min_interval: float = float(SFX_THROTTLES.get(sfx_id, 0.0))
	var last: float = float(_sfx_last_played_at.get(sfx_id, -9999.0))
	if now - last < min_interval:
		return true
	_sfx_last_played_at[sfx_id] = now
	return false


func _make_looping_stream(stream: AudioStream) -> AudioStream:
	if stream is AudioStreamWAV:
		var wav: AudioStreamWAV = (stream as AudioStreamWAV).duplicate(true)
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		return wav
	return stream
