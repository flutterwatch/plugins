// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const ExampleApp());

/// Exercises each class of URL watchOS can act on, and one it cannot.
class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  String _status = 'Pick a URL';

  Future<void> _open(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await canLaunchUrl(uri)) {
      setState(() => _status = 'unsupported: ${uri.scheme}:');
      return;
    }
    final bool ok = await launchUrl(uri);
    if (!mounted) {
      return;
    }
    // For http/https this means "offered via Handoff", not "opened here" —
    // the watch has no browser to open it in.
    setState(() => _status = ok ? 'handed to system' : 'refused');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: <Widget>[
              Text(_status, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              _Button(
                label: 'https (→ iPhone)',
                onTap: () => _open('https://example.com'),
              ),
              _Button(label: 'tel', onTap: () => _open('tel:+15551234567')),
              _Button(label: 'sms', onTap: () => _open('sms:+15551234567')),
              _Button(
                label: 'mailto (unsupported)',
                onTap: () => _open('mailto:hello@example.com'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: ElevatedButton(onPressed: onTap, child: Text(label)),
    );
  }
}
