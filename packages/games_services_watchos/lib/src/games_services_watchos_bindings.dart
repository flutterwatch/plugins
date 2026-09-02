/// Thin Dart binding over the GameKit C shim.
///
/// Everything is poll-based rather than callback-based: GameKit answers on its
/// own queues, and calling into Dart from an arbitrary thread needs a
/// NativeCallable plus a live isolate. Polling a state word from the frame the
/// game already runs is simpler and cannot misbehave at shutdown.
library;

import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

enum _GcState { idle, pending, ok, failed }

_GcState _state(int raw) => switch (raw) {
  1 => _GcState.pending,
  2 => _GcState.ok,
  3 => _GcState.failed,
  _ => _GcState.idle,
};

/// One row of a leaderboard.
class GcEntry {
  const GcEntry({
    required this.rank,
    required this.score,
    required this.player,
    required this.isLocal,
  });

  final int rank;
  final int score;
  final String player;

  /// True for the signed-in player's own row.
  final bool isLocal;
}

typedef _VoidFn = void Function();
typedef _IntFn = int Function();
typedef _StrFn = Pointer<Utf8> Function();

class _Symbols {
  _Symbols(DynamicLibrary lib)
    : authenticate = lib.lookupFunction<Void Function(), _VoidFn>(
        'games_services_watchos_authenticate',
      ),
      authState = lib.lookupFunction<Int32 Function(), _IntFn>(
        'games_services_watchos_auth_state',
      ),
      submitState = lib.lookupFunction<Int32 Function(), _IntFn>(
        'games_services_watchos_submit_state',
      ),
      entriesState = lib.lookupFunction<Int32 Function(), _IntFn>(
        'games_services_watchos_entries_state',
      ),
      playerAlias = lib.lookupFunction<Pointer<Utf8> Function(), _StrFn>(
        'games_services_watchos_player_alias',
      ),
      entriesJson = lib.lookupFunction<Pointer<Utf8> Function(), _StrFn>(
        'games_services_watchos_entries_json',
      ),
      lastError = lib.lookupFunction<Pointer<Utf8> Function(), _StrFn>(
        'games_services_watchos_last_error',
      ),
      submit =
          lib.lookupFunction<
            Void Function(Int64, Pointer<Utf8>),
            void Function(int, Pointer<Utf8>)
          >('games_services_watchos_submit'),
      loadEntries =
          lib.lookupFunction<
            Void Function(Pointer<Utf8>, Int32),
            void Function(Pointer<Utf8>, int)
          >('games_services_watchos_load_entries'),
      free =
          lib.lookupFunction<
            Void Function(Pointer<Utf8>),
            void Function(Pointer<Utf8>)
          >('games_services_watchos_free');

  final _VoidFn authenticate;
  final _IntFn authState;
  final _IntFn submitState;
  final _IntFn entriesState;
  final _StrFn playerAlias;
  final _StrFn entriesJson;
  final _StrFn lastError;
  final void Function(int, Pointer<Utf8>) submit;
  final void Function(Pointer<Utf8>, int) loadEntries;
  final void Function(Pointer<Utf8>) free;
}

/// GameKit over FFI, or a quiet no-op when the symbols are not linked.
///
/// Nothing here throws: a caller that is not signed in, or a platform where
/// the plugin was never linked, gets an unavailable feature rather than an
/// exception on a path it cannot recover from.
///
/// Subclass and override to fake the native side in tests; the
/// [GamesServicesWatchosBindings.forTesting] constructor skips FFI resolution
/// so a host test never touches `DynamicLibrary.process()`.
class GamesServicesWatchosBindings {
  GamesServicesWatchosBindings();

  /// Skips symbol resolution. For tests only.
  GamesServicesWatchosBindings.forTesting() : _resolved = true;

  _Symbols? _bindings;
  bool _resolved = false;

  bool get available => _resolve() != null;

  /// Whether the native side reports a signed-in local player. Read live, not
  /// cached: an authentication that lapses after launch otherwise leaves the
  /// caller believing it is still signed in while GameKit refuses every call.
  bool get authenticated {
    final b = _resolve();
    return b != null && _state(b.authState()) == _GcState.ok;
  }

  _Symbols? _resolve() {
    if (_resolved) return _bindings;
    _resolved = true;
    try {
      _bindings = _Symbols(DynamicLibrary.process());
    } catch (_) {
      _bindings = null;
    }
    return _bindings;
  }

  /// Reads a native string and frees it; the C side hands over ownership.
  String? _takeString(Pointer<Utf8> ptr, _Symbols b) {
    if (ptr == nullptr) return null;
    try {
      return ptr.toDartString();
    } finally {
      b.free(ptr);
    }
  }

  /// Live authentication state, named, for diagnostics.
  String get authStateName {
    final b = _resolve();
    if (b == null) return 'nolib';
    return _state(b.authState()).name;
  }

  String? get lastError {
    final b = _resolve();
    return b == null ? null : _takeString(b.lastError(), b);
  }

  String? get playerAlias {
    final b = _resolve();
    return b == null ? null : _takeString(b.playerAlias(), b);
  }

  Future<bool> signIn({Duration timeout = const Duration(seconds: 20)}) async {
    final b = _resolve();
    if (b == null) return false;
    // Already good: the state is read live from GKLocalPlayer, so this is a
    // real answer rather than a cached one.
    if (_state(b.authState()) == _GcState.ok) return true;
    b.authenticate();
    return await _settle(() => _state(b.authState()), timeout) == _GcState.ok;
  }

  Future<bool> submitScore(
    int score,
    String leaderboardId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final b = _resolve();
    if (b == null || _state(b.authState()) != _GcState.ok) return false;
    final Pointer<Utf8> lid = leaderboardId.toNativeUtf8();
    try {
      b.submit(score, lid);
    } finally {
      calloc.free(lid);
    }
    return await _settle(() => _state(b.submitState()), timeout) == _GcState.ok;
  }

  /// Null when the read failed, empty when the leaderboard genuinely has no
  /// entries. These must stay distinguishable: returning an empty list for a
  /// timeout made a broken fetch read as "no scores yet" all the way up to the
  /// card, which is exactly how a failing watch leaderboard looked correct.
  Future<List<GcEntry>?> topScores(
    String leaderboardId, {
    int count = 10,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final b = _resolve();
    if (b == null) return null;
    // Authentication can lapse between launch and here -- the watch drops it
    // when it loses the phone, and GameKit then rejects the read from the
    // inside. Re-drive the handler once rather than reporting a load failure
    // for what is really a sign-in that went away.
    if (_state(b.authState()) != _GcState.ok) {
      if (!await signIn(timeout: timeout)) return null;
    }
    final Pointer<Utf8> lid = leaderboardId.toNativeUtf8();
    try {
      b.loadEntries(lid, count);
    } finally {
      calloc.free(lid);
    }
    if (await _settle(() => _state(b.entriesState()), timeout) != _GcState.ok) {
      return null;
    }
    final raw = _takeString(b.entriesJson(), b);
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .map(
            (j) => GcEntry(
              rank: j['rank'] as int? ?? 0,
              score: j['score'] as int? ?? 0,
              player: j['player'] as String? ?? '',
              isLocal: j['local'] as bool? ?? false,
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  /// Polls [read] until it leaves pending, or the timeout expires. 120ms costs
  /// nothing next to a 60fps frame and does not make a sign-in feel stalled.
  Future<_GcState> _settle(_GcState Function() read, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    _GcState s = read();
    while (s == _GcState.pending && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      s = read();
    }
    return s;
  }
}
