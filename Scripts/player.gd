extends CharacterBody3D

# --- EXPORTED VARIABLES (Visible in Inspector) ---

@export_category("External Nodes")
@export var camera_rig: Node3D

@export_category("Movement")
@export var max_speed = 2.5
@export var acceleration = 3.5
@export var friction = 30.0

@export_category("Jumping")
##Maximum height the player can reach in meters.
@export var jump_height: float = 1.7 : set = _set_jump_height
##Total time the character spends airborne during a full jump (press and hold).
@export var jump_duration: float = 0.8 : set = _set_jump_duration
##Multiplier applied to gravity when falling.
@export var jump_gravity_multiplier: float = 1.4 : set = _set_jump_gravity_multiplier
##Variable height. Multiplier applied to upward velocity when jump is released early (0 = sharp cut, 1 = no cut).
@export var jump_cutoff: float = 0.5
##Total number of jumps allowed (1 = ground jump only).
@export var max_jumps = 2
##Time window before landing to buffer a jump input (seconds).
@export var jump_buffer_duration = 0.15 # Renamed from Jump_Buffer_Time for consistency
##Time window after leaving ground to still perform a ground jump (seconds).
@export var coyote_time_duration = 0.1

@export_category("Rolling")
## The horizontal distance covered during a ground roll in meters.
@export var roll_distance: float = 1.3 : set = _set_roll_distance
## The total time the ground roll takes in seconds.
@export var roll_duration: float = 0.5 : set = _set_roll_duration
## The horizontal distance covered during an air roll in meters.
@export var air_roll_distance: float = 2.5 : set = _set_air_roll_distance
## The total time the air roll takes in seconds.
@export var air_roll_duration: float = 0.6 : set = _set_air_roll_duration
## Upward boost applied at the start of an air roll.
@export var air_roll_vertical_boost: float = 3.0
## Point in the roll animation (0.0 to 1.0) where air roll starts slowing down.
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
@export var attack_damage: float = 25.0
## Attacks per second. (Ex: 1.5 = 1.5 attacks per second)
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
var _air_roll_anim_speed_scale: float = 1.0
var is_crouching = false
var is_in_crouch_transition = false
var last_horizontal_direction = 0.0
var current_stamina: float
var jump_buffer_bool = false # Flag for Chaff Games buffer method
var _roll_anim_fps: float = 10.0
var _roll_anim_speed_scale: float = 1.0
var enemies_in_range: Array = []
var current_target: Node3D = null

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
@onready var stats = $Stats # Referência ao nosso nó de Stats
@onready var health_bar = $"../CanvasLayer/PlayerHealthBar"

# --- CONSTANTS ---
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity") # Keep this if needed elsewhere, otherwise calculate within jump parameters

func _ready():
	standing_shape.disabled = false
	crouching_shape.disabled = true
	stand_up_checker.add_exception(self)

	if animated_sprite.flip_h:
		last_horizontal_direction = -1.0 # Facing left
	else:
		last_horizontal_direction = 1.0 # Facing right
	
	#animated_sprite.animation_finished.connect(_on_animation_finished)

	current_stamina = max_stamina
	stamina_regen_timer.wait_time = stamina_regen_delay
	_update_stamina_display()

	coyote_timer.wait_time = coyote_time_duration

	_calculate_jump_parameters()
	_calculate_roll_parameters()
	_calculate_air_roll_parameters()
	
		# --- HEALTH BAR SETUP ---
	# Define os valores iniciais da barra de vida
	health_bar.max_value = stats.max_health
	health_bar.value = stats.current_health

	# Conecta o sinal "health_changed" do nó Stats à nova função
	stats.health_changed.connect(_on_player_health_changed)
	
	# --- COMBAT SETUP ---
	attack_timer.wait_time = 1.0 / attack_speed
	
	# Conecta os sinais da nossa área de ataque
	attack_range.body_entered.connect(_on_attack_range_body_entered)
	attack_range.body_exited.connect(_on_attack_range_body_exited)
	
	# Conecta o sinal do nosso timer de ataque
	attack_timer.timeout.connect(_on_attack_timer_timeout)


