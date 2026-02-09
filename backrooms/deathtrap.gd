extends Area2D

# How much damage this area deals instantly
@export var damage_amount: int = 10

func _on_body_entered(body):
	# Only the SERVER decides if damage happens
	if not multiplayer.is_server(): return
	
	# Check if the object entering is a Player (has 'take_damage' function)
	if body.has_method("take_damage"):
		print("Player stepped in damage zone!")
		body.take_damage(damage_amount)
