/// Public web addresses of things people share. The web build is hosted at
/// [webBase]; routes are resolved in `main.dart`.
const webBase = 'https://yusal-web.web.app';

/// Link to a published house; anyone can open it, signed in or not.
String houseLink(String postId) => '$webBase/#/h/$postId';

/// Parses a route name such as `/h/post_aigerim` into a house id.
String? houseIdFromRoute(String? route) {
  if (route == null) return null;
  final m = RegExp(r'^/h/([A-Za-z0-9_\-]+)/?$').firstMatch(route);
  return m?.group(1);
}
