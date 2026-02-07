extends Node2D

const DEFAULT_PORT = 7000
const MAX_PLAYERS = 4
const BROADCAST_PORT = 8911 

@export var player_scene: PackedScene
@export var scrap_scene: PackedScene 
@export var wall_scene: PackedScene 

# UI Nodes
@onready var lobby_ui = $CanvasLayer/LobbyUI
@onready var players_container = $Players
@onready var code_entry = $CanvasLayer/LobbyUI/VBoxContainer/CodeEntry
@onready var status_label = $CanvasLayer/LobbyUI/VBoxContainer/StatusLabel
@onready var vbox = $CanvasLayer/LobbyUI/VBoxContainer

# Dynamic UI Nodes
var address_entry: LineEdit 
var lobby_name_entry: LineEdit 
var server_list: VBoxContainer
var refresh_button: Button

var peer = ENetMultiplayerPeer.new()

# Broadcast Variables
var broadcaster = PacketPeerUDP.new()
var listener = PacketPeerUDP.new()
var broadcast_timer = Timer.new()
var found_servers = {} 
var listener_bound = false
var bind_retry_timer = Timer.new()

func _ready():
	print("--- HAMACHI LOBBY MANAGER LOADED ---")
	
	_restore_address_entry() 
	_setup_extra_ui() 
	
	code_entry.placeholder_text = "Lobby Code (Changes Port)"
	status_label.text = "Hamachi Mode: Ready"
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	var spawner = MultiplayerSpawner.new()
	add_child(spawner)
	spawner.spawn_path = players_container.get_path()
	if player_scene: spawner.add_spawnable_scene(player_scene.resource_path)
	if scrap_scene: spawner.add_spawnable_scene(scrap_scene.resource_path)
	if wall_scene: spawner.add_spawnable_scene(wall_scene.resource_path)

	broadcaster.set_broadcast_enabled(true)
	broadcaster.set_dest_address("255.255.255.255", BROADCAST_PORT)
	
	broadcast_timer.wait_time = 1.0
	broadcast_timer.timeout.connect(_broadcast_presence)
	add_child(broadcast_timer)
	
	bind_retry_timer.wait_time = 2.0
	bind_retry_timer.timeout.connect(_attempt_bind)
	add_child(bind_retry_timer)
	
	_start_listening()

func _process(delta):
	if listener_bound and listener.get_available_packet_count() > 0:
		var packet = listener.get_packet()
		var data_str = packet.get_string_from_utf8()
		var sender_ip = listener.get_packet_ip()
		
		var data = JSON.parse_string(data_str)
		if data and data.has("name") and data.has("port"):
			var key = sender_ip + ":" + str(data["port"])
			if not found_servers.has(key):
				found_servers[key] = true
				_add_server_button(data["name"], sender_ip, data["port"])

# --- UI SETUP ---
func _restore_address_entry():
	if has_node("CanvasLayer/LobbyUI/VBoxContainer/AddressEntry"):
		address_entry = $CanvasLayer/LobbyUI/VBoxContainer/AddressEntry
	else:
		address_entry = LineEdit.new()
		address_entry.name = "AddressEntry"
		vbox.add_child(address_entry)
		vbox.move_child(address_entry, 1) 
	
	address_entry.placeholder_text = "Host IP (Hamachi IP)"

func _setup_extra_ui():
	lobby_name_entry = LineEdit.new()
	lobby_name_entry.placeholder_text = "Lobby Name (e.g. Mike's Room)"
	vbox.add_child(lobby_name_entry)
	vbox.move_child(lobby_name_entry, 0) 
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)
	
	refresh_button = Button.new()
	refresh_button.text = "Refresh List"
	refresh_button.pressed.connect(_on_refresh_pressed)
	vbox.add_child(refresh_button)
	
	var list_label = Label.new()
	list_label.text = "--- NEARBY LOBBIES ---"
	list_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(list_label)
	
	server_list = VBoxContainer.new()
	vbox.add_child(server_list)

func _add_server_button(name, ip, port):
	var btn = Button.new()
	btn.text = "Join: " + name + " (" + ip + ")"
	btn.pressed.connect(func(): 
		address_entry.text = ip
		_join_game_direct(ip, port)
	)
	server_list.add_child(btn)

# --- HOSTING ---
func _on_host_button_pressed():
	_cleanup_connection()
	
	listener.close()
	listener_bound = false
	bind_retry_timer.stop()
	
	var port = get_port_from_code(code_entry.text)
	
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		status_label.text = "Error hosting: " + str(error)
		_start_listening()
		return
	
	multiplayer.multiplayer_peer = peer
	
	lobby_ui.hide()
	spawn_player(1)
	_spawn_level_scrap()
	
	broadcast_timer.start()
	
	status_label.text = "Hosting on Port " + str(port)
	print("Hosting. Code: " + code_entry.text + " -> Port: " + str(port))

# --- JOINING ---
func _on_join_button_pressed():
	var ip = address_entry.text.strip_edges()
	var port = get_port_from_code(code_entry.text)
	
	if ip == "":
		status_label.text = "Enter Hamachi IP!"
		return
		
	_join_game_direct(ip, port)

func _join_game_direct(ip, port):
	_cleanup_connection()
	
	listener.close()
	listener_bound = false
	bind_retry_timer.stop()
	
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, port)
	if error != OK:
		status_label.text = "Error Joining: " + str(error)
		return
	
	multiplayer.multiplayer_peer = peer
	status_label.text = "Connecting..."

# --- BROADCASTING ---
func _start_listening():
	bind_retry_timer.stop()
	listener.close()
	listener_bound = false
	_attempt_bind()
	if not listener_bound:
		bind_retry_timer.start()

func _attempt_bind():
	if listener_bound: 
		bind_retry_timer.stop()
		return
	var err = listener.bind(BROADCAST_PORT)
	if err == OK:
		listener_bound = true
		bind_retry_timer.stop()
		status_label.text = "Scanning for games..."
	else:
		if bind_retry_timer.is_stopped(): bind_retry_timer.start()

func _broadcast_presence():
	var name_txt = lobby_name_entry.text
	if name_txt == "": name_txt = "Lobby " + code_entry.text
	
	var port = get_port_from_code(code_entry.text)
	
	var data = { "name": name_txt, "port": port }
	var json = JSON.stringify(data)
	broadcaster.put_packet(json.to_utf8_buffer())

func _on_refresh_pressed():
	for child in server_list.get_children(): child.queue_free()
	found_servers.clear()
	_start_listening()

func get_port_from_code(code_text: String) -> int:
	if code_text.strip_edges() == "": return DEFAULT_PORT
	var hashed = code_text.hash()
	return 10000 + (abs(hashed) % 50000)

# --- STANDARD EVENTS ---
func _cleanup_connection():
	if peer: peer.close()
	broadcast_timer.stop()
	multiplayer.multiplayer_peer = null

func _on_peer_connected(id): 
	if multiplayer.is_server(): spawn_player(id)

func _on_peer_disconnected(id): 
	if multiplayer.is_server() and players_container.has_node(str(id)): 
		players_container.get_node(str(id)).queue_free()

func _on_connected_to_server():
	status_label.text = "Connected!"
	lobby_ui.hide()

func _on_connection_failed():
	status_label.text = "Connection Failed."
	multiplayer.multiplayer_peer = null

func _on_server_disconnected():
	_cleanup_connection()
	lobby_ui.show()
	status_label.text = "Host Disconnected."
	for child in players_container.get_children(): child.queue_free()
	_start_listening()

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
