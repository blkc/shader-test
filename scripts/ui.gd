extends Node3D

@onready var capture_button = $CanvasLayer/CanvasButton
@onready var quad_button = $CanvasLayer/QuadButton
@onready var two_pass_button = $CanvasLayer/TwoPassButton
@onready var camera = $Camera3D
@onready var mesh_instance = $OriginalCube
@onready var near_sphere = $NearSphere
@onready var side_box = $SideBox

const DepthMapGenerator = preload("res://scripts/depth_map_generator_canvas.gd")
const DepthMapGeneratorQuad = preload("res://scripts/depth_map_generator_quad.gd")
const DepthMapGeneratorTwoPass = preload("res://scripts/depth_map_generator_two_pass.gd")

func _ready():
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color.RED
    mesh_instance.set_surface_override_material(0, mat)

    # Set the side_box and near_sphere to be on Layer 2 for demonstration.
    # This will create a depth range for the generator to measure.
    side_box.layers = 2
    near_sphere.layers = 2

    capture_button.show()
    capture_button.pressed.connect(_on_capture_canvas_pressed)
    
    quad_button.show()
    quad_button.pressed.connect(_on_capture_quad_pressed)

    two_pass_button.show()
    two_pass_button.pressed.connect(_on_capture_two_pass_pressed)

# Can't get canvas working
func _on_capture_canvas_pressed():
    var vp = get_viewport()
    var size = vp.size
    var img = await DepthMapGeneratorCanvas.generate_depth_map(vp, camera, size, 4.0, 15.0)
    if img:
        DepthMapGeneratorCanvas.save_depth_map_debug(img)

func _on_capture_quad_pressed():
    var vp = get_viewport()
    var size = vp.size
    var img = await DepthMapGeneratorQuad.generate_depth_map(vp, camera, size, near_sphere)
    if img:
        DepthMapGeneratorQuad.save_depth_map_debug(img)

func _on_capture_two_pass_pressed():
    var vp = get_viewport()
    var size = vp.size
    # Render only Layer 2, which now contains the SideBox and NearSphere.
    var cull_mask = 2
    var img = await DepthMapGeneratorTwoPass.generate_depth_map(vp, camera, size, cull_mask)
    if img:
        DepthMapGeneratorTwoPass.save_depth_map_debug(img)
