/// Модели анализа здоровья. Это оздоровительный мониторинг, а не медицинская диагностика.
const kAlgoVersion = '1.0';

enum HealthCategory { heartRate, hrv, sleep, recovery, spo2 }

enum Severity { info, advice, attention, urgent }

/// Тип HRV. Значения разных типов не смешиваются и не сравниваются друг с другом.
enum HrvMetric { rmssd, sdnn, unknown }

enum Availability { available, stale, awaitingSync, unsupported }

String categoryLabel(HealthCategory c) => switch (c) {
      HealthCategory.heartRate => 'Пульс',
      HealthCategory.hrv => 'HRV',
      HealthCategory.sleep => 'Сон',
      HealthCategory.recovery => 'Восстановление',
      HealthCategory.spo2 => 'SpO₂',
    };

String severityLabel(Severity s) => switch (s) {
      Severity.info => 'Информация',
      Severity.advice => 'Рекомендация',
      Severity.attention => 'Требует внимания',
      Severity.urgent => 'Срочно',
    };

class Sample {
  final DateTime at;
  final double v;
  const Sample(this.at, this.v);
}

class HrvSample {
  final DateTime at;
  final double v;
  final HrvMetric metric;
  const HrvSample(this.at, this.v, this.metric);
}

class DailyValue {
  final DateTime day; // начало суток
  final double v;
  const DailyValue(this.day, this.v);
}

class SleepNight {
  final DateTime day; // день пробуждения
  final DateTime start, end;
  final int sleepMin;
  final double? nightHr;
  const SleepNight(this.day, this.start, this.end, this.sleepMin,
      {this.nightHr});
}

/// Вывод анализа с основанием, периодом и достоверностью.
class Insight {
  final String
      key; // идентификатор события: повторная обработка не создаёт дубль
  final HealthCategory category;
  final Severity severity;
  final String title, body;
  final List<String> basis; // использованные показатели
  final String period;
  final String confidence;
  final DateTime createdAt;
  final String algoVersion;
  const Insight({
    required this.key,
    required this.category,
    required this.severity,
    required this.title,
    required this.body,
    required this.basis,
    required this.period,
    required this.confidence,
    required this.createdAt,
    this.algoVersion = kAlgoVersion,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'cat': category.name,
        'sev': severity.name,
        'title': title,
        'body': body,
        'basis': basis,
        'period': period,
        'conf': confidence,
        'at': createdAt.toIso8601String(),
        'v': algoVersion,
      };

  static Insight? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = DateTime.tryParse('${j['at']}');
    final cat = HealthCategory.values.where((c) => c.name == j['cat']);
    final sev = Severity.values.where((c) => c.name == j['sev']);
    if (at == null || cat.isEmpty || sev.isEmpty) return null;
    return Insight(
      key: '${j['key']}',
      category: cat.first,
      severity: sev.first,
      title: '${j['title']}',
      body: '${j['body']}',
      basis: [for (final b in (j['basis'] as List? ?? const [])) '$b'],
      period: '${j['period']}',
      confidence: '${j['conf']}',
      createdAt: at,
      algoVersion: '${j['v']}',
    );
  }
}

/// Доступность показателя по фактическому каналу «часы → приложение».
class Capability {
  final String id, label;
  final Availability state;
  final String detail;
  final DateTime? last;
  const Capability(this.id, this.label, this.state, this.detail, {this.last});
}

/// Настройки мониторинга.
class HealthPrefs {
  final bool auto;
  final Map<HealthCategory, bool> categories;
  final int infoEveryDays; // 1 или 7
  final int quietFromMin, quietToMin; // минуты от полуночи
  final bool privacy;
  final double hrMinDelta; // порог повышения пульса покоя, уд/мин
  final double sleepMinHours;
  const HealthPrefs({
    this.auto = true,
    this.categories = const {
      HealthCategory.heartRate: true,
      HealthCategory.hrv: true,
      HealthCategory.sleep: true,
      HealthCategory.recovery: true,
      HealthCategory.spo2: true,
    },
    this.infoEveryDays = 7,
    this.quietFromMin = 22 * 60,
    this.quietToMin = 8 * 60,
    this.privacy = false,
    this.hrMinDelta = 5,
    this.sleepMinHours = 6,
  });

  bool enabled(HealthCategory c) => categories[c] ?? true;

  bool inQuiet(DateTime t) {
    final m = t.hour * 60 + t.minute;
    if (quietFromMin == quietToMin) return false;
    return quietFromMin < quietToMin
        ? m >= quietFromMin && m < quietToMin
        : m >= quietFromMin || m < quietToMin;
  }
}
