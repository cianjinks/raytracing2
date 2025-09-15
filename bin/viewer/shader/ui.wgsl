struct VertexInput {
    @location(0) position: vec2f,
    @location(1) texture_coord: vec2f,
    @location(2) color: u32, // TODO: Should this be u32?
}

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) texture_coord: vec2f,
    @location(1) @interpolate(flat) color: u32,
}

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    out.position = transform * vec4f(in.position, 0.0, 1.0);
    out.texture_coord = in.texture_coord;
    out.color = in.color;
    return out;
}

@group(0) @binding(0) var textureSampler: sampler;
@group(0) @binding(1) var texture: texture_2d<f32>;
@group(0) @binding(2) var<uniform> transform: mat4x4<f32>;

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4f {
    // the microui default atlas just contains alpha
    // we use the vertex color for rgb channels
    let texColor = textureSample(texture, textureSampler, in.texture_coord);
    let a = texColor.r * f32((in.color >> 24) & 0xffu) / 255;
    let b = f32((in.color >> 16) & 0xffu) / 255;
    let g = f32((in.color >> 8) & 0xffu) / 255;
    let r = f32(in.color & 0xffu) / 255;
    return vec4f(r, g, b, a);
}