// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host-side unit tests: the native FirebaseAuth backend is faked, asserting
// that the Dart class maps platform-interface calls onto the right FFI
// requests and rebuilds users/credentials/errors from the JSON results.

import 'dart:async';

import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_auth_watchos/firebase_auth_watchos.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseApp;
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _userMap({
  String uid = 'uid-1',
  String? email = 'user@example.com',
  bool isAnonymous = false,
}) {
  return <String, Object?>{
    'uid': uid,
    'email': email,
    'displayName': 'Test User',
    'photoUrl': null,
    'phoneNumber': null,
    'isAnonymous': isAnonymous,
    'isEmailVerified': true,
    'providerId': 'firebase',
    'tenantId': null,
    'refreshToken': null,
    'creationTimestamp': 1700000000000,
    'lastSignInTimestamp': 1700000001000,
    'providerData': <Object?>[
      <String, Object?>{
        'uid': uid,
        'email': email,
        'displayName': 'Test User',
        'photoUrl': null,
        'phoneNumber': null,
        'providerId': 'password',
        'isAnonymous': false,
        'isEmailVerified': false,
      },
    ],
  };
}

class _FakeBindings extends FirebaseAuthWatchosBindings {
  _FakeBindings() : super.forTesting();

  final List<Map<String, Object?>> beginRequests = <Map<String, Object?>>[];
  final List<String> signOutApps = <String>[];

  /// Result the next completed operation resolves to.
  Map<String, Object?> opResult = <String, Object?>{};

  /// How many polls report pending before the result is served.
  int pendingPolls = 0;

  /// The current-user snapshot served to [currentUser].
  Map<String, Object?> snapshot = <String, Object?>{
    'authGeneration': 0,
    'idTokenGeneration': 0,
    'user': null,
  };

  int _nextToken = 1;

  @override
  Map<String, Object?> begin(Map<String, Object?> request) {
    beginRequests.add(request);
    if (opResult.containsKey('error') && opResult['sync'] == true) {
      return opResult;
    }
    return <String, Object?>{'token': _nextToken++};
  }

  @override
  Map<String, Object?> poll(int token) {
    if (pendingPolls > 0) {
      pendingPolls -= 1;
      return <String, Object?>{'pending': true};
    }
    return opResult;
  }

  @override
  Map<String, Object?> currentUser(String appName) => snapshot;

  @override
  Map<String, Object?> signOut(String appName) {
    signOutApps.add(appName);
    snapshot = <String, Object?>{
      'authGeneration': (snapshot['authGeneration']! as int) + 1,
      'idTokenGeneration': (snapshot['idTokenGeneration']! as int) + 1,
      'user': null,
    };
    return <String, Object?>{'ok': true};
  }

  @override
  Map<String, Object?> setLanguageCode(String appName, String code) {
    return <String, Object?>{'languageCode': code.isEmpty ? 'en' : code};
  }

  @override
  Map<String, Object?> isSignInLink(String appName, String link) {
    return <String, Object?>{'value': link.contains('signIn')};
  }
}

// Listens to the stream [changes] returns and collects the uids it emits. The
// subscription is cancelled when the test ends, passed or failed.
List<String?> _listenUids(Stream<UserPlatform?> Function() changes) {
  final List<String?> seen = <String?>[];
  final StreamSubscription<UserPlatform?> subscription =
      changes().listen((UserPlatform? user) => seen.add(user?.uid));
  addTearDown(subscription.cancel);
  return seen;
}

// Serves a native snapshot with both listener counters at [generation], as
// when the SDK's two listeners report the same event, and lets the change
// streams poll it.
Future<void> _report(
  _FakeBindings fake,
  int generation,
  Map<String, Object?>? user,
) {
  fake.snapshot = <String, Object?>{
    'authGeneration': generation,
    'idTokenGeneration': generation,
    'user': user,
  };
  return Future<void>.delayed(const Duration(milliseconds: 30));
}

