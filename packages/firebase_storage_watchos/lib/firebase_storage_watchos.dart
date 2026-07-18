// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `firebase_storage`, implemented over dart:ffi.
//
// Method-channel plugins are not supported on watchOS, so this package
// follows the FFI plugin model: `watchos/Classes/firebase_storage_watchos_ffi.m`
// bridges the Firebase Apple SDK (`FirebaseStorage`, linked via the SwiftPM
// dependency declared in `watchos/Package.swift`) behind C symbols returning
// JSON, the CLI force-loads the compiled archive into the watch binary, and
// this class resolves the symbols via `DynamicLibrary.process()`.
//
// Storage operations are network-backed, so the bridge is asynchronous:
// one-shot operations use a begin/poll token, and uploads/downloads run as
// native tasks whose latest snapshot the Dart side polls for progress.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage_platform_interface/firebase_storage_platform_interface.dart';

/// FFI bindings to the native firebase_storage_watchos C functions.
///
/// Each method marshals its arguments into C strings, calls the native
/// function, copies the returned JSON, frees the native buffer, and decodes
/// it. Overridable for tests via [FirebaseStorageWatchos.bindingsOverride]:
/// the [FirebaseStorageWatchosBindings.forTesting] constructor skips FFI
/// initialization so fakes work off-device.
class FirebaseStorageWatchosBindings {
  /// Creates bindings that look up native symbols in the current process.
  FirebaseStorageWatchosBindings() : _lib = DynamicLibrary.process();

  /// Constructor for fakes/mocks — skips FFI initialization.
  FirebaseStorageWatchosBindings.forTesting() : _lib = null;

  final DynamicLibrary? _lib;

