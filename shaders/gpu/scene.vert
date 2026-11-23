// One vertex of the 3D view: where it is in the house, its lit colour and
// where on a textile it falls.
uniform FrameInfo {
  mat4 mvp;
}
frame_info;

in vec3 position;
in vec4 color;
in vec2 uv;

out vec4 v_color;
out vec2 v_uv;

void main() {
  v_color = color;
  v_uv = uv;
  gl_Position = frame_info.mvp * vec4(position, 1.0);
}
