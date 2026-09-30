import '../document/house_document.dart';

class DesignHistory {
  DesignHistory(HouseDocument doc) : present = doc;
  HouseDocument present;
  final List<HouseDocument> _past = [], _future = [];
  bool get canUndo => _past.isNotEmpty;
  bool get canRedo => _future.isNotEmpty;
  bool commit(HouseDocument next) {
    if (extractDesignState(next) == extractDesignState(present)) return false;
    _past.add(present);
    if (_past.length > 100) _past.removeAt(0);
    present = next;
    _future.clear();
    return true;
  }

  void reset(HouseDocument doc) {
    present = doc;
    _past.clear();
    _future.clear();
  }

  void undo() {
    if (!canUndo) return;
    _future.add(present);
    present =
        composeDocument(present.meta, extractDesignState(_past.removeLast()));
  }

  void redo() {
    if (!canRedo) return;
    _past.add(present);
    present =
        composeDocument(present.meta, extractDesignState(_future.removeLast()));
  }
}
