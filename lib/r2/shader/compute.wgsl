@group(0) @binding(0) var<storage, read_write> pixel_data: array<u32>; 
@group(0) @binding(1) var<uniform> current_sample: f32;

@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let index = (id.y * 640) + id.x;
    if (current_sample == 0) {
        pixel_data[index] = 0xFF000000;
    } else {
        pixel_data[index] = pixel_data[index] + 1;
    }
}