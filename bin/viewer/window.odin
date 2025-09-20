package viewer

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

window_create :: proc(
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
	glfw.SetCharCallback(w.raw_window, char_callback)
	glfw.SetWindowContentScaleCallback(w.raw_window, content_scale_callback)

	return w
}

window_should_close :: proc(w: ^Window) -> b32 {
	return glfw.WindowShouldClose(w.raw_window)
}

window_on_update :: proc() {
	glfw.PollEvents()
}

window_destroy :: proc(w: ^Window) {
	glfw.DestroyWindow(w.raw_window)
	free(w.user_pointer)
	free(w)
	glfw.Terminate()
}

window_get_dpi :: proc(w: ^Window) -> f32 {
	xs, ys := glfw.GetWindowContentScale(w.raw_window)
	if xs != ys {
		log.warnf("[GLFW Warn] content scale is different in X and Y: %f, %f", xs, ys)
	}
	return xs
}

@(private = "file")
error_callback :: proc "c" (error: c.int, description: cstring) {
	context = runtime.default_context()
	log.infof("[GLFW Error] %d - %s", error, description)
}

@(private = "file")
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

@(private = "file")
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

	// TODO: Add more as needed
	event_key := EventKey.None
	switch key {
	// TODO: Can we merge these cases?
	case glfw.KEY_LEFT_SHIFT:
		event_key = .SHIFT
	case glfw.KEY_RIGHT_SHIFT:
		event_key = .SHIFT
	case glfw.KEY_LEFT_CONTROL:
		event_key = .CTRL
	case glfw.KEY_RIGHT_CONTROL:
		event_key = .CTRL
	case glfw.KEY_LEFT_ALT:
		event_key = .ALT
	case glfw.KEY_RIGHT_ALT:
		event_key = .ALT
	case glfw.KEY_ESCAPE:
		event_key = .ESCAPE
	case glfw.KEY_BACKSPACE:
		event_key = .BACKSPACE
	case glfw.KEY_DELETE:
		event_key = .DELETE
	case glfw.KEY_ENTER:
		event_key = .RETURN
	case glfw.KEY_LEFT:
		event_key = .LEFT
	case glfw.KEY_RIGHT:
		event_key = .RIGHT
	case glfw.KEY_HOME:
		event_key = .HOME
	case glfw.KEY_END:
		event_key = .END
	case glfw.KEY_A:
		event_key = .A
	case glfw.KEY_C:
		event_key = .C
	case glfw.KEY_D:
		event_key = .D
	case glfw.KEY_W:
		event_key = .W
	case glfw.KEY_S:
		event_key = .S
	case glfw.KEY_V:
		event_key = .V
	case glfw.KEY_X:
		event_key = .X
	case:
		log.warnf("[GLFW Warn] unsupported key press: %d", key)
	}

	event := Event {
		type = type,
		key  = event_key,
	}
	user_data.callback(event, user_data.callback_user_data)
}

@(private = "file")
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

	event_mouse_button := EventMouseButton.None
	switch button {
	case glfw.MOUSE_BUTTON_LEFT:
		event_mouse_button = .Left
	case glfw.MOUSE_BUTTON_RIGHT:
		event_mouse_button = .Right
	case glfw.MOUSE_BUTTON_MIDDLE:
		event_mouse_button = .Middle
	case:
		log.warnf("[GLFW Warn] unsupported mouse button press: %d", button)
	}

	event := Event {
		type   = type,
		button = event_mouse_button,
	}
	user_data.callback(event, user_data.callback_user_data)
}

@(private = "file")
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

@(private = "file")
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

@(private = "file")
char_callback :: proc "c" (window: glfw.WindowHandle, codepoint: rune) {
	user_data := (^WindowUserPointer)(glfw.GetWindowUserPointer(window))
	context = user_data.ctx

	event := Event {
		type      = .TextInput,
		codepoint = codepoint,
	}
	user_data.callback(event, user_data.callback_user_data)
}

@(private = "file")
content_scale_callback :: proc "c" (window: glfw.WindowHandle, xscale, yscale: f32) {
	user_data := (^WindowUserPointer)(glfw.GetWindowUserPointer(window))
	context = user_data.ctx

	if xscale != yscale {
		log.warnf("[GLFW Warn] content scale is different in X and Y: %f, %f", xscale, yscale)
	}

	event := Event {
		type = .WindowDpi,
		dpi  = xscale,
	}
	user_data.callback(event, user_data.callback_user_data)
}
