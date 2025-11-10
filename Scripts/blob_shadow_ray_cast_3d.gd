extends RayCast3D

@export var rigidbody: CharacterBody3D
@onready var blobshadow = $BlobShadow

func _process(_delta: float) -> void:
	global_position = rigidbody.global_position
	
	if is_colliding():
		blobshadow.show()
		blobshadow.global_position = get_collision_point()
	else:
		blobshadow.hide()
	
