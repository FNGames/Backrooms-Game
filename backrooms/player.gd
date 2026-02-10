extends CharacterBody2D

# --- CONFIGURATION ---
@export var speed: float = 300.0
@export var lerp_speed: float = 20.0
@export var max_health: int = 100 
@export var grid_size: int = 40 # Size of grid cells for walls
@export var deconstruct_time: float = 0.5 # Time to hold right-click to delete

# --- CRAFTING RECIPES ---
# UPDATED: Now supports "Buildables" defined directly here!
@export var recipes: Array[Dictionary] = [
	{
		"name": "Refined Metal",
		"scrap_cost": 10,
		"fabric_cost": 0,
		"output_name": "metal",
		"output_amount": 10,
		"is_buildable": false
	},
	{
		"name": "Bandage",
		"scrap_cost": 0,
		"fabric_cost": 5,
		"output_name": "bandage",
		"output_amount": 1,
		"is_buildable": false
	},
	{
		"name": "Wall Bundle",
		"scrap_cost": 10,
		"fabric_cost": 0,
		"output_name": "wall",
		"output_amount": 5,
		# NEW BUILDABLE PROPERTIES
		"is_buildable": true,
		"build_scene": "res://wall.tscn",   # Drag your scene here
		"ghost_texture": "res://icon.svg",  # Drag your ghost image here
		"button_path": NodePath("Inv/InvControl/CraftedItems/WallIcon/Button"), # Path to the button in scene
		"ghost_scale": Vector2(1, 1) # <--- NEW: Manually set ghost size (Leave 0,0 for auto-fit)
	}
]

# --- STATE ---
var target_position: Vector2 = Vector2.ZERO
var can_send_updates = false
var current_anim: String = "idle" 
var is_flipped: bool = false 

# --- BUILDING STATE (UPDATED) ---
var current_build_recipe: Dictionary = {} # Stores the active recipe we are building
var ghost_sprite: Sprite2D 
var ghost_area: Area2D # Detects overlaps
var can_place_current: bool = false
var last_placed_pos: Vector2 = Vector2.INF # Prevents spamming the same tile
var deconstruct_timer: float = 0.0 # <--- NEW: For deleting walls

# --- UI STATE ---
var is_hovering_craft_button: bool = false

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

@onready var inventory: CanvasLayer = $Inv

# --- INVENTORY VISUALS ---
@onready var red_placholder: Sprite2D = $Inv/InvControl/Sprite2D/ScarpAmmount/RedPlacholder
@onready var red_placholder_2: Sprite2D = $Inv/InvControl/Sprite2D/ScarpAmmount/RedPlacholder2
@onready var red_placholder_3: Sprite2D = $Inv/InvControl/Sprite2D/ScarpAmmount/RedPlacholder3
@onready var red_placholder_4: Sprite2D = $Inv/InvControl/Sprite2D/ScarpAmmount/RedPlacholder4

@onready var fabric_placeholder: Sprite2D = $Inv/InvControl/Sprite2D/FabricAmount/FabricPlaceholder
@onready var fabric_placeholder_2: Sprite2D = $Inv/InvControl/Sprite2D/FabricAmount/FabricPlaceholder2
@onready var fabric_placeholder_3: Sprite2D = $Inv/InvControl/Sprite2D/FabricAmount/FabricPlaceholder3
@onready var fabric_placeholder_4: Sprite2D = $Inv/InvControl/Sprite2D/FabricAmount/FabricPlaceholder4

# --- CRAFTING AREA VISUALS ---
@onready var craft_scrap_1: Sprite2D = $Inv/InvControl/CraftingArea/CraftScrap1
@onready var craft_scrap_2: Sprite2D = $Inv/InvControl/CraftingArea/CraftScrap2
@onready var craft_scrap_3: Sprite2D = $Inv/InvControl/CraftingArea/CraftScrap3
@onready var craft_scrap_4: Sprite2D = $Inv/InvControl/CraftingArea/CraftScrap4

@onready var craft_fabric_1: Sprite2D = $Inv/InvControl/CraftingArea/CraftFabric1
@onready var craft_fabric_2: Sprite2D = $Inv/InvControl/CraftingArea/CraftFabric2
@onready var craft_fabric_3: Sprite2D = $Inv/InvControl/CraftingArea/CraftFabric3
@onready var craft_fabric_4: Sprite2D = $Inv/InvControl/CraftingArea/CraftFabric4

