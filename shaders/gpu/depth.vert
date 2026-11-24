// A vertex of the house for a picture of distances: from the sun, for
// shadows, or from the eye, for the corners.
uniform DepthInfo {
  mat4 mvp;
  // Times the vertex: its distance, 0 nearest to 1 farthest.
  vec4 row;
}
depth_info;

in vec3 position;

out float v_depth;

void main() {
  vec4 p = vec4(position, 1.0);
  v_depth = dot(depth_info.row, p);
  gl_Position = depth_info.mvp * p;
}
