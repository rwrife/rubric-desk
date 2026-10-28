// Rubric Desk scoring domain: pure Dart, no platform or I/O imports.
// PLAN.md contract: revision pinning, unknown-safe scoring, exact fractions.

/// Immutable snapshot of a rubric. Publishing an edit means a new [revision];
/// old revisions stay valid so scored assignments never change underneath.
class Rubric {
  Rubric({
    required this.id,
    required this.revision,
    required this.title,
    required List<Criterion> criteria,
    List<Band> bands = const [],
  }) : criteria = List.unmodifiable(
         criteria.map(
           (c) => Criterion(
             id: c.id,
             name: c.name,
             weight: c.weight,
             levels: List.unmodifiable(c.levels),
           ),
         ),
       ),
       bands = List.unmodifiable(bands) {
    if (id.isEmpty || title.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'rubric id and title are required');
    }
    if (revision < 1) {
      throw ArgumentError.value(revision, 'revision', 'must be >= 1');
    }
    if (criteria.isEmpty) {
      throw ArgumentError.value(
        criteria,
        'criteria',
        'a rubric needs criteria',
      );
    }
    if (criteria.map((c) => c.id).toSet().length != criteria.length) {
      throw ArgumentError('duplicate criterion id');
    }
    for (final criterion in criteria) {
      _validateCriterion(criterion);
    }
    _validateBands(bands);
  }

  final String id;
  final int revision;
  final String title;
  final List<Criterion> criteria;
  final List<Band> bands;

  /// Published copy with an incremented revision; caller supplies new criteria.
  Rubric nextRevision({
    List<Criterion>? criteria,
    List<Band>? bands,
    String? title,
  }) => Rubric(
    id: id,
    revision: revision + 1,
    title: title ?? this.title,
    criteria: criteria ?? this.criteria,
    bands: bands ?? this.bands,
  );

  Criterion criterion(String criterionId) =>
      criteria.firstWhere((c) => c.id == criterionId);
}

void _validateCriterion(Criterion criterion) {
  if (criterion.id.isEmpty || criterion.name.trim().isEmpty) {
    throw ArgumentError.value(
      criterion.id,
      'criterion.id',
      'id and name required',
    );
  }
  if (criterion.weight <= 0) {
    throw ArgumentError.value(
      criterion.weight,
      'weight',
      'weights are positive integers',
    );
  }
  if (criterion.levels.isEmpty) {
    throw ArgumentError.value(
      criterion.levels,
      'levels',
      'a criterion needs ordered levels',
    );
  }
  if (criterion.levels.map((l) => l.id).toSet().length !=
      criterion.levels.length) {
    throw ArgumentError('duplicate level id in ${criterion.id}');
  }
  final points = criterion.levels.map((l) => l.points).toList();
  if (points.first != 0 || points.last <= 0 || !_strictlyIncreasing(points)) {
    throw ArgumentError.value(
      points,
      'levels',
      'levels run from 0 up to a positive maximum, strictly',
    );
  }
}

void _validateBands(List<Band> bands) {
  if (bands.map((b) => b.minimumPercent).toSet().length != bands.length) {
    throw ArgumentError('duplicate band boundary');
  }
  if (!_strictlyIncreasing(bands.map((b) => b.minimumPercent).toList())) {
    throw ArgumentError('band boundaries must ascend');
  }
  for (final band in bands) {
    if (band.label.trim().isEmpty ||
        band.minimumPercent < 0 ||
        band.minimumPercent > 100) {
      throw ArgumentError.value(
        band.minimumPercent,
        'band',
        '0..100 and labelled',
      );
    }
  }
}

bool _strictlyIncreasing(List<int> values) {
  for (var i = 1; i < values.length; i++) {
    if (values[i] <= values[i - 1]) return false;
  }
  return true;
}

class Criterion {
  const Criterion({
    required this.id,
    required this.name,
    required this.weight,
    required this.levels,
  });

  final String id;
  final String name;

