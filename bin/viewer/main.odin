package viewer

main :: proc() {
	a := app_create("raytracing2", 1600, 900)
	app_run(a)
	app_destroy(a)
}
