extends Node
## Doble de Network para tests: registra las intenciones en vez de enviarlas.

signal message_received(msg: Dictionary)

var sent: Array[Dictionary] = []

func send_intent(type: String, payload: Dictionary = {}) -> int:
	var intent := payload.duplicate()
	intent["t"] = type
	intent["seq"] = sent.size() + 1
	sent.append(intent)
	return intent["seq"]
