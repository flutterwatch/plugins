// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// The session, over dart:ffi — the same code on the iPhone and the watch.
//
// The native side exports C symbols and this file binds them.
// `WCSessionDelegate` callbacks arrive on a background queue and wake Dart
// through a `NativeCallable.listener`; there is no polling on either platform.
//
// The signal deliberately carries only a *kind*, never a payload:
// `NativeCallable.listener` is asynchronous, so native returns before Dart
// runs and any pointer handed across could be freed in between. Dart pulls the
// data back with the synchronous reads instead, draining the native ring
// buffer that still sits behind them — a burst can outrun the isolate, and a
// bounded buffer with a drop counter beats unbounded growth.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'backend.dart';
import 'codec.dart';
import 'types.dart';

/// Signature of the native→Dart wake signal.
typedef SignalNative = Void Function(Int64);

/// Raw FFI bindings, isolated behind a class so unit tests can subclass and
/// override without a native binary present (see [WatchLinkFfiBindings.forTesting]).
class WatchLinkFfiBindings {
  /// Binds against the native symbols, wherever the linker put them.
  WatchLinkFfiBindings() : _lib = _resolve();

  /// Finds the native symbols without asking which platform this is.
  ///
  /// On watchOS the CLI force-links the plugin archive into the executable, so
  /// they are already in the process. On iOS the plugin is a dynamic framework
  /// — it has to be, because a static archive's members are only pulled in
  /// when something references them, and nothing here does: these symbols
  /// exist purely to be looked up at runtime, so the linker would drop them.
  ///
  /// Probing beats branching on the platform. `Platform.isIOS` is true on
  /// watchOS too, so a branch would need the flutter_watchos dependency back
  /// just to answer a question the lookup already answers.
  ///
  /// Two framework names, because the two iOS integrations disagree: CocoaPods
  /// names it after the pod (underscores), Swift Package Manager after the
  /// SwiftPM product (hyphens). Which one an app gets depends on how it was
  /// built, not on anything this package can decide.
  static DynamicLibrary _resolve() {
    final DynamicLibrary process = DynamicLibrary.process();
    if (process.providesSymbol('flutter_watch_link_activate')) {
      return process;
    }
    for (final String name in const <String>[
      'flutter_watch_link', // CocoaPods
      'flutter-watch-link', // Swift Package Manager
    ]) {
      try {
        return DynamicLibrary.open('$name.framework/$name');
      } on ArgumentError {
        continue;
      }
    }
    throw StateError(
      'flutter_watch_link: native library not found. The plugin '
      'must build as a dynamic framework — a static one drops these symbols, '
      'because nothing references them outside dart:ffi.',
    );
  }

  /// Skips FFI initialization, for fakes in unit tests.
  WatchLinkFfiBindings.forTesting() : _lib = null;

  final DynamicLibrary? _lib;

  late final void Function(Pointer<NativeFunction<SignalNative>>) _setCallback =
      _lib!.lookupFunction<Void Function(Pointer<NativeFunction<SignalNative>>),
              void Function(Pointer<NativeFunction<SignalNative>>)>(
          'flutter_watch_link_set_callback');

  late final void Function() _activate =
      _lib!.lookupFunction<Void Function(), void Function()>(
          'flutter_watch_link_activate');

  late final int Function() _isSupported =
      _lib!.lookupFunction<Int32 Function(), int Function()>(
          'flutter_watch_link_is_supported');

  late final int Function() _state =
      _lib!.lookupFunction<Int32 Function(), int Function()>(
          'flutter_watch_link_state');

  late final int Function(Pointer<Utf8>) _sendMessage = _lib!.lookupFunction<
      Int32 Function(Pointer<Utf8>),
      int Function(Pointer<Utf8>)>('flutter_watch_link_send_message');

  late final int Function(Pointer<Utf8>) _updateContext =
      _lib!.lookupFunction<Int32 Function(Pointer<Utf8>),
              int Function(Pointer<Utf8>)>(
          'flutter_watch_link_update_application_context');

  late final int Function(Pointer<Utf8>) _transferUserInfo =
      _lib!.lookupFunction<Int32 Function(Pointer<Utf8>),
              int Function(Pointer<Utf8>)>(
          'flutter_watch_link_transfer_user_info');

  late final int Function(Pointer<Utf8>, int) _sendMessageWithReply =
      _lib!.lookupFunction<Int32 Function(Pointer<Utf8>, Int64),
              int Function(Pointer<Utf8>, int)>(
          'flutter_watch_link_send_message_with_reply');

