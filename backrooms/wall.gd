extends StaticBody2D

func _ready():
	# 1. VISUALS (Grey Cube)
	if not has_node("Sprite2D"):
		var s = Sprite2D.new()
		var p = PlaceholderTexture2D.new()
		p.size = Vector2(40, 40)
		s.texture = p
		s.modulate = Color(0.5, 0.5, 0.5) # Grey color
		add_child(s)
	
	# 2. COLLISION
	if not has_node("CollisionShape2D"):
		var c = CollisionShape2D.new()
		var rect = RectangleShape2D.new()
		rect.size = Vector2(40, 40)
		c.shape = rect
		add_child(c)
