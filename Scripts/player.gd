extends CharacterBody3D

# --- EXPORTED VARIABLES (Visible in Inspector) ---

@export_category("External Nodes")
@export var camera_rig: Node3D

@export_category("Movement")
@export var max_speed = 2.5
@export var acceleration = 3.5
@export var friction = 30.0

@export_category("Jumping")
@export var jump_height: float = 1.7 : set = _set_jump_height
@export var jump_duration: float = 0.8 : set = _set_jump_duration
@export var jump_gravity_multiplier: float = 1.4 : set = _set_jump_gravity_multiplier
@export var jump_cutoff: float = 0.5
@export var max_jumps = 2
@export var jump_buffer_duration = 0.15 
@export var coyote_time_duration = 0.1

@export_category("Rolling")
@export var roll_distance: float = 1.3 : set = _set_roll_distance
@export var roll_duration: float = 0.5 : set = _set_roll_duration
@export var air_roll_distance: float = 2.5 : set = _set_air_roll_distance
@export var air_roll_duration: float = 0.6 : set = _set_air_roll_duration
@export var air_roll_vertical_boost: float = 3.0
@export var roll_slowdown_point: float = 0.2

@export_category("Crouching")
@export var crouch_speed = 0.5

@export_category("Stamina")
@export var max_stamina = 100.0
@export var stamina_regen_rate = 25.0
@export var stamina_regen_delay = 0.7

@export_category("Animation")
@export var min_animation_speed = 0.2
@export var max_animation_speed = 1.0

@export_category("Combat")
@export var attack_damage: float = 20.0
@export var attack_speed: float = 1.0 : set = _set_attack_speed

# --- INTERNAL STATE VARIABLES (Not in Inspector) ---
var _jump_velocity: float
var _jump_gravity: float
var _fall_gravity: float
var jumps_made = 0
var was_on_floor = false
var has_rolled_in_air = false
var is_rolling_in_ground = false
var roll_direction = Vector3.ZERO
var _roll_initial_velocity: float
var _roll_deceleration: float
var _air_roll_initial_velocity: float
var _air_roll_deceleration: float
var is_crouching = false
var current_stamina: float
var jump_buffer_bool = false
var enemies_in_range: Array = []
var current_target: Node3D = null
var _default_collision_mask: int
var _default_collision_layer: int
var health_tween: Tween # Para o feedback de dano

# --- NODE REFERENCES ---
@onready var animated_sprite = $AnimatedSprite3D
@onready var standing_shape = $StandingShape
@onready var crouching_shape = $CrouchingShape
@onready var stand_up_checker = $ShapeCast3D
@onready var coyote_timer = $CoyoteTimer
@onready var roll_timer = $RollTimer
@onready var air_roll_timer = $AirRollTimer
@onready var stamina_regen_timer = $StaminaRegenTimer
@onready var stamina_bars: Array[ProgressBar] = [
	$"../CanvasLayer/StaminaBarContainer/HBoxContainer/StaminaBar",
	$"../CanvasLayer/StaminaBarContainer/HBoxContainer/StaminaBar2",
	$"../CanvasLayer/StaminaBarContainer/HBoxContainer/StaminaBar3"
]
@onready var attack_range = $AutoAttackRange
@onready var attack_timer = $AttackTimer
@onready var stats = $Stats
@onready var attack_range_decal = $AttackRangeDecal

# --- Referências da Barra de Vida (MODIFICADO) ---
@onready var health_bar_front = $"../CanvasLayer/HealthBar_Front"
@onready var health_bar_back = $"../CanvasLayer/HealthBar_Back"

# --- NOVA REFERÊNCIA DA REATORAÇÃO ---
@onready var anim_tree = $AnimationTree

# --- CONSTANTS ---
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity") 

