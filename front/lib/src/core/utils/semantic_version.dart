class SemanticVersion implements Comparable<SemanticVersion> {
  const SemanticVersion(this.parts, this.original);

  final List<int> parts;
  final String original;

  factory SemanticVersion.parse(String value) {
    final parts = value
        .split('.')
        .map((piece) => int.tryParse(piece) ?? 0)
        .toList(growable: false);

    return SemanticVersion(parts, value);
  }

  @override
  int compareTo(SemanticVersion other) {
    final maxLength =
        parts.length > other.parts.length ? parts.length : other.parts.length;

    for (var index = 0; index < maxLength; index++) {
      final left = index < parts.length ? parts[index] : 0;
      final right = index < other.parts.length ? other.parts[index] : 0;
      final diff = left.compareTo(right);
      if (diff != 0) {
        return diff;
      }
    }

    return 0;
  }
}
