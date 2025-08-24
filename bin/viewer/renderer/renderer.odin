package renderer

import "base:runtime"

import "core:log"

import "external:glfw"
import "external:wgpu"
import "external:wgpu/glfwglue"

import "raytracing2:bin/viewer/window"

Renderer :: struct {
	ctx:             runtime.Context,
	window_width:    u32,
	window_height:   u32,
	instance:        wgpu.Instance,
	surface:         wgpu.Surface,
	adapter:         wgpu.Adapter,
	device:          wgpu.Device,
	config:          wgpu.SurfaceConfiguration,
	queue:           wgpu.Queue,
	module:          wgpu.ShaderModule,
	pipeline_layout: wgpu.PipelineLayout,
	pipeline:        wgpu.RenderPipeline,
}

// TODO: We should possibly just take a surface here so that the renderer
//       does not rely on GLFW directly?
create :: proc(window_width, window_height: u32, raw_window: glfw.WindowHandle) -> ^Renderer {
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

on_update :: proc(r: ^Renderer) {
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
	wgpu.RenderPassEncoderDraw(render_pass, 3, 1, 0, 0)

	wgpu.RenderPassEncoderEnd(render_pass)
	wgpu.RenderPassEncoderRelease(render_pass)

	// Encode + submit render pass
	command_buffer := wgpu.CommandEncoderFinish(encoder, nil)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(r.queue, {command_buffer})
	wgpu.SurfacePresent(r.surface)
}

on_event :: proc(r: ^Renderer, event: window.Event) {
	#partial switch event.type {
	case .WindowResize:
		r.config.width, r.config.height = event.width, event.height
		wgpu.SurfaceConfigure(r.surface, &r.config)
	case:
	// Ignore
	}
}

destroy :: proc(r: ^Renderer) {
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

@(private)
log_callback :: proc "c" (level: wgpu.LogLevel, message: wgpu.StringView, userdata: rawptr) {
	context = runtime.default_context()
	log.infof("[WGPU Log] %v - %s", level, message)
}

@(private)
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

@(private)
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

	r.pipeline_layout = wgpu.DeviceCreatePipelineLayout(r.device, &{})
	r.pipeline = wgpu.DeviceCreateRenderPipeline(
		r.device,
		&wgpu.RenderPipelineDescriptor {
			layout = r.pipeline_layout,
			vertex = wgpu.VertexState {
				module = r.module,
				entryPoint = "vs_main",
				bufferCount = 0,
				buffers = nil,
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
