// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// watchOS implementation of `firebase_auth`, implemented over dart:ffi.
//
// Method-channel plugins are not supported on watchOS, so this package
// follows the FFI plugin model: `watchos/Classes/firebase_auth_watchos_ffi.m`
// bridges the Firebase Apple SDK (`FirebaseAuth`, linked via the SwiftPM
// dependency declared in `watchos/Package.swift`) behind C symbols returning
// JSON, the CLI force-loads the compiled archive into the watch binary, and
// this class resolves the symbols via `DynamicLibrary.process()`.
//
// Auth operations are network-backed, so the bridge is asynchronous: Dart
// starts an operation with `begin` (which returns a token) and polls `poll`
// until the native completion posts the result. Auth-state streams poll the
// native change generations (bumped by the SDK's listener callbacks).

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';

/// FFI bindings to the native firebase_auth_watchos C functions.
///
/// Each method marshals its arguments into C strings, calls the native
/// function, copies the returned JSON, frees the native buffer, and decodes
/// it. Overridable for tests via [FirebaseAuthWatchos.bindingsOverride]: the
/// [FirebaseAuthWatchosBindings.forTesting] constructor skips FFI
/// initialization so fakes work off-device.
class FirebaseAuthWatchosBindings {
  /// Creates bindings that look up native symbols in the current process.
  FirebaseAuthWatchosBindings() : _lib = DynamicLibrary.process();

  /// Constructor for fakes/mocks — skips FFI initialization.
  FirebaseAuthWatchosBindings.forTesting() : _lib = null;

  final DynamicLibrary? _lib;

  late final Pointer<Utf8> Function(Pointer<Utf8>) _begin = _lib!
      .lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Utf8>)>('firebase_auth_watchos_begin');

  late final Pointer<Utf8> Function(int) _poll = _lib!.lookupFunction<
      Pointer<Utf8> Function(Int64),
      Pointer<Utf8> Function(int)>('firebase_auth_watchos_poll');

  late final Pointer<Utf8> Function(Pointer<Utf8>) _currentUser =
      _lib!.lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>),
              Pointer<Utf8> Function(Pointer<Utf8>)>(
          'firebase_auth_watchos_current_user');

  late final Pointer<Utf8> Function(Pointer<Utf8>) _signOut = _lib!
      .lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Utf8>)>('firebase_auth_watchos_sign_out');

  late final Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)
      _setLanguageCode = _lib!.lookupFunction<
              Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>),
              Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)>(
          'firebase_auth_watchos_set_language_code');

  late final Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, int)
      _useEmulator = _lib!.lookupFunction<
              Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Int64),
              Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, int)>(
          'firebase_auth_watchos_use_emulator');

  late final Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)
      _isSignInLink = _lib!.lookupFunction<
              Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>),
              Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)>(
          'firebase_auth_watchos_is_sign_in_link');

  late final void Function(Pointer<Utf8>) _free = _lib!.lookupFunction<
      Void Function(Pointer<Utf8>),
      void Function(Pointer<Utf8>)>('firebase_auth_watchos_free');

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

  Map<String, Object?> _call1(
    Pointer<Utf8> Function(Pointer<Utf8>) fn,
    String arg,
  ) {
    final Pointer<Utf8> ptr = arg.toNativeUtf8();
    try {
      return _consume(fn(ptr));
    } finally {
      calloc.free(ptr);
    }
  }

  Map<String, Object?> _call2(
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>) fn,
    String a,
    String b,
  ) {
    final Pointer<Utf8> aPtr = a.toNativeUtf8();
    final Pointer<Utf8> bPtr = b.toNativeUtf8();
    try {
      return _consume(fn(aPtr, bPtr));
    } finally {
      calloc.free(aPtr);
      calloc.free(bPtr);
    }
  }

  /// Starts an asynchronous native auth operation; returns `{"token": N}`.
  Map<String, Object?> begin(Map<String, Object?> request) =>
      _call1(_begin, json.encode(request));

  /// Polls an operation; `{"pending": true}` until the result is ready.
  Map<String, Object?> poll(int token) => _consume(_poll(token));

  /// Reads the auth instance's current user + change generations.
  Map<String, Object?> currentUser(String appName) =>
      _call1(_currentUser, appName);

  /// Signs out the current user.
  Map<String, Object?> signOut(String appName) => _call1(_signOut, appName);

  /// Sets (or resets, with an empty code) the auth language code.
  Map<String, Object?> setLanguageCode(String appName, String code) =>
      _call2(_setLanguageCode, appName, code);

  /// Points the auth instance at a local emulator.
  Map<String, Object?> useEmulator(String appName, String host, int port) {
    final Pointer<Utf8> appPtr = appName.toNativeUtf8();
    final Pointer<Utf8> hostPtr = host.toNativeUtf8();
    try {
      return _consume(_useEmulator(appPtr, hostPtr, port));
    } finally {
      calloc.free(appPtr);
      calloc.free(hostPtr);
    }
  }

  /// Whether `link` is a sign-in-with-email link.
  Map<String, Object?> isSignInLink(String appName, String link) =>
      _call2(_isSignInLink, appName, link);
}

