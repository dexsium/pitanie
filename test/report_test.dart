import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pitanie/core/nutrition.dart';
import 'package:pitanie/features/dashboard/day_data.dart';
import 'package:pitanie/features/reports/report_pdf.dart';
import 'package:pitanie/features/reports/report_stats.dart';

DayStat day(String key, {double kcal = 0, double? weight, double steps = 0}) =>
    DayStat(key, Nutrients(kcal, kcal / 20, kcal / 40, kcal / 10), 0,
        ActivityDay(steps: steps), weight, GoalValues.fallback, kcal > 0);

void main() {
  test('средние считаются только по дням с данными, пропуски не нули', () {
    final r = buildReportStats(
        '2026-11-01',
        '2026-11-04',
        [
          day('2026-11-01', kcal: 2000, weight: 80, steps: 8000),
          day('2026-11-02'),
          day('2026-11-03', kcal: 1000, steps: 4000),
          day('2026-11-04', weight: 79),
        ],
        LiftSummary.empty);
    expect(r.foodDays, 2);
    expect(r.avgKcal, 1500);
    expect(r.avgSteps, 6000);
    expect(r.avgSleepHours, isNull);
    expect(r.avgHr, isNull);
    expect(r.weightChange, -1);
  });

  test('без данных значения null, а не ноль', () {
    final r = buildReportStats('2026-11-01', '2026-11-02',
        [day('2026-11-01'), day('2026-11-02')], LiftSummary.empty);
    expect(r.avgKcal, isNull);
    expect(r.weightChange, isNull);
  });

  test('PDF формируется офлайн с кириллицей и многостраничными данными',
      () async {
    pw.Font f(String p) =>
        pw.Font.ttf(File(p).readAsBytesSync().buffer.asByteData());
    final days = [
      for (var i = 1; i <= 60; i++)
        day('2026-10-${(i % 28 + 1).toString().padLeft(2, '0')}',
            kcal: 1800.0 + i, weight: 80 - i / 20, steps: 5000.0 + i * 10)
    ];
    final r = buildReportStats(
        '2026-10-01',
        '2026-10-28',
        days,
        const LiftSummary(
            3, 12000, [LiftExerciseSummary('Жим лёжа', 9, 100, 117)]));
    final bytes = await buildReportPdf(r,
        regular: f('assets/fonts/Roboto-Regular.ttf'),
        bold: f('assets/fonts/Roboto-Bold.ttf'),
        now: DateTime(2026, 11, 5, 12));
    expect(bytes.length, greaterThan(2000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
