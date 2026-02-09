extends Sprite2D

@export var frame_count := 3

@export var min_delay := 3.0   # time hidden
@export var max_delay := 7.0

@export var min_visible := 0.2 # time visible
@export var max_visible := 0.4

func _ready():
	randomize()
	hide()
	_random_loop()

func _random_loop():
	while true:
		# wait while hidden
		await get_tree().create_timer(randf_range(min_delay, max_delay)).timeout

		# pick random frame + show
		frame = randi() % frame_count
		show()

		# stay visible
		await get_tree().create_timer(randf_range(min_visible, max_visible)).timeout

		hide()
