extends CharacterBody2D

# --- CONFIGURATION ---
@export var speed: float = 300.0
@export var lerp_speed: float = 20.0
@export var max_health: int = 100 
@export var grid_size: int = 40 # Size of grid cells for walls

# --- CRAFTING RECIPES ---
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
	},
	{
		"name": "Wall Bundle",
		"scrap_cost": 10,
		"fabric_cost": 0,
		"output_name": "wall",
		"output_amount": 5
	}
]

# --- STATE ---
var target_position: Vector2 = Vector2.ZERO
var can_send_updates = false
var current_anim: String = "idle" 
var is_flipped: bool = false 

# --- BUILDING STATE (NEW) ---
var is_placing_wall: bool = false
var ghost_wall: Sprite2D # Visual preview

# --- NETWORK THROTTLE ---
var network_tick_rate: float = 0.05 
var current_tick: float = 0.0

# --- RESOURCES & STATS ---
var health: int = 100 
var scrap_amount: int = 0
var fabric_amount: int = 0 
var crafted_inventory: Dictionary = {} 

# --- STAGING AREA (The "Table") ---
var scrap_in_crafting: int = 0   
var fabric_in_crafting: int = 0

var interact_timer: float = 0.0
var hold_duration: float = 3.0 
var current_pile = null 

# UI Components
var progress_bar: ProgressBar
var score_label: Label
var fabric_label: Label 
var interaction_area: Area2D

# UPDATED: Changed to CanvasLayer as requested
@onready var inventory: CanvasLayer = $Inv

# --- INVENTORY VISUALS (SCRAP) ---
@onready var red_placholder: Sprite2D = $Inv/InvControl/Sprite2D/ScarpAmmount/RedPlacholder
@onready var red_placholder_2: Sprite2D = $Inv/InvControl/Sprite2D/ScarpAmmount/RedPlacholder2
@onready var red_placholder_3: Sprite2D = $Inv/InvControl/Sprite2D/ScarpAmmount/RedPlacholder3
@onready var red_placholder_4: Sprite2D = $Inv/InvControl/Sprite2D/ScarpAmmount/RedPlacholder4

# --- INVENTORY VISUALS (FABRIC - NEW) ---
# Make sure you create these nodes in Godot!
@onready var fabric_placeholder: Sprite2D = $Inv/InvControl/Sprite2D/FabricAmount/FabricPlaceholder
@onready var fabric_placeholder_2: Sprite2D = $Inv/InvControl/Sprite2D/FabricAmount/FabricPlaceholder2
@onready var fabric_placeholder_3: Sprite2D = $Inv/InvControl/Sprite2D/FabricAmount/FabricPlaceholder3
@onready var fabric_placeholder_4: Sprite2D = $Inv/InvControl/Sprite2D/FabricAmount/FabricPlaceholder4

# --- CRAFTING AREA VISUALS (SCRAP) ---
@onready var craft_scrap_1: Sprite2D = $Inv/InvControl/CraftingArea/CraftScrap1
@onready var craft_scrap_2: Sprite2D = $Inv/InvControl/CraftingArea/CraftScrap2
@onready var craft_scrap_3: Sprite2D = $Inv/InvControl/CraftingArea/CraftScrap3
@onready var craft_scrap_4: Sprite2D = $Inv/InvControl/CraftingArea/CraftScrap4

# --- CRAFTING AREA VISUALS (FABRIC - NEW) ---
@onready var craft_fabric_1: Sprite2D = $Inv/InvControl/CraftingArea/CraftFabric1
@onready var craft_fabric_2: Sprite2D = $Inv/InvControl/CraftingArea/CraftFabric2
@onready var craft_fabric_3: Sprite2D = $Inv/InvControl/CraftingArea/CraftFabric3
@onready var craft_fabric_4: Sprite2D = $Inv/InvControl/CraftingArea/CraftFabric4

# --- CRAFTED ITEMS ---
@onready var metal_icon: Sprite2D = $Inv/InvControl/CraftedItems/MetalIcon
@onready var bandage_icon: Sprite2D = $Inv/InvControl/CraftedItems/BandageIcon
@onready var wall_icon: Sprite2D = $Inv/InvControl/CraftedItems/WallIcon 

