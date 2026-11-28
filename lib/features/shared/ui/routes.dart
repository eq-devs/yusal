import 'package:flutter/widgets.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/features/shared/ui/scope.dart';
import 'package:yusal/service/storage/project_store.dart';

/// The screens one feature opens in another, as values: a feature says
/// where to go ([pageFor], [openRef]) without importing the page, so features
/// do not import each other's pages and the feature graph stays acyclic.
/// `app.dart` turns each one into its page (`appPage`, an exhaustive
/// switch: a new destination does not compile until it has a page).
sealed class Destination {
  const Destination();
}

final class ToAdmin extends Destination {
  const ToAdmin();
}

final class ToApply extends Destination {
  const ToApply(this.demand, {this.existing});
  final Demand demand;
  final Application? existing;
}

final class ToApplications extends Destination {
  const ToApplications(this.demandId);
  final String demandId;
}

final class ToAppeals extends Destination {
  const ToAppeals();
}

final class ToBackup extends Destination {
  const ToBackup({this.highlight});
  final String? highlight;
}

final class ToChat extends Destination {
  const ToChat(this.conversationId);
  final String conversationId;
}

final class ToCooperation extends Destination {
  const ToCooperation(this.cooperationId);
  final String cooperationId;
}

final class ToDemand extends Destination {
  const ToDemand(this.demandId);
  final String demandId;
}

final class ToDemandFromDesign extends Destination {
  const ToDemandFromDesign(this.entry);
  final ProjectEntry entry;
}

final class ToDiscover extends Destination {
  const ToDiscover();
}

final class ToEditor extends Destination {
  const ToEditor(this.entry, this.store);
  final ProjectEntry entry;
  final ProjectStore store;
}

final class ToHouseWorkspace extends Destination {
  const ToHouseWorkspace(this.houseKey, {this.initialTab = 0});
  final String houseKey;
  final int initialTab;
}

final class ToLogin extends Destination {
  const ToLogin();
}

final class ToPost extends Destination {
  const ToPost(this.postId, {this.preview});
  final String postId;
  final HousePost? preview;
}

final class ToProfile extends Destination {
  const ToProfile(this.profileId);
  final String profileId;
}

final class ToProfileEdit extends Destination {
  const ToProfileEdit({this.role});
  final ProRole? role;
}

final class ToPublishDemand extends Destination {
  const ToPublishDemand({this.snapshot, this.designProjectId});
  final DesignSnapshot? snapshot;
  final String? designProjectId;
}

final class ToPublishPost extends Destination {
  const ToPublishPost(this.entry);
  final ProjectEntry entry;
}

final class ToShell extends Destination {
  const ToShell();
}

/// Where the app builds pages: `main()` and the tests' setup set
/// `Routes.pages = appPage` (from `app.dart`).
abstract final class Routes {
  static Widget Function(Destination)? _pages;

  // ignore: avoid_setters_without_getters
  static set pages(Widget Function(Destination) pages) => _pages = pages;
}

/// The page for [to].
Widget pageFor(Destination to) {
  final pages = Routes._pages;
  if (pages == null) {
    throw StateError('Routes.pages = appPage was not set');
  }
  return pages(to);
}

/// Opens the page for a referenced object (notices and tapped pushes).
Future<void> openRef(BuildContext context, RefType type, String id) {
  final Destination? to = switch (type) {
    RefType.cooperation => ToCooperation(id),
    RefType.conversation => ToChat(id),
    RefType.post => ToPost(id),
    RefType.profile => ToProfile(id),
    RefType.appeal || RefType.account => const ToAppeals(),
    RefType.report => null,
    RefType.demand || RefType.application => ToDemand(id),
  };
  if (to == null) return Future<void>.value();
  return pushPage<void>(context, (_) => pageFor(to));
}
