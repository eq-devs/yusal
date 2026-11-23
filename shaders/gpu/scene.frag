// A face's colour, times its textile where it has one, darker where the
// sun does not reach it and in the corners where little sky does. Plain
// faces sample a white pixel, so one shader draws them all.
uniform sampler2D textile;
// How far from the sun the nearest thing is, seen from the sun.
uniform sampler2D shadow_map;
// How far from the eye the nearest thing is, seen from the eye.
uniform sampler2D depth_map;

uniform LightInfo {
  // From the house to the sun's view: x and y from -1 to 1, depth 0 to 1.
  mat4 light;
  vec4 eye_far;     // the eye; how far the depth map reaches, in metres
  vec4 forward_ao;  // the way the eye looks; how strong the corners are
  vec4 right_sx;    // the eye's right; clip x for one metre at one metre
  vec4 up_sy;       // the eye's up; clip y for one metre at one metre
  vec4 shadow;      // strength, one texel, which way up maps are, bias
  vec4 corner;      // how far a corner reaches, in metres
}
info;

in vec4 v_color;
in vec2 v_uv;
in vec4 v_shade;
in vec3 v_world;
in vec4 v_clip;

out vec4 frag_color;

float unpack(vec4 c) {
  return dot(c, vec4(1.0, 1.0 / 255.0, 1.0 / 65025.0, 1.0 / 16581375.0));
}

vec2 map_uv(vec2 ndc) {
  return vec2(0.5 + 0.5 * ndc.x, 0.5 + 0.5 * ndc.y * info.shadow.z);
}

float lit_at(vec2 uv, float depth) {
  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return 1.0;
  return unpack(texture(shadow_map, uv)) < depth ? 0.0 : 1.0;
}

// The share of the sun that reaches this point: 1 in the open.
float sunlight(vec3 normal) {
  vec4 p = info.light * vec4(v_world + normal * 0.05, 1.0);
  if (p.z > 1.0) return 1.0;
  float depth = p.z - info.shadow.w;
  float texel = info.shadow.y;
  vec2 at = map_uv(p.xy) / texel - 0.5;
  vec2 f = fract(at);
  vec2 base = (floor(at) + 0.5) * texel;
  float sum = 0.0;
  // Nine texels, weighted as four overlapping squares: a soft edge about
  // a texel and a half wide.
  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      float wx = i < 0 ? 1.0 - f.x : (i > 0 ? f.x : 1.0);
      float wy = j < 0 ? 1.0 - f.y : (j > 0 ? f.y : 1.0);
      sum += wx * wy * lit_at(base + vec2(float(i), float(j)) * texel, depth);
    }
  }
  return sum / 4.0;
}

// The share of the sky this point sees: less in corners and under eaves.
float open_sky(vec3 normal) {
  vec3 eye = info.eye_far.xyz;
  vec3 forward = info.forward_ao.xyz;
  float far = info.eye_far.w;
  float z = dot(v_world - eye, forward);
  vec2 ndc = v_clip.xy / v_clip.w;
  float radius = info.corner.x;
  vec2 reach = radius * vec2(info.right_sx.w, info.up_sy.w) / max(z, 0.05);
  // Turned a little differently from pixel to pixel in a pattern the eye
  // reads as even, so a dozen samples do for many.
  float turn = fract(52.9829189 *
      fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715)))) * 6.2831853;
  float sum = 0.0;
  for (int i = 0; i < 12; i++) {
    float a = float(i) * 2.3999632 + turn;
    float r = sqrt((float(i) + 0.5) / 12.0);
    vec2 d = vec2(cos(a), sin(a)) * r;
    vec2 s = ndc + d * reach;
    float zs = unpack(texture(depth_map, map_uv(s))) * far;
    if (zs >= far) continue;
    vec3 there = eye + (info.right_sx.xyz * (s.x / info.right_sx.w) +
        info.up_sy.xyz * (s.y / info.up_sy.w) + forward) * zs;
    vec3 v = there - v_world;
    float dd = dot(v, v);
    float above = dot(normal, v) - 0.02 - 0.004 * z;
    if (above <= 0.0 || dd > radius * radius * 4.0) continue;
    sum += above / (sqrt(dd) + 0.02) * (1.0 - dd / (radius * radius * 4.0));
  }
  return 1.0 - clamp(sum / 12.0 * 1.7, 0.0, 1.0);
}

void main() {
  vec4 color = v_color * texture(textile, v_uv);
  vec3 normal = v_shade.xyz;
  if (dot(normal, normal) > 0.25) {
    float dim = 1.0;
    if (info.shadow.x > 0.0 && v_shade.w != 0.0) {
      float sun = v_shade.w < 0.0 ? 0.0 : sunlight(normal);
      dim *= 1.0 - abs(v_shade.w) * (1.0 - sun) * info.shadow.x;
    }
    if (info.forward_ao.w > 0.0) {
      dim *= 1.0 - info.forward_ao.w * (1.0 - open_sky(normal));
    }
    color.rgb *= dim;
  }
  frag_color = color;
}
