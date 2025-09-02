package viewer

import "base:runtime"

import "core:log"

import "external:glfw"
import "external:microui"
import "external:wgpu"
import "external:wgpu/glfwglue"

import "raytracing2:lib/r2/util"

Renderer :: struct {
	ctx:                      runtime.Context,
	window_width:             u32,
	window_height:            u32,

	// create
	instance:                 wgpu.Instance,
	surface:                  wgpu.Surface,
	adapter:                  wgpu.Adapter,
	device:                   wgpu.Device,
	config:                   wgpu.SurfaceConfiguration,
	queue:                    wgpu.Queue,

	// texture view rendering
	texture_shader:           wgpu.ShaderModule,
	texture_pipeline_layout:  wgpu.PipelineLayout,
	texture_pipeline:         wgpu.RenderPipeline,
	texture_quad_buffer:      wgpu.Buffer,
	texture_bindgroup_layout: wgpu.BindGroupLayout,

	// microui rendering
	ui_shader:                wgpu.ShaderModule,
	ui_atlas_texture:         wgpu.Texture,
	ui_atlas_texture_view:    wgpu.TextureView,
	ui_sampler:               wgpu.Sampler,
	ui_transform_matrix:      wgpu.Buffer,
	ui_tex_buffer:            wgpu.Buffer,
	ui_vertex_buffer:         wgpu.Buffer,
	ui_color_buffer:          wgpu.Buffer,
	ui_index_buffer:          wgpu.Buffer,
	ui_bindgroup_layout:      wgpu.BindGroupLayout,
	ui_bindgroup:             wgpu.BindGroup,
	ui_pipeline_layout:       wgpu.PipelineLayout,
	ui_pipeline:              wgpu.RenderPipeline,

	// render
	curr_surface_texture:     wgpu.Texture,
	curr_surface_view:        wgpu.TextureView,
}

UI_BUFFER_SIZE :: 16384

// A simple texture renderer

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

renderer_render :: proc(
	r: ^Renderer,
	texture_view: wgpu.TextureView,
	texture_sampler: wgpu.Sampler,
	ui_ctx: ^microui.Context,
) {
	renderer_begin(r)
	renderer_render_texture_view(r, texture_view, texture_sampler)
	renderer_render_microui(r, ui_ctx)
	renderer_end(r)
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
	wgpu.BindGroupLayoutRelease(r.texture_bindgroup_layout)
	wgpu.BufferRelease(r.texture_quad_buffer)
	wgpu.RenderPipelineRelease(r.texture_pipeline)
	wgpu.PipelineLayoutRelease(r.texture_pipeline_layout)
	wgpu.ShaderModuleRelease(r.texture_shader)
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

	renderer_setup_texture_objects(r)
	renderer_setup_ui_objects(r)
}

@(private = "file")
renderer_begin :: proc(r: ^Renderer) {
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
	r.curr_surface_texture = surface_texture.texture

	// Create view for surface texture (with defaults)
	r.curr_surface_view = wgpu.TextureCreateView(surface_texture.texture, nil)
}

@(private = "file")
renderer_render_texture_view :: proc(
	r: ^Renderer,
	texture_view: wgpu.TextureView,
	texture_sampler: wgpu.Sampler,
) {
	// Create bindgroup
	// NOTE: We do this every frame because we expect to dyanmically resize our texture and don't want to bother
	//       trying to lazily evaluate it.
	bindgroup := wgpu.DeviceCreateBindGroup(
		r.device,
		&{
			layout = r.texture_bindgroup_layout,
			entryCount = 2,
			entries = raw_data(
				[]wgpu.BindGroupEntry {
					{binding = 0, textureView = texture_view},
					{binding = 1, sampler = texture_sampler},
				},
			),
		},
	)
	defer wgpu.BindGroupRelease(bindgroup)

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
				view = r.curr_surface_view,
				depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
				loadOp = .Clear,
				storeOp = .Store,
				clearValue = {1.0, 0.0, 0.0, 1.0},
			},
		},
	)

	wgpu.RenderPassEncoderSetPipeline(render_pass, r.texture_pipeline)
	wgpu.RenderPassEncoderSetVertexBuffer(
		render_pass,
		0,
		r.texture_quad_buffer,
		0,
		wgpu.BufferGetSize(r.texture_quad_buffer),
	)
	wgpu.RenderPassEncoderSetBindGroup(render_pass, 0, bindgroup)
	wgpu.RenderPassEncoderDraw(render_pass, 6, 2, 0, 0)

	wgpu.RenderPassEncoderEnd(render_pass)
	wgpu.RenderPassEncoderRelease(render_pass)

	// Encode + submit render pass
	command_buffer := wgpu.CommandEncoderFinish(encoder, nil)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(r.queue, {command_buffer})
}

