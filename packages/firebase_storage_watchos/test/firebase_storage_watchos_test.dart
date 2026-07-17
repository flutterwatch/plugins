// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Host-side unit tests: the native FirebaseStorage backend is faked,
// asserting that the Dart class maps platform-interface calls onto the right
// FFI requests and rebuilds metadata/tasks/errors from the JSON results.

import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:firebase_storage_platform_interface/firebase_storage_platform_interface.dart';
import 'package:firebase_storage_watchos/firebase_storage_watchos.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBindings extends FirebaseStorageWatchosBindings {
  _FakeBindings() : super.forTesting();

  final List<Map<String, Object?>> beginRequests = <Map<String, Object?>>[];
  final List<Map<String, Object?>> taskRequests = <Map<String, Object?>>[];
  final List<(int, String)> controls = <(int, String)>[];

  Map<String, Object?> opResult = <String, Object?>{};
  int pendingPolls = 0;

  /// Scripted task snapshots, served in order (last one repeats).
  List<Map<String, Object?>> taskSnapshots = <Map<String, Object?>>[];
  int _snapshotIndex = 0;

  int _nextId = 1;

  @override
  Map<String, Object?> begin(Map<String, Object?> request) {
    beginRequests.add(request);
    return <String, Object?>{'token': _nextId++};
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
  Map<String, Object?> taskStart(Map<String, Object?> request) {
    taskRequests.add(request);
    return <String, Object?>{'taskId': _nextId++};
  }

  @override
  Map<String, Object?> taskSnapshot(int taskId) {
    if (taskSnapshots.isEmpty) {
      return <String, Object?>{
        'state': 'running',
        'bytesTransferred': 0,
        'totalBytes': 0,
      };
    }
    final Map<String, Object?> snapshot =
        taskSnapshots[_snapshotIndex.clamp(0, taskSnapshots.length - 1)];
    if (_snapshotIndex < taskSnapshots.length - 1) {
      _snapshotIndex += 1;
    }
    return snapshot;
  }

  @override
  Map<String, Object?> taskControl(int taskId, String action) {
    controls.add((taskId, action));
    return <String, Object?>{'value': true};
  }

  @override
  Map<String, Object?> configure(Map<String, Object?> request) {
    beginRequests.add(request);
    return <String, Object?>{'ok': true};
  }
}

