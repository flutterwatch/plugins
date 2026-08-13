// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// One companion app, both devices:
//   flutter run            — the iPhone
//   flutter-watchos run    — the Apple Watch
//
// The same Dart and the same native source run on each. Everything below is
// device-agnostic apart from sizing, which is the point of the package.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_watch_link/flutter_watch_link.dart';
import 'package:flutter_watchos/flutter_watchos.dart';

void main() => runApp(const DemoApp());

/// The demo, sized for whichever device is running it.
class DemoApp extends StatelessWidget {
  const DemoApp({super.key, this.forceCompact});

  /// Overrides the device check. For tests only.
  final bool? forceCompact;

  @override
  Widget build(BuildContext context) {
    // One entrypoint for both devices: there is a single widget tree here, so
    // a second target would buy nothing. (An app with genuinely different
    // phone and watch UIs is a different case — there, separate targets keep
    // the unused tree out of the watch binary.)
    //
    // `isWatch` is pure Dart with no FFI, so it is safe to evaluate inside the
    // iOS binary. Note `Platform.isIOS` is *true* on watchOS and would not
    // answer this.
    final bool compact = forceCompact ?? FlutterWatchosPlatform.isWatch;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: compact ? Brightness.dark : Brightness.light,
        colorSchemeSeed: Colors.teal,
      ),
      home: DemoPage(compact: compact),
    );
  }
}

/// Drives one [WatchLink] and shows everything it reports.
class DemoPage extends StatefulWidget {
  const DemoPage({super.key, required this.compact});

  final bool compact;

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final WatchLink _link = WatchLink.instance;
  final List<String> _log = <String>[];
  final List<StreamSubscription<Object?>> _subs =
      <StreamSubscription<Object?>>[];

  WatchLinkState _state = WatchLinkState.unknown;
  int _counter = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    if (!await _link.isSupported()) {
      _add('WatchConnectivity is not available on this device');
      return;
    }

    // Subscribe before activating: the activation callback is itself a state
    // change, and it is the one most worth not missing.
    _subs.add(_link.states.listen((WatchLinkState s) {
      setState(() => _state = s);
    }));
    _subs.add(_link.messages.listen(_onMessage));
    _subs.add(_link.files
        .listen((WatchLinkFile f) => _add('file: ${f.path} ${f.metadata}')));
    // Without this, a send that WCSession accepts and then fails looks exactly
    // like a delivered one.
    _subs.add(_link.errors.listen((String e) => _add('error: $e')));

    await _link.activate();

    // A cold launch has a context waiting for it before any stream fires.
    final Map<String, Object?>? caughtUp =
        await _link.receivedApplicationContext();
    if (caughtUp != null) {
      _add('caught up from context: $caughtUp');
    }
  }

  void _onMessage(WatchLinkMessage m) {
    _add('${m.tier.name}: ${m.payload}');
    if (m.expectsReply) {
      // Answer promptly — the sender's reply block is held natively and is
      // dropped after 30 seconds.
      unawaited(m.reply(<String, Object?>{'ack': m.payload['n']}));
    }
  }

  void _add(String line) {
    if (!mounted) {
      return;
    }
    setState(() {
      _log.insert(0, line);
      if (_log.length > 30) {
        _log.removeLast();
      }
    });
  }

  /// Runs [action], turning the exception the session throws into a log line
  /// instead of an unhandled error.
  Future<void> _guard(String label, Future<void> Function() action) async {
    try {
      await action();
      _add('$label ok');
    } on WatchLinkException catch (e) {
      _add('$label failed — ${e.code}');
    }
  }

  Map<String, Object?> get _payload => <String, Object?>{'n': ++_counter};

  @override
  void dispose() {
    for (final StreamSubscription<Object?> s in _subs) {
      unawaited(s.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool compact = widget.compact;
    final Map<String, bool> flags = <String, bool>{
      'activated': _state.activated,
      'paired': _state.counterpartPaired,
      'installed': _state.counterpartInstalled,
      'reachable': _state.reachable,
    };

    return Scaffold(
      appBar: compact ? null : AppBar(title: const Text('flutter_watch_link')),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(compact ? 6 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: <Widget>[
                  for (final MapEntry<String, bool> f in flags.entries)
                    _Flag(label: f.key, on: f.value, compact: compact),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: <Widget>[
                  // One button per tier, so the difference between them is
                  // something you can press rather than only read about.
                  _Action(
                    label: 'message',
                    compact: compact,
                    onPressed: () => _guard(
                        'sendMessage', () => _link.sendMessage(_payload)),
                  ),
                  _Action(
                    label: 'reply',
                    compact: compact,
                    onPressed: () => _guard('sendMessageWithReply', () async {
                      final Map<String, Object?> r =
                          await _link.sendMessageWithReply(_payload);
                      _add('reply: $r');
                    }),
                  ),
                  _Action(
                    label: 'context',
                    compact: compact,
                    onPressed: () => _guard('updateApplicationContext',
                        () => _link.updateApplicationContext(_payload)),
                  ),
                  _Action(
                    label: 'userInfo',
                    compact: compact,
                    onPressed: () => _guard('transferUserInfo',
                        () => _link.transferUserInfo(_payload)),
                  ),
                  _Action(
                    label: 'sent ctx',
                    compact: compact,
                    onPressed: () async => _add(
                        'last sent: ${await _link.sentApplicationContext()}'),
                  ),
                  _Action(
                    label: 'queued',
                    compact: compact,
                    onPressed: () async => _add(
                        'undelivered: ${await _link.outstandingTransferCount()}'
                        ' userInfo, '
                        '${await _link.outstandingFileTransferCount()} files'),
                  ),
                ],
              ),
              const Divider(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: _log.length,
                  itemBuilder: (BuildContext context, int i) => Text(
                    _log[i],
                    style: TextStyle(fontSize: compact ? 11 : 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One session flag, lit when true.
class _Flag extends StatelessWidget {
  const _Flag({required this.label, required this.on, required this.compact});

  final String label;
  final bool on;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: on ? Colors.teal : Colors.grey.shade700,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(color: Colors.white, fontSize: compact ? 10 : 12),
        ),
      );
}

/// A button that runs one session call.
class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.compact,
    required this.onPressed,
  });

  final String label;
  final bool compact;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: compact ? 26 : 36,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
            textStyle: TextStyle(fontSize: compact ? 11 : 13),
          ),
          onPressed: () => onPressed(),
          child: Text(label),
        ),
      );
}
