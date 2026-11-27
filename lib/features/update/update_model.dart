/// Model hasil cek update aplikasi.
class AppUpdate {
  final String latestVersion;
  final String apkUrl;
  final bool force;

  const AppUpdate({
    required this.latestVersion,
    required this.apkUrl,
    this.force = false,
  });

  /// Bandingkin dua versi (semver-ish: major.minor.patch, boleh ada "+build").
  /// Return true kalau [latest] lebih baru dari [current].
  static bool isNewer(String latest, String current) {
    List<int> parseVersion(String v) =>
        v.split('+').first.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    int parseBuild(String v) {
      final parts = v.split('+');
      if (parts.length > 1) {
        return int.tryParse(parts[1]) ?? 0;
      }
      return 0;
    }

    final lv = parseVersion(latest);
    final cv = parseVersion(current);
    for (var i = 0; i < 3; i++) {
      final x = i < lv.length ? lv[i] : 0;
      final y = i < cv.length ? cv[i] : 0;
      if (x != y) return x > y;
    }
    final lb = parseBuild(latest);
    final cb = parseBuild(current);
    return lb > cb;
  }
}
