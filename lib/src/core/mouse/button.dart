enum TerminalMouseButton {
  left(id: 0),

  middle(id: 1),

  right(id: 2),

  wheelUp(id: 64, isWheel: true),

  wheelDown(id: 65, isWheel: true),

  wheelLeft(id: 66, isWheel: true),

  wheelRight(id: 67, isWheel: true),
  ;

  /// The id that is used to report a button press or release to the terminal.
  ///
  /// Mouse wheel buttons use ids 64-67 (bit 6 set), as standardized by
  /// xterm: wheel up = 64, wheel down = 65, wheel left = 66, wheel
  /// right = 67. Modifier bits (shift = 4, alt = 8, ctrl = 16) are OR'ed
  /// onto the id when reporting.
  final int id;

  /// Whether this button is a mouse wheel button.
  final bool isWheel;

  const TerminalMouseButton({required this.id, this.isWheel = false});
}
