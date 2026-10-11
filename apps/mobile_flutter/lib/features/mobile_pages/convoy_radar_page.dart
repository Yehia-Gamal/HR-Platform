import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/sharing/whatsapp_share_service.dart';
import 'package:flutter/material.dart';

class ConvoyCheckpoint {
  ConvoyCheckpoint({
    required this.id,
    required this.title,
    required this.status,
    this.time,
    this.notes,
    this.target,
    this.achieved,
  });

  final String id;
  final String title;
  CheckpointStatus status;
  String? time;
  String? notes;
  int? target;
  int? achieved;
}

enum CheckpointStatus { pending, inProgress, completed }

/// صفحة رادار القوافل والمأموريات الميدانية التفاعلية —
/// متابعة محطات الوصول الميداني ونسب توزيع المساعدات وبث المستجدات عبر الواتساب.
class ConvoyRadarPage extends StatefulWidget {
  const ConvoyRadarPage({
    super.key,
    this.convoyTitle = 'قافلة ستر ودفا — قرى مركز أطفيح',
    this.route = 'مقر الجمعية الرئيسي ← قرى أطفيح، الجيزة',
    this.responsibleName = 'أ/ أحمد محمود (مسؤول العمليات الميدانية)',
    this.volunteersCount = 18,
    this.vehiclesCount = 3,
    this.aidType = 'كراتين مواد غذائية وبطاطين شتاء',
    this.initialTargetAid = 250,
    this.initialDeliveredAid = 165,
  });

  final String convoyTitle;
  final String route;
  final String responsibleName;
  final int volunteersCount;
  final int vehiclesCount;
  final String aidType;
  final int initialTargetAid;
  final int initialDeliveredAid;

  @override
  State<ConvoyRadarPage> createState() => _ConvoyRadarPageState();
}

class _ConvoyRadarPageState extends State<ConvoyRadarPage> {
  late int _targetAid;
  late int _deliveredAid;
  late List<ConvoyCheckpoint> _checkpoints;

  @override
  void initState() {
    super.initState();
    _targetAid = widget.initialTargetAid;
    _deliveredAid = widget.initialDeliveredAid;
    _checkpoints = [
      ConvoyCheckpoint(
        id: 'cp-1',
        title: 'الانطلاق من المقر الرئيسي وتجهيز الشاحنات',
        status: CheckpointStatus.completed,
        time: '07:30 ص',
        notes: 'تم فحص المركبات واكتمال المتطوعين وشحن كامل المساعدات.',
      ),
      ConvoyCheckpoint(
        id: 'cp-2',
        title: 'الوصول لنقطة التجمع الأولى (قرية منيل سلطان)',
        status: CheckpointStatus.completed,
        time: '09:40 ص',
        notes: 'تم التنسيق مع لجان القرية ومسؤولي الوحدة المحلية بنجاح.',
      ),
      ConvoyCheckpoint(
        id: 'cp-3',
        title: 'نقطة التوزيع الرئيسية (الأسر الأكثر استحقاقاً)',
        status: CheckpointStatus.inProgress,
        time: '11:15 ص',
        target: 150,
        achieved: 120,
        notes: 'التوزيع مستمر بانتظام بنظام الكوبونات المعتمدة مسبقاً.',
      ),
      ConvoyCheckpoint(
        id: 'cp-4',
        title: 'نقطة التوزيع الفرعية والمسح الميداني للحالات',
        status: CheckpointStatus.pending,
        target: 100,
        achieved: 0,
        notes: 'توزيع البطاطين وزيارة كبار السن وذوي الهمم في منازلهم.',
      ),
      ConvoyCheckpoint(
        id: 'cp-5',
        title: 'انتهاء أعمال القافلة والعودة وتسليم العهدة',
        status: CheckpointStatus.pending,
        notes: 'حصر المتبقي وتسليم كشوف التوقيعات والتقرير الختامي.',
      ),
    ];
  }

