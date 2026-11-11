import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/perf_log.dart';

/// Журнал производительности: можно скопировать и отправить разработчику.
class PerfLogPage extends StatefulWidget {
  const PerfLogPage({super.key});
  @override
  State<PerfLogPage> createState() => _PerfLogPageState();
}

class _PerfLogPageState extends State<PerfLogPage> {
  @override
  Widget build(BuildContext context) {
    final text = PerfLog.dump();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Журнал производительности'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
          IconButton(
            tooltip: 'Скопировать',
            icon: const Icon(Icons.copy),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Скопировано')));
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          text,
          style: const TextStyle(fontFamily: 'Courier', fontSize: 12, height: 1.4),
        ),
      ),
    );
  }
}
