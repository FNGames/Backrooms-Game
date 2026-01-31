extends Node2D

const DEFAULT_PORT = 7000
const DEFAULT_SERVER_IP = "127.0.0.1"
const MAX_PLAYERS = 4
const BROADCAST_PORT = 8911

@export var player_scene: PackedScene
@export var scrap_scene: PackedScene 
@export var wall_scene: PackedScene # NEW: Drag your wall.tscn here!

# UI Nodes
@onready var lobby_ui = $CanvasLayer/LobbyUI
@onready var players_container = $Players
@onready var address_entry = $CanvasLayer/LobbyUI/VBoxContainer/AddressEntry
@onready var code_entry = $CanvasLayer/LobbyUI/VBoxContainer/CodeEntry
@onready var status_label = $CanvasLayer/LobbyUI/VBoxContainer/StatusLabel
@onready var vbox = $CanvasLayer/LobbyUI/VBoxContainer

# Dynamic UI Nodes
var lobby_name_entry: LineEdit 
var public_checkbox: CheckBox
var server_list: VBoxContainer
var refresh_button: Button

var peer = ENetMultiplayerPeer.new()
var ip_fetcher = HTTPRequest.new()

# Broadcast & State Variables
var broadcaster = PacketPeerUDP.new()
var listener = PacketPeerUDP.new()
var broadcast_timer = Timer.new()
var found_servers = {} 

var listener_bound = false
var bind_retry_timer = Timer.new()
var is_port_open = false

func _ready():
	_setup_extra_ui()
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	# SETUP SPAWNER (PLAYERS)
	var spawner = MultiplayerSpawner.new()
	add_child(spawner)
	spawner.spawn_path = players_container.get_path()
	if player_scene:
		spawner.add_spawnable_scene(player_scene.resource_path)
	
	# SETUP SPAWNER (SCRAP)
	if scrap_scene:
		spawner.add_spawnable_scene(scrap_scene.resource_path)
		
	# NEW: SETUP SPAWNER (WALLS)
	if wall_scene:
		spawner.add_spawnable_scene(wall_scene.resource_path)
		
	ip_fetcher.name = "IPFetcher"
	add_child(ip_fetcher)
	ip_fetcher.request_completed.connect(_on_ip_request_completed)
	
	broadcaster.set_broadcast_enabled(true)
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

# --- NEW: SPAWN SCRAP LOGIC ---
func _spawn_level_scrap():
	if not scrap_scene: return
	
	# Spawn 5 piles at random locations
	for i in range(5):
		var pile = scrap_scene.instantiate()
		pile.name = "Scrap_" + str(randi())
		pile.global_position = Vector2(randf_range(100, 900), randf_range(100, 500))
		players_container.add_child(pile, true) # 'true' means human-readable names for sync

# --- UI SETUP ---
func _setup_extra_ui():
	lobby_name_entry = LineEdit.new()
	lobby_name_entry.placeholder_text = "Lobby Name (e.g. Mike's Game)"
	vbox.add_child(lobby_name_entry)
	vbox.move_child(lobby_name_entry, 0)
	
	public_checkbox = CheckBox.new()
	public_checkbox.text = "Public Lobby (Show in List)"
	vbox.add_child(public_checkbox)
	vbox.move_child(public_checkbox, 3)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)
	
	refresh_button = Button.new()
	refresh_button.text = "Refresh / Search for Games"
	refresh_button.pressed.connect(_on_refresh_pressed)
	vbox.add_child(refresh_button)
	
	var list_label = Label.new()
	list_label.text = "--- FOUND LOBBIES ---"
	list_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(list_label)
	
	server_list = VBoxContainer.new()
	vbox.add_child(server_list)

func _add_server_button(name, ip, port):
	var btn = Button.new()
	btn.text = "Join: " + name + " (" + ip + ")"
	btn.pressed.connect(func(): _join_game_direct(ip, port))
	server_list.add_child(btn)

# --- BROADCAST LOGIC ---
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
	else:
		if bind_retry_timer.is_stopped():
			bind_retry_timer.start()

func _on_refresh_pressed():
	for child in server_list.get_children():
		child.queue_free()
	found_servers.clear()
	_start_listening()

func _broadcast_presence():
	var name_txt = lobby_name_entry.text
	if name_txt == "": 
		if code_entry.text != "": name_txt = "Lobby " + code_entry.text
		else: name_txt = "Unnamed Lobby"
	
	var port = get_port_from_code(code_entry.text)
	var data = { "name": name_txt, "port": port }
	var json = JSON.stringify(data)
	broadcaster.set_dest_address("255.255.255.255", BROADCAST_PORT)
	broadcaster.put_packet(json.to_utf8_buffer())

# --- HOSTING & JOINING ---

func _join_game_direct(ip, port):
	_cleanup_connection()
	var error = peer.create_client(ip, port)
	if error != OK:
		status_label.text = "Error joining: " + str(error)
		return
	
	multiplayer.multiplayer_peer = peer
	status_label.text = "Connecting to " + ip + "..."
	_toggle_ui_input(false) 
	get_tree().create_timer(15.0).timeout.connect(_check_connection_timeout)

