import 'dart:convert';

import 'package:digital_tasbih/l10n.dart';
import 'package:digital_tasbih/updater.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Client fake(int status, Map<String, dynamic> body) =>
    MockClient((_) async => http.Response(jsonEncode(body), status));

Map<String, dynamic> release(
  String tag, {
  List<String> assets = const ['Zikir.apk'],
}) => {
  'tag_name': tag,
  'published_at': '2026-10-26T10:00:00Z',
  'assets': [
    for (final a in assets)
      {'name': a, 'browser_download_url': 'https://example.com/$tag/$a'},
  ],
};

void main() {
  test('build number is read from the release tag', () {
    expect(buildFromTag('build-8'), 8);
    expect(buildFromTag(' build-120 '), 120);
    expect(buildFromTag('v1.2.3'), isNull);
    expect(buildFromTag('build-x'), isNull);
    expect(buildFromTag(''), isNull);
  });

  test(
    'fetchLatest returns the APK link and build of the newest release',
    () async {
      final info = await fetchLatest(client: fake(200, release('build-9')));
      expect(info.build, 9);
      expect(info.url, 'https://example.com/build-9/Zikir.apk');
      expect(info.published, DateTime.utc(2026, 10, 26, 10));
    },
  );

  test('fetchLatest explains problems instead of crashing', () async {
    Matcher updateError(UpdateErrorKind kind, [int? code]) => isA<UpdateError>()
        .having((e) => e.kind, 'kind', kind)
        .having((e) => e.code, 'code', code);

    await expectLater(
      fetchLatest(client: fake(403, {'message': 'rate limit'})),
      throwsA(updateError(UpdateErrorKind.http, 403)),
    );
    await expectLater(
      fetchLatest(client: fake(200, release('nightly'))),
      throwsA(updateError(UpdateErrorKind.noApk)),
    );
    await expectLater(
      fetchLatest(client: fake(200, release('build-9', assets: ['notes.txt']))),
      throwsA(updateError(UpdateErrorKind.noApk)),
    );
  });

  test('update errors read well in both languages', () {
    const http = UpdateError(UpdateErrorKind.http, 403);
    expect(http.message(S.en), contains('403'));
    expect(http.message(S.bangla), contains('৪০৩')); // Bangla digits
    expect(
      const UpdateError(UpdateErrorKind.noApk).message(S.en),
      contains('no APK'),
    );
    expect(
      const UpdateError(UpdateErrorKind.timeout).message(S.bangla),
      contains('ইন্টারনেট'),
    );
    expect(http.toString(), contains('403')); // English in logs
  });

  group('finding the newest build', () {
    const pageUrl = 'github.com';
    const tagBase = 'https://github.com/Md-Atiqur-Rahman/Zikir/releases/tag/';

    /// A fake GitHub: the website redirect and the API answer as told.
    ({http.Client client, List<String> calls}) github({
      http.Response Function()? page,
      http.Response Function()? api,
    }) {
      final calls = <String>[];
      final client = MockClient((req) async {
        calls.add(req.url.host);
        if (req.url.host == pageUrl) {
          return (page ?? () => http.Response('', 404))();
        }
        return (api ?? () => http.Response('{}', 500))();
      });
      return (client: client, calls: calls);
    }

    http.Response redirectTo(String tag) =>
        http.Response('', 302, headers: {'location': '$tagBase$tag'});

    http.Response apiRelease(String tag) =>
        http.Response(jsonEncode(release(tag)), 200);

    test('apk link is built from the tag', () {
      expect(
        apkUrlFor('build-9'),
        'https://github.com/Md-Atiqur-Rahman/Zikir/releases/download/build-9/Zikir.apk',
      );
    });

    test('the website redirect is enough; the API is not even asked', () async {
      final g = github(page: () => redirectTo('build-20'));
      final info = await fetchLatest(client: g.client);
      expect(info.build, 20);
      expect(info.url, apkUrlFor('build-20'));
      expect(info.published, isNull);
      expect(g.calls, ['github.com']);
    });

    test(
      'works while the API is rate limited (403), as on mobile data',
      () async {
        final g = github(
          page: () => redirectTo('build-21'),
          api: () => http.Response('{"message":"rate limit exceeded"}', 403),
        );
        expect((await fetchLatest(client: g.client)).build, 21);
      },
    );

    test('falls back to the API when the redirect is not usable', () async {
      for (final page in <http.Response Function()>[
        () => http.Response('', 500),
        () => http.Response('', 302), // redirect without a target
        () => http.Response('<html>', 200), // not a redirect at all
        () => redirectTo('v2.0'), // not one of our tags
      ]) {
        final g = github(page: page, api: () => apiRelease('build-22'));
        final info = await fetchLatest(client: g.client);
        expect(info.build, 22);
        expect(
          info.url,
          'https://example.com/build-22/Zikir.apk',
        ); // from the API
        expect(info.published, DateTime.utc(2026, 10, 26, 10));
        expect(g.calls, ['github.com', 'api.github.com']);
      }
    });

    test(
      'both failing: the API reason is reported, with a hint for 403',
      () async {
        final g = github(
          page: () => http.Response('', 500),
          api: () => http.Response('{}', 403),
        );
        final e = await fetchLatest(client: g.client)
            .then<Object?>((_) => null, onError: (Object e) => e);
        expect(e, isA<UpdateError>());
        final err = e! as UpdateError;
        expect((err.kind, err.code), (UpdateErrorKind.http, 403));
        expect(err.message(S.en), contains('limiting requests'));
        expect(err.message(S.en), contains('403'));
        expect(err.message(S.bangla), contains('সীমিত'));
        expect(err.message(S.bangla), contains('৪০৩'));
        // other codes keep the plain message
        expect(
          const UpdateError(UpdateErrorKind.http, 500).message(S.en),
          isNot(contains('limiting')),
        );
      },
    );

    test('no connection at all gives the plain "no answer" message', () async {
      final client = MockClient(
        (req) async => throw http.ClientException('Failed host lookup'),
      );
      final e = await fetchLatest(client: client)
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect((e! as UpdateError).kind, UpdateErrorKind.timeout);
    });
  });

  Future<void> open(
    WidgetTester tester, {
    required int installed,
    required Future<UpdateInfo> Function() fetch,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UpdatePage(fetch: fetch, installed: () async => installed),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows "Update now" when a newer build exists', (tester) async {
    await open(
      tester,
      installed: 5,
      fetch: () async => UpdateInfo(
        8,
        'https://example.com/a.apk',
        DateTime.utc(2026, 10, 26),
      ),
    );
    expect(find.text('Update available'), findsOneWidget);
    expect(find.textContaining('Installed: build 5'), findsOneWidget);
    expect(find.textContaining('New: build 8'), findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);
  });

  testWidgets('says up to date when the installed build is the newest', (
    tester,
  ) async {
    await open(
      tester,
      installed: 8,
      fetch: () async => const UpdateInfo(8, 'x', null),
    );
    expect(find.text('You are up to date'), findsOneWidget);
    expect(find.text('Update now'), findsNothing);
    expect(find.text('Check again'), findsOneWidget);
  });

  testWidgets('shows the reason and a retry button when the check fails', (
    tester,
  ) async {
    await open(
      tester,
      installed: 1,
      fetch: () async => throw 'No answer from GitHub. Check your internet.',
    );
    expect(find.text('Could not update'), findsOneWidget);
    expect(find.textContaining('No answer from GitHub'), findsOneWidget);
    expect(find.text('Check again'), findsOneWidget);
  });
}
