import 'dart:convert';

import 'package:rubric_desk/domain/ledger.dart';
import 'package:rubric_desk/domain/scoring.dart';

// ponytail: printable output is plain UTF-8 text; add PDF layout when page control matters.
String printableRubric(Rubric rubric) => [
  '${rubric.title} · revision ${rubric.revision}',
  for (final c in rubric.criteria) ...[
    '${c.name} (weight ${c.weight})',
    for (final l in c.levels) '  ${l.label}: ${l.points}/${c.maximumPoints}',
  ],
  if (rubric.bands.isNotEmpty) ...[
    'Bands',
    for (final b in rubric.bands) '  ${b.minimumPercent}%+: ${b.label}',
  ],
].join('\n');

String feedbackText(
  String student,
  Assignment assignment,
  StudentScore score,
) => [
  '$student · ${assignment.title}',
  if (score.total == null)
    score.allExcused ? 'All excused · no total' : 'Incomplete · no total'
  else
    'Total: ${score.percent}%${score.band == null ? '' : ' · ${score.band}'}',
  'Counted weight: ${score.countedWeight}; excused weight: ${score.excusedWeight}',
  for (final b in score.breakdown)
    '${b.criterion.name} (weight ${b.criterion.weight}): '
        '${b.unmarked
            ? 'unmarked (unknown)'
            : b.excused
            ? 'excused (excluded)'
            : '${b.earned}/${b.criterion.maximumPoints}'}'
        '${b.mark?.note.isNotEmpty == true ? ' · ${b.mark!.note}' : ''}',
].join('\n');

// Spreadsheet-formula injection includes leading whitespace and control characters.
String _csv(String value) {
  final safe = RegExp(r'^[\s\x00-\x1f]*[=+@\-]').hasMatch(value)
      ? "'$value"
      : value;
  return '"${safe.replaceAll('"', '""')}"';
}

String gradeCsv(
  Assignment assignment,
  List<({String label, StudentScore score})> students,
) => [
  'Student,Assignment,Total,Status,Band,Excused,Unmarked',
  for (final row in students)
    [
      row.label,
      assignment.title,
      row.score.total == null ? '' : '${row.score.percent}%',
      row.score.allExcused
          ? 'all excused'
          : row.score.incomplete
          ? 'incomplete'
          : 'complete',
      row.score.band ?? '',
      row.score.breakdown
          .where((b) => b.excused)
          .map((b) => b.criterion.name)
          .join('; '),
      row.score.breakdown
          .where((b) => b.unmarked)
          .map((b) => b.criterion.name)
          .join('; '),
    ].map(_csv).join(','),
].join('\r\n');

const backupTables = [
  'courses',
  'students',
  'rubrics',
  'assignments',
  'mark_ledger',
];

String encodeBackup(Map<String, List<Map<String, Object?>>> tables) =>
    jsonEncode({
      'format': 'rubric-desk-backup',
      'version': 1,
      'tables': tables,
    });

Map<String, List<Map<String, Object?>>> decodeBackup(String raw) {
  final root = jsonDecode(raw);
  if (root is! Map<String, dynamic> ||
      root['format'] != 'rubric-desk-backup' ||
      root['version'] != 1 ||
      root['tables'] is! Map<String, dynamic>) {
    throw const FormatException('Unsupported backup format or version');
  }
  final tables = root['tables'] as Map<String, dynamic>;
  if (tables.keys.toSet().difference(backupTables.toSet()).isNotEmpty ||
      tables.length != backupTables.length) {
    throw const FormatException('Missing or unexpected backup tables');
  }
  if (tables.values.any((value) => value is! List)) {
    throw const FormatException('Invalid backup table rows');
  }
  return {
    for (final table in backupTables)
      table: (tables[table] as List).map((row) {
        if (row is! Map<String, dynamic>) {
          throw const FormatException('Invalid backup row');
        }
        return Map<String, Object?>.from(row);
      }).toList(),
  };
}
