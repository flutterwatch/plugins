// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// The weekly upstream compatibility check on its fixtures, in
// tool/test/fixtures/upstream_compat/. Each fixture's pub_dev.yaml stands
// in for the pub.dev API, and its resolve.yaml for `flutter pub get`: a
// package and source listed there fails to resolve with that output. The
// games_services output is the one plugins.md P6 recorded on 2026-09-29.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plugins_tool/src/forbidden_words.dart';
import 'package:plugins_tool/src/upstream_compat.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'src/fixture_repo.dart';

/// A fetcher that answers from a map of package to latest version.
LatestVersionFetcher mapFetcher(Map<String, String> versions) {
  return (String package) async {
    final String? version = versions[package];
    return version == null ? null : Version.parse(version);
  };
}

/// A fetcher that answers from the fixture's pub_dev.yaml.
LatestVersionFetcher fixtureFetcher(String fixture) {
  final Object? document = loadYaml(
    File(p.join(fixture, 'pub_dev.yaml')).readAsStringSync(),
  );
  return mapFetcher(<String, String>{
    if (document is YamlMap)
      for (final MapEntry<Object?, Object?> entry in document.entries)
        '${entry.key}': '${entry.value}',
  });
}

/// A resolver that fails for the package and source the fixture's
/// resolve.yaml lists, and checks each scratch pubspec it is given.
Resolver fixtureResolver(String fixture, String root) {
  final File listed = File(p.join(fixture, 'resolve.yaml'));
  final Object? failures = listed.existsSync()
      ? loadYaml(listed.readAsStringSync())
      : null;
  return (String appDirectory) {
    final YamlMap pubspec =
        loadYaml(File(p.join(appDirectory, 'pubspec.yaml')).readAsStringSync())
            as YamlMap;
    final YamlMap dependencies = pubspec['dependencies'] as YamlMap;
    expect(dependencies['flutter'], <String, String>{'sdk': 'flutter'});
    final String package = dependencies.keys.last as String;
    final Object? source = dependencies[package];
    final String label;
    if (source is YamlMap) {
      expect(
        source['path'],
        p.join(p.absolute(root), 'packages', package),
        reason: 'the repository variant depends on the package by path',
      );
      label = 'repository';
    } else {
      expect(source, startsWith('^'));
      label = 'published';
    }
    final Object? output = failures is YamlMap
        ? failures['$package $label']
        : null;
    return output == null
        ? (exitCode: 0, output: 'Got dependencies!')
        : (exitCode: 1, output: '$output');
  };
}

void main() {
  final ForbiddenWords words = ForbiddenWords.load(
    p.join('words', 'words.txt'),
  );
  final List<Fixture> fixtures = fixturesIn(
    p.join('test', 'fixtures', 'upstream_compat'),
  );

  test('a new upstream major is among the failing fixtures', () {
    expect(
      fixtures
          .singleWhere((Fixture f) => f.name == 'new_major')
          .expectedExitCode,
      1,
    );
  });

  for (final Fixture fixture in fixtures) {
    test('fixture ${fixture.name}', () async {
      final String root = p.join(fixture.directory, 'repo');
      final StringBuffer out = StringBuffer();
      final int code = await runUpstreamCompatibility(
        root,
        p.join(fixture.directory, 'upstream_versions.yaml'),
        fixtureFetcher(fixture.directory),
        fixtureResolver(fixture.directory, root),
        words,
        out,
      );
      expect(code, fixture.expectedExitCode, reason: '$out');
      for (final String text in fixture.expectedOutput) {
        expect('$out', contains(text));
      }
    });
  }

  test('a pre-release name from pub.dev is withheld and fails', () async {
    final String fixture = p.join(
      'test',
      'fixtures',
      'upstream_compat',
      'same',
    );
    final String root = p.join(fixture, 'repo');
    final StringBuffer out = StringBuffer();
    final int code = await runUpstreamCompatibility(
      root,
      p.join(fixture, 'upstream_versions.yaml'),
      mapFetcher(<String, String>{
        'battery_plus': '7.1.1',
        'battery_plus_watchos': '0.1.0-${words.words.first}.1',
      }),
      fixtureResolver(fixture, root),
      words,
      out,
    );
    expect(code, 1);
    expect(words.wordsIn('$out'), isEmpty, reason: '$out');
    expect('$out', contains('withheld'));
  });

  test('a pub.dev that cannot be read fails the package', () async {
    final String fixture = p.join(
      'test',
      'fixtures',
      'upstream_compat',
      'same',
    );
    final String root = p.join(fixture, 'repo');
    final StringBuffer out = StringBuffer();
    final int code = await runUpstreamCompatibility(
      root,
      p.join(fixture, 'upstream_versions.yaml'),
      (String package) async =>
          throw const HttpException('pub.dev answered 503.'),
      fixtureResolver(fixture, root),
      words,
      out,
    );
    expect(code, 1);
    expect('$out', contains('pub.dev could not be read'));
  });

  test('compareWithTable', () {
    final Version table = Version.parse('7.1.1');
    expect(compareWithTable('b', table, Version.parse('7.1.1')), (
      problem: null,
      note: null,
    ));
    expect(
      compareWithTable('b', table, Version.parse('7.9.0')).problem,
      isNull,
    );
    expect(
      compareWithTable('b', table, Version.parse('8.0.0')).problem,
      contains('a new major'),
    );
    expect(
      compareWithTable(
        'b',
        Version.parse('0.2.1'),
        Version.parse('0.3.0'),
      ).problem,
      contains('a new major'),
      reason: 'below 1.0.0 the minor is the major',
    );
  });

  test('the scratch pubspec depends on the latest upstream', () {
    final YamlMap pubspec =
        loadYaml(
              scratchPubspec(
                upstream: 'battery_plus',
                upstreamVersion: Version.parse('7.1.1'),
                package: 'battery_plus_watchos',
                packageVersion: Version.parse('0.1.0'),
              ),
            )
            as YamlMap;
    expect(pubspec['publish_to'], 'none');
    expect(pubspec['dependencies']['battery_plus'], '^7.1.1');
    expect(pubspec['dependencies']['battery_plus_watchos'], '^0.1.0');
  });

  test('resolutionReason drops the progress lines', () {
    expect(
      resolutionReason(
        'Resolving dependencies...\n\nBecause a needs b, version solving '
        'failed.\n',
      ),
      <String>['Because a needs b, version solving failed.'],
    );
  });

  group('pubDevFetcher', () {
    late HttpServer server;
    late HttpClient client;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) async {
        if (request.uri.path == '/api/packages/battery_plus_watchos') {
          request.response.write(
            jsonEncode(<String, Object?>{
              'name': 'battery_plus_watchos',
              'latest': <String, Object?>{'version': '0.1.0'},
              'versions': <Object?>[
                <String, Object?>{'version': '0.1.0'},
              ],
            }),
          );
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await server.close(force: true);
    });

    test('reads latest.version, and null for an unknown package', () async {
      final LatestVersionFetcher fetch = pubDevFetcher(
        client,
        host: 'http://127.0.0.1:${server.port}',
      );
      expect(await fetch('battery_plus_watchos'), Version.parse('0.1.0'));
      expect(await fetch('no_such_package'), isNull);
    });
  });
}
