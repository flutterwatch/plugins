// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:url_launcher_watchos/url_launcher_watchos.dart';

/// Fake bindings that record calls instead of touching FFI, and model the
/// native scheme rules so the Dart layer can be checked against them.
class _FakeBindings extends UrlLauncherWatchosBindings {
  _FakeBindings() : super.forTesting();

  final List<String> launched = <String>[];
  int closeHandoffCalls = 0;

  static const Set<String> _supported = <String>{'tel', 'sms', 'http', 'https'};

  static bool _supports(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || uri.scheme.isEmpty) {
      return false;
    }
    return _supported.contains(uri.scheme.toLowerCase());
  }

  @override
  bool canLaunch(String url) => _supports(url);

  @override
  bool launch(String url) {
    if (!_supports(url)) {
      return false;
    }
    launched.add(url);
    return true;
  }

  @override
  void closeHandoff() => closeHandoffCalls++;
}

void main() {
  late _FakeBindings bindings;
  late UrlLauncherWatchos launcher;

  setUp(() {
    bindings = _FakeBindings();
    UrlLauncherWatchos.bindingsOverride = bindings;
    launcher = UrlLauncherWatchos();
  });

  tearDown(() => UrlLauncherWatchos.bindingsOverride = null);

  test('registerWith installs itself as the platform instance', () {
    UrlLauncherWatchos.registerWith();
    expect(UrlLauncherPlatform.instance, isA<UrlLauncherWatchos>());
  });

  group('canLaunch', () {
    test('accepts the schemes watchOS can act on', () async {
      expect(await launcher.canLaunch('tel:+15551234'), isTrue);
      expect(await launcher.canLaunch('sms:+15551234'), isTrue);
      expect(await launcher.canLaunch('https://flutterwatch.dev'), isTrue);
      expect(await launcher.canLaunch('http://example.com'), isTrue);
    });

    test('refuses schemes with no watchOS mechanism', () async {
      // mailto: is deliberately absent: openSystemURL does not own it and
      // returns void, so claiming success would be a lie.
      expect(await launcher.canLaunch('mailto:a@b.com'), isFalse);
      expect(await launcher.canLaunch('file:///tmp/x'), isFalse);
      expect(await launcher.canLaunch('not a url'), isFalse);
    });
  });

  group('launchUrl', () {
    test('hands a supported URL to the native side', () async {
      final bool ok = await launcher.launchUrl(
        'https://flutterwatch.dev',
        const LaunchOptions(),
      );
      expect(ok, isTrue);
      expect(bindings.launched, <String>['https://flutterwatch.dev']);
    });

    test('returns false for an unsupported scheme', () async {
      final bool ok =
          await launcher.launchUrl('ftp://example.com', const LaunchOptions());
      expect(ok, isFalse);
      expect(bindings.launched, isEmpty);
    });

    test('legacy launch() ignores the webview flags', () async {
      final bool ok = await launcher.launch(
        'https://flutterwatch.dev',
        useSafariVC: true,
        useWebView: true,
        enableJavaScript: true,
        enableDomStorage: true,
        universalLinksOnly: false,
        headers: const <String, String>{},
      );
      expect(ok, isTrue);
      expect(bindings.launched, <String>['https://flutterwatch.dev']);
    });
  });

  group('modes', () {
    test('supports only the modes that can exist on a watch', () async {
      expect(await launcher.supportsMode(PreferredLaunchMode.platformDefault),
          isTrue);
      expect(
          await launcher.supportsMode(PreferredLaunchMode.externalApplication),
          isTrue);
      expect(
          await launcher.supportsMode(PreferredLaunchMode.inAppWebView), isFalse);
      expect(
          await launcher.supportsMode(PreferredLaunchMode.inAppBrowserView),
          isFalse);
    });

    test('nothing can be closed', () async {
      for (final PreferredLaunchMode mode in PreferredLaunchMode.values) {
        expect(await launcher.supportsCloseForMode(mode), isFalse);
      }
    });
  });

  test('closeWebView withdraws the Handoff activity', () async {
    await launcher.closeWebView();
    expect(bindings.closeHandoffCalls, 1);
  });

  test('linkDelegate is null so the framework uses its default', () {
    expect(launcher.linkDelegate, isNull);
  });
}
