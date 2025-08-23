package main

import "base:runtime"

import "core:fmt"

import "external:glfw"
import "external:wgpu"
import "external:wgpu/glfwglue"

import "raytracing2:lib/core"

glfw_error_callback :: proc "c" (error: i32, description: cstring) {
	context = runtime.default_context()
	fmt.printfln("[GLFW Error] %d: %s", error, description)
}

wgpu_log_callback :: proc "c" (level: wgpu.LogLevel, message: wgpu.StringView, userdata: rawptr) {
	context = runtime.default_context()
	fmt.printfln("[WGPU Log] %s", message)
}

main :: proc() {
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
	defer glfw.DestroyWindow(window)

	// Minimal WebGPU initialization
	instance := wgpu.CreateInstance(nil)
	surface := glfwglue.GetSurface(instance, window)

	// Loop
	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()
	}
}
