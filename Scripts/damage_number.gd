extends Label3D

# Esta função é chamada de fora para iniciar o número
func start(damage_amount: float, start_position: Vector3):
	
	# --- A MUDANÇA PARA INTEIROS ---
	# Converte o 'float' de dano (ex: 25.0) para um 'int' (25) e depois para 'string'
	text = str(int(damage_amount))
	
	# Define a posição 3D inicial
	global_position = start_position
	
	# Cria uma animação Tween
	var tween = create_tween()
	
	# 1. Mover para cima (em 3D)
	# Pega a posição final 0.75m acima da inicial
	var end_position = global_position + (Vector3.UP * 0.15)
	
	# Anima a propriedade 'position' 3D ao longo de 1.2 segundos
	tween.tween_property(self, "position", end_position, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# 2. Desaparecer (em paralelo)
	# Modifica o 'modulate:a' (alfa/transparência) para 0.
	# Começa com um atraso (0.5s) e dura 0.7 segundos.
	tween.parallel().tween_property(self, "modulate:a", 0.0, 0.5).set_delay(0.35)
	tween.parallel().tween_property(self, "outline_modulate:a", 0.0, 0.5).set_delay(0.35)
	
	# 3. Autodestruição
	# Quando o tween terminar, chama a função queue_free() para remover o nó.
	tween.tween_callback(queue_free)
