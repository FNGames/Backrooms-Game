extends CharacterBody2D

# --- CONFIGURATION ---
@export var speed: float = 300.0
@export var lerp_speed: float = 20.0



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

# --- RESOURCES ---
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

@onready var inv: CanvasLayer = $Inv


# --- INVENTORY VISUALS (Left Side) ---
@onready var red_placholder: Sprite2D = $Inv/InvControl/Sprite2D/ScarpAmmount/RedPlacholder
@onready var red_placholder_2: Sprite2D = $Inv/InvControl/Sprite2D/ScarpAmmount/RedPlacholder2
@onready var red_placholder_3: Sprite2D = $Inv/InvControl/Sprite2D/ScarpAmmount/RedPlacholder3
@onready var red_placholder_4: Sprite2D = $Inv/InvControl/Sprite2D/ScarpAmmount/RedPlacholder4

# --- CRAFTING AREA VISUALS (Right Side) ---
@onready var craft_scrap_1: Sprite2D = $Inv/InvControl/CraftingArea/CraftScrap1
@onready var craft_scrap_2: Sprite2D = $Inv/InvControl/CraftingArea/CraftScrap2
@onready var craft_scrap_3: Sprite2D = $Inv/InvControl/CraftingArea/CraftScrap3
@onready var craft_scrap_4: Sprite2D = $Inv/InvControl/CraftingArea/CraftScrap4

# --- CRAFTED ITEMS (New Area) ---
@onready var metal_icon: Sprite2D = $Inv/InvControl/CraftedItems/MetalIcon
@onready var bandage_icon: Sprite2D = $Inv/InvControl/CraftedItems/BandageIcon

# --- TOOLTIP UI (New) ---
# Create a Label named "RecipeTooltip" inside InvControl
@onready var recipe_tooltip: Label = $Inv/InvControl/RecipeTooltip

func _ready():
	motion_mode = MOTION_MODE_FLOATING
	var id = name.to_int()
	if id != 0: set_multiplayer_authority(id)
	
	print("Player Ready. Name: ", name, " Authority: ", get_multiplayer_authority())
	
	target_position = global_position
	_setup_interaction_components()
	
	var camera = get_node_or_null("Camera2D")

	if is_multiplayer_authority():
		if not camera:
			camera = Camera2D.new()
			add_child(camera)
		camera.make_current()
		modulate = Color(0.5, 1, 0.5) 
		
		if has_node("Inv"): $Inv.visible = true
		inv.visible = false 
		
		# Init visuals
		if recipe_tooltip: recipe_tooltip.hide()
		update_inventory_visuals() 
		
		await get_tree().create_timer(0.5).timeout
		can_send_updates = true
	else:
		if camera: camera.enabled = false
		modulate = Color(1, 0.5, 0.5) 
		progress_bar.visible = false 
		if has_node("Inv"): $Inv.visible = false
	
	if not craft_scrap_1: print("WARNING: CraftScrap1 node missing!")

func _physics_process(delta):
	if is_multiplayer_authority():
		if Input.is_action_just_pressed("ui_accept"):
			inv.visible = not inv.visible
			
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
	# --- 1. PUBLIC VISUALS (Labels) ---
	if score_label: score_label.text = "Scrap: " + str(scrap_amount)
	if fabric_label: fabric_label.text = "Fabric: " + str(fabric_amount)

	# --- 2. PRIVATE VISUALS (Bag & Table) ---
	if not is_multiplayer_authority(): return

	# HIDE EVERYTHING
	if red_placholder: red_placholder.hide()
	if red_placholder_2: red_placholder_2.hide()
	if red_placholder_3: red_placholder_3.hide()
	if red_placholder_4: red_placholder_4.hide()
	
	if craft_scrap_1: craft_scrap_1.hide()
	if craft_scrap_2: craft_scrap_2.hide()
	if craft_scrap_3: craft_scrap_3.hide()
	if craft_scrap_4: craft_scrap_4.hide()
	
	# SHOW BAG ITEMS
	if scrap_amount >= 10 and red_placholder: red_placholder.show()
	if scrap_amount >= 20 and red_placholder_2: red_placholder_2.show()
	if scrap_amount >= 30 and red_placholder_3: red_placholder_3.show()
	if scrap_amount >= 40 and red_placholder_4: red_placholder_4.show()
	
	# SHOW TABLE ITEMS
	if scrap_in_crafting >= 10 and craft_scrap_1: craft_scrap_1.show()
	if scrap_in_crafting >= 20 and craft_scrap_2: craft_scrap_2.show()
	if scrap_in_crafting >= 30 and craft_scrap_3: craft_scrap_3.show()
	if scrap_in_crafting >= 40 and craft_scrap_4: craft_scrap_4.show()

	# --- 3. CRAFTED ITEM ICONS ---
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

