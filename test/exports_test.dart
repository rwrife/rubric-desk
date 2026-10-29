import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rubric_desk/domain/database.dart';
import 'package:rubric_desk/domain/exports.dart';
import 'package:rubric_desk/domain/ledger.dart';
import 'package:rubric_desk/domain/scoring.dart';

void main() {
  test(
    'exports unknown, excused and formula-like labels without fake totals',
    () {
      final rubric = Rubric(
        id: 'r',
        revision: 1,
        title: 'Rubric',
        criteria: [
          Criterion(
            id: 'c',
            name: 'Criterion',
            weight: 1,
            levels: [
              Level(id: 'z', points: 0, label: 'Zero'),
              Level(id: 'one', points: 1, label: 'One'),
            ],
          ),
        ],
      );
      final assignment = Assignment(
        id: 'a',
        courseId: 'course',
        title: '=task',
        rubricId: 'r',
        rubricRevision: 1,
        createdAt: DateTime.utc(2026),
      );
      final unknown = scoreStudent(rubric, []);
      final excused = scoreStudent(rubric, [
        Mark.excused(
          studentId: 's',
          criterionId: 'c',
          recordedAt: DateTime.utc(2026),
        ),
      ]);
      final zero = scoreStudent(rubric, [
        Mark.level(
          studentId: 's',
          criterionId: 'c',
          levelId: 'z',
          recordedAt: DateTime.utc(2026),
        ),
      ]);
      expect(
        gradeCsv(assignment, [
          (label: ' =cmd', score: unknown),
          (label: '@evil', score: excused),
          (label: 'Zero', score: zero),
        ]),
        contains('"\' =cmd","\'=task","","incomplete"'),
      );
      expect(
        gradeCsv(assignment, [(label: '@evil', score: excused)]),
        contains('"","all excused"'),
      );
      expect(
        gradeCsv(assignment, [(label: 'Zero', score: zero)]),
        contains('"0%"'),
      );
      expect(
        feedbackText('Student', assignment, unknown),
        contains('unmarked (unknown)'),
      );
      expect(printableRubric(rubric), contains('Zero: 0/1'));
    },
  );

  test(
    'backup round trip keeps sequence and rolls back malformed references',
    () {
      final source = SqliteLedgerDatabase.inMemory();
      final target = SqliteLedgerDatabase.inMemory();
      addTearDown(source.close);
      addTearDown(target.close);
      source.saveCourse('course', 'Class');
      source.saveStudent('s', 'course', 'Student');
      source.saveRubricRevision(
        Rubric(
          id: 'r',
          revision: 1,
          title: 'Rubric',
          criteria: [
            Criterion(
              id: 'c',
              name: 'Criterion',
              weight: 1,
              levels: [
                Level(id: 'z', points: 0),
                Level(id: 'one', points: 1),
              ],
            ),
          ],
        ),
      );
      source.createAssignment(
        Assignment(
          id: 'a',
          courseId: 'course',
          title: 'Task',
          rubricId: 'r',
          rubricRevision: 1,
          createdAt: DateTime.utc(2026),
        ),
      );
      source.appendMark(
        assignmentId: 'a',
        studentId: 's',
        criterionId: 'c',
        kind: MarkKind.level,
        levelId: 'one',
      );
      source.appendMark(
        assignmentId: 'a',
        studentId: 's',
        criterionId: 'c',
        kind: MarkKind.excused,
      );
      final raw = source.exportBackup();
      target.saveCourse('old', 'Existing');
      expect(target.previewBackup(raw)['mark_ledger'], 2);
      expect(target.courses.single.id, 'old');
      target.restoreBackup(raw);
      expect(target.courses.single.label, 'Class');
      expect(target.auditTrail('a').map((e) => e.sequence), [1, 2]);
      expect(
        target.score(assignmentId: 'a', studentId: 's').allExcused,
        isTrue,
      );
      final bad = jsonDecode(raw) as Map<String, dynamic>;
      (bad['tables']['mark_ledger'] as List).first['student_id'] = 'missing';
      expect(
        () => target.restoreBackup(jsonEncode(bad)),
        throwsA(isA<Exception>()),
      );
      expect(target.exportBackup(), raw);
      expect(
        () => target.previewBackup('{"version":2}'),
        throwsFormatException,
      );
    },
  );
}
