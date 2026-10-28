import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:rubric_desk/domain/database.dart';
import 'package:rubric_desk/domain/ledger.dart';
import 'package:rubric_desk/domain/scoring.dart';
import 'package:rubric_desk/scoring_workspace.dart';

void main() {
  late SqliteLedgerDatabase db;
  late Assignment assignment;

  setUp(() {
    db = SqliteLedgerDatabase.inMemory();
    db.saveCourse('course', 'Biology');
    db.saveStudent('student', 'course', 'Student A');
    db.saveRubricRevision(
      Rubric(
        id: 'rubric',
        revision: 1,
        title: 'Lab',
        criteria: [
          Criterion(
            id: 'evidence',
            name: 'Evidence',
            weight: 2,
            levels: [
              const Level(id: 'none', points: 0, label: 'None'),
              const Level(id: 'good', points: 4, label: 'Good'),
            ],
          ),
          Criterion(
            id: 'reason',
            name: 'Reasoning',
            weight: 1,
            levels: [
              const Level(id: 'none', points: 0, label: 'None'),
              const Level(id: 'good', points: 4, label: 'Good'),
            ],
          ),
        ],
      ),
    );
    assignment = Assignment(
      id: 'a',
      courseId: 'course',
      title: 'First lab',
      rubricId: 'rubric',
      rubricRevision: 1,
      createdAt: DateTime.utc(2026),
    );
    db.createAssignment(assignment);
  });

  tearDown(() => db.close());

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.windows,
  ]) {
    for (final width in [390.0, 800.0, 1280.0]) {
      testWidgets(
        '$platform width $width: native shell, layout and unknown-safe marks',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });
          final page = ScoringWorkspaceLayout(
            store: db,
            assignment: assignment,
            platform: platform,
          );
          await tester.pumpWidget(switch (platform) {
            TargetPlatform.iOS => CupertinoApp(home: page),
            TargetPlatform.windows => fluent.FluentApp(home: page),
            _ => material.MaterialApp(home: page),
          });
          expect(
            find.byType(CupertinoPageScaffold),
            platform == TargetPlatform.iOS ? findsOneWidget : findsNothing,
          );
          expect(
            find.byType(fluent.ScaffoldPage),
            platform == TargetPlatform.windows ? findsOneWidget : findsNothing,
          );
          expect(
            find.byType(material.Scaffold),
            platform == TargetPlatform.android ? findsOneWidget : findsNothing,
          );
          expect(find.byKey(const Key('score-inspector')), findsOneWidget);
          expect(find.text('Incomplete · no total'), findsOneWidget);
          if (width < 600) {
            expect(find.byKey(const Key('desktop-grid')), findsNothing);
            expect(find.byKey(const Key('tablet-grid')), findsNothing);
          } else {
            expect(
              find.byKey(Key(width < 1000 ? 'tablet-grid' : 'desktop-grid')),
              findsOneWidget,
            );
          }
          await tester.tap(find.byKey(const Key('level-0')));
          await tester.pump();
          expect(
            db.score(assignmentId: 'a', studentId: 'student').total,
            isNull,
          );
          expect(find.text('0/4 points'), findsOneWidget);
          await tester.tap(find.byKey(const Key('excuse')));
          await tester.pump();
          expect(
            find.text('Excused · excluded from denominator'),
            findsOneWidget,
          );
          expect(db.auditTrail('a').length, 2);
          await tester.tap(find.byKey(const Key('unmark')));
          await tester.pump();
          expect(find.text('Unmarked (unknown)'), findsOneWidget);
          expect(db.auditTrail('a').length, 3);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'undo appends previous mark, note survives, excused changes denominator',
    (tester) async {
      await tester.pumpWidget(
        material.MaterialApp(
          home: ScoringWorkspaceLayout(
            store: db,
            assignment: assignment,
            platform: TargetPlatform.android,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('mark-note')),
        'Quoted evidence',
      );
      await tester.tap(find.byKey(const Key('level-1')));
      await tester.pump();
      expect(
        db.currentMarksFor(assignmentId: 'a', studentId: 'student').single.note,
        'Quoted evidence',
      );
      await tester.tap(find.byKey(const Key('excuse')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('undo-mark')));
      await tester.pump();
      expect(
        db
            .currentMarksFor(assignmentId: 'a', studentId: 'student')
            .single
            .levelId,
        'good',
      );
      expect(db.auditTrail('a').length, 3);
      await tester.tap(find.byKey(const Key('criterion-reason')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('excuse')));
      await tester.pump();
      expect(db.score(assignmentId: 'a', studentId: 'student').percent, 100);
      expect(find.textContaining('1 excused'), findsWidgets);
    },
  );
}