/// watchOS implementation of [FirebaseAuthPlatform].
class FirebaseAuthWatchos extends FirebaseAuthPlatform {
  /// Creates the platform implementation, optionally bound to [appInstance].
  FirebaseAuthWatchos({super.appInstance});

  /// Test hook: set before first use to replace the FFI bindings.
  static FirebaseAuthWatchosBindings? bindingsOverride;

  /// How often the auth-state streams poll the native change generations.
  static Duration streamPollInterval = const Duration(milliseconds: 200);

  /// How often a pending native operation is polled for its result.
  static Duration opPollInterval = const Duration(milliseconds: 40);

  static FirebaseAuthWatchosBindings? _bindings;

  static FirebaseAuthWatchosBindings get _b =>
      bindingsOverride ?? (_bindings ??= FirebaseAuthWatchosBindings());

  static final Map<String, FirebaseAuthWatchos> _instances =
      <String, FirebaseAuthWatchos>{};

  /// Registers this implementation as the default `firebase_auth` platform
  /// implementation on watchOS.
  static void registerWith() {
    FirebaseAuthPlatform.instance = FirebaseAuthWatchos();
  }

  String? _languageCode;

  // Bumped after user-mutating operations (profile updates, reload) so
  // [userChanges] fires even when the SDK posts no ID-token notification.
  int _userMutations = 0;

