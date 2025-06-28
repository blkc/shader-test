extends Node3D

@onready var capture_button = $CanvasLayer/CaptureButton
@onready var camera = $Camera3D
@onready var mesh_instance = $MeshInstance3D

const DepthMapGenerator = preload("res://scripts/depth_map_generator.gd")

func _ready():
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color.RED
    mesh_instance.set_surface_override_material(0, mat)

    capture_button.show()
    capture_button.pressed.connect(_on_capture_pressed)

func _on_capture_pressed():
    var vp = get_viewport()
    var size = vp.size
    var img = await DepthMapGenerator.generate_depth_map(vp, camera, size)
    if img:
        DepthMapGenerator.save_depth_map_debug(img)
