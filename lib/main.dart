import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/perf_log.dart';
import 'database/database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PerfLog.startWatching();
  PerfLog.mark('main: начало');
  await initializeDateFormatting('ru');
  final db = AppDatabase.open();
  PerfLog.mark('main: база создана, запуск интерфейса');
  runApp(ProviderScope(
    overrides: [dbProvider.overrideWithValue(db)],
    child: const PitanieApp(),
  ));
}
