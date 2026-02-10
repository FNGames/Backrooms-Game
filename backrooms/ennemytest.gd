extends CharacterBody2D

@export var speed: float = 120.0
@export var damage: int = 10
@export var attack_range: float = 50.0
@export var attack_cooldown: float = 1.0

# Navigation Agent is crucial for smart pathfinding
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

var target_player: CharacterBody2D = null
var attack_timer: float = 0.0

func _ready():
	# Server Authority (Host) handles AI logic
	if not multiplayer.is_server():
		set_physics_process(false) # Clients don't calculate AI
	
	# Setup Visuals (Red Circle) if not present
	if not has_node("Sprite2D"):
		var s = Sprite2D.new()
		var p = PlaceholderTexture2D.new()
		p.size = Vector2(35, 35)
		s.texture = p
		s.modulate = Color(1, 0, 0) # Red color for Enemy
		add_child(s)
	
	if not has_node("CollisionShape2D"):
		var c = CollisionShape2D.new()
		var shape = CircleShape2D.new()
		shape.radius = 18
		c.shape = shape
		add_child(c)
	
	# Create Navigation Agent dynamically if missing
	if not has_node("NavigationAgent2D"):
		var n = NavigationAgent2D.new()
		n.path_desired_distance = 20.0
		n.target_desired_distance = 20.0
		n.path_max_distance = 100.0
		n.avoidance_enabled = true # Avoid other enemies
		n.radius = 20.0
		add_child(n)
		nav_agent = n
	
	# Sync Position to clients
	var synch = MultiplayerSynchronizer.new()
	synch.replication_config = SceneReplicationConfig.new()
	synch.replication_config.add_property(".:global_position")
	add_child(synch)

func _physics_process(delta):
	# 1. Find the nearest player
	_find_target()
	
	# 2. Movement Logic
	if target_player:
		# Update path target
		nav_agent.target_position = target_player.global_position
		
		# Get next point on path (avoids walls!)
		if not nav_agent.is_navigation_finished():
			var next_pos = nav_agent.get_next_path_position()
			var direction = global_position.direction_to(next_pos)
			velocity = direction * speed
			move_and_slide()
		
		# 3. Attack Logic
		var dist = global_position.distance_to(target_player.global_position)
		if dist <= attack_range:
			attack_timer -= delta
			if attack_timer <= 0:
				_attack_player()
				attack_timer = attack_cooldown

func _find_target():
	var players = get_tree().get_nodes_in_group("players")
	var shortest_dist = INF
	var nearest = null
	
	for p in players:
		var d = global_position.distance_to(p.global_position)
		if d < shortest_dist:
			shortest_dist = d
			nearest = p
	
	target_player = nearest

func _attack_player():
	if target_player.has_method("take_damage"):
		target_player.take_damage(damage)
