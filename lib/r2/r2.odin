package r2

import "base:runtime"

import "external:wgpu"

import "raytracing2:lib/r2/util"

State :: struct {
	image_width:  u32,
	image_height: u32,
	_device:      wgpu.Device,
	_queue:       wgpu.Queue,
}

// The R2 renderer takes a WebGPU Device and provides a TextureView and Sampler for use
init :: proc(image_width, image_height: u32, device: wgpu.Device) -> ^State {
	r := new(State)
	r.image_width, r.image_height = image_width, image_height
	r._device = device
	r._queue = wgpu.DeviceGetQueue(r._device)
	return r
}

cleanup :: proc(r: ^State) {
	wgpu.QueueRelease(r._queue)
	free(r)
}

update_image :: proc(r: ^State, image_width, image_height: u32) {
	if ((r.image_width != image_width) || (r.image_height != image_height)) {
		r.image_width = image_width
		r.image_height = image_height
	}
}

RenderContext :: struct {
	// samples
	_max_sample_count:         u32,
	_current_sample:           u32,
	// gpu objects
	_current_sample_buffer:    wgpu.Buffer,
	_compute_shader:           wgpu.ShaderModule,
	_compute_bindgroup_layout: wgpu.BindGroupLayout,
	_compute_bindgroup:        wgpu.BindGroup,
	_compute_pipeline_layout:  wgpu.PipelineLayout,
	_compute_pipeline:         wgpu.ComputePipeline,
	_texture:                  wgpu.Texture,
	_texture_view:             wgpu.TextureView,
	_texture_sampler:          wgpu.Sampler,
}

MAX_SAMPLE_COUNT :: 4096
WORKGROUP_SIZE_PER_DIMENSION :: 8

// R2 provides a rendering API which expects the user to determine when the rendering
// needs to be reset (e.g if the user modifies the scene).
//
// NOTE: At the moment I don't have any scene or other concepts yet, so the information needed
//       for the render is pulled from the R2 struct. Specifically the image width and height.
//       Following the "user determines when render needs to be reset", its up to the user to
// 		 call `reset_render_context` when they modify the image width and height.
create_render_context :: proc(r: ^State) -> ^RenderContext {
	rctx := new(RenderContext)
	reset_render_context(r, rctx)
	return rctx
}

render_next_sample :: proc(r: ^State, rctx: ^RenderContext) -> (wgpu.TextureView, wgpu.Sampler) {
	// Only render if there is samples left
	if rctx._current_sample < rctx._max_sample_count {
		// Create command encoder
		encoder := wgpu.DeviceCreateCommandEncoder(r._device, nil)
		defer wgpu.CommandEncoderRelease(encoder)

		// Create compute pass
		compute_pass := wgpu.CommandEncoderBeginComputePass(encoder, nil)

		wgpu.ComputePassEncoderSetPipeline(compute_pass, rctx._compute_pipeline)
		wgpu.ComputePassEncoderSetBindGroup(compute_pass, 0, rctx._compute_bindgroup)
		wgpu.QueueWriteBuffer(
			r._queue,
			rctx._current_sample_buffer,
			0,
			&rctx._current_sample,
			size_of(f32),
		)
		wg_count_x :=
			(r.image_width + WORKGROUP_SIZE_PER_DIMENSION - 1) / WORKGROUP_SIZE_PER_DIMENSION
		wg_count_y :=
			(r.image_height + WORKGROUP_SIZE_PER_DIMENSION - 1) / WORKGROUP_SIZE_PER_DIMENSION
		wgpu.ComputePassEncoderDispatchWorkgroups(compute_pass, wg_count_x, wg_count_y, 1)

		wgpu.ComputePassEncoderEnd(compute_pass)
		wgpu.ComputePassEncoderRelease(compute_pass)

		// Encode + submit
		command_buffer := wgpu.CommandEncoderFinish(encoder, nil)
		defer wgpu.CommandBufferRelease(command_buffer)

		wgpu.QueueSubmit(r._queue, {command_buffer})

		// Increment sample
		rctx._current_sample += 1
	}
	return rctx._texture_view, rctx._texture_sampler
}