# --- TOOLTIP & HEALTH ---
@onready var recipe_tooltip: Label = $Inv/InvControl/RecipeTooltip
@onready var health_label: Label = $Inv/InvControl/HealthLabel 

func _ready():
	motion_mode = MOTION_MODE_FLOATING
	var id = name.to_int()
	if id != 0: set_multiplayer_authority(id)
	
	health = max_health 
	
	# Fix Recipe List if stale
	var has_wall_recipe = false
	for r in recipes:
		if r["name"] == "Wall Bundle":
			has_wall_recipe = true
			break
	if not has_wall_recipe:
		recipes.append({
			"name": "Wall Bundle",
			"scrap_cost": 10,
			"fabric_cost": 0,
			"output_name": "wall",
			"output_amount": 5
		})
	
	target_position = global_position
	_setup_interaction_components()
	_create_ghost_wall() 
	
	var camera = get_node_or_null("Camera2D")

	if is_multiplayer_authority():
		if not camera:
			camera = Camera2D.new()
			add_child(camera)
		camera.make_current()
		modulate = Color(0.5, 1, 0.5) 
		
		# Initial Visibility State
		if inventory: inventory.visible = false 
		
		if recipe_tooltip: recipe_tooltip.hide()
		update_inventory_visuals() 
		
		await get_tree().create_timer(0.5).timeout
		can_send_updates = true
	else:
		if camera: camera.enabled = false
		modulate = Color(1, 0.5, 0.5) 
		progress_bar.visible = false 
		if inventory: inventory.visible = false
	
	if not craft_scrap_1: print("WARNING: CraftScrap1 node missing!")

func _create_ghost_wall():
	ghost_wall = Sprite2D.new()
	var p = PlaceholderTexture2D.new()
	p.size = Vector2(40, 40)
	ghost_wall.texture = p
	ghost_wall.modulate = Color(0, 1, 0, 0.5) 
	ghost_wall.top_level = true 
	ghost_wall.hide()
	add_child(ghost_wall)

func _physics_process(delta):
	if is_multiplayer_authority():
		# Handle Inventory Toggle
		if Input.is_action_just_pressed("ui_accept"):
			if is_placing_wall:
				is_placing_wall = false
				ghost_wall.hide()
				if inventory: inventory.visible = true
			else:
				if inventory: inventory.visible = not inventory.visible
		
		if is_placing_wall:
			var mouse_pos = get_global_mouse_position()
			var snapped_pos = mouse_pos.snapped(Vector2(grid_size, grid_size))
			ghost_wall.global_position = snapped_pos
			ghost_wall.show()
		
		handle_input()
		handle_interaction(delta) 
		move_and_slide()
		
		current_tick += delta
		if current_tick >= network_tick_rate:
			current_tick = 0.0 
			_send_network_updates()
	else:
		global_position = global_position.lerp(target_position, lerp_speed * delta)

func _input(event):
	if not is_multiplayer_authority(): return
	
	if is_placing_wall and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var mouse_pos = get_global_mouse_position()
			var snapped_pos = mouse_pos.snapped(Vector2(grid_size, grid_size))
			rpc_id(1, "request_place_wall_item", snapped_pos)
		
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			is_placing_wall = false
			ghost_wall.hide()
			if inventory: inventory.visible = true

	elif not is_placing_wall and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if scrap_amount >= 1:
			var mouse_pos = get_global_mouse_position()
			rpc_id(1, "request_place_wall", mouse_pos)

# --- VISUALS ---