  /// Positive integer weight; uneven weights are supported.
  final int weight;

  /// Ordered lowest to highest. `points` are explicit, never implied.
  final List<Level> levels;

  int get maximumPoints => levels.last.points;
}

class Level {
  const Level({required this.id, required this.points, this.label = ''});

  final String id;
  final int points;
  final String label;
}

/// Inclusive lower edge of a reported band, expressed as whole percent.
class Band {
  const Band({required this.minimumPercent, required this.label});

  final int minimumPercent;
  final String label;
}

enum MarkKind {
  /// A selected level ([Mark.levelId] required).
  level,

  /// Explicitly excused: excluded from the denominator and disclosed.
  excused,

  /// Append-only retraction of a previous mark; resolves to unknown.
  unmarked,
}

/// One ledger fact. The ledger itself is append-only (see ledger.dart);
/// scoring only ever receives the resolved current mark per criterion.
class Mark {
  const Mark({
    required this.studentId,
    required this.criterionId,
    required this.kind,
    this.levelId,
    required this.recordedAt,
    this.note = '',
  });

  final String studentId;
  final String criterionId;
  final MarkKind kind;
  final String? levelId;
  final DateTime recordedAt;
  final String note;

  factory Mark.level({
    required String studentId,
    required String criterionId,
    required String levelId,
    required DateTime recordedAt,
    String note = '',
  }) => Mark(
    studentId: studentId,
    criterionId: criterionId,
    kind: MarkKind.level,
    levelId: levelId,
    recordedAt: recordedAt,
    note: note,
  );

  factory Mark.excused({
    required String studentId,
    required String criterionId,
    required DateTime recordedAt,
    String note = '',
  }) => Mark(
    studentId: studentId,
    criterionId: criterionId,
    kind: MarkKind.excused,
    recordedAt: recordedAt,
    note: note,
  );
}

/// Exact fraction so weighting never depends on floating point order.
class Rational {
  Rational(int numerator, int denominator)
    : assert(denominator > 0, 'denominator must be positive'),
      numerator = numerator ~/ _gcd(numerator.abs(), denominator),
      denominator = denominator ~/ _gcd(numerator.abs(), denominator);

  final int numerator;
  final int denominator;

  Rational operator +(Rational other) => Rational(
    numerator * other.denominator + other.numerator * denominator,
    denominator * other.denominator,
  );

  Rational operator /(int scale) =>
      Rational(numerator, denominator * scale); // scale > 0 by callers

  double get asDouble => numerator / denominator;

  /// Whole percent, rounded half away from zero. Presentation only.
  int roundedPercent() =>
      (asDouble * 100 + (asDouble >= 0 ? 0.5 : -0.5)).truncate();

  @override
  String toString() => '$numerator/$denominator';

  @override
  bool operator ==(Object other) =>
      other is Rational &&
      other.numerator == numerator &&
      other.denominator == denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);
}

int _gcd(int a, int b) {
  while (b != 0) {
    final r = a % b;
    a = b;
    b = r;
  }
  return a == 0 ? 1 : a.abs();
}

/// One criterion's contribution, shown to the user next to every total.
class CriterionBreakdown {
  const CriterionBreakdown({
    required this.criterion,
    required this.mark,
    required this.earned,
    required this.counted,
  });

  final Criterion criterion;

  /// Null when the criterion is not marked: unknown, never zero.
  final Mark? mark;

  /// Null unless a level was selected (explicit 0 is a real score).
  final int? earned;

  /// False when excused: excluded from the denominator and disclosed.
  final bool counted;

  bool get excused => mark?.kind == MarkKind.excused;
  // ponytail: retracted rows retain note/history; score treats them as unknown.
  bool get unmarked => mark == null || mark!.kind == MarkKind.unmarked;
}

/// Result of scoring one student against one pinned rubric revision.
class StudentScore {
  const StudentScore({
    required this.breakdown,
    required this.total,
    required this.band,
    required this.countedWeight,
    required this.excusedWeight,
  });

