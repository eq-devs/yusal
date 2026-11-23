import 'package:flutter/widgets.dart';

/// A place a page keeps free for the orb, so it floats over nothing the
/// page needs: the orb sits there while the page is on top, and what it
/// says opens beside it. Takes no room where there is no assistant.
class VoiceSlot extends StatefulWidget {
  const VoiceSlot({super.key, this.size = 44});
  final double size;

  static final _mounted = <_VoiceSlotState>[];

  /// Whether the orb can appear at all: built in and signed in. The voice
  /// feature sets it while its host is mounted.
  static bool Function() wanted = never;
  static bool never() => false;

  /// How many open pages want the orb out of the way (the sign-in page:
  /// its buttons reach the corner where the orb sits).
  static final hidden = ValueNotifier<int>(0);

  /// Where the orb goes on screen now, if the page on top keeps a place.
  static Rect? get rect {
    for (final slot in _mounted.reversed) {
      final box = slot.context.findRenderObject();
      if (slot.onTop && box is RenderBox && box.attached && box.hasSize) {
        return box.localToGlobal(Offset.zero) & box.size;
      }
    }
    return null;
  }

  @override
  State<VoiceSlot> createState() => _VoiceSlotState();
}

class _VoiceSlotState extends State<VoiceSlot> {
  bool onTop = true;

  @override
  void initState() {
    super.initState();
    VoiceSlot._mounted.add(this);
  }

  @override
  void dispose() {
    VoiceSlot._mounted.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Off while another page covers this one.
    onTop = TickerMode.valuesOf(context).enabled;
    return VoiceSlot.wanted()
        ? SizedBox.square(dimension: widget.size)
        : const SizedBox.shrink();
  }
}
