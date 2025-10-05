package viewer

import "core:fmt"
import "core:log"
import "core:mem"

import "external:microui"
import "external:tracy"

import "raytracing2:lib/r2"

Application :: struct {
	window:       ^Window,
	renderer:     ^Renderer,
	ui:           ^UI,
	r2_state:     ^r2.State,
	r2_rctx:      ^r2.RenderContext,
	image_width:  u32,
	image_height: u32,
}

app_create :: proc(
	name: string,
	window_width, window_height: u32,
	image_width, image_height: u32,
) -> ^Application {
	// init logging
	context.logger = log.create_console_logger()

	// init tracing
	tracy.SetThreadName("main")

	// create application
	a := new(Application)
	a.image_width = image_width
	a.image_height = image_height
	a.window = window_create(name, window_width, window_height, app_on_event, rawptr(a))
	a.renderer = renderer_create(
		window_width,
		window_height,
		window_get_dpi(a.window),
		a.image_width,
		a.image_height,
		a.window.raw_window,
	)
	a.ui = ui_create()
	a.r2_state = r2.init(
		image_width = a.image_width,
		image_height = a.image_height,
		device = a.renderer.device,
	)
	a.r2_rctx = r2.create_render_context(a.r2_state)

	return a
}

app_run :: proc(a: ^Application) {
	for !window_should_close(a.window) {
		defer tracy.FrameMark()

		window_on_update()

		ui_begin(a.ui)
		app_ui(a)
		ui_end(a.ui)

		texture_view, texture_sampler := r2.render_next_sample(a.r2_state, a.r2_rctx)

		renderer_render(a.renderer, texture_view, texture_sampler, &a.ui.ctx)
	}
}

app_on_event :: proc(event: Event, user_data: rawptr) {
	a := (^Application)(user_data)

	ui_on_event(a.ui, event)
	renderer_on_event(a.renderer, event)
}

app_destroy :: proc(a: ^Application) {
	r2.destroy_render_context(a.r2_rctx)
	r2.cleanup(a.r2_state)
	ui_destroy(a.ui)
	renderer_destroy(a.renderer)
	window_destroy(a.window)
	free(a)
}

app_ui :: proc(a: ^Application) {
	ctx := &a.ui.ctx
	if microui.window(ctx, "raytracing2", {40, 40, 300, 450}) {
		if .ACTIVE in microui.header(ctx, "Image Settings", opt = {microui.Opt.EXPANDED}) {
			// Image Width
			fwidth := f32(a.image_width)
			microui.layout_row(ctx, {84, -1}, 0)
			microui.label(ctx, "Image Width:")
			microui.slider(ctx, &fwidth, 128, 1920, step = 1.0)
			a.image_width = u32(fwidth)

			// Image Height
			fheight := f32(a.image_height)
			microui.layout_row(ctx, {90, -1}, 0)
			microui.label(ctx, "Image Height:")
			microui.slider(ctx, &fheight, 128, 1920, step = 1.0)
			a.image_height = u32(fheight)

			// Update Image
			renderer_update_image(a.renderer, a.image_width, a.image_height)
			if r2.update_image(a.r2_state, a.image_width, a.image_height) {
				r2.reset_render_context(a.r2_state, a.r2_rctx)
			}
		}
	}
}