func update_inventory_visuals():
	if score_label: score_label.text = "Scrap: " + str(scrap_amount)
	if fabric_label: fabric_label.text = "Fabric: " + str(fabric_amount)
	
	if health_label: 
		health_label.text = "HP: " + str(health) + "/" + str(max_health)
		if health < 30: health_label.modulate = Color(1, 0, 0)
		else: health_label.modulate = Color(0, 1, 0)

	if not is_multiplayer_authority(): return

	# 1. HIDE ALL FIRST
	if red_placholder: red_placholder.hide()
	if red_placholder_2: red_placholder_2.hide()
	if red_placholder_3: red_placholder_3.hide()
	if red_placholder_4: red_placholder_4.hide()
	
	if fabric_placeholder: fabric_placeholder.hide()
	if fabric_placeholder_2: fabric_placeholder_2.hide()
	if fabric_placeholder_3: fabric_placeholder_3.hide()
	if fabric_placeholder_4: fabric_placeholder_4.hide()
	
	if craft_scrap_1: craft_scrap_1.hide()
	if craft_scrap_2: craft_scrap_2.hide()
	if craft_scrap_3: craft_scrap_3.hide()
	if craft_scrap_4: craft_scrap_4.hide()
	
	if craft_fabric_1: craft_fabric_1.hide()
	if craft_fabric_2: craft_fabric_2.hide()
	if craft_fabric_3: craft_fabric_3.hide()
	if craft_fabric_4: craft_fabric_4.hide()
	
	# 2. SHOW BAG ITEMS (Scrap - 10s)
	if scrap_amount >= 10 and red_placholder: red_placholder.show()
	if scrap_amount >= 20 and red_placholder_2: red_placholder_2.show()
	if scrap_amount >= 30 and red_placholder_3: red_placholder_3.show()
	if scrap_amount >= 40 and red_placholder_4: red_placholder_4.show()
	
	# 3. SHOW BAG ITEMS (Fabric - 5s)
	if fabric_amount >= 5 and fabric_placeholder: fabric_placeholder.show()
	if fabric_amount >= 10 and fabric_placeholder_2: fabric_placeholder_2.show()
	if fabric_amount >= 15 and fabric_placeholder_3: fabric_placeholder_3.show()
	if fabric_amount >= 20 and fabric_placeholder_4: fabric_placeholder_4.show()
	
	# 4. SHOW TABLE ITEMS (Scrap - 10s)
	if scrap_in_crafting >= 10 and craft_scrap_1: craft_scrap_1.show()
	if scrap_in_crafting >= 20 and craft_scrap_2: craft_scrap_2.show()
	if scrap_in_crafting >= 30 and craft_scrap_3: craft_scrap_3.show()
	if scrap_in_crafting >= 40 and craft_scrap_4: craft_scrap_4.show()
	
	# 5. SHOW TABLE ITEMS (Fabric - 5s)
	if fabric_in_crafting >= 5 and craft_fabric_1: craft_fabric_1.show()
	if fabric_in_crafting >= 10 and craft_fabric_2: craft_fabric_2.show()
	if fabric_in_crafting >= 15 and craft_fabric_3: craft_fabric_3.show()
	if fabric_in_crafting >= 20 and craft_fabric_4: craft_fabric_4.show()

	# 6. CRAFTED ITEM ICONS
	if metal_icon:
		var metal_count = crafted_inventory.get("metal", 0)
		metal_icon.visible = metal_count > 0
		var m_lbl = metal_icon.get_node_or_null("Label")
		if m_lbl: m_lbl.text = str(metal_count)

	if bandage_icon:
		var bandage_count = crafted_inventory.get("bandage", 0)
		bandage_icon.visible = bandage_count > 0
		var b_lbl = bandage_icon.get_node_or_null("Label")
		if b_lbl: b_lbl.text = str(bandage_count)
		
	if wall_icon:
		var wall_count = crafted_inventory.get("wall", 0)
		wall_icon.visible = wall_count > 0
		var w_lbl = wall_icon.get_node_or_null("Label")
		if w_lbl: w_lbl.text = str(wall_count)

# --- BUTTONS ---

func _on_combine_button_mouse_entered():
	if not is_multiplayer_authority(): return
	if not recipe_tooltip: return
	recipe_tooltip.show()
	recipe_tooltip.text = "Recipes:\n"
	var found_any = false
	for r in recipes:
		if scrap_in_crafting >= r["scrap_cost"] and fabric_in_crafting >= r["fabric_cost"]:
			recipe_tooltip.text += "-> " + r["name"] + "\n"
			found_any = true
	if not found_any: recipe_tooltip.text += "(None)"

func _on_combine_button_mouse_exited():
	if recipe_tooltip: recipe_tooltip.hide()

# SCRAP BUTTONS
func _on_scrap_button_pressed():
	if not is_multiplayer_authority(): return
	if scrap_amount >= 10: rpc_id(1, "request_transfer_scrap", 10) 

