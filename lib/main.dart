import 'package:flutter/widgets.dart';
import 'package:yusal/app.dart';
import 'package:yusal/features/editor/engine/render2d/project_preview.dart';
import 'package:yusal/service/storage/project_store.dart';

export 'package:yusal/app.dart';

/// Holds the first frame until the local startup work is done (a few
/// milliseconds, no network), so the launch screen hands straight over to
/// the real app, signed-in account included. Server work runs after.
void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized()..deferFirstFrame();
  ProjectStore.app.previewRenderer = renderProjectPreview;
  runApp(const BootGate());
  Boot.ready.whenComplete(binding.allowFirstFrame);
  Boot.start();
}
