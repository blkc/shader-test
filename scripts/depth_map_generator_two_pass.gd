class_name DepthMapGeneratorTwoPass
extends RefCounted

## Generates a high-contrast depth map using a two-pass method.
## It correctly handles deformed meshes with skeletons by bypassing AABB calculations.
static func generate_depth_map(parent_vp: Viewport, camera: Camera3D, size: Vector2, cull_mask: int = 0b1) -> Image:
	if not parent_vp or not camera:
		printerr("[DepthMapGeneratorTwoPass] Invalid Viewport or Camera provided.")
		return null

	# --- PASS 1: Render raw, encoded depth to a texture ---
	var raw_depth_image = await _pass_1_get_raw_depth_image(parent_vp, camera, size, cull_mask)
	if raw_depth_image == null:
		printerr("[DepthMapGeneratorTwoPass] Failed to generate raw depth image.")
		return null

	# --- PASS 2: Analyze the raw image and normalize it to a final 8-bit image ---
	var final_image = _pass_2_normalize_raw_image(raw_depth_image)
	
	return final_image


## Creates a SubViewport to render the scene with a shader that writes raw linear depth.
static func _pass_1_get_raw_depth_image(parent_vp: Viewport, camera: Camera3D, size: Vector2, cull_mask: int) -> Image:
	var sub_vp = SubViewport.new()
	sub_vp.size = size
	sub_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	sub_vp.transparent_bg = true
	# Use the same 3D world, but the camera inside will have no environment.
	sub_vp.world_3d = parent_vp.world_3d
	parent_vp.add_child(sub_vp)

	var cam = camera.duplicate() as Camera3D
	# Explicitly copy camera properties to ensure the duplicate is exact.
	cam.global_transform = camera.global_transform
	cam.projection = camera.projection
	cam.fov = camera.fov
	cam.size = camera.size
	cam.near = camera.near
	cam.far = camera.far
	# Set the cull mask to render only the specified layers.
	cam.cull_mask = cull_mask
	# Ensure the camera inside the viewport has no environment to force an unlit render.
	cam.environment = null
	# This is crucial so the SubViewport actually uses this camera.
	cam.current = true
	sub_vp.add_child(cam)

	var quad = MeshInstance3D.new()
	quad.mesh = QuadMesh.new()
	quad.mesh.size = Vector2(2, 2)
	quad.extra_cull_margin = 16384.0
	quad.material_override = _make_raw_depth_shader()
	cam.add_child(quad)

	await sub_vp.get_tree().process_frame
	await sub_vp.get_tree().process_frame

	var img = sub_vp.get_texture().get_image()
	sub_vp.queue_free()
	
	return img


## Decodes a 3-channel Color back into a single high-precision float value.
static func _unpack_rgb_to_float(c: Color) -> float:
	return c.r + (c.g / 255.0) + (c.b / 65025.0)


## Iterates over the raw image, finds the min/max depth range,
## and uses that range to create a normalized L8 grayscale image.
static func _pass_2_normalize_raw_image(raw_image: Image) -> Image:
	var width = raw_image.get_width()
	var height = raw_image.get_height()

	var d_min = 1e30
	var d_max = -1e30

	# First, find the true min/max depth of the objects in the image
	for y in range(height):
		for x in range(width):
			var packed_color = raw_image.get_pixel(x, y)
			# Use the alpha channel as a sentinel to identify object pixels.
			if packed_color.a > 0.5:
				var d = _unpack_rgb_to_float(packed_color)
				d_min = min(d_min, d)
				d_max = max(d_max, d)

	if not is_finite(d_min):
		printerr("[DepthMapGeneratorTwoPass] No objects found in depth map (is scene empty?).")
		return null

	# Second, normalize the depth into the 0-1 range and create the final image
	var final_image = Image.create(width, height, false, Image.FORMAT_L8)
	var range = d_max - d_min

	# If the object's depth range is negligible, create a small, artificial
	# range to ensure a subtle gradient is still visible. This prevents
	# shallow objects from appearing as a solid white color.
	if range < 1e-6:
		d_max = d_min + 0.1 # Create an artificial 10cm depth range.
		range = 0.1

	for y in range(height):
		for x in range(width):
			var packed_color = raw_image.get_pixel(x, y)
			var norm = 0.0
			# Check for background pixels again before normalizing
			if packed_color.a > 0.5:
				var d = _unpack_rgb_to_float(packed_color)
				norm = clamp((d - d_min) / range, 0.0, 1.0)
			else:
				# Explicitly set background to the farthest value
				norm = 1.0
			
			# Invert so closer objects are whiter, and write to L8 format.
			# A gamma correction is applied to brighten mid-tones and match the "squirrel" look.
			var gamma = 0.45
			var final_value = pow(1.0 - norm, gamma)
			final_image.set_pixel(x, y, Color(final_value, final_value, final_value))
			
	return final_image


static func _make_raw_depth_shader() -> ShaderMaterial:
	var mat = ShaderMaterial.new()
	var sh = Shader.new()
	# This shader no longer needs camera uniforms passed in.
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture;

// Encodes a float value into a 3-channel RGB vector.
// This leaves the Alpha channel free for a sentinel.
vec3 pack_float_to_rgb(float v) {
	vec3 enc = vec3(1.0, 255.0, 65025.0) * v;
	enc = fract(enc);
	enc -= enc.yzx * vec3(1.0/255.0, 1.0/255.0, 0.0);
	return enc;
}

void fragment() {
	// Read the raw non-linear depth value from the buffer
	float d = texture(DEPTH_TEXTURE, SCREEN_UV).r;

	// Use the inverse projection matrix for a more robust depth calculation.
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, d) * 2.0 - 1.0;
	#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, d);
	#endif
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float linear_depth = -view.z;
	
	// Use the alpha channel as a sentinel to mark background pixels.
	// If d is 1.0, it's the clear color, i.e., the background.
	float is_object = d < 1.0 ? 1.0 : 0.0;
	
	// Output the encoded high-precision depth as the color
	vec3 encoded_depth = pack_float_to_rgb(linear_depth);
	ALBEDO = encoded_depth;
	ALPHA = is_object;
}
"""
	mat.shader = sh
	return mat

static func save_depth_map_debug(depth_image: Image, filepath: String = "user://depth_map_two_pass_debug.png") -> bool:
	if depth_image == null:
		printerr("[DepthMapGeneratorTwoPass] No image to save")
		return false
	var err = depth_image.save_png(filepath)
	if err != OK:
		printerr("[DepthMapGeneratorTwoPass] Failed to save PNG: %s" % err)
		return false
	return true
