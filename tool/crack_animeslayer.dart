// Standalone end-to-end crack test for animeslayer.to.
//
// Run:
//   dart run tool/crack_animeslayer.dart
//
// Pipeline:
//   1. GET https://patrimoines-en-mouvement.org/lib/flare/v3.php → {first, sec}
//   2. Pick a real /e/<slug>#<frag> from /home (decode `data-href` with XOR/base64)
//   3. POST apiFirst  body=pe=<lastSeg>&hash=<frag>      → {a,b,c,d}
//   4. POST apiSec    body=keyn,name,pe,bool,id,info,san,mwsem
//   5. Decode each `servers[*]` with XOR(base64) key `AQWXZSCED@@POIUYTRR159`
//   6. Print iframe URLs.

import 'dart:convert';
import 'dart:io';

const String _origin = 'https://animeslayer.to';
const String _flareUrl = 'https://patrimoines-en-mouvement.org/lib/flare/v3.php';
const String _hrefKey = 'asxwqa147';
const String _streamKey = 'AQWXZSCED@@POIUYTRR159';
const String _ua =
    'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36';

// Hardcoded constants pulled from page (lines 1567-1572):
const String _name = 'KwQdDUVLRBELIQgCEhY=';
const String _bool = 'no';
const String _san = 'KwQdDUVLRBELIQgCEhY=';
const String _mwsem = 'U29yY2VyeSBGaWdodCxKdWp1dHN1IEthaXNlbixKSks=';

final HttpClient _http = HttpClient()
  ..userAgent = _ua
  ..connectionTimeout = const Duration(seconds: 20);

Future<String> _get(String url, {Map<String, String>? headers}) async {
  final req = await _http.getUrl(Uri.parse(url));
  req.headers.set(HttpHeaders.userAgentHeader, _ua);
  req.headers.set(HttpHeaders.acceptHeader, 'text/html,application/json,*/*');
  if (headers != null) {
    headers.forEach(req.headers.set);
  }
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  if (res.statusCode >= 400) {
    throw Exception('GET $url → ${res.statusCode}\n${body.substring(0, body.length > 500 ? 500 : body.length)}');
  }
  return body;
}

Future<String> _post(String url, String body, {Map<String, String>? headers}) async {
  final req = await _http.postUrl(Uri.parse(url));
  req.headers.set(HttpHeaders.userAgentHeader, _ua);
  req.headers.set(HttpHeaders.contentTypeHeader,
      'application/x-www-form-urlencoded; charset=UTF-8');
  req.headers.set('Origin', _origin);
  req.headers.set('Referer', '$_origin/');
  req.headers.set(HttpHeaders.acceptHeader, 'application/json, text/plain, */*');
  if (headers != null) {
    headers.forEach(req.headers.set);
  }
  req.write(body);
  final res = await req.close();
  final resBody = await res.transform(utf8.decoder).join();
  if (res.statusCode >= 400) {
    throw Exception('POST $url → ${res.statusCode}\n$resBody');
  }
  return resBody;
}

String _xorB64(String data, String key) {
  final decoded = base64.decode(data.trim());
  final out = StringBuffer();
  for (var i = 0; i < decoded.length; i++) {
    out.writeCharCode(decoded[i] ^ key.codeUnitAt(i % key.length));
  }
  return out.toString();
}

String? _decodeHref(String enc) {
  try {
    return _xorB64(enc, _hrefKey);
  } catch (_) {
    return null;
  }
}

Future<({String slug, String frag})> _findRealEpisode() async {
  stdout.writeln('[1] Fetching /home to find a real episode…');
  final html = await _get('$_origin/home');
  // Look for data-href pointing to /e/...
  final regex = RegExp(r'data-href="([^"]+)"');
  final matches = regex.allMatches(html);
  for (final m in matches) {
    final dec = _decodeHref(m.group(1)!);
    if (dec == null) continue;
    if (dec.startsWith('/e/') && dec.contains('#')) {
      final hashIdx = dec.indexOf('#');
      final path = dec.substring(0, hashIdx);
      final frag = dec.substring(hashIdx + 1);
      stdout.writeln('    found: $dec');
      return (slug: path, frag: frag);
    }
  }
  throw Exception('No /e/<slug>#frag links found on /home');
}

