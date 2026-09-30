// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// The weekly upstream compatibility check: compares each upstream's latest
/// version on pub.dev with `upstream_versions.yaml`, and resolves each
/// package with it. It reads pub.dev and publishes nothing.
///
/// Usage, from `tool/`: `dart run bin/upstream_compat.dart
/// [--root <repository>] [--table <upstream_versions.yaml>]
/// [--flutter <flutter executable>]`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plugins_tool/src/forbidden_words.dart';
import 'package:plugins_tool/src/repository.dart';
import 'package:plugins_tool/src/upstream_compat.dart';

Future<void> main(List<String> arguments) async {
  final Map<String, String> options = parseOptions(arguments, <String>{
    'root',
    'table',
    'flutter',
  });
  final String tool = toolDirectory();
  final HttpClient client = HttpClient();
  try {
    exitCode = await runUpstreamCompatibility(
      options['root'] ?? repositoryRootOf(tool),
      options['table'] ?? p.join(tool, 'upstream_versions.yaml'),
      pubDevFetcher(client),
      flutterPubGet(flutter: options['flutter'] ?? 'flutter'),
      ForbiddenWords.load(p.join(tool, 'words', 'words.txt')),
      stdout,
    );
  } finally {
    client.close();
  }
}