func _on_host_button_pressed():
	_cleanup_connection()
	listener.close()
	listener_bound = false
	bind_retry_timer.stop()
	
	var port = get_port_from_code(code_entry.text)
	var local_ip = _get_local_ip()
	
	DisplayServer.window_set_title("Local IP: " + local_ip + " | Code: " + code_entry.text)
	status_label.text = "Configuring UPnP..."
	status_label.modulate = Color(1, 1, 0) # Yellow (Working)
	_toggle_ui_input(false)
	
	await get_tree().create_timer(0.1).timeout
	var public_ip_upnp = _upnp_setup(port)
	
	var error = peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		status_label.text = "Error hosting: " + str(error)
		_toggle_ui_input(true)
		return
	
	multiplayer.multiplayer_peer = peer
	lobby_ui.hide()
	
	# SPAWN STUFF
	spawn_player(1)
	_spawn_level_scrap() 
	
	if "Failed" in str(public_ip_upnp):
		is_port_open = false 
		print("UPnP Failed. Falling back to Web IP fetch...")
		ip_fetcher.request("https://api64.ipify.org")
	else:
		is_port_open = true 
		_update_host_ui(public_ip_upnp, local_ip)
		
	if public_checkbox.button_pressed:
		broadcast_timer.start()

func _on_join_button_pressed():
	_cleanup_connection()
	var address = address_entry.text
	if address == "": address = DEFAULT_SERVER_IP
	var port = get_port_from_code(code_entry.text)
	
	var error = peer.create_client(address, port)
	if error != OK:
		status_label.text = "Error joining: " + str(error)
		return
	
	multiplayer.multiplayer_peer = peer
	status_label.text = "Connecting..."
	_toggle_ui_input(false)
	get_tree().create_timer(15.0).timeout.connect(_check_connection_timeout)

func _check_connection_timeout():
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
		peer.close()
		status_label.text = "Timed Out. Host is blocked."
		status_label.modulate = Color(1, 0, 0) # Red
		_toggle_ui_input(true)

# --- UTILS & EVENTS ---

func _toggle_ui_input(enabled: bool):
	for child in vbox.get_children():
		if child is Button or child is LineEdit or child is CheckBox:
			if child is Button: child.disabled = !enabled
			if child is LineEdit: child.editable = enabled
			if child is CheckBox: child.disabled = !enabled

func _cleanup_connection():
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		peer.close()
	broadcast_timer.stop()
	bind_retry_timer.stop()
	listener.close()
	listener_bound = false
	for child in server_list.get_children(): child.queue_free()
	found_servers.clear()

func _input(event):
	if Input.is_action_just_pressed("ui_cancel"):
		leave_game()

func leave_game():
	_cleanup_connection()
	multiplayer.multiplayer_peer = null
	lobby_ui.show()
	_toggle_ui_input(true)
	status_label.text = "Left Game."
	status_label.modulate = Color(1, 1, 1) # White
	DisplayServer.window_set_title("Game Lobby")
	for child in players_container.get_children(): child.queue_free()
	_start_listening()

func get_port_from_code(code_text: String) -> int:
	if code_text.strip_edges() == "": return DEFAULT_PORT
	var hashed = code_text.hash()
	return 10000 + (abs(hashed) % 50000)

func _get_local_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10."): return ip
	return "127.0.0.1"

func _upnp_setup(port):
	var upnp = UPNP.new()
	var err = upnp.discover(2000, 2)
	if err != 0: err = upnp.discover(2000, 2, "InternetGatewayDevice")
	if err != 0: return "Failed"
	
	for i in range(upnp.get_device_count()):
		var dev = upnp.get_device(i)
		dev.add_port_mapping(port, port, "Godot_Game", "UDP")
		dev.add_port_mapping(port, port, "Godot_Game", "UDP", 3600)
		if dev.is_valid_gateway(): return dev.query_external_address()
	return "Failed"

func _on_ip_request_completed(result, code, headers, body):
	if code == 200:
		var public_ip = body.get_string_from_utf8()
		var local_ip = _get_local_ip()
		_update_host_ui(public_ip, local_ip)

func _update_host_ui(public_ip, local_ip):
	if is_port_open:
		status_label.text = "HOSTING (ONLINE & READY)\nPublic IP: " + public_ip
		status_label.modulate = Color(0, 1, 0) # Green
		DisplayServer.window_set_title("ONLINE: " + public_ip + " | Local: " + local_ip)
	else:
		status_label.text = "HOSTING (PORT CLOSED!)\nPublic IP: " + public_ip + "\n(Friends likely cannot join)"
		status_label.modulate = Color(1, 0.5, 0.5) # Red-ish
		DisplayServer.window_set_title("PORT CLOSED: " + public_ip + " (Use Hamachi)")

func _on_peer_connected(id): if multiplayer.is_server(): spawn_player(id)
func _on_peer_disconnected(id): if multiplayer.is_server() and players_container.has_node(str(id)): players_container.get_node(str(id)).queue_free()
func _on_connected_to_server(): 
	status_label.text = "Connected!"
	status_label.modulate = Color(0, 1, 0)
	lobby_ui.hide() 
	_toggle_ui_input(true)
func _on_connection_failed(): 
	status_label.text = "Connection Failed."
	status_label.modulate = Color(1, 0, 0)
	multiplayer.multiplayer_peer = null
	_toggle_ui_input(true)
func _on_server_disconnected(): 
	leave_game()
	status_label.text = "Host Disconnected."

func spawn_player(id):
	var player = player_scene.instantiate()
	player.name = str(id)
	players_container.add_child(player, true) 
	player.global_position = Vector2(randf_range(100, 900), randf_range(100, 500))
