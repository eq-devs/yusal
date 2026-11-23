import 'package:yusal/features/editor/engine/render3d/scene_gpu.dart';

/// Where Flutter GPU does not exist (the web): no renderer.
Future<SceneGpu?> createSceneGpu() async => null;
