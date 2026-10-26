import 'dart:convert';

import 'package:rubric_desk/domain/scoring.dart';

/// Pure-Dart append-only mark ledger with transactional SQL schema.
///
/// Acceptance criteria:
/// * mark ledger is append-only: every change adds a row with monotonic sequence;
/// * current marks per student x criterion resolve from latest sequence;
/// * assignments pin a rubric revision; editing template never mutates old marks;
/// * SQLite migrations run transactionally; schema tracked via user_version.

class Assignment {
  const Assignment({
    required this.id,
    required this.courseId,
    required this.title,
    required this.rubricId,
    required this.rubricRevision,
    required this.createdAt,
  });

  final String id;
  final String courseId;
  final String title;
  final String rubricId;
  final int rubricRevision;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'course_id': courseId,
    'title': title,
    'rubric_id': rubricId,
    'rubric_revision': rubricRevision,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  factory Assignment.fromMap(Map<String, Object?> map) => Assignment(
    id: map['id']! as String,
    courseId: map['course_id']! as String,
    title: map['title']! as String,
    rubricId: map['rubric_id']! as String,
    rubricRevision: map['rubric_revision']! as int,
    createdAt: DateTime.parse(map['created_at']! as String),
  );
}

class LedgerEntry {
  const LedgerEntry({
    required this.sequence,
    required this.assignmentId,
    required this.studentId,
    required this.criterionId,
    required this.kind,
    this.levelId,
    required this.recordedAt,
    this.note = '',
  });

  final int sequence;
  final String assignmentId;
  final String studentId;
  final String criterionId;
  final MarkKind kind;
  final String? levelId;
  final DateTime recordedAt;
  final String note;

  Mark toMark() => Mark(
    studentId: studentId,
    criterionId: criterionId,
    kind: kind,
    levelId: levelId,
    recordedAt: recordedAt,
    note: note,
  );

  Map<String, Object?> toMap() => {
    'sequence': sequence,
    'assignment_id': assignmentId,
    'student_id': studentId,
    'criterion_id': criterionId,
    'kind': kind.name,
    'level_id': levelId,
    'recorded_at': recordedAt.toUtc().toIso8601String(),
    'note': note,
  };

  factory LedgerEntry.fromMap(Map<String, Object?> map) => LedgerEntry(
    sequence: map['sequence']! as int,
    assignmentId: map['assignment_id']! as String,
    studentId: map['student_id']! as String,
    criterionId: map['criterion_id']! as String,
    kind: MarkKind.values.byName(map['kind']! as String),
    levelId: map['level_id'] as String?,
    recordedAt: DateTime.parse(map['recorded_at']! as String),
    note: (map['note'] as String?) ?? '',
  );
}

/// Serializes and deserializes Rubric revision snapshots to JSON for storage.
String rubricToJson(Rubric rubric) => jsonEncode({
  'id': rubric.id,
  'revision': rubric.revision,
  'title': rubric.title,
  'criteria': rubric.criteria
      .map(
        (c) => {
          'id': c.id,
          'name': c.name,
          'weight': c.weight,
          'levels': c.levels
              .map((l) => {'id': l.id, 'points': l.points, 'label': l.label})
              .toList(),
        },
      )
      .toList(),
  'bands': rubric.bands
      .map((b) => {'minimumPercent': b.minimumPercent, 'label': b.label})
      .toList(),
});

Rubric rubricFromJson(String raw) {
  final map = jsonDecode(raw) as Map<String, Object?>;
  final criteria = (map['criteria'] as List).cast<Map<String, Object?>>().map((
    c,
  ) {
    final levels = (c['levels'] as List).cast<Map<String, Object?>>().map((l) {
      return Level(
        id: l['id']! as String,
        points: l['points']! as int,
        label: (l['label'] as String?) ?? '',
      );
    }).toList();
    return Criterion(
      id: c['id']! as String,
      name: c['name']! as String,
      weight: c['weight']! as int,
      levels: levels,
    );
  }).toList();
  final bands =
      (map['bands'] as List?)?.cast<Map<String, Object?>>().map((b) {
        return Band(
          minimumPercent: b['minimumPercent']! as int,
          label: b['label']! as String,
        );
      }).toList() ??
      const <Band>[];
  return Rubric(
    id: map['id']! as String,
    revision: map['revision']! as int,
    title: map['title']! as String,
    criteria: criteria,
    bands: bands,
  );
}

/// Canonical SQL statements for schema migrations.
/// Pure Dart strings so they run in sqlite3 or in-memory drivers across all platforms.
class Migrations {
  static const int currentVersion = 1;

