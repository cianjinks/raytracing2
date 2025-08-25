package viewer

import "core:log"
import "core:mem"

Application :: struct {
	window:   ^Window,
	renderer: ^Renderer,
}

app_create :: proc(name: string, window_width: u32, window_height: u32) -> ^Application {
	// init logging
	context.logger = log.create_console_logger()

	// create application
	a := new(Application)
	a.window = window_create(name, window_width, window_height, app_on_event, rawptr(a))
	a.renderer = renderer_create(window_width, window_height, a.window.raw_window)

	return a
}

app_run :: proc(a: ^Application) {
	for !window_should_close(a.window) {
		window_on_update()
		renderer_on_update(a.renderer)
	}
}

app_on_event :: proc(event: Event, user_data: rawptr) {
	a := (^Application)(user_data)

	renderer_on_event(a.renderer, event)
}

app_destroy :: proc(a: ^Application) {
	renderer_destroy(a.renderer)
	window_destroy(a.window)
	free(a)
}
