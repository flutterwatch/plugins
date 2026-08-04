// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Runs on a real watch (or the Simulator) against the linked FFI symbols, so
// it proves the native side is present and answering — something the host
// unit tests, which fake the bindings, cannot.
//
// What it deliberately does NOT assert: that a URL actually opened. Neither
// `openSystemURL:` nor Handoff reports completion to the app, and the watch
// has no API to observe the paired phone. Those need a human with a wrist.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('canLaunchUrl (real FFI)', () {
    test('accepts the schemes watchOS can act on', () async {
      expect(await canLaunchUrl(Uri.parse('tel:+15551234567')), isTrue);
      expect(await canLaunchUrl(Uri.parse('sms:+15551234567')), isTrue);
      expect(await canLaunchUrl(Uri.parse('https://flutterwatch.dev')), isTrue);
      expect(await canLaunchUrl(Uri.parse('http://example.com')), isTrue);
    });

    test('refuses schemes with no watchOS mechanism', () async {
      expect(await canLaunchUrl(Uri.parse('mailto:hello@example.com')), isFalse);
      expect(await canLaunchUrl(Uri.parse('ftp://example.com')), isFalse);
    });
  });

  group('launchUrl (real FFI)', () {
    test('a web URL is accepted for Handoff', () async {
      // True means "published as an NSUserActivity", not "opened".
      expect(await launchUrl(Uri.parse('https://flutterwatch.dev')), isTrue);
    });

    test('an unsupported scheme is refused, not silently swallowed', () async {
      // Reports false rather than throwing: the caller gets a definite "this
      // did not happen" instead of an exception to catch.
      expect(await launchUrl(Uri.parse('ftp://example.com')), isFalse);
    });

    test('closeWebView withdraws the Handoff activity without throwing',
        () async {
      await launchUrl(Uri.parse('https://flutterwatch.dev'));
      await closeInAppWebView();
    });
  });
}
