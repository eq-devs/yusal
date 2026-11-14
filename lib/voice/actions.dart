import 'actions_design.dart';
import 'actions_nav.dart';
import 'form.dart';
import 'registry.dart';

/// Every action the app offers.
final appActions =
    ActionRegistry([...navActions, ...designActions, ...formActions]);