  String get _appName => appInstance?.name ?? defaultFirebaseAppName;

  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) {
    return _instances[app.name] ??= FirebaseAuthWatchos(appInstance: app);
  }

  @override
  FirebaseAuthPlatform setInitialValues({
    InternalUserDetails? currentUser,
    String? languageCode,
  }) {
    // State is read live from the native SDK; nothing to seed.
    _languageCode = languageCode ?? _languageCode;
    return this;
  }

  @override
  UserPlatform? get currentUser => _snapshot().user;

  @override
  set currentUser(UserPlatform? userPlatform) {
    // The native SDK owns the current user; nothing to store.
  }

  @override
  String? get languageCode => _languageCode;

  @override
  Future<void> setLanguageCode(String? languageCode) async {
    final Map<String, Object?> result =
        _b.setLanguageCode(_appName, languageCode ?? '');
    _throwIfError(result);
    _languageCode = result['languageCode'] as String?;
  }

  @override
  Future<void> useAuthEmulator(String host, int port) async {
    _throwIfError(_b.useEmulator(_appName, host, port));
  }

  @override
  bool isSignInWithEmailLink(String emailLink) {
    final Map<String, Object?> result = _b.isSignInLink(_appName, emailLink);
    _throwIfError(result);
    return result['value'] == true;
  }

  @override
  Stream<UserPlatform?> authStateChanges() =>
      _watch((_AuthSnapshot s) => s.authGeneration);

  @override
  Stream<UserPlatform?> idTokenChanges() =>
      _watch((_AuthSnapshot s) => s.idTokenGeneration);

  @override
  Stream<UserPlatform?> userChanges() => _watch((_AuthSnapshot s) =>
      s.authGeneration + s.idTokenGeneration + s.userMutations);

  @override
  Future<UserCredentialPlatform> signInAnonymously() =>
      _signInOp(<String, Object?>{'op': 'signInAnonymously'});

  @override
  Future<UserCredentialPlatform> signInWithEmailAndPassword(
    String email,
    String password,
  ) =>
      _signInOp(<String, Object?>{
        'op': 'signInWithEmailAndPassword',
        'email': email,
        'password': password,
      });

  @override
  Future<UserCredentialPlatform> createUserWithEmailAndPassword(
    String email,
    String password,
  ) =>
      _signInOp(<String, Object?>{
        'op': 'createUserWithEmailAndPassword',
        'email': email,
        'password': password,
      });

  @override
  Future<UserCredentialPlatform> signInWithEmailLink(
    String email,
    String emailLink,
  ) =>
      _signInOp(<String, Object?>{
        'op': 'signInWithEmailLink',
        'email': email,
        'emailLink': emailLink,
      });

  @override
  Future<UserCredentialPlatform> signInWithCustomToken(String token) =>
      _signInOp(<String, Object?>{
        'op': 'signInWithCustomToken',
        'token': token,
      });

  @override
  Future<UserCredentialPlatform> signInWithCredential(
    AuthCredential credential,
  ) {
    if (credential is EmailAuthCredential) {
      final String? password = credential.password;
      if (password != null) {
        return signInWithEmailAndPassword(credential.email, password);
      }
      final String? emailLink = credential.emailLink;
      if (emailLink != null) {
        return signInWithEmailLink(credential.email, emailLink);
      }
    }
    throw UnimplementedError(
      'signInWithCredential on watchOS supports email credentials only; '
      '${credential.providerId} sign-in requires a UI flow watchOS cannot '
      'present.',
    );
  }

  @override
  Future<void> signOut() async {
    _throwIfError(_b.signOut(_appName));
  }

  @override
  Future<void> sendPasswordResetEmail(
    String email, [
    ActionCodeSettings? actionCodeSettings,
  ]) async {
    await _awaitOp(<String, Object?>{
      'op': 'sendPasswordResetEmail',
      'email': email,
    });
  }

  @override
  Future<void> confirmPasswordReset(String code, String newPassword) async {
    await _awaitOp(<String, Object?>{
      'op': 'confirmPasswordReset',
      'code': code,
      'newPassword': newPassword,
    });
  }

  @override
  Future<String> verifyPasswordResetCode(String code) async {
    final Map<String, Object?> result = await _awaitOp(<String, Object?>{
      'op': 'verifyPasswordResetCode',
      'code': code,
    });
    return result['email']! as String;
  }

  @override
  Future<void> applyActionCode(String code) async {
    await _awaitOp(<String, Object?>{'op': 'applyActionCode', 'code': code});
  }

  // --- Internals ---------------------------------------------------------

  _AuthSnapshot _snapshot() {
    final Map<String, Object?> result = _b.currentUser(_appName);
    _throwIfError(result);
    final Object? userMap = result['user'];
    return _AuthSnapshot(
      authGeneration: result['authGeneration'] as int? ?? 0,
      idTokenGeneration: result['idTokenGeneration'] as int? ?? 0,
      userMutations: _userMutations,
      user: userMap is Map ? _userFromMap(userMap.cast<String, Object?>()) : null,
    );
  }

  // One shared poll loop per platform instance feeds every active
  // change-stream subscription: N listeners cost one native snapshot per
  // interval, not N. The timer runs only while a subscription exists.
  final Set<void Function(_AuthSnapshot?, Object?, StackTrace?)>
      _pollSubscribers = <void Function(_AuthSnapshot?, Object?, StackTrace?)>{};
  Timer? _pollTimer;
  String? _lastPollErrorSignature;

  // When [target] is set, delivers only to it (the immediate first emit for
  // a new subscription) — bypassing the error dedup so a late listener still
  // observes the current failure state.
  void _pollOnce({void Function(_AuthSnapshot?, Object?, StackTrace?)? target}) {
    final List<void Function(_AuthSnapshot?, Object?, StackTrace?)> targets =
        target != null
            ? <void Function(_AuthSnapshot?, Object?, StackTrace?)>[target]
            : List<void Function(_AuthSnapshot?, Object?, StackTrace?)>.of(
                _pollSubscribers);
    final _AuthSnapshot snapshot;
    try {
      snapshot = _snapshot();
    } on Object catch (error, stackTrace) {
      // Deliver a given failure once, not once per tick: the pre-initializeApp
      // "no app" state would otherwise flood the stream every poll interval.
      final String signature = error.toString();
      if (target == null && signature == _lastPollErrorSignature) {
        return;
      }
      _lastPollErrorSignature = signature;
      for (final void Function(_AuthSnapshot?, Object?, StackTrace?) deliver
          in targets) {
        deliver(null, error, stackTrace);
      }
      return;
    }
    _lastPollErrorSignature = null;
    for (final void Function(_AuthSnapshot?, Object?, StackTrace?) deliver
        in targets) {
      deliver(snapshot, null, null);
    }
  }

  // A fresh stream per call, matching FlutterFire semantics: emits the
  // current user immediately, then again whenever the watched generation
  // moves. The generation is bumped natively by the SDK's listeners.
  Stream<UserPlatform?> _watch(int Function(_AuthSnapshot) generationOf) {
    late StreamController<UserPlatform?> controller;
    int? lastGeneration;
    void onPoll(_AuthSnapshot? snapshot, Object? error, StackTrace? stackTrace) {
      if (error != null) {
        controller.addError(error, stackTrace!);
        return;
      }
      final int generation = generationOf(snapshot!);
      if (generation != lastGeneration) {
        lastGeneration = generation;
        controller.add(snapshot.user);
      }
    }

    controller = StreamController<UserPlatform?>(
      onListen: () {
        _pollSubscribers.add(onPoll);
        _pollTimer ??=
            Timer.periodic(streamPollInterval, (_) => _pollOnce());
        _pollOnce(target: onPoll);
      },
      onCancel: () {
        _pollSubscribers.remove(onPoll);
        if (_pollSubscribers.isEmpty) {
          _pollTimer?.cancel();
          _pollTimer = null;
          _lastPollErrorSignature = null;
        }
      },
    );
    return controller.stream;
  }

  /// Starts a native operation and polls until its result arrives.
  /// Throws [FirebaseAuthException] on an in-band error.
  Future<Map<String, Object?>> _awaitOp(Map<String, Object?> request) async {
    final Map<String, Object?> begin =
        _b.begin(<String, Object?>{...request, 'app': _appName});
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

  Future<UserCredentialPlatform> _signInOp(Map<String, Object?> request) async {
    final Map<String, Object?> result = await _awaitOp(request);
    final Object? userMap = result['user'];
    final Object? additional = result['additionalUserInfo'];
    return UserCredentialWatchos(
      auth: this,
      user: userMap is Map ? _userFromMap(userMap.cast<String, Object?>()) : null,
      additionalUserInfo: additional is Map
          ? _additionalUserInfoFromMap(additional.cast<String, Object?>())
          : null,
    );
  }

  UserWatchos _userFromMap(Map<String, Object?> map) {
    final List<Map<Object?, Object?>?> providerData =
        (map['providerData'] as List<Object?>? ?? const <Object?>[])
            .whereType<Map<Object?, Object?>>()
            .cast<Map<Object?, Object?>?>()
            .toList();
    return UserWatchos(
      this,
      InternalUserDetails(
        userInfo: InternalUserInfo(
          uid: map['uid']! as String,
          email: map['email'] as String?,
          displayName: map['displayName'] as String?,
          photoUrl: map['photoUrl'] as String?,
          phoneNumber: map['phoneNumber'] as String?,
          isAnonymous: map['isAnonymous'] as bool? ?? false,
          isEmailVerified: map['isEmailVerified'] as bool? ?? false,
          providerId: map['providerId'] as String?,
          tenantId: map['tenantId'] as String?,
          refreshToken: map['refreshToken'] as String?,
          creationTimestamp: map['creationTimestamp'] as int?,
          lastSignInTimestamp: map['lastSignInTimestamp'] as int?,
        ),
        providerData: providerData,
      ),
    );
  }

  static AdditionalUserInfo _additionalUserInfoFromMap(
    Map<String, Object?> map,
  ) {
    final Object? profile = map['profile'];
    // ignore: invalid_use_of_protected_member
    return AdditionalUserInfo(
      isNewUser: map['isNewUser'] == true,
      providerId: map['providerId'] as String?,
      username: map['username'] as String?,
      profile: profile is Map ? profile.cast<String, dynamic>() : null,
    );
  }

  static Never _throwError(Map<String, Object?> result) {
    // ignore: invalid_use_of_protected_member
    throw FirebaseAuthException(
      code: result['code'] as String? ?? 'unknown',
      message: result['error'] as String?,
      email: result['email'] as String?,
    );
  }

  static void _throwIfError(Map<String, Object?> result) {
    if (result.containsKey('error')) {
      _throwError(result);
    }
  }

  void _bumpUserMutations() {
    _userMutations += 1;
  }
}

