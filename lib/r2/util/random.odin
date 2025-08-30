package util

fast_random :: proc(seed: ^u32) -> u32 {
	state := seed^
	seed^ = state * 747796405 + 2891336453
	word := ((state >> ((state >> 28) + 4)) ~ state) * 277803737
	return (word >> 22) ~ word
}
