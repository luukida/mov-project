extends CharacterBody3D

var gravity = abs(ProjectSettings.get_setting("physics/3d/default_gravity"))
var is_dead = false 
var state_machine

@export var speed: float = 0.3
@export var attack_damage: float = 10.0

# Referências aos nossos nós filhos
@onready var nav_agent = $NavigationAgent3D
@onready var stats = $Stats
@onready var attack_area = $Skeleton_Minion/AttackArea
@onready var sensor_area = $SensorArea
@onready var player = get_node("/root/MainGame/Player")
@onready var skeleton_minion = $Skeleton_Minion
@onready var enemy_collision_shape = $EnemyCollisionShape
@onready var health_bar = $HealthBarViewport/HealthBar
@onready var health_bar_sprite = $HealthBarSprite
@onready var animation_player = $AnimationPlayer
@onready var animation_tree = $AnimationTree

signal was_hit(damage_amount, world_position)

# --- NOMES DOS ESTADOS DA ANIMAÇÃO ---
var STATE_IDLE = "Rig_Medium_Special_Skeletons_Idle"
var STATE_WALK = "Rig_Medium_Special_Skeletons_Walking"
var STATE_ATTACK = "Rig_Medium_CombatMelee_Melee_1H_Attack_Stab"
var STATE_DEATH = "Rig_Medium_Special_Skeletons_Death"
var STATE_SPAWN = "Rig_Medium_Special_Skeletons_Spawn_Ground"


func _ready():
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 1.0
	
	# --- HEALTH BAR SETUP ---
	stats.health_changed.connect(_on_enemy_health_changed)
	
	health_bar.max_value = stats.max_health
	health_bar.value = stats.current_health
	
	health_bar_sprite.visible = false
	
	stats.damage_taken.connect(_on_damage_taken)
	
	animation_tree.active = true
	state_machine = animation_tree["parameters/playback"]
	

func _physics_process(delta):
	
	if not player or not nav_agent:
		return
		
	if not is_on_floor():
		velocity.y -= gravity * delta

	var current_state = state_machine.get_current_node()
	is_dead = (current_state == STATE_DEATH) 
	var is_attacking = (current_state == STATE_ATTACK)

	var player_in_sensor = sensor_area.overlaps_body(player)
	
	# Se o jogador estiver NO SENSOR, execute a IA de combate
	if player_in_sensor and not is_dead:
	
		var did_attack_this_frame = false
		var player_in_attack_area = attack_area.overlaps_body(player)
		
		# --- LÓGICA DE MOVIMENTO E ROTAÇÃO ---
		if not is_attacking and current_state != STATE_SPAWN:
			
			var target_pos = player.global_position
			target_pos.y = global_position.y
			nav_agent.set_target_position(target_pos)
			
			var next_path_pos = nav_agent.get_next_path_position()
			var direction = global_position.direction_to(next_path_pos)
			direction.y = 0
			direction = direction.normalized()
			
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
		
			if player:
				skeleton_minion.look_at(target_pos, Vector3.UP)
				skeleton_minion.rotate_y(deg_to_rad(180)) 
				
		else:
			# (Se estiver Atacando ou Morto)
			velocity.x = 0
			velocity.z = 0

		# --- LÓGICA DE COMBATE (SIMPLIFICADA) ---
		if player_in_attack_area and not is_attacking:
			animation_tree.set("parameters/conditions/attack", true)
			did_attack_this_frame = true
			
		else:
			animation_tree.set("parameters/conditions/attack", false)

		# --- LÓGICA DE HANDSHAKE (Conserta o loop infinito) ---
		if is_attacking:
			animation_tree.set("parameters/conditions/attack", false)
			
		# --- CORREÇÃO DO BUG "ATACANDO E ANDANDO" ---
		if did_attack_this_frame:
			velocity.x = 0
			velocity.z = 0
	
	else:
		# --- JOGADOR FORA DO SENSOR (ou morto) ---
		velocity.x = 0
		velocity.z = 0
		animation_tree.set("parameters/conditions/attack", false) # Garante que o ataque pare

	# --- FÍSICA E ANIMAÇÃO (FORA DO 'ELSE') ---
	move_and_slide()
	
	# --- LÓGICA DE ANIMAÇÃO (Idle/Walk) - CORRIGIDA ---
	if not is_dead:
		var moving = velocity.length() > 0.1
		animation_tree.set("parameters/conditions/is_moving", moving)
		animation_tree.set("parameters/conditions/is_idle", not moving)

# Esta função é chamada quando o nó "Stats" emite o sinal "no_health"
func _on_no_health():
	if is_dead: return 
	
	is_dead = true
	set_physics_process(false) 
	
	enemy_collision_shape.disabled = true
	attack_area.get_node("CollisionShape3D").disabled = true
	
	animation_tree.set("parameters/conditions/is_dead", true)
	
	await animation_tree.animation_finished
	queue_free() 

# Esta função será chamada PELA ANIMAÇÃO no frame de impacto.
func _apply_damage_on_hit():
	# 1. Pega uma lista de todos os corpos DENTRO da AttackArea AGORA
	var bodies_in_area = attack_area.get_overlapping_bodies()
	
	# 2. Procura pelo jogador nessa lista
	for body in bodies_in_area:
		if body == player:
			# 3. Encontrou o jogador! Causa o dano.
			var player_stats = player.get_node_or_null("Stats")
			if player_stats:
				print("ATAQUE CONECTADO!") # Ótimo para debug
				player_stats.take_damage(attack_damage)
				
				# 'break' para garantir que não acertemos o jogador várias vezes
				break

# --- HEALTH BAR FUNCTIONS ---

# Esta função é chamada quando o nó "Stats" emite "health_changed"
func _on_enemy_health_changed(current_health, max_health):
	# Atualiza os valores da barra de vida
	health_bar.value = current_health
	health_bar.max_value = max_health
	
	# Mostra a barra (o Sprite 3D) se o inimigo tomar dano,
	# e esconde se estiver com vida cheia (ex: curado).
	health_bar_sprite.visible = (current_health < max_health)

func _on_damage_taken(amount):
	# Envia a posição 3D exata do HealthBarSprite
	was_hit.emit(amount, health_bar_sprite.global_position)