# --- CRAFTED ITEMS ---
@onready var metal_icon: Sprite2D = $Inv/InvControl/CraftedItems/MetalIcon
@onready var bandage_icon: Sprite2D = $Inv/InvControl/CraftedItems/BandageIcon
@onready var wall_icon: Sprite2D = $Inv/InvControl/CraftedItems/WallIcon 

# --- TOOLTIP & HEALTH ---
@onready var recipe_list: VBoxContainer = $Inv/InvControl/RecipeList
@onready var health_label: Label = $Inv/InvControl/HealthLabel 

func _ready():
	motion_mode = MOTION_MODE_FLOATING
	var id = name.to_int()
	if id != 0: set_multiplayer_authority(id)
	
	health = max_health 
	
	# NEW: Connect buttons defined in recipes
	for i in range(recipes.size()):
		var r = recipes[i]
		# Ensure defaults exist
		if not r.has("is_buildable"): r["is_buildable"] = false
		
		if r["is_buildable"] and r.has("button_path"):
			var path = r["button_path"]
			if has_node(path):
				var btn = get_node(path)
				# Connect button to the generic build starter
				if not btn.pressed.is_connected(_on_build_item_pressed):
					btn.pressed.connect(_on_build_item_pressed.bind(i))
				print("Connected build button for: ", r["name"])
			else:
				print("Warning: Button path not found for ", r["name"])
	
	target_position = global_position
	_setup_interaction_components()
	_create_build_ghost() 
	
	var camera = get_node_or_null("Camera2D")

	if is_multiplayer_authority():
		if not camera:
			camera = Camera2D.new()
			add_child(camera)
		camera.make_current()
		modulate = Color(0.5, 1, 0.5) 
		
		if inventory: inventory.visible = false 
		
		if recipe_list: recipe_list.hide()
		update_inventory_visuals() 
		
		await get_tree().create_timer(0.5).timeout
		can_send_updates = true
	else:
		if camera: camera.enabled = false
		modulate = Color(1, 0.5, 0.5) 
		progress_bar.visible = false 
		if inventory: inventory.visible = false
	
	if not craft_scrap_1: print("WARNING: CraftScrap1 node missing!")

# UPDATED: Creates Sprite and Area SEPARATELY so hiding one doesn't break the other
func _create_build_ghost():
	# 1. Visual Ghost
	ghost_sprite = Sprite2D.new()
	ghost_sprite.top_level = true 
	ghost_sprite.hide()
	add_child(ghost_sprite)
	
	# 2. Collision Area (Decoupled!)
	ghost_area = Area2D.new()
	ghost_area.top_level = true # Independent movement
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(grid_size, grid_size) * 0.95 
	col.shape = shape
	ghost_area.add_child(col)
	add_child(ghost_area)

func _physics_process(delta):
	if is_multiplayer_authority():
		# Handle Inventory Toggle
		if Input.is_action_just_pressed("ui_accept"):
			if not current_build_recipe.is_empty():
				_cancel_building()
				if inventory: inventory.visible = true
			else:
				if inventory: inventory.visible = not inventory.visible
		
		# --- BUILDING LOGIC ---
		if not current_build_recipe.is_empty():
			var mouse_pos = get_global_mouse_position()
			var snapped_pos = mouse_pos.snapped(Vector2(grid_size, grid_size))
			
			# Move BOTH components
			ghost_sprite.global_position = snapped_pos
			ghost_area.global_position = snapped_pos # Crucial for overlap check
			ghost_sprite.show()
			
			# Check Overlaps (Collision Check)
			var bodies = ghost_area.get_overlapping_bodies()
			var is_overlapping = false
			for b in bodies:
				if b != self: # Ignore the player themselves
					is_overlapping = true
					break
			
			if is_overlapping:
				ghost_sprite.modulate = Color(1, 0, 0, 0.5) # RED
				can_place_current = false
			else:
				ghost_sprite.modulate = Color(0, 1, 0, 0.5) # GREEN
				can_place_current = true
			
			# DRAG PLACEMENT LOGIC
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				# Only place if valid AND if we haven't already placed on this exact tile in this drag action
				if can_place_current and snapped_pos != last_placed_pos:
					var recipe_idx = recipes.find(current_build_recipe)
					if recipe_idx != -1:
						rpc_id(1, "request_place_buildable", recipe_idx, snapped_pos)
						last_placed_pos = snapped_pos # Mark this tile as "done" for this drag
			else:
				# Reset last placed position when mouse is released
				last_placed_pos = Vector2.INF
		
		# --- DECONSTRUCTION LOGIC (When NOT building) ---
		else:
			ghost_sprite.hide()
			handle_deconstruction(delta)
		
		# Recipe List UI Logic
		if recipe_list and recipe_list.visible:
			if is_hovering_craft_button:
				pass
			else:
				var local_m = recipe_list.get_local_mouse_position()
				var list_rect = Rect2(Vector2.ZERO, recipe_list.size)
				if not list_rect.grow(5).has_point(local_m):
					recipe_list.hide()

		handle_input()
		handle_interaction(delta) 
		move_and_slide()
		
		current_tick += delta
		if current_tick >= network_tick_rate:
			current_tick = 0.0 
			_send_network_updates()
	else:
		global_position = global_position.lerp(target_position, lerp_speed * delta)

