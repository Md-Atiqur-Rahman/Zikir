import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Newest GitHub Release of the app; every release is tagged `build-<number>`.
const _latestUrl =
    'https://api.github.com/repos/Md-Atiqur-Rahman/Zikir/releases/latest';

class UpdateInfo {
  final int build;
  final String url; // direct download of the APK
  final DateTime? published;
  const UpdateInfo(this.build, this.url, this.published);
}

/// 'build-12' -> 12, anything else -> null.
int? buildFromTag(String tag) {
  final m = RegExp(r'^build-(\d+)$').firstMatch(tag.trim());
  return m == null ? null : int.parse(m.group(1)!);
}

/// Asks GitHub for the newest release. Throws a readable message when it can't.
Future<UpdateInfo> fetchLatest({http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final r = await c
        .get(
          Uri.parse(_latestUrl),
          headers: {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw 'GitHub answered with code ${r.statusCode}';
    }
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final build = buildFromTag((j['tag_name'] as String?) ?? '');
    final assets = ((j['assets'] as List?) ?? const []).cast<Map>();
    final apk = assets.where((a) => '${a['name']}'.endsWith('.apk'));
    if (build == null || apk.isEmpty) {
      throw 'The latest release has no APK file';
    }
    return UpdateInfo(
      build,
      '${apk.first['browser_download_url']}',
      DateTime.tryParse('${j['published_at']}'),
    );
  } on TimeoutException {
    throw 'No answer from GitHub. Check your internet.';
  } finally {
    if (client == null) c.close();
  }
}

Future<int> installedBuild() async {
  final info = await PackageInfo.fromPlatform();
  return int.tryParse(info.buildNumber) ?? 0;
}

/// Check for a newer build, download it and hand it to Android's installer.
class UpdatePage extends StatefulWidget {
  /// Overridable so the page can be tested without the network.
  final Future<UpdateInfo> Function()? fetch;
  final Future<int> Function()? installed;
  const UpdatePage({super.key, this.fetch, this.installed});

  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

enum _Phase { checking, upToDate, available, downloading, installing, error }

class _UpdatePageState extends State<UpdatePage> {
  _Phase _phase = _Phase.checking;
  int _installed = 0;
  UpdateInfo? _latest;
  String _error = '';
  double? _progress; // 0..1 while downloading
  StreamSubscription<OtaEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => _phase = _Phase.checking);
    try {
      final installed = await (widget.installed ?? installedBuild)();
      final latest = await (widget.fetch ?? fetchLatest)();
      if (!mounted) return;
      setState(() {
        _installed = installed;
        _latest = latest;
        _phase = latest.build > installed ? _Phase.available : _Phase.upToDate;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _phase = _Phase.error;
      });
    }
  }

  void _update() {
    final latest = _latest!;
    if (kIsWeb) {
      setState(() {
        _error = 'Updating works only in the Android app.';
        _phase = _Phase.error;
      });
      return;
    }
    setState(() {
      _phase = _Phase.downloading;
      _progress = null;
    });
    _sub?.cancel();
    _sub = OtaUpdate()
        .execute(
          latest.url,
          destinationFilename: 'Zikir-build-${latest.build}.apk',
        )
        .listen(
          (event) {
            if (!mounted) return;
            switch (event.status) {
              case OtaStatus.DOWNLOADING:
                final pct = int.tryParse(event.value ?? '');
                setState(() {
                  _phase = _Phase.downloading;
                  _progress = pct == null ? null : pct / 100;
                });
              case OtaStatus.INSTALLING:
              case OtaStatus.INSTALLATION_DONE:
                setState(() => _phase = _Phase.installing);
              case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                setState(() {
                  _error = 'Permission was not given. Allow Zikir to install apps, then try again.';
                  _phase = _Phase.error;
                });
              case OtaStatus.DOWNLOAD_ERROR:
                setState(() {
                  _error =
                      'The download failed. Check your internet and try again.';
                  _phase = _Phase.error;
                });
              default:
                setState(() {
                  _error =
                      'The update could not be installed (${event.status.name}).';
                  _phase = _Phase.error;
                });
            }
          },
          onError: (Object e) {
            if (!mounted) return;
            setState(() {
              _error = '$e';
              _phase = _Phase.error;
            });
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = _latest;

    final (IconData icon, String title, String body) = switch (_phase) {
      _Phase.checking => (
        Icons.sync,
        'Checking...',
        'Asking GitHub for the newest version.',
      ),
      _Phase.upToDate => (
        Icons.check_circle_outline,
        'You are up to date',
        'Installed: build $_installed',
      ),
      _Phase.available => (
        Icons.system_update,
        'Update available',
        'Installed: build $_installed\nNew: build ${latest?.build}'
            '${latest?.published == null ? '' : '  (${DateFormat('d MMM yyyy').format(latest!.published!.toLocal())})'}',
      ),
      _Phase.downloading => (
        Icons.downloading,
        'Downloading build ${latest?.build}...',
        _progress == null ? '' : '${(_progress! * 100).round()}%',
      ),
      _Phase.installing => (
        Icons.install_mobile,
        'Opening the installer',
        'Tap Install on the screen Android shows. Your counts and settings are kept.',
      ),
      _Phase.error => (Icons.error_outline, 'Could not update', _error),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Check for update')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            if (_phase == _Phase.checking) const CircularProgressIndicator(),
            if (_phase == _Phase.downloading)
              LinearProgressIndicator(value: _progress, minHeight: 8),
            if (_phase == _Phase.available) ...[
              FilledButton.icon(
                onPressed: _update,
                icon: const Icon(Icons.download),
                label: const Text('Update now'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Android may ask you to allow Zikir to install apps the first time.',
                textAlign: TextAlign.center,
              ),
            ],
            if (_phase == _Phase.upToDate || _phase == _Phase.error)
              OutlinedButton.icon(
                onPressed: _check,
                icon: const Icon(Icons.refresh),
                label: const Text('Check again'),
              ),
          ],
        ),
      ),
    );
  }
}