func _on_crafting_scrap_pressed():
	if not is_multiplayer_authority(): return
	if scrap_in_crafting >= 10: rpc_id(1, "request_return_scrap", 10)

# FABRIC BUTTONS (NEW)
# Connect button in Inventory -> FabricAmount -> Button
func _on_fabric_button_pressed():
	if not is_multiplayer_authority(): return
	# Transfer 5 at a time
	if fabric_amount >= 5: rpc_id(1, "request_transfer_fabric", 5)

# Connect button in CraftingArea -> FabricButton (create this button)
func _on_crafting_fabric_pressed():
	if not is_multiplayer_authority(): return
	# Return 5 at a time
	if fabric_in_crafting >= 5: rpc_id(1, "request_return_fabric", 5)

func _on_combine_button_pressed():
	if not is_multiplayer_authority(): return
	var found_recipe = -1
	for i in range(recipes.size()):
		var r = recipes[i]
		if scrap_in_crafting >= r["scrap_cost"] and fabric_in_crafting >= r["fabric_cost"]:
			found_recipe = i
			break
	if found_recipe != -1: rpc_id(1, "request_craft_from_table", found_recipe)

func _on_bandage_button_pressed():
	if not is_multiplayer_authority(): return
	if crafted_inventory.get("bandage", 0) > 0:
		if health < max_health: rpc_id(1, "request_use_item", "bandage")

func _on_wall_button_pressed():
	if not is_multiplayer_authority(): return
	if crafted_inventory.get("wall", 0) > 0:
		is_placing_wall = true
		if inventory: inventory.visible = false
		print("Entered Wall Placement Mode")
	else:
		print("No walls to place!")

# --- NETWORKING LOGIC ---

func sync_state_to_everyone():
	if not multiplayer.is_server(): return
	rpc("update_resources", scrap_amount, fabric_amount, scrap_in_crafting, fabric_in_crafting, health)
	var inv_json = JSON.stringify(crafted_inventory)
	rpc("update_crafted_inventory_safe", inv_json)

@rpc("any_peer", "call_local", "reliable")
func request_transfer_scrap(amount):
	if multiplayer.is_server():
		if scrap_amount >= amount:
			scrap_amount -= amount
			scrap_in_crafting += amount
		sync_state_to_everyone()

@rpc("any_peer", "call_local", "reliable")
func request_return_scrap(amount):
	if multiplayer.is_server():
		if scrap_in_crafting >= amount:
			scrap_in_crafting -= amount
			scrap_amount += amount
		sync_state_to_everyone()

# NEW RPCs FOR FABRIC
@rpc("any_peer", "call_local", "reliable")
func request_transfer_fabric(amount):
	if multiplayer.is_server():
		if fabric_amount >= amount:
			fabric_amount -= amount
			fabric_in_crafting += amount
		sync_state_to_everyone()

@rpc("any_peer", "call_local", "reliable")
func request_return_fabric(amount):
	if multiplayer.is_server():
		if fabric_in_crafting >= amount:
			fabric_in_crafting -= amount
			fabric_amount += amount
		sync_state_to_everyone()

@rpc("any_peer", "call_local", "reliable")
func request_craft_from_table(index):
	if multiplayer.is_server():
		if index < 0 or index >= recipes.size(): return
		var r = recipes[index]
		if scrap_in_crafting >= r["scrap_cost"] and fabric_in_crafting >= r["fabric_cost"]:
			scrap_in_crafting -= r["scrap_cost"]
			fabric_in_crafting -= r["fabric_cost"]
			
			var out_name = r["output_name"]
			if not crafted_inventory.has(out_name): crafted_inventory[out_name] = 0
			crafted_inventory[out_name] += r["output_amount"]
			
			sync_state_to_everyone()

@rpc("any_peer", "call_local", "reliable")
func request_use_item(item_name):
	if multiplayer.is_server():
		if crafted_inventory.get(item_name, 0) > 0:
			if item_name == "bandage":
				health += 100
				if health > max_health: health = max_health
			
			crafted_inventory[item_name] -= 1
			if crafted_inventory[item_name] <= 0:
				crafted_inventory.erase(item_name)
			
			sync_state_to_everyone()

