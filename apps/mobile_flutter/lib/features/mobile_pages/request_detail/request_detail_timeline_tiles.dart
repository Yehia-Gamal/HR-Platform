part of '../mobile_request_detail_page.dart';

class _StageStrip extends StatelessWidget {
  const _StageStrip({
    required this.steps,
    required this.requestStatus,
    required this.currentIndex,
  });

  final List<MobileRequestStep> steps;
  final String requestStatus;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final children = <Widget>[];
    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      final state = requestStageState(
        s,
        requestStatus,
        isCurrent: i == currentIndex,
      );
      final faded =
          state == RequestStageState.skipped ||
          state == RequestStageState.waiting ||
          state == RequestStageState.stopped;
      children.add(
        Expanded(
          child: Column(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: faded ? scheme.surface : state.color,
                  border: Border.all(color: state.color, width: 2),
                ),
                child: Icon(
                  state.icon,
                  size: 18,
                  color: faded ? state.color : Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                requestStageName(s.name, roleSlug: s.roleSlug, order: s.order),
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: faded ? scheme.onSurfaceVariant : null,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                state.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: state.color,
                ),
              ),
            ],
          ),
        ),
      );
      if (i < steps.length - 1) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: SizedBox(
              width: 28,
              child: Divider(thickness: 2, color: scheme.outlineVariant),
            ),
          ),
        );
      }
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.event,
    required this.isFirst,
    required this.isLast,
  });

  final _JourneyEvent event;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = scheme.outlineVariant.withValues(alpha: .7);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 34,
            child: Column(
              children: [
                Container(
                  width: 2,
                  height: 6,
                  color: isFirst ? Colors.transparent : line,
                ),
                event.live
                    ? _PulsingDot(color: event.color, size: 28)
                    : Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: event.color.withValues(alpha: .14),
                          border: Border.all(
                            color: event.color.withValues(alpha: .5),
                          ),
                        ),
                        child: Icon(event.icon, size: 15, color: event.color),
                      ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast ? Colors.transparent : line,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 8, bottom: isLast ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                      color: event.live ? event.color : null,
                    ),
                  ),
                  if (event.subtitle != null && event.subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        event.subtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (event.at != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        arDateTime(event.at!),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (event.comment != null && event.comment!.trim().isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: event.color.withValues(alpha: .07),
                        borderRadius: const BorderRadiusDirectional.only(
                          topEnd: Radius.circular(12),
                          bottomStart: Radius.circular(12),
                          bottomEnd: Radius.circular(12),
                        ),
                      ),
                      child: Text(
                        '«${event.comment!.trim()}»',
                        style: const TextStyle(fontSize: 12.5, height: 1.5),
                      ),
                    ),
                  if (event.chip != null) ...[
                    const SizedBox(height: 6),
                    RequestMetaChip(
                      icon: event.chipDanger
                          ? Icons.warning_amber_rounded
                          : Icons.schedule_rounded,
                      text: event.chip!,
                      color: event.chipDanger
                          ? AppColors.statusDanger
                          : AppColors.statusInfo,
                      strong: event.chipDanger,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// دائرة نابضة للمرحلة الحالية.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // نبض محدود لا يستنزف البطارية ولا يُبقي الشاشة ترسم بلا نهاية، ويحترم
    // إعداد تقليل الحركة في الجهاز.
    if (!MediaQuery.disableAnimationsOf(context)) {
      _controller.repeat(reverse: true, count: 6);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_controller.value);
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: 1 + .3 * t,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: .35 * (1 - t)),
                  ),
                ),
              ),
              Container(
                width: widget.size * .62,
                height: widget.size * .62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                ),
                child: const Icon(
                  Icons.hourglass_top_rounded,
                  size: 11,
                  color: Colors.white,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// بانر إعادة الرفع — يوضّح لصاحب الطلب أنه رُفض/أُعيد ويمكن تعديله.
