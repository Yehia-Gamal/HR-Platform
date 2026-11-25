part of '../mobile_request_detail_page.dart';

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.request});

  final MobileRequestDetail request;

  Map<String, dynamic> get _p => request.payload;

  String? _text(String key) {
    final v = _p[key]?.toString().trim();
    return v == null || v.isEmpty || v == 'null' ? null : v;
  }

  String? _day(String key) {
    final d = DateTime.tryParse(_p[key]?.toString() ?? '');
    return d == null ? null : arDay(d);
  }

  List<(IconData, String, String)> _rows() {
    final rows = <(IconData, String, String)>[];
    void add(IconData icon, String label, String? value) {
      if (value != null && value.trim().isNotEmpty) {
        rows.add((icon, label, value.trim()));
      }
    }

    final period = requestPeriodLabel(_p);
    final days = requestDays(_p);
    switch (request.type) {
      case 'leave':
        add(
          Icons.category_rounded,
          'نوع الإجازة',
          leaveTypeLabel(_text('leaveType')),
        );
        add(Icons.date_range_rounded, 'الفترة', period);
        if (days != null) {
          add(Icons.event_available_rounded, 'المدة', arDays(days));
        }
      case 'fundraising':
        add(
          Icons.celebration_rounded,
          'نوع الفعالية',
          'يوم ترفيهي للموظفين (فاندي)',
        );
        add(Icons.place_rounded, 'مكان اليوم الترفيهي / الوجهة', _text('location'));
        add(
          Icons.date_range_rounded,
          days != null && days > 1 ? 'الفترة' : 'تاريخ اليوم الترفيهي',
          period,
        );
        if (days != null && days > 1) {
          add(Icons.event_available_rounded, 'المدة', arDays(days));
        }
        if (_text('notes') != null && _text('notes')!.trim().isNotEmpty) {
          add(Icons.notes_rounded, 'ملاحظات', _text('notes'));
        }
      case 'mission' || 'convoy':
        add(Icons.place_rounded, 'الوجهة', _text('location'));
        add(
          Icons.date_range_rounded,
          days != null && days > 1 ? 'الفترة' : 'اليوم',
          period,
        );
        if (days != null && days > 1) {
          add(Icons.event_available_rounded, 'المدة', arDays(days));
        }
        add(
          Icons.logout_rounded,
          days != null && days > 1 ? 'انطلاق اليوم الأول' : 'وقت الانطلاق',
          time12(_p['startTime']),
        );
        add(Icons.login_rounded, 'وقت العودة', time12(_p['endTime']));
        if (_text('notes') != null &&
            _text('notes')!.trim().isNotEmpty &&
            _text('notes') != request.reason?.trim()) {
          add(Icons.notes_rounded, 'ملاحظات', _text('notes'));
        }
      case 'late_permit' || 'early_permit':
        add(
          Icons.category_rounded,
          'نوع الإذن',
          permitKindLabel(_text('permitKind'), request.type),
        );
        add(Icons.today_rounded, 'اليوم', period);
        add(Icons.timer_outlined, 'المدة', permitDurationLabel(_p['minutes']));
      case 'shift_change':
        add(Icons.schedule_rounded, 'الفترة المطلوبة', _text('shiftName'));
        add(Icons.event_available_rounded, 'تبدأ من', _day('effectiveFrom'));
      case 'attendance_correction':
        add(Icons.today_rounded, 'اليوم', _day('workDate') ?? _day('correctionDate') ?? period);
        add(
          Icons.login_rounded,
          'الحضور المطلوب',
          time12(_p['proposedCheckInTime'] ?? _p['checkInTime'] ?? _p['requestedCheckIn']),
        );
        add(
          Icons.logout_rounded,
          'الانصراف المطلوب',
          time12(_p['proposedCheckOutTime'] ?? _p['checkOutTime'] ?? _p['requestedCheckOut']),
        );
      case 'overtime':
        add(Icons.today_rounded, 'اليوم', period);
        if (_p['hours'] != null) {
          add(Icons.timer_outlined, 'ساعات العمل الإضافي', '${_p['hours']} ساعة');
        }
        if (_text('tasks') != null) {
          add(Icons.assignment_outlined, 'المهام المنجزة', _text('tasks'));
        }
      case 'excuse':
        add(Icons.today_rounded, 'اليوم', period);
        if (_p['minutes'] != null) {
          add(Icons.timer_outlined, 'المدة', permitDurationLabel(_p['minutes']));
        }
        if (_text('excuseType') != null) {
          add(Icons.category_rounded, 'نوع العذر', _text('excuseType'));
        }
      default:
        add(Icons.date_range_rounded, 'الفترة', period);
        add(Icons.place_rounded, 'المكان', _text('location'));
        if (_text('notes') != null &&
            _text('notes')!.trim().isNotEmpty &&
            _text('notes') != request.reason?.trim()) {
          add(Icons.notes_rounded, 'ملاحظات', _text('notes'));
        }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = _rows();
    final reason = request.reason?.trim();
    final showReason =
        reason != null && reason.isNotEmpty && reason != request.title?.trim();
    if (rows.isEmpty && !showReason && request.attachments.isEmpty) {
      return const SizedBox.shrink();
    }
    return _SectionCard(
      icon: Icons.assignment_outlined,
      title: 'بيانات ${requestTypeDefiniteLabel(request.type)}',
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(rows[i].$1, size: 18, color: scheme.primary),
                const SizedBox(width: 10),
                SizedBox(
                  width: 104,
                  child: Text(
                    rows[i].$2,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    rows[i].$3,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (i < rows.length - 1)
            Divider(
              height: 1,
              thickness: 0.7,
              color: scheme.outlineVariant.withValues(alpha: .25),
            ),
        ],
        if (showReason) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.format_quote_rounded,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'السبب والتفاصيل',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  reason,
                  style: const TextStyle(fontSize: 13.5, height: 1.6),
                ),
              ],
            ),
          ),
        ],
        if (_p['startLocation'] is Map) ...[
          const SizedBox(height: 10),
          _StartLocationTile(
            location: Map<String, dynamic>.from(_p['startLocation'] as Map),
          ),
        ],
        if (request.attachments.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (var i = 0; i < request.attachments.length; i++)
            _AttachmentTile(attachment: request.attachments[i], index: i),
        ],
      ],
    );
  }
}

