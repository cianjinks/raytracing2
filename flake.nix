{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      flake-utils,
      nixpkgs,
      ...
    }@inputs:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages."${system}";
      in
      {
        devShell = pkgs.mkShell {
          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [
            # Even when statically compiled, GLFW tries to load various shared libraries:
            #  - libwayland-client.so.0: https://github.com/glfw/glfw/blob/63a7e8b7f82497b0459acba5c1ce7f39aa2bc0e8/src/wl_init.c#L521
            #  - libxkbcommon.so.0: https://github.com/glfw/glfw/blob/63a7e8b7f82497b0459acba5c1ce7f39aa2bc0e8/src/wl_init.c#L666
            pkgs.wayland
            pkgs.libxkbcommon
            # Provide WebGPU with OpenGL backend
            # pkgs.libGL
            # Provide WebGPU with Vulkan backend
            pkgs.vulkan-headers
            pkgs.vulkan-loader
            pkgs.vulkan-tools
            pkgs.vulkan-tools-lunarg
            pkgs.vulkan-extension-layer
            pkgs.vulkan-validation-layers
          ];
          packages = [
            # Odin
            pkgs.odin
            # Debugger
            pkgs.lldb
          ];
        };
      }
    );
}