/// watchOS implementation of [UserCredentialPlatform].
class UserCredentialWatchos extends UserCredentialPlatform {
  /// Creates the credential result of a sign-in operation.
  UserCredentialWatchos({
    required super.auth,
    super.user,
    super.additionalUserInfo,
  });
}

/// watchOS implementation of [MultiFactorPlatform].
///
/// Multi-factor flows need UI the watch cannot present; every operation
/// reports [UnimplementedError] (the base class behaviour).
class MultiFactorWatchos extends MultiFactorPlatform {
  /// Creates the multi-factor handle for [auth].
  MultiFactorWatchos(super.auth);
}

/// watchOS implementation of [UserPlatform].
class UserWatchos extends UserPlatform {
  /// Wraps the native SDK's current user snapshot.
  UserWatchos(FirebaseAuthWatchos auth, InternalUserDetails user)
      : _watchosAuth = auth,
        super(auth, MultiFactorWatchos(auth), user);

  final FirebaseAuthWatchos _watchosAuth;

  Future<Map<String, Object?>> _userOp(Map<String, Object?> request) async {
    final Map<String, Object?> result = await _watchosAuth._awaitOp(request);
    _watchosAuth._bumpUserMutations();
    return result;
  }

  @override
  Future<void> delete() async {
    await _userOp(<String, Object?>{'op': 'deleteUser'});
  }

