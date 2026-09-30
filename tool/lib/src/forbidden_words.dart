// Copyright 2026 The FlutterWatch Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// The word rule of spec 0007 D8, and its entry lists.
///
/// This is the Dart form of the rule in `tool/check_words.sh`. Both read the
/// words from `tool/words/words.txt`, and `test/forbidden_words_test.dart`
/// checks that both give the same answers on `tool/words/samples.txt`.
library;

import 'dart:io';

/// The forbidden words, and the rule that finds them in text.
class ForbiddenWords {
  /// Creates the rule for [words], each also forbidden with a trailing "s".
  ForbiddenWords(Iterable<String> words)
    : words = List<String>.unmodifiable(words),
      _forms = <String>{
        for (final String word in words) ...<String>[
          word.toLowerCase(),
          '${word.toLowerCase()}s',
        ],
      };

  /// Reads the words from [path]: one per line; blank lines and lines that
  /// start with `#` are skipped.
  factory ForbiddenWords.load(String path) {
    return ForbiddenWords(
      File(path)
          .readAsLinesSync()
          .map((String line) => line.trim())
          .where((String line) => line.isNotEmpty && !line.startsWith('#')),
    );
  }

  /// The words, in file order.
  final List<String> words;

  final Set<String> _forms;

  static final RegExp _camelCaseBoundary = RegExp('([a-z])([A-Z])');
  static final RegExp _nonLetters = RegExp('[^A-Za-z]+');

  /// Splits [text] into words the way the rule does.
  ///
  /// A word ends at every character that is not an ASCII letter and at every
  /// change from a lower-case to an upper-case letter.
  static List<String> ruleWords(String text) {
    return text
        .replaceAllMapped(
          _camelCaseBoundary,
          (Match match) => '${match[1]} ${match[2]}',
        )
        .split(_nonLetters)
        .where((String word) => word.isNotEmpty)
        .toList();
  }

  /// The forbidden words in [text], in the order they appear. The match
  /// ignores case.
  List<String> wordsIn(String text) {
    return ruleWords(
      text,
    ).where((String word) => _forms.contains(word.toLowerCase())).toList();
  }
}

/// Converts a path glob to a regular expression over repository-relative
/// paths: `*` and `?` stay inside one directory, `**` crosses directories,
/// and `**/` also matches no directory at all.
RegExp globToRegExp(String glob) {
  final StringBuffer buffer = StringBuffer('^');
  for (int i = 0; i < glob.length; i++) {
    final String char = glob[i];
    if (char == '*' && i + 1 < glob.length && glob[i + 1] == '*') {
      if (i + 2 < glob.length && glob[i + 2] == '/') {
        buffer.write('(?:.*/)?');
        i += 2;
      } else {
        buffer.write('.*');
        i += 1;
      }
    } else if (char == '*') {
      buffer.write('[^/]*');
    } else if (char == '?') {
      buffer.write('[^/]');
    } else {
      buffer.write(RegExp.escape(char));
    }
  }
  buffer.write(r'$');
  return RegExp(buffer.toString());
}

/// One line of an entry list: text that may stand in the files [glob]
/// matches, and why.
class WordEntry {
  /// Creates an entry. [line] is its line in the file, from 1.
  WordEntry({
    required this.glob,
    required this.text,
    required this.reason,
    required this.line,
  }) : _pattern = globToRegExp(glob);

  /// The repository-relative paths the entry applies to.
  final String glob;

  /// The exact text the entry covers.
  final String text;

  /// Why the text is there.
  final String reason;

  /// The entry's line in its file, from 1.
  final int line;

  final RegExp _pattern;

  /// Whether this entry applies to the repository-relative [path].
  bool appliesTo(String path) => _pattern.hasMatch(path);
}

/// A list of entries in the format of `tool/words/forbidden_words_allow.txt`:
/// one entry per line, `<path glob> | <exact text> | <reason>`.
class WordEntries {
  /// Creates a list from [entries].
  WordEntries(this.entries);

  /// Parses [contents]. Blank lines and lines that start with `#` are
  /// skipped. Throws a [FormatException] for a line without all three parts.
  factory WordEntries.parse(String contents) {
    final List<WordEntry> entries = <WordEntry>[];
    final List<String> lines = contents.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i].trimRight();
      if (line.trim().isEmpty || line.trimLeft().startsWith('#')) {
        continue;
      }
      final int first = line.indexOf(' | ');
      final int second = first < 0 ? -1 : line.indexOf(' | ', first + 3);
      if (first < 0 || second < 0) {
        throw FormatException(
          'Line ${i + 1} needs "glob | text | reason": $line',
        );
      }
      final String glob = line.substring(0, first).trim();
      final String text = line.substring(first + 3, second);
      final String reason = line.substring(second + 3).trim();
      if (glob.isEmpty || text.trim().isEmpty || reason.isEmpty) {
        throw FormatException('Line ${i + 1} has an empty part: $line');
      }
      entries.add(
        WordEntry(glob: glob, text: text, reason: reason, line: i + 1),
      );
    }
    return WordEntries(entries);
  }

  /// Reads the list at [path]; a missing file is an empty list.
  factory WordEntries.load(String path) {
    final File file = File(path);
    return file.existsSync()
        ? WordEntries.parse(file.readAsStringSync())
        : WordEntries(<WordEntry>[]);
  }

  /// The entries, in file order.
  final List<WordEntry> entries;

  /// The first entry that applies to [path] and whose text is in [text], or
  /// null.
  WordEntry? covering(String path, String text) {
    for (final WordEntry entry in entries) {
      if (entry.appliesTo(path) && text.contains(entry.text)) {
        return entry;
      }
    }
    return null;
  }
}