func _physics_process(delta):
	# --- CORE LOGIC & RESETS ---
	var just_left_ground = not is_on_floor() and was_on_floor
	was_on_floor = is_on_floor() # Remember floor state for next frame

	if is_on_floor():
		jumps_made = 0
		has_rolled_in_air = false
	else: # In the air
		if is_rolling_in_ground and not has_rolled_in_air:
			is_rolling_in_ground = false
		if is_crouching or is_in_crouch_transition:
			is_crouching = false
			is_in_crouch_transition = false
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

	var target_speed = max_speed # Default to max run speed

	# --- STAMINA REGENERATION LOGIC ---
	if stamina_regen_timer.is_stopped() and current_stamina < max_stamina:
		current_stamina += stamina_regen_rate * delta
		current_stamina = min(current_stamina, max_stamina)
		_update_stamina_display()
	
	## --- Crouch transition guard ---
	#if is_in_crouch_transition:
		#move_and_slide()
		#return

	# --- STATE-BASED LOGIC (PRIORITY ORDER) ---

	# STATE 1: Player is rolling
	if is_rolling_in_ground:
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

	# STATE 2: Player is in a crouch transition
	elif is_in_crouch_transition:
		#print("State: Crouch Transition")
		pass # Do nothing

	# STATE 3: Handle all crouching logic
	elif is_crouching:
		target_speed = crouch_speed # Set the target speed for the Unified Movement block

		# Check if player is trying to stand up
		if not Input.is_action_pressed("crouch"):
			if not stand_up_checker.is_colliding():
				is_in_crouch_transition = true
				standing_shape.disabled = false
				crouching_shape.disabled = true
				animated_sprite.speed_scale = 1.0
				animated_sprite.play("crouch_up")
				if not animated_sprite.animation_finished.is_connected(_on_crouch_up_finished):
					animated_sprite.animation_finished.connect(_on_crouch_up_finished, CONNECT_ONE_SHOT)
		else:
			# Just play the correct animation. The unified block handles the movement.
			if direction.length() > 0:
				animated_sprite.play("crouch_walk")
			else:
				animated_sprite.play("crouch")
	
	# STATE 4: Standard Gameplay
	else:
		# Check to START crouching
		if Input.is_action_just_pressed("crouch") and is_on_floor():
			is_in_crouch_transition = true
			animated_sprite.speed_scale = 1.0
			animated_sprite.play("crouch_down")
			if not animated_sprite.animation_finished.is_connected(_on_crouch_down_finished):
				animated_sprite.animation_finished.connect(_on_crouch_down_finished, CONNECT_ONE_SHOT)
		
		# If not starting a crouch, then check for jump, roll, and movement.
		else:
			# --- JUMP LOGIC (Using Chaff Games' Buffer Method) ---
			var jump_pressed_this_frame = Input.is_action_just_pressed("jump")
			var perform_jump = false
			var is_first_jump = false

			# --- DETERMINE IF A JUMP SHOULD HAPPEN ---

			# Condition 1: Coyote time jump (Check first)
			if jump_pressed_this_frame and jumps_made == 0 and not is_on_floor() and not coyote_timer.is_stopped():
				perform_jump = true
				is_first_jump = true
				coyote_timer.stop() # Consume coyote time

			# Condition 2: Normal ground jump OR Buffered jump check on ground
			elif is_on_floor() and (jump_pressed_this_frame or jump_buffer_bool):
				perform_jump = true
				is_first_jump = true
				jump_buffer_bool = false # Consume buffer if used

			# Condition 3: Air jump (double jump)
			elif jump_pressed_this_frame and not is_on_floor() and jumps_made > 0 and jumps_made < max_jumps:
				perform_jump = true
				is_first_jump = false
				jump_buffer_bool = false # Cannot buffer during air jump

			# Condition 4: START BUFFER (Only if jump pressed in air and no jump performed/possible)
			elif jump_pressed_this_frame and not is_on_floor():
				# Check if already buffering to prevent multiple timers AND ensure jumps are used
				if not jump_buffer_bool and jumps_made >= max_jumps:
					jump_buffer_bool = true
					get_tree().create_timer(jump_buffer_duration).timeout.connect(_on_jump_buffer_timeout) # Use correct duration variable

			# --- EXECUTE JUMP if any condition met ---
			if perform_jump:
				if is_first_jump:
					jumps_made = 1
					animated_sprite.play("jump")
				else: # It's an air jump
					jumps_made += 1
					animated_sprite.play("double_jump")
				velocity.y = _jump_velocity
				animated_sprite.speed_scale = 1.0
				coyote_timer.stop() # Stop coyote timer if jump occurs
				jump_buffer_bool = false # Ensure buffer flag is false after any jump

			# Check for Roll/Air Roll (only if no jump happened)
			elif Input.is_action_just_pressed("special_action"):
				var cost_one_bar = max_stamina / 3.0
				var cost_two_bars = cost_one_bar * 2.0
				if is_on_floor():
					# Ground roll costs one bar and uses calculated physics
					if current_stamina >= cost_one_bar:
						current_stamina -= cost_one_bar
						_update_stamina_display()
						stamina_regen_timer.start()

						is_rolling_in_ground = true # Enter the rolling state

						# Determine roll direction
						var roll_dir = direction
						if direction.length() == 0:
							roll_dir = -camera_rig.global_transform.basis.x.normalized() if animated_sprite.flip_h else camera_rig.global_transform.basis.x.normalized()
						roll_direction = roll_dir # Store the locked direction

						# Set initial velocity based on calculation
						velocity = roll_direction * _roll_initial_velocity

						# --- THE FIX IS HERE: Start the ground roll timer ---
						roll_timer.start()
						#print("--> Ground Roll Timer STARTED <--") # Optional Debug

						# Play animation and set its speed scale
						if input_dir.x < 0: animated_sprite.flip_h = true
						elif input_dir.x > 0: animated_sprite.flip_h = false
						animated_sprite.speed_scale = _roll_anim_speed_scale
						animated_sprite.play("roll")
				
				elif not has_rolled_in_air and direction.length() > 0:
					if current_stamina >= cost_two_bars:
						current_stamina -= cost_two_bars
						_update_stamina_display()
						stamina_regen_timer.start()
						has_rolled_in_air = true
						is_rolling_in_ground = true
						animated_sprite.speed_scale = _air_roll_anim_speed_scale
						animated_sprite.play("roll")
						roll_direction = direction
						velocity.x = direction.x * _air_roll_initial_velocity
						velocity.z = direction.z * _air_roll_initial_velocity
						velocity.y = air_roll_vertical_boost
						air_roll_timer.start()

			# Standard Run/Idle/Turnaround/Fall animations
			else:
				if is_on_floor():
					var horizontal_input = input_dir.x
					if animated_sprite.animation != "turnaround":
						if horizontal_input != 0 and sign(horizontal_input) != sign(last_horizontal_direction):
							animated_sprite.speed_scale = 1.0
							animated_sprite.play("turnaround")
							if not animated_sprite.animation_finished.is_connected(_on_turnaround_finished):
								animated_sprite.animation_finished.connect(_on_turnaround_finished, CONNECT_ONE_SHOT)
						elif direction.length() > 0:
							animated_sprite.play("run")
							var current_horizontal_speed = Vector2(velocity.x, velocity.z).length()
							var mapped_speed = remap(current_horizontal_speed, 0.0, max_speed, min_animation_speed, max_animation_speed)
							animated_sprite.speed_scale = mapped_speed
						else:
							animated_sprite.speed_scale = 1.0
							animated_sprite.play("idle")
					if horizontal_input != 0: last_horizontal_direction = horizontal_input
				else: # In-air animations
					animated_sprite.speed_scale = 1.0
					if not is_rolling_in_ground:
						if velocity.y > 0.1:
							if animated_sprite.animation != "jump" and animated_sprite.animation != "double_jump":
								if jumps_made == 1:
									animated_sprite.play("jump")
								elif jumps_made >= 2:
									animated_sprite.play("double_jump")
						elif velocity.y < -0.1:
							animated_sprite.play("fall")
						else:
							if animated_sprite.animation != "fall" and animated_sprite.animation != "jumpfallinbetween":
								animated_sprite.play("jumpfallinbetween")

	# <<<--- End of State 4 'else' block ---<<<

	# --- UNIFIED MOVEMENT LOGIC ---
	if not is_rolling_in_ground and not is_in_crouch_transition:
		var target_velocity = direction * target_speed
		velocity.x = lerp(velocity.x, target_velocity.x, acceleration * delta)
		velocity.z = lerp(velocity.z, target_velocity.z, acceleration * delta)
		if direction.length() == 0:
			velocity.x = lerp(velocity.x, 0.0, friction * delta)
			velocity.z = lerp(velocity.z, 0.0, friction * delta)

	# --- UNIVERSAL FLIP LOGIC ---
	if animated_sprite.animation != "turnaround" and not is_rolling_in_ground:
		if input_dir.x < 0:
			animated_sprite.flip_h = true
		elif input_dir.x > 0:
			animated_sprite.flip_h = false

	move_and_slide()

	# --- COMBAT LOGIC ---
	_update_target()
	
	# Se temos um alvo válido e nosso timer de ataque não está rodando,
	# inicie um novo ataque.
	if current_target and attack_timer.is_stopped():
		attack_timer.start()
		# Opcional: Você pode tocar uma animação de "início de ataque" aqui
		# animated_sprite.play("attack_windup")

