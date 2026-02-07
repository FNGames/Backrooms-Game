extends CharacterBody2D

# --- CONFIGURATION ---
@export var speed: float = 300.0
@export var lerp_speed: float = 20.0

# --- STATE ---
var target_position: Vector2 = Vector2.ZERO
var can_send_updates = false
var current_anim: String = "idle" 
var is_flipped: bool = false 

# --- NETWORK THROTTLE ---
var network_tick_rate: float = 0.05 
var current_tick: float = 0.0

# --- SCRAP MECHANIC ---
var scrap_amount: int = 0
var interact_timer: float = 0.0
var hold_duration: float = 3.0 
var current_pile = null 

# UI Components
var progress_bar: ProgressBar
var score_label: Label
var interaction_area: Area2D

@onready var inventory: Sprite2D = $Inv/InvControl/Sprite2D

# Scrap Placeholders
@onready var red_placholder: Sprite2D = $Inv/InvControl/Sprite2D/ScarpAmmount/RedPlacholder
@onready var red_placholder_2: Sprite2D = $Inv/InvControl/Sprite2D/ScarpAmmount/RedPlacholder2
@onready var red_placholder_3: Sprite2D = $Inv/InvControl/Sprite2D/ScarpAmmount/RedPlacholder3
@onready var red_placholder_4: Sprite2D = $Inv/InvControl/Sprite2D/ScarpAmmount/RedPlacholder4

func _ready():
	motion_mode = MOTION_MODE_FLOATING
	var id = name.to_int()
	if id != 0: set_multiplayer_authority(id)
	
	target_position = global_position
	_setup_interaction_components()
	
	var camera = get_node_or_null("Camera2D")

	# --- CLIENT SIDED VISIBILITY LOGIC (Rule 1) ---
	if is_multiplayer_authority():
		# IF I AM THE OWNER:
		if not camera:
			camera = Camera2D.new()
			add_child(camera)
		camera.make_current()
		modulate = Color(0.5, 1, 0.5) 
		
		# Show the UI container (Inv), but hide the bag sprite (inventory) to start
		if has_node("Inv"): $Inv.visible = true
		inventory.visible = false 
		
		# FIX: Ensure visual state is correct at start (hides all placeholders if 0 scrap)
		update_inventory_visuals() 
		
		await get_tree().create_timer(0.5).timeout
		can_send_updates = true
	else:
		# IF I AM NOT THE OWNER (I am looking at a friend):
		if camera: camera.enabled = false
		modulate = Color(1, 0.5, 0.5) 
		progress_bar.visible = false 
		
		# HIDE THEIR INVENTORY FROM MY SCREEN
		# This ensures Player 1 doesn't see Player 2's menu floating in the air
		if has_node("Inv"): $Inv.visible = false

func _physics_process(delta):
	# REMOVED INVENTORY LOGIC FROM HERE (Rule 2)
	
	if is_multiplayer_authority():
		# MOVED INPUT HERE (Rule 3): Only the owner can open their own bag
		if Input.is_action_just_pressed("ui_accept"):
			inventory.visible = not inventory.visible
			
		handle_input()
		handle_interaction(delta) 
		move_and_slide()
		
		current_tick += delta
		if current_tick >= network_tick_rate:
			current_tick = 0.0 
			_send_network_updates()
	else:
		global_position = global_position.lerp(target_position, lerp_speed * delta)

# NEW FUNCTION: Handles the visuals only when they need to change
func update_inventory_visuals():
	# Reset all to hidden first
	red_placholder.hide()
	red_placholder_2.hide()
	red_placholder_3.hide()
	red_placholder_4.hide()
	
	# Show based on amount
	if scrap_amount >= 10: red_placholder.show()
	if scrap_amount >= 20: red_placholder_2.show()
	if scrap_amount >= 30: red_placholder_3.show()
	if scrap_amount >= 40: red_placholder_4.show()

func _send_network_updates():
	var new_anim = "idle"
	if velocity.length() > 0: new_anim = "walk"
	if new_anim != current_anim:
		current_anim = new_anim
		rpc("play_animation", current_anim)
		
	if velocity.x != 0:
		var should_flip = velocity.x < 0
		if should_flip != is_flipped:
			is_flipped = should_flip
			rpc("update_flip", is_flipped)
	
	if can_send_updates:
		rpc_id(1, "update_position_server", global_position)

