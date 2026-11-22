/// Reads a number as people type it: a comma or a dot for the decimal
/// part, spaces ignored, and simple sums such as `3,6+2,4` or `12/3`
/// (`*` and `/` before `+` and `-`, no brackets). Returns null for
/// anything else.
double? parseNumber(String text) {
  final s = text
      .replaceAll(RegExp(r'[\s ]'), '')
      .replaceAll(',', '.')
      .replaceAll('×', '*')
      .replaceAll('÷', '/')
      .replaceAll('−', '-');
  if (!RegExp(r'^-?\d*\.?\d+([+\-*/]\d*\.?\d+)*$').hasMatch(s)) return null;
  final numbers = RegExp(r'(?:^-)?\d*\.?\d+')
      .allMatches(s)
      .map((m) => double.parse(m[0]!))
      .toList();
  final signs = RegExp(r'(?<=\d)[+\-*/]').allMatches(s).map((m) => m[0]!);
  // Fold products into the running term, then add the terms up.
  var sum = 0.0;
  var term = numbers.first;
  var i = 1;
  for (final sign in signs) {
    final n = numbers[i++];
    switch (sign) {
      case '*':
        term *= n;
      case '/':
        term /= n;
      case '+':
        sum += term;
        term = n;
      case '-':
        sum += term;
        term = -n;
    }
  }
  final value = sum + term;
  return value.isFinite ? value : null;
}
