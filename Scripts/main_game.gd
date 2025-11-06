extends Node3D

# Vamos arrastar nossa cena DamageNumber.tscn aqui no Inspector
@export var damage_number_scene: PackedScene

# Referências à nossa câmera e UI
@onready var camera = $CameraRig/Camera3D
@onready var ui_layer = $CanvasLayer


func _on_enemy_was_hit(damage_amount, world_position):

	# 1. Instancia nossa cena de número de dano
	var number_instance = damage_number_scene.instantiate()

	# A posição de spawn é exatamente a posição da barra de vida.
	var spawn_pos = world_position

	# 2. Adiciona o número ao mundo 3D
	add_child(number_instance)

	# 3. Inicia o número na nova posição, mais próxima
	number_instance.start(damage_amount, spawn_pos)