# --- Function Definitions ---

func _calculate_jump_parameters():
	# Ensure valid inputs to prevent division by zero or sqrt of negative
	if jump_height <= 0 or jump_duration <= 0 or jump_gravity_multiplier <= 0:
		printerr("Jump height, duration, and gravity multiplier must be positive!")
		return

	# Calculate time spent rising (t_up) and falling (t_down) based on total duration and gravity multiplier
	var time_to_peak = jump_duration * sqrt(jump_gravity_multiplier) / (1.0 + sqrt(jump_gravity_multiplier))
	var _time_to_fall = jump_duration / (1.0 + sqrt(jump_gravity_multiplier))

	# Ensure calculated times are valid
	if time_to_peak <= 0:
		printerr("Calculated jump time to peak is invalid. Check jump_duration and jump_gravity_multiplier.")
		return

	# Calculate the necessary gravities and initial velocity
	_jump_gravity = (-2.0 * jump_height) / (time_to_peak * time_to_peak)
	_fall_gravity = _jump_gravity * jump_gravity_multiplier
	_jump_velocity = abs(_jump_gravity) * time_to_peak # Same as (2.0 * jump_height) / time_to_peak

func _calculate_roll_parameters():
	# Ensure valid inputs
	if roll_duration <= 0 or roll_distance <= 0:
		printerr("Roll duration and distance must be positive!")
		_roll_initial_velocity = 0.0
		_roll_deceleration = 0.0
		return
	
	# Get the roll animation properties
	if animated_sprite and animated_sprite.sprite_frames.has_animation("roll"):
		var roll_anim_name = "roll"
		_roll_anim_fps = animated_sprite.sprite_frames.get_animation_speed(roll_anim_name)
		var frame_count = animated_sprite.sprite_frames.get_frame_count(roll_anim_name)

		# Ensure FPS and frame count are valid
		if _roll_anim_fps > 0 and frame_count > 0:
			# Calculate the animation's default duration
			var default_anim_duration = float(frame_count) / _roll_anim_fps

			# Calculate the required speed scale to match roll_duration
			if roll_duration > 0:
				_roll_anim_speed_scale = default_anim_duration / roll_duration
			else:
				_roll_anim_speed_scale = 1.0 # Avoid division by zero, use default speed
		else:
			_roll_anim_speed_scale = 1.0 # Use default if animation data is invalid
	else:
		_roll_anim_speed_scale = 1.0 # Use default if animation/sprite not ready

	# Calculate initial velocity and constant deceleration to cover distance in time, ending at zero speed
	_roll_initial_velocity = 2.0 * roll_distance / roll_duration
	_roll_deceleration = -_roll_initial_velocity / roll_duration # a = (vf - v0) / t, vf=0
	roll_timer.wait_time = roll_duration # Set the timer duration

