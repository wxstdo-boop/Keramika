
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final urls = [
    'https://gitlab.com/wxstdo',
    'https://gitlab.com/wxstdo/keramika',
    'https://gitlab.com/api/v4/users?username=wxstdo',
  ];
  for (final u in urls) {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final req = await client.getUrl(Uri.parse(u));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      print('URL: $u');
      print('STATUS: ${res.statusCode}');
      print('BODY: ${body.length > 200 ? body.substring(0, 200) : body}');
      print('---');
      client.close();
    } catch (e) {
      print('URL: $u');
      print('ERROR: $e');
      print('---');
    }
  }
}
