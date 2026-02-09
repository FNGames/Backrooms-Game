extends Control

@onready var volume_slider: HSlider = $VBoxContainer/HSliderContainer/HSlider
@onready var fullscreen_checkbox: CheckBox = $VBoxContainer/CheckBox
@onready var resolution_option: OptionButton = $VBoxContainer/OptionButton
@onready var back_button: Button = $VBoxContainer/Button

func _ready():
	# Fill resolution options
	var res_list = [
		Vector2i(1920, 1080),
		Vector2i(1600, 900),
		Vector2i(1366, 768),
		Vector2i(1280, 720)
	]
	for res in res_list:
		resolution_option.add_item("%dx%d" % [res.x, res.y])
	
	# Set current resolution
	var current_res = DisplayServer.window_get_size()
	for i in range(resolution_option.get_item_count()):
		var item_text = resolution_option.get_item_text(i)
		if item_text == "%dx%d" % [current_res.x, current_res.y]:
			resolution_option.select(i)
			break

	# Set fullscreen checkbox
	fullscreen_checkbox.pressed = DisplayServer.window_get_mode() == DisplayServer.WindowMode.FULLSCREEN

	# Set volume slider (0-1)
	volume_slider.min_value = 0
	volume_slider.max_value = 1
	volume_slider.step = 0.01
	var master_bus = AudioServer.get_bus_index("Master")
	var db = AudioServer.get_bus_volume_db(master_bus)
	volume_slider.value = pow(10.0, db / 20.0)

	# Connect signals
	volume_slider.value_changed.connect(Callable(self, "_on_volume_changed"))
	fullscreen_checkbox.toggled.connect(Callable(self, "_on_fullscreen_toggled"))
	resolution_option.item_selected.connect(Callable(self, "_on_resolution_selected"))
	back_button.pressed.connect(Callable(self, "_on_back_pressed"))

func _on_volume_changed(value):
	var master_bus = AudioServer.get_bus_index("Master")
	var db = 20.0 * Math.log10(value)
	AudioServer.set_bus_volume_db(master_bus, db)

func _on_fullscreen_toggled(pressed):
	if pressed:
		DisplayServer.window_set_mode(DisplayServer.WindowMode.FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WindowMode.WINDOWED)

func _on_resolution_selected(index):
	var res_text = resolution_option.get_item_text(index)
	var parts = res_text.split("x")
	var new_res = Vector2i(parts[0].to_int(), parts[1].to_int())
	DisplayServer.window_set_size(new_res)

func _on_back_pressed():
	hide() # or emit a signal to switch menus