  late final int Function(int, Pointer<Utf8>) _respond = _lib!.lookupFunction<
      Int32 Function(Int64, Pointer<Utf8>),
      int Function(int, Pointer<Utf8>)>('flutter_watch_link_respond');

  late final int Function(Pointer<Utf8>, Pointer<Utf8>) _transferFile =
      _lib!.lookupFunction<Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
              int Function(Pointer<Utf8>, Pointer<Utf8>)>(
          'flutter_watch_link_transfer_file');

  late final int Function() _outstandingFiles =
      _lib!.lookupFunction<Int32 Function(), int Function()>(
          'flutter_watch_link_outstanding_file_transfer_count');

  late final Pointer<Utf8> Function() _applicationContext =
      _lib!.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'flutter_watch_link_application_context');

  late final Pointer<Utf8> Function() _sentApplicationContext =
      _lib!.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'flutter_watch_link_sent_application_context');

  late final Pointer<Utf8> Function() _pollInbound =
      _lib!.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'flutter_watch_link_poll_inbound');

  late final int Function() _outstanding =
      _lib!.lookupFunction<Int32 Function(), int Function()>(
          'flutter_watch_link_outstanding_transfer_count');

  late final int Function() _dropped =
      _lib!.lookupFunction<Int32 Function(), int Function()>(
          'flutter_watch_link_dropped_inbound_count');

  late final Pointer<Utf8> Function() _takeLastError =
      _lib!.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'flutter_watch_link_take_last_error');

  late final void Function(Pointer<Utf8>) _freeString = _lib!.lookupFunction<
      Void Function(Pointer<Utf8>),
      void Function(Pointer<Utf8>)>('flutter_watch_link_free');

  /// Registers the function native code calls to wake Dart, or `nullptr` to
  /// stop signalling.
  void setCallback(Pointer<NativeFunction<SignalNative>> callback) =>
      _setCallback(callback);

  /// Activates `WCSession.default`. Idempotent.
  void activate() => _activate();

  /// Whether this device can run a session at all.
  bool isSupported() => _isSupported() != 0;

  /// The packed session-state word.
  int state() => _state();

  int _send(int Function(Pointer<Utf8>) f, String json) {
    final Pointer<Utf8> p = json.toNativeUtf8();
    try {
      return f(p);
    } finally {
      calloc.free(p);
    }
  }

  /// Sends [json] immediately.
  int sendMessage(String json) => _send(_sendMessage, json);

  /// Replaces the application context with [json].
  int updateApplicationContext(String json) => _send(_updateContext, json);

  /// Queues [json] for guaranteed delivery.
  int transferUserInfo(String json) => _send(_transferUserInfo, json);

  /// Sends [json] asking for a reply, tagged with [correlationId].
  int sendMessageWithReply(String json, int correlationId) {
    final Pointer<Utf8> p = json.toNativeUtf8();
    try {
      return _sendMessageWithReply(p, correlationId);
    } finally {
      calloc.free(p);
    }
  }

  /// Answers the received message identified by [replyId].
  int respond(int replyId, String json) {
    final Pointer<Utf8> p = json.toNativeUtf8();
    try {
      return _respond(replyId, p);
    } finally {
      calloc.free(p);
    }
  }

  /// Queues the file at [path] with optional [metadataJson].
  int transferFile(String path, String? metadataJson) {
    final Pointer<Utf8> p = path.toNativeUtf8();
    final Pointer<Utf8> m =
        metadataJson == null ? nullptr : metadataJson.toNativeUtf8();
    try {
      return _transferFile(p, m);
    } finally {
      calloc.free(p);
      if (m != nullptr) {
        calloc.free(m);
      }
    }
  }

  /// Undelivered file-transfer count.
  int outstandingFileTransferCount() => _outstandingFiles();

  /// Copies a native string out and frees it.
  ///
  /// Ownership transfers to Dart on every call that returns a pointer, so each
  /// one is freed here — unlike path_provider_watchos, whose pointers are
  /// process-lifetime constants the plugin keeps.
  String? _take(Pointer<Utf8> p) {
    if (p == nullptr) {
      return null;
    }
    try {
      return p.toDartString();
    } finally {
      _freeString(p);
    }
  }

  /// The last application context received, as JSON, or null.
  String? applicationContext() => _take(_applicationContext());

  /// The last application context sent from this device, as JSON, or null.
  String? sentApplicationContext() => _take(_sentApplicationContext());

  /// The oldest buffered inbound envelope, as JSON, or null when empty.
  String? pollInbound() => _take(_pollInbound());

  /// Undelivered `transferUserInfo` count.
  int outstandingTransferCount() => _outstanding();

  /// Inbound payloads dropped because the native ring buffer was full.
  int droppedInboundCount() => _dropped();

  /// The latest asynchronous failure, clearing it. Null when there is none.
  String? takeLastError() => _take(_takeLastError());
}

