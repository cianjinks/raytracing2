@group(0) @binding(0) var<storage, read> pixel_data: array<vec4<f32>>;
@group(0) @binding(1) var texture: texture_storage_2d<rgba8unorm, write>;

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let index = (id.y * 640) + id.x;
    let color = pixel_data[index];
    textureStore(texture, vec2<i32>(i32(id.x), i32(id.y)), color);
}