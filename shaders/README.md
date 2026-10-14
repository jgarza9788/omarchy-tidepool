# Shaders

`dots.frag` and `fire.frag` draw the `dots` and `fire` visualizer styles in one
GPU pass each (see `components/Visualizer.qml` and `components/SpectrumShader.qml`).
They port `Model.dotGrid` / `Model.cellGrid` / `Model.noise` / `Model.fireState` /
`Model.fireHsl` to GLSL, so if you change the look in `Model.js` change it here
too. The Model.js versions still draw the fallback used when a shader can't load.

After editing a `.frag`, run `./build.sh` and commit the `.qsb` files: users get
the compiled bundles and don't need Qt's `qsb`.

The spectrum reaches the shader as 16 `vec4` properties (`b0`..`b15`, up to 64
bands, values 0..100) because Qt can't pass arrays to a ShaderEffect.
