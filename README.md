# Yusal · 自建房设计工具

Flutter house planning app for web, iOS and Android. Dimensions are integer millimeters in `.house` files; the editor displays meters.

## Implemented workflows

- Blank projects and three starter templates.
- Room painting, erasing, types, naming, merging and undo/redo.
- Global/per-floor grids, precise movement, promotion and deletion with conflict choices.
- Doors, windows, sliding doors, positioning, sizing, hinges and main entrance.
- Wall opening/thickness overrides; floors, floor copies, heights and deletion.
- Straight, L and U stairs; flat/gable roofs; configurable creation defaults.
- Net dimensions/areas, 2D plans, orbitable 3D previews and linked picking.
- R01–R10 design checks with highlighted locations.
- Local projects, atomic saves, autosave, recovery index, WebP thumbnails, damaged-file entries, import/export and native `.house` opening.

## Run

```sh
flutter pub get
flutter run -d chrome
```

Use `flutter devices` to choose an iOS simulator or Android device, then `flutter run -d <device-id>`.

## Verify

```sh
flutter analyze
flutter test
flutter test integration_test/app_test.dart -d <ios-simulator-id>
flutter build web --release
flutter build apk --debug
flutter build ios --simulator --no-codesign
```

The unit/widget suite includes 10,000 seeded canonicalization cases, byte-for-byte fixtures, commands, all templates, storage failures, small-screen layouts and autosave/undo. The iOS integration workflow exercises project creation, 3D, native WebP generation and reopening.

## Structure

- `lib/core/`: pure Dart documents, codec, validation, axes, canonicalization, commands, history, geometry and checks.
- `lib/features/`: project home and interactive editor.
- `lib/render2d/`, `lib/render3d/`: render derived geometry.
- `lib/storage/`: platform filesystem boundary, index and project persistence.
- `android/`, `ios/`: native bounded file-import handlers and document registration.

## Acceptance status

This is a runnable implementation candidate. Full acceptance of every matrix in the development specification has not been certified. The current 3D renderer uses software projection with CustomPainter; final engine selection, depth/transparency accuracy, performance and physical-device acceptance remain open. Storage failures currently use exceptions internally, and index listing rebuilds from source files. Grid lines and doors/windows support reversible drag previews, alongside precise property dialogs. Sharing/opening must still be tested in the target users' real chat/file apps on physical iOS/Android devices.

See `IMPLEMENTATION_PLAN.md` for implementation progress and remaining conformance work.
