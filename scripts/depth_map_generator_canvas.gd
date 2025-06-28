class_name DepthMapGeneratorCanvas
extends RefCounted

static func generate_depth_map(
    parent_vp: Viewport,
    camera: Camera3D,
    size: Vector2,
    remap_near: float = -1.0,
    remap_far: float = -1.0
) -> Image:
    if not parent_vp or not camera:
        print("[DepthMapGenerator] Invalid Viewport or Camera")
        return null

    var remap_n = remap_near if remap_near >= 0.0 else camera.near
    var remap_f = remap_far if remap_far >= 0.0 else camera.far

    var sub_vp = SubViewport.new()
    sub_vp.size = size
    sub_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
    sub_vp.transparent_bg = true
    sub_vp.world_3d = parent_vp.world_3d
    parent_vp.add_child(sub_vp)

    var cam = Camera3D.new()
    cam.global_transform = camera.global_transform
    cam.projection = camera.projection
    cam.keep_aspect = camera.keep_aspect
    cam.near = camera.near
    cam.far = camera.far
    cam.current = true
    sub_vp.add_child(cam)

    var layer = CanvasLayer.new()
    sub_vp.add_child(layer)

    var rect = ColorRect.new()
    rect.color = Color(1, 1, 1, 1)
    rect.anchors_preset = Control.PRESET_FULL_RECT
    rect.material = _make_depth_shader(camera.near, camera.far, remap_n, remap_f)
    layer.add_child(rect)

    await sub_vp.get_tree().process_frame
    await sub_vp.get_tree().process_frame

    var img = sub_vp.get_texture().get_image()

    sub_vp.queue_free()
    return img

static func save_depth_map_debug(depth_image: Image, filepath: String = "user://depth_map_canvas_debug.png") -> bool:
    if depth_image == null:
        printerr("[DepthMapGenerator] No image to save")
        return false
    var err = depth_image.save_png(filepath)
    if err != OK:
        printerr("[DepthMapGenerator] Failed to save PNG: %s" % err)
        return false
    return true

static func _make_depth_shader(camera_near: float, camera_far: float, remap_near: float, remap_far: float) -> ShaderMaterial:
    var mat = ShaderMaterial.new()
    var sh = Shader.new()
    sh.code = """
shader_type canvas_item;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture;
uniform float camera_near;
uniform float camera_far;
uniform float remap_near;
uniform float remap_far;

void fragment() {
    float d = texture(DEPTH_TEXTURE, SCREEN_UV).r;
    float z_ndc = d * 2.0 - 1.0;

    float linear_depth = (2.0 * camera_near * camera_far) /
                         (camera_far + camera_near - z_ndc * (camera_far - camera_near));
    float norm = (linear_depth - remap_near) / (remap_far - remap_near);
    
    COLOR = vec4(vec3(1.0 - clamp(norm, 0.0, 1.0)), 1.0);
}
"""
    mat.shader = sh
    mat.set_shader_parameter("camera_near", camera_near)
    mat.set_shader_parameter("camera_far", camera_far)
    mat.set_shader_parameter("remap_near", remap_near)
    mat.set_shader_parameter("remap_far", remap_far)
    return mat