  /// Ordered migration steps. Runs inside an exclusive transaction.
  static const List<String> v1 = [
    '''
    CREATE TABLE IF NOT EXISTS schema_version (
      version INTEGER NOT NULL PRIMARY KEY,
      applied_at TEXT NOT NULL
    );
    ''',
    '''
    CREATE TABLE IF NOT EXISTS rubrics (
      id TEXT NOT NULL,
      revision INTEGER NOT NULL,
      title TEXT NOT NULL,
      body_json TEXT NOT NULL,
      created_at TEXT NOT NULL,
      PRIMARY KEY (id, revision)
    );
    ''',
    '''
    CREATE TABLE IF NOT EXISTS assignments (
      id TEXT NOT NULL PRIMARY KEY,
      course_id TEXT NOT NULL,
      title TEXT NOT NULL,
      rubric_id TEXT NOT NULL,
      rubric_revision INTEGER NOT NULL,
      created_at TEXT NOT NULL,
      FOREIGN KEY (rubric_id, rubric_revision) REFERENCES rubrics(id, revision)
    );
    ''',
    '''
    CREATE TABLE IF NOT EXISTS mark_ledger (
      sequence INTEGER PRIMARY KEY AUTOINCREMENT,
      assignment_id TEXT NOT NULL,
      student_id TEXT NOT NULL,
      criterion_id TEXT NOT NULL,
      kind TEXT NOT NULL,
      level_id TEXT,
      note TEXT NOT NULL DEFAULT '',
      recorded_at TEXT NOT NULL,
      FOREIGN KEY (assignment_id) REFERENCES assignments(id)
    );
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_ledger_assignment_student
      ON mark_ledger(assignment_id, student_id, criterion_id, sequence);
    ''',
    '''
    CREATE VIEW IF NOT EXISTS current_marks AS
      SELECT l.*
      FROM mark_ledger l
      INNER JOIN (
        SELECT assignment_id, student_id, criterion_id, MAX(sequence) as max_seq
        FROM mark_ledger
        GROUP BY assignment_id, student_id, criterion_id
      ) latest
      ON l.assignment_id = latest.assignment_id
        AND l.student_id = latest.student_id
        AND l.criterion_id = latest.criterion_id
        AND l.sequence = latest.max_seq;
    ''',
  ];
}

/// In-memory implementation of the ledger repository.
///
/// Uses standard Dart map storage to keep tests hermetic without platform C-bindings,
/// matching the exact SQLite schema and query semantics.
class MemoryLedgerRepository {
  final Map<String, Map<int, Rubric>> _rubrics = {};
  final Map<String, Assignment> _assignments = {};
  final List<LedgerEntry> _ledger = [];
  int _sequence = 0;

  void saveRubricRevision(Rubric rubric) {
    final revisions = _rubrics.putIfAbsent(rubric.id, () => {});
    if (revisions.containsKey(rubric.revision)) {
      throw StateError(
        'rubric ${rubric.id} revision ${rubric.revision} already exists and is immutable',
      );
    }
    revisions[rubric.revision] = rubric;
  }

  Rubric? getRubricRevision(String id, int revision) => _rubrics[id]?[revision];

  void createAssignment(Assignment assignment) {
    if (_assignments.containsKey(assignment.id)) {
      throw StateError('assignment ${assignment.id} already exists');
    }
    final rubric = getRubricRevision(
      assignment.rubricId,
      assignment.rubricRevision,
    );
    if (rubric == null) {
      throw StateError(
        'pinned rubric revision ${assignment.rubricId}#${assignment.rubricRevision} does not exist',
      );
    }
    _assignments[assignment.id] = assignment;
  }

  Assignment? getAssignment(String id) => _assignments[id];

  /// Appends a new mark to the ledger. Never mutates previous rows.
  LedgerEntry appendMark({
    required String assignmentId,
    required String studentId,
    required String criterionId,
    required MarkKind kind,
    String? levelId,
    String note = '',
    DateTime? recordedAt,
  }) {
    final assignment = _assignments[assignmentId];
    if (assignment == null) {
      throw StateError('unknown assignment $assignmentId');
    }
    final rubric = getRubricRevision(
      assignment.rubricId,
      assignment.rubricRevision,
    );
    if (rubric == null) {
      throw StateError('corrupted assignment rubric link');
    }
    final criterion = rubric.criteria
        .where((c) => c.id == criterionId)
        .firstOrNull;
    if (criterion == null) {
      throw ArgumentError('unknown criterion $criterionId');
    }
    if (kind == MarkKind.level) {
      if (levelId == null || !criterion.levels.any((l) => l.id == levelId)) {
        throw ArgumentError('invalid levelId $levelId');
      }
    } else if (levelId != null) {
      throw ArgumentError('excused mark cannot have levelId');
    }

    _sequence += 1;
    final entry = LedgerEntry(
      sequence: _sequence,
      assignmentId: assignmentId,
      studentId: studentId,
      criterionId: criterionId,
      kind: kind,
      levelId: levelId,
      recordedAt: recordedAt ?? DateTime.now(),
      note: note,
    );
    _ledger.add(entry);
    return entry;
  }

  /// Resolves the latest mark per criterion for one student in an assignment.
  List<Mark> currentMarksFor({
    required String assignmentId,
    required String studentId,
  }) {
    final latest = <String, LedgerEntry>{};
    for (final entry in _ledger) {
      if (entry.assignmentId == assignmentId && entry.studentId == studentId) {
        latest[entry.criterionId] = entry;
      }
    }
    return latest.values.map((e) => e.toMark()).toList();
  }

  /// Full append-only audit trail for verification.
  List<LedgerEntry> auditTrailForAssignment(String assignmentId) =>
      _ledger.where((e) => e.assignmentId == assignmentId).toList();

  /// Scores a student using the pinned rubric revision and current marks.
  StudentScore score({
    required String assignmentId,
    required String studentId,
  }) {
    final assignment = _assignments[assignmentId];
    if (assignment == null) {
      throw StateError('unknown assignment $assignmentId');
    }
    final rubric = getRubricRevision(
      assignment.rubricId,
      assignment.rubricRevision,
    )!;
    final marks = currentMarksFor(
      assignmentId: assignmentId,
      studentId: studentId,
    );
    return scoreStudent(rubric, marks);
  }
}
