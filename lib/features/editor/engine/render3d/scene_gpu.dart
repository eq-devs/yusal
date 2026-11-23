import 'dart:ui' as ui;

import 'package:yusal/features/editor/engine/render3d/scene_gpu_frame.dart';
import 'package:yusal/features/editor/engine/render3d/scene_gpu_stub.dart'
    if (dart.library.io) 'package:yusal/features/editor/engine/render3d/scene_gpu_impeller.dart'
    as impl;

/// Draws the 3D view's faces on the GPU, with a depth buffer, where the
/// device can. The view asks [SceneGpu.instance] once at start-up and
/// paints on the canvas for as long as the answer is null: on the web, on
/// phones whose graphics driver Flutter GPU does not run on, and after any
/// failure while drawing.
abstract class SceneGpu {
  /// The device's GPU renderer once [prepare] has found one; null before
  /// that, where there is none, and after a failure.
  static SceneGpu? get instance => _failed ? null : _instance;
  static SceneGpu? _instance;
  static bool _failed = false;
  static Future<void>? _preparing;

  /// Why there is no renderer, when there is none; for the meter and logs.
  static String? reason;

  /// Off in a build made with `--dart-define=YUSAL_GPU=false`, to compare
  /// with the canvas painter on the same phone.
  static const allowed = bool.fromEnvironment('YUSAL_GPU', defaultValue: true);

  /// Looks for a renderer, once. Safe to call from every view.
  static Future<void> prepare() => _preparing ??= () async {
        if (!allowed) {
          reason = 'switched off';
          return;
        }
        try {
          _instance = await impl.createSceneGpu();
          if (_instance == null) reason = 'not available here';
        } catch (e) {
          reason = '$e';
        }
      }();

  /// Gives up on the GPU for the rest of the run, after [error] while
  /// drawing: the canvas painter takes over from the same frame.
  static void fail(Object error) {
    _failed = true;
    reason = '$error';
  }

  /// Forgets what [prepare] found; for tests.
  static void reset() {
    _instance = null;
    _failed = false;
    _preparing = null;
    reason = null;
  }

  /// [frame] drawn [width] by [height] pixels on a clear ground, as an
  /// image to put on the canvas. Throws when the GPU cannot draw it.
  ui.Image draw(GpuFrame frame, int width, int height);
}
