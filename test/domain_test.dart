import 'package:flutter_test/flutter_test.dart';
import 'package:rubric_desk/domain/database.dart';
import 'package:rubric_desk/domain/ledger.dart';
import 'package:rubric_desk/domain/scoring.dart';

final now = DateTime.utc(2026, 10, 26);

Rubric rubric({int revision = 1}) => Rubric(
  id: 'writing',
  title: 'Writing',
  revision: revision,
  criteria: const [
    Criterion(
      id: 'ideas',
      name: 'Ideas',
      weight: 3,
      levels: [
        Level(id: 'zero', points: 0),
        Level(id: 'half', points: 2),
        Level(id: 'full', points: 4),
      ],
    ),
    Criterion(
      id: 'style',
      name: 'Style',
      weight: 1,
      levels: [
        Level(id: 'zero', points: 0),
        Level(id: 'full', points: 2),
      ],
    ),
  ],
  bands: const [
    Band(minimumPercent: 0, label: 'Needs work'),
    Band(minimumPercent: 50, label: 'Developing'),
    Band(minimumPercent: 75, label: 'Strong'),
  ],
);

Mark level(String criterion, String value) => Mark.level(
  studentId: 's1',
  criterionId: criterion,
  levelId: value,
  recordedAt: now,
);
Mark excused(String criterion) =>
    Mark.excused(studentId: 's1', criterionId: criterion, recordedAt: now);

