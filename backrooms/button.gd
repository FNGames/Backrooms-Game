extends Button
@onready var play_export: Sprite2D = $PlayExport
@onready var tick_sound: AudioStreamPlayer2D = $"../../TickSound"


func _on_mouse_entered() -> void:
	play_export.show()
	tick_sound.play()

func _on_mouse_exited() -> void:
	play_export.hide()