  @override
  Future<void> reload() async {
    await _userOp(<String, Object?>{'op': 'reload'});
  }

  @override
  Future<String?> getIdToken(bool forceRefresh) async {
    final Map<String, Object?> result = await _watchosAuth._awaitOp(
      <String, Object?>{'op': 'getIdToken', 'forceRefresh': forceRefresh},
    );
    return result['token'] as String?;
  }

  @override
  Future<IdTokenResult> getIdTokenResult(bool forceRefresh) async {
    final Map<String, Object?> result = await _watchosAuth._awaitOp(
      <String, Object?>{'op': 'getIdToken', 'forceRefresh': forceRefresh},
    );
    final Object? claims = result['claims'];
    // ignore: invalid_use_of_protected_member
    return IdTokenResult(
      InternalIdTokenResult(
        token: result['token'] as String?,
        expirationTimestamp: result['expirationTimestamp'] as int?,
        authTimestamp: result['authTimestamp'] as int?,
        issuedAtTimestamp: result['issuedAtTimestamp'] as int?,
        signInProvider: result['signInProvider'] as String?,
        signInSecondFactor: result['signInSecondFactor'] as String?,
        claims: claims is Map ? claims.cast<String?, Object?>() : null,
      ),
    );
  }

  @override
  Future<void> sendEmailVerification(
      [ActionCodeSettings? actionCodeSettings]) async {
    await _userOp(<String, Object?>{'op': 'sendEmailVerification'});
  }

  @override
  Future<void> verifyBeforeUpdateEmail(
    String newEmail, [
    ActionCodeSettings? actionCodeSettings,
  ]) async {
    await _userOp(<String, Object?>{
      'op': 'verifyBeforeUpdateEmail',
      'newEmail': newEmail,
    });
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    await _userOp(<String, Object?>{
      'op': 'updatePassword',
      'password': newPassword,
    });
  }

  @override
  Future<void> updateProfile(Map<String, String?> profile) async {
    await _userOp(<String, Object?>{
      'op': 'updateProfile',
      'hasDisplayName': profile.containsKey('displayName'),
      'displayName': profile['displayName'],
      'hasPhotoUrl': profile.containsKey('photoURL'),
      'photoUrl': profile['photoURL'],
    });
  }
}

class _AuthSnapshot {
  _AuthSnapshot({
    required this.authGeneration,
    required this.idTokenGeneration,
    required this.userMutations,
    required this.user,
  });

  final int authGeneration;
  final int idTokenGeneration;
  final int userMutations;
  final UserPlatform? user;
}
