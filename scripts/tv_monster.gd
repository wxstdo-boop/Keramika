extends Node3D
## Чудище, вылезающее из экрана монитора после взятия брелока:
## высокое, бледно-красное, без лица, с красным свечением.
## Дышит, медленно покачивается и поворачивает корпус к игроку;
## дёргается и вспыхивает красным, когда в него стреляют.

var _flinch := 0.0
var _emerged := false
var _glow: OmniLight3D
var _torso: Node3D
var _flesh: StandardMaterial3D
var _pale: StandardMaterial3D


func _ready() -> void:
	_build()
	_emerge()


func _build() -> void:
	_flesh = StandardMaterial3D.new()
	_flesh.albedo_color = Color(0.52, 0.16, 0.14)
	_flesh.roughness = 0.5
	_flesh.metallic = 0.04
	_flesh.emission_enabled = true
	_flesh.emission = Color(0.30, 0.03, 0.025)
	_flesh.emission_energy_multiplier = 0.55
	_pale = StandardMaterial3D.new()
	_pale.albedo_color = Color(0.70, 0.44, 0.38)
	_pale.roughness = 0.62
	_pale.emission_enabled = true
	_pale.emission = Color(0.13, 0.045, 0.04)
	_pale.emission_energy_multiplier = 0.5

	_torso = Node3D.new()
	_torso.name = "TorsoRoot"
	add_child(_torso)

	# Бледная вытянутая голова без лица.
	_cap(_torso, "Head", 0.08, 0.46, Vector3(0, 1.58, 0), _pale)
	_cap(_torso, "Neck", 0.04, 0.14, Vector3(0, 1.40, 0), _flesh)
	_cap(_torso, "Torso", 0.16, 0.85, Vector3(0, 1.12, 0), _flesh)
	# Длинные тонкие руки.
	for side in [-1.0, 1.0]:
		var arm := _cap(_torso, "Arm" + ("L" if side < 0.0 else "R"), 0.032, 1.0, Vector3(side * 0.24, 0.92, 0.0), _flesh)
		arm.rotation_degrees = Vector3(0, 0, side * 6.0)
	# Ноги.
	for side in [-1.0, 1.0]:
		var leg := _cap(_torso, "Leg" + ("L" if side < 0.0 else "R"), 0.048, 0.8, Vector3(side * 0.10, 0.40, 0.0), _flesh)
		leg.rotation_degrees = Vector3(6.0, 0, side * 3.0)

	# Красная трещина-«лицо» на груди, обращена к комнате.
	var crack := MeshInstance3D.new()
	crack.name = "ChestCrack"
	var csp := SphereMesh.new()
	csp.radius = 0.032
	csp.height = 0.064
	csp.radial_segments = 12
	crack.mesh = csp
	crack.position = Vector3(0, 1.22, -0.17)
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.95, 0.06, 0.04, 0.95)
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.emission_enabled = true
	cm.emission = Color(1.0, 0.1, 0.05)
	cm.emission_energy_multiplier = 3.0
	crack.material_override = cm
	crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_torso.add_child(crack)

	# Красноватое свечение вокруг чудища.
	_glow = OmniLight3D.new()
	_glow.name = "MonsterGlow"
	_glow.light_color = Color(0.9, 0.07, 0.05)
	_glow.omni_range = 3.2
	_glow.omni_attenuation = 1.8
	_glow.light_energy = 0.65
	_glow.shadow_enabled = false
	_glow.position = Vector3(0, 1.5, 0)
	add_child(_glow)

	# Физическое тело — в него можно стрелять.
	var body := StaticBody3D.new()
	body.name = "TvMonsterBody"
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector3(0, 1.05, 0)
	var bcs := CollisionShape3D.new()
	var bcap := CapsuleShape3D.new()
	bcap.radius = 0.22
	bcap.height = 1.4
	bcs.shape = bcap
	body.add_child(bcs)
	add_child(body)


func _cap(parent_node: Node, label: String, radius: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = label
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = height
	cm.radial_segments = 16
	cm.rings = 6
	mi.mesh = cm
	mi.position = pos
	mi.set_surface_override_material(0, mat)
	parent_node.add_child(mi)
	return mi


func _emerge() -> void:
	# Стартует сжатым в точке экрана монитора и плавно разворачивается
	# на столе перед ним — будто вылезает из телевизора.
	global_position = Vector3(1.78, 1.22, 1.75)
	scale = Vector3(0.04, 0.04, 0.04)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "global_position", Vector3(1.78, 0.86, 1.42), 2.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector3.ONE, 2.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func() -> void: _emerged = true)


func flinch() -> void:
	_flinch = 1.0
	if _glow != null:
		_glow.light_energy = 2.4


func _process(delta: float) -> void:
	if not _emerged:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var breathe: float = 1.0 + 0.014 * sin(t * 1.6)
	var fl: float = 1.0 + _flinch * 0.12
	scale = Vector3(breathe * fl, breathe * (1.0 - _flinch * 0.07), breathe * fl)
	rotation_degrees.z = 1.4 * sin(t * 0.55)
	_flinch = move_toward(_flinch, 0.0, delta * 1.6)
	if _glow != null:
		_glow.light_energy = lerpf(_glow.light_energy, 0.65 + 0.18 * sin(t * 2.3), delta * 3.0)
	# Верхняя часть корпуса медленно поворачивается к игроку.
	var player := get_tree().current_scene.find_child("Player", true, false) as Node3D
	if player != null and _torso != null:
		var to_p := player.global_position - global_position
		var target_yaw := atan2(to_p.x, -to_p.z)
		_torso.rotation.y = lerp_angle(_torso.rotation.y, clampf(target_yaw, -0.45, 0.45), delta * 1.2)
