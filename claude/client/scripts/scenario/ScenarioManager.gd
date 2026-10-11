class_name ScenarioManager
extends Node
## Carga un caso (JSON) y monta la partida en el cliente:
##   1. ScenarioSource lee el archivo.
##   2. ScenarioParser lo valida y construye ScenarioData.
##   3. Los roles se entregan a RoleManager (sin que este conozca el formato).
##   4. EvidenceSpawner instancia cada pista en el mapa como Interactable, con
##      el mismo id que usa el servidor, así el estado de red las rellena solo.
##
## El servidor carga el MISMO archivo (SCENARIO=<id>) y es quien decide qué
## hay realmente en cada punto y quién lo ve.

signal scenario_loaded(data: ScenarioData)
signal scenario_failed(errors: PackedStringArray)
signal evidence_spawned(spawn: EvidenceSpawnData, node: Interactable)
signal scenario_cleared

@export var role_manager: RoleManager
## Nodo bajo el que se crean las pistas (normalmente el mapa).
@export var spawn_root: Node2D

var source: ScenarioSource = ScenarioSource.FileSource.new()
var spawner := EvidenceSpawner.new()
var current: ScenarioData

var _spawned := {}  # evidence id -> Interactable

func load_scenario(scenario_id: String) -> bool:
	var result := ScenarioParser.parse(source.load_raw(scenario_id))
	for w in result.warnings:
		push_warning("[Escenario %s] %s" % [scenario_id, w])
	if not result.ok():
		for e in result.errors:
			push_error("[Escenario %s] %s" % [scenario_id, e])
		scenario_failed.emit(result.errors)
		return false
	apply(result.data)
	return true

func apply(data: ScenarioData) -> void:
	clear_scenario()
	current = data
	if role_manager:
		role_manager.source = RoleConfigSource.MemorySource.new({data.scenario_id: data.to_role_set()})
		role_manager.load_role_set(data.scenario_id)
	if spawn_root:
		for spawn in data.evidence_spawns:
			var node := spawner.spawn(spawn, spawn_root)
			_spawned[spawn.id] = node
			evidence_spawned.emit(spawn, node)
	scenario_loaded.emit(data)

func clear_scenario() -> void:
	for node in _spawned.values():
		if is_instance_valid(node):
			node.queue_free()
	_spawned.clear()
	if current:
		current = null
		scenario_cleared.emit()

func get_spawned(evidence_id: String) -> Interactable:
	return _spawned.get(evidence_id)

## Contenido multimedia de una pista (texto, audio, imagen) para la UI de
## inspección. definition_id es el que llega en EvidenceData.definition_id.
func get_content(definition_id: String) -> Dictionary:
	var spawn: EvidenceSpawnData = current.get_spawn(definition_id) if current else null
	return spawn.content if spawn else {}

## Objetivos secretos del rol local (para el panel de briefing).
func secret_objectives_for(role_id: String) -> Array[Dictionary]:
	var role: ScenarioRoleData = current.get_role(role_id) if current else null
	return role.secret_objectives if role else []
