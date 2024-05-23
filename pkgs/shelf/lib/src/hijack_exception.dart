class HijackException implements Exception {
  const HijackException();

  @override
  String toString() =>
      "A shelf request's underlying data stream was hijacked.\n"
      'This exception is used for control flow and should only be handled by a '
      'Shelf Adapter.';
}
