extends Area2D

func _ready():
	# Add to a group so the player can detect it easily
	add_to_group("scrap")
	
	# SETUP VISUALS (If you haven't added them in Editor)
	# This ensures there is something to see even if you just use a blank node
	if not has_node("Sprite2D"):
		var s = Sprite2D.new()
		# Use a built-in icon or placeholder color
		var placeholder = PlaceholderTexture2D.new()
		placeholder.size = Vector2(32, 32)
		s.texture = placeholder
		s.modulate = Color(0.6, 0.4, 0.2) # Brown-ish color
		add_child(s)
	
	if not has_node("CollisionShape2D"):
		var c = CollisionShape2D.new()
		var rect = RectangleShape2D.new()
		rect.size = Vector2(40, 40)
		c.shape = rect
		add_child(c)

# Called by the server when a player collects this
@rpc("call_local")
func collect():
	# Play a sound or particle effect here if you want!
	queue_free() # Delete object from the game poop
