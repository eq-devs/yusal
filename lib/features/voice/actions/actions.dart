import 'package:yusal/features/voice/actions/coop.dart';
import 'package:yusal/features/voice/actions/demand.dart';
import 'package:yusal/features/voice/actions/design.dart';
import 'package:yusal/features/voice/actions/engine.dart';
import 'package:yusal/features/voice/actions/houses.dart';
import 'package:yusal/features/voice/actions/nav.dart';
import 'package:yusal/features/voice/model/form.dart';
import 'package:yusal/features/voice/state/registry.dart';

/// Every action the app offers.
final appActions = ActionRegistry([
  ...navActions,
  ...houseActions,
  ...demandActions,
  ...coopActions,
  ...designActions,
  ...formActions,
  // Last, so the tools before them keep their place in voice_tools.json.
  ...engineActions
]);