func _calculate_air_roll_parameters():
	# Ensure valid inputs
	if air_roll_duration <= 0 or air_roll_distance <= 0:
		printerr("Air roll duration and distance must be positive!")
		_air_roll_initial_velocity = 0.0
		_air_roll_deceleration = 0.0
		return

	# Calculate initial velocity and constant deceleration
	_air_roll_initial_velocity = 2.0 * air_roll_distance / air_roll_duration
	_air_roll_deceleration = -_air_roll_initial_velocity / air_roll_duration
	air_roll_timer.wait_time = air_roll_duration # Set the timer duration
	
	# --- Calculate Animation Speed Scale ---
	if animated_sprite and animated_sprite.sprite_frames.has_animation("roll"):
		var roll_anim_name = "roll"
		var anim_fps = animated_sprite.sprite_frames.get_animation_speed(roll_anim_name)
		var frame_count = animated_sprite.sprite_frames.get_frame_count(roll_anim_name)

		if anim_fps > 0 and frame_count > 0:
			var default_anim_duration = float(frame_count) / anim_fps
			if air_roll_duration > 0:
				_air_roll_anim_speed_scale = default_anim_duration / air_roll_duration
			else:
				_air_roll_anim_speed_scale = 1.0
		else:
			_air_roll_anim_speed_scale = 1.0
	else:
		_air_roll_anim_speed_scale = 1.0

