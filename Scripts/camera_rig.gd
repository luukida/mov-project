extends Node3D

# You can adjust this in the Inspector to change rotation speed.
@export var rotation_sensitivity = 0.2

# Drag your player node here from the scene tree.
@export var target_node: Node3D

func _process(_delta):
	# Make the camera rig always follow the target's position.
	if target_node:
		global_position = target_node.global_position

func _unhandled_input(event):
	# Check if the right mouse button is held down and the mouse is moving.
	if event is InputEventMouseMotion and Input.is_action_pressed("camera_rotate"):
		# Rotate the rig on the Y-axis based on horizontal mouse movement.
		rotate_y(deg_to_rad(-event.relative.x * rotation_sensitivity))