/// The [WatchLinkBackend] both platforms use.
class WatchLinkFfiBackend implements WatchLinkBackend {
  /// Binds to the statically linked native symbols.
  WatchLinkFfiBackend() : _bindings = WatchLinkFfiBindings();

  /// Uses caller-supplied [bindings], for unit tests.
  WatchLinkFfiBackend.forTesting(WatchLinkFfiBindings bindings)
      : _bindings = bindings;

  final WatchLinkFfiBindings _bindings;

  /// The single trampoline native signals through.
  ///
  /// Allocated once and reused across listen/cancel cycles: it is never closed
  /// before [dispose], because native can be between reading the pointer and
  /// calling it at the moment a listener cancels.
  NativeCallable<SignalNative>? _callable;

  /// Whether [_callable] is currently registered with native.
  ///
  /// Tracked separately from [_callable] so unregistering does not have to
  /// throw the trampoline away — doing that leaked one per listen/cancel
  /// cycle, since a [NativeCallable] is only reclaimed by `close()`.
  bool _signalling = false;

  bool _disposed = false;
  WatchLinkState _lastState = WatchLinkState.unknown;

  late final StreamController<WatchLinkMessage> _messages =
      StreamController<WatchLinkMessage>.broadcast(
    onListen: _startSignals,
    onCancel: _stopSignalsIfIdle,
  );

  late final StreamController<String> _errors =
      StreamController<String>.broadcast(
    onListen: _startSignals,
    onCancel: _stopSignalsIfIdle,
  );

  late final StreamController<WatchLinkFile> _files =
      StreamController<WatchLinkFile>.broadcast(
    onListen: _startSignals,
    onCancel: _stopSignalsIfIdle,
  );

  /// Futures waiting on a reply, keyed by the id sent with the message.
  final Map<int, Completer<Map<String, Object?>>> _pendingReplies =
      <int, Completer<Map<String, Object?>>>{};
  int _nextCorrelationId = 1;

  late final StreamController<WatchLinkState> _states =
      StreamController<WatchLinkState>.broadcast(
    onListen: _startSignals,
    onCancel: _stopSignalsIfIdle,
  );

  void _startSignals() {
    if (_disposed || _signalling) {
      return;
    }
    final NativeCallable<SignalNative> callable = _callable ??= () {
      final NativeCallable<SignalNative> c =
          NativeCallable<SignalNative>.listener(_onSignal);
      // The session should not be a reason the isolate stays alive.
      c.keepIsolateAlive = false;
      return c;
    }();
    _signalling = true;
    _bindings.setCallback(callable.nativeFunction);
    // Payloads can already be buffered — they arrive from the moment the
    // session activates, which may be long before anything listens. Draining
    // once here is what makes registration order stop mattering.
    drainOnce();
  }

  void _stopSignalsIfIdle() {
    if (_messages.hasListener ||
        _states.hasListener ||
        _errors.hasListener ||
        _files.hasListener ||
        // A reply that has not landed yet still needs the signal that carries
        // it, even with no stream listeners left.
        _pendingReplies.isNotEmpty) {
      return;
    }
    _bindings.setCallback(nullptr);
    _signalling = false;
    // The trampoline itself is deliberately *not* closed here. Native may
    // already be between reading the pointer and calling it, and closing under
    // that race is what turns a dropped message into a crash. It is kept and
    // re-registered on the next listen; dispose() closes it once for good.
  }

  /// Guards every entry point against use after [dispose].
  ///
  /// Without this the first call back in would reach a closed controller and
  /// fail as `StateError: Cannot add new events after calling close`, which
  /// says nothing about what actually went wrong.
  void _checkAlive() {
    if (_disposed) {
      throw const WatchLinkException(
        'This backend was disposed. A disposed session cannot be reused — '
        'construct a new backend, or leave WatchLink.instance undisposed, '
        'which is what an app normally wants.',
        code: 'disposed',
      );
    }
  }

  /// Handles one native wake-up.
  ///
  /// The `kind` is advisory — draining all three sources is two cheap reads
  /// plus a dequeue loop, and doing so unconditionally means a signal that is
  /// coalesced or misattributed can never strand a payload.
  void _onSignal(int kind) => drainOnce();

