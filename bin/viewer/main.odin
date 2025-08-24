package main

import "raytracing2:bin/viewer/application"

main :: proc() {
	a := application.create("raytracing2", 1600, 900)
	application.run(a)
	application.destroy(a)
}
