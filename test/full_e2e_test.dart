import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:play_torrio_native/api/anime_arabic_extractor.dart';
import 'package:play_torrio_native/api/anime_arabic_service.dart';

void main() {
  test('e2e crack animeslayer', () async {
    final log = StringBuffer();
    void p(Object? m) {
      log.writeln(m);
      stderr.writeln(m);
    }

    final s = AnimeArabicService();
    final home = await s.getHome();
    p('spotlight=${home.spotlight.length} recent=${home.recentEpisodes.length} '
        'trending=${home.trending.length} popularMovies=${home.popularMovies.length} '
        'topSeasonal=${home.topSeasonal.length} seasonal=${home.seasonal.length} '
        'legendary=${home.legendary.length} upcoming=${home.upcoming.length} '
        'misc=${home.misc.length}');
    final pool = <ArabicAnimeCard>[
      ...home.recentEpisodes,
      ...home.trending,
      ...home.popularMovies,
      ...home.topSeasonal,
      ...home.seasonal,
      ...home.legendary,
      ...home.spotlight,
      for (final m in home.misc) ...m.value,
    ];
    p('pool size=${pool.length}');
    if (pool.isNotEmpty) {
      p('  first: ${pool.first.slug} / ${pool.first.title}');
    }
    for (final card in pool.take(8)) {
      try {
        p('[*] details: ${card.slug}');
        final d = await s.getDetails(card.slug);
        p('    episodes=${d.episodes.length}');
        if (d.episodes.isEmpty) continue;
        final ep = d.episodes.first;
        p('    ep1 watchPath=${ep.watchPath}');
        final x = AnimeArabicExtractor();
        final hits = await x.resolveEpisode(
          ep,
          onProgress: (ph, det) => p('    [$ph] $det'),
        );
        if (hits.isEmpty) {
          p('    no hits');
          continue;
        }
        p('=== ${hits.length} STREAMS RESOLVED ===');
        for (final h in hits) {
          p('  ${h.server.displayName.padRight(12)} ${h.quality.padRight(8)} ${h.url.length > 110 ? "${h.url.substring(0, 110)}..." : h.url}');
        }
        final first = hits.first;
        final c = HttpClient();
        try {
          final req = await c.openUrl('HEAD', Uri.parse(first.url));
          first.headers.forEach(req.headers.set);
          final res = await req.close();
          p('=== HEAD test ===');
          p('  HTTP ${res.statusCode}  CT=${res.headers.value('content-type')}  CL=${res.headers.value('content-length')}');
        } finally {
          c.close(force: true);
        }
        // Force test failure to dump log so we can see the stream URL.
        fail('SUCCESS DUMP:\n$log');
      } catch (e, st) {
        if (e.toString().contains('SUCCESS DUMP')) rethrow;
        p('    err: $e\n$st');
      }
    }
    fail('No working episode found.\n$log');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