  /// Emits every buffered payload, then the state if it moved, then any error.
  ///
  /// Visible for tests, which drive it directly rather than through native.
  void drainOnce() {
    // A signal can still arrive from native after dispose has unregistered
    // the callback — it may have been in flight — and the controllers are
    // closed by then.
    if (_disposed) {
      return;
    }
    // Loop rather than taking one per signal — signals can coalesce, and a
    // burst that arrived while the app was backgrounded would otherwise
    // trickle out one item at a time.
    while (true) {
      final String? envelope = _bindings.pollInbound();
      if (envelope == null) {
        break;
      }
      _dispatch(jsonDecode(envelope));
    }

    final WatchLinkState next = decodeState(_bindings.state());
    if (next != _lastState) {
      _lastState = next;
      _states.add(next);
    }

    // Failures that landed on a native callback after their call returned.
    final String? error = _bindings.takeLastError();
    if (error != null) {
      _errors.add(error);
    }
  }

  /// Routes one inbound envelope to whichever stream or future it belongs to.
  ///
  /// Replies and files share the message buffer, so this is where the four
  /// shapes diverge. Anything unrecognised is dropped rather than thrown: the
  /// receiver cannot fix it, and an exception here would stall every later
  /// envelope behind it.
  void _dispatch(Object? decoded) {
    if (decoded is! Map<String, Object?>) {
      return;
    }
    switch (decoded['tier']) {
      case 'reply':
        final Completer<Map<String, Object?>>? pending =
            _takePending(decoded['correlationId']);
        final Object? payload = decoded['payload'];
        pending?.complete(
            payload is Map<String, Object?> ? payload : <String, Object?>{});
      case 'replyError':
        final Completer<Map<String, Object?>>? pending =
            _takePending(decoded['correlationId']);
        pending?.completeError(WatchLinkException(
          '${decoded['error'] ?? 'the counterpart did not reply'}',
          code: 'reply-failed',
        ));
      case 'file':
        final WatchLinkFile? file = decodeFile(decoded);
        if (file != null) {
          _files.add(file);
        }
      default:
        final WatchLinkMessage? message = decodeEnvelope(
          decoded,
          responderFor: (int replyId) => (Map<String, Object?> reply) async =>
              _check(_bindings.respond(replyId, jsonEncode(reply)), 'reply'),
        );
        if (message != null) {
          _messages.add(message);
        }
    }
  }

  Completer<Map<String, Object?>>? _takePending(Object? correlationId) =>
      correlationId is int ? _pendingReplies.remove(correlationId) : null;

  void _check(int code, String operation) {
    if (code != kOk) {
      throw exceptionFor(code, operation);
    }
  }

  @override
  Future<bool> isSupported() async {
    _checkAlive();
    return _bindings.isSupported();
  }

  @override
  Future<void> activate() async {
    _checkAlive();
    // Register before activating, so the activation callback itself is not the
    // signal that gets missed.
    _startSignals();
    _bindings.activate();
  }

  @override
  Future<WatchLinkState> readState() async {
    _checkAlive();
    return decodeState(_bindings.state());
  }

  @override
  Future<void> sendMessage(Map<String, Object?> payload) async {
    _checkAlive();
    _check(_bindings.sendMessage(jsonEncode(payload)), 'sendMessage');
  }

  @override
  Future<Map<String, Object?>> sendMessageWithReply(
    Map<String, Object?> payload, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    // `async` so a refused send rejects the future instead of throwing
    // synchronously — every other method on this backend rejects, and a caller
    // should not need a try/catch *and* an await for one of them.
    //
    // Registered before the send, because the reply can be delivered before
    // this method returns.
    _checkAlive();
    final int id = _nextCorrelationId++;
    final Completer<Map<String, Object?>> completer =
        Completer<Map<String, Object?>>();
    _pendingReplies[id] = completer;
    _startSignals();

    final int code = _bindings.sendMessageWithReply(jsonEncode(payload), id);
    if (code != kOk) {
      _pendingReplies.remove(id);
      throw exceptionFor(code, 'sendMessageWithReply');
    }

    // The native side gives up after its own timeout, but a dropped signal
    // would otherwise leave this future pending for the life of the app.
    return completer.future.timeout(timeout, onTimeout: () {
      _pendingReplies.remove(id);
      throw WatchLinkException(
        'No reply within ${timeout.inSeconds}s. The counterpart received the '
        'message but did not answer it.',
        code: 'reply-timeout',
      );
    });
  }

