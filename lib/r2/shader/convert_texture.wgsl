struct RenderUniforms {
    current_sample: u32,
    image_width: u32,
    image_height: u32,
}

@group(0) @binding(0) var<storage, read> pixel_data: array<vec4<f32>>;
@group(0) @binding(1) var texture: texture_storage_2d<rgba8unorm, write>;
@group(0) @binding(2) var<uniform> uniforms: RenderUniforms;

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    if (id.x >= uniforms.image_width || id.y >= uniforms.image_height) {
        return;
    }

    let index = (id.y * uniforms.image_width) + id.x;
    let color = pixel_data[index];
    textureStore(texture, vec2<i32>(i32(id.x), i32(id.y)), color);
}