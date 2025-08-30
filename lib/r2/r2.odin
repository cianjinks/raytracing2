package r2

import "base:runtime"

import "external:wgpu"

import "raytracing2:lib/r2/util"

R2 :: struct {
	image_width:     u32,
	image_height:    u32,
	_device:         wgpu.Device,
	_queue:          wgpu.Queue,
	_texture:        wgpu.Texture,
	texture_view:    wgpu.TextureView,
	texture_sampler: wgpu.Sampler,
}

// The R2 renderer takes a WebGPU Device and provides a TextureView and Sampler for use
init :: proc(image_width, image_height: u32, device: wgpu.Device) -> ^R2 {
	r := new(R2)
	r.image_width, r.image_height = image_width, image_height
	r._device = device
	r._queue = wgpu.DeviceGetQueue(r._device)
	recreate_texture(r)
	return r
}

render :: proc() {

}

cleanup :: proc(r: ^R2) {
	wgpu.SamplerRelease(r.texture_sampler)
	wgpu.TextureViewRelease(r.texture_view)
	wgpu.TextureRelease(r._texture)
	wgpu.QueueRelease(r._queue)
	free(r)
}

update_image :: proc(r: ^R2, image_width, image_height: u32) {
	if ((r.image_width != image_width) || (r.image_height != image_height)) {
		r.image_width = image_width
		r.image_height = image_height
		recreate_texture(r)
	}
}

@(private = "file")
recreate_texture :: proc(r: ^R2) {
	// free existing texture
	if (r.texture_sampler != nil) {
		wgpu.SamplerRelease(r.texture_sampler)
		r.texture_sampler = nil
	}
	if (r.texture_view != nil) {
		wgpu.TextureViewRelease(r.texture_view)
		r.texture_view = nil
	}
	if (r._texture != nil) {
		wgpu.TextureRelease(r._texture)
		r._texture = nil
	}

	// create new one
	r._texture = wgpu.DeviceCreateTexture(
		r._device,
		&{
			usage = {.TextureBinding, .CopyDst},
			dimension = ._2D,
			size = {width = r.image_width, height = r.image_height, depthOrArrayLayers = 1},
			format = .RGBA8Unorm,
			mipLevelCount = 1,
			sampleCount = 1,
		},
	)

	texture_data := make([]u8, r.image_width * r.image_height * 4)
	for x in 0 ..< r.image_width {
		for y in 0 ..< r.image_height {
			idx := ((y * r.image_width) + x) * 4
			seed := idx
			texture_data[idx] = u8(util.fast_random(&seed))
			texture_data[idx + 1] = u8(util.fast_random(&seed))
			texture_data[idx + 2] = u8(util.fast_random(&seed))
			texture_data[idx + 3] = 255
		}
	}
	wgpu.QueueWriteTexture(
		r._queue,
		destination = &{texture = r._texture, mipLevel = 0, origin = {0, 0, 0}, aspect = .All},
		data = rawptr(&texture_data[0]),
		dataSize = len(texture_data) * size_of(u8),
		dataLayout = &{offset = 0, bytesPerRow = 4 * r.image_width, rowsPerImage = r.image_height},
		writeSize = &{r.image_width, r.image_height, 1},
	)
	delete(texture_data)

	// create view and sampler for use
	r.texture_view = wgpu.TextureCreateView(
		r._texture,
		&{
			format = .RGBA8Unorm,
			dimension = ._2D,
			baseMipLevel = 0,
			mipLevelCount = 1,
			baseArrayLayer = 0,
			arrayLayerCount = 1,
			aspect = .All,
			usage = {.TextureBinding, .CopyDst},
		},
	)
	r.texture_sampler = wgpu.DeviceCreateSampler(
		r._device,
		&{
			addressModeU = .Repeat,
			addressModeV = .Repeat,
			addressModeW = .Repeat,
			magFilter = .Nearest,
			minFilter = .Nearest,
			mipmapFilter = .Nearest,
			lodMinClamp = 0.0,
			lodMaxClamp = 1.0,
			compare = .Undefined,
			maxAnisotropy = 1,
		},
	)
}