# --- NEW: Deconstruction Logic Function ---
func handle_deconstruction(delta):
	# FIX: Don't deconstruct if inventory is open
	if inventory and inventory.visible: 
		deconstruct_timer = 0.0
		progress_bar.visible = false
		return

	# If holding Right Click and NOT inside a menu/building mode
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var mouse_pos = get_global_mouse_position()
		var snapped_pos = mouse_pos.snapped(Vector2(grid_size, grid_size))
		
		# Move the detection area to the mouse
		ghost_area.global_position = snapped_pos
		
		# Detect walls
		var bodies = ghost_area.get_overlapping_bodies()
		var target_node = null
		
		for b in bodies:
			# FIX: Check for "wall" (lowercase) OR Group. Safer checking.
			if b != self and ("wall" in b.name.to_lower() or b.is_in_group("walls")):
				target_node = b
				break
		
		if target_node:
			deconstruct_timer += delta
			progress_bar.visible = true
			progress_bar.value = deconstruct_timer
			progress_bar.max_value = deconstruct_time
			progress_bar.modulate = Color(1, 0, 0) # Red for deleting
			
			if deconstruct_timer >= deconstruct_time:
				# Trigger Delete
				rpc_id(1, "request_deconstruct", target_node.get_path())
				deconstruct_timer = 0.0
				progress_bar.visible = false
		else:
			# Reset if mouse moved off target
			deconstruct_timer = 0.0
			progress_bar.visible = false
	else:
		# Reset when button released
		deconstruct_timer = 0.0
		# Only hide if we aren't interacting with something else
		if progress_bar.modulate == Color(1, 0, 0):
			progress_bar.visible = false

func _input(event):
	if not is_multiplayer_authority(): return
	
	# ADMIN CHEATS
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F1:
			rpc_id(1, "request_admin_give", "scrap", 100)
		elif event.keycode == KEY_F2:
			rpc_id(1, "request_admin_give", "fabric", 100)
		elif event.keycode == KEY_F3:
			rpc_id(1, "request_admin_give", "wall", 5)

	# CANCEL BUILDING (Right Click)
	if not current_build_recipe.is_empty() and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_building()
			if inventory: inventory.visible = true

# --- NEW: GENERIC BUILDING FUNCTIONS ---

# Triggered by buttons defined in the Recipe Inspector
func _on_build_item_pressed(recipe_index):
	if not is_multiplayer_authority(): return
	
	var r = recipes[recipe_index]
	var item_name = r["output_name"]
	
	# Check if we have the item in inventory
	if crafted_inventory.get(item_name, 0) > 0:
		current_build_recipe = r
		
		# UPDATED: Attempt to fetch sprite from scene first
		var found_texture = null
		if r.has("build_scene") and ResourceLoader.exists(r["build_scene"]):
			var scn = load(r["build_scene"])
			var inst = scn.instantiate()
			# Try to find a sprite node
			if inst.has_node("Sprite2D"):
				found_texture = inst.get_node("Sprite2D").texture
			elif inst is Sprite2D:
				found_texture = inst.texture
			inst.free() # Don't need the instance anymore
		
		if found_texture:
			ghost_sprite.texture = found_texture
		elif r.has("ghost_texture") and r["ghost_texture"] != "" and ResourceLoader.exists(r["ghost_texture"]):
			ghost_sprite.texture = load(r["ghost_texture"])
		else:
			# Fallback placeholder if nothing found
			var p = PlaceholderTexture2D.new()
			p.size = Vector2(grid_size, grid_size)
			ghost_sprite.texture = p

		# --- NEW GHOST SCALE LOGIC ---
		if r.has("ghost_scale") and r["ghost_scale"] != Vector2.ZERO:
			ghost_sprite.scale = r["ghost_scale"]
		else:
			# Auto-Scale logic (to make sure it fits grid)
			var s_size = ghost_sprite.texture.get_size()
			var max_dim = max(s_size.x, s_size.y)
			if max_dim > 0:
				var scale_fac = grid_size / max_dim
				ghost_sprite.scale = Vector2(scale_fac, scale_fac)
			else:
				ghost_sprite.scale = Vector2.ONE
		
		if inventory: inventory.visible = false
		print("Building: ", item_name)
	else:
		print("No ", item_name, " to place!")

