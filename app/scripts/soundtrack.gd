extends Node
## Original local soundtrack. No network or API credential is used by the game.

const TRACKS = preload("res://scripts/soundtrack_playlist.gd").TRACKS
var settings_path := "user://soundtrack.cfg"
const MUSIC_VOLUME_DB = -17.0
var player: AudioStreamPlayer
var track_index := -1
var muted := false
var fade: Tween

func _ready() -> void:
	# Keep captures, benchmarks and headless runs free of audio work.
	if DisplayServer.get_name() == "headless" or "--mute-music" in OS.get_cmdline_user_args():
		set_process_unhandled_key_input(false)
		return
	var settings := ConfigFile.new()
	if settings.load(settings_path) == OK:
		muted = bool(settings.get_value("music", "muted", false))
	player = AudioStreamPlayer.new()
	player.name = "MusicPlayer"
	add_child(player)
	player.finished.connect(play_next)
	if not muted:
		play_next()

func play_next() -> void:
	if not is_instance_valid(player) or muted:
		return
	if fade:
		fade.kill()
	player.stop()
	# Skip absent/invalid assets; a missing soundtrack must never prevent play.
	for attempt in range(TRACKS.size()):
		track_index = (track_index + 1) % TRACKS.size()
		if not FileAccess.file_exists(TRACKS[track_index]):
			continue
		var stream := AudioStreamMP3.new()
		stream.data = FileAccess.get_file_as_bytes(TRACKS[track_index])
		if stream.get_length() <= 0.0:
			continue
		player.stream = stream
		player.volume_db = -60.0
		player.play()
		fade = create_tween()
		fade.tween_property(player, "volume_db", MUSIC_VOLUME_DB, 1.2)
		return

func toggle_mute() -> void:
	muted = not muted
	var settings := ConfigFile.new()
	settings.set_value("music", "muted", muted)
	settings.save(settings_path)
	if muted:
		if fade:
			fade.kill()
		player.stop()
	else:
		# Restart the current track after unmuting.
		if track_index >= 0:
			track_index -= 1
		play_next()

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_instance_valid(player) or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_M:
		toggle_mute()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_N:
		play_next()
		get_viewport().set_input_as_handled()
