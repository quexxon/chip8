'use strict'

const vertexShader = `#version 300 es

in vec4 a_position;
in vec2 a_texcoord;

out vec2 v_texcoord;

void main() {
  gl_Position = a_position;
  v_texcoord = a_texcoord;
}
`

const fragmentShader = `#version 300 es

precision highp float;

in vec2 v_texcoord;

uniform sampler2D u_texture;

out vec4 outColor;

void main() {
  outColor = texture(u_texture, v_texcoord);
}
`

let memory
const state = {
  frame: new Uint8Array(64 * 32 * 4)
}

function readByteArray (ptr, len) {
  return new Uint8Array(memory.buffer, ptr, len)
}

function readString (ptr, len) {
  return new TextDecoder().decode(readByteArray(ptr, len))
}

const frame = new Uint8Array(32 * 64 * 4)
for (let i = 3; i < frame.length; i += 4) {
  frame[i] = 0xFF
}

function createShader (gl, type, source) {
  const shader = gl.createShader(type)
  gl.shaderSource(shader, source)
  gl.compileShader(shader)
  if (gl.getShaderParameter(shader, gl.COMPILE_STATUS)) return shader

  console.error(gl.getShaderInfoLog(shader))
  gl.deleteShader(shader)
  throw new Error('Failed to create shader')
}

function createProgram (gl, vertexShader, fragmentShader) {
  const program = gl.createProgram()
  gl.attachShader(program, vertexShader)
  gl.attachShader(program, fragmentShader)
  gl.linkProgram(program)
  if (gl.getProgramParameter(program, gl.LINK_STATUS)) return program

  console.error(gl.getProgramInfoLog(program))
  gl.deleteProgram(program)
  throw new Error('Failed to create program')
}