void main() {
  test('unknown never means zero; explicitly chosen zero is zero', () {
    final unknown = scoreStudent(rubric(), [level('style', 'full')]);
    expect(unknown.total, isNull);
    expect(unknown.incomplete, isTrue);
    expect(unknown.unmarkedCriteria, ['ideas']);
    expect(unknown.breakdown.first.earned, isNull);

    final explicitZero = scoreStudent(rubric(), [
      level('ideas', 'zero'),
      level('style', 'full'),
    ]);
    expect(explicitZero.total, Rational(1, 4));
    expect(explicitZero.percent, 25);
    expect(explicitZero.breakdown.first.earned, 0);
    expect(explicitZero.incomplete, isFalse);
  });

  test('uneven weights, excused denominator and all-excused', () {
    final mixed = scoreStudent(rubric(), [
      level('ideas', 'half'),
      level('style', 'full'),
    ]);
    expect(mixed.total, Rational(5, 8)); // (3 * 2/4 + 1 * 2/2) / 4
    expect(mixed.percent, 63);
    expect(mixed.countedWeight, 4);
    expect(mixed.band, 'Developing');

    final withExcuse = scoreStudent(rubric(), [
      level('ideas', 'half'),
      excused('style'),
    ]);
    expect(withExcuse.total, Rational(1, 2));
    expect(withExcuse.countedWeight, 3);
    expect(withExcuse.excusedWeight, 1);
    expect(withExcuse.excusedCriteria, ['style']);
    expect(withExcuse.breakdown.last.counted, isFalse);

    final all = scoreStudent(rubric(), [excused('ideas'), excused('style')]);
    expect(all.total, isNull);
    expect(all.allExcused, isTrue);
    expect(all.incomplete, isFalse);
    expect(() => all.percent, throwsStateError);
  });

  test('band lower edges are inclusive, exact and not rounded early', () {
    expect(
      scoreStudent(rubric(), [level('ideas', 'half'), excused('style')]).band,
      'Developing',
    ); // exact 50%
    expect(
      scoreStudent(rubric(), [
        level('ideas', 'full'),
        level('style', 'zero'),
      ]).band,
      'Strong',
    ); // exact 75%
    expect(
      scoreStudent(rubric(), [
        level('ideas', 'half'),
        level('style', 'zero'),
      ]).band,
      'Needs work',
    ); // 37.5%
  });

  test('revision, level, mark and band validation', () {
    expect(() => rubric(revision: 0), throwsArgumentError);
    expect(
      () => Rubric(id: 'x', title: 'X', revision: 1, criteria: const []),
      throwsArgumentError,
    );
    expect(
      () => Rubric(
        id: 'x',
        title: 'X',
        revision: 1,
        criteria: const [
          Criterion(
            id: 'a',
            name: 'A',
            weight: 0,
            levels: [
              Level(id: 'z', points: 0),
              Level(id: 'f', points: 1),
            ],
          ),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => Rubric(
        id: 'x',
        title: 'X',
        revision: 1,
        criteria: const [
          Criterion(
            id: 'a',
            name: 'A',
            weight: 1,
            levels: [
              Level(id: 'f', points: 2),
              Level(id: 'z', points: 0),
            ],
          ),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => Rubric(
        id: 'x',
        title: 'X',
        revision: 1,
        criteria: rubric().criteria,
        bands: const [
          Band(minimumPercent: 75, label: 'A'),
          Band(minimumPercent: 50, label: 'B'),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => scoreStudent(rubric(), [level('ideas', 'bogus')]),
      throwsArgumentError,
    );
    expect(
      () => scoreStudent(rubric(), [
        level('ideas', 'full'),
        level('ideas', 'full'),
      ]),
      throwsArgumentError,
    );
    expect(
      () => scoreStudent(rubric(), [
        Mark.excused(studentId: 's1', criterionId: 'alien', recordedAt: now),
      ]),
      throwsArgumentError,
    );
  });

  test(
    'SQLite migration is idempotent; revision pinned; ledger appends only',
    () {
      final db = SqliteLedgerDatabase.inMemory();
      addTearDown(db.close);
      expect(db.currentVersion, 2);
      db.migrate();
      expect(db.currentVersion, 2);
      final v1 = rubric();
      db.saveRubricRevision(v1);
      final assignment = Assignment(
        id: 'assignment-1',
        courseId: 'class-1',
        title: 'Essay',
        rubricId: 'writing',
        rubricRevision: 1,
        createdAt: now,
      );
      db.createAssignment(assignment);
      expect(db.getAssignment('assignment-1')?.rubricRevision, 1);
      expect(() => db.saveRubricRevision(v1), throwsStateError);

      final v2 = v1.nextRevision(
        criteria: [
          v1.criteria.first,
          const Criterion(
            id: 'style',
            name: 'Style revised',
            weight: 10,
            levels: [
              Level(id: 'zero', points: 0),
              Level(id: 'full', points: 2),
            ],
          ),
        ],
      );
      db.saveRubricRevision(v2);
      expect(db.getRubricRevision('writing', 2)!.criteria.last.weight, 10);
      expect(db.getRubricRevision('writing', 1)!.criteria.last.weight, 1);
      expect(
        db.score(assignmentId: 'assignment-1', studentId: 's1').total,
        isNull,
      );

      final first = db.appendMark(
        assignmentId: 'assignment-1',
        studentId: 's1',
        criterionId: 'ideas',
        kind: MarkKind.level,
        levelId: 'zero',
        recordedAt: now,
      );
      final second = db.appendMark(
        assignmentId: 'assignment-1',
        studentId: 's1',
        criterionId: 'ideas',
        kind: MarkKind.level,
        levelId: 'full',
        recordedAt: now,
      );
      final third = db.appendMark(
        assignmentId: 'assignment-1',
        studentId: 's1',
        criterionId: 'style',
        kind: MarkKind.excused,
        recordedAt: now,
      );
      expect([first.sequence, second.sequence, third.sequence], [1, 2, 3]);
      expect(db.auditTrail('assignment-1').length, 3);
      expect(
        db
            .currentMarksFor(assignmentId: 'assignment-1', studentId: 's1')
            .length,
        2,
      );
      final result = db.score(assignmentId: 'assignment-1', studentId: 's1');
      expect(result.total, Rational(1, 1));
      expect(result.excusedCriteria, ['style']);
      expect(result.countedWeight, 3); // old revision, not 10
      expect(
        () => db.appendMark(
          assignmentId: 'assignment-1',
          studentId: 's1',
          criterionId: 'ideas',
          kind: MarkKind.level,
          levelId: 'alien',
        ),
        throwsArgumentError,
      );
      expect(db.auditTrail('assignment-1').length, 3);
    },
  );

  test('JSON rubric snapshot round trips and rejects invalid revisions', () {
    final decoded = rubricFromJson(rubricToJson(rubric()));
    expect(decoded.revision, 1);
    expect(decoded.criteria.first.levels[1].points, 2);
    expect(decoded.bands.last.minimumPercent, 75);
    expect(
      () => rubricFromJson('{"id":"x","revision":0,"title":"X","criteria":[]}'),
      throwsArgumentError,
    );
  });
}