func _ready():
	standing_shape.disabled = false
	crouching_shape.disabled = true
	stand_up_checker.add_exception(self)

	current_stamina = max_stamina
	stamina_regen_timer.wait_time = stamina_regen_delay
	_update_stamina_display()

	coyote_timer.wait_time = coyote_time_duration

	_calculate_jump_parameters()
	_calculate_roll_parameters()
	_calculate_air_roll_parameters()
	
	_default_collision_mask = get_collision_mask()
	_default_collision_layer = get_collision_layer()
	
	# --- HEALTH BAR SETUP (MODIFICADO) ---
	health_bar_front.max_value = stats.max_health
	health_bar_front.value = stats.current_health
	health_bar_back.max_value = stats.max_health
	health_bar_back.value = stats.current_health
	stats.health_changed.connect(_on_player_health_changed)
	
	# --- COMBAT SETUP ---
	attack_timer.wait_time = 1.0 / attack_speed
	attack_range.body_entered.connect(_on_attack_range_body_entered)
	attack_range.body_exited.connect(_on_attack_range_body_exited)
	attack_timer.timeout.connect(_on_attack_timer_timeout)
	
	# --- ATIVA A ANIMATIONTREE ---
	anim_tree.active = true


func _physics_process(delta):
	# --- CORE LOGIC & RESETS ---
	var just_left_ground = not is_on_floor() and was_on_floor
	was_on_floor = is_on_floor() 

	if is_on_floor():
		jumps_made = 0
		has_rolled_in_air = false
	else: 
		if is_rolling_in_ground and not has_rolled_in_air:
			is_rolling_in_ground = false
		
		# Se cairmos de uma plataforma agachados, levanta automaticamente
		if is_crouching:
			is_crouching = false
			standing_shape.disabled = false
			crouching_shape.disabled = true

		# --- JUMP CUTOFF LOGIC ---
		if Input.is_action_just_released("jump") and velocity.y > 0:
			velocity.y *= jump_cutoff

		# --- START COYOTE TIMER ---
		if just_left_ground and jumps_made == 0:
			coyote_timer.start()

	if not is_on_floor():
		if velocity.y > 0:
			velocity.y += _jump_gravity * delta
		else:
			velocity.y += _fall_gravity * delta

	# Get universal input direction
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	var direction = (camera_rig.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var target_speed = max_speed 

	# --- STAMINA REGENERATION LOGIC ---
	if stamina_regen_timer.is_stopped() and current_stamina < max_stamina:
		current_stamina += stamina_regen_rate * delta
		current_stamina = min(current_stamina, max_stamina)
		_update_stamina_display()

	# --- STATE-BASED LOGIC (PRIORITY ORDER) - (REFATORADO) ---

	# STATE 1: Player is rolling
	if is_rolling_in_ground:
		# Lógica de FÍSICA de Roll (permanece)
		if has_rolled_in_air:
			velocity.x += roll_direction.x * _air_roll_deceleration * delta
			velocity.z += roll_direction.z * _air_roll_deceleration * delta
			if velocity.x * roll_direction.x + velocity.z * roll_direction.z < 0:
				velocity.x = 0
				velocity.z = 0
		else:
			velocity.x += roll_direction.x * _roll_deceleration * delta
			velocity.z += roll_direction.z * _roll_deceleration * delta
			if velocity.dot(roll_direction) < 0:
				velocity.x = 0
				velocity.z = 0

	# STATE 2: Player is crouching
	elif is_crouching:
		target_speed = crouch_speed # Define a velocidade de movimento

		# Checa se o jogador quer se levantar
		if not Input.is_action_pressed("crouch"):
			if not stand_up_checker.is_colliding():
				# Lógica de ESTADO:
				is_crouching = false 
				# Lógica de FÍSICA:
				standing_shape.disabled = false
				crouching_shape.disabled = true
				# A AnimationTree vai pegar "is_crouching = false" e
				# iniciar a transição "CrouchUp" sozinha.

	# STATE 3: Standard Gameplay (Não está rolando, nem agachado)
	else:
		# Checa se o jogador quer se agachar
		if Input.is_action_just_pressed("crouch") and is_on_floor():
			# Lógica de ESTADO:
			is_crouching = true 
			# Lógica de FÍSICA:
			standing_shape.disabled = true
			crouching_shape.disabled = false
			# A AnimationTree vai pegar "is_crouching = true" e
			# iniciar a transição "CrouchDown" sozinha.
		
		# Se não estiver começando a agachar, checa pulo e roll
		else:
			# --- JUMP LOGIC (Física e Estado) ---
			var jump_pressed_this_frame = Input.is_action_just_pressed("jump")
			var perform_jump = false
			var is_first_jump = false

			# (Condições 1, 2, 3, 4 de pulo permanecem idênticas)
			# ...
			if jump_pressed_this_frame and jumps_made == 0 and not is_on_floor() and not coyote_timer.is_stopped():
				perform_jump = true
				is_first_jump = true
				coyote_timer.stop() 
			elif is_on_floor() and (jump_pressed_this_frame or jump_buffer_bool):
				perform_jump = true
				is_first_jump = true
				jump_buffer_bool = false 
			elif jump_pressed_this_frame and not is_on_floor() and jumps_made > 0 and jumps_made < max_jumps:
				perform_jump = true
				is_first_jump = false
				jump_buffer_bool = false 
			elif jump_pressed_this_frame and not is_on_floor():
				if not jump_buffer_bool and jumps_made >= max_jumps:
					jump_buffer_bool = true
					get_tree().create_timer(jump_buffer_duration).timeout.connect(_on_jump_buffer_timeout) 

			# --- EXECUTE JUMP (Física e Estado) ---
			if perform_jump:
				if is_first_jump:
					jumps_made = 1
				else: 
					jumps_made += 1
				
				velocity.y = _jump_velocity
				
				coyote_timer.stop() 
				jump_buffer_bool = false 

			# --- ROLL LOGIC (Física e Estado) ---
			elif Input.is_action_just_pressed("special_action"):
				var cost_one_bar = max_stamina / 3.0
				var cost_two_bars = cost_one_bar * 2.0
				
				# Ground roll
				if is_on_floor():
					if current_stamina >= cost_one_bar:
						current_stamina -= cost_one_bar
						_update_stamina_display()
						stamina_regen_timer.start()
						
						stats.is_invulnerable = true
						set_collision_mask_value(3, false) 
						set_collision_layer_value(1, false)

						is_rolling_in_ground = true 

						var roll_dir = direction
						if direction.length() == 0:
							roll_dir = -camera_rig.global_transform.basis.x.normalized() if animated_sprite.flip_h else camera_rig.global_transform.basis.x.normalized()
						roll_direction = roll_dir 

						velocity = roll_direction * _roll_initial_velocity
						roll_timer.start()
				
				# Air roll
				elif not has_rolled_in_air and direction.length() > 0:
					if current_stamina >= cost_two_bars:
						current_stamina -= cost_two_bars
						_update_stamina_display()
						stamina_regen_timer.start()
						
						stats.is_invulnerable = true
						set_collision_mask_value(3, false)
						set_collision_layer_value(1, false)
						
						has_rolled_in_air = true
						is_rolling_in_ground = true 
						
						roll_direction = direction
						velocity.x = direction.x * _air_roll_initial_velocity
						velocity.z = direction.z * _air_roll_initial_velocity
						velocity.y = air_roll_vertical_boost
						air_roll_timer.start()

	# <<<--- Fim do 'else' do STATE 3 ---<<<

	# --- UNIFIED MOVEMENT LOGIC (Simplificado) ---
	if not is_rolling_in_ground:
		var target_velocity = direction * target_speed
		velocity.x = lerp(velocity.x, target_velocity.x, acceleration * delta)
		velocity.z = lerp(velocity.z, target_velocity.z, acceleration * delta)
		if direction.length() == 0:
			velocity.x = lerp(velocity.x, 0.0, friction * delta)
			velocity.z = lerp(velocity.z, 0.0, friction * delta)

	# --- UNIVERSAL FLIP LOGIC (Simplificado) ---
	if not is_rolling_in_ground:
		if input_dir.x < 0:
			animated_sprite.flip_h = true
		elif input_dir.x > 0:
			animated_sprite.flip_h = false

	move_and_slide()

	# --- COMBAT LOGIC ---
	_update_target()
	
	# Controla a visibilidade do anel de ataque
	if not enemies_in_range.is_empty():
		if not attack_range_decal.visible:
			#print("DEBUG: Mostrando Decal de Ataque")
			attack_range_decal.show()
	else:
		if attack_range_decal.visible:
			#print("DEBUG: Escondendo Decal de Ataque")
			attack_range_decal.hide()
	
	if current_target and attack_timer.is_stopped() and not is_rolling_in_ground and not is_crouching:
		# (Vamos adicionar o ataque na próxima etapa)
		# anim_tree.set("parameters/attack_pressed", true) 
		attack_timer.start()
		
	
	# --- [NOVO BLOCO] FEEDER DA ANIMATIONTREE ---
	# No final de _physics_process, alimentamos a árvore com o estado atual.
	
	var h_vel = Vector2(velocity.x, velocity.z).length()

	# Alimenta os BlendSpaces (com os nomes que definimos no 'Value Label')
	anim_tree.set("parameters/Locomotion/blend_position", h_vel)
	anim_tree.set("parameters/InAir/blend_position", velocity.y)
	anim_tree.set("parameters/CrouchLocomotion/blend_position", h_vel)
	
	# Alimenta as Expressões de Transição
	anim_tree.set("parameters/is_on_floor", is_on_floor())
	anim_tree.set("parameters/is_rolling", is_rolling_in_ground)
	anim_tree.set("parameters/is_crouching", is_crouching)

# --- Function Definitions ---

func _calculate_jump_parameters():
	# (Esta função permanece idêntica)
	if jump_height <= 0 or jump_duration <= 0 or jump_gravity_multiplier <= 0:
		printerr("Jump height, duration, and gravity multiplier must be positive!")
		return
	var time_to_peak = jump_duration * sqrt(jump_gravity_multiplier) / (1.0 + sqrt(jump_gravity_multiplier))
	var _time_to_fall = jump_duration / (1.0 + sqrt(jump_gravity_multiplier))
	if time_to_peak <= 0:
		printerr("Calculated jump time to peak is invalid. Check jump_duration and jump_gravity_multiplier.")
		return
	_jump_gravity = (-2.0 * jump_height) / (time_to_peak * time_to_peak)
	_fall_gravity = _jump_gravity * jump_gravity_multiplier
	_jump_velocity = abs(_jump_gravity) * time_to_peak 

func _calculate_roll_parameters():
	# (Esta função está simplificada, sem 'animated_sprite')
	if roll_duration <= 0 or roll_distance <= 0:
		printerr("Roll duration and distance must be positive!")
		_roll_initial_velocity = 0.0
		_roll_deceleration = 0.0
		return
	
	_roll_initial_velocity = 2.0 * roll_distance / roll_duration
	_roll_deceleration = -_roll_initial_velocity / roll_duration 
	roll_timer.wait_time = roll_duration 

func _calculate_air_roll_parameters():
	# (Esta função está simplificada, sem 'animated_sprite')
	if air_roll_duration <= 0 or air_roll_distance <= 0:
		printerr("Air roll duration and distance must be positive!")
		_air_roll_initial_velocity = 0.0
		_air_roll_deceleration = 0.0
		return

	_air_roll_initial_velocity = 2.0 * air_roll_distance / air_roll_duration
	_air_roll_deceleration = -_air_roll_initial_velocity / air_roll_duration
	air_roll_timer.wait_time = air_roll_duration 
			
func _on_jump_buffer_timeout():
	jump_buffer_bool = false

func _update_stamina_display():
	# (Esta função permanece idêntica)
	var stamina_per_bar = max_stamina / stamina_bars.size()
	var remaining_stamina = current_stamina
	for bar in stamina_bars:
		bar.max_value = stamina_per_bar
		var fill_amount = clamp(remaining_stamina, 0, stamina_per_bar)
		bar.value = fill_amount
		remaining_stamina -= fill_amount

func _on_roll_timer_timeout():
	# (Esta função permanece idêntica)
	is_rolling_in_ground = false
	
	stats.is_invulnerable = false
	set_collision_mask(_default_collision_mask)
	set_collision_layer(_default_collision_layer)
	
	velocity.x = 0
	velocity.z = 0

func _on_air_roll_timer_timeout():
	# (Esta função permanece idêntica, mas sem 'animated_sprite.play()')
	is_rolling_in_ground = false 
	
	stats.is_invulnerable = false
	set_collision_mask(_default_collision_mask)
	set_collision_layer(_default_collision_layer)

# --- SETTER FUNCTIONS ---
# (Todas as funções setter permanecem idênticas)

func _set_jump_height(new_height: float):
	jump_height = new_height
	if is_node_ready(): 
		_calculate_jump_parameters()

func _set_jump_duration(new_duration: float):
	jump_duration = new_duration
	if is_node_ready():
		_calculate_jump_parameters()

func _set_jump_gravity_multiplier(new_multiplier: float):
	jump_gravity_multiplier = new_multiplier
	if is_node_ready():
		_calculate_jump_parameters()

func _set_roll_distance(new_distance: float):
	roll_distance = new_distance
	if is_node_ready():
		_calculate_roll_parameters()

func _set_roll_duration(new_duration: float):
	roll_duration = new_duration
	if is_node_ready():
		_calculate_roll_parameters()

func _set_air_roll_distance(new_distance: float):
	air_roll_distance = new_distance
	if is_node_ready():
		_calculate_air_roll_parameters()

func _set_air_roll_duration(new_duration: float):
	air_roll_duration = new_duration
	if is_node_ready():
		_calculate_air_roll_parameters()


# --- HEALTH BAR FUNCTIONS (MODIFICADO) ---

func _on_player_health_changed(current_health, max_health):
	# 1. Atualiza os valores máximos (caso mudem)
	health_bar_front.max_value = max_health
	health_bar_back.max_value = max_health
	
	# 2. A barra da FRENTE (vermelha) atualiza IMEDIATAMENTE
	health_bar_front.value = current_health

	# 3. Mata qualquer tween anterior para evitar conflitos
	if health_tween and health_tween.is_running():
		health_tween.kill()
		
	# 4. Cria o novo Tween para o feedback
	health_tween = create_tween()

	# --- EFEITO 1: TREPIDAÇÃO (Shake) ---
	var original_pos = health_bar_front.position
	var shake_strength = 10.0 
	
	health_tween.tween_property(health_bar_front, "position", original_pos + Vector2(shake_strength, 0), 0.05)
	health_tween.parallel().tween_property(health_bar_back, "position", original_pos + Vector2(shake_strength, 0), 0.05)
	
	health_tween.tween_property(health_bar_front, "position", original_pos - Vector2(shake_strength, 0), 0.05)
	health_tween.parallel().tween_property(health_bar_back, "position", original_pos - Vector2(shake_strength, 0), 0.05)
	
	health_tween.tween_property(health_bar_front, "position", original_pos, 0.05)
	health_tween.parallel().tween_property(health_bar_back, "position", original_pos, 0.05)

	# --- EFEITO 2: BARRA FANTASMA (Atraso) ---
	health_tween.tween_property(health_bar_back, "value", current_health, 0.4).set_delay(0.3).set_ease(Tween.EASE_OUT)

# --- COMBAT FUNCTIONS ---
# (Todas as funções de combate permanecem idênticas)

func _update_target():
	enemies_in_range = enemies_in_range.filter(is_instance_valid)
	
	if enemies_in_range.is_empty():
		current_target = null
		return

	var closest_enemy: Node3D = null
	var min_distance = INF 

	for enemy in enemies_in_range:
		var distance = global_position.distance_to(enemy.global_position)
		if distance < min_distance:
			min_distance = distance
			closest_enemy = enemy
	
	current_target = closest_enemy

func _on_attack_timer_timeout():
	if is_instance_valid(current_target):
		var target_stats = current_target.get_node_or_null("Stats")
		if target_stats:
			print("Atacando %s por %s de dano" % [current_target.name, attack_damage])
			target_stats.take_damage(attack_damage)

func _on_attack_range_body_entered(body):
	if body.is_in_group("enemies"):
		if not enemies_in_range.has(body):
			enemies_in_range.append(body)

func _on_attack_range_body_exited(body):
	if enemies_in_range.has(body):
		enemies_in_range.erase(body)

func _set_attack_speed(new_speed: float):
	attack_speed = new_speed
	if attack_timer: 
		attack_timer.wait_time = 1.0 / attack_speed
