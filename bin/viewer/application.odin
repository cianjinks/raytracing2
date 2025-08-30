package viewer

import "core:log"
import "core:mem"

import "raytracing2:lib/r2"

Application :: struct {
	window:   ^Window,
	renderer: ^Renderer,
	r2:       ^r2.R2,
}

app_create :: proc(name: string, window_width: u32, window_height: u32) -> ^Application {
	// init logging
	context.logger = log.create_console_logger()

	// create application
	a := new(Application)
	a.window = window_create(name, window_width, window_height, app_on_event, rawptr(a))
	a.renderer = renderer_create(window_width, window_height, a.window.raw_window)
	a.r2 = r2.init(
		image_width = window_width,
		image_height = window_height,
		device = a.renderer.device,
	)

	return a
}

app_run :: proc(a: ^Application) {
	for !window_should_close(a.window) {
		window_on_update()
		renderer_on_update(a.renderer, a.r2.texture_view, a.r2.texture_sampler)
	}
}

app_on_event :: proc(event: Event, user_data: rawptr) {
	a := (^Application)(user_data)

	renderer_on_event(a.renderer, event)
}

app_destroy :: proc(a: ^Application) {
	r2.cleanup(a.r2)
	renderer_destroy(a.renderer)
	window_destroy(a.window)
	free(a)
}
