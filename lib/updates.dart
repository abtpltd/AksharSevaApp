import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Where new builds are published: the build workflow makes a GitHub release `v<build number>` with the APK attached.
const releaseApi = 'https://api.github.com/repos/abtpltd/AksharSevaApp/releases/latest';
const _downloadPrefix = 'https://github.com/abtpltd/AksharSevaApp/releases/download/';

/// The newest build on GitHub.
class UpdateInfo {
  final int build;
  final String url;
  const UpdateInfo(this.build, this.url);
}

/// What a check found.
sealed class UpdateResult {
  const UpdateResult();
}

/// The phone has the newest build.
class UpToDate extends UpdateResult {
  final int build;
  const UpToDate(this.build);
}

/// A newer build can be downloaded.
class UpdateAvailable extends UpdateResult {
  final UpdateInfo info;
  final int current;
  const UpdateAvailable(this.info, this.current);
}

/// The phone could not reach GitHub, or the answer made no sense.
class UpdateUnknown extends UpdateResult {
  const UpdateUnknown();
}

/// The app was installed from Google Play, which updates it by itself; a build from GitHub is signed differently and could not replace it.
class UpdateByStore extends UpdateResult {
  const UpdateByStore();
}

/// The build number a release tag names: `v12` is 12; anything else is not a build of ours.
int? buildFromTag(Object? tag) {
  if (tag is! String) return null;
  final m = RegExp(r'^v(\d{1,9})$').firstMatch(tag.trim());
  return m == null ? null : int.parse(m[1]!);
}

/// The release's build and APK address, or null when the answer is not a build of ours (wrong tag, no APK, an address that is not our release download).
UpdateInfo? parseRelease(Object? json) {
  if (json is! Map) return null;
  final build = buildFromTag(json['tag_name']);
  if (build == null || json['draft'] == true || json['prerelease'] == true) return null;
  for (final a in (json['assets'] is List ? json['assets'] as List : const [])) {
    if (a is Map && a['name'] == 'AksharSevak.apk') {
      final u = a['browser_download_url'];
      if (u is String && u.startsWith(_downloadPrefix) && u.endsWith('/AksharSevak.apk')) return UpdateInfo(build, u);
    }
  }
  return null;
}

/// Asks GitHub for the newest build and compares it with [currentBuild]. [installer] is the package that installed this app (Google Play is `com.android.vending`).
Future<UpdateResult> checkForUpdate({required int currentBuild, String? installer, http.Client? client, Duration timeout = const Duration(seconds: 10)}) async {
  if (installer == 'com.android.vending') return const UpdateByStore();
  final c = client ?? http.Client();
  try {
    final r = await c.get(Uri.parse(releaseApi), headers: {'accept': 'application/vnd.github+json'}).timeout(timeout);
    if (r.statusCode != 200) return const UpdateUnknown();
    final info = parseRelease(jsonDecode(r.body));
    if (info == null) return const UpdateUnknown();
    return info.build > currentBuild ? UpdateAvailable(info, currentBuild) : UpToDate(currentBuild);
  } on Object {
    return const UpdateUnknown();
  } finally {
    if (client == null) c.close();
  }
}

/// This phone's check: reads its own build number and installer, then asks GitHub.
Future<UpdateResult> checkThisApp() async {
  try {
    final p = await PackageInfo.fromPlatform();
    return checkForUpdate(currentBuild: int.tryParse(p.buildNumber) ?? 0, installer: p.installerStore);
  } on Object {
    return const UpdateUnknown();
  }
}

/// Opens the APK address in the phone's browser, which downloads it; tapping the downloaded file installs the update.
Future<bool> openDownload(UpdateInfo info) async {
  try {
    return await launchUrl(Uri.parse(info.url), mode: LaunchMode.externalApplication);
  } on Object {
    return false;
  }
}

/// What the screens call. Tests put pretend versions here.
Future<UpdateResult> Function() updateCheck = checkThisApp;
Future<bool> Function(UpdateInfo) updateDownload = openDownload;

/// Set to true by `main` so the app looks for an update once when it opens. Off in tests, so they never reach the network.
bool checkOnStart = false;
