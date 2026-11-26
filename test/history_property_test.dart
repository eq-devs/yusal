// Undo and redo over random command sequences: n undos give back the
// start exactly, n redos the end, and a commit after undo drops redo.
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/commands/kz_template.dart';
import 'package:yusal/features/editor/engine/core/history/design_history.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';

import 'support/command_samples.dart';

void main() {
  for (final seed in [1, 2, 3, 4, 5, 6]) {
    test('seed $seed: undo all, redo all', () {
      var n = 0;
      final ctx = CommandContext(
          newId: () => 'h$seed-${n++}', now: () => '2026-11-26T00:00:00Z');
      final start = createKazakhTemplate(ctx.now(), ctx.newId);
      final history = DesignHistory(start, limit: 1000);
      final rng = Random(seed);
      final states = [extractDesignState(start)];
      var tries = 0;
      while (states.length < 25 && tries++ < 400) {
        final doc = history.present;
        final samples = commandsFor(doc);
        final (kind, args) = samples[rng.nextInt(samples.length)];
        final r = executeCommand(
            extractDesignState(doc), DesignCommand(kind, args), ctx);
        if (r is! Applied) continue;
        final next = composeDocument(doc.meta, r.newState);
        // Every step leaves a valid house that saves and loads as itself.
        expect(validateHouse(next), isEmpty, reason: '$kind $args');
        final loaded = loadHouse(utf8.encode(encodeHouse(next)));
        expect(extractDesignState(loaded.document!), r.newState,
            reason: '$kind $args');
        if (history.commit(next)) states.add(r.newState);
      }
      expect(states.length, greaterThan(10), reason: 'too few edits applied');
      final end = extractDesignState(history.present);
      for (var i = states.length - 2; i >= 0; i--) {
        history.undo();
        expect(extractDesignState(history.present), states[i]);
      }
      expect(history.canUndo, isFalse);
      while (history.canRedo) {
        history.redo();
      }
      expect(extractDesignState(history.present), end);
      // A new edit after undo leaves nothing to redo.
      history.undo();
      final doc = history.present;
      final r = executeCommand(
          extractDesignState(doc),
          DesignCommand(
              'RenameFloor', {'floorId': doc.floors.first.id, 'value': 'X'}),
          ctx);
      expect(history.commit(composeDocument(doc.meta, (r as Applied).newState)),
          isTrue);
      expect(history.canRedo, isFalse);
    });
  }
}