async function main () {
  const canvas = document.querySelector('#canvas')
  const gl = canvas.getContext('webgl2')
  if (!gl) throw new Error('Failed to get WebGL2 context')

  const { instance: { exports: chip8 } } = await WebAssembly.instantiateStreaming(
    fetch('zig-out/chip8.wasm'),
    {
      env: {
        consoleLog (ptr, len) {
          console.log(readString(ptr, len))
        },
        logRam (ptr, len) {
          console.log(readByteArray(ptr, len))
        },
        logInt (int) { console.log(int) },
        readBytes (keyPtr, keyLen, bufferPtr, bufferLen) {
          const key = readString(keyPtr, keyLen)
          const bytes = state[key]

          if (bytes === undefined) {
            throw new Error('Unknown state key')
          }

          const buffer = new Uint8Array(memory.buffer, bufferPtr, bufferLen)
          const slice = bytes.slice(0, bufferLen)
          buffer.set(slice)
          return slice.length
        },
        writeBytes (keyPtr, keyLen, bufferPtr, bufferLen) {
          const key = readString(keyPtr, keyLen)
          const buffer = new Uint8Array(memory.buffer, bufferPtr, bufferLen)
          const buf = state[key]
          if (buf === undefined) {
            throw new Error('Unknown state key')
          }
          buf.set(buffer)
        },
        random () {
          return crypto.getRandomValues(new Uint8Array(1))[0]
        }
      }
    }
  )

  memory = chip8.memory

  const file = await fetch('vip_sum_fun.chip8').then(resp => resp.text())
  state.program = new TextEncoder().encode(file)

  chip8.init()
  performance.mark('loadProgram')
  const status = chip8.loadProgram()
  if (status !== 0) {
    console.log(status)
    throw new Error('Unable to load program')
  }
  performance.measure('loadProgram', 'loadProgram')
  chip8.getRam()
  console.log(performance.getEntriesByType('measure'))
  performance.clearMarks()
  performance.clearMeasures()

  chip8.getFrame()
  console.log(state.frame)

  window.onkeydown = e => { chip8.onKeyDown(e.keyCode) }
  window.onkeyup = e => { chip8.onKeyUp(e.keyCode) }

  const program = createProgram(
    gl,
    createShader(gl, gl.VERTEX_SHADER, vertexShader),
    createShader(gl, gl.FRAGMENT_SHADER, fragmentShader)
  )

  // look up where the vertex data needs to go.
  const positionAttributeLocation = gl.getAttribLocation(program, 'a_position')
  const texcoordAttributeLocation = gl.getAttribLocation(program, 'a_texcoord')

  const textureLocation = gl.getUniformLocation(program, 'u_texture')

  // Create a buffer and put three 2d clip space points in it
  const positionBuffer = gl.createBuffer()

  // Bind it to ARRAY_BUFFER (think of it as ARRAY_BUFFER = positionBuffer)
  gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer)

  const positions = [
    -1, -1,
    -1, 1,
    1, 1,
    -1, -1,
    1, 1,
    1, -1
  ]
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(positions), gl.STATIC_DRAW)

  // Create a vertex array object (attribute state)
  const vao = gl.createVertexArray()

  // and make it the one we're currently working with
  gl.bindVertexArray(vao)

  // Turn on the attribute
  gl.enableVertexAttribArray(positionAttributeLocation)

  // Tell the attribute how to get data out of positionBuffer (ARRAY_BUFFER)
  const size = 2 // 2 components per iteration
  const type = gl.FLOAT // the data is 32bit floats
  const normalize = false // don't normalize the data
  const stride = 0 // 0 = move forward size * sizeof(type) each iteration to get the next position
  const offset = 0 // start at the beginning of the buffer
  gl.vertexAttribPointer(positionAttributeLocation, size, type, normalize, stride, offset)

  const texcoordBuffer = gl.createBuffer()
  gl.bindBuffer(gl.ARRAY_BUFFER, texcoordBuffer)

  gl.bufferData(
    gl.ARRAY_BUFFER,
    new Float32Array([
      1, 1,
      1, 0,
      0, 0,
      1, 1,
      0, 0,
      0, 1
    ]),
    gl.STATIC_DRAW
  )

  gl.enableVertexAttribArray(texcoordAttributeLocation)

  {
    const size = 2 // 2 components per iteration
    const type = gl.FLOAT // the data is 32bit floating point values
    const normalize = true // convert from 0-255 to 0.0-1.0
    const stride = 0 // 0 = move forward size * sizeof(type) each iteration to get the next color
    const offset = 0 // start at the beginning of the buffer
    gl.vertexAttribPointer(texcoordAttributeLocation, size, type, normalize, stride, offset)
  }

  // Create a texture.
  const texture = gl.createTexture()

  // use texture unit 0
  gl.activeTexture(gl.TEXTURE0 + 0)

  // bind to the TEXTURE_2D bind point of texture unit 0
  gl.bindTexture(gl.TEXTURE_2D, texture)

  const activeImage = frame
  // fill texture with 3x2 pixels
  {
    const level = 0
    const internalFormat = gl.RGBA
    const width = 64
    const height = 32
    const border = 0
    const format = gl.RGBA
    const type = gl.UNSIGNED_BYTE

    gl.texImage2D(
      gl.TEXTURE_2D, level, internalFormat, width, height, border, format, type, activeImage
    )

    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
  }

  gl.clearColor(0, 0, 0, 0)

  let prevTime = 0

  gl.viewport(0, 0, gl.canvas.width, gl.canvas.height)
  gl.clear(gl.COLOR_BUFFER_BIT)
  gl.useProgram(program)
  gl.bindVertexArray(vao)
  gl.uniform1i(textureLocation, 0)

  function draw (time) {
    if (time - prevTime > 80) {
      gl.drawArrays(gl.TRIANGLES, 0, positions.length / 2)

      updateTexture(gl, texture, frame)

      prevTime = time
    }

    requestAnimationFrame(draw)
  }

  requestAnimationFrame(draw)
}

async function updateTexture (gl, texture, frame) {
  const level = 0
  const internalFormat = gl.RGBA
  const width = 64
  const height = 32
  const border = 0
  const format = gl.RGBA
  const type = gl.UNSIGNED_BYTE

  gl.bindTexture(gl.TEXTURE_2D, texture)
  gl.texImage2D(
    gl.TEXTURE_2D, level, internalFormat, width, height, border, format, type, frame
  )
}

main()
