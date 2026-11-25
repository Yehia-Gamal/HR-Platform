part of '../mobile_attendance_page.dart';

String? _formatServerRecordedAt(dynamic raw) {
  if (raw == null) return null;
  final cairo = AppTime.tryParse(raw);
  if (cairo == null) return null;
  return DateFormat('h:mm a', 'ar').format(cairo);
}


extension _AttendancePunchFlow on _MobileAttendancePageState {
  Future<void> _punch(String action, {bool skipDialog = false}) async {
    // حارس إعادة الدخول: يمنع أي طلب بصمة ثانٍ أثناء وجود طلب قيد التنفيذ
    // (من زر ثانٍ أو إعادة محاولة عند الاستئناف) — تجنّب إرسال حضور مكرر.
    if (_working) return;

    // حارس الانصراف المبكر: منع الانصراف خلال أقل من دقيقتين من تسجيل الحضور
    if (action == 'CHECK_OUT') {
      final stateVal = ref.read(attendanceStateProvider).asData?.value;
      if (stateVal?.todayCheckInAt != null) {
        final elapsed = DateTime.now().toUtc().difference(stateVal!.todayCheckInAt!.toUtc()).inSeconds;
        if (elapsed < 120) {
          final waitSec = 120 - elapsed;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('سُجّل حضورك للتو. حفاظاً على صحة سجلك، الانصراف متاح بعد $waitSec ثانية.'),
                backgroundColor: AppColors.statusWarning,
              ),
            );
          }
          return;
        }
      }
    }

    _updateUi(() => _working = true);

    if (!skipDialog) {
      final shiftInfo = ref.read(myWorkShiftInfoProvider).asData?.value;
      final availableShifts = shiftInfo?.availableShifts ?? [];
      final currentShift = shiftInfo?.currentShift;
      String? chosenShiftId = currentShift?.id ?? (availableShifts.isNotEmpty ? availableShifts.first.id : null);

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            final scheme = Theme.of(ctx).colorScheme;
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Icon(
                    action == 'CHECK_IN'
                        ? Icons.fingerprint_rounded
                        : Icons.logout_rounded,
                    color: scheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    action == 'CHECK_IN'
                        ? 'تأكيد تسجيل الحضور'
                        : 'تأكيد تسجيل الانصراف',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (action == 'CHECK_IN' && availableShifts.isNotEmpty) ...[
                      Text(
                        'فترة العمل (الوردية) المعتمدة:',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.4),
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: chosenShiftId != null &&
                                    availableShifts.any((s) => s.id == chosenShiftId)
                                ? chosenShiftId
                                : (availableShifts.isNotEmpty ? availableShifts.first.id : null),
                            isExpanded: true,
                            icon: Icon(Icons.keyboard_arrow_down_rounded, color: scheme.primary),
                            items: availableShifts.map((shift) {
                              return DropdownMenuItem<String>(
                                value: shift.id,
                                child: Text(
                                  '${shift.name} (${shift.formattedRange})',
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setDialogState(() => chosenShiftId = val);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '⚡ يتم اعتماد الوردية المختارة فوراً دون الحاجة لموافقة المدير وتسجيل حضورك عليها مباشرة.',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Divider(height: 20),
                    ],
                    const Text(
                      'سيتم قراءة موقعك الحالي والتحقق الحي لتسجيل البصمة.',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx, false),
                  child: const Text('إلغاء'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    if (action == 'CHECK_IN' &&
                        chosenShiftId != null &&
                        chosenShiftId != currentShift?.id) {
                      try {
                        await ref
                            .read(mobileCommandsProvider)
                            .adoptMyWorkShift(shiftId: chosenShiftId!);
                      } catch (_) {}
                    }
                    if (dialogCtx.mounted) {
                      Navigator.pop(dialogCtx, true);
                    }
                  },
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('متابعة وتسجيل'),
                ),
              ],
            );
          },
        ),
      );
      if (confirmed != true) {
        if (mounted) _updateUi(() => _working = false);
        return;
      }
    }

    if (!mounted) return;
    try {
      final result = await ref
          .read(mobileCommandsProvider)
          .punchAttendanceLocal(eventType: action);

      // الخادم يرجع ok: false عند رفض العملية (خارج النطاق، تكرار، إلخ)
      if (result['ok'] != true) {
        if (mounted) {
          final errorCode = result['error'] as String? ?? 'unknown_error';
          // أخطاء الإعدادات (نطاق جغرافي غير معرّف) — بانر معلوماتي برتقالي.
          // أخطاء الانتهاك (خارج النطاق، موقع مزيف) — بانر أحمر.
          final isConfigIssue =
              errorCode == 'attendance_geofence_not_configured';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_humanizePunchError(errorCode)),
              backgroundColor: isConfigIssue
                  ? AppColors.statusWarning
                  : AppColors.statusDanger,
            ),
          );
        }
        return;
      }

      // punchAttendanceLocal() already invalidates the relevant providers.
      if (mounted) {
        if (action == 'CHECK_OUT' && result['penaltyWaived'] == true) {
          final waivedAmount = result['waivedAmount'];
          final checkIn = result['checkIn'];
          final checkOut = result['checkOut'];
          final msg = result['message'] as String? ??
              'تم استيفاء 8 ساعات عمل كاملة — تم إلغاء خصم غرامة التأخير ($waivedAmount ج.م) بنجاح 🎉';
          showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(
                    Icons.celebration_rounded,
                    color: AppColors.statusSuccess,
                    size: 28,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'إلغاء غرامة التأخير 🎉',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    msg,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.statusSuccess.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.statusSuccess.withValues(alpha: .3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (checkIn != null)
                          Text(
                            '⏰ وقت الحضور: $checkIn',
                            style: const TextStyle(fontSize: 13),
                          ),
                        if (checkOut != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '🚪 وقت الانصراف: $checkOut',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                        const SizedBox(height: 4),
                        const Text(
                          '⏱️ إجمالي العمل: 8 ساعات كاملة (تم استيفاء وقت العمل المقرر)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('الحمد لله'),
                ),
              ],
            ),
          );
        } else if (action == 'CHECK_OUT' && result['penaltyRemaining'] == true) {
          final penaltyAmount = result['penaltyAmount'];
          final remainingMins = result['remainingMinutes'];
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'تنبيه: تم تسجيل الانصراف قبل إتمام 8 ساعات عمل (متبقي $remainingMins دقيقة) — غرامة التأخير ($penaltyAmount ج.م) تظل مستحقة السداد.',
              ),
              backgroundColor: AppColors.statusWarning,
              duration: const Duration(seconds: 5),
            ),
          );
        } else {
          final serverTimeText = _formatServerRecordedAt(result['recordedAt']);
          final distanceRaw = result['distanceMeters'];
          final distanceText = distanceRaw is num
              ? ' (${distanceRaw.round()} م من النطاق)'
              : '';
          final baseText = action == 'CHECK_IN'
              ? 'تم تسجيل الحضور بنجاح ✓'
              : 'تم تسجيل الانصراف بنجاح ✓';
          final receiptText = serverTimeText != null
              ? '$baseText — وقت الخادم: $serverTimeText$distanceText'
              : '$baseText$distanceText';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(receiptText),
              backgroundColor: AppColors.statusSuccess,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } on AttendanceOfflineException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppColors.statusDanger,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } on OfflineQueuedException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(const AttendanceOfflineException().toString()),
            backgroundColor: AppColors.statusDanger,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } on GpsDisabledException {
      if (mounted) {
        _updateUi(() => _issueKind = _LocationIssueKind.gpsOff);
        final opened = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('الموقع مغلق'),
            content: const Text('يرجى تفعيل خدمة الموقع (GPS) للمتابعة.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('تفعيل الموقع'),
              ),
            ],
          ),
        );
        if (opened == true) {
          _pendingRetry = _PendingRetry.punch(action);
          await Geolocator.openLocationSettings();
        } else {
          if (!mounted) return;
          _updateUi(() {
            _issueKind = null;
            _pendingRetry = null;
          });
        }
      }
    } on GpsPermissionDeniedException catch (e) {
      if (mounted) {
        if (e.isDeniedForever) {
          _updateUi(() => _issueKind = _LocationIssueKind.deniedForever);
          final opened = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('صلاحية الموقع مرفوضة'),
              content: const Text(
                'صلاحية الموقع مرفوضة نهائيًا. افتح إعدادات التطبيق لتفعيلها.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('فتح الإعدادات'),
                ),
              ],
            ),
          );
          if (opened == true) {
            _pendingRetry = _PendingRetry.punch(action);
            await Geolocator.openAppSettings();
          } else {
            if (!mounted) return;
            _updateUi(() {
              _issueKind = null;
              _pendingRetry = null;
            });
          }
        } else {
          final perm = await Geolocator.requestPermission();
          if (!mounted) return;
          if (perm == LocationPermission.always ||
              perm == LocationPermission.whileInUse) {
            // أُعيد التعيين قبل الاستدعاء التكراري لتجاوز حارس إعادة الدخول،
            // ثم يُنتظَر الطلب الداخلي حتى يكتمل قبل أن يُعيد finally تفعيل الزر.
            if (mounted) _updateUi(() => _working = false);
            await _punch(action, skipDialog: true);
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('يرجى منح صلاحية الموقع للمتابعة.')),
          );
        }
      }
    } on GpsAccuracyException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (error, stack) {
      _showErrorFeedback(error, stack, contextTag: '_punch');
    } finally {
      if (mounted) _updateUi(() => _working = false);
    }
  }

  /// إظهار رسائل الخطأ بوضوح وتوجيه الموظف إذا كانت المشكلة في قفل الشاشة أو البصمة.
}