func _cancel_building():
	current_build_recipe = {}
	ghost_sprite.hide()
	last_placed_pos = Vector2.INF

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
	is_hovering_craft_button = true 
	
	if not recipe_list: return
	
	for child in recipe_list.get_children():
		child.queue_free()
	
	recipe_list.show()
	
	var found_any = false
	for i in range(recipes.size()):
		var r = recipes[i]
		if scrap_in_crafting >= r["scrap_cost"] and fabric_in_crafting >= r["fabric_cost"]:
			var btn = Button.new()
			btn.text = r["name"]
			btn.pressed.connect(_on_recipe_selected.bind(i))
			recipe_list.add_child(btn)
			found_any = true
	
	if not found_any:
		var lbl = Label.new()
		lbl.text = "(None)"
		recipe_list.add_child(lbl)

func _on_combine_button_mouse_exited():
	is_hovering_craft_button = false 

func _on_recipe_selected(index):
	rpc_id(1, "request_craft_from_table", index)

func _on_scrap_button_pressed():
	if not is_multiplayer_authority(): return
	if scrap_amount >= 10: rpc_id(1, "request_transfer_scrap", 10) 

func _on_crafting_scrap_pressed():
	if not is_multiplayer_authority(): return
	if scrap_in_crafting >= 10: rpc_id(1, "request_return_scrap", 10)

func _on_fabric_button_pressed():
	if not is_multiplayer_authority(): return
	if fabric_amount >= 5: rpc_id(1, "request_transfer_fabric", 5)

func _on_crafting_fabric_pressed():
	if not is_multiplayer_authority(): return
	if fabric_in_crafting >= 5: rpc_id(1, "request_return_fabric", 5)

func _on_combine_button_pressed():
	if not is_multiplayer_authority(): return
	_on_combine_button_mouse_entered()

func _on_bandage_button_pressed():
	if not is_multiplayer_authority(): return
	if crafted_inventory.get("bandage", 0) > 0:
		if health < max_health: rpc_id(1, "request_use_item", "bandage")

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

# UPDATED: Replaces request_place_wall_item with Generic Builder
@rpc("any_peer", "call_local", "reliable")
func request_place_buildable(recipe_index, pos):
	if multiplayer.is_server():
		var r = recipes[recipe_index]
		var item_name = r["output_name"]
		
		# 1. Check Inventory
		if crafted_inventory.get(item_name, 0) > 0:
			# 2. Consume Item
			crafted_inventory[item_name] -= 1
			if crafted_inventory[item_name] <= 0:
				crafted_inventory.erase(item_name)
			sync_state_to_everyone()
			
			# 3. Spawn the Scene
			if r.has("build_scene"):
				var scene_path = r["build_scene"]
				if ResourceLoader.exists(scene_path):
					var s = load(scene_path).instantiate()
					s.global_position = pos
					s.name = item_name + "_" + str(randi())
					get_parent().add_child(s, true)
				else:
					print("Error: Build scene not found: ", scene_path)

# NEW: Server Logic to Delete Node and Refund
@rpc("any_peer", "call_local", "reliable")
func request_deconstruct(node_path):
	if multiplayer.is_server():
		var node = get_node_or_null(node_path)
		if node:
			# FIX: Case insensitive check OR Group check
			if "wall" in node.name.to_lower() or node.is_in_group("walls"):
				# Refund 1 Wall Item
				if not crafted_inventory.has("wall"): crafted_inventory["wall"] = 0
				crafted_inventory["wall"] += 1
				
				node.queue_free()
				sync_state_to_everyone()
				print("Deconstructed: ", node.name)

@rpc("any_peer", "call_local", "reliable")
func request_admin_give(type: String, amount: int):
	if multiplayer.is_server():
		if type == "scrap":
			scrap_amount += amount
		elif type == "fabric":
			fabric_amount += amount
		elif type == "wall":
			if not crafted_inventory.has("wall"): crafted_inventory["wall"] = 0
			crafted_inventory["wall"] += amount
		
		sync_state_to_everyone()

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
	col.shape.radius = 88.36 
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
