/// One layout rule [runChecks] applies.
class RuleSpec {
  const RuleSpec(this.id, this.level, this.about, this.summary);
  final String id;

  /// `important` for what makes the house unusable as drawn, `suggestion`
  /// for what makes it worse to live in.
  final String level;

  /// What the rule looks at: room, stair, opening, floor or house.
  final String about;
  final String summary;

  Map<String, Object?> toJson() =>
      {'id': id, 'level': level, 'about': about, 'summary': summary};
}

/// Every rule [runChecks] can report, by its id.
const ruleCatalog = <RuleSpec>[
  RuleSpec(
      'R01', 'suggestion', 'room', 'A room is narrower than its use needs.'),
  RuleSpec('R02', 'important', 'room',
      'A room or stair has space taken up entirely by walls.'),
  RuleSpec(
      'R03', 'suggestion', 'room', 'A room is smaller than its use needs.'),
  RuleSpec('R04', 'suggestion', 'room', 'A room has no door into it.'),
  RuleSpec('R05', 'suggestion', 'room', 'A bedroom has no outside window.'),
  RuleSpec('R06', 'important', 'stair',
      'A stair does not fit the space and floor height it has.'),
  RuleSpec(
      'R07',
      'important',
      'opening',
      'A door or window has no wall to sit in: it runs past its wall, sits '
          'on an open stretch, or has no wall there.'),
  RuleSpec(
      'R08',
      'suggestion',
      'house',
      'No main entrance is set, or it is not a door on the ground floor '
          'outside wall.'),
  RuleSpec('R09', 'suggestion', 'floor', 'Part of a floor belongs to no room.'),
  RuleSpec('R10', 'important', 'opening', 'Two openings on one wall overlap.'),
  RuleSpec('R11', 'suggestion', 'opening',
      'A bathroom door opens straight into a kitchen or dining room.'),
  RuleSpec('R12', 'suggestion', 'room',
      'A kitchen or living room has no outside window.'),
  RuleSpec('R13', 'suggestion', 'opening', 'A door is narrower than advised.'),
  RuleSpec('R14', 'suggestion', 'floor',
      'A drawn wall stops short of the next wall, so the room is not enclosed.'),
];
