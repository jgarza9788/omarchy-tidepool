import QtQuick

// A ShaderEffect fed with a spectrum. Qt can't pass an array to a shader, so
// the bands (0..100) travel packed four to a vec4, up to 64 of them; the
// fragment shaders read them back with band(i). Set `fragmentShader` to a
// compiled .qsb from shaders/ and add that shader's own uniforms as properties.
ShaderEffect {
  id: fx

  property var values: []
  property color accent: "white"

  function pack(k) {
    var v = values
    var i = k * 4
    return Qt.vector4d(v.length > i ? v[i] : 0, v.length > i + 1 ? v[i + 1] : 0, v.length > i + 2 ? v[i + 2] : 0, v.length > i + 3 ? v[i + 3] : 0)
  }

  property vector4d b0: pack(0)
  property vector4d b1: pack(1)
  property vector4d b2: pack(2)
  property vector4d b3: pack(3)
  property vector4d b4: pack(4)
  property vector4d b5: pack(5)
  property vector4d b6: pack(6)
  property vector4d b7: pack(7)
  property vector4d b8: pack(8)
  property vector4d b9: pack(9)
  property vector4d b10: pack(10)
  property vector4d b11: pack(11)
  property vector4d b12: pack(12)
  property vector4d b13: pack(13)
  property vector4d b14: pack(14)
  property vector4d b15: pack(15)

  property vector2d area: Qt.vector2d(width, height)
}
