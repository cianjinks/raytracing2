package viewer

import "base:runtime"

import "core:log"

import "external:glfw"
import "external:wgpu"
import "external:wgpu/glfwglue"

Renderer :: struct {
	ctx:              runtime.Context,
	window_width:     u32,
	window_height:    u32,
	instance:         wgpu.Instance,
	surface:          wgpu.Surface,
	adapter:          wgpu.Adapter,
	device:           wgpu.Device,
	config:           wgpu.SurfaceConfiguration,
	queue:            wgpu.Queue,
	module:           wgpu.ShaderModule,
	pipeline_layout:  wgpu.PipelineLayout,
	pipeline:         wgpu.RenderPipeline,
	buffer:           wgpu.Buffer,
	texture:          wgpu.Texture,
	texture_view:     wgpu.TextureView,
	bindgroup_layout: wgpu.BindGroupLayout,
	bindgroup:        wgpu.BindGroup,
}

// TODO: We should possibly just take a surface here so that the renderer
//       does not rely on GLFW directly?
renderer_create :: proc(
	window_width, window_height: u32,
	raw_window: glfw.WindowHandle,
) -> ^Renderer {
	r := new(Renderer)
	r.ctx = context
	r.window_width = window_width
	r.window_height = window_height

	wgpu.SetLogCallback(log_callback, nil)

	instance := wgpu.CreateInstance(nil)
	if instance == nil {
		log.panic("Failed to create WebGPU instance")
	}
	r.instance = instance

	surface := glfwglue.GetSurface(instance, raw_window)
	if surface == nil {
		log.panic("Failed to create WebGPU surface")
	}
	r.surface = surface

	wgpu.InstanceRequestAdapter(
		instance,
		&{compatibleSurface = r.surface},
		// this begins a chain of callbacks to setup wgpu
		{callback = request_adapter_callback, userdata1 = rawptr(r)},
	)

	// NOTE: For native webgpu we can assume the above callback chain has run before we exit here

	return r
}

renderer_on_update :: proc(r: ^Renderer) {
	// Get surface texture
	surface_texture := wgpu.SurfaceGetCurrentTexture(r.surface)
	switch surface_texture.status {
	case .SuccessOptimal, .SuccessSuboptimal:
	// good
	case .Timeout, .Outdated, .Lost:
	// TODO
	case .OutOfMemory, .DeviceLost, .Error:
		log.panicf("[WGPU Error] Failed to get surface texture: %v", surface_texture.status)
	}
	defer wgpu.TextureRelease(surface_texture.texture)

	// Create view for surface texture (with defaults)
	view := wgpu.TextureCreateView(surface_texture.texture, nil)
	defer wgpu.TextureViewRelease(view)

	// Create command encoder (with defaults)
	encoder := wgpu.DeviceCreateCommandEncoder(r.device, nil)
	defer wgpu.CommandEncoderRelease(encoder)

	// Create a render pass that clears the screen
	// (we create it then immediately end it without drawing anything)
	render_pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&wgpu.RenderPassDescriptor {
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment {
				view = view,
				depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
				loadOp = .Clear,
				storeOp = .Store,
				clearValue = {1.0, 0.0, 0.0, 1.0},
			},
		},
	)

	wgpu.RenderPassEncoderSetPipeline(render_pass, r.pipeline)
	wgpu.RenderPassEncoderSetVertexBuffer(
		render_pass,
		0,
		r.buffer,
		0,
		wgpu.BufferGetSize(r.buffer),
	)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, r.bindgroup)
	wgpu.RenderPassEncoderDraw(render_pass, 6, 2, 0, 0)

	wgpu.RenderPassEncoderEnd(render_pass)
	wgpu.RenderPassEncoderRelease(render_pass)

	// Encode + submit render pass
	command_buffer := wgpu.CommandEncoderFinish(encoder, nil)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(r.queue, {command_buffer})
	wgpu.SurfacePresent(r.surface)
}

