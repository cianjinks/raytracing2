package window

import "base:runtime"

import "core:c"
import "core:log"
import "core:strings"

import "external:glfw"

Window :: struct {
	name:         string,
	width:        u32,
	height:       u32,
	raw_window:   glfw.WindowHandle,
	user_pointer: ^WindowUserPointer,
}

WindowEventCallback :: #type proc(event: Event, user_data: rawptr)

WindowUserPointer :: struct {
	ctx:                runtime.Context,
	callback:           WindowEventCallback,
	callback_user_data: rawptr,
}

create :: proc(
	name: string,
	width: u32,
	height: u32,
	event_callback: WindowEventCallback,
	event_callback_user_data: rawptr,
) -> ^Window {
	w := new(Window)

	glfw.SetErrorCallback(error_callback)

	// init
	if !glfw.Init() {
		log.panic("Failed to create GLFW window")
	}

	// window
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API) // needed to use webgpu with glfw
	raw_window := glfw.CreateWindow(
		c.int(width),
		c.int(height),
		strings.clone_to_cstring(name),
		nil,
		nil,
	)
	if raw_window == nil {
		log.panic("Failed to create GLFW window")
	}
	w.raw_window = raw_window

	// callbacks
	w.user_pointer = new(WindowUserPointer)
	w.user_pointer.ctx = context
	w.user_pointer.callback = event_callback
	w.user_pointer.callback_user_data = event_callback_user_data

	glfw.SetWindowUserPointer(w.raw_window, rawptr(w.user_pointer))
	glfw.SetFramebufferSizeCallback(w.raw_window, framebuffer_size_callback)
	glfw.SetKeyCallback(w.raw_window, key_callback)
	glfw.SetMouseButtonCallback(w.raw_window, mouse_button_callback)
	glfw.SetCursorPosCallback(w.raw_window, cursor_pos_callback)
	glfw.SetScrollCallback(w.raw_window, scroll_callback)

	return w
}

should_close :: proc(w: ^Window) -> b32 {
	return glfw.WindowShouldClose(w.raw_window)
}

on_update :: proc() {
	glfw.PollEvents()
}

destroy :: proc(w: ^Window) {
	glfw.DestroyWindow(w.raw_window)
	free(w.user_pointer)
	free(w)
	glfw.Terminate()
}

@(private)
error_callback :: proc "c" (error: c.int, description: cstring) {
	context = runtime.default_context()
	log.infof("[GLFW Error] %d - %s", error, description)
}

@(private)
framebuffer_size_callback :: proc "c" (window: glfw.WindowHandle, width, height: c.int) {
	user_data := (^WindowUserPointer)(glfw.GetWindowUserPointer(window))
	context = user_data.ctx

	event := Event {
		type   = .WindowResize,
		width  = u32(width),
		height = u32(height),
	}
	user_data.callback(event, user_data.callback_user_data)
}

@(private)
key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: c.int) {
	user_data := (^WindowUserPointer)(glfw.GetWindowUserPointer(window))
	context = user_data.ctx

	type := EventType.None
	switch action {
	case glfw.PRESS:
		type = .KeyPress
	case glfw.RELEASE:
		type = .KeyRelease
	case glfw.REPEAT:
		type = .KeyRepeat
	}

	event := Event {
		type = type,
		key  = key,
	}
	user_data.callback(event, user_data.callback_user_data)
}

@(private)
mouse_button_callback :: proc "c" (window: glfw.WindowHandle, button, action, mods: c.int) {
	user_data := (^WindowUserPointer)(glfw.GetWindowUserPointer(window))
	context = user_data.ctx

	type := EventType.None
	switch action {
	case glfw.PRESS:
		type = .MousePress
	case glfw.RELEASE:
		type = .MouseRelease
	}

	event := Event {
		type   = type,
		button = button,
	}
	user_data.callback(event, user_data.callback_user_data)
}

@(private)
cursor_pos_callback :: proc "c" (window: glfw.WindowHandle, xpos, ypos: f64) {
	user_data := (^WindowUserPointer)(glfw.GetWindowUserPointer(window))
	context = user_data.ctx

	event := Event {
		type = .MousePosition,
		xpos = xpos,
		ypos = ypos,
	}
	user_data.callback(event, user_data.callback_user_data)
}

@(private)
scroll_callback :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
	user_data := (^WindowUserPointer)(glfw.GetWindowUserPointer(window))
	context = user_data.ctx

	event := Event {
		type    = .MouseScroll,
		xoffset = xoffset,
		yoffset = yoffset,
	}
	user_data.callback(event, user_data.callback_user_data)
}
