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
  /// Return true kalau [a] lebih baru dari [b].
  static bool isNewer(String a, String b) {
    List<int> parse(String v) =>
        v.split('+').first.split('.').map(int.parse).toList();
    final av = parse(a);
    final bv = parse(b);
    for (var i = 0; i < 3; i++) {
      final x = i < av.length ? av[i] : 0;
      final y = i < bv.length ? bv[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }
}
