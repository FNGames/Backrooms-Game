extends Node2D

const MAX_PLAYERS = 4
const DEFAULT_PORT = 7000 # For LAN mode

@export var player_scene: PackedScene
@export var scrap_scene: PackedScene 
@export var wall_scene: PackedScene 

# UI Nodes
@onready var lobby_ui = $CanvasLayer/LobbyUI
@onready var players_container = $Players
@onready var code_entry = $CanvasLayer/LobbyUI/VBoxContainer/CodeEntry
@onready var status_label = $CanvasLayer/LobbyUI/VBoxContainer/StatusLabel
@onready var vbox = $CanvasLayer/LobbyUI/VBoxContainer
@onready var host_button = $CanvasLayer/LobbyUI/VBoxContainer/HostButton
@onready var join_button = $CanvasLayer/LobbyUI/VBoxContainer/JoinButton

# NEW: Hybrid Peer (Can be NodeTunnel OR ENet)
var peer: MultiplayerPeer 

# NEW: Toggle for mode
var relay_checkbox: CheckBox

func _ready():
	print("--- CUSTOM NETWORK MANAGER LOADED ---") # LOOK FOR THIS IN OUTPUT!
	
	# Clean up old UI artifacts if they exist
	if has_node("CanvasLayer/LobbyUI/VBoxContainer/AddressEntry"):
		$CanvasLayer/LobbyUI/VBoxContainer/AddressEntry.queue_free()
	
	# Setup UI
	_setup_extra_ui()
	_update_ui_for_mode() # Set initial state
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	_setup_spawner()

func _setup_spawner():
	var spawner = MultiplayerSpawner.new()
	add_child(spawner)
	spawner.spawn_path = players_container.get_path()
	if player_scene: spawner.add_spawnable_scene(player_scene.resource_path)
	if scrap_scene: spawner.add_spawnable_scene(scrap_scene.resource_path)
	if wall_scene: spawner.add_spawnable_scene(wall_scene.resource_path)

func _setup_extra_ui():
	# Create the toggle for Online vs LAN
	relay_checkbox = CheckBox.new()
	relay_checkbox.text = "Use Online Relay (Internet)"
	relay_checkbox.button_pressed = true # Default to trying Online
	relay_checkbox.toggled.connect(_on_mode_toggled)
	
	# Add to top of VBox
	vbox.add_child(relay_checkbox)
	vbox.move_child(relay_checkbox, 0)

func _on_mode_toggled(pressed):
	_update_ui_for_mode()

func _update_ui_for_mode():
	if relay_checkbox.button_pressed:
		code_entry.placeholder_text = "Paste Host ID Here"
		status_label.text = "Mode: Online Relay (No Port Forwarding needed)"
	else:
		code_entry.placeholder_text = "Enter IP Address (e.g. 127.0.0.1)"
		status_label.text = "Mode: Local LAN (Direct IP)"
	status_label.modulate = Color(1, 1, 1)

# --- HOSTING LOGIC ---
func _on_host_button_pressed():
	_toggle_ui(false)
	
	# CASE A: RELAY MODE
	if relay_checkbox.button_pressed:
		_host_relay()
	# CASE B: LAN MODE
	else:
		_host_lan()

func _host_relay():
	status_label.text = "Connecting to Relay IP (97.107.137.81)..."
	status_label.modulate = Color(1, 1, 0) # Yellow
	
	peer = NodeTunnelPeer.new()
	# Listen for errors
	if peer.has_signal("relay_connect_error"):
		peer.relay_connect_error.connect(_on_relay_error)
	
	# FIX: FORCE IP ADDRESS
	# We use the raw IP to bypass Godot's DNS/IPv6 issues
	print("DEBUG: Connecting to IP 97.107.137.81:9998...")
	peer.connect_to_relay("97.107.137.81", 9998)
	
	# Safety Timer
	var timer = get_tree().create_timer(10.0)
	timer.timeout.connect(func():
		if status_label.text.begins_with("Connecting"):
			status_label.text = "Error: IP Connection Failed.\n(Handshake stuck on IP 97.107.137.81)"
			status_label.modulate = Color(1, 0, 0)
			_toggle_ui(true)
			peer = null
	)
	
	# This is where it hangs if you run the wrong file
	await peer.relay_connected
	if peer == null: return
	
	print("DEBUG: Relay Connected! Creating Server...")
	var error = peer.create_server(MAX_PLAYERS)
	if error != OK:
		status_label.text = "Error hosting: " + str(error)
		_toggle_ui(true)
		return
		
	_finalize_connection()
	
	var my_id = peer.online_id
	DisplayServer.clipboard_set(my_id) 
	status_label.text = "Hosting (Relay)! ID Copied.\nID: " + str(my_id)
	status_label.modulate = Color(0, 1, 0)
	code_entry.text = str(my_id)

