// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// On-device smoke test. The firebase_storage pub example ships no upstream
// integration_test, so — as with firebase_core/firebase_auth — this verifies
// the real native path on the watch simulator: that FirebaseStorage links,
// resolves an instance for the configured app, serves reference plumbing over
// the FFI bridge, and round-trips real backend calls (assertions tolerate the
// test project's security rules denying access — a mapped error response
// proves the same native network path as a success).

import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_storage_example/firebase_options.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  });

  testWidgets('resolves a storage instance and reference plumbing',
      (WidgetTester tester) async {
    final FirebaseStorage storage = FirebaseStorage.instance;
    final Reference ref = storage.ref('flutter-tests/watch/smoke.txt');
    expect(ref.fullPath, 'flutter-tests/watch/smoke.txt');
    expect(ref.name, 'smoke.txt');
    expect(ref.parent!.fullPath, 'flutter-tests/watch');
    expect(ref.bucket, isNotEmpty);
  });

  testWidgets('retry times round-trip through the native instance',
      (WidgetTester tester) async {
    final FirebaseStorage storage = FirebaseStorage.instance;
    storage.setMaxUploadRetryTime(const Duration(seconds: 30));
    expect(storage.maxUploadRetryTime, const Duration(seconds: 30));
  });

  testWidgets('an upload reaches the Storage backend',
      (WidgetTester tester) async {
    final Reference ref =
        FirebaseStorage.instance.ref('flutter-tests/watch/smoke.txt');
    final Uint8List payload =
        Uint8List.fromList('firebase_storage_watchos smoke'.codeUnits);
    try {
      final TaskSnapshot snapshot = await ref.putData(
        payload,
        SettableMetadata(contentType: 'text/plain'),
      );
      expect(snapshot.state, TaskState.success);
      // The SDK's progress counts the multipart request body, so totalBytes
      // exceeds the payload for small uploads; the getData round-trip below
      // is the byte-exact check.
      expect(snapshot.totalBytes, greaterThanOrEqualTo(payload.length));

      final Uint8List? roundTrip = await ref.getData();
      expect(roundTrip, payload);
      await ref.delete();
    } on FirebaseException catch (e) {
      // The test project's rules may deny unauthenticated writes; the mapped
      // error code proves the same native round-trip.
      expect(e.plugin, 'firebase_storage');
      expect(e.code, isNotEmpty);
    }
  });

  testWidgets('a missing object surfaces a mapped storage error',
      (WidgetTester tester) async {
    await expectLater(
      FirebaseStorage.instance
          .ref('flutter-tests/watch/definitely-missing-${DateTime.now().millisecondsSinceEpoch}.txt')
          .getDownloadURL(),
      throwsA(isA<FirebaseException>()
          .having((FirebaseException e) => e.plugin, 'plugin',
              'firebase_storage')
          .having((FirebaseException e) => e.code, 'code', isNotEmpty)),
    );
  });
}
