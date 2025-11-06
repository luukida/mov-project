@tool
class_name Stats
extends Node

## Sinal emitido quando a vida muda. Envia a vida atual e a máxima.
signal health_changed(current_health, max_health)
## Sinal emitido quando a vida chega a zero.
signal no_health()

signal damage_taken(amount)

@export var max_health: float = 100.0
var current_health: float

func _ready():
	# Começa com a vida cheia
	current_health = max_health

func take_damage(amount: float):
	# Se já estiver morto, não faça nada
	if current_health <= 0:
		return

	current_health -= amount
	current_health = clamp(current_health, 0, max_health)
	
	damage_taken.emit(amount)
	health_changed.emit(current_health, max_health)
	
	if current_health == 0:
		no_health.emit()

# Função bônus que podemos usar depois (ex: para poções)
func heal(amount: float):
	# Se já estiver com vida cheia, não faça nada
	if current_health >= max_health:
		return
	
	current_health += amount
	current_health = clamp(current_health, 0, max_health)
	
	health_changed.emit(current_health, max_health)