func _host_lan():
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(DEFAULT_PORT, MAX_PLAYERS)
	if error != OK:
		status_label.text = "Error hosting LAN: " + str(error)
		_toggle_ui(true)
		return
	
	_finalize_connection()
	status_label.text = "Hosting (LAN) on Port " + str(DEFAULT_PORT)
	status_label.modulate = Color(0, 1, 0)

# --- JOINING LOGIC ---
func _on_join_button_pressed():
	var input_text = code_entry.text.strip_edges()
	if input_text == "":
		status_label.text = "Please enter ID or IP!"
		return
		
	_toggle_ui(false)
	
	if relay_checkbox.button_pressed:
		_join_relay(input_text)
	else:
		_join_lan(input_text)

func _join_relay(host_id):
	status_label.text = "Connecting to Relay..."
	status_label.modulate = Color(1, 1, 0)
	
	peer = NodeTunnelPeer.new()
	if peer.has_signal("relay_connect_error"):
		peer.relay_connect_error.connect(_on_relay_error)

	print("DEBUG: Connecting to IP 97.107.137.81:9998...")
	peer.connect_to_relay("97.107.137.81", 9998)
	
	var timer = get_tree().create_timer(10.0)
	timer.timeout.connect(func():
		if status_label.text.begins_with("Connecting"):
			status_label.text = "Error: IP Connection Failed.\n(Handshake stuck on IP 97.107.137.81)"
			status_label.modulate = Color(1, 0, 0)
			_toggle_ui(true)
			peer = null
	)
	
	await peer.relay_connected
	if peer == null: return
	
	print("DEBUG: Relay Connected! Finding Host...")
	status_label.text = "Finding Host..."
	var error = peer.create_client(host_id)
	if error != OK:
		status_label.text = "Error joining: " + str(error)
		_toggle_ui(true)
		return
	
	_finalize_connection()
	status_label.text = "Connecting to Game..."

func _join_lan(ip_address):
	# If empty, default to localhost
	if ip_address == "": ip_address = "127.0.0.1"
	
	status_label.text = "Connecting to LAN IP..."
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip_address, DEFAULT_PORT)
	if error != OK:
		status_label.text = "Error joining LAN: " + str(error)
		_toggle_ui(true)
		return
		
	_finalize_connection()

# --- COMMON CONNECTION FINALIZATION ---
func _finalize_connection():
	multiplayer.multiplayer_peer = peer
	if multiplayer.is_server():
		lobby_ui.hide()
		spawn_player(1)
		_spawn_level_scrap()

func _on_relay_error():
	print("DEBUG: Immediate Relay Error Signal Received")
	status_label.text = "Connection Refused.\nFirewall blocked Port 9998 or Server Down."
	status_label.modulate = Color(1, 0, 0)
	_toggle_ui(true)
	peer = null

# --- STANDARD MULTIPLAYER EVENTS ---

func _on_peer_connected(id): 
	if multiplayer.is_server(): spawn_player(id)

func _on_peer_disconnected(id): 
	if multiplayer.is_server() and players_container.has_node(str(id)): 
		players_container.get_node(str(id)).queue_free()

func _on_connected_to_server():
	status_label.text = "Connected!"
	status_label.modulate = Color(0, 1, 0)
	lobby_ui.hide()
	_toggle_ui(true)

func _on_connection_failed():
	status_label.text = "Connection Failed."
	status_label.modulate = Color(1, 0, 0)
	multiplayer.multiplayer_peer = null
	_toggle_ui(true)

func _on_server_disconnected():
	leave_game()
	status_label.text = "Host Disconnected."

func leave_game():
	if peer: peer.close()
	multiplayer.multiplayer_peer = null
	lobby_ui.show()
	_toggle_ui(true)
	for child in players_container.get_children(): child.queue_free()

func _toggle_ui(enabled: bool):
	host_button.disabled = !enabled
	join_button.disabled = !enabled
	code_entry.editable = enabled
	relay_checkbox.disabled = !enabled

func spawn_player(id):
	var player = player_scene.instantiate()
	player.name = str(id)
	players_container.add_child(player, true) 
	player.global_position = Vector2(randf_range(100, 900), randf_range(100, 500))

func _spawn_level_scrap():
	if not scrap_scene: return
	for i in range(5):
		var pile = scrap_scene.instantiate()
		pile.name = "Scrap_" + str(randi())
		pile.global_position = Vector2(randf_range(100, 900), randf_range(100, 500))
		players_container.add_child(pile, true)
