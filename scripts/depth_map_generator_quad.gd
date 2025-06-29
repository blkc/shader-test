class_name DepthMapGeneratorQuad
extends RefCounted

static func generate_depth_map(parent_vp: Viewport, camera: Camera3D, size: Vector2, model_node: Node3D = null) -> Image:
    if not parent_vp or not camera:
        printerr("[DepthMapGeneratorQuad] Invalid Viewport or Camera provided.")
        return null

    var remap_n: float
    var remap_f: float

    if model_node:
        var remap_values = _calculate_remap_from_model(model_node, camera)
        remap_n = remap_values[0]
        remap_f = remap_values[1]
    else:
        remap_n = camera.near
        remap_f = camera.far

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
    quad.material_override = _make_quad_depth_shader(remap_n, remap_f)
    cam.add_child(quad)

    await sub_vp.get_tree().process_frame
    await sub_vp.get_tree().process_frame

    var img = sub_vp.get_texture().get_image()

    sub_vp.queue_free()
    return img

static func _calculate_remap_from_model(model_node: Node3D, camera: Camera3D) -> PackedFloat32Array:
    var model_aabb = _get_model_aabb(model_node)

    if model_aabb.size == Vector3.ZERO:
        return [camera.near, camera.far]

    var view_matrix = camera.global_transform.affine_inverse()

    var min_z = INF
    var max_z = - INF

    for i in 8:
        var corner = model_aabb.get_endpoint(i)
        var view_pos = view_matrix * corner
        min_z = min(min_z, view_pos.z)
        max_z = max(max_z, view_pos.z)

    var remap_near = - max_z
    var remap_far = - min_z

    var padding = (remap_far - remap_near) * 0.05
    remap_near -= padding
    remap_far += padding

    remap_near = max(remap_near, camera.near)
    remap_far = min(remap_far, camera.far)

    return [remap_near, remap_far]

static func _get_model_aabb(node: Node3D) -> AABB:
    var aabb = AABB()
    var has_aabb = false

    var queue: Array[Node] = [node]
    while not queue.is_empty():
        var current = queue.pop_front()
        if current is VisualInstance3D and current.is_visible_in_tree():
            var instance_aabb = current.global_transform * current.get_aabb()
            if not has_aabb:
                aabb = instance_aabb
                has_aabb = true
            else:
                aabb = aabb.merge(instance_aabb)

        for child in current.get_children():
            queue.push_back(child)

    return aabb if has_aabb else AABB()

static func save_depth_map_debug(depth_image: Image, filepath: String = "user://depth_map_quad_debug.png") -> bool:
    if depth_image == null:
        printerr("[DepthMapGeneratorQuad] No image to save")
        return false
    var err = depth_image.save_png(filepath)
    if err != OK:
        printerr("[DepthMapGeneratorQuad] Failed to save PNG: %s" % err)
        return false
    return true

static func _make_quad_depth_shader(remap_near: float, remap_far: float) -> ShaderMaterial:
    var mat = ShaderMaterial.new()
    var sh = Shader.new()
    sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture;
uniform float remap_near;
uniform float remap_far;

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

    float norm = (linear_depth - remap_near) / (remap_far - remap_near);

    ALBEDO = vec3(1.0 - clamp(norm, 0.0, 1.0));
}
"""
    mat.shader = sh
    mat.set_shader_parameter("remap_near", remap_near)
    mat.set_shader_parameter("remap_far", remap_far)
    return mat
