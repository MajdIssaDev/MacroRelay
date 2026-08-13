import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class UpdateInfo {
  const UpdateInfo({required this.latest, required this.url, required this.body});
  final String latest;
  final String url;
  final String body;
}

class Updater {
  static const current = '1.2.2';
  static const owner = 'MajdIssaDev';
  static const repo = 'MacroRelay';

  static Future<UpdateInfo?> check() async {
    final uri = Uri.parse('https://api.github.com/repos/$owner/$repo/releases/latest');
    final res = await http.get(uri, headers: {'Accept': 'application/vnd.github+json'});
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (data['tag_name'] as String? ?? '').replaceFirst('v', '');
    if (tag.isEmpty || tag == current) return null;
    return UpdateInfo(
      latest: tag,
      url: data['html_url'] as String? ?? 'https://github.com/$owner/$repo/releases',
      body: data['body'] as String? ?? '',
    );
  }
}
