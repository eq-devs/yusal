import 'actions_coop.dart';
import 'actions_demand.dart';
import 'actions_design.dart';
import 'actions_houses.dart';
import 'actions_nav.dart';
import 'form.dart';
import 'registry.dart';

/// Every action the app offers.
final appActions = ActionRegistry([
  ...navActions,
  ...houseActions,
  ...demandActions,
  ...coopActions,
  ...designActions,
  ...formActions
]);
