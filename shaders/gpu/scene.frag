// A face's colour, times its textile where it has one. Plain faces sample a
// white pixel, so one shader draws both.
uniform sampler2D textile;

in vec4 v_color;
in vec2 v_uv;

out vec4 frag_color;

void main() {
  frag_color = v_color * texture(textile, v_uv);
}
