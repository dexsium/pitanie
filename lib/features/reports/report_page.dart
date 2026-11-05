import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import 'report_pdf.dart';
import 'report_stats.dart';

/// Выбор периода и формирование PDF-отчёта.
class ReportPage extends ConsumerStatefulWidget {
  const ReportPage({super.key});
  @override
  ConsumerState<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends ConsumerState<ReportPage> {
  int _days = 30; // 0 — свой период
  DateTimeRange? _custom;
  bool _busy = false;
  String? _error;

  DateTimeRange get _range {
    if (_days == 0 && _custom != null) return _custom!;
    final to = dayStart(DateTime.now());
    return DateTimeRange(
        start: to.subtract(Duration(days: _days - 1)), end: to);
  }

  Future<void> _pickCustom() async {
    final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: dayStart(DateTime.now()),
        initialDateRange: _custom ?? _range);
    if (r != null) {
      setState(() {
        _custom = DateTimeRange(start: dayStart(r.start), end: dayStart(r.end));
        _days = 0;
      });
    }
  }

  Future<void> _make() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final range = _range;
      final stats =
          await loadReportStats(ref.read(dbProvider), range.start, range.end);
      final regular =
          pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
      final bold =
          pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
      final bytes = await buildReportPdf(stats, regular: regular, bold: bold);
      if (!mounted) return;
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Отчёт')),
                    body: PdfPreview(
                      build: (_) async => bytes,
                      pdfFileName:
                          'pitanie_report_${dayKey(range.start)}_${dayKey(range.end)}.pdf',
                      canChangePageFormat: false,
                      canChangeOrientation: false,
                      canDebug: false,
                    ),
                  )));
    } catch (e) {
      if (mounted) setState(() => _error = 'Не удалось сформировать отчёт: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final f = DateFormat('d.MM.yyyy');
    final r = _range;
    return Scaffold(
      appBar: AppBar(title: const Text('PDF-отчёт')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(
            'Питание, активность, сон, пульс, вес и силовые тренировки за выбранный период. '
            'Отчёт формируется на телефоне без интернета, его можно просмотреть, сохранить и отправить.',
            style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 16),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 7, label: Text('7 дн.')),
            ButtonSegment(value: 30, label: Text('30 дн.')),
            ButtonSegment(value: 90, label: Text('90 дн.')),
            ButtonSegment(value: 0, label: Text('Свой')),
          ],
          selected: {_days},
          onSelectionChanged: (s) {
            if (s.first == 0) {
              _pickCustom();
            } else {
              setState(() => _days = s.first);
            }
          },
        ),
        const SizedBox(height: 12),
        Text('Период: ${f.format(r.start)} — ${f.format(r.end)}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: kPrimary),
          onPressed: _busy ? null : _make,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.picture_as_pdf),
          label: Text(_busy ? 'Формирование…' : 'Сформировать отчёт'),
        ),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: cs.error))),
      ]),
    );
  }
}