renderer_on_event :: proc(r: ^Renderer, event: Event) {
	#partial switch event.type {
	case .WindowResize:
		r.config.width, r.config.height = event.width, event.height
		wgpu.SurfaceConfigure(r.surface, &r.config)
	case:
	// Ignore
	}
}

renderer_destroy :: proc(r: ^Renderer) {
	wgpu.BindGroupRelease(r.bindgroup)
	wgpu.BindGroupLayoutRelease(r.bindgroup_layout)
	wgpu.TextureViewRelease(r.texture_view)
	wgpu.TextureRelease(r.texture)
	wgpu.BufferRelease(r.buffer)
	wgpu.RenderPipelineRelease(r.pipeline)
	wgpu.PipelineLayoutRelease(r.pipeline_layout)
	wgpu.ShaderModuleRelease(r.module)
	wgpu.SurfaceUnconfigure(r.surface)
	wgpu.QueueRelease(r.queue)
	wgpu.DeviceRelease(r.device)
	wgpu.AdapterRelease(r.adapter)
	wgpu.SurfaceRelease(r.surface)
	wgpu.InstanceRelease(r.instance)
	free(r)
}

@(private = "file")
log_callback :: proc "c" (level: wgpu.LogLevel, message: wgpu.StringView, userdata: rawptr) {
	context = runtime.default_context()
	log.infof("[WGPU Log] %v - %s", level, message)
}

@(private = "file")
request_adapter_callback :: proc "c" (
	status: wgpu.RequestAdapterStatus,
	adapter: wgpu.Adapter,
	message: string,
	userdata1: rawptr,
	userdata2: rawptr,
) {
	r := (^Renderer)(userdata1)
	context = r.ctx

	if status != wgpu.RequestAdapterStatus.Success || adapter == nil {
		log.panicf("[WGPU Error] %v - %s", status, message)
	}
	r.adapter = adapter

	wgpu.AdapterRequestDevice(
		adapter,
		nil,
		{callback = request_device_callback, userdata1 = rawptr(r)},
	)
}

