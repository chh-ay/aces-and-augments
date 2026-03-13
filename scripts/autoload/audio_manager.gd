extends Node

const MASTER_BUS_NAME: String = "Master"
const MIN_AUDIBLE_LINEAR: float = 0.0001
const SFX_PLAYER_COUNT: int = 10
const MUSIC_STREAMS: Dictionary = {
	"menu": preload("res://assets/audio/music/menu_loop.wav"),
	"run": preload("res://assets/audio/music/run_loop.wav")
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
	"ending_bad": preload("res://assets/audio/sfx/ending_bad.wav")
}
const SFX_THROTTLES: Dictionary = {
	"shoot": 0.02,
	"enemy_hit": 0.03,
	"enemy_die": 0.04,
	"xp_pickup": 0.04,
	"card_pickup": 0.07,
	"player_hit": 0.10
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
	apply_saved_settings()

func apply_saved_settings() -> void:
	var save_manager: Node = _get_save_manager()
	if save_manager == null:
		return
	if save_manager.has_method("get_master_volume_percent"):
		set_master_volume_percent(int(save_manager.call("get_master_volume_percent", 100)))
	if save_manager.has_method("get_fullscreen_enabled"):
		set_fullscreen_enabled(bool(save_manager.call("get_fullscreen_enabled", false)))

func get_master_volume_percent() -> int:
	var save_manager: Node = _get_save_manager()
	if save_manager != null and save_manager.has_method("get_master_volume_percent"):
		return int(save_manager.call("get_master_volume_percent", 100))
	return 100

func set_master_volume_percent(percent: int) -> void:
	var safe_percent: int = clampi(percent, 0, 100)
	if _master_bus_index == -1:
		_master_bus_index = AudioServer.get_bus_index(MASTER_BUS_NAME)
	if _master_bus_index != -1:
		if safe_percent <= 0:
			AudioServer.set_bus_mute(_master_bus_index, true)
			AudioServer.set_bus_volume_db(_master_bus_index, linear_to_db(MIN_AUDIBLE_LINEAR))
		else:
			AudioServer.set_bus_mute(_master_bus_index, false)
			AudioServer.set_bus_volume_db(_master_bus_index, linear_to_db(max(float(safe_percent) / 100.0, MIN_AUDIBLE_LINEAR)))
	var save_manager: Node = _get_save_manager()
	if save_manager != null and save_manager.has_method("set_master_volume_percent"):
		save_manager.call("set_master_volume_percent", safe_percent)

func get_fullscreen_enabled() -> bool:
	var window: Window = _get_game_window()
	if window == null:
		return false
	return window.mode == Window.MODE_FULLSCREEN or window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN

func can_change_display_mode() -> bool:
	return not OS.has_feature("editor")

func get_display_mode_hint() -> String:
	if can_change_display_mode():
		return "Windowed or fullscreen"
	return "Disabled while running embedded in the editor"

func set_fullscreen_enabled(is_enabled: bool) -> void:
	if not can_change_display_mode():
		return
	var window: Window = _get_game_window()
	if window != null:
		window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN if is_enabled else Window.MODE_WINDOWED
		if not is_enabled:
			window.move_to_center()
	var save_manager: Node = _get_save_manager()
	if save_manager != null and save_manager.has_method("set_fullscreen_enabled"):
		save_manager.call("set_fullscreen_enabled", is_enabled)

func play_sfx(sfx_id: String, pitch_scale: float = 1.0, volume_db: float = 0.0) -> void:
	var stream: AudioStream = SFX_STREAMS.get(sfx_id, null)
	if stream == null:
		return
	if _should_throttle_sfx(sfx_id):
		return
	_ensure_sfx_players()
	if _sfx_players.is_empty():
		return
	var player: AudioStreamPlayer = _sfx_players[_sfx_cursor]
	_sfx_cursor = wrapi(_sfx_cursor + 1, 0, _sfx_players.size())
	player.stop()
	player.stream = stream
	player.pitch_scale = pitch_scale
	player.volume_db = volume_db
	player.play()

func play_music(music_id: String, volume_db: float = -14.0) -> void:
	var stream: AudioStream = MUSIC_STREAMS.get(music_id, null)
	if stream == null:
		return
	_ensure_music_player()
	if _music_player == null:
		return
	if _current_music_id == music_id and _music_player.playing:
		return
	_current_music_id = music_id
	_music_player.stop()
	_music_player.stream = _make_looping_stream(stream)
	_music_player.volume_db = volume_db
	_music_player.play()

func stop_music() -> void:
	_current_music_id = ""
	if _music_player != null:
		_music_player.stop()

func _get_save_manager() -> Node:
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop == null:
		return null
	var scene_tree: SceneTree = main_loop as SceneTree
	if scene_tree == null:
		return null
	return scene_tree.root.get_node_or_null("SaveManager")

func _get_game_window() -> Window:
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop == null:
		return null
	var scene_tree: SceneTree = main_loop as SceneTree
	if scene_tree == null:
		return null
	return scene_tree.root

func _ensure_sfx_players() -> void:
	if not _sfx_players.is_empty():
		return
	for _index in range(SFX_PLAYER_COUNT):
		var player := AudioStreamPlayer.new()
		player.bus = MASTER_BUS_NAME
		add_child(player)
		_sfx_players.append(player)

func _ensure_music_player() -> void:
	if _music_player != null:
		return
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = MASTER_BUS_NAME
	add_child(_music_player)

func _should_throttle_sfx(sfx_id: String) -> bool:
	if not SFX_THROTTLES.has(sfx_id):
		return false
	var now_seconds: float = float(Time.get_ticks_msec()) / 1000.0
	var min_interval: float = float(SFX_THROTTLES.get(sfx_id, 0.0))
	var last_seconds: float = float(_sfx_last_played_at.get(sfx_id, -9999.0))
	if now_seconds - last_seconds < min_interval:
		return true
	_sfx_last_played_at[sfx_id] = now_seconds
	return false

func _make_looping_stream(stream: AudioStream) -> AudioStream:
	if stream is AudioStreamWAV:
		var wav_stream: AudioStreamWAV = (stream as AudioStreamWAV).duplicate(true)
		wav_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		return wav_stream
	return stream
