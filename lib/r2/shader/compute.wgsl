struct RenderUniforms {
    current_sample: u32,
    image_width: u32,
    image_height: u32,
}

@group(0) @binding(0) var<storage, read_write> pixel_data: array<vec4<f32>>;
@group(0) @binding(1) var<uniform> uniforms: RenderUniforms;

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    if (id.x >= uniforms.image_width || id.y >= uniforms.image_height) {
        return;
    }

    let index = (id.y * uniforms.image_width) + id.x;
    if (uniforms.current_sample == 0) {
        pixel_data[index] = vec4f(0.0, 0.0, 0.0, 1.0);
    } else {
        pixel_data[index].r = pixel_data[index].r + (1.0 / 256.0);
    }
}