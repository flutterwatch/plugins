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
  final List<String> openedInApp = <String>[];
  int closeHandoffCalls = 0;
  int closeInAppCalls = 0;

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

  @override
  bool openInApp(String url) {
    final String scheme = Uri.tryParse(url)?.scheme.toLowerCase() ?? '';
    if (scheme != 'http' && scheme != 'https') {
      return false;
    }
    openedInApp.add(url);
    return true;
  }

  @override
  void closeInApp() => closeInAppCalls++;
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
    Future<bool> launchWith(String url, PreferredLaunchMode mode) =>
        launcher.launchUrl(url, LaunchOptions(mode: mode));

    test('the default mode shows a web URL on the watch', () async {
      final bool ok = await launcher.launchUrl(
        'https://flutterwatch.dev',
        const LaunchOptions(),
      );
      expect(ok, isTrue);
      expect(bindings.openedInApp, <String>['https://flutterwatch.dev']);
      expect(bindings.launched, isEmpty);
    });

    test('the default mode hands tel: to the system', () async {
      expect(
        await launchWith('tel:+15551234', PreferredLaunchMode.platformDefault),
        isTrue,
      );
      expect(bindings.launched, <String>['tel:+15551234']);
      expect(bindings.openedInApp, isEmpty);
    });

    test('both in-app modes show a web URL on the watch', () async {
      expect(
        await launchWith(
            'https://a.example', PreferredLaunchMode.inAppBrowserView),
        isTrue,
      );
      expect(
        await launchWith('http://b.example', PreferredLaunchMode.inAppWebView),
        isTrue,
      );
      expect(bindings.openedInApp,
          <String>['https://a.example', 'http://b.example']);
      expect(bindings.launched, isEmpty);
    });

    test('an in-app mode refuses a non-web URL', () async {
      expect(
        await launchWith('tel:+15551234', PreferredLaunchMode.inAppBrowserView),
        isFalse,
      );
      expect(bindings.openedInApp, isEmpty);
      expect(bindings.launched, isEmpty);
    });

    test('externalApplication sends a web URL to the iPhone', () async {
      expect(
        await launchWith('https://flutterwatch.dev',
            PreferredLaunchMode.externalApplication),
        isTrue,
      );
      expect(bindings.launched, <String>['https://flutterwatch.dev']);
      expect(bindings.openedInApp, isEmpty);
    });

    test('externalNonBrowserApplication falls back to externalApplication',
        () async {
      expect(
        await launchWith('https://flutterwatch.dev',
            PreferredLaunchMode.externalNonBrowserApplication),
        isTrue,
      );
      expect(bindings.launched, <String>['https://flutterwatch.dev']);
    });

    test('returns false for an unsupported scheme', () async {
      final bool ok =
          await launcher.launchUrl('ftp://example.com', const LaunchOptions());
      expect(ok, isFalse);
      expect(bindings.launched, isEmpty);
      expect(bindings.openedInApp, isEmpty);
    });

    test('legacy launch() with useSafariVC shows a web URL on the watch',
        () async {
      final bool ok = await launcher.launch(
        'https://flutterwatch.dev',
        useSafariVC: true,
        useWebView: false,
        enableJavaScript: true,
        enableDomStorage: true,
        universalLinksOnly: false,
        headers: const <String, String>{},
      );
      expect(ok, isTrue);
      expect(bindings.openedInApp, <String>['https://flutterwatch.dev']);
    });

    test('legacy launch() without in-app flags sends to the iPhone', () async {
      final bool ok = await launcher.launch(
        'https://flutterwatch.dev',
        useSafariVC: false,
        useWebView: false,
        enableJavaScript: false,
        enableDomStorage: false,
        universalLinksOnly: false,
        headers: const <String, String>{},
      );
      expect(ok, isTrue);
      expect(bindings.launched, <String>['https://flutterwatch.dev']);
      expect(bindings.openedInApp, isEmpty);
    });
  });

  group('modes', () {
    test('supports every mode except externalNonBrowserApplication', () async {
      for (final PreferredLaunchMode mode in <PreferredLaunchMode>[
        PreferredLaunchMode.platformDefault,
        PreferredLaunchMode.inAppWebView,
        PreferredLaunchMode.inAppBrowserView,
        PreferredLaunchMode.externalApplication,
      ]) {
        expect(await launcher.supportsMode(mode), isTrue, reason: '$mode');
      }
      expect(
          await launcher
              .supportsMode(PreferredLaunchMode.externalNonBrowserApplication),
          isFalse);
    });

    test('only the in-app modes can be closed', () async {
      for (final PreferredLaunchMode mode in PreferredLaunchMode.values) {
        final bool inApp = mode == PreferredLaunchMode.inAppWebView ||
            mode == PreferredLaunchMode.inAppBrowserView;
        expect(await launcher.supportsCloseForMode(mode), inApp,
            reason: '$mode');
      }
    });
  });

  test('closeWebView dismisses the browser and withdraws Handoff', () async {
    await launcher.closeWebView();
    expect(bindings.closeInAppCalls, 1);
    expect(bindings.closeHandoffCalls, 1);
  });

  test('linkDelegate is null so the framework uses its default', () {
    expect(launcher.linkDelegate, isNull);
  });
}
