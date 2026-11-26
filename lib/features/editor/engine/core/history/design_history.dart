import 'package:yusal/features/editor/engine/core/document/house_document.dart';

/// Undo and redo over whole-document snapshots.
///
/// Snapshots share every unchanged object with their neighbours (documents
/// are immutable), so a step costs what the edit changed, not the house.
/// The design's name and dates ([Meta]) are not part of undo: [rename]
/// changes them without a step, and undo keeps the current ones.
class DesignHistory {
  DesignHistory(HouseDocument doc, {this.limit = 100}) : _present = doc;

  /// How many steps back undo reaches.
  final int limit;
  HouseDocument _present;
  final List<HouseDocument> _past = [];
  final List<HouseDocument> _future = [];

  /// Whether a group is open, and whether it has taken its one step yet.
  bool _grouping = false;
  bool _groupStepped = false;

  HouseDocument get present => _present;
  bool get canUndo => _past.isNotEmpty;
  bool get canRedo => _future.isNotEmpty;
  int get undoDepth => _past.length;

  /// Makes [next] the present as one undo step. Returns false, and changes
  /// nothing, when [next] designs the same house.
  bool commit(HouseDocument next) {
    if (extractDesignState(next) == extractDesignState(_present)) return false;
    if (!(_grouping && _groupStepped)) {
      _past.add(_present);
      if (_past.length > limit) _past.removeAt(0);
      _groupStepped = _grouping;
    }
    _present = next;
    _future.clear();
    return true;
  }

  /// Changes the design's name and dates without an undo step.
  void rename(Meta meta) =>
      _present = composeDocument(meta, extractDesignState(_present));

  void reset(HouseDocument doc) {
    _present = doc;
    _past.clear();
    _future.clear();
    _grouping = false;
    _groupStepped = false;
  }

  /// Starts a group: every commit until [endGroup] undoes as one step.
  /// One spoken sentence can run several commands.
  void beginGroup() {
    _grouping = true;
    _groupStepped = false;
  }

  void endGroup() {
    _grouping = false;
    _groupStepped = false;
  }

  void undo() {
    if (!canUndo) return;
    endGroup();
    _future.add(_present);
    _present = _withCurrentMeta(_past.removeLast());
  }

  void redo() {
    if (!canRedo) return;
    endGroup();
    _past.add(_present);
    _present = _withCurrentMeta(_future.removeLast());
  }

  /// [doc] as it was, unless the name changed since: reusing the very
  /// object keeps every geometry cache keyed on it.
  HouseDocument _withCurrentMeta(HouseDocument doc) => doc.meta == _present.meta
      ? doc
      : composeDocument(_present.meta, extractDesignState(doc));
}