void main() {
  late _FakeBindings fake;
  late FirebaseStorageWatchos storage;

  setUp(() {
    fake = _FakeBindings();
    FirebaseStorageWatchos.bindingsOverride = fake;
    FirebaseStorageWatchos.opPollInterval = const Duration(milliseconds: 1);
    storage = FirebaseStorageWatchos(bucket: 'test-bucket');
  });

  tearDown(() {
    FirebaseStorageWatchos.bindingsOverride = null;
  });

  test('registerWith installs the platform instance', () {
    FirebaseStorageWatchos.registerWith();
    expect(FirebaseStoragePlatform.instance, isA<FirebaseStorageWatchos>());
  });

  test('getDownloadURL sends the reference path and parses the URL', () async {
    fake.pendingPolls = 1;
    fake.opResult = <String, Object?>{'url': 'https://example.com/o/file'};
    final String url = await storage.ref('path/to/file.txt').getDownloadURL();
    expect(url, 'https://example.com/o/file');
    expect(fake.beginRequests.single, <String, Object?>{
      'app': '[DEFAULT]',
      'bucket': 'test-bucket',
      'op': 'getDownloadURL',
      'path': 'path/to/file.txt',
    });
  });

  test('getMetadata rebuilds FullMetadata from the native map', () async {
    fake.opResult = <String, Object?>{
      'metadata': <String, Object?>{
        'bucket': 'test-bucket',
        'fullPath': 'path/to/file.txt',
        'name': 'file.txt',
        'size': 42,
        'contentType': 'text/plain',
        'generation': '123',
        'creationTimeMillis': 1700000000000,
      },
    };
    final FullMetadata metadata =
        await storage.ref('path/to/file.txt').getMetadata();
    expect(metadata.name, 'file.txt');
    expect(metadata.size, 42);
    expect(metadata.contentType, 'text/plain');
    expect(metadata.generation, '123');
  });

  test('a native storage error surfaces as FirebaseException', () async {
    fake.opResult = <String, Object?>{
      'error': 'Object does not exist.',
      'code': 'object-not-found',
    };
    await expectLater(
      storage.ref('missing.txt').getDownloadURL(),
      throwsA(isA<FirebaseException>()
          .having((FirebaseException e) => e.code, 'code', 'object-not-found')
          .having((FirebaseException e) => e.plugin, 'plugin',
              'firebase_storage')),
    );
  });

  test('getData decodes the base64 payload', () async {
    fake.opResult = <String, Object?>{'data': base64Encode(<int>[1, 2, 3])};
    final Uint8List? data = await storage.ref('bin').getData(1024);
    expect(data, <int>[1, 2, 3]);
    expect(fake.beginRequests.single['maxSize'], 1024);
  });

  test('list parses items, prefixes, and the page token', () async {
    fake.opResult = <String, Object?>{
      'items': <Object?>['a/1.txt', 'a/2.txt'],
      'prefixes': <Object?>['a/b'],
      'nextPageToken': 'token-1',
    };
    final ListResultPlatform result = await storage
        .ref('a')
        .list(const ListOptions(maxResults: 50, pageToken: 'token-0'));
    expect(result.items.map((ReferencePlatform r) => r.fullPath),
        <String>['a/1.txt', 'a/2.txt']);
    expect(result.prefixes.single.fullPath, 'a/b');
    expect(result.nextPageToken, 'token-1');
    expect(fake.beginRequests.single['maxResults'], 50);
    expect(fake.beginRequests.single['pageToken'], 'token-0');
  });

  test('putData starts a native task with base64 payload and metadata', () {
    storage.ref('up.txt').putData(
          Uint8List.fromList(utf8.encode('hello')),
          SettableMetadata(contentType: 'text/plain'),
        );
    final Map<String, Object?> request = fake.taskRequests.single;
    expect(request['kind'], 'putData');
    expect(request['path'], 'up.txt');
    expect(request['data'], base64Encode(utf8.encode('hello')));
    expect((request['metadata']! as Map)['contentType'], 'text/plain');
  });

  test('putString raw uploads the utf8 bytes', () {
    storage.ref('s.txt').putString('hi', PutStringFormat.raw);
    expect(fake.taskRequests.single['data'], base64Encode(utf8.encode('hi')));
  });

  test('task onComplete resolves on the success snapshot', () async {
    fake.taskSnapshots = <Map<String, Object?>>[
      <String, Object?>{
        'state': 'running',
        'bytesTransferred': 1,
        'totalBytes': 5,
      },
      <String, Object?>{
        'state': 'success',
        'bytesTransferred': 5,
        'totalBytes': 5,
        'metadata': <String, Object?>{'fullPath': 'up.txt', 'size': 5},
      },
    ];
    final TaskPlatform task =
        storage.ref('up.txt').putData(Uint8List.fromList(<int>[1]));
    final TaskSnapshotPlatform snapshot = await task.onComplete;
    expect(snapshot.state, TaskState.success);
    expect(snapshot.bytesTransferred, 5);
    expect(snapshot.totalBytes, 5);
    expect(snapshot.metadata!.size, 5);
  });

  test('snapshotEvents emits progress and closes on the terminal state',
      () async {
    fake.taskSnapshots = <Map<String, Object?>>[
      <String, Object?>{
        'state': 'running',
        'bytesTransferred': 1,
        'totalBytes': 5,
      },
      <String, Object?>{
        'state': 'running',
        'bytesTransferred': 3,
        'totalBytes': 5,
      },
      <String, Object?>{
        'state': 'success',
        'bytesTransferred': 5,
        'totalBytes': 5,
      },
    ];
    final TaskPlatform task =
        storage.ref('up.txt').putData(Uint8List.fromList(<int>[1]));
    final List<TaskSnapshotPlatform> seen =
        await task.snapshotEvents.toList();
    expect(seen.map((TaskSnapshotPlatform s) => s.bytesTransferred),
        <int>[1, 3, 5]);
    expect(seen.last.state, TaskState.success);
  });

  test('a failed task throws the mapped storage error from onComplete',
      () async {
    fake.taskSnapshots = <Map<String, Object?>>[
      <String, Object?>{
        'state': 'error',
        'bytesTransferred': 0,
        'totalBytes': 5,
        'error': <String, Object?>{
          'error': 'Not authorized.',
          'code': 'unauthorized',
        },
      },
    ];
    final TaskPlatform task =
        storage.ref('up.txt').putData(Uint8List.fromList(<int>[1]));
    await expectLater(
      task.onComplete,
      throwsA(isA<FirebaseException>()
          .having((FirebaseException e) => e.code, 'code', 'unauthorized')),
    );
  });

  test('pause/resume/cancel forward to the native task', () async {
    final TaskPlatform task =
        storage.ref('up.txt').putData(Uint8List.fromList(<int>[1]));
    await task.pause();
    await task.resume();
    await task.cancel();
    expect(fake.controls.map(((int, String) c) => c.$2),
        <String>['pause', 'resume', 'cancel']);
  });

  test('useStorageEmulator configures the native instance', () async {
    await storage.useStorageEmulator('localhost', 9199);
    expect(fake.beginRequests.single, <String, Object?>{
      'app': '[DEFAULT]',
      'bucket': 'test-bucket',
      'op': 'useEmulator',
      'host': 'localhost',
      'port': 9199,
    });
    expect(storage.emulatorHost, 'localhost');
    expect(storage.emulatorPort, 9199);
  });

  test('retry-time setters update the native instance and the getters', () {
    storage.setMaxUploadRetryTime(30000);
    expect(storage.maxUploadRetryTime, 30000);
    expect(fake.beginRequests.single['op'], 'setMaxUploadRetryTime');
    expect(fake.beginRequests.single['milliseconds'], 30000);
  });
}