func handle_input():
	var input_direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = input_direction * speed

func _input(event):
	if not is_multiplayer_authority(): return
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if scrap_amount >= 1:
			var mouse_pos = get_global_mouse_position()
			rpc_id(1, "request_place_wall", mouse_pos)
		else:
			print("Not enough scrap to build wall!")

func _setup_interaction_components():
	interaction_area = Area2D.new()
	var col = CollisionShape2D.new()
	col.shape = CircleShape2D.new()
	col.shape.radius = 40
	interaction_area.add_child(col)
	add_child(interaction_area)
	
	interaction_area.area_entered.connect(_on_area_entered)
	interaction_area.area_exited.connect(_on_area_exited)
	
	progress_bar = ProgressBar.new()
	progress_bar.size = Vector2(60, 10)
	progress_bar.position = Vector2(-30, -60) 
	progress_bar.show_percentage = false
	progress_bar.max_value = hold_duration
	progress_bar.visible = false
	progress_bar.modulate = Color(0, 1, 0)
	add_child(progress_bar)
	
	score_label = Label.new()
	score_label.text = "Scrap: 0"
	score_label.position = Vector2(-20, 40)
	add_child(score_label)

func handle_interaction(delta):
	if current_pile != null and Input.is_action_pressed("ui_accept"):
		interact_timer += delta
		progress_bar.visible = true
		progress_bar.value = interact_timer
		
		if interact_timer >= hold_duration:
			interact_timer = 0.0
			progress_bar.value = 0.0
			progress_bar.visible = false
			rpc_id(1, "request_collect_scrap", current_pile.get_path())
	else:
		interact_timer = 0.0
		progress_bar.value = 0.0
		progress_bar.visible = false

func _on_area_entered(area):
	if area.is_in_group("scrap"): 
		current_pile = area

func _on_area_exited(area):
	if area == current_pile: current_pile = null

# --- NETWORKING ---

@rpc("any_peer", "call_local", "reliable")
func request_collect_scrap(pile_path):
	if multiplayer.is_server():
		var pile = get_node_or_null(pile_path)
		if pile != null:
			var sender_id = multiplayer.get_remote_sender_id()
			if sender_id == 0: sender_id = 1
			
			var player_node = get_parent().get_node_or_null(str(sender_id))
			if player_node:
				player_node.rpc("add_scrap", 10)
			pile.collect()
		else:
			print("Server Error: Scrap pile not found at path ", pile_path)

@rpc("any_peer", "call_local")
func request_place_wall(pos):
	if multiplayer.is_server():
		if scrap_amount >= 1:
			rpc("add_scrap", -1)
			
			if ResourceLoader.exists("res://wall.tscn"):
				var wall_scn = load("res://wall.tscn") 
				var wall = wall_scn.instantiate()
				wall.global_position = pos
				wall.name = "Wall_" + str(randi())
				get_parent().add_child(wall, true) 
			else:
				print("CRITICAL ERROR: 'res://wall.tscn' not found!")

@rpc("any_peer", "call_local", "reliable")
func add_scrap(amount):
	scrap_amount += amount
	score_label.text = "Scrap: " + str(scrap_amount)
	
	# CALL VISUAL UPDATE HERE (Event-Driven)
	update_inventory_visuals()
	
	score_label.modulate = Color(1, 1, 0)
	await get_tree().create_timer(0.2).timeout
	score_label.modulate = Color(1, 1, 1)

@rpc("any_peer", "call_local", "unreliable_ordered")
func update_position_server(new_pos: Vector2):
	target_position = new_pos
	rpc("update_position_client", new_pos)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func update_position_client(new_pos: Vector2):
	if not is_inside_tree(): return
	target_position = new_pos

@rpc("call_local", "reliable")
func play_animation(anim_name: String):
	current_anim = anim_name
	if has_node("AnimatedSprite2D"): get_node("AnimatedSprite2D").play(anim_name)
	elif has_node("AnimationPlayer"): get_node("AnimationPlayer").play(anim_name)

@rpc("call_local", "reliable")
func update_flip(flipped: bool):
	is_flipped = flipped
	if has_node("AnimatedSprite2D"): get_node("AnimatedSprite2D").flip_h = flipped
	elif has_node("Sprite2D"): get_node("Sprite2D").flip_h = flipped
