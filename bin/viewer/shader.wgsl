struct VertexInput {
    @location(0) position: vec2f,
    @location(1) texture_coord: vec2f,
}

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) texture_coord: vec2f,
}

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    out.position = vec4f(in.position, 0.0, 1.0);
    out.texture_coord = in.texture_coord;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4f {
    return vec4f(0.0, 0.4, 1.0, 1.0);
}