// A signed-out start, the call the SDK makes to each listener it installs, a
// sign-in, a sign-out and a second call for the same signed-out state: each
// signed-out state is reported once, as firebase_auth 7.x does.
Future<void> _expectSignedOutReportedOnce(
  _FakeBindings fake,
  Stream<UserPlatform?> Function() changes,
) async {
  final List<String?> seen = _listenUids(changes);
  await Future<void>.delayed(const Duration(milliseconds: 20));
  expect(seen, <String?>[null]);

  await _report(fake, 1, null);
  expect(seen, <String?>[null]);

  await _report(fake, 2, _userMap());
  expect(seen, <String?>[null, 'uid-1']);

  await _report(fake, 3, null);
  expect(seen, <String?>[null, 'uid-1', null]);

  await _report(fake, 4, null);
  expect(seen, <String?>[null, 'uid-1', null]);
}

// A signed-in start, then the call the SDK makes to each listener it
// installs: the user is emitted once, as firebase_auth does. A sign-out after
// that call is reported.
Future<void> _expectInstallCallLeftOut(
  _FakeBindings fake,
  Stream<UserPlatform?> Function() changes,
) async {
  fake.snapshot = <String, Object?>{
    'authGeneration': 0,
    'idTokenGeneration': 0,
    'user': _userMap(),
  };
  final List<String?> seen = _listenUids(changes);
  await Future<void>.delayed(const Duration(milliseconds: 20));
  expect(seen, <String?>['uid-1']);

  await _report(fake, 1, _userMap());
  expect(seen, <String?>['uid-1']);

  await _report(fake, 2, null);
  expect(seen, <String?>['uid-1', null]);
}

// A signed-in start and a sign-out before the SDK's install call runs: that
// call reports the signed-out state, and for authStateChanges it is the only
// report, so it is emitted. The sign-out's own report that follows bumps
// only the ID-token counter, as the auth-state listener reports a uid once,
// and is not emitted again.
Future<void> _expectSignOutInInstallCallReported(
  _FakeBindings fake,
  Stream<UserPlatform?> Function() changes,
) async {
  fake.snapshot = <String, Object?>{
    'authGeneration': 0,
    'idTokenGeneration': 0,
    'user': _userMap(),
  };
  final List<String?> seen = _listenUids(changes);
  await Future<void>.delayed(const Duration(milliseconds: 20));
  expect(seen, <String?>['uid-1']);

  await _report(fake, 1, null);
  expect(seen, <String?>['uid-1', null]);

  fake.snapshot = <String, Object?>{
    'authGeneration': 1,
    'idTokenGeneration': 2,
    'user': null,
  };
  await Future<void>.delayed(const Duration(milliseconds: 30));
  expect(seen, <String?>['uid-1', null]);
}

