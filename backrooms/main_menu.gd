extends CanvasLayer

@onready var animated_sprite_2d: AnimatedSprite2D = $Fuzz
@onready var main_menu: CanvasLayer = $"."
@onready var blue_screen: AnimatedSprite2D = $"Blue Screen"
@onready var fuzz_sound: AudioStreamPlayer2D = $FuzzSound
@onready var humming: AudioStreamPlayer2D = $Humming
@onready var vhsclcik: AudioStreamPlayer2D = $VHSCLCIK
@onready var bg_music: AudioStreamPlayer2D = $"BG MUSIC"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	humming.play()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_button_pressed() -> void:
	humming.stop()
	vhsclcik.play()
	await get_tree().create_timer(0.70).timeout
	fuzz_sound.play()
	animated_sprite_2d.show()
	animated_sprite_2d.play("default")
	await get_tree().create_timer(2.5).timeout
	blue_screen.show()
	blue_screen.play("default")
	await get_tree().create_timer(1.1).timeout
	blue_screen.hide()
	main_menu.hide()
	get_tree().change_scene_to_file("res://lobby.tscn")