@rpc("any_peer", "call_local", "reliable")
func request_place_wall_item(pos):
	if multiplayer.is_server():
		if crafted_inventory.get("wall", 0) > 0:
			crafted_inventory["wall"] -= 1
			if crafted_inventory["wall"] <= 0:
				crafted_inventory.erase("wall")
			
			sync_state_to_everyone()
			
			if ResourceLoader.exists("res://wall.tscn"):
				var wall_scn = load("res://wall.tscn") 
				var wall = wall_scn.instantiate()
				wall.global_position = pos
				wall.name = "Wall_" + str(randi())
				get_parent().add_child(wall, true)

# --- RELIABLE UPDATE ---

@rpc("any_peer", "call_local", "reliable")
func update_resources(s_amt, f_amt, s_table, f_table, hp):
	if not multiplayer.is_server(): print("Client Update. HP: ", hp)
	scrap_amount = s_amt
	fabric_amount = f_amt
	scrap_in_crafting = s_table
	fabric_in_crafting = f_table
	health = hp 
	update_inventory_visuals()

@rpc("any_peer", "call_local", "reliable")
func update_crafted_inventory_safe(json_data):
	var parsed = JSON.parse_string(json_data)
	if parsed is Dictionary:
		crafted_inventory = parsed
	else:
		crafted_inventory = {}
	update_inventory_visuals()

# --- STANDARD INTERACTION ETC ---

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
	var input_direction = Input.get_vector("left", "right", "up", "down")
	velocity = input_direction * speed

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
	
	fabric_label = Label.new()
	fabric_label.text = "Fabric: 0"
	fabric_label.position = Vector2(-20, 60) 
	fabric_label.modulate = Color(0.8, 0.8, 1.0) 
	add_child(fabric_label)
	
	health_label = Label.new()
	health_label.text = "HP: 100"
	health_label.position = Vector2(-20, -80)
	health_label.modulate = Color(0, 1, 0)
	add_child(health_label)

func handle_interaction(delta):
	if current_pile != null and Input.is_action_pressed("interact"):
		interact_timer += delta
		progress_bar.visible = true
		progress_bar.value = interact_timer
		
		if interact_timer >= hold_duration:
			interact_timer = 0.0
			progress_bar.value = 0.0
			progress_bar.visible = false
			
			var type = "scrap"
			if current_pile.is_in_group("fabric"): type = "fabric"
			rpc_id(1, "request_collect_resource", current_pile.get_path(), type)
	else:
		interact_timer = 0.0
		progress_bar.value = 0.0
		progress_bar.visible = false

func _on_area_entered(area):
	if area.is_in_group("scrap") or area.is_in_group("fabric"): 
		current_pile = area
func _on_area_exited(area):
	if area == current_pile: current_pile = null

@rpc("any_peer", "call_local")
func request_place_wall(pos):
	if multiplayer.is_server():
		if scrap_amount >= 1:
			scrap_amount -= 1
			sync_state_to_everyone()
			if ResourceLoader.exists("res://wall.tscn"):
				var wall_scn = load("res://wall.tscn") 
				var wall = wall_scn.instantiate()
				wall.global_position = pos
				wall.name = "Wall_" + str(randi())
				get_parent().add_child(wall, true) 

@rpc("any_peer", "call_local", "reliable")
func trigger_pickup_visuals(type):
	if type == "fabric":
		if fabric_label:
			fabric_label.modulate = Color(0, 1, 1) 
			await get_tree().create_timer(0.2).timeout
			fabric_label.modulate = Color(0.8, 0.8, 1.0)
	else:
		if score_label:
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

@rpc("any_peer", "call_local", "reliable")
func request_collect_resource(pile_path, type):
	if multiplayer.is_server():
		var pile = get_node_or_null(pile_path)
		if pile != null:
			if type == "fabric":
				self.fabric_amount += 5
			else:
				self.scrap_amount += 10
			sync_state_to_everyone()
			rpc("trigger_pickup_visuals", type)
			pile.collect()

func take_damage(amount: int):
	if multiplayer.is_server():
		health -= amount
		if health < 0: health = 0
		sync_state_to_everyone()
