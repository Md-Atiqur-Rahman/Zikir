import 'dart:convert';

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
    await expectLater(
      fetchLatest(client: fake(403, {'message': 'rate limit'})),
      throwsA(contains('403')),
    );
    await expectLater(
      fetchLatest(client: fake(200, release('nightly'))),
      throwsA(contains('no APK')),
    );
    await expectLater(
      fetchLatest(client: fake(200, release('build-9', assets: ['notes.txt']))),
      throwsA(contains('no APK')),
    );
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
