extends Node
## Original local soundtrack. No network or API credential is used by the game.

const TRACKS = preload("res://scripts/soundtrack_playlist.gd").TRACKS
var settings_path := "user://soundtrack.cfg"
const MUSIC_VOLUME_DB = -17.0
const Keys = preload("res://scripts/ui/keys.gd")
var player: AudioStreamPlayer
var track_index := -1
var muted := false
var fade: Tween
## One music player for the whole game, kept at the tree root under this name.
## Every scene (main menu, game) has its own Soundtrack node, but they all
## steer this one player, so a scene change and the loading screen do not
## start the piece anew. Removing a player from the tree stops it, so it is
## never reparented.
const SHARED_PLAYER = "MusicPlayer"

func _ready() -> void:
	# Keep captures, benchmarks and headless runs free of audio work.
	if DisplayServer.get_name() == "headless" or "--mute-music" in OS.get_cmdline_user_args():
		set_process_unhandled_key_input(false)
		return
	var settings := ConfigFile.new()
	if settings.load(settings_path) == OK:
		muted = bool(settings.get_value("music", "muted", false))
	player = get_tree().root.get_node_or_null(SHARED_PLAYER) as AudioStreamPlayer
	if player:
		# the piece of the scene before plays on
		track_index = int(player.get_meta("track_index", -1))
		_steer_player()
		if muted:
			player.stop()
		elif not player.playing:
			play_next()
		return
	player = AudioStreamPlayer.new()
	player.name = SHARED_PLAYER
	player.process_mode = Node.PROCESS_MODE_ALWAYS # plays on in the pause menu
	_steer_player()
	# the root is busy adding this scene: join it next idle step, then play
	get_tree().root.add_child.call_deferred(player)
	if not muted:
		play_next.call_deferred()

func _steer_player() -> void:
	for link in player.finished.get_connections():
		player.finished.disconnect(link.callable)
	player.finished.connect(play_next)

func _exit_tree() -> void:
	if is_instance_valid(player) and player.finished.is_connected(play_next):
		player.finished.disconnect(play_next)

func play_next() -> void:
	if not is_instance_valid(player) or muted or not player.is_inside_tree():
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
		player.set_meta("track_index", track_index)
		# the tween hangs on the player so it outlives a scene change
		fade = player.create_tween()
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
	if Keys.pressed(event, "apoleia_music"):
		toggle_mute()
		get_viewport().set_input_as_handled()
	elif Keys.pressed(event, "apoleia_next_song"):
		play_next()
		get_viewport().set_input_as_handled()