  @override
  Future<void> transferFile(String path,
      {Map<String, Object?>? metadata}) async {
    _checkAlive();
    _check(
      _bindings.transferFile(
          path, metadata == null ? null : jsonEncode(metadata)),
      'transferFile',
    );
  }

  @override
  Future<int> outstandingFileTransferCount() async {
    _checkAlive();
    return _bindings.outstandingFileTransferCount();
  }

  @override
  Stream<WatchLinkFile> get files {
    _checkAlive();
    return _files.stream;
  }

  @override
  Future<void> updateApplicationContext(Map<String, Object?> payload) async {
    _checkAlive();
    _check(_bindings.updateApplicationContext(jsonEncode(payload)),
        'updateApplicationContext');
  }

  @override
  Future<void> transferUserInfo(Map<String, Object?> payload) async {
    _checkAlive();
    _check(_bindings.transferUserInfo(jsonEncode(payload)), 'transferUserInfo');
  }

  @override
  Future<Map<String, Object?>?> receivedApplicationContext() async {
    _checkAlive();
    return _decodeContext(_bindings.applicationContext());
  }

  @override
  Future<Map<String, Object?>?> sentApplicationContext() async {
    _checkAlive();
    return _decodeContext(_bindings.sentApplicationContext());
  }

  static Map<String, Object?>? _decodeContext(String? json) {
    if (json == null) {
      return null;
    }
    final Object? decoded = jsonDecode(json);
    return decoded is Map<String, Object?> ? decoded : null;
  }

  @override
  Future<int> outstandingTransferCount() async {
    _checkAlive();
    return _bindings.outstandingTransferCount();
  }

  /// Inbound payloads the native ring buffer had to drop.
  ///
  /// Non-zero means payloads arrived faster than the isolate drained them.
  /// Surfaced for the diagnostics UI.
  Future<int> droppedInboundCount() async => _bindings.droppedInboundCount();

  @override
  Stream<WatchLinkMessage> get messages {
    _checkAlive();
    return _messages.stream;
  }

  /// Session state changes, seeded with the current state for *every*
  /// subscriber.
  ///
  /// [Stream.multi] rather than the broadcast controller's stream directly,
  /// because a broadcast `onListen` fires only when the listener count goes
  /// from zero to one. Seeding there left a second concurrent listener sitting
  /// on [WatchLinkState.unknown] — reporting "not activated" on an activated
  /// session — until something happened to change the state.
  @override
  Stream<WatchLinkState> get states {
    _checkAlive();
    return Stream<WatchLinkState>.multi(
      (MultiStreamController<WatchLinkState> out) {
        final WatchLinkState current = decodeState(_bindings.state());
        // Only the first subscriber records the seed as the last known state.
        // A later subscriber must not, or the change it just observed would be
        // suppressed for everyone else on the next drain.
        if (!_states.hasListener) {
          _lastState = current;
        }
        out.add(current);
        final StreamSubscription<WatchLinkState> sub = _states.stream.listen(
          out.add,
          onError: out.addError,
          onDone: out.close,
        );
        out.onCancel = sub.cancel;
      },
      isBroadcast: true,
    );
  }

  @override
  Stream<String> get errors {
    _checkAlive();
    return _errors.stream;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _bindings.setCallback(nullptr);
    _signalling = false;
    _callable?.close();
    _callable = null;
    // Fail anything still waiting rather than leaving futures pending for ever.
    for (final Completer<Map<String, Object?>> pending
        in _pendingReplies.values) {
      if (!pending.isCompleted) {
        pending.completeError(const WatchLinkException(
          'The session was disposed while a reply was outstanding.',
          code: 'disposed',
        ));
      }
    }
    _pendingReplies.clear();
    await _messages.close();
    await _states.close();
    await _errors.close();
    await _files.close();
  }
}

/// Registers the watchOS implementation.
///
/// Named to match `dartPluginClass` in pubspec.yaml, so the CLI's generated
/// registrant calls [registerWith] before `main()` runs.
class FlutterWatchLink {
  /// Registrant hook.
  ///
  /// Deliberately does nothing. Both platforms share one FFI backend, so
  /// there is nothing to select between — and keeping registration
  /// non-load-bearing is what stops this package repeating the
  /// in_app_purchase_watchos failure, where the app-facing package's own
  /// registration clobbered the platform implementation depending on which
  /// ran first.
  static void registerWith() {}
}
