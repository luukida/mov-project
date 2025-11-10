extends Node3D

# Vamos arrastar nossa cena DamageNumber.tscn aqui no Inspector
@export var damage_number_scene: PackedScene
@onready var spawn_timer = $EnemySpawnTimer

# Referências à nossa câmera e UI
@onready var camera = $CameraRig/Camera3D
@onready var ui_layer = $CanvasLayer
@onready var min_spawn_time: float = 1.5
@onready var max_spawn_time: float = 6.0
@onready var nav_region = $GridMaps/NavigationRegion3D

const enemy_scene = preload("res://Scenes/enemy.tscn")


func _ready():
	spawn_timer.timeout.connect(_on_enemy_spawn_timer_timeout)
	_on_enemy_spawn_timer_timeout()

func _on_enemy_was_hit(damage_amount, world_position):

	# 1. Instancia nossa cena de número de dano
	var number_instance = damage_number_scene.instantiate()

	# A posição de spawn é exatamente a posição da barra de vida.
	var spawn_pos = world_position

	# 2. Adiciona o número ao mundo 3D
	add_child(number_instance)

	# 3. Inicia o número na nova posição, mais próxima
	number_instance.start(damage_amount, spawn_pos)

# Esta função é chamada toda vez que o EnemySpawnTimer termina
func _on_enemy_spawn_timer_timeout():
	# 1. PEGAR UM PONTO ALEATÓRIO (A parte difícil)
	
	# Pega o mapa de navegação (RID) da nossa região
	var nav_map = nav_region.get_navigation_map()
	
	# Pede ao servidor de navegação um ponto aleatório nesse mapa
	var spawn_point = NavigationServer3D.map_get_random_point(nav_map, 1, false)
	
	# O ponto retornado é *exatamente* no chão. Vamos subir um pouco
	# para que o inimigo não spawne "dentro" do chão.
	#spawn_point.y -= 0.2

	# 2. SPAWNAR O INIMIGO
	var enemy_instance = enemy_scene.instantiate()
	enemy_instance.was_hit.connect(_on_enemy_was_hit)
	enemy_instance.global_position = spawn_point
	
	# Adiciona o inimigo como filho do MainGame (ou de um nó "Enemies")
	add_child(enemy_instance)
	
	print("Inimigo spawnado em: ", spawn_point)

	# 3. REINICIAR O TIMER (A parte do tempo aleatório)
	
	# Define o próximo tempo de espera para um novo valor aleatório
	spawn_timer.wait_time = randf_range(min_spawn_time, max_spawn_time)
	# Reinicia o timer
	spawn_timer.start()
