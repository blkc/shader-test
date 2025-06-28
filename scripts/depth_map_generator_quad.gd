class_name DepthMapGeneratorQuad
extends RefCounted

static func generate_depth_map(parent_vp: Viewport, camera: Camera3D, size: Vector2) -> Image:
    if not parent_vp or not camera:
        printerr("[DepthMapGeneratorQuad] Invalid Viewport or Camera provided.")
        return null

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

    var quad = MeshInstance3D.new()
    quad.mesh = QuadMesh.new()
    quad.mesh.size = Vector2(2, 2)
    quad.extra_cull_margin = 16384.0
    quad.material_override = _make_quad_depth_shader(cam.far)
    cam.add_child(quad)

    await sub_vp.get_tree().process_frame
    await sub_vp.get_tree().process_frame

    var img = sub_vp.get_texture().get_image()

    sub_vp.queue_free()
    return img

static func save_depth_map_debug(depth_image: Image, filepath: String = "user://depth_map_quad_debug.png") -> bool:
    if depth_image == null:
        printerr("[DepthMapGeneratorQuad] No image to save")
        return false
    var err = depth_image.save_png(filepath)
    if err != OK:
        printerr("[DepthMapGeneratorQuad] Failed to save PNG: %s" % err)
        return false
    return true

static func _make_quad_depth_shader(far_plane: float) -> ShaderMaterial:
    var mat = ShaderMaterial.new()
    var sh = Shader.new()
    sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture;
uniform float far_plane;

void vertex() {
    POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
    float depth = texture(DEPTH_TEXTURE, SCREEN_UV).r;

    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
    #else
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
    #endif

    vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    view.xyz /= view.w;
    float linear_depth = -view.z;

    ALBEDO = vec3(1.0 - (linear_depth / far_plane));
}
"""
    mat.shader = sh
    mat.set_shader_parameter("far_plane", far_plane)
    return mat