@(private = "file")
renderer_end :: proc(r: ^Renderer) {
	wgpu.SurfacePresent(r.surface)

	wgpu.TextureViewRelease(r.curr_surface_view)
	wgpu.TextureRelease(r.curr_surface_texture)
}

@(private = "file")
renderer_render_microui :: proc(r: ^Renderer, ctx: ^microui.Context) {
	for variant in microui.next_command_iterator(ctx, nil) {
		switch cmd in variant {
		case ^microui.Command_Text: // TODO
		case ^microui.Command_Rect: // TODO
		case ^microui.Command_Icon: // TODO
		case ^microui.Command_Clip: // TODO
		case ^microui.Command_Jump:
			unreachable()
		}
	}
}

@(private = "file")
renderer_setup_texture_objects :: proc(r: ^Renderer) {
	r.texture_shader = wgpu.DeviceCreateShaderModule(
		r.device,
		&{
			nextInChain = &wgpu.ShaderSourceWGSL {
				sType = .ShaderSourceWGSL,
				code = #load("shader/shader.wgsl", string),
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
	r.texture_quad_buffer = wgpu.DeviceCreateBuffer(
		r.device,
		&{usage = wgpu.BufferUsageFlags{.CopyDst, .Vertex}, size = u64(data_size)},
	)
	wgpu.QueueWriteBuffer(r.queue, r.texture_quad_buffer, 0, rawptr(&data[0]), uint(data_size))

	// bindings
	r.texture_bindgroup_layout = wgpu.DeviceCreateBindGroupLayout(
		r.device,
		&{
			entryCount = 2,
			entries = raw_data(
				[]wgpu.BindGroupLayoutEntry {
					{
						binding = 0,
						visibility = {.Fragment},
						texture = {sampleType = .Float, viewDimension = ._2D},
					},
					{binding = 1, visibility = {.Fragment}, sampler = {type = .Filtering}},
				},
			),
		},
	)

	// pipeline
	r.texture_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		r.device,
		&{bindGroupLayoutCount = 1, bindGroupLayouts = &r.texture_bindgroup_layout},
	)
	r.texture_pipeline = wgpu.DeviceCreateRenderPipeline(
		r.device,
		&wgpu.RenderPipelineDescriptor {
			layout = r.texture_pipeline_layout,
			vertex = wgpu.VertexState {
				module = r.texture_shader,
				entryPoint = "vs_main",
				bufferCount = 1,
				buffers = &wgpu.VertexBufferLayout {
					stepMode = .Vertex,
					arrayStride = 4 * size_of(f32),
					attributeCount = 2,
					attributes = raw_data(
						[]wgpu.VertexAttribute {
							{format = .Float32x2, offset = 0, shaderLocation = 0},
							{format = .Float32x2, offset = 2 * size_of(f32), shaderLocation = 1},
						},
					),
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
				module = r.texture_shader,
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

@(private = "file")
renderer_setup_ui_objects :: proc(r: ^Renderer) {
	r.ui_shader = wgpu.DeviceCreateShaderModule(
		r.device,
		&{
			nextInChain = &wgpu.ShaderSourceWGSL {
				sType = .ShaderSourceWGSL,
				code = #load("shader/ui.wgsl", string),
			},
		},
	)

	// atlas texture
	r.ui_atlas_texture = wgpu.DeviceCreateTexture(
		r.device,
		&{
			usage = {.TextureBinding, .CopyDst},
			dimension = ._2D,
			size = {microui.DEFAULT_ATLAS_WIDTH, microui.DEFAULT_ATLAS_HEIGHT, 1},
			format = .R8Unorm,
			mipLevelCount = 1,
			sampleCount = 1,
		},
	)
	r.ui_atlas_texture_view = wgpu.TextureCreateView(r.ui_atlas_texture, nil)
	r.ui_sampler = wgpu.DeviceCreateSampler(
		r.device,
		&{
			addressModeU = .ClampToEdge,
			addressModeV = .ClampToEdge,
			addressModeW = .ClampToEdge,
			magFilter = .Nearest,
			minFilter = .Nearest,
			mipmapFilter = .Nearest,
			lodMinClamp = 0,
			lodMaxClamp = 32,
			compare = .Undefined,
			maxAnisotropy = 1,
		},
	)

	// buffers
	r.ui_transform_matrix = wgpu.DeviceCreateBuffer(
		r.device,
		&{
			label = "Constant buffer",
			usage = {.Uniform, .CopyDst},
			size = size_of(matrix[4, 4]f32),
		},
	)

	r.ui_vertex_buffer = wgpu.DeviceCreateBuffer(
		r.device,
		&{
			label = "Vertex Buffer",
			usage = {.Vertex, .CopyDst},
			size = 8 * UI_BUFFER_SIZE * size_of(f32),
		},
	)
	r.ui_tex_buffer = wgpu.DeviceCreateBuffer(
		r.device,
		&{
			label = "Texture Buffer",
			usage = {.Vertex, .CopyDst},
			size = 8 * UI_BUFFER_SIZE * size_of(f32),
		},
	)
	r.ui_color_buffer = wgpu.DeviceCreateBuffer(
		r.device,
		&{
			label = "Color Buffer",
			usage = {.Vertex, .CopyDst},
			size = 16 * UI_BUFFER_SIZE * size_of(u8),
		},
	)
	r.ui_index_buffer = wgpu.DeviceCreateBuffer(
		r.device,
		&{
			label = "Index Buffer",
			usage = {.Index, .CopyDst},
			size = 6 * UI_BUFFER_SIZE * size_of(u32),
		},
	)


	// bindgroup
	r.ui_bindgroup_layout = wgpu.DeviceCreateBindGroupLayout(
		r.device,
		&{
			entryCount = 3,
			entries = raw_data(
				[]wgpu.BindGroupLayoutEntry {
					{binding = 0, visibility = {.Fragment}, sampler = {type = .Filtering}},
					{
						binding = 1,
						visibility = {.Fragment},
						texture = {
							sampleType = .Float,
							viewDimension = ._2D,
							multisampled = false,
						},
					},
					{
						binding = 2,
						visibility = {.Vertex},
						buffer = {type = .Uniform, minBindingSize = size_of(matrix[4, 4]f32)},
					},
				},
			),
		},
	)
	r.ui_bindgroup = wgpu.DeviceCreateBindGroup(
		r.device,
		&{
			layout = r.ui_bindgroup_layout,
			entryCount = 3,
			entries = raw_data(
				[]wgpu.BindGroupEntry {
					{binding = 0, sampler = r.ui_sampler},
					{binding = 1, textureView = r.ui_atlas_texture_view},
					{binding = 2, buffer = r.ui_transform_matrix, size = size_of(matrix[4, 4]f32)},
				},
			),
		},
	)

	// pipeline
	r.ui_pipeline_layout = wgpu.DeviceCreatePipelineLayout(
		r.device,
		&{bindGroupLayoutCount = 1, bindGroupLayouts = &r.ui_bindgroup_layout},
	)
	r.ui_pipeline = wgpu.DeviceCreateRenderPipeline(
		r.device,
		&{
			layout = r.ui_pipeline_layout,
			vertex = {
				module = r.ui_shader,
				entryPoint = "vs_main",
				bufferCount = 3,
				buffers = raw_data(
					[]wgpu.VertexBufferLayout {
						{
							stepMode = .Vertex,
							arrayStride = 8,
							attributeCount = 1,
							attributes = &wgpu.VertexAttribute {
								format = .Float32x2,
								shaderLocation = 0,
							},
						},
						{
							stepMode = .Vertex,
							arrayStride = 8,
							attributeCount = 1,
							attributes = &wgpu.VertexAttribute {
								format = .Float32x2,
								shaderLocation = 1,
							},
						},
						{
							stepMode = .Vertex,
							arrayStride = 4,
							attributeCount = 1,
							attributes = &wgpu.VertexAttribute {
								format = .Uint32,
								shaderLocation = 2,
							},
						},
					},
				),
			},
			fragment = &{
				module = r.ui_shader,
				entryPoint = "fs_main",
				targetCount = 1,
				targets = &wgpu.ColorTargetState {
					format = .BGRA8Unorm,
					blend = &{
						alpha = {
							srcFactor = .SrcAlpha,
							dstFactor = .OneMinusSrcAlpha,
							operation = .Add,
						},
						color = {
							srcFactor = .SrcAlpha,
							dstFactor = .OneMinusSrcAlpha,
							operation = .Add,
						},
					},
					writeMask = wgpu.ColorWriteMaskFlags_All,
				},
			},
			primitive = {topology = .TriangleList, cullMode = .None},
			multisample = {count = 1, mask = 0xFFFFFFFF},
		},
	)

	// upload atlas texture + transform matrix
	wgpu.QueueWriteTexture(
		r.queue,
		&{texture = r.ui_atlas_texture},
		&microui.default_atlas_alpha,
		microui.DEFAULT_ATLAS_WIDTH * microui.DEFAULT_ATLAS_HEIGHT,
		&{bytesPerRow = microui.DEFAULT_ATLAS_WIDTH, rowsPerImage = microui.DEFAULT_ATLAS_HEIGHT},
		&{microui.DEFAULT_ATLAS_WIDTH, microui.DEFAULT_ATLAS_HEIGHT, 1},
	)
}
