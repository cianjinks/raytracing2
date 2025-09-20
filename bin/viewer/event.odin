package viewer

import "core:c"

Event :: struct {
	type:             EventType,
	// type = WindowResize
	width, height:    u32,
	// type = KeyPress, KeyRelease, KeyRepeat
	key:              EventKey,
	// type = MousePress, MouseRelease
	button:           EventMouseButton,
	// type = MousePosition
	xpos, ypos:       f64,
	// type = MouseScroll
	xoffset, yoffset: f64,
	// type = TextInput
	codepoint:        rune,
	// type = WindowDpi
	dpi:              f32,
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
	TextInput,
	WindowResize,
	WindowDpi,
}

EventKey :: enum {
	None,
	//
	SHIFT,
	CTRL,
	ALT,
	ESCAPE,
	BACKSPACE,
	DELETE,
	RETURN,
	LEFT,
	RIGHT,
	HOME,
	END,
	//
	A,
	C,
	D,
	W,
	S,
	V,
	X,
}

EventMouseButton :: enum {
	None,
	Left,
	Right,
	Middle,
}
