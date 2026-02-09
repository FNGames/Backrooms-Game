extends Sprite2D

@export var images: Array[Texture2D] = []
@export var image_scales: Array[Vector2] = [] # per-image scale

@export var fade_time := 1.2
@export var black_pause := 0.08
@export var hold_time := 3.0

@export var zoom_amount := 1.05      # max zoom factor for each image
@export var max_offset := Vector2(30, 20)
@export var smoothness := 6.0

var index := 0
var center_pos: Vector2
var base_scale: Vector2
var zoom_tween: Tween

func _ready():
	if images.is_empty():
		push_warning("No images assigned!")
		return

	center_pos = position

	# make sure image_scales matches images
	while image_scales.size() < images.size():
		image_scales.append(scale) # default scale if not set

	base_scale = image_scales[0]
	texture = images[0]
	scale = base_scale
	modulate = Color.WHITE
	randomize()

	_run_slideshow()

func _process(delta):
	# mouse parallax
	var viewport_size = get_viewport_rect().size
	var mouse_pos = get_viewport().get_mouse_position()

	var normalized = (mouse_pos / viewport_size) * 2.0 - Vector2.ONE
	var target_offset = Vector2(
		normalized.x * max_offset.x,
		normalized.y * max_offset.y
	)

	position = position.lerp(center_pos + target_offset, smoothness * delta)

func _run_slideshow():
	while true:
		_start_slow_zoom()
		await get_tree().create_timer(hold_time).timeout
		await _fade_swap()

func _start_slow_zoom():
	if zoom_tween and zoom_tween.is_running():
		zoom_tween.kill()

	# zoom from current scale to target
	var target_scale = base_scale * zoom_amount
	zoom_tween = create_tween()
	zoom_tween.tween_property(
		self,
		"scale",
		target_scale,
		hold_time + fade_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _fade_swap():
	# fade to black
	var dark := create_tween()
	dark.tween_property(self, "modulate", Color.BLACK, fade_time * 0.45)
	await dark.finished

	# reset scale while black
	var reset_zoom := create_tween()
	reset_zoom.tween_property(self, "scale", base_scale, black_pause)
	await reset_zoom.finished

	# swap image
	index = (index + 1) % images.size()
	texture = images[index]
	base_scale = image_scales[index] # use this image’s scale

	scale = base_scale # set immediately for next zoom

	# fade back to white
	var light := create_tween()
	light.tween_property(self, "modulate", Color.WHITE, fade_time * 0.55)
	await light.finished
