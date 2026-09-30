// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// A report written into a public CI log.
library;

import 'forbidden_words.dart';

/// One package's entry in a report: a headline and the lines that explain
/// it. Before it reaches the log, every line goes through the word rule of
/// spec 0007 D8, because CI logs are public: a line that holds a forbidden
/// word is withheld, and the entry fails.
class ReportEntry {
  /// Creates an entry for [name].
  ReportEntry(this.name);

  /// The package or file the entry is about.
  final String name;

  /// What fails the entry, each followed by the lines that support it,
  /// such as a tool's own output, indented by two spaces.
  final List<String> problems = <String>[];

  /// What is worth saying but does not fail the entry.
  final List<String> notes = <String>[];

  /// A summary for the headline of a passing entry.
  String summary = '';

  /// Writes the entry to [out] and returns whether it failed.
  bool writeTo(StringSink out, ForbiddenWords words) {
    final List<String> lines = <String>[
      ...problems,
      ...notes,
    ].map((String line) => '       ${line.trimRight()}').toList();
    final List<String> printed = lines
        .where((String line) => words.wordsIn(line).isEmpty)
        .toList();
    int withheld = lines.length - printed.length;
    String headline = problems.isEmpty
        ? 'ok   $name${summary.isEmpty ? '' : ': $summary'}'
        : 'FAIL $name';
    if (words.wordsIn(headline).isNotEmpty) {
      withheld++;
      headline = 'FAIL (a name withheld)';
    }
    if (withheld > 0) {
      printed.add(
        '       $withheld line${withheld == 1 ? '' : 's'} withheld: a '
        'forbidden word (spec 0007 D8) may not reach the public log.',
      );
      if (headline.startsWith('ok   ')) {
        headline = headline.replaceFirst('ok   ', 'FAIL ');
      }
    }
    out.writeln(headline);
    printed.forEach(out.writeln);
    return problems.isNotEmpty || withheld > 0;
  }
}
