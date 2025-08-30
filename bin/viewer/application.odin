package viewer

import "core:fmt"
import "core:log"
import "core:mem"

import "external:microui"

import "raytracing2:lib/r2"

Application :: struct {
	window:   ^Window,
	renderer: ^Renderer,
	ui:       ^UI,
	r2:       ^r2.R2,
}

app_create :: proc(name: string, window_width: u32, window_height: u32) -> ^Application {
	// init logging
	context.logger = log.create_console_logger()

	// create application
	a := new(Application)
	a.window = window_create(name, window_width, window_height, app_on_event, rawptr(a))
	a.renderer = renderer_create(window_width, window_height, a.window.raw_window)
	a.ui = ui_create()
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
		ui_begin(a.ui)
		app_ui(a)
		ui_end(a.ui)
		renderer_on_update(a.renderer, a.r2.texture_view, a.r2.texture_sampler)
	}
}

app_on_event :: proc(event: Event, user_data: rawptr) {
	a := (^Application)(user_data)

	ui_on_event(a.ui, event)
	renderer_on_event(a.renderer, event)
}

app_destroy :: proc(a: ^Application) {
	r2.cleanup(a.r2)
	ui_destroy(a.ui)
	renderer_destroy(a.renderer)
	window_destroy(a.window)
	free(a)
}

app_ui :: proc(a: ^Application) {
	ctx := &a.ui.ctx
	if microui.window(ctx, "Test Window", {40, 40, 300, 450}) {
		if .ACTIVE in microui.header(ctx, "Test Header") {
			win := microui.get_current_container(ctx)
			microui.layout_row(ctx, {54, -1}, 0)
			microui.label(ctx, "Position:")
			microui.label(ctx, fmt.tprintf("%d, %d", win.rect.x, win.rect.y))
			microui.label(ctx, "Size:")
			microui.label(ctx, fmt.tprintf("%d, %d", win.rect.w, win.rect.h))
		}
	}
}
