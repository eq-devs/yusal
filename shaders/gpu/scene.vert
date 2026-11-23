// One vertex of the 3D view: where it is in the house, its lit colour,
// where on a textile it falls, which way its face looks and how much of
// its light is the sun's.
uniform FrameInfo {
  mat4 mvp;
}
frame_info;

in vec3 position;
in vec4 color;
in vec2 uv;
// The face's normal, toward the eye, and the share of its light lost in
// shadow (below zero: it faces away from the sun and is always in it).
in vec4 shade;
// Where the vertex truly is: faces laid on others are drawn a little
// nearer the eye than they are.
in vec3 world;

out vec4 v_color;
out vec2 v_uv;
out vec4 v_shade;
out vec3 v_world;
out vec4 v_clip;

void main() {
  v_color = color;
  v_uv = uv;
  v_shade = shade;
  v_world = world;
  gl_Position = frame_info.mvp * vec4(position, 1.0);
  v_clip = gl_Position;
}