func _on_turnaround_finished():
	if last_horizontal_direction < 0:
		animated_sprite.flip_h = true
	elif last_horizontal_direction > 0:
		animated_sprite.flip_h = false
	
	var current_input = Input.get_axis("left", "right")
	if current_input != 0:
		animated_sprite.play("run")
	else:
		animated_sprite.play("idle")

func _on_roll_finished():
	is_rolling_in_ground = false
	if not is_on_floor():
		animated_sprite.play("fall")

func _on_crouch_down_finished():
	# The transition is done. We are now officially crouching.
	is_crouching = true
	is_in_crouch_transition = false
	standing_shape.disabled = true
	crouching_shape.disabled = false

func _on_crouch_up_finished():
	# The transition to stand is done. We are no longer crouching.
	is_crouching = false
	is_in_crouch_transition = false

#func _on_animation_finished(anim_name: String) -> void:
	#print("Animation Finished:", anim_name)
#
	#if anim_name == "crouch_down":
		#print("--> Crouch Down FINISHED (via general handler) <--")
		#is_crouching = true
		#is_in_crouch_transition = false
		#standing_shape.disabled = true
		#crouching_shape.disabled = false
#
	#elif anim_name == "crouch_up":
		#print("--> Crouch Up FINISHED (via general handler) <--")
		#is_crouching = false
		#is_in_crouch_transition = false
	#
	#elif anim_name == "turnaround":
		## You might need to call your specific turnaround logic here
		## For example: _process_turnaround_finished_state()
		## Or integrate the _on_turnaround_finished logic directly
		#if last_horizontal_direction < 0:
			#animated_sprite.flip_h = true
		#elif last_horizontal_direction > 0:
			#animated_sprite.flip_h = false
		#var current_input = Input.get_axis("left", "right")
		#if current_input != 0:
			#animated_sprite.play("run")
		#else:
			#animated_sprite.play("idle")
			

func _on_jump_buffer_timeout():
	jump_buffer_bool = false

