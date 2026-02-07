extends Area2D

func _ready():
	add_to_group("scrap")
	
	# --- VISUALS ---
	if not has_node("Sprite2D"):
		var s = Sprite2D.new()
		var placeholder = PlaceholderTexture2D.new()
		placeholder.size = Vector2(32, 32)
		s.texture = placeholder
		s.modulate = Color(0.6, 0.4, 0.2)
		add_child(s)
	
	if not has_node("CollisionShape2D"):
		var c = CollisionShape2D.new()
		var rect = RectangleShape2D.new()
		rect.size = Vector2(40, 40)
		c.shape = rect
		add_child(c)

	# --- SYNC FIX ---
	# Automatically adds a Synchronizer so the position syncs to clients
	var synch = MultiplayerSynchronizer.new()
	synch.replication_config = SceneReplicationConfig.new()
	# This line tells Godot: "Sync the global_position of this object"
	synch.replication_config.add_property(".:global_position")
	add_child(synch)

@rpc("call_local")
func collect():
	queue_free()
