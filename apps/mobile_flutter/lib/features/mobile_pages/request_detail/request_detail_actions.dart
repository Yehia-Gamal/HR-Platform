part of '../mobile_request_detail_page.dart';

// ═══════════════════════════════════════════════════════════════════════════
// الإجراءات: القرار، السحب، إعادة الرفع، فتح المرفق
// ═══════════════════════════════════════════════════════════════════════════

Future<void> _openDecision(
  BuildContext context,
  WidgetRef ref,
  MobileRequestDetail request,
  String decision,
) async {
  final done = await showRequestDecisionSheet(
    context,
    ref,
    requestId: request.id,
    number: request.number,
    type: request.type,
    employeeName: request.employeeName,
    decision: decision,
  );
  if (done) ref.invalidate(mobileRequestDetailProvider(request.id));
}

String _cancelButtonLabel(
  MobileRequestDetail request,
  bool isAdminOrHr,
  bool isMine,
) {
  if (isAdminOrHr && !isMine) {
    return request.status == 'approved'
        ? 'سحب / إلغاء الاعتماد (إدارياً)'
        : 'إلغاء الطلب إدارياً';
  }
  final typeNoun = switch (request.type) {
    'fundraising' => 'الفاندي',
    'convoy' => 'القافلة',
    'mission' => 'المأمورية',
    'leave' => 'الإجازة',
    'permit' || 'late_permit' || 'early_permit' => 'الإذن',
    _ => 'الطلب',
  };
  return request.status == 'approved'
      ? 'إلغاء $typeNoun'
      : (request.type == 'mission' ||
              request.type == 'convoy' ||
              request.type == 'fundraising'
          ? 'إلغاء $typeNoun'
          : 'سحب الطلب قبل صدور القرار');
}

Future<void> _openWithdraw(
  BuildContext context,
  WidgetRef ref,
  MobileRequestDetail request,
) async {
  final isApproved = request.status == 'approved';
  final done = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => RequestActionSheet(
      config: RequestSheetConfig(
        title: isApproved ? 'سحب / إلغاء الاعتماد' : 'سحب الطلب',
        icon: isApproved ? Icons.block_rounded : Icons.undo_rounded,
        color: AppColors.statusDanger,
        explanation: isApproved
            ? 'سيتم إلغاء اعتماد هذا الطلب إدارياً، واسترداد رصيد الإجازة للموظف (إن وجد)، وإعادة ضبط سجل الحضور، وإشعار الموظف فوراً.'
            : 'يتوقف مسار الاعتماد ولا يصل الطلب للمعتمدين. يمكنك تقديم طلب جديد لاحقًا.',
        inputLabel: isApproved ? 'سبب سحب الاعتماد (إلزامي)' : 'سبب السحب (إلزامي)',
        required: true,
        suggestions: isApproved
            ? const [
                'إلغاء بناءً على قرار الإدارة',
                'تغيير في خطة العمل وجدول التكليفات',
                'تم بالخطأ ويُستبدل بطلب آخر',
              ]
            : const [
                'لم أعد بحاجة إلى الطلب',
                'قُدِّم بالخطأ',
                'سأقدّم طلبًا آخر ببيانات صحيحة',
              ],
        confirmLabel: isApproved ? 'تأكيد سحب الاعتماد' : 'تأكيد السحب',
        successMessage: isApproved
            ? 'تم سحب وإلغاء الطلب المعتمد بنجاح.'
            : 'تم سحب الطلب وإيقاف مسار الاعتماد.',
      ),
      subject: '${requestTypeLabel(request.type)} · طلب رقم ${request.number}',
      onSubmit: (note) =>
          ref.read(mobileCommandsProvider).cancelRequest(request.id, note),
    ),
  );
  if (done != true || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        isApproved
            ? 'تم سحب وإلغاء الطلب المعتمد بنجاح.'
            : 'تم سحب الطلب وإيقاف مسار الاعتماد.',
      ),
    ),
  );
}

/// 0452: فتح نموذج التعديل معبّأً بالقيم الحالية ثم إعادة الرفع.
Future<void> _resubmit(
  BuildContext context,
  WidgetRef ref,
  MobileRequestDetail request,
) async {
  final result = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => NewRequestSheet(
      type: request.type,
      permitKind: request.payload['permitKind']?.toString(),
      initial: {
        'title': request.title,
        'reason': request.reason,
        'payload': request.payload,
      },
    ),
  );
  if (result == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref
        .read(mobileCommandsProvider)
        .resubmitRequest(
          requestId: request.id,
          title: result['title'] as String,
          reason: result['reason'] as String,
          payload: result['payload'] as Map<String, dynamic>,
        );
    ref.invalidate(mobileRequestDetailProvider(request.id));
    messenger.showSnackBar(
      const SnackBar(
        content: Text('تم تعديل الطلب وإعادة رفعه — بدأ مسار اعتماد جديد.'),
      ),
    );
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(requestErrorMessage(error) ?? humanizeError(error)),
      ),
    );
  }
}

Future<void> _openAttachment(BuildContext context, String path) async {
  try {
    final url = await Supabase.instance.client.storage
        .from('request-attachments')
        .createSignedUrl(path, 120)
        .timeout(const Duration(seconds: 20));
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// عداد تنازلي حي لمهلة الـ ساعتين
// ═══════════════════════════════════════════════════════════════════════════

/// شريط العد التنازلي الحي لمهلة الـ ساعتين حتى تصعيد الطلب لأبو عمار.
/// يظهر فقط للموظف صاحب الطلب وللمدير المباشر إذا كان الطلب pending.