void main() {
  late _FakeBindings fake;
  late FirebaseAuthWatchos auth;

  setUp(() {
    fake = _FakeBindings();
    FirebaseAuthWatchos.bindingsOverride = fake;
    FirebaseAuthWatchos.opPollInterval = const Duration(milliseconds: 1);
    FirebaseAuthWatchos.streamPollInterval = const Duration(milliseconds: 5);
    auth = FirebaseAuthWatchos();
  });

  tearDown(() {
    FirebaseAuthWatchos.bindingsOverride = null;
  });

  test('registerWith installs the platform instance', () {
    FirebaseAuthWatchos.registerWith();
    expect(FirebaseAuthPlatform.instance, isA<FirebaseAuthWatchos>());
  });

  test('currentUser is null when the native SDK has no user', () {
    expect(auth.currentUser, isNull);
  });

  test('currentUser rebuilds the native user snapshot', () {
    fake.snapshot = <String, Object?>{
      'authGeneration': 1,
      'idTokenGeneration': 1,
      'user': _userMap(),
    };
    final UserPlatform user = auth.currentUser!;
    expect(user.uid, 'uid-1');
    expect(user.email, 'user@example.com');
    expect(user.displayName, 'Test User');
    expect(user.isEmailVerified, isTrue);
    expect(user.isAnonymous, isFalse);
    expect(user.metadata.creationTime,
        DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true));
    expect(user.providerData, hasLength(1));
    expect(user.providerData.single.providerId, 'password');
  });

  test('signInWithEmailAndPassword sends the request and parses the result',
      () async {
    fake.pendingPolls = 2;
    fake.opResult = <String, Object?>{
      'user': _userMap(),
      'additionalUserInfo': <String, Object?>{
        'isNewUser': false,
        'providerId': 'password',
        'username': null,
        'profile': null,
      },
    };
    final UserCredentialPlatform credential =
        await auth.signInWithEmailAndPassword('user@example.com', 'secret');
    expect(fake.beginRequests.single, <String, Object?>{
      'op': 'signInWithEmailAndPassword',
      'email': 'user@example.com',
      'password': 'secret',
      'app': '[DEFAULT]',
    });
    expect(credential.user!.uid, 'uid-1');
    expect(credential.additionalUserInfo!.isNewUser, isFalse);
    expect(credential.additionalUserInfo!.providerId, 'password');
  });

  test('a native auth error surfaces as FirebaseAuthException', () async {
    fake.opResult = <String, Object?>{
      'error': 'The password is invalid.',
      'code': 'wrong-password',
      'email': 'user@example.com',
    };
    await expectLater(
      auth.signInWithEmailAndPassword('user@example.com', 'nope'),
      throwsA(isA<FirebaseAuthException>()
          .having((FirebaseAuthException e) => e.code, 'code', 'wrong-password')
          .having((FirebaseAuthException e) => e.email, 'email',
              'user@example.com')),
    );
  });

  test('signInAnonymously resolves to an anonymous user', () async {
    fake.opResult = <String, Object?>{
      'user': _userMap(uid: 'anon-1', email: null, isAnonymous: true),
      'additionalUserInfo': null,
    };
    final UserCredentialPlatform credential = await auth.signInAnonymously();
    expect(credential.user!.isAnonymous, isTrue);
    expect(fake.beginRequests.single['op'], 'signInAnonymously');
  });

  test('signInWithCredential supports email/password credentials only',
      () async {
    fake.opResult = <String, Object?>{'user': _userMap()};
    await auth.signInWithCredential(
        EmailAuthProvider.credential(email: 'u@e.com', password: 'pw'));
    expect(fake.beginRequests.single['op'], 'signInWithEmailAndPassword');
    expect(
      () => auth
          .signInWithCredential(GoogleAuthProvider.credential(idToken: 't')),
      throwsUnimplementedError,
    );
  });

  test('signOut delegates to the native instance', () async {
    await auth.signOut();
    expect(fake.signOutApps, <String>['[DEFAULT]']);
  });

  test('getIdToken and getIdTokenResult parse the token payload', () async {
    fake.snapshot = <String, Object?>{
      'authGeneration': 1,
      'idTokenGeneration': 1,
      'user': _userMap(),
    };
    fake.opResult = <String, Object?>{
      'token': 'jwt-token',
      'expirationTimestamp': 1700003600000,
      'authTimestamp': 1700000000000,
      'issuedAtTimestamp': 1700000000000,
      'signInProvider': 'password',
      'signInSecondFactor': null,
      'claims': <String, Object?>{'admin': true},
    };
    final UserPlatform user = auth.currentUser!;
    expect(await user.getIdToken(true), 'jwt-token');
    expect(fake.beginRequests.last['op'], 'getIdToken');
    expect(fake.beginRequests.last['forceRefresh'], isTrue);
    final IdTokenResult result = await user.getIdTokenResult(false);
    expect(result.token, 'jwt-token');
    expect(result.signInProvider, 'password');
    expect(result.claims, containsPair('admin', true));
  });

  test('updateProfile sends explicit presence flags', () async {
    fake.snapshot = <String, Object?>{
      'authGeneration': 1,
      'idTokenGeneration': 1,
      'user': _userMap(),
    };
    fake.opResult = <String, Object?>{'ok': true};
    await auth.currentUser!
        .updateProfile(<String, String?>{'displayName': 'New Name'});
    final Map<String, Object?> request = fake.beginRequests.single;
    expect(request['op'], 'updateProfile');
    expect(request['hasDisplayName'], isTrue);
    expect(request['displayName'], 'New Name');
    expect(request['hasPhotoUrl'], isFalse);
  });

  test('updateProfile forwards an explicit null', () async {
    fake.snapshot = <String, Object?>{
      'authGeneration': 1,
      'idTokenGeneration': 1,
      'user': _userMap(),
    };
    fake.opResult = <String, Object?>{'ok': true};
    // firebase_auth 7.x passes only the fields it is given, so a null it is
    // given reaches the platform as a key with a null value.
    await auth.currentUser!.updateProfile(<String, String?>{'photoURL': null});
    final Map<String, Object?> request = fake.beginRequests.single;
    expect(request['op'], 'updateProfile');
    expect(request['hasPhotoUrl'], isTrue);
    expect(request['photoUrl'], isNull);
    expect(request['hasDisplayName'], isFalse);
  });

  test('sendPasswordResetEmail completes on ok', () async {
    fake.opResult = <String, Object?>{'ok': true};
    await auth.sendPasswordResetEmail('user@example.com');
    expect(fake.beginRequests.single['op'], 'sendPasswordResetEmail');
    expect(fake.beginRequests.single['email'], 'user@example.com');
  });

  test('authStateChanges emits the current user, then on generation change',
      () async {
    // The listeners were installed, and the SDK made its first call to each,
    // before this subscription.
    fake.snapshot = <String, Object?>{
      'authGeneration': 1,
      'idTokenGeneration': 1,
      'user': null,
    };
    final List<String?> seen = _listenUids(auth.authStateChanges);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(seen, <String?>[null]);

    fake.snapshot = <String, Object?>{
      'authGeneration': 2,
      'idTokenGeneration': 2,
      'user': _userMap(),
    };
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(seen, <String?>[null, 'uid-1']);

    // An idToken-only change must not re-emit on authStateChanges.
    fake.snapshot = <String, Object?>{
      'authGeneration': 2,
      'idTokenGeneration': 3,
      'user': _userMap(),
    };
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(seen, <String?>[null, 'uid-1']);
  });

  test('authStateChanges reports a signed-out state once', () async {
    await _expectSignedOutReportedOnce(fake, auth.authStateChanges);
  });

  test('idTokenChanges reports a signed-out state once', () async {
    await _expectSignedOutReportedOnce(fake, auth.idTokenChanges);
  });

  test('userChanges reports a signed-out state once', () async {
    await _expectSignedOutReportedOnce(fake, auth.userChanges);
  });

  test('authStateChanges leaves out the listener install call', () async {
    await _expectInstallCallLeftOut(fake, auth.authStateChanges);
  });

  test('idTokenChanges leaves out the listener install call', () async {
    await _expectInstallCallLeftOut(fake, auth.idTokenChanges);
  });

  test('userChanges leaves out the listener install call', () async {
    await _expectInstallCallLeftOut(fake, auth.userChanges);
  });

  test('authStateChanges reports a sign-out the install call carries',
      () async {
    await _expectSignOutInInstallCallReported(fake, auth.authStateChanges);
  });

  test('idTokenChanges reports a sign-out the install call carries', () async {
    await _expectSignOutInInstallCallReported(fake, auth.idTokenChanges);
  });

  test('userChanges reports a sign-out the install call carries', () async {
    await _expectSignOutInInstallCallReported(fake, auth.userChanges);
  });

  test('delegateFor returns one instance per app', () {
    FirebaseAuthWatchos.registerWith();
    final TestFirebaseApp app = TestFirebaseApp('secondary');
    final FirebaseAuthPlatform delegate = auth.delegateFor(app: app);
    expect(delegate, isA<FirebaseAuthWatchos>());
    expect(identical(auth.delegateFor(app: app), delegate), isTrue);
  });
}

/// Minimal FirebaseApp stand-in for delegateFor tests.
class TestFirebaseApp implements FirebaseApp {
  TestFirebaseApp(this.name);

  @override
  final String name;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
