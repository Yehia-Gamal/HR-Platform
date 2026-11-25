part of '../monthly_attendance_statement_page.dart';

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: color,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_left, color: color, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── نموذج طلب إجازة سريع ───────────────────────────────────────────

class _QuickLeaveSheet extends StatefulWidget {
  const _QuickLeaveSheet({required this.dateStr});
  final String dateStr;
  @override
  State<_QuickLeaveSheet> createState() => _QuickLeaveSheetState();
}

class _QuickLeaveSheetState extends State<_QuickLeaveSheet> {
  final _reasonCtrl = TextEditingController();
  String _leaveType = 'annual';

  static const _leaveTypes = {
    'annual': 'سنوية',
    'casual': 'عارضة',
    'weekly_rest_comp': 'بدل راحة',
    'sick': 'مرضية',
  };

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
            decoration: BoxDecoration(
              color: scheme.onSurfaceVariant.withValues(alpha: .3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'طلب إجازة',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'اليوم: ${widget.dateStr}',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _leaveType,
            decoration: const InputDecoration(
              labelText: 'نوع الإجازة',
              isDense: true,
            ),
            items: _leaveTypes.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
                .toList(),
            onChanged: (v) => setState(() => _leaveType = v!),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _reasonCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'السبب',
              hintText: 'اكتب سبب طلب الإجازة...',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.send),
            label: const Text('إرسال الطلب'),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final reason = _reasonCtrl.text.trim();
    if (reason.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال سبب الطلب (3 أحرف على الأقل)'),
        ),
      );
      return;
    }
    Navigator.pop(context, {
      'title': 'طلب إجازة ${_leaveTypes[_leaveType]} — ${widget.dateStr}',
      'reason': reason,
      'payload': {
        'leaveType': _leaveType,
        'startDate': widget.dateStr,
        'endDate': widget.dateStr,
        'dayMark': true,
      },
    });
  }
}

// ─── ورقة تعديل حالة اليوم بأثر رجعي (إجازة / مأمورية / قافلة / يوم ترفيهي فاندي) ───


extension _RetroactiveDayChangeSubmit on _RetroactiveDayChangeSheetState {
  void _submit() {
    final reason = _reasonCtrl.text.trim();
    if (reason.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال سبب التعديل (3 أحرف على الأقل)'),
        ),
      );
      return;
    }

    String title;
    final Map<String, dynamic> payload = {
      'startDate': widget.dateStr,
      'endDate': widget.dateStr,
      'dayMark': true,
    };

    if (_category == 'leave') {
      const leaveNames = {
        'casual': 'عارضة',
        'annual': 'اعتيادية',
        'weekly_rest_comp': 'بدل راحة',
      };
      payload['leaveType'] = _leaveType;
      title =
          'طلب إجازة ${leaveNames[_leaveType] ?? _leaveType} — ${widget.dateStr}';
    } else {
      var loc = _locationCtrl.text.trim();
      if (loc.isEmpty) {
        loc = switch (_category) {
          'mission' => 'مأمورية عمل خارجية',
          'convoy' => 'قافلة مساعدات خارجية (كامب)',
          'fundraising' => 'يوم ترفيهي للموظفين (فاندي / Fun Day)',
          _ => 'نشاط عمل',
        };
      }
      payload['location'] = loc;
      title = switch (_category) {
        'mission' => 'مأمورية عمل خارجية — ${widget.dateStr}',
        'convoy' => 'قافلة مساعدات — ${widget.dateStr}',
        'fundraising' => 'يوم ترفيهي (فاندي) — ${widget.dateStr}',
        _ => 'تكليف عمل — ${widget.dateStr}',
      };
    }

    Navigator.pop(context, {
      'type': _category,
      'title': title,
      'reason': reason,
      'payload': payload,
    });
  }
}

class _QuickPermitSheet extends StatefulWidget {
  const _QuickPermitSheet({required this.dateStr, required this.permitKind});
  final String dateStr;
  final String permitKind;
  @override
  State<_QuickPermitSheet> createState() => _QuickPermitSheetState();
}

class _QuickPermitSheetState extends State<_QuickPermitSheet> {
  final _reasonCtrl = TextEditingController();

  String get _kindLabel =>
      widget.permitKind == 'early_departure' ? 'إذن انصراف' : 'إذن حضور';

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
            decoration: BoxDecoration(
              color: scheme.onSurfaceVariant.withValues(alpha: .3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _kindLabel,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFFF59E0B),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'اليوم: ${widget.dateStr}',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _reasonCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'السبب',
              hintText: 'اكتب سبب طلب $_kindLabel...',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.send),
            label: const Text('إرسال الطلب'),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final reason = _reasonCtrl.text.trim();
    if (reason.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال سبب الطلب (3 أحرف على الأقل)'),
        ),
      );
      return;
    }
    Navigator.pop(context, {
      'title': '$_kindLabel — ${widget.dateStr}',
      'reason': reason,
      'payload': {
        'permitDate': widget.dateStr,
        'minutes': 120,
        'permitKind': widget.permitKind,
      },
    });
  }
}

// ─── شريحة تفاصيل صغيرة (chip) ────────────────────────────────────

class _DetailChip extends StatelessWidget {
  const _DetailChip({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── ورقة تعديل اليوم إدارياً ─────────────────────────────────────