Future<Map<String, dynamic>> _firstCall(String apiFirst, String pe, String hash) async {
  final body = 'pe=${Uri.encodeComponent(pe)}&hash=${Uri.encodeComponent(hash)}';
  final raw = await _post(apiFirst, body);
  return jsonDecode(raw) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _secondCall(
  String apiSec, {
  required String dkeyn,
  required String cep,
  required String aid,
  required String binfo,
}) async {
  final params = {
    'keyn': dkeyn,
    'name': _name,
    'pe': cep,
    'bool': _bool,
    'id': aid,
    'info': binfo,
    'san': _san,
    'mwsem': _mwsem,
  };
  final body = params.entries
      .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');
  final raw = await _post(apiSec, body);
  return jsonDecode(raw) as Map<String, dynamic>;
}

Future<void> main(List<String> args) async {
  try {
    // 0. Pick episode URL
    String slug;
    String frag;
    if (args.length >= 2) {
      slug = args[0];
      frag = args[1];
      stdout.writeln('[*] Using provided episode: slug=$slug frag=$frag');
    } else {
      final ep = await _findRealEpisode();
      slug = ep.slug;
      frag = ep.frag;
    }

    // Derive `pe` (last hyphen segment of pathname, per ep.html line 1525)
    final parts = slug.split('-');
    final pe = parts.length > 1 ? parts.last : '';
    stdout.writeln('    pathname=$slug   pe=$pe   hash=$frag');

    // 1. Get apiFirst / apiSec
    stdout.writeln('\n[2] Fetching flare config…');
    final flareRaw = await _get(_flareUrl, headers: {
      'Origin': _origin,
      'Referer': '$_origin/',
    });
    final flare = jsonDecode(flareRaw) as Map<String, dynamic>;
    final apiFirst = flare['first'] as String;
    final apiSec = flare['sec'] as String;
    stdout.writeln('    apiFirst=$apiFirst');
    stdout.writeln('    apiSec=$apiSec');

    // 2. First call
    stdout.writeln('\n[3] POST apiFirst…');
    final r1 = await _firstCall(apiFirst, pe, frag);
    stdout.writeln('    → $r1');
    final aid = r1['a']?.toString() ?? '';
    final binfo = r1['b']?.toString() ?? '';
    final dkeyn = r1['d']?.toString() ?? '';
    final cep = r1['c']?.toString() ?? '';
    if (dkeyn.isEmpty) {
      throw Exception('First call missing field "d"');
    }

    // 3. Second call
    stdout.writeln('\n[4] POST apiSec…');
    final r2 = await _secondCall(
      apiSec,
      dkeyn: dkeyn,
      cep: cep,
      aid: aid,
      binfo: binfo,
    );
    stdout.writeln('    keys: ${r2.keys.toList()}');
    final servers = (r2['servers'] as Map?)?.cast<String, dynamic>() ?? {};
    final auto = r2['auto']?.toString();
    stdout.writeln('    auto=$auto  serverNames=${servers.keys.toList()}');

    // 4. Decrypt each
    stdout.writeln('\n[5] Decrypting iframe URLs…');
    if (servers.isEmpty) {
      stdout.writeln('    ⚠ no servers in response. raw=$r2');
    }
    for (final entry in servers.entries) {
      try {
        final url = _xorB64(entry.value.toString(), _streamKey);
        stdout.writeln('    [${entry.key.padRight(10)}] $url');
      } catch (e) {
        stdout.writeln('    [${entry.key}] DECRYPT FAILED: $e');
      }
    }

    // Also try `data` (auto-loaded encrypted url)
    final dataField = r2['data']?.toString();
    if (dataField != null && dataField.isNotEmpty) {
      try {
        final url = _xorB64(dataField, _streamKey);
        stdout.writeln('\n    [auto:$auto] $url');
      } catch (e) {
        stdout.writeln('\n    [auto] DECRYPT FAILED: $e');
      }
    }

    stdout.writeln('\n✓ Native crack OK.');
  } catch (e, st) {
    stderr.writeln('✗ FAILED: $e');
    stderr.writeln(st);
    exitCode = 1;
  } finally {
    _http.close(force: true);
  }
}
