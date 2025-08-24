package window

import "core:c"

Event :: struct {
	type:             EventType,
	// type = WindowResize
	width, height:    u32,
	// type = KeyPress, KeyRelease, KeyRepeat
	key:              c.int,
	// type = MousePress, MouseRelease
	button:           c.int,
	// type = MousePosition
	xpos, ypos:       f64,
	// type = MouseScroll
	xoffset, yoffset: f64,
}

EventType :: enum {
	None,
	KeyPress,
	KeyRelease,
	KeyRepeat,
	MousePress,
	MouseRelease,
	MousePosition,
	MouseScroll,
	WindowResize,
}
