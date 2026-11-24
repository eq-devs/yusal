import 'package:flutter/widgets.dart';
import 'package:yusal/app.dart';

export 'package:yusal/app.dart';

/// Holds the first frame until the local startup work is done (a few
/// milliseconds, no network), so the launch screen hands straight over to
/// the real app, signed-in account included. Server work runs after.
void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized()..deferFirstFrame();
  runApp(const BootGate());
  Boot.ready.whenComplete(binding.allowFirstFrame);
  Boot.start();
}
