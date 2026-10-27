import 'package:sqlite3/sqlite3.dart';
import 'package:rubric_desk/domain/ledger.dart';
import 'package:rubric_desk/domain/scoring.dart';

/// Real SQLite storage engine backing the local gradebook.
///
/// Features:
/// * Runs transactional migrations using PRAGMA user_version;
/// * Persists immutable rubric revision JSON;
/// * Appends every mark into the ledger with auto-incrementing sequence;
/// * Queries latest marks per criterion via a deterministic view;
/// * Works in-memory (sqlite3.openInMemory()) for unit tests, or with a file path.
class SqliteLedgerDatabase {
  SqliteLedgerDatabase(this._db);

  final Database _db;

  factory SqliteLedgerDatabase.inMemory() {
    final db = sqlite3.openInMemory();
    final instance = SqliteLedgerDatabase(db);
    instance.migrate();
    return instance;
  }

  factory SqliteLedgerDatabase.open(String path) {
    final db = sqlite3.open(path);
    final instance = SqliteLedgerDatabase(db);
    instance.migrate();
    return instance;
  }

  void close() => _db.close();

  int get currentVersion {
    final result = _db.select('PRAGMA user_version;');
    return result.first.values.first as int;
  }

  /// Runs missing migrations up to [Migrations.currentVersion] inside a transaction.
  void migrate() {
    _db.execute('PRAGMA foreign_keys = ON;');
    final version = currentVersion;
    if (version > Migrations.currentVersion) {
      throw StateError(
        'database schema $version is newer than supported ${Migrations.currentVersion}',
      );
    }
    if (version < 1) {
      _db.execute('BEGIN IMMEDIATE TRANSACTION;');
      try {
        for (final statement in Migrations.v1) {
          _db.execute(statement);
        }
        _db.execute(
          'INSERT INTO schema_version (version, applied_at) VALUES (1, ?);',
          [DateTime.now().toUtc().toIso8601String()],
        );
        _db.execute('PRAGMA user_version = 1;');
        _db.execute('COMMIT;');
      } catch (e) {
        _db.execute('ROLLBACK;');
        rethrow;
      }
    }
    if (version < 2) {
      _db.execute('BEGIN IMMEDIATE TRANSACTION;');
      try {
        for (final statement in Migrations.v2) {
          _db.execute(statement);
        }
        _db.execute('PRAGMA user_version = 2;');
        _db.execute('COMMIT;');
      } catch (_) {
        _db.execute('ROLLBACK;');
        rethrow;
      }
    }
  }

  List<({String id, String label})> get courses => _db
      .select('SELECT id, label FROM courses ORDER BY label, id;')
      .map((r) => (id: r['id'] as String, label: r['label'] as String))
      .toList();

  List<({String id, String label})> students(String courseId) => _db
      .select(
        'SELECT id, label FROM students WHERE course_id = ? ORDER BY label, id;',
        [courseId],
      )
      .map((r) => (id: r['id'] as String, label: r['label'] as String))
      .toList();

  void saveCourse(String id, String label) {
    if (id.isEmpty || label.trim().isEmpty) {
      throw ArgumentError('course label required');
    }
    _db.execute(
      'INSERT INTO courses (id, label) VALUES (?, ?) '
      'ON CONFLICT(id) DO UPDATE SET label = excluded.label;',
      [id, label.trim()],
    );
  }

  void saveStudent(String id, String courseId, String label) {
    if (id.isEmpty || label.trim().isEmpty) {
      throw ArgumentError('student label required');
    }
    _db.execute(
      'INSERT INTO students (id, course_id, label) VALUES (?, ?, ?) '
      'ON CONFLICT(id) DO UPDATE SET label = excluded.label WHERE course_id = excluded.course_id;',
      [id, courseId, label.trim()],
    );
  }

  List<Rubric> get latestRubrics => _db
      .select(
        'SELECT r.body_json FROM rubrics r WHERE revision = '
        '(SELECT MAX(revision) FROM rubrics WHERE id = r.id) ORDER BY r.title, r.id;',
      )
      .map((r) => rubricFromJson(r['body_json'] as String))
      .toList();

  List<Assignment> assignments(String courseId) => _db
      .select(
        'SELECT id FROM assignments WHERE course_id = ? ORDER BY created_at, id;',
        [courseId],
      )
      .map((r) => getAssignment(r['id'] as String)!)
      .toList();

