extends Button
@onready var play_export: Sprite2D = $PlayExport


func _on_mouse_entered() -> void:
	play_export.show()


func _on_mouse_exited() -> void:
	play_export.hide()
