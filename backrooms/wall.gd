extends StaticBody2D

func _ready():
	# --- VISUALS ---
	if not has_node("Sprite2D"):
		var s = Sprite2D.new()
		var p = PlaceholderTexture2D.new()
		p.size = Vector2(40, 40)
		s.texture = p
		s.modulate = Color(0.5, 0.5, 0.5)
		add_child(s)
	
	if not has_node("CollisionShape2D"):
		var c = CollisionShape2D.new()
		var rect = RectangleShape2D.new()
		rect.size = Vector2(40, 40)
		c.shape = rect
		add_child(c)

	# --- SYNC FIX ---
	# Syncs position for placed walls so they appear where you clicked
	var synch = MultiplayerSynchronizer.new()
	synch.replication_config = SceneReplicationConfig.new()
	synch.replication_config.add_property(".:global_position")
	add_child(synch)
