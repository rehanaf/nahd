import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'update_model.dart';
import '../../core/app_version.dart';

class UpdateService {
  final http.Client _client = http.Client();

  /// Ganti URL ini setelah Anda sediakan endpoint, misal:
  /// GET https://id-animate.zet.web.id/release/version.json
  /// Response JSON (lihat public_html/release/version.json):
  ///   {"latest_version": "1.0.2", "apk_url": "https://.../id-animate-1.0.2-arm64-v8a.apk", "force": false}
  static const String endpoint = 'https://id-animate.zet.web.id/release/version.json';

  /// Cek apakah ada versi baru. Return null kalau tidak ada atau gagal.
  Future<AppUpdate?> checkUpdate() async {
    try {
      final url = Uri.parse('$endpoint?t=${DateTime.now().millisecondsSinceEpoch}');
      final res = await _client.get(url);
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final latest = data['latest_version'] as String?;
      final apkUrl = data['apk_url'] as String?;
      if (latest == null || apkUrl == null) return null;

      final info = await PackageInfo.fromPlatform();
      final currentVersion = (info.version.isNotEmpty && info.version != '0.0.1') ? info.version : appVersion;
      final currentBuild = (info.buildNumber.isNotEmpty && info.buildNumber != '0') ? info.buildNumber : appBuildNumber;
      final currentFull = '$currentVersion+$currentBuild';

      if (AppUpdate.isNewer(latest, currentFull)) {
        return AppUpdate(
          latestVersion: latest,
          apkUrl: apkUrl,
          force: data['force'] == true,
        );
      }
      return null;
    } catch (_) {
      // Gagal cek (offline, server down, dsb) jangan ganggu user.
      return null;
    }
  }

  /// Download APK ke folder dokumen lokal, lalu buka installer Android.
  Future<File> downloadApk(String url) async {
    final res = await _client.get(Uri.parse(url));
    if (res.statusCode != 200) {
      throw Exception('Download gagal (HTTP ${res.statusCode})');
    }
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/id-animate.apk');
    await file.writeAsBytes(res.bodyBytes, flush: true);
    return file;
  }
}
