import 'package:yusal/voice/actions_coop.dart';
import 'package:yusal/voice/actions_demand.dart';
import 'package:yusal/voice/actions_design.dart';
import 'package:yusal/voice/actions_houses.dart';
import 'package:yusal/voice/actions_nav.dart';
import 'package:yusal/voice/form.dart';
import 'package:yusal/voice/registry.dart';

/// Every action the app offers.
final appActions = ActionRegistry([
  ...navActions,
  ...houseActions,
  ...demandActions,
  ...coopActions,
  ...designActions,
  ...formActions
]);
