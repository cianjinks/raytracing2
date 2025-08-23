package main

import "base:runtime"

import "core:c"
import "core:fmt"

import "external:glfw"
import "external:wgpu"
import "external:wgpu/glfwglue"

import "raytracing2:lib/core"

state: struct {
	ctx:      runtime.Context,
	window:   glfw.WindowHandle,
	instance: wgpu.Instance,
	surface:  wgpu.Surface,
	adapter:  wgpu.Adapter,
	device:   wgpu.Device,
	config:   wgpu.SurfaceConfiguration,
	queue:    wgpu.Queue,
}

glfw_error_callback :: proc "c" (error: c.int, description: cstring) {
	context = state.ctx
	fmt.printfln("[GLFW Error] %d: %s", error, description)
}

wgpu_log_callback :: proc "c" (level: wgpu.LogLevel, message: string, userdata: rawptr) {
	context = state.ctx
	fmt.printfln("[WGPU Log] %s", message)
}

wgpu_request_adapter_callback :: proc "c" (
	status: wgpu.RequestAdapterStatus,
	adapter: wgpu.Adapter,
	message: string,
	userdata1: rawptr,
	userdata2: rawptr,
) {
	context = state.ctx
	if status != wgpu.RequestAdapterStatus.Success || adapter == nil {
		fmt.panicf("[WGPU Error] %v - %s", status, message)
	}
	state.adapter = adapter

	// Once we have an adapter, request a device
	wgpu.AdapterRequestDevice(adapter, nil, {callback = wgpu_request_device_callback})
}

wgpu_request_device_callback :: proc "c" (
	status: wgpu.RequestDeviceStatus,
	device: wgpu.Device,
	message: string,
	userdata1: rawptr,
	userdata2: rawptr,
) {
	context = state.ctx
	if status != wgpu.RequestDeviceStatus.Success || device == nil {
		fmt.panicf("[WGPU Error] %v - %s", status, message)
	}
	state.device = device

	// Once we have a device setup the surface, queue and pipeline
	width, height := glfw.GetFramebufferSize(state.window)
	state.config = wgpu.SurfaceConfiguration {
		device      = state.device,
		usage       = {.RenderAttachment},
		format      = .BGRA8Unorm,
		width       = u32(width),
		height      = u32(height),
		presentMode = .Fifo,
		alphaMode   = .Opaque,
	}
	wgpu.SurfaceConfigure(state.surface, &state.config)

	state.queue = wgpu.DeviceGetQueue(state.device)

	// Enter main loop
	for !glfw.WindowShouldClose(state.window) {
		glfw.PollEvents()
		render()
	}
}

glfw_resize_callback :: proc "c" (window: glfw.WindowHandle, width, height: c.int) {
	state.config.width, state.config.height = u32(width), u32(height)
	wgpu.SurfaceConfigure(state.surface, &state.config)
}

main :: proc() {
	state.ctx = context

	glfw.SetErrorCallback(glfw_error_callback)
	wgpu.SetLogCallback(wgpu_log_callback, nil)

	// GLFW initialization
	if !glfw.Init() {
		panic("Failed to initialize GLFW")
	}
	defer glfw.Terminate()

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API) // needed to use webgpu with glfw

	window := glfw.CreateWindow(1280, 720, "raytracing2 viewer", nil, nil)
	if window == nil {
		panic("Failed to create GLFW window")
	}
	state.window = window

	glfw.SetFramebufferSizeCallback(state.window, glfw_resize_callback)

	// WebGPU initialization
	instance := wgpu.CreateInstance(nil)
	if instance == nil {
		panic("Failed to create WebGPU instance")
	}
	state.instance = instance

	surface := glfwglue.GetSurface(instance, window)
	if surface == nil {
		panic("Failed to create WebGPU surface")
	}
	state.surface = surface

	wgpu.InstanceRequestAdapter(
		instance,
		&{compatibleSurface = surface},
		// this begins a chain of callbacks to setup wgpu and start the render loop
		{callback = wgpu_request_adapter_callback},
	)
}

render :: proc() {
	// Get surface texture
	surface_texture := wgpu.SurfaceGetCurrentTexture(state.surface)
	switch surface_texture.status {
	case .SuccessOptimal, .SuccessSuboptimal:
	// good
	case .Timeout, .Outdated, .Lost:
	// TODO
	case .OutOfMemory, .DeviceLost, .Error:
		fmt.panicf("[WGPU Error] Failed to get surface texture: %v", surface_texture.status)
	}
	defer wgpu.TextureRelease(surface_texture.texture)

	// Create view for surface texture (with defaults)
	view := wgpu.TextureCreateView(surface_texture.texture, nil)
	defer wgpu.TextureViewRelease(view)

	// Create command encoder (with defaults)
	encoder := wgpu.DeviceCreateCommandEncoder(state.device, nil)
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
	wgpu.RenderPassEncoderEnd(render_pass)
	wgpu.RenderPassEncoderRelease(render_pass)

	// Encode + submit render pass
	command_buffer := wgpu.CommandEncoderFinish(encoder, nil)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(state.queue, {command_buffer})
	wgpu.SurfacePresent(state.surface)
}

cleanup :: proc() {
	wgpu.SurfaceUnconfigure(state.surface)
	wgpu.QueueRelease(state.queue)
	wgpu.DeviceRelease(state.device)
	wgpu.AdapterRelease(state.adapter)
	wgpu.SurfaceRelease(state.surface)
	wgpu.InstanceRelease(state.instance)
	glfw.DestroyWindow(state.window)
}
