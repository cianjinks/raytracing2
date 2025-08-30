package viewer

import "core:unicode/utf8"

import "external:microui"

UI :: struct {
	ctx:                          microui.Context,
	_last_mouse_x, _last_mouse_y: i32,
}

ui_create :: proc() -> ^UI {
	ui := new(UI)
	microui.init(&ui.ctx)
	ui.ctx.text_width = microui.default_atlas_text_width
	ui.ctx.text_height = microui.default_atlas_text_height
	return ui
}

ui_begin :: proc(ui: ^UI) {
	microui.begin(&ui.ctx)
}

ui_end :: proc(ui: ^UI) {
	microui.end(&ui.ctx)
}

ui_on_event :: proc(ui: ^UI, event: Event) {
	#partial switch event.type {
	case .KeyPress:
		key, ok := convert_event_key_to_ui_key(event.key)
		if ok {
			microui.input_key_down(&ui.ctx, key)
		}
	case .KeyRelease:
		key, ok := convert_event_key_to_ui_key(event.key)
		if ok {
			microui.input_key_up(&ui.ctx, key)
		}
	case .MousePress:
		mb, ok := convert_event_mb_to_ui_mb(event.button)
		if ok {
			microui.input_mouse_down(&ui.ctx, ui._last_mouse_x, ui._last_mouse_y, mb)
		}
	case .MouseRelease:
		mb, ok := convert_event_mb_to_ui_mb(event.button)
		if ok {
			microui.input_mouse_up(&ui.ctx, ui._last_mouse_x, ui._last_mouse_y, mb)
		}
	case .MousePosition:
		ui._last_mouse_x = i32(event.xpos)
		ui._last_mouse_y = i32(event.ypos)
		microui.input_mouse_move(&ui.ctx, ui._last_mouse_x, ui._last_mouse_y)
	case .MouseScroll:
		microui.input_scroll(&ui.ctx, ui._last_mouse_x, ui._last_mouse_y)
	case .TextInput:
		bytes, size := utf8.encode_rune(event.codepoint)
		microui.input_text(&ui.ctx, string(bytes[:size]))
	}
}

ui_destroy :: proc(ui: ^UI) {
	free(ui)
}

@(private = "file")
convert_event_key_to_ui_key :: proc(key: EventKey) -> (microui.Key, bool) {
	switch key {
	case .SHIFT:
		return .SHIFT, true
	case .CTRL:
		return .CTRL, true
	case .ALT:
		return .ALT, true
	case .BACKSPACE:
		return .BACKSPACE, true
	case .DELETE:
		return .DELETE, true
	case .RETURN:
		return .RETURN, true
	case .LEFT:
		return .LEFT, true
	case .RIGHT:
		return .RIGHT, true
	case .HOME:
		return .HOME, true
	case .END:
		return .END, true
	case .A:
		return .A, true
	case .C:
		return .C, true
	case .V:
		return .V, true
	case .X:
		return .X, true
	// not supported by microui
	case .D:
		fallthrough
	case .W:
		fallthrough
	case .S:
		fallthrough
	case .None:
		return nil, false
	}
	return nil, false
}

@(private = "file")
convert_event_mb_to_ui_mb :: proc(mb: EventMouseButton) -> (microui.Mouse, bool) {
	switch mb {
	case .Left:
		return .LEFT, true
	case .Right:
		return .RIGHT, true
	case .Middle:
		return .MIDDLE, true
	case .None:
		return nil, false
	}
	return nil, false
}
