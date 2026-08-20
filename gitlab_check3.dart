
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final urls = [
    'https://gitlab.com/api/v4/users/41361994/projects?per_page=100',
    'https://gitlab.com/api/v4/projects?search=keramika',
  ];
  for (final u in urls) {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final req = await client.getUrl(Uri.parse(u));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      print('URL: $u');
      print('STATUS: ${res.statusCode}');
      print('BODY: ${body.length > 1500 ? body.substring(0, 1500) : body}');
      print('---');
      client.close();
    } catch (e) {
      print('URL: $u');
      print('ERROR: $e');
      print('---');
    }
  }
}