func _update_stamina_display():
	var stamina_per_bar = max_stamina / stamina_bars.size()
	var remaining_stamina = current_stamina

	for bar in stamina_bars:
		bar.max_value = stamina_per_bar
		var fill_amount = clamp(remaining_stamina, 0, stamina_per_bar)
		bar.value = fill_amount
		remaining_stamina -= fill_amount

func _on_roll_timer_timeout():
	#print("--> Ground Roll Timer FINISHED <--")
	is_rolling_in_ground = false
	# Ensure a clean stop after the ground roll duration
	velocity.x = 0
	velocity.z = 0

func _on_air_roll_timer_timeout():
	#print("--> Air Roll Timer FINISHED <--")
	is_rolling_in_ground = false # Exit the shared rolling state
	# Don't zero out velocity here, let gravity continue
	if not is_on_floor():
		animated_sprite.play("fall") # Transition to fall animation

# --- SETTER FUNCTIONS ---

func _set_jump_height(new_height: float):
	jump_height = new_height
	# Recalculate physics whenever height changes
	if is_node_ready(): # Avoid running calculations before _ready()
		_calculate_jump_parameters()

func _set_jump_duration(new_duration: float):
	jump_duration = new_duration
	# Recalculate physics whenever duration changes
	if is_node_ready():
		_calculate_jump_parameters()

func _set_jump_gravity_multiplier(new_multiplier: float):
	jump_gravity_multiplier = new_multiplier
	# Recalculate physics whenever multiplier changes
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


# --- HEALTH BAR FUNCTIONS ---

func _on_player_health_changed(current_health, max_health):
	health_bar.value = current_health
	# Atualiza o max_value caso ele mude (ex: level up)
	health_bar.max_value = max_health


# --- COMBAT FUNCTIONS ---

func _update_target():
	# Limpa alvos inválidos (que morreram e foram removidos)
	enemies_in_range = enemies_in_range.filter(is_instance_valid)
	
	if enemies_in_range.is_empty():
		current_target = null
		return

	# --- LÓGICA DO INIMIGO MAIS PRÓXIMO ---
	var closest_enemy: Node3D = null
	var min_distance = INF # 'INF' significa infinito (um número muito grande)

	for enemy in enemies_in_range:
		var distance = global_position.distance_to(enemy.global_position)
		if distance < min_distance:
			min_distance = distance
			closest_enemy = enemy
	
	current_target = closest_enemy
	# Opcional: Fazer o sprite olhar para o inimigo
	# if current_target:
	# 	var relative_pos = camera_rig.global_transform.basis.x.dot(
	# 		(current_target.global_position - global_position).normalized()
	# 	)
	# 	if relative_pos > 0.1:
	# 		animated_sprite.flip_h = false
	# 	elif relative_pos < -0.1:
	# 		animated_sprite.flip_h = true


# Chamado quando o AttackTimer termina
func _on_attack_timer_timeout():
	# Se o alvo ainda for válido (não morreu enquanto o timer rodava)
	if is_instance_valid(current_target):
		var target_stats = current_target.get_node_or_null("Stats")
		if target_stats:
			print("Atacando %s por %s de dano" % [current_target.name, attack_damage])
			target_stats.take_damage(attack_damage)
			# Opcional: Tocar animação de "acerto"
			# animated_sprite.play("attack_hit")


# Chamado quando um corpo entra na nossa área de ataque
func _on_attack_range_body_entered(body):
	# Se o corpo for um inimigo, adicione-o à nossa lista de alvos
	if body.is_in_group("enemies"):
		if not enemies_in_range.has(body):
			enemies_in_range.append(body)


# Chamado quando um corpo sai da nossa área de ataque
func _on_attack_range_body_exited(body):
	# Se o corpo estava na nossa lista, remova-o
	if enemies_in_range.has(body):
		enemies_in_range.erase(body)


# Atualiza o timer de ataque se mudarmos o valor no Inspector
func _set_attack_speed(new_speed: float):
	attack_speed = new_speed
	if attack_timer: # Garante que o timer exista
		attack_timer.wait_time = 1.0 / attack_speed