reset_render_context :: proc(r: ^State, rctx: ^RenderContext) {
	// reset sample
	rctx._max_sample_count = MAX_SAMPLE_COUNT
	rctx._current_sample = 0

	// free GPU objects if they already exist
	free_render_context_objects(rctx)

	// create texture GPU objects
	rctx._texture = wgpu.DeviceCreateTexture(
		r._device,
		&{
			usage = {.TextureBinding, .CopyDst},
			dimension = ._2D,
			size = {width = r.image_width, height = r.image_height, depthOrArrayLayers = 1},
			format = .RGBA8Unorm,
			mipLevelCount = 1,
			sampleCount = 1,
		},
	)
	rctx._texture_view = wgpu.TextureCreateView(
		rctx._texture,
		// TODO: Could be nil since we don't want to provide a different view than the texture format?
		&{
			format = .RGBA8Unorm,
			dimension = ._2D,
			baseMipLevel = 0,
			mipLevelCount = 1,
			baseArrayLayer = 0,
			arrayLayerCount = 1,
			aspect = .All,
			usage = {.TextureBinding, .CopyDst},
		},
	)
	rctx._texture_sampler = wgpu.DeviceCreateSampler(
		r._device,
		&{
			addressModeU = .Repeat,
			addressModeV = .Repeat,
			addressModeW = .Repeat,
			magFilter = .Nearest,
			minFilter = .Nearest,
			mipmapFilter = .Nearest,
			lodMinClamp = 0.0,
			lodMaxClamp = 1.0,
			compare = .Undefined,
			maxAnisotropy = 1,
		},
	)

	// create compute GPU objects
	// TODO: We very likely don't need to recreate most of these objects every reset
	//       as they don't rely on data from R2
	rctx._current_sample_buffer = wgpu.DeviceCreateBuffer(
		r._device,
		&{label = "Constant Buffer", usage = {.Uniform, .CopyDst}, size = size_of(f32)},
	)
	rctx._compute_shader = wgpu.DeviceCreateShaderModule(
		r._device,
		&{
			nextInChain = &wgpu.ShaderSourceWGSL {
				sType = .ShaderSourceWGSL,
				code = #load("shader/compute.wgsl", string),
			},
		},
	)
	rctx._compute_bindgroup_layout = wgpu.DeviceCreateBindGroupLayout(
		r._device,
		&{
			entryCount = 3,
			entries = raw_data(
				[]wgpu.BindGroupLayoutEntry {
					{binding = 0, visibility = {.Compute}, sampler = {type = .Filtering}},
					{
						binding = 1,
						visibility = {.Compute},
						texture = {
							sampleType = .Float,
							viewDimension = ._2D,
							multisampled = false,
						},
					},
					{
						binding = 2,
						visibility = {.Compute},
						buffer = {type = .Uniform, minBindingSize = size_of(f32)},
					},
				},
			),
		},
	)
	rctx._compute_bindgroup = wgpu.DeviceCreateBindGroup(
		r._device,
		&{
			layout = rctx._compute_bindgroup_layout,
			entryCount = 3,
			entries = raw_data(
				[]wgpu.BindGroupEntry {
					{binding = 0, sampler = rctx._texture_sampler},
					{binding = 1, textureView = rctx._texture_view},
					{binding = 2, buffer = rctx._current_sample_buffer, size = size_of(f32)},
				},
			),
		},
	)
	rctx._compute_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		r._device,
		&{bindGroupLayoutCount = 1, bindGroupLayouts = &rctx._compute_bindgroup_layout},
	)
	rctx._compute_pipeline = wgpu.DeviceCreateComputePipeline(
		r._device,
		&{layout = nil, compute = {module = rctx._compute_shader, entryPoint = "compute_main"}},
	)
}

@(private = "file")
free_render_context_objects :: proc(rctx: ^RenderContext) {
	if (rctx._texture_sampler != nil) {
		wgpu.SamplerRelease(rctx._texture_sampler)
		rctx._texture_sampler = nil
	}
	if (rctx._texture_view != nil) {
		wgpu.TextureViewRelease(rctx._texture_view)
		rctx._texture_view = nil
	}
	if (rctx._texture != nil) {
		wgpu.TextureRelease(rctx._texture)
		rctx._texture = nil
	}
	if (rctx._compute_pipeline != nil) {
		wgpu.ComputePipelineRelease(rctx._compute_pipeline)
		rctx._compute_pipeline = nil
	}
	if (rctx._compute_pipeline_layout != nil) {
		wgpu.PipelineLayoutRelease(rctx._compute_pipeline_layout)
		rctx._compute_pipeline_layout = nil
	}
	if (rctx._compute_bindgroup != nil) {
		wgpu.BindGroupRelease(rctx._compute_bindgroup)
		rctx._compute_bindgroup = nil
	}
	if (rctx._compute_bindgroup_layout != nil) {
		wgpu.BindGroupLayoutRelease(rctx._compute_bindgroup_layout)
		rctx._compute_bindgroup_layout = nil
	}
	if (rctx._compute_shader != nil) {
		wgpu.ShaderModuleRelease(rctx._compute_shader)
		rctx._compute_shader = nil
	}
	if (rctx._current_sample_buffer != nil) {
		wgpu.BufferRelease(rctx._current_sample_buffer)
		rctx._current_sample_buffer = nil
	}
}

destroy_render_context :: proc(rctx: ^RenderContext) {
	free_render_context_objects(rctx)
	free(rctx)
}
