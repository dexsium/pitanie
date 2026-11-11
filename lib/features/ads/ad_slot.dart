import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ad_provider.dart';
import 'ads_models.dart';

/// Рекламное место. Занимает место на экране только когда реклама разрешена пользователем,
/// не превышены лимиты и сеть вернула объявление; иначе не занимает места вообще.
/// Рекламный блок подписан «Реклама» и не перекрывает содержимое экрана.
class AdSlot extends ConsumerStatefulWidget {
  final AdPlacement placement;
  const AdSlot(this.placement, {super.key});

  @override
  ConsumerState<AdSlot> createState() => _AdSlotState();
}

class _AdSlotState extends ConsumerState<AdSlot> {
  Widget? _ad;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = ref.read(adProviderProvider);
    // Без подключённой сети ничего не проверяется и не запрашивается.
    if (!provider.available) return;
    final service = ref.read(adsServiceProvider);
    final p = widget.placement;
    // Заглушка не подчиняется лимитам и не учитывается в счётчиках.
    if (!provider.isPlaceholder && await service.decide(p) != AdDecision.allowed) return;
    Widget? ad;
    try {
      ad = await provider.buildAd(p);
    } catch (_) {
      ad = null;
    }
    if (ad == null) {
      if (!provider.isPlaceholder) await service.recordError(p);
      return;
    }
    if (!provider.isPlaceholder) await service.recordImpression(p);
    if (mounted) setState(() => _ad = ad);
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Реклама', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        const SizedBox(height: 4),
        ad,
      ]),
    );
  }
}