  void saveRubricRevision(Rubric rubric) {
    final existing = _db.select(
      'SELECT id FROM rubrics WHERE id = ? AND revision = ?;',
      [rubric.id, rubric.revision],
    );
    if (existing.isNotEmpty) {
      throw StateError(
        'rubric ${rubric.id} revision ${rubric.revision} already exists (immutable)',
      );
    }
    _db.execute(
      'INSERT INTO rubrics (id, revision, title, body_json, created_at) VALUES (?, ?, ?, ?, ?);',
      [
        rubric.id,
        rubric.revision,
        rubric.title,
        rubricToJson(rubric),
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  Rubric? getRubricRevision(String id, int revision) {
    final rows = _db.select(
      'SELECT body_json FROM rubrics WHERE id = ? AND revision = ?;',
      [id, revision],
    );
    if (rows.isEmpty) return null;
    return rubricFromJson(rows.first['body_json'] as String);
  }

  void createAssignment(Assignment assignment) {
    final rubric = getRubricRevision(
      assignment.rubricId,
      assignment.rubricRevision,
    );
    if (rubric == null) {
      throw StateError(
        'cannot pin missing rubric revision ${assignment.rubricId}#${assignment.rubricRevision}',
      );
    }
    _db.execute(
      'INSERT INTO assignments (id, course_id, title, rubric_id, rubric_revision, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?);',
      [
        assignment.id,
        assignment.courseId,
        assignment.title,
        assignment.rubricId,
        assignment.rubricRevision,
        assignment.createdAt.toUtc().toIso8601String(),
      ],
    );
  }

  Assignment? getAssignment(String id) {
    final rows = _db.select('SELECT * FROM assignments WHERE id = ?;', [id]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return Assignment(
      id: row['id'] as String,
      courseId: row['course_id'] as String,
      title: row['title'] as String,
      rubricId: row['rubric_id'] as String,
      rubricRevision: row['rubric_revision'] as int,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  /// Appends one mark into the ledger. Never mutates history.
  LedgerEntry appendMark({
    required String assignmentId,
    required String studentId,
    required String criterionId,
    required MarkKind kind,
    String? levelId,
    String note = '',
    DateTime? recordedAt,
  }) {
    final assignment = getAssignment(assignmentId);
    if (assignment == null) {
      throw StateError('unknown assignment $assignmentId');
    }
    final rubric = getRubricRevision(
      assignment.rubricId,
      assignment.rubricRevision,
    )!;
    final criterion = rubric.criteria
        .where((c) => c.id == criterionId)
        .firstOrNull;
    if (criterion == null) {
      throw ArgumentError('unknown criterion $criterionId');
    }
    if (kind == MarkKind.level) {
      if (levelId == null || !criterion.levels.any((l) => l.id == levelId)) {
        throw ArgumentError(
          'invalid levelId $levelId for criterion $criterionId',
        );
      }
    } else if (levelId != null) {
      throw ArgumentError('excused mark cannot carry a levelId');
    }

    final ts = (recordedAt ?? DateTime.now()).toUtc();
    _db.execute(
      'INSERT INTO mark_ledger (assignment_id, student_id, criterion_id, kind, level_id, note, recorded_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?);',
      [
        assignmentId,
        studentId,
        criterionId,
        kind.name,
        levelId,
        note,
        ts.toIso8601String(),
      ],
    );
    final lastId = _db.lastInsertRowId;
    return LedgerEntry(
      sequence: lastId,
      assignmentId: assignmentId,
      studentId: studentId,
      criterionId: criterionId,
      kind: kind,
      levelId: levelId,
      recordedAt: ts,
      note: note,
    );
  }

  /// Reads latest marks for one student using the SQL view.
  List<Mark> currentMarksFor({
    required String assignmentId,
    required String studentId,
  }) {
    final rows = _db.select(
      'SELECT student_id, criterion_id, kind, level_id, note, recorded_at '
      'FROM current_marks '
      'WHERE assignment_id = ? AND student_id = ?;',
      [assignmentId, studentId],
    );
    return rows.map((r) {
      return Mark(
        studentId: r['student_id'] as String,
        criterionId: r['criterion_id'] as String,
        kind: MarkKind.values.byName(r['kind'] as String),
        levelId: r['level_id'] as String?,
        note: (r['note'] as String?) ?? '',
        recordedAt: DateTime.parse(r['recorded_at'] as String),
      );
    }).toList();
  }

  /// Full append-only ledger for an assignment.
  List<LedgerEntry> auditTrail(String assignmentId) {
    final rows = _db.select(
      'SELECT sequence, assignment_id, student_id, criterion_id, kind, level_id, note, recorded_at '
      'FROM mark_ledger WHERE assignment_id = ? ORDER BY sequence ASC;',
      [assignmentId],
    );
    return rows.map((r) {
      return LedgerEntry(
        sequence: r['sequence'] as int,
        assignmentId: r['assignment_id'] as String,
        studentId: r['student_id'] as String,
        criterionId: r['criterion_id'] as String,
        kind: MarkKind.values.byName(r['kind'] as String),
        levelId: r['level_id'] as String?,
        note: (r['note'] as String?) ?? '',
        recordedAt: DateTime.parse(r['recorded_at'] as String),
      );
    }).toList();
  }

  /// Resolves the student's score from the pinned revision and current marks.
  StudentScore score({
    required String assignmentId,
    required String studentId,
  }) {
    final assignment = getAssignment(assignmentId);
    if (assignment == null) {
      throw StateError('unknown assignment $assignmentId');
    }
    final rubric = getRubricRevision(
      assignment.rubricId,
      assignment.rubricRevision,
    );
    if (rubric == null) {
      throw StateError('corrupted assignment rubric pin');
    }
    final marks = currentMarksFor(
      assignmentId: assignmentId,
      studentId: studentId,
    );
    return scoreStudent(rubric, marks);
  }
}
