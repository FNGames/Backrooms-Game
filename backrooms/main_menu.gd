extends CanvasLayer

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var main_menu: CanvasLayer = $"."

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_button_pressed() -> void:
	animated_sprite_2d.show()
	animated_sprite_2d.play("default")
	await get_tree().create_timer(0.5).timeout
	main_menu.hide()