/// موقع بدء المأمورية كما سُجِّل لحظة إرسالها: العنوان/الإحداثيات، الدقة، الوقت،
/// فتح الخريطة، وتحذير صريح إن كان الموقع من تطبيق تزييف.
class _StartLocationTile extends StatelessWidget {
  const _StartLocationTile({required this.location});

  final Map<String, dynamic> location;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lat = (location['lat'] as num?)?.toDouble();
    final lng = (location['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return const SizedBox.shrink();
    final mocked = location['mocked'] == true;
    final accuracy = (location['accuracy'] as num?)?.round();
    final at = DateTime.tryParse(location['capturedAt']?.toString() ?? '');
    final address = location['address']?.toString().trim();
    final color = mocked ? AppColors.statusDanger : const Color(0xFF2563EB);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.my_location_rounded, size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'موقع بدء المأمورية',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      address != null && address.isNotEmpty
                          ? address
                          : '${lat.toStringAsFixed(5)}، ${lng.toStringAsFixed(5)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (at != null) arDateTime(at),
                        if (accuracy != null) 'الدقة ± $accuracy م',
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (mocked) ...[
            const SizedBox(height: 8),
            const Text(
              'تحذير: الموقع صادر عن تطبيق لتزييف المواقع، وليس من GPS الجهاز.',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: AppColors.statusDanger,
              ),
            ),
          ],
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(
                  'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
                ),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('فتح على الخريطة'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({required this.attachment, required this.index});

  final MobileRequestAttachment attachment;
  final int index;

  @override
  Widget build(BuildContext context) {
    final mime = attachment.mimeType.toLowerCase();
    final isImage = mime.startsWith('image/');
    final isPdf = mime.contains('pdf');
    final kb = attachment.sizeBytes / 1024;
    final size = attachment.sizeBytes <= 0
        ? null
        : kb < 1024
        ? '${kb.round()} كيلوبايت'
        : '${(kb / 1024).toStringAsFixed(1)} ميجابايت';
    return Card(
      margin: const EdgeInsets.only(top: 6),
      elevation: 0,
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: .35),
      child: ListTile(
        dense: true,
        leading: Icon(
          isImage
              ? Icons.image_outlined
              : isPdf
              ? Icons.picture_as_pdf_outlined
              : Icons.attach_file_rounded,
        ),
        title: Text(
          isImage
              ? 'صورة ${index + 1}'
              : isPdf
              ? 'ملف PDF ${index + 1}'
              : 'مرفق ${index + 1}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: size == null ? null : Text(size),
        trailing: const Icon(Icons.open_in_new_rounded, size: 18),
        onTap: () => _openAttachment(context, attachment.path),
      ),
    );
  }
}

/// بطاقة قسم بعنوان وأيقونة.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .6)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: AppColors.brandPrimary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// سياق القرار للمعتمِد: الرصيد، الزملاء خارج المقر، طلبات الشهر، البديل
// ═══════════════════════════════════════════════════════════════════════════