  final List<CriterionBreakdown> breakdown;

  /// Weighted score as a fraction of 1. Null when incomplete or all-excused.
  final Rational? total;

  /// Null whenever [total] is null, or when no band reaches the total.
  final String? band;
  final int countedWeight;
  final int excusedWeight;

  bool get hasTotal => total != null;
  bool get allExcused => breakdown.isNotEmpty && countedWeight == 0;
  bool get incomplete => breakdown.any((b) => b.unmarked);
  List<String> get unmarkedCriteria =>
      breakdown.where((b) => b.unmarked).map((b) => b.criterion.id).toList();
  List<String> get excusedCriteria =>
      breakdown.where((b) => b.excused).map((b) => b.criterion.id).toList();

  /// 0..100 for display; throws when there is no total to display.
  int get percent {
    final value = total;
    if (value == null) {
      throw StateError('no total: incomplete or all-excused');
    }
    return value.roundedPercent();
  }
}

/// Deterministic unknown-safe scorer.
///
/// total = sum(weight_i * earned_i / max_i) / sum(weight_i over non-excused),
/// computed as an exact fraction. Returns no total while any non-excused
/// criterion is unmarked, and no total when everything is excused.
StudentScore scoreStudent(Rubric rubric, List<Mark> marks) {
  final byCriterion = <String, Mark>{};
  for (final mark in marks) {
    if (mark.studentId.isEmpty) throw ArgumentError('mark needs a student id');
    if (!rubric.criteria.any((c) => c.id == mark.criterionId)) {
      throw ArgumentError('mark for unknown criterion ${mark.criterionId}');
    }
    if (byCriterion.containsKey(mark.criterionId)) {
      throw ArgumentError('duplicate current mark for ${mark.criterionId}');
    }
    if (mark.kind == MarkKind.level && mark.levelId == null) {
      throw ArgumentError('level mark needs a level id');
    }
    if (mark.kind != MarkKind.level && mark.levelId != null) {
      throw ArgumentError('non-level mark must not carry a level id');
    }
    byCriterion[mark.criterionId] = mark;
  }

  final breakdown = <CriterionBreakdown>[];
  var countedWeight = 0;
  var excusedWeight = 0;
  var weighted = Rational(0, 1);
  for (final criterion in rubric.criteria) {
    final mark = byCriterion[criterion.id];
    final excused = mark?.kind == MarkKind.excused;
    int? earned;
    if (mark != null && mark.kind == MarkKind.level) {
      final level = criterion.levels
          .where((l) => l.id == mark.levelId)
          .firstOrNull;
      if (level == null) {
        throw ArgumentError(
          'level ${mark.levelId} is not part of ${criterion.id}',
        );
      }
      earned = level.points;
      weighted =
          weighted +
          Rational(level.points * criterion.weight, criterion.maximumPoints);
    }
    if (excused) {
      excusedWeight += criterion.weight;
    } else {
      countedWeight += criterion.weight;
    }
    breakdown.add(
      CriterionBreakdown(
        criterion: criterion,
        mark: mark,
        earned: earned,
        counted: !excused,
      ),
    );
  }

  if (countedWeight == 0 || breakdown.any((b) => b.unmarked)) {
    return StudentScore(
      breakdown: breakdown,
      total: null,
      band: null,
      countedWeight: countedWeight,
      excusedWeight: excusedWeight,
    );
  }

  final total = weighted / countedWeight;
  return StudentScore(
    breakdown: breakdown,
    total: total,
    band: _bandFor(rubric.bands, total),
    countedWeight: countedWeight,
    excusedWeight: excusedWeight,
  );
}

/// Inclusive lower edge; exact integer comparison so band edges never drift.
String? _bandFor(List<Band> bands, Rational total) {
  String? label;
  for (final band in bands) {
    if (100 * total.numerator >= band.minimumPercent * total.denominator) {
      label = band.label;
    }
  }
  return label;
}
