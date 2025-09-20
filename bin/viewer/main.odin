package viewer

main :: proc() {
	a := app_create("raytracing2", 1600, 900, 640, 360)
	app_run(a)
	app_destroy(a)
}
