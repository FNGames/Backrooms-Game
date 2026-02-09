extends Button
@onready var play_export_2: Sprite2D = $PlayExport2
@onready var tick_sound: AudioStreamPlayer2D = $"../../TickSound"
@onready var v_box_container: VBoxContainer = $"../../VBoxContainer"


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	v_box_container.hide()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_pressed() -> void:
	v_box_container.show()


func _on_mouse_exited() -> void:
	play_export_2.hide()


func _on_mouse_entered() -> void:
	play_export_2.show()
	tick_sound.play()
