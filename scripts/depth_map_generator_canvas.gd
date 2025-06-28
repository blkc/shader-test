class_name DepthMapGeneratorCanvas
extends RefCounted

static func generate_depth_map(
    parent_vp: Viewport,
    camera: Camera3D,
    size: Vector2
) -> Image:
    if not parent_vp or not camera:
        print("[DepthMapGenerator] Invalid Viewport or Camera")
        return null

    var near_plane = camera.near
    var far_plane = camera.far

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
    cam.near = near_plane
    cam.far = far_plane
    cam.current = true
    sub_vp.add_child(cam)

    var layer = CanvasLayer.new()
    sub_vp.add_child(layer)

    var rect = ColorRect.new()
    rect.color = Color(1, 1, 1, 1)
    rect.anchor_left = 0; rect.anchor_top = 0
    rect.anchor_right = 1; rect.anchor_bottom = 1
    rect.offset_left = 0; rect.offset_top = 0
    rect.offset_right = 0; rect.offset_bottom = 0
    rect.material = _make_depth_shader(near_plane, far_plane)
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

static func _make_depth_shader(near_plane: float, far_plane: float) -> ShaderMaterial:
    var mat = ShaderMaterial.new()
    var sh = Shader.new()
    sh.code = """
shader_type canvas_item;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture;
uniform float near_plane;
uniform float far_plane;

void fragment() {
    float d = texture(DEPTH_TEXTURE, SCREEN_UV).r;
    float z_ndc = d * 2.0 - 1.0;
    float lin = (2.0 * near_plane * far_plane) /
                (far_plane + near_plane - z_ndc * (far_plane - near_plane));
    float norm = clamp((lin - near_plane)/(far_plane - near_plane), 0.0, 1.0);
    COLOR = vec4(vec3(1.0 - norm), 1.0);
}
"""
    mat.shader = sh
    mat.set_shader_parameter("near_plane", near_plane)
    mat.set_shader_parameter("far_plane", far_plane)
    return mat
