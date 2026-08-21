extends Node3D
## Живой глитч текста «This Man_2006» на экране монитора: случайные
## горизонтальные рывки, лёгкий перекос и микровспышки — как неисправная ЭЛТ.

var _base_position := Vector3.ZERO
var _jitter_timer := 0.0
var _flicker_timer := 0.0
var _hide_timer := 0.0

const JITTER_MIN := 0.05
const JITTER_MAX := 0.22


func _ready() -> void:
	_base_position = position


func _process(delta: float) -> void:
	# Рывки текста.
	_jitter_timer -= delta
	if _jitter_timer <= 0.0:
		_jitter_timer = randf_range(JITTER_MIN, JITTER_MAX)
		var r := randf()
		if r < 0.55:
			# Лёгкое дрожание.
			position = _base_position + Vector3(randf_range(-0.006, 0.006), randf_range(-0.004, 0.004), 0.0)
			scale = Vector3.ONE
		elif r < 0.82:
			# Резкий рывок строки.
			position = _base_position + Vector3(randf_range(-0.028, 0.028), randf_range(-0.01, 0.01), 0.0)
			scale = Vector3(1.05, 1.0, 1.0)
		else:
			# Редкое успокоение.
			position = _base_position
			scale = Vector3.ONE
	# Микровспышки: текст на миг пропадает.
	_flicker_timer -= delta
	if _flicker_timer <= 0.0:
		_flicker_timer = randf_range(0.3, 1.4)
		if randf() < 0.14:
			visible = false
			_hide_timer = randf_range(0.05, 0.16)
	if _hide_timer > 0.0:
		_hide_timer -= delta
		if _hide_timer <= 0.0:
			visible = true
