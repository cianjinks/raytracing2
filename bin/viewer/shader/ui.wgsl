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
    return textureSample(texture, textureSampler, in.texture_coord);
}