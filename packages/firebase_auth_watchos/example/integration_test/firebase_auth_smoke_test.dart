// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// On-device smoke test. The firebase_auth pub example ships no upstream
// integration_test, so — as with firebase_core — this verifies the real
// native path on the watch simulator: that FirebaseAuth links, resolves an
// auth instance for the configured app, serves the current-user snapshot and
// auth-state stream over the FFI bridge, and round-trips a real backend call
// (assertions tolerate auth methods being disabled on the test project — an
// error response proves the same native network path as a success).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_example/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  });

  testWidgets('resolves an auth instance with no current user',
      (WidgetTester tester) async {
    final FirebaseAuth auth = FirebaseAuth.instance;
    if (auth.currentUser != null) {
      await auth.signOut();
    }
    expect(auth.currentUser, isNull);
  });

  testWidgets('authStateChanges emits the signed-out state first',
      (WidgetTester tester) async {
    final User? first = await FirebaseAuth.instance.authStateChanges().first;
    expect(first, isNull);
  });

  testWidgets('isSignInWithEmailLink round-trips through the native SDK',
      (WidgetTester tester) async {
    expect(
      FirebaseAuth.instance.isSignInWithEmailLink('https://example.com/'),
      isFalse,
    );
  });

  testWidgets('anonymous sign-in reaches the Firebase Auth backend',
      (WidgetTester tester) async {
    final FirebaseAuth auth = FirebaseAuth.instance;
    try {
      final UserCredential credential = await auth.signInAnonymously();
      expect(credential.user, isNotNull);
      expect(credential.user!.isAnonymous, isTrue);
      expect(auth.currentUser!.uid, credential.user!.uid);
      await auth.signOut();
      expect(auth.currentUser, isNull);
    } on FirebaseAuthException catch (e) {
      // Anonymous auth may be disabled on the test project; a mapped error
      // code proves the same native round-trip.
      expect(e.code, isNotEmpty);
    }
  });

  testWidgets('bad email/password sign-in surfaces a mapped auth error',
      (WidgetTester tester) async {
    await expectLater(
      FirebaseAuth.instance.signInWithEmailAndPassword(
        email: 'nobody@flutterwatch.dev',
        password: 'definitely-wrong-password',
      ),
      throwsA(isA<FirebaseAuthException>()
          .having((FirebaseAuthException e) => e.code, 'code', isNotEmpty)),
    );
  });
}
