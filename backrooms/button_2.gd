extends Button
@onready var play_export_2: Sprite2D = $PlayExport2
@onready var tick_sound: AudioStreamPlayer2D = $"../../TickSound"


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_pressed() -> void:
	pass # Replace with function body.


func _on_mouse_exited() -> void:
	play_export_2.hide()


func _on_mouse_entered() -> void:
	play_export_2.show()
	tick_sound.play()
