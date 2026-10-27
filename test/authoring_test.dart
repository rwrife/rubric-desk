import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter_test/flutter_test.dart';
import 'package:rubric_desk/domain/database.dart';
import 'package:rubric_desk/domain/ledger.dart';
import 'package:rubric_desk/domain/scoring.dart';
import 'package:rubric_desk/main.dart';

void main() {
  test('roster persists; published assignment retains old rubric', () {
    final dir = Directory.systemTemp.createTempSync('rubric-desk-test');
    final path = '${dir.path}/grades.sqlite';
    try {
      final db = SqliteLedgerDatabase.open(path);
      db.saveCourse('c', 'History');
      db.saveStudent('s', 'c', 'Learner A');
      final first = Rubric(
        id: 'r',
        revision: 1,
        title: 'Essay',
        criteria: [
          const Criterion(
            id: 'argument',
            name: 'Argument',
            weight: 2,
            levels: [
              Level(id: 'low', points: 0),
              Level(id: 'high', points: 2),
            ],
          ),
        ],
      );
      db.saveRubricRevision(first);
      db.createAssignment(
        Assignment(
          id: 'a',
          courseId: 'c',
          title: 'Paper',
          rubricId: 'r',
          rubricRevision: 1,
          createdAt: DateTime.utc(2026),
        ),
      );
      db.close();
      final reopened = SqliteLedgerDatabase.open(path);
      expect(reopened.currentVersion, 2);
      expect(reopened.courses.single.label, 'History');
      expect(reopened.students('c').single.label, 'Learner A');
      reopened.saveRubricRevision(
        first.nextRevision(
          criteria: [
            const Criterion(
              id: 'argument',
              name: 'Argument',
              weight: 5,
              levels: [
                Level(id: 'low', points: 0),
                Level(id: 'high', points: 4),
              ],
            ),
          ],
        ),
      );
      expect(reopened.assignments('c').single.rubricRevision, 1);
      expect(reopened.getRubricRevision('r', 1)!.criteria.single.weight, 2);
      expect(reopened.latestRubrics.single.revision, 2);
      reopened.close();
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  testWidgets('iOS authoring uses Cupertino fields', (tester) async {
    final db = SqliteLedgerDatabase.inMemory();
    addTearDown(db.close);
    await tester.pumpWidget(
      RubricDeskApp(platformOverride: TargetPlatform.iOS, store: db),
    );
    expect(find.byType(CupertinoTextField), findsWidgets);
    expect(find.byType(TextField), findsNothing);
    await tester.enterText(find.byType(CupertinoTextField).first, 'Math');
    await tester.tap(find.text('Create course'));
    await tester.pumpAndSettle();
    expect(db.courses.single.label, 'Math');
  });

  testWidgets('Android authoring uses Material fields', (tester) async {
    final db = SqliteLedgerDatabase.inMemory();
    addTearDown(db.close);
    await tester.pumpWidget(
      RubricDeskApp(platformOverride: TargetPlatform.android, store: db),
    );
    expect(find.byType(TextField), findsWidgets);
    expect(find.byType(CupertinoTextField), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'Math');
    await tester.tap(find.text('Create course'));
    await tester.pumpAndSettle();
    expect(db.courses.single.label, 'Math');
  });

  testWidgets('Windows authoring uses Fluent controls', (tester) async {
    final db = SqliteLedgerDatabase.inMemory();
    addTearDown(db.close);
    await tester.pumpWidget(
      RubricDeskApp(platformOverride: TargetPlatform.windows, store: db),
    );
    expect(find.byType(fluent.TextBox), findsWidgets);
    await tester.enterText(find.byType(fluent.TextBox).first, 'Math');
    await tester.tap(find.text('Create course'));
    await tester.pumpAndSettle();
    expect(db.courses.single.label, 'Math');
  });
}
