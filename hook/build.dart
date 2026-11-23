import 'package:flutter_gpu_shaders/build.dart';
import 'package:hooks/hooks.dart';

/// Compiles the 3D view's GPU shaders into the app's assets.
void main(List<String> args) async {
  await build(args, (input, output) async {
    await buildShaderBundleJson(
      buildInput: input,
      buildOutput: output,
      manifestFileName: 'shaders/gpu/scene.shaderbundle.json',
    );
  });
}
