extends CharacterBody2D

# --- CONFIGURATION ---
@export var speed: float = 300.0
@export var lerp_speed: float = 20.0

# --- CRAFTING SYSTEM (NEW) ---
# This creates a list in the Inspector!
@export var recipes: Array[Dictionary] = [
	{
		"name": "Refined Metal",
		"scrap_cost": 10,
		"fabric_cost": 0,
		"output_name": "metal",
		"output_amount": 10
	},
	{
		"name": "Bandage",
		"scrap_cost": 0,
		"fabric_cost": 5,
		"output_name": "bandage",
		"output_amount": 1
	}
]

# --- STATE ---
var target_position: Vector2 = Vector2.ZERO
var can_send_updates = false
var current_anim: String = "idle" 
var is_flipped: bool = false 

# --- NETWORK THROTTLE ---
var network_tick_rate: float = 0.05 
var current_tick: float = 0.0

# --- RESOURCES (UPDATED) ---
var scrap_amount: int = 0
var fabric_amount: int = 0 # NEW RESOURCE
var crafted_inventory: Dictionary = {} # Stores all outputs: {"metal": 0, "bandage": 0}

var interact_timer: float = 0.0
var hold_duration: float = 3.0 
var current_pile = null 

# UI Components
var progress_bar: ProgressBar
var score_label: Label
var fabric_label: Label # NEW LABEL
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

	# --- CLIENT SIDED VISIBILITY LOGIC ---
	if is_multiplayer_authority():
		if not camera:
			camera = Camera2D.new()
			add_child(camera)
		camera.make_current()
		modulate = Color(0.5, 1, 0.5) 
		
		if has_node("Inv"): $Inv.visible = true
		inventory.visible = false 
		
		update_inventory_visuals() 
		
		await get_tree().create_timer(0.5).timeout
		can_send_updates = true
	else:
		if camera: camera.enabled = false
		modulate = Color(1, 0.5, 0.5) 
		progress_bar.visible = false 
		if has_node("Inv"): $Inv.visible = false

func _physics_process(delta):
	if is_multiplayer_authority():
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

func update_inventory_visuals():
	# Reset all to hidden first
	if red_placholder: red_placholder.hide()
	if red_placholder_2: red_placholder_2.hide()
	if red_placholder_3: red_placholder_3.hide()
	if red_placholder_4: red_placholder_4.hide()
	
	# Show based on amount (Scrap)
	if scrap_amount >= 10 and red_placholder: red_placholder.show()
	if scrap_amount >= 20 and red_placholder_2: red_placholder_2.show()
	if scrap_amount >= 30 and red_placholder_3: red_placholder_3.show()
	if scrap_amount >= 40 and red_placholder_4: red_placholder_4.show()
	
	# Update Text Labels
	score_label.text = "Scrap: " + str(scrap_amount)
	fabric_label.text = "Fabric: " + str(fabric_amount)

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

# --- DYNAMIC CRAFTING LOGIC (UPDATED) ---
func _on_button_pressed() -> void:
	if not is_multiplayer_authority(): return
	
	# DEFAULT: Try to craft the FIRST recipe in the list (Index 0)
	# (You can change this to 1, 2, etc. if you make more buttons)
	var recipe_index = 0 
	
	if recipes.size() > recipe_index:
		var recipe = recipes[recipe_index]
		
		# Check if we have enough materials for this specific recipe
		if scrap_amount >= recipe["scrap_cost"] and fabric_amount >= recipe["fabric_cost"]:
			rpc_id(1, "request_craft_recipe", recipe_index)
		else:
			print("Not enough resources for: " + recipe["name"])
	else:
		print("No recipe found at index " + str(recipe_index))

@rpc("any_peer", "call_local", "reliable")
func request_craft_recipe(index: int):
	if multiplayer.is_server():
		# Security Check: Does recipe exist?
		if index < 0 or index >= recipes.size(): return
		
		var recipe = recipes[index]
		
		# Security Check: Can they afford it?
		if scrap_amount >= recipe["scrap_cost"] and fabric_amount >= recipe["fabric_cost"]:
			# Deduct Cost
			scrap_amount -= recipe["scrap_cost"]
			fabric_amount -= recipe["fabric_cost"]
			
			# Add Output
			var out_name = recipe["output_name"]
			var out_amt = recipe["output_amount"]
			
			if not crafted_inventory.has(out_name):
				crafted_inventory[out_name] = 0
			crafted_inventory[out_name] += out_amt
			
			# Sync back to client
			rpc("update_crafting_stats", scrap_amount, fabric_amount, crafted_inventory)

@rpc("call_local", "reliable")
func update_crafting_stats(new_scrap, new_fabric, new_inventory):
	scrap_amount = new_scrap
	fabric_amount = new_fabric
	crafted_inventory = new_inventory
	
	update_inventory_visuals()
	
	print("Crafting Complete! Inventory: ", crafted_inventory)

# --- STANDARD SETUP & NETWORKING ---

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
	
	# NEW FABRIC LABEL
	fabric_label = Label.new()
	fabric_label.text = "Fabric: 0"
	fabric_label.position = Vector2(-20, 60) # Below scrap
	fabric_label.modulate = Color(0.8, 0.8, 1.0) # Light blueish
	add_child(fabric_label)

func handle_interaction(delta):
	if current_pile != null and Input.is_action_pressed("ui_accept"):
		interact_timer += delta
		progress_bar.visible = true
		progress_bar.value = interact_timer
		
		if interact_timer >= hold_duration:
			interact_timer = 0.0
			progress_bar.value = 0.0
			progress_bar.visible = false
			
			# Send pile path AND the group it belongs to so server knows what to add
			var type = "scrap"
			if current_pile.is_in_group("fabric"): type = "fabric"
			
			rpc_id(1, "request_collect_resource", current_pile.get_path(), type)
	else:
		interact_timer = 0.0
		progress_bar.value = 0.0
		progress_bar.visible = false

func _on_area_entered(area):
	# Check for both groups
	if area.is_in_group("scrap") or area.is_in_group("fabric"): 
		current_pile = area
		
func _on_area_exited(area):
	if area == current_pile: current_pile = null

@rpc("any_peer", "call_local", "reliable")
func request_collect_resource(pile_path, type):
	if multiplayer.is_server():
		var pile = get_node_or_null(pile_path)
		if pile != null:
			var sender_id = multiplayer.get_remote_sender_id()
			if sender_id == 0: sender_id = 1
			var player_node = get_parent().get_node_or_null(str(sender_id))
			
			if player_node:
				if type == "fabric":
					player_node.rpc("add_fabric", 5) # Fabric gives 5
				else:
					player_node.rpc("add_scrap", 10) # Scrap gives 10
			
			pile.collect()

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

@rpc("any_peer", "call_local", "reliable")
func add_scrap(amount):
	scrap_amount += amount
	update_inventory_visuals()
	score_label.modulate = Color(1, 1, 0)
	await get_tree().create_timer(0.2).timeout
	score_label.modulate = Color(1, 1, 1)

# NEW RPC FOR FABRIC
@rpc("any_peer", "call_local", "reliable")
func add_fabric(amount):
	fabric_amount += amount
	update_inventory_visuals()
	fabric_label.modulate = Color(0, 1, 1) # Cyan flash
	await get_tree().create_timer(0.2).timeout
	fabric_label.modulate = Color(0.8, 0.8, 1.0)

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