  void _addDelivered(int count) {
    setState(() {
      _deliveredAid = (_deliveredAid + count).clamp(0, _targetAid);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم تسجيل تسليم $count ${widget.aidType} بنجاح'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _advanceCheckpoint(ConvoyCheckpoint cp, CheckpointStatus nextStatus) {
    setState(() {
      cp.status = nextStatus;
      final now = TimeOfDay.now();
      final h = now.hourOfPeriod == 0 ? 12 : now.hourOfPeriod;
      final m = now.minute.toString().padLeft(2, '0');
      final period = now.period == DayPeriod.am ? 'ص' : 'م';
      cp.time = '$h:$m $period';
    });
  }

  void _editNotes(ConvoyCheckpoint cp) {
    final ctrl = TextEditingController(text: cp.notes);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(cp.title, style: const TextStyle(fontSize: 14)),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'الملاحظة الميدانية',
            hintText: 'اكتب مستجدات هذه المحطة...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                cp.notes = ctrl.text.trim();
              });
              Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareWhatsAppBroadcast() async {
    final percent = _targetAid > 0
        ? ((_deliveredAid / _targetAid) * 100).round()
        : 0;

    final currentCp = _checkpoints.firstWhere(
      (c) => c.status == CheckpointStatus.inProgress,
      orElse: () => _checkpoints.lastWhere(
        (c) => c.status == CheckpointStatus.completed,
        orElse: () => _checkpoints.first,
      ),
    );

    final buffer = StringBuffer();
    buffer.writeln('🚌 *بث مستجدات القافلة الميدانية — جمعية أحلى شباب* 🚌');
    buffer.writeln();
    buffer.writeln('📍 القافلة: *«${widget.convoyTitle}»*');
    buffer.writeln('🛣️ خط السير: *${widget.route}*');
    buffer.writeln('👤 المسؤول الميداني: *${widget.responsibleName}*');
    buffer.writeln('👥 الطاقم: *${widget.volunteersCount} متطوعاً* | 🚐 *${widget.vehiclesCount} مركبات*');
    buffer.writeln();
    buffer.writeln('📦 المساعدات: *${widget.aidType}*');
    buffer.writeln('📊 نسبة إنجاز التوزيع: *$_deliveredAid من $_targetAid ($percent%)*');
    buffer.writeln();
    buffer.writeln('🚩 المحطة الحالية: *${currentCp.title}*');
    if (currentCp.notes != null && currentCp.notes!.isNotEmpty) {
      buffer.writeln('📝 مستجدات: ${currentCp.notes}');
    }
    buffer.writeln();
    buffer.writeln('دعواتكم لفريق الميدان والمتطوعين بالتيسير والتوفيق 💚🌿');
    buffer.writeln('— *غرفة عمليات جمعية أحلى شباب*');

    await WhatsAppShareService.shareText(buffer.toString());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final completedCount =
        _checkpoints.where((c) => c.status == CheckpointStatus.completed).length;
    final percent = _targetAid > 0
        ? ((_deliveredAid / _targetAid) * 100).round()
        : 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('رادار القوافل والميدان'),
        actions: [
          IconButton(
            tooltip: 'بث المستجدات للواتساب',
            icon: const Icon(Icons.share_rounded),
            onPressed: _shareWhatsAppBroadcast,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.campaign_rounded),
            label: const Text(
              'بث مستجدات الميدان لجروب الواتساب',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
            ),
            onPressed: _shareWhatsAppBroadcast,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Convoy Hero Card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: scheme.primary.withValues(alpha: 0.2)),
            ),
            color: scheme.primary.withValues(alpha: 0.05),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: scheme.primary.withValues(alpha: 0.15),
                        child: Icon(
                          Icons.directions_bus_rounded,
                          color: scheme.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.convoyTitle,
                              style: text.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.route,
                              style: text.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.statusSuccess.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.statusSuccess.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.fiber_manual_record_rounded,
                              size: 10,
                              color: AppColors.statusSuccess,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'مباشر',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: AppColors.statusSuccess,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      _MetaChip(
                        icon: Icons.person_rounded,
                        label: widget.responsibleName,
                      ),
                      _MetaChip(
                        icon: Icons.groups_rounded,
                        label: '${widget.volunteersCount} متطوعاً',
                      ),
                      _MetaChip(
                        icon: Icons.local_shipping_outlined,
                        label: '${widget.vehiclesCount} مركبات',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Aid Distribution Progress Card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 18,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'المساعدات: ${widget.aidType}',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                      Text(
                        '$percent%',
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _targetAid > 0
                          ? (_deliveredAid / _targetAid).clamp(0.0, 1.0)
                          : 0.0,
                      minHeight: 8,
                      backgroundColor: scheme.surfaceContainerHighest,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'تم تسليم $_deliveredAid من أصل $_targetAid حالة',
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Row(
                        children: [
                          const Text(
                            'تحديث سريع: ',
                            style: TextStyle(fontSize: 11),
                          ),
                          _QuickAddBtn(label: '+5', onTap: () => _addDelivered(5)),
                          const SizedBox(width: 4),
                          _QuickAddBtn(label: '+20', onTap: () => _addDelivered(20)),
                          const SizedBox(width: 4),
                          _QuickAddBtn(label: '+50', onTap: () => _addDelivered(50)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Checkpoints Section Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'مسار ومحطات القافلة الميدانية',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              Text(
                '$completedCount من ${_checkpoints.length} محطات',
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Checkpoint Cards
          for (var i = 0; i < _checkpoints.length; i++) ...[
            _CheckpointCard(
              index: i + 1,
              checkpoint: _checkpoints[i],
              onAdvance: (status) => _advanceCheckpoint(_checkpoints[i], status),
              onEditNotes: () => _editNotes(_checkpoints[i]),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _QuickAddBtn extends StatelessWidget {
  const _QuickAddBtn({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _CheckpointCard extends StatelessWidget {
  const _CheckpointCard({
    required this.index,
    required this.checkpoint,
    required this.onAdvance,
    required this.onEditNotes,
  });

  final int index;
  final ConvoyCheckpoint checkpoint;
  final ValueChanged<CheckpointStatus> onAdvance;
  final VoidCallback onEditNotes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isCompleted = checkpoint.status == CheckpointStatus.completed;
    final isInProgress = checkpoint.status == CheckpointStatus.inProgress;

    final borderColor = isInProgress
        ? scheme.primary.withValues(alpha: 0.5)
        : isCompleted
            ? AppColors.statusSuccess.withValues(alpha: 0.3)
            : scheme.outlineVariant;

    final bgColor = isInProgress
        ? scheme.primary.withValues(alpha: 0.04)
        : isCompleted
            ? AppColors.statusSuccess.withValues(alpha: 0.03)
            : scheme.surface;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor),
      ),
      color: bgColor,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: isCompleted
                      ? AppColors.statusSuccess
                      : isInProgress
                          ? scheme.primary
                          : scheme.surfaceContainerHighest,
                  foregroundColor:
                      isCompleted || isInProgress ? Colors.white : scheme.onSurfaceVariant,
                  child: isCompleted
                      ? const Icon(Icons.check_rounded, size: 16)
                      : Text(
                          '$index',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        checkpoint.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                      if (checkpoint.time != null)
                        Text(
                          checkpoint.time!,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (checkpoint.status == CheckpointStatus.pending)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onPressed: () => onAdvance(CheckpointStatus.inProgress),
                    child: const Text('بدء المحطة', style: TextStyle(fontSize: 11)),
                  ),
                if (checkpoint.status == CheckpointStatus.inProgress)
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.statusSuccess,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onPressed: () => onAdvance(CheckpointStatus.completed),
                    child: const Text('إتمام المحطة ✓', style: TextStyle(fontSize: 11)),
                  ),
              ],
            ),
            if (checkpoint.notes != null && checkpoint.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  checkpoint.notes!,
                  style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
                icon: const Icon(Icons.edit_note_rounded, size: 16),
                label: const Text('تعديل الملاحظة', style: TextStyle(fontSize: 11)),
                onPressed: onEditNotes,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