@(private = "file")
request_device_callback :: proc "c" (
	status: wgpu.RequestDeviceStatus,
	device: wgpu.Device,
	message: string,
	userdata1: rawptr,
	userdata2: rawptr,
) {
	r := (^Renderer)(userdata1)
	context = r.ctx

	if status != wgpu.RequestDeviceStatus.Success || device == nil {
		log.panicf("[WGPU Error] %v - %s", status, message)
	}
	r.device = device

	r.config = wgpu.SurfaceConfiguration {
		device      = r.device,
		usage       = {.RenderAttachment},
		format      = .BGRA8Unorm,
		width       = r.window_width,
		height      = r.window_height,
		presentMode = .Fifo,
		alphaMode   = .Opaque,
	}
	wgpu.SurfaceConfigure(r.surface, &r.config)

	r.queue = wgpu.DeviceGetQueue(r.device)

	r.module = wgpu.DeviceCreateShaderModule(
		r.device,
		&{
			nextInChain = &wgpu.ShaderSourceWGSL {
				sType = .ShaderSourceWGSL,
				code = #load("shader.wgsl", string),
			},
		},
	)

	// 2 triangles with texture coordinates to make a quad
	data := []f32 {
		// top left
		-1.0,
		1.0,
		0.0,
		1.0,
		// bottom left
		-1.0,
		-1.0,
		0.0,
		0.0,
		// bottom right
		1.0,
		-1.0,
		1.0,
		0.0,
		// top left
		-1.0,
		1.0,
		0.0,
		1.0,
		// bottom right
		1.0,
		-1.0,
		1.0,
		0.0,
		// top right
		1.0,
		1.0,
		1.0,
		1.0,
	}
	data_size := 24 * size_of(f32)
	r.buffer = wgpu.DeviceCreateBuffer(
		r.device,
		&{usage = wgpu.BufferUsageFlags{.CopyDst, .Vertex}, size = u64(data_size)},
	)
	wgpu.QueueWriteBuffer(r.queue, r.buffer, 0, rawptr(&data[0]), uint(data_size))
	buffer_attributes := []wgpu.VertexAttribute {
		{format = .Float32x2, offset = 0, shaderLocation = 0},
		{format = .Float32x2, offset = 2 * size_of(f32), shaderLocation = 1},
	}

	// a simple texture
	r.texture = wgpu.DeviceCreateTexture(
		r.device,
		&{
			usage = {.TextureBinding, .CopyDst},
			dimension = ._2D,
			size = {width = r.window_width, height = r.window_height, depthOrArrayLayers = 1},
			format = .RGBA8Unorm,
			mipLevelCount = 1,
			sampleCount = 1,
		},
	)
	r.texture_view = wgpu.TextureCreateView(
		r.texture,
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

	texture_data := make([]u8, r.window_width * r.window_height * 4)
	for x in 0 ..< r.window_width {
		for y in 0 ..< r.window_height {
			idx := ((x * r.window_height) + y) * 4
			texture_data[idx] = 128
			texture_data[idx + 1] = 128
			texture_data[idx + 2] = 128
			texture_data[idx + 3] = 255
		}
	}
	wgpu.QueueWriteTexture(
		r.queue,
		destination = &{texture = r.texture, mipLevel = 0, origin = {0, 0, 0}, aspect = .All},
		data = rawptr(&texture_data[0]),
		dataSize = len(texture_data) * size_of(u8),
		dataLayout = &{
			offset = 0,
			bytesPerRow = 4 * r.window_width,
			rowsPerImage = r.window_height,
		},
		writeSize = &{r.window_width, r.window_height, 1},
	)
	delete(texture_data)


	// bindings
	bindgroup_layout_entries := []wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Fragment},
			texture = {sampleType = .Float, viewDimension = ._2D},
		},
	}
	r.bindgroup_layout = wgpu.DeviceCreateBindGroupLayout(
		r.device,
		&{
			entryCount = len(bindgroup_layout_entries),
			entries = raw_data(bindgroup_layout_entries[:]),
		},
	)
	bindgroup_entries := []wgpu.BindGroupEntry{{binding = 0, textureView = r.texture_view}}
	r.bindgroup = wgpu.DeviceCreateBindGroup(
		r.device,
		&{
			layout = r.bindgroup_layout,
			entryCount = len(bindgroup_entries),
			entries = raw_data(bindgroup_entries[:]),
		},
	)

	// pipeline
	r.pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		r.device,
		&{bindGroupLayoutCount = 1, bindGroupLayouts = &r.bindgroup_layout},
	)
	r.pipeline = wgpu.DeviceCreateRenderPipeline(
		r.device,
		&wgpu.RenderPipelineDescriptor {
			layout = r.pipeline_layout,
			vertex = wgpu.VertexState {
				module = r.module,
				entryPoint = "vs_main",
				bufferCount = 1,
				buffers = &wgpu.VertexBufferLayout {
					stepMode = .Vertex,
					arrayStride = 4 * size_of(f32),
					attributeCount = len(buffer_attributes),
					attributes = raw_data(buffer_attributes[:]),
				},
				constantCount = 0,
				constants = nil,
			},
			primitive = wgpu.PrimitiveState {
				topology = .TriangleList,
				stripIndexFormat = .Undefined,
				frontFace = .CCW,
				cullMode = .None,
			},
			depthStencil = nil,
			multisample = wgpu.MultisampleState {
				count = 1,
				mask = 0xFFFFFFFF,
				alphaToCoverageEnabled = false,
			},
			fragment = &wgpu.FragmentState {
				module = r.module,
				entryPoint = "fs_main",
				targetCount = 1,
				targets = &wgpu.ColorTargetState {
					format = .BGRA8Unorm,
					blend = nil,
					writeMask = wgpu.ColorWriteMaskFlags_All,
				},
				constantCount = 0,
				constants = nil,
			},
		},
	)
}
