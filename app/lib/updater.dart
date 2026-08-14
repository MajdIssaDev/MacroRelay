import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

enum UpdateKind { upToDate, skipped, failed }

class UpdateResult {
  const UpdateResult(this.kind, this.message);
  final UpdateKind kind;
  final String message;
}

class Updater {
  static const current = '1.4.1';
  static const owner = 'MajdIssaDev';
  static const repo = 'MacroRelay';

  static const _headers = {
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'MacroRelay/$current',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  static Future<UpdateResult> checkAndApply({
    void Function(String status)? onStatus,
    Future<void> Function()? onBeforeApply,
    bool apply = true,
    bool allowSetupInstall = true,
  }) async {
    void status(String s) => onStatus?.call(s);
    try {
      status('Checking updates…');
      final latest = await _latestRelease();
      if (latest == null) {
        return const UpdateResult(UpdateKind.failed, 'Update check failed');
      }
      if (compareVersions(latest.tag, current) <= 0) {
        return UpdateResult(UpdateKind.upToDate, 'Up to date (v$current)');
      }

      final updateExe = _findUpdateExe();
      final nupkg = latest.assetWhere((n) => n.toLowerCase().endsWith('-full.nupkg'));
      final setup = latest.assetWhere((n) => n.toLowerCase().endsWith('-win-setup.exe'));

      if (!apply) {
        return UpdateResult(UpdateKind.skipped, 'Update ${latest.tag} available');
      }

      if (updateExe != null && nupkg != null) {
        status('Downloading ${latest.tag}…');
        final file = await _download(nupkg.url, nupkg.name, onStatus: status, version: latest.tag);
        status('Installing ${latest.tag}…');
        await onBeforeApply?.call();
        await Process.start(
          updateExe.path,
          ['--silent', 'apply', '--waitPid', '$pid', '--package', file.path],
          workingDirectory: updateExe.parent.path,
          mode: ProcessStartMode.detached,
        );
        exit(0);
      }

      if (allowSetupInstall && setup != null) {
        status('Downloading ${latest.tag}…');
        final file = await _download(setup.url, setup.name, onStatus: status, version: latest.tag);
        status('Installing ${latest.tag}…');
        await onBeforeApply?.call();
        await Process.start(
          file.path,
          const [],
          mode: ProcessStartMode.detached,
        );
        exit(0);
      }

      return const UpdateResult(
        UpdateKind.skipped,
        'Updates apply after installing with Setup.exe from GitHub Releases.',
      );
    } catch (err) {
      return UpdateResult(UpdateKind.failed, 'Update failed: $err');
    }
  }

  static Future<_Release?> _latestRelease() async {
    final uri = Uri.parse('https://api.github.com/repos/$owner/$repo/releases/latest');
    final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (data['tag_name'] as String? ?? '').replaceFirst(RegExp(r'^v'), '');
    if (tag.isEmpty) return null;
    final assets = <_Asset>[];
    for (final raw in (data['assets'] as List? ?? const [])) {
      final map = raw as Map<String, dynamic>;
      final name = map['name'] as String? ?? '';
      final url = map['browser_download_url'] as String? ?? '';
      if (name.isNotEmpty && url.isNotEmpty) assets.add(_Asset(name, url));
    }
    return _Release(tag, assets);
  }

  static Future<File> _download(
    String url,
    String name, {
    required void Function(String status) onStatus,
    required String version,
  }) async {
    final dest = File(_join(Directory.systemTemp.path, 'MacroRelay-$name'));
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      req.headers['User-Agent'] = 'MacroRelay/$current';
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode < 200 || res.statusCode >= 400) {
        throw Exception('download HTTP ${res.statusCode}');
      }
      final total = res.contentLength ?? 0;
      final sink = dest.openWrite();
      var got = 0;
      await for (final chunk in res.stream) {
        got += chunk.length;
        sink.add(chunk);
        if (total > 0) {
          final pct = ((got / total) * 100).clamp(0, 100).round();
          onStatus('Downloading $version… $pct%');
        }
      }
      await sink.close();
      return dest;
    } finally {
      client.close();
    }
  }

  static File? _findUpdateExe() {
    final dir = File(Platform.resolvedExecutable).parent;
    for (final candidate in [
      File(_join(dir.path, 'Update.exe')),
      File(_join(dir.parent.path, 'Update.exe')),
    ]) {
      if (candidate.existsSync()) return candidate;
    }
    return null;
  }

  static int compareVersions(String a, String b) {
    List<int> parse(String v) {
      final core = v.split(RegExp(r'[-+]')).first;
      return [for (final p in core.split('.')) int.tryParse(p) ?? 0];
    }

    final pa = parse(a);
    final pb = parse(b);
    final n = math.max(pa.length, pb.length);
    for (var i = 0; i < n; i++) {
      final da = i < pa.length ? pa[i] : 0;
      final db = i < pb.length ? pb[i] : 0;
      if (da != db) return da.compareTo(db);
    }
    return 0;
  }

  static String _join(String a, String b) => '$a${Platform.pathSeparator}$b';
}

class _Release {
  const _Release(this.tag, this.assets);
  final String tag;
  final List<_Asset> assets;

  _Asset? assetWhere(bool Function(String name) test) {
    for (final a in assets) {
      if (test(a.name)) return a;
    }
    return null;
  }
}

class _Asset {
  const _Asset(this.name, this.url);
  final String name;
  final String url;
}
