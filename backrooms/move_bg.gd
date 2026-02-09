extends Sprite2D
# or TextureRect — works the same

@export var max_offset := Vector2(30, 20) # how far it can move
@export var smoothness := 6.0              # higher = snappier

var center_pos: Vector2

func _ready():
	center_pos = position

func _process(delta):
	var viewport_size = get_viewport_rect().size
	var mouse_pos = get_viewport().get_mouse_position()

	# Convert mouse position to -1 → 1 range
	var normalized = (mouse_pos / viewport_size) * 2.0 - Vector2.ONE

	# Apply offset
	var target_offset = Vector2(
		normalized.x * max_offset.x,
		normalized.y * max_offset.y
	)

	# Smooth movement
	position = position.lerp(center_pos + target_offset, smoothness * delta)
