// PDF-отчёт. Формируется на устройстве, интернет не нужен. Шрифты передаёт вызывающий код
// (в приложении это Roboto из assets): стандартные шрифты PDF кириллицу не содержат.
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/dates.dart';
import 'report_stats.dart';

const _purple = PdfColor.fromInt(0xFF6D3FD6);
const _grey = PdfColor.fromInt(0xFF666666);

String _d(String key) => DateFormat('d.MM.yyyy').format(parseDayKey(key));

String _n(double? v, {int dec = 0, String unit = ''}) {
  if (v == null) return 'Нет данных';
  final s = dec == 0 ? fmt0(v) : fmt1(v);
  return unit.isEmpty ? s : '$s $unit';
}

Future<Uint8List> buildReportPdf(ReportStats r,
    {required pw.Font regular, required pw.Font bold, DateTime? now}) async {
  final doc = pw.Document(
      title: 'Отчёт ${_d(r.fromKey)} — ${_d(r.toKey)}',
      theme: pw.ThemeData.withFont(base: regular, bold: bold));
  final generated = DateFormat('d.MM.yyyy HH:mm').format(now ?? DateTime.now());

  pw.Widget h(String t) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
      child: pw.Text(t,
          style: pw.TextStyle(font: bold, fontSize: 14, color: _purple)));

  pw.Widget table(List<List<String>> rows) => pw.TableHelper.fromTextArray(
        data: rows,
        cellStyle: const pw.TextStyle(fontSize: 10),
        cellAlignments: {
          0: pw.Alignment.centerLeft,
          1: pw.Alignment.centerRight
        },
        columnWidths: {
          0: const pw.FlexColumnWidth(3),
          1: const pw.FlexColumnWidth(2)
        },
        border: const pw.TableBorder(
            horizontalInside:
                pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
        headerCount: 0,
        cellPadding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      );

  pw.Widget note(String t) =>
      pw.Text(t, style: const pw.TextStyle(fontSize: 9, color: _grey));

  // Линейный график по дням: пропуски (null) не рисуются и не заменяются нулями.
  pw.Widget chart(String title, List<double?> values, String unit) {
    final pts = <pw.PointChartValue>[
      for (var i = 0; i < values.length; i++)
        if (values[i] != null) pw.PointChartValue(i.toDouble(), values[i]!)
    ];
    if (pts.length < 2) {
      return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: pw.TextStyle(font: bold, fontSize: 11)),
            note('Недостаточно данных для графика'),
          ]);
    }
    var lo = pts.map((p) => p.y).reduce((a, b) => a < b ? a : b);
    var hi = pts.map((p) => p.y).reduce((a, b) => a > b ? a : b);
    if (hi - lo < 1e-9) {
      lo -= 1;
      hi += 1;
    }
    final pad = (hi - lo) * 0.1;
    lo -= pad;
    hi += pad;
    final n = values.length - 1;
    return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('$title, $unit',
              style: pw.TextStyle(font: bold, fontSize: 11)),
          pw.SizedBox(height: 4),
          pw.SizedBox(
            height: 120,
            child: pw.Chart(
              grid: pw.CartesianGrid(
                xAxis: pw.FixedAxis([0, n / 2, n.toDouble()],
                    format: (v) => DateFormat('d.MM').format(
                        parseDayKey(r.fromKey).add(Duration(days: v.round()))),
                    textStyle: const pw.TextStyle(fontSize: 8)),
                yAxis: pw.FixedAxis([lo, (lo + hi) / 2, hi],
                    format: (v) => (hi - lo) < 10 ? fmt1(v) : fmt0(v),
                    textStyle: const pw.TextStyle(fontSize: 8)),
              ),
              datasets: [
                pw.LineDataSet(
                    data: pts,
                    color: _purple,
                    drawPoints: pts.length < 40,
                    lineWidth: 1.5),
              ],
            ),
          ),
        ]);
  }

  final days = r.days;
  final lift = r.lift;

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 40),
    footer: (c) =>
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      note('Сформировано $generated'),
      note('Страница ${c.pageNumber} из ${c.pagesCount}'),
    ]),
    build: (c) => [
      pw.Text('Отчёт о питании, активности и здоровье',
          style: pw.TextStyle(font: bold, fontSize: 20)),
      pw.SizedBox(height: 4),
      pw.Text('Период: ${_d(r.fromKey)} — ${_d(r.toKey)} (${days.length} дн.)',
          style: const pw.TextStyle(fontSize: 12)),
      pw.SizedBox(height: 4),
      note(
          'Оценки в отчёте информационные и не являются медицинским заключением. '
          'Если за период нет записей, показатель отмечен как «Нет данных», а не нулём.'),
      h('Питание'),
      table([
        ['Дней с записями', '${r.foodDays} из ${days.length}'],
        ['Калории, в среднем за день', _n(r.avgKcal, unit: 'ккал')],
        ['Цель по калориям (среднее)', _n(r.goalKcal, unit: 'ккал')],
        ['Белки', _n(r.avgProteins, unit: 'г')],
        ['Жиры', _n(r.avgFats, unit: 'г')],
        ['Углеводы', _n(r.avgCarbs, unit: 'г')],
        ['Вода (напиток «вода»)', _n(r.avgWaterMl, unit: 'мл')],
      ]),
      pw.SizedBox(height: 8),
      chart('Калории по дням',
          [for (final d in days) d.hasFood ? d.n.calories : null], 'ккал'),
      h('Активность'),
      table([
        ['Дней с шагами', '${r.stepDays} из ${days.length}'],
        ['Шаги, в среднем за день', _n(r.avgSteps)],
        [
          'Расстояние, в среднем за день',
          _n(r.avgDistanceKm, dec: 1, unit: 'км')
        ],
        ['Тренировок (с часов и подтверждённых)', '${r.workoutCount}'],
        ['Время тренировок', '${fmt0(r.workoutMinutes)} мин'],
      ]),
      pw.SizedBox(height: 8),
      chart(
          'Шаги по дням',
          [for (final d in days) d.act.steps > 0 ? d.act.steps : null],
          'шагов'),
      h('Сон'),
      table([
        ['Дней со сном', '${r.sleepDays} из ${days.length}'],
        [
          'Продолжительность, в среднем',
          _n(r.avgSleepHours, dec: 1, unit: 'ч')
        ],
      ]),
      pw.SizedBox(height: 8),
      chart(
          'Сон по дням',
          [
            for (final d in days)
              d.act.sleepMinutes > 0 ? d.act.sleepMinutes / 60 : null
          ],
          'ч'),
      h('Пульс'),
      table([
        ['Дней с пульсом', '${r.hrDays} из ${days.length}'],
        ['Средний пульс', _n(r.avgHr, unit: 'уд/мин')],
        ['Максимальный пульс', _n(r.maxHr, unit: 'уд/мин')],
      ]),
      note(
          'HRV и индекс восстановления в отчёт не включены: часы '
          'пока не отдают подтверждённых значений HRV, индекс не рассчитывается.'),
      pw.SizedBox(height: 8),
      chart('Средний пульс по дням', [for (final d in days) d.act.avgHr],
          'уд/мин'),
      h('Вес'),
      table([
        ['Дней с взвешиванием', '${r.weightDays}'],
        ['Первое значение за период', _n(r.firstWeight, dec: 1, unit: 'кг')],
        ['Последнее значение', _n(r.lastWeight, dec: 1, unit: 'кг')],
        [
          'Изменение',
          r.weightChange == null
              ? 'Нет данных'
              : '${r.weightChange! >= 0 ? '+' : ''}${fmt1(r.weightChange!)} кг'
        ],
      ]),
      pw.SizedBox(height: 8),
      chart('Вес по дням', [for (final d in days) d.weight], 'кг'),
      note(
          'Состав тела (жир, мышцы) в отчёт не включён: это оценочные значения по '
          'импедансу, они показываются в разделе «Тело» с указанием метода.'),
      h('Силовые тренировки'),
      if (lift.sessions == 0)
        note('Нет данных: за период нет записей в дневнике тренировок.')
      else ...[
        table([
          ['Тренировок', '${lift.sessions}'],
          ['Общий объём (вес × повторения)', '${fmt0(lift.volume)} кг'],
        ]),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: [
            'Упражнение',
            'Подходов',
            'Макс. вес, кг',
            '1ПМ (оценка), кг'
          ],
          data: [
            for (final e in lift.exercises)
              [
                e.name,
                '${e.sets}',
                e.maxWeight == null ? '—' : fmtAuto(e.maxWeight!),
                e.est1Rm == null ? '—' : fmt0(e.est1Rm!),
              ]
          ],
          headerStyle: pw.TextStyle(font: bold, fontSize: 10),
          cellStyle: const pw.TextStyle(fontSize: 10),
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerRight,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
          },
          border: const pw.TableBorder(
              horizontalInside:
                  pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
        ),
        pw.SizedBox(height: 4),
        note(
            '1ПМ — оценка по формуле Эпли для подходов в 1–12 повторений, не измерение.'),
      ],
    ],
  ));
  return doc.save();
}