# --- BUTTONS ---

# NEW: Hover Logic for Combine Button
# Connect 'mouse_entered' signal from CombineButton to this function
func _on_combine_button_mouse_entered():
	if not is_multiplayer_authority(): return
	if not recipe_tooltip: return
	
	recipe_tooltip.show()
	recipe_tooltip.text = "Recipes:\n"
	
	var found_any = false
	for r in recipes:
		# Check if table contents meet the requirement for this recipe
		if scrap_in_crafting >= r["scrap_cost"] and fabric_in_crafting >= r["fabric_cost"]:
			recipe_tooltip.text += "-> " + r["name"] + "\n"
			found_any = true
	
	if not found_any:
		recipe_tooltip.text += "(None)"

# Connect 'mouse_exited' signal from CombineButton to this function
func _on_combine_button_mouse_exited():
	if recipe_tooltip: recipe_tooltip.hide()

func _on_scrap_button_pressed():
	if not is_multiplayer_authority(): return
	if scrap_amount >= 10: rpc_id(1, "request_transfer_scrap", 10) 

func _on_crafting_scrap_pressed():
	if not is_multiplayer_authority(): return
	if scrap_in_crafting >= 10: rpc_id(1, "request_return_scrap", 10)

func _on_combine_button_pressed():
	if not is_multiplayer_authority(): return
	var found_recipe = -1
	for i in range(recipes.size()):
		var r = recipes[i]
		if scrap_in_crafting >= r["scrap_cost"] and fabric_in_crafting >= r["fabric_cost"]:
			found_recipe = i
			break
	if found_recipe != -1: rpc_id(1, "request_craft_from_table", found_recipe)

# --- NETWORKING LOGIC ---

func sync_state_to_everyone():
	if not multiplayer.is_server(): return
	
	rpc("update_resources", scrap_amount, fabric_amount, scrap_in_crafting, fabric_in_crafting)
	
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
			print("Server: Crafted ", out_name)

# --- RELIABLE UPDATE (FIXED: Added any_peer) ---

@rpc("any_peer", "call_local", "reliable")
func update_resources(s_amt, f_amt, s_table, f_table):
	if not multiplayer.is_server(): print("Client: Resources Updated. Scrap: ", s_amt)
	scrap_amount = s_amt
	fabric_amount = f_amt
	scrap_in_crafting = s_table
	fabric_in_crafting = f_table
	update_inventory_visuals()

@rpc("any_peer", "call_local", "reliable")
func update_crafted_inventory_safe(json_data):
	var parsed = JSON.parse_string(json_data)
	if parsed is Dictionary:
		crafted_inventory = parsed
	else:
		crafted_inventory = {}
	update_inventory_visuals()

# --- INTERACTION & PICKUP ---

@rpc("any_peer", "call_local", "reliable")
func request_collect_resource(pile_path, type):
	if multiplayer.is_server():
		var pile = get_node_or_null(pile_path)
		if pile != null:
			print("Server: Collecting ", type, " for ", name)
			
			if type == "fabric":
				self.fabric_amount += 5
			else:
				self.scrap_amount += 10
			
			sync_state_to_everyone()
			rpc("trigger_pickup_visuals", type)
			pile.collect()

# --- STANDARD SETUP (unchanged) ---

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

func _input(event):
	if not is_multiplayer_authority(): return
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if scrap_amount >= 1:
			var mouse_pos = get_global_mouse_position()
			rpc_id(1, "request_place_wall", mouse_pos)

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

func handle_interaction(delta):
	if current_pile != null and Input.is_action_pressed("Interact"):
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
