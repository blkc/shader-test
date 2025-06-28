extends Node3D

@onready var capture_button = $CanvasLayer/CanvasButton
@onready var quad_button = $CanvasLayer/QuadButton
@onready var camera = $Camera3D
@onready var mesh_instance = $OriginalCube

const DepthMapGenerator = preload("res://scripts/depth_map_generator_canvas.gd")
const DepthMapGeneratorQuad = preload("res://scripts/depth_map_generator_quad.gd")

func _ready():
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color.RED
    mesh_instance.set_surface_override_material(0, mat)

    capture_button.show()
    capture_button.pressed.connect(_on_capture_canvas_pressed)
    
    quad_button.show()
    quad_button.pressed.connect(_on_capture_quad_pressed)

func _on_capture_canvas_pressed():
    var vp = get_viewport()
    var size = vp.size
    var img = await DepthMapGeneratorCanvas.generate_depth_map(vp, camera, size, 4.0, 15.0)
    if img:
        DepthMapGeneratorCanvas.save_depth_map_debug(img)

func _on_capture_quad_pressed():
    var vp = get_viewport()
    var size = vp.size
    var img = await DepthMapGeneratorQuad.generate_depth_map(vp, camera, size, 4.0, 15.0)
    if img:
        DepthMapGeneratorQuad.save_depth_map_debug(img)
