package application

import "core:log"
import "core:mem"

import "raytracing2:bin/viewer/renderer"
import "raytracing2:bin/viewer/window"

Application :: struct {
	window:   ^window.Window,
	renderer: ^renderer.Renderer,
}

create :: proc(name: string, window_width: u32, window_height: u32) -> ^Application {
	// init logging
	context.logger = log.create_console_logger()

	// create application
	a := new(Application)
	a.window = window.create(name, window_width, window_height, on_event, rawptr(a))
	a.renderer = renderer.create(window_width, window_height, a.window.raw_window)

	return a
}

run :: proc(a: ^Application) {
	for !window.should_close(a.window) {
		window.on_update()
		renderer.on_update(a.renderer)
	}
}

on_event :: proc(event: window.Event, user_data: rawptr) {
	a := (^Application)(user_data)

	renderer.on_event(a.renderer, event)
}

destroy :: proc(a: ^Application) {
	renderer.destroy(a.renderer)
	window.destroy(a.window)
	free(a)
}
