extends Sprite2D

@onready var recording_red: Sprite2D = $"."

func _ready() -> void:
	flash_loop()

func flash_loop() -> void:
	while true:
		recording_red.frame = 0
		await get_tree().create_timer(1.0).timeout
		recording_red.frame = 1
		await get_tree().create_timer(1.0).timeout
