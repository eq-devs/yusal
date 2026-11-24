// A distance from 0 to 1, spread over the four bytes of a pixel.
in float v_depth;

out vec4 frag_color;

void main() {
  float d = clamp(v_depth, 0.0, 0.99999);
  vec4 e = fract(d * vec4(1.0, 255.0, 65025.0, 16581375.0));
  e -= e.yzww * vec4(1.0 / 255.0, 1.0 / 255.0, 1.0 / 255.0, 0.0);
  frag_color = e;
}