  late final Pointer<Utf8> Function(Pointer<Utf8>) _begin = _lib!
      .lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Utf8>)>('firebase_storage_watchos_begin');

  late final Pointer<Utf8> Function(int) _poll = _lib!.lookupFunction<
      Pointer<Utf8> Function(Int64),
      Pointer<Utf8> Function(int)>('firebase_storage_watchos_poll');

  late final Pointer<Utf8> Function(Pointer<Utf8>) _taskStart =
      _lib!.lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>),
              Pointer<Utf8> Function(Pointer<Utf8>)>(
          'firebase_storage_watchos_task_start');

  late final Pointer<Utf8> Function(int) _taskSnapshot = _lib!.lookupFunction<
      Pointer<Utf8> Function(Int64),
      Pointer<Utf8> Function(int)>('firebase_storage_watchos_task_snapshot');

  late final Pointer<Utf8> Function(int, Pointer<Utf8>) _taskControl =
      _lib!.lookupFunction<Pointer<Utf8> Function(Int64, Pointer<Utf8>),
              Pointer<Utf8> Function(int, Pointer<Utf8>)>(
          'firebase_storage_watchos_task_control');

  late final Pointer<Utf8> Function(Pointer<Utf8>) _configure =
      _lib!.lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>),
              Pointer<Utf8> Function(Pointer<Utf8>)>(
          'firebase_storage_watchos_configure');

  late final void Function(Pointer<Utf8>) _free = _lib!.lookupFunction<
      Void Function(Pointer<Utf8>),
      void Function(Pointer<Utf8>)>('firebase_storage_watchos_free');

  /// Decodes and frees a native JSON string result.
  Map<String, Object?> _consume(Pointer<Utf8> ptr) {
    if (ptr == nullptr) {
      return <String, Object?>{
        'error': 'Native call returned null.',
        'code': 'internal',
      };
    }
    final String jsonString = ptr.toDartString();
    _free(ptr);
    return (json.decode(jsonString) as Map).cast<String, Object?>();
  }

  Map<String, Object?> _callJson(
    Pointer<Utf8> Function(Pointer<Utf8>) fn,
    Map<String, Object?> request,
  ) {
    final Pointer<Utf8> ptr = json.encode(request).toNativeUtf8();
    try {
      return _consume(fn(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  /// Starts an asynchronous one-shot operation; returns `{"token": N}`.
  Map<String, Object?> begin(Map<String, Object?> request) =>
      _callJson(_begin, request);

  /// Polls an operation; `{"pending": true}` until the result is ready.
  Map<String, Object?> poll(int token) => _consume(_poll(token));

  /// Starts an upload/download task; returns `{"taskId": N}`.
  Map<String, Object?> taskStart(Map<String, Object?> request) =>
      _callJson(_taskStart, request);

  /// Reads a task's latest snapshot.
  Map<String, Object?> taskSnapshot(int taskId) =>
      _consume(_taskSnapshot(taskId));

  /// Pauses, resumes, or cancels a task.
  Map<String, Object?> taskControl(int taskId, String action) {
    final Pointer<Utf8> actionPtr = action.toNativeUtf8();
    try {
      return _consume(_taskControl(taskId, actionPtr));
    } finally {
      calloc.free(actionPtr);
    }
  }

  /// Applies synchronous per-instance configuration.
  Map<String, Object?> configure(Map<String, Object?> request) =>
      _callJson(_configure, request);
}

/// watchOS implementation of [FirebaseStoragePlatform].
class FirebaseStorageWatchos extends FirebaseStoragePlatform {
  /// Creates the platform implementation for [appInstance] + [bucket].
  FirebaseStorageWatchos({super.appInstance, required super.bucket});

  /// Test hook: set before first use to replace the FFI bindings.
  static FirebaseStorageWatchosBindings? bindingsOverride;

  /// How often a pending native operation or task is polled.
  static Duration opPollInterval = const Duration(milliseconds: 40);

  static FirebaseStorageWatchosBindings? _bindings;

  static FirebaseStorageWatchosBindings get _b =>
      bindingsOverride ?? (_bindings ??= FirebaseStorageWatchosBindings());

  static final Map<String, FirebaseStorageWatchos> _instances =
      <String, FirebaseStorageWatchos>{};

  /// Registers this implementation as the default `firebase_storage`
  /// platform implementation on watchOS.
  static void registerWith() {
    FirebaseStoragePlatform.instance = FirebaseStorageWatchos(bucket: '');
  }

  int _maxOperationRetryTime = const Duration(minutes: 2).inMilliseconds;
  int _maxUploadRetryTime = const Duration(minutes: 10).inMilliseconds;
  int _maxDownloadRetryTime = const Duration(minutes: 10).inMilliseconds;

  String get _appName => appInstance?.name ?? defaultFirebaseAppName;

  Map<String, Object?> _request([Map<String, Object?> extra = const {}]) =>
      <String, Object?>{'app': _appName, 'bucket': bucket, ...extra};

  @override
  FirebaseStoragePlatform delegateFor({
    required FirebaseApp app,
    required String bucket,
  }) {
    return _instances['${app.name}|$bucket'] ??=
        FirebaseStorageWatchos(appInstance: app, bucket: bucket);
  }

  @override
  ReferencePlatform ref(String path) => ReferenceWatchos(this, path);

  @override
  int get maxOperationRetryTime => _maxOperationRetryTime;

  @override
  int get maxUploadRetryTime => _maxUploadRetryTime;

  @override
  int get maxDownloadRetryTime => _maxDownloadRetryTime;

  @override
  void setMaxOperationRetryTime(int time) {
    _throwIfError(_b.configure(
        _request({'op': 'setMaxOperationRetryTime', 'milliseconds': time})));
    _maxOperationRetryTime = time;
  }

  @override
  void setMaxUploadRetryTime(int time) {
    _throwIfError(_b.configure(
        _request({'op': 'setMaxUploadRetryTime', 'milliseconds': time})));
    _maxUploadRetryTime = time;
  }

  @override
  void setMaxDownloadRetryTime(int time) {
    _throwIfError(_b.configure(
        _request({'op': 'setMaxDownloadRetryTime', 'milliseconds': time})));
    _maxDownloadRetryTime = time;
  }

  @override
  Future<void> useStorageEmulator(String host, int port) async {
    _throwIfError(_b.configure(
        _request({'op': 'useEmulator', 'host': host, 'port': port})));
    emulatorHost = host;
    emulatorPort = port;
  }

  /// Starts a native one-shot operation and polls until its result arrives.
  Future<Map<String, Object?>> _awaitOp(Map<String, Object?> request) async {
    final Map<String, Object?> begin = _b.begin(_request(request));
    _throwIfError(begin);
    final int token = begin['token']! as int;
    while (true) {
      final Map<String, Object?> result = _b.poll(token);
      if (result['pending'] != true) {
        _throwIfError(result);
        return result;
      }
      await Future<void>.delayed(opPollInterval);
    }
  }

  static void _throwIfError(Map<String, Object?> result) {
    if (result.containsKey('error')) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: result['code'] as String? ?? 'unknown',
        message: result['error'] as String?,
      );
    }
  }
}

/// watchOS implementation of [ReferencePlatform].
class ReferenceWatchos extends ReferencePlatform {
  /// Creates a reference to [path] in [storage]'s bucket.
  ReferenceWatchos(FirebaseStorageWatchos super.storage, super.path);

  FirebaseStorageWatchos get _watchosStorage =>
      storage as FirebaseStorageWatchos;

  Map<String, Object?> _op(String op, [Map<String, Object?> extra = const {}]) =>
      <String, Object?>{'op': op, 'path': fullPath, ...extra};

  @override
  Future<void> delete() async {
    await _watchosStorage._awaitOp(_op('delete'));
  }

  @override
  Future<String> getDownloadURL() async {
    final Map<String, Object?> result =
        await _watchosStorage._awaitOp(_op('getDownloadURL'));
    return result['url']! as String;
  }

  @override
  Future<FullMetadata> getMetadata() async {
    final Map<String, Object?> result =
        await _watchosStorage._awaitOp(_op('getMetadata'));
    return FullMetadata((result['metadata']! as Map).cast<String, dynamic>());
  }

  @override
  Future<FullMetadata> updateMetadata(SettableMetadata metadata) async {
    final Map<String, Object?> result = await _watchosStorage
        ._awaitOp(_op('updateMetadata', {'metadata': metadata.asMap()}));
    return FullMetadata((result['metadata']! as Map).cast<String, dynamic>());
  }

  @override
  Future<ListResultPlatform> list([ListOptions? options]) async {
    final Map<String, Object?> result =
        await _watchosStorage._awaitOp(_op('list', {
      'maxResults': options?.maxResults ?? 1000,
      'pageToken': options?.pageToken,
    }));
    return _listResultFromMap(result);
  }

  @override
  Future<ListResultPlatform> listAll() async {
    final Map<String, Object?> result =
        await _watchosStorage._awaitOp(_op('listAll'));
    return _listResultFromMap(result);
  }

  ListResultWatchos _listResultFromMap(Map<String, Object?> map) {
    return ListResultWatchos(
      _watchosStorage,
      nextPageToken: map['nextPageToken'] as String?,
      itemPaths:
          (map['items'] as List<Object?>? ?? const []).cast<String>(),
      prefixPaths:
          (map['prefixes'] as List<Object?>? ?? const []).cast<String>(),
    );
  }

  @override
  Future<Uint8List?> getData(int maxSize) async {
    final Map<String, Object?> result =
        await _watchosStorage._awaitOp(_op('getData', {'maxSize': maxSize}));
    final String? base64 = result['data'] as String?;
    return base64 == null ? null : base64Decode(base64);
  }

  @override
  TaskPlatform putData(Uint8List data, [SettableMetadata? metadata]) {
    return _startTask(<String, Object?>{
      'kind': 'putData',
      'data': base64Encode(data),
      'metadata': metadata?.asMap(),
    });
  }

  @override
  TaskPlatform putString(
    String data,
    PutStringFormat format, [
    SettableMetadata? metadata,
  ]) {
    // The app-facing package converts most formats to base64 before calling
    // the platform; decode whatever arrives into raw bytes.
    final Uint8List bytes = switch (format) {
      PutStringFormat.raw => utf8.encode(data),
      PutStringFormat.base64 => base64Decode(data),
      PutStringFormat.base64Url => base64Url.decode(data),
      PutStringFormat.dataUrl => UriData.parse(data).contentAsBytes(),
    };
    return putData(bytes, metadata);
  }

  @override
  TaskPlatform putFile(File file, [SettableMetadata? metadata]) {
    return _startTask(<String, Object?>{
      'kind': 'putFile',
      'filePath': file.path,
      'metadata': metadata?.asMap(),
    });
  }

  @override
  TaskPlatform writeToFile(File file) {
    return _startTask(<String, Object?>{
      'kind': 'writeToFile',
      'filePath': file.path,
    });
  }

  TaskWatchos _startTask(Map<String, Object?> request) {
    final Map<String, Object?> result = FirebaseStorageWatchos._b
        .taskStart(_watchosStorage._request({...request, 'path': fullPath}));
    FirebaseStorageWatchos._throwIfError(result);
    return TaskWatchos(this, result['taskId']! as int);
  }
}

/// watchOS implementation of [ListResultPlatform].
class ListResultWatchos extends ListResultPlatform {
  /// Creates a list result over the native paths.
  ListResultWatchos(
    FirebaseStorageWatchos storage, {
    String? nextPageToken,
    required List<String> itemPaths,
    required List<String> prefixPaths,
  })  : _itemPaths = itemPaths,
        _prefixPaths = prefixPaths,
        super(storage, nextPageToken);

  final List<String> _itemPaths;
  final List<String> _prefixPaths;

  @override
  List<ReferencePlatform> get items =>
      _itemPaths.map((String path) => storage!.ref(path)).toList();

  @override
  List<ReferencePlatform> get prefixes =>
      _prefixPaths.map((String path) => storage!.ref(path)).toList();
}

/// watchOS implementation of [TaskSnapshotPlatform].
class TaskSnapshotWatchos extends TaskSnapshotPlatform {
  /// Wraps one native snapshot of a running task.
  TaskSnapshotWatchos(this._ref, TaskState state, Map<String, dynamic> data)
      : _raw = data,
        super(state, data);

  final ReferencePlatform _ref;

  // The decoded native snapshot this instance was built from; error details
  // are read from here so a failure is reported from the same state that
  // triggered it.
  final Map<String, dynamic> _raw;

  @override
  ReferencePlatform get ref => _ref;
}

/// watchOS implementation of [TaskPlatform].
///
/// The native side owns the SDK task and keeps its latest snapshot current
/// from the SDK's observer callbacks; this class polls that snapshot.
class TaskWatchos extends TaskPlatform {
  /// Wraps the native task [taskId] operating on [ref].
  TaskWatchos(this._ref, this._taskId) : super();

  final ReferenceWatchos _ref;
  final int _taskId;

  Future<TaskSnapshotPlatform>? _onComplete;

  static TaskState _stateFromName(String? name) {
    return switch (name) {
      'paused' => TaskState.paused,
      'success' => TaskState.success,
      'canceled' => TaskState.canceled,
      'error' => TaskState.error,
      _ => TaskState.running,
    };
  }

  TaskSnapshotWatchos _snapshotNow() {
    final Map<String, Object?> map =
        FirebaseStorageWatchos._b.taskSnapshot(_taskId);
    // A snapshot carries a `state`; without one this is an FFI-level error
    // (a failed task instead reports state "error" with a nested error map).
    if (!map.containsKey('state')) {
      FirebaseStorageWatchos._throwIfError(map);
    }
    return TaskSnapshotWatchos(
      _ref,
      _stateFromName(map['state'] as String?),
      map.cast<String, dynamic>(),
    );
  }

  static bool _isTerminal(TaskState state) =>
      state == TaskState.success ||
      state == TaskState.canceled ||
      state == TaskState.error;

  @override
  TaskSnapshotPlatform get snapshot => _snapshotNow();

  @override
  Stream<TaskSnapshotPlatform> get snapshotEvents {
    late StreamController<TaskSnapshotPlatform> controller;
    Timer? timer;
    Object? lastEmitted;
    void poll() {
      final TaskSnapshotWatchos current;
      try {
        current = _snapshotNow();
      } on Object catch (error, stackTrace) {
        controller.addError(error, stackTrace);
        timer?.cancel();
        controller.close();
        return;
      }
      final (TaskState, int) key = (current.state, current.bytesTransferred);
      if (key != lastEmitted) {
        lastEmitted = key;
        if (current.state == TaskState.error ||
            current.state == TaskState.canceled) {
          controller.addError(_taskException(current));
        } else {
          controller.add(current);
        }
      }
      if (_isTerminal(current.state)) {
        timer?.cancel();
        controller.close();
      }
    }

    controller = StreamController<TaskSnapshotPlatform>(
      onListen: () {
        poll();
        timer = Timer.periodic(FirebaseStorageWatchos.opPollInterval,
            (_) => poll());
      },
      onCancel: () {
        timer?.cancel();
        timer = null;
      },
    );
    return controller.stream;
  }

  FirebaseException _taskException(TaskSnapshotWatchos snapshot) {
    final Object? error = snapshot._raw['error'];
    if (error is Map) {
      return FirebaseException(
        plugin: 'firebase_storage',
        code: error['code'] as String? ?? 'unknown',
        message: error['error'] as String?,
      );
    }
    return FirebaseException(
      plugin: 'firebase_storage',
      code: snapshot.state == TaskState.canceled ? 'canceled' : 'unknown',
    );
  }

  @override
  Future<TaskSnapshotPlatform> get onComplete {
    // snapshotEvents runs the poll-until-terminal loop: it emits the final
    // success snapshot as its last data event, or the mapped
    // FirebaseException for error/canceled, then closes — so `.last` is
    // exactly onComplete's contract.
    return _onComplete ??= snapshotEvents.last;
  }

  Future<bool> _control(String action) async {
    final Map<String, Object?> result =
        FirebaseStorageWatchos._b.taskControl(_taskId, action);
    FirebaseStorageWatchos._throwIfError(result);
    return result['value'] == true;
  }

  @override
  Future<bool> pause() => _control('pause');

  @override
  Future<bool> resume() => _control('resume');

  @override
  Future<bool> cancel() => _control('cancel');
}
