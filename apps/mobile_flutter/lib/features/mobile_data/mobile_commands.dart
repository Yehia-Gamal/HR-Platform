part of 'mobile_providers.dart';

final mobileCommandsProvider = Provider<MobileCommands>(
  (ref) => MobileCommands(ref),
);

class MobileCommands {
  MobileCommands(this.ref);
  final Ref ref;
  Future<void> submitRequest(
    String type,
    String title,
    String reason,
    Map<String, dynamic> payload,
  ) async {
    // مفتاح idempotency يمنع الإرسال المزدوج عند إعادة المحاولة أو الضغط المزدوج.
    final idempotencyKey = const Uuid().v4();
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'submit_my_request',
          params: {
            'p_request_type':    type,
            'p_title':           title,
            'p_reason':          reason,
            'p_payload':         payload,
            'p_idempotency_key': idempotencyKey,
          },
        ));
    ref.invalidate(mobileRequestsProvider);
    ref.invalidate(employeeHomeProvider);
  }

  Future<void> startMission(String requestId) async {
    await _withTimeout(ref.read(supabaseProvider).rpc<dynamic>(
          'start_my_mission',
          params: {'p_request_id': requestId},
        ));
    ref.invalidate(mobileRequestsProvider);
    ref.invalidate(employeeHomeProvider);
  }

  Future<void> endMission({
    required String requestId,
    required String report,
    String? outcome,
  }) async {
    await _withTimeout(ref.read(supabaseProvider).rpc<dynamic>(
          'end_my_mission',
          params: {
            'p_request_id': requestId,
            'p_report': report,
            'p_outcome': outcome,
          },
        ));
    ref.invalidate(mobileRequestsProvider);
    ref.invalidate(employeeHomeProvider);
  }
    Future<Map<String, dynamic>> uploadRequestAttachment({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final client = ref.read(supabaseProvider);
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('AUTHENTICATION_REQUIRED');
    final normalizedMime = _allowedImageMime(mimeType, fileName);
    final extension = switch (normalizedMime) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    final path = '$userId/${const Uuid().v4()}.$extension';
    await client.storage.from('request-attachments').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: normalizedMime, upsert: false),
        ).timeout(const Duration(seconds: 60));
    return {
      'path': path,
      'name': fileName,
      'mimeType': normalizedMime,
      'sizeBytes': bytes.length,
    };
  }

  Future<void> deleteRequestAttachments(Iterable<String> paths) async {
    final values = paths.where((path) => path.trim().isNotEmpty).toList();
    if (values.isEmpty) return;
    await ref
        .read(supabaseProvider)
        .storage
        .from('request-attachments')
        .remove(values);
  }

  static String _allowedImageMime(String mimeType, String fileName) {
    final value = mimeType.toLowerCase();
    if (value == 'image/png' || value == 'image/webp' || value == 'image/jpeg') {
      return value;
    }
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.png')) return 'image/png';
    if (lowerName.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> decideRequest(
    String id,
    String decision,
    String? comment,
  ) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'decide_request',
          params: {
            'p_request_id': id,
            'p_decision': decision,
            'p_comment': comment,
          },
        ));
    ref.invalidate(mobileRequestsProvider);
    ref.invalidate(mobileActionCenterProvider);
    ref.invalidate(managerDashboardProvider);
    ref.invalidate(executiveDashboardProvider);
  }

  Future<void> cancelRequest(String id, String reason) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'cancel_request',
          params: {'p_request_id': id, 'p_reason': reason.trim()},
        ));
    ref.invalidate(mobileRequestsProvider);
    ref.invalidate(mobileRequestDetailProvider(id));
    ref.invalidate(mobileActionCenterProvider);
    ref.invalidate(employeeHomeProvider);
  }

  // إنشاء تكليف عمل (مأمورية/قافلة/فاندي) بواسطة المدير لتابعيه.
  Future<void> createWorkAssignment({
    required String assignmentType,
    required String title,
    required DateTime startAt,
    required DateTime endAt,
    required List<String> participantIds,
    String? description,
    String? location,
    bool isFullDay = true,
    bool needsReport = false,
    double? targetAmount,
  }) async {
    final payload = <String, dynamic>{
      'isFullDay': isFullDay,
      'targetAmount': ?targetAmount,
    };
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'create_work_assignment',
          params: {
            'p_assignment_type': assignmentType,
            'p_title': title.trim(),
            'p_start_at': startAt.toUtc().toIso8601String(),
            'p_end_at': endAt.toUtc().toIso8601String(),
            'p_participant_ids': participantIds,
            'p_description': description?.trim(),
            'p_location': location?.trim(),
            'p_needs_report': needsReport,
            'p_payload': payload,
          },
        ));
    ref.invalidate(workAssignmentsProvider('team'));
    ref.invalidate(workAssignmentsProvider('mine'));
    ref.invalidate(employeeHomeProvider);
  }

  // قرار على تكليف عمل (اعتماد/رفض).
  Future<void> decideWorkAssignment(
    String id,
    String decision,
    String? comment,
  ) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'decide_work_assignment',
          params: {
            'p_assignment_id': id,
            'p_decision': decision,
            'p_comment': comment?.trim(),
          },
        ));
    ref.invalidate(workAssignmentsProvider('team'));
    ref.invalidate(workAssignmentsProvider('mine'));
  }

  // إرسال تقرير تنفيذ التكليف من المشارك.
  Future<void> submitAssignmentReport(
    String id,
    String report, {
    String? outcome,
    double? achievedAmount,
  }) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'submit_assignment_report',
          params: {
            'p_assignment_id': id,
            'p_report': report.trim(),
            'p_outcome': outcome?.trim(),
            'p_achieved_amount': achievedAmount,
          },
        ));
    ref.invalidate(workAssignmentsProvider('mine'));
    ref.invalidate(workAssignmentsProvider('team'));
  }

  Future<void> advanceKpi(
    String id,
    String action,
    String? note, {
    List<Map<String, dynamic>>? scores,
  }) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'advance_kpi_stage',
          params: {
            'p_evaluation_id': id,
            'p_action': action,
            'p_scores': scores,
            'p_note': note,
          },
        ));
    ref.invalidate(mobileKpiProvider);
    ref.invalidate(kpiEvaluationFormProvider(id));
    ref.invalidate(mobileActionCenterProvider);
    ref.invalidate(employeeHomeProvider);
    ref.invalidate(managerDashboardProvider);
    ref.invalidate(executiveDashboardProvider);
  }

  Future<void> returnKpi(String id, String targetStage, String note) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'return_kpi_stage',
          params: {
            'p_evaluation_id': id,
            'p_target_stage': targetStage,
            'p_note': note,
          },
        ));
    ref.invalidate(mobileKpiProvider);
    ref.invalidate(kpiEvaluationFormProvider(id));
    ref.invalidate(mobileActionCenterProvider);
    ref.invalidate(employeeHomeProvider);
    ref.invalidate(managerDashboardProvider);
    ref.invalidate(executiveDashboardProvider);
  }

  Future<void> saveKpiGoalProgress(
    String evaluationId,
    KpiGoalForm goal, {
    required double achievedValue,
    required String status,
    String? evidenceSource,
    String? employeeNote,
  }) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'save_kpi_goal',
          params: {
            'p_evaluation_id': evaluationId,
            'p_goal_id': goal.id,
            'p_title': goal.title,
            'p_description': null,
            'p_target_value': goal.targetValue,
            'p_achieved_value': achievedValue,
            'p_unit': goal.unit,
            'p_weight': goal.weight,
            'p_due_date': null,
            'p_evidence_source': evidenceSource,
            'p_employee_note': employeeNote,
            'p_manager_note': null,
            'p_status': status,
          },
        ));
    ref.invalidate(kpiEvaluationFormProvider(evaluationId));
  }

  Future<void> saveKpiSession(
    String evaluationId,
    Map<String, dynamic> session,
  ) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'save_kpi_review_session',
          params: {'p_evaluation_id': evaluationId, 'p_session': session},
        ));
    ref.invalidate(kpiEvaluationFormProvider(evaluationId));
  }

  Future<void> saveKpiCompliance(
    String evaluationId,
    String metric,
    int required,
    int actual,
    int exempt,
    int cancelled,
    String? note,
  ) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'save_kpi_compliance_metric',
          params: {
            'p_evaluation_id': evaluationId,
            'p_metric': metric,
            'p_required': required,
            'p_actual': actual,
            'p_exempt': exempt,
            'p_cancelled': cancelled,
            'p_note': note,
          },
        ));
    ref.invalidate(kpiEvaluationFormProvider(evaluationId));
  }

  Future<void> acknowledgeKpi(
    String evaluationId,
    String? note,
    String? appealReason,
  ) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'acknowledge_kpi_evaluation',
          params: {
            'p_evaluation_id': evaluationId,
            'p_note': note,
            'p_appeal_reason': appealReason,
          },
        ));
    ref.invalidate(mobileKpiProvider);
    ref.invalidate(kpiEvaluationFormProvider(evaluationId));
    ref.invalidate(mobileActionCenterProvider);
  }

  Future<void> requestLocation(
    String employeeId,
    String reason,
  ) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'request_live_location',
          params: {
            'p_employee_id': employeeId,
            'p_mode': 'snapshot',
            'p_reason': reason,
          },
        ));
    ref.invalidate(locationDirectoryProvider);
    ref.invalidate(executiveDashboardProvider);
  }

  Future<void> cancelLocationRequest(String requestId) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'cancel_location_request_as_requester',
          params: {'p_request_id': requestId},
        ));
    ref.invalidate(locationDirectoryProvider);
    ref.invalidate(executiveDashboardProvider);
  }

  Future<void> respondLocation(String requestId, bool accept) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'respond_live_location_request',
          params: {'p_request_id': requestId, 'p_accept': accept},
        ));
    ref.invalidate(myLocationRequestsProvider);
    ref.invalidate(employeeHomeProvider);
  }

  Future<void> submitLocationPoint(
    String requestId, {
    required double latitude,
    required double longitude,
    required double accuracy,
    double? altitude,
    double? speed,
    double? heading,
    bool isMock = false,
    String? addressAr,
  }) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'submit_live_location_point',
          params: {
            'p_request_id': requestId,
            'p_latitude': latitude,
            'p_longitude': longitude,
            'p_accuracy': accuracy,
            'p_altitude': altitude,
            'p_speed': speed,
            'p_heading': heading,
            'p_is_mock': isMock,
            'p_address_ar': addressAr,
          },
        ));
    ref.invalidate(myLocationRequestsProvider);
  }

  Future<void> upsertPushToken(String fcmToken, String platform) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'upsert_my_push_token',
          params: {'p_fcm_token': fcmToken, 'p_platform': platform},
        ));
  }

  Future<void> completeLocation(String requestId) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'complete_my_live_location_request',
          params: {'p_request_id': requestId},
        ));
    ref.invalidate(myLocationRequestsProvider);
  }

  Future<void> uploadLocationVideo(
    String requestId, {
    required String employeeId,
    required String filePath,
    required int durationSeconds,
    required double latitude,
    required double longitude,
    required double accuracy,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw StateError('لم يتم العثور على ملف الفيديو. أعد التسجيل.');
    }
    final sizeBytes = await file.length();
    if (sizeBytes <= 0) {
      throw StateError('ملف الفيديو فارغ. أعد التسجيل.');
    }
    if (sizeBytes > 15 * 1024 * 1024) {
      throw StateError('حجم الفيديو أكبر من الحد المسموح. أعد التسجيل.');
    }

    final storagePath =
        '$employeeId/$requestId/${DateTime.now().toUtc().microsecondsSinceEpoch}.mp4';
    final client = ref.read(supabaseProvider);
    await _withTimeout(
      client.storage.from('live-location-videos').upload(
            storagePath,
            file,
            fileOptions: const FileOptions(
              contentType: 'video/mp4',
              upsert: false,
            ),
          ),
      const Duration(seconds: 60),
    );
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'register_live_location_video',
          params: {
            'p_request_id': requestId,
            'p_storage_path': storagePath,
            'p_duration_seconds': durationSeconds,
            'p_size_bytes': sizeBytes,
            'p_mime_type': 'video/mp4',
            'p_latitude': latitude,
            'p_longitude': longitude,
            'p_accuracy': accuracy,
          },
        ));
    ref.invalidate(myLocationRequestsProvider);
  }

  Future<void> registerLocationMapSnapshot(
    String requestId, {
    required String storagePath,
  }) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'register_live_location_map_snapshot',
          params: {'p_request_id': requestId, 'p_storage_path': storagePath},
        ));
    ref.invalidate(myLocationRequestsProvider);
  }

  Future<bool> supportsPasskeys() =>
      ref.read(passkeyAttendanceServiceProvider).isSupported();
  Future<void> registerPasskey({String deviceLabel = 'هاتف الموظف'}) async {
    await ref
        .read(passkeyAttendanceServiceProvider)
        .register(deviceLabel: deviceLabel);
    ref.invalidate(attendanceStateProvider);
    ref.invalidate(myPasskeysProvider);
  }

  Future<void> registerLocalBiometricDevice() async {
    final localAuth = LocalAuthentication();
    // تحقق من توفر بصمة فعلية — إذا لم تتوفر يُسمح بقفل الشاشة (نقش/PIN) كبديل.
    bool hasBiometrics = false;
    try {
      if (await localAuth.canCheckBiometrics) {
        final available = await localAuth.getAvailableBiometrics();
        hasBiometrics = available.isNotEmpty;
      }
    } catch (_) {
      // بعض الأجهزة ترمي استثناءً — نتجاهله ونكمل بقفل الشاشة.
    }
    // biometricOnly: false → يسمح بالنقش أو PIN عند عدم توفر بصمة.
    final didAuthenticate = await localAuth.authenticate(
      localizedReason: hasBiometrics
          ? 'تأكيد تسجيل البصمة لنظام الحضور'
          : 'تأكيد تسجيل الجهاز بالنقش أو PIN لنظام الحضور',
      options: const AuthenticationOptions(
        stickyAuth: true,
        biometricOnly: false,
        useErrorDialogs: true,
      ),
    );
    if (!didAuthenticate) {
      throw StateError('تم إلغاء التحقق. لم يتم التسجيل.');
    }
    ref.invalidate(deviceRegistrationProvider);
    await ref.read(deviceRegistrationProvider.future);
    ref.invalidate(attendanceStateProvider);
  }

  Future<Map<String, dynamic>> punchAttendance({
    required String eventType,
  }) async {
    final result = await ref
        .read(passkeyAttendanceServiceProvider)
        .punch(eventType);
    ref.invalidate(attendanceStateProvider);
    ref.invalidate(myAttendanceHistoryProvider);
    ref.invalidate(employeeHomeProvider);
    return result;
  }

  /// حضور انفرادي: بصمة محلية أو قفل شاشة + موقع → RPC مبسط (بدون WebAuthn/Samsung Pass).
  /// أجهزة بدون بصمة تستخدم PIN/نمط كبديل (biometricOnly: false).
  Future<Map<String, dynamic>> punchAttendanceLocal({
    required String eventType,
  }) async {
    final localAuth = LocalAuthentication();
    // تحديد ما إذا كان الجهاز يملك بصمة فعلية (إصبع/وجه)
    bool hasBiometrics = false;
    try {
      if (await localAuth.canCheckBiometrics) {
        final available = await localAuth.getAvailableBiometrics();
        hasBiometrics = available.isNotEmpty;
      }
    } catch (_) {
      // بعض الأجهزة ترمي استثناءً — نتابع بقفل الشاشة.
    }
    // biometricOnly: false → يسمح بالنقش أو PIN عند عدم توفر بصمة.
    final didAuthenticate = await localAuth.authenticate(
      localizedReason: hasBiometrics
          ? 'تأكيد تسجيل الحضور بالبصمة'
          : 'تأكيد تسجيل الحضور بالنقش أو PIN',
      options: const AuthenticationOptions(
        stickyAuth: true,
        biometricOnly: false,
        useErrorDialogs: true,
      ),
    );
    if (!didAuthenticate) {
      throw StateError('تم إلغاء التحقق.');
    }

    final position = await LocationService.current();
    final operationId = const Uuid().v4();
    final installationId = await ref.read(installationIdProvider.future);
    final data = await retryWithBackoff(
      () => ref
          .read(supabaseProvider)
          .rpc<Map<String, dynamic>>(
            'punch_attendance_local_biometric_v1',
            params: {
              'p_operation_id': operationId,
              'p_event_type': eventType,
              'p_installation_id': installationId,
              'p_latitude': position.latitude,
              'p_longitude': position.longitude,
              'p_accuracy_meters': position.accuracy,
              'p_is_mock': position.isMocked,
            },
          )
          .timeout(const Duration(seconds: 20)),
    );
    ref.invalidate(attendanceStateProvider);
    ref.invalidate(myAttendanceHistoryProvider);
    ref.invalidate(employeeHomeProvider);
    return data;
  }

  Future<void> revokePasskey(String credentialId, String reason) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'revoke_my_passkey',
          params: {
            'p_credential_id': credentialId,
            'p_reason': reason.trim().isEmpty ? null : reason.trim(),
          },
        ));
    ref.invalidate(myPasskeysProvider);
    ref.invalidate(attendanceStateProvider);
  }

  /// هاتف مفقود — يلغي الجهاز النشط ويسمح بتسجيل جهاز جديد
  Future<void> requestDeviceReplacement(String reason) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'request_device_replacement',
          params: {
            'p_reason': reason.trim().isEmpty ? null : reason.trim(),
          },
        ));
    ref.invalidate(myPasskeysProvider);
    ref.invalidate(attendanceStateProvider);
  }

  Future<MobileActionTarget> resolveAction(MobileActionItem item) async {
    return ref.read(mobileActionTargetProvider(item).future);
  }

  Future<void> acknowledge(MobileFeedItem item) async {
    final function = item.kind == 'decision'
        ? 'acknowledge_decision'
        : 'acknowledge_announcement';
    final params = item.kind == 'decision'
        ? {'p_decision_id': item.id, 'p_acknowledge': true}
        : {'p_announcement_id': item.id};
    await _withTimeout(ref.read(supabaseProvider).rpc<dynamic>(function, params: params));
    ref.invalidate(mobileFeedProvider);
    ref.invalidate(employeeHomeProvider);
  }

  Future<void> recordAnnouncementView(String announcementId) async {
    await _withTimeout(ref.read(supabaseProvider).rpc<dynamic>(
      'record_announcement_view',
      params: {'p_announcement_id': announcementId},
    ));
    ref.invalidate(mobileFeedProvider);
  }

  Future<void> toggleAnnouncementReaction(
    String announcementId,
    String reactionType,
  ) async {
    await _withTimeout(ref.read(supabaseProvider).rpc<dynamic>(
      'toggle_announcement_reaction',
      params: {
        'p_announcement_id': announcementId,
        'p_reaction_type': reactionType,
      },
    ));
    ref.invalidate(mobileFeedProvider);
    ref.invalidate(
      mobileFeedDetailProvider((kind: 'announcement', id: announcementId)),
    );
  }
}

extension ExecutiveDisputeCommands on MobileCommands {
  /// 0198 — تقديم رأي/توصية على قضية
  Future<void> submitDisputeRecommendation({
    required String caseId,
    required String text,
    String statementType = 'recommendation',
  }) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'submit_dispute_statement',
          params: {
            'p_case_id': caseId,
            'p_statement_type': statementType,
            'p_statement_text': text.trim(),
            'p_visibility': 'committee_only',
          },
        ));
    ref.invalidate(disputeCaseRecommendationsProvider(caseId));
    ref.invalidate(committeeDisputePortalProvider);
  }

  Future<void> decideAdminAction({
    required String caseId,
    required String decision,
    required String reason,
    String? modifiedAction,
    String? modifiedDetail,
  }) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'decide_admin_action',
          params: {
            'p_case_id': caseId,
            'p_decision': decision,
            'p_reason': reason.trim(),
            'p_modified_action': modifiedAction,
            'p_modified_detail': modifiedDetail?.trim(),
          },
        ));
    ref.invalidate(executiveDisputeInboxProvider);
    ref.invalidate(committeeDisputePortalProvider);
    ref.invalidate(myDisputePortalProvider);
    ref.invalidate(executiveDashboardProvider);
  }

  /// اقتراح إجراء إداري — يستخدمه مقرر/رئيس اللجنة بعد صدور القرار
  Future<void> proposeAdminAction({
    required String caseId,
    required String action,
    required String detail,
  }) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'propose_admin_action',
          params: {
            'p_case_id': caseId,
            'p_action': action,
            'p_detail': detail.trim(),
          },
        ));
    ref.invalidate(committeeDisputePortalProvider);
    ref.invalidate(executiveDisputeInboxProvider);
  }

  /// تنفيذ الإجراء الإداري المعتمد — يستخدمه HR
  Future<void> executeAdminAction({
    required String caseId,
    required String notes,
  }) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'execute_admin_action',
          params: {
            'p_case_id': caseId,
            'p_notes': notes.trim(),
          },
        ));
    ref.invalidate(committeeDisputePortalProvider);
    ref.invalidate(executiveDisputeInboxProvider);
    ref.invalidate(executiveDashboardProvider);
  }

  /// جدولة جلسة نزاع — schedule_dispute_session_v2 (وليس transition_dispute_case)
  Future<String> scheduleDisputeSession({
    required String caseId,
    required String type,
    required DateTime scheduledAt,
    DateTime? endsAt,
    String? location,
    String modality = 'in_person',
  }) async {
    final result = await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'schedule_dispute_session_v2',
          params: {
            'p_case_id': caseId,
            'p_type': type,
            'p_scheduled_at': scheduledAt.toUtc().toIso8601String(),
            'p_ends_at': endsAt?.toUtc().toIso8601String(),
            'p_location': location?.trim().isEmpty ?? true
                ? null
                : location?.trim(),
            'p_modality': modality,
          },
        ));
    ref.invalidate(committeeDisputePortalProvider);
    ref.invalidate(executiveDisputeInboxProvider);
    ref.invalidate(myDisputePortalProvider);
    return result?.toString() ?? caseId;
  }

  /// إصدار قرار اللجنة — issue_dispute_decision (يتطلب جلسة مُعقدة بحضور النصاب)
  Future<void> issueDisputeDecision({
    required String caseId,
    required String sessionId,
    required String text,
    required String rationale,
    required String outcome,
  }) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'issue_dispute_decision',
          params: {
            'p_case_id': caseId,
            'p_session_id': sessionId,
            'p_text': text.trim(),
            'p_rationale': rationale.trim(),
            'p_outcome': outcome,
          },
        ));
    ref.invalidate(committeeDisputePortalProvider);
    ref.invalidate(executiveDisputeInboxProvider);
    ref.invalidate(myDisputePortalProvider);
    ref.invalidate(disputeCaseHeldSessionsProvider(caseId));
  }

  /// تسجيل تسوية — record_dispute_settlement
  Future<void> recordDisputeSettlement({
    required String caseId,
    required String type,
    required String from,
    String? to,
    String? text,
  }) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'record_dispute_settlement',
          params: {
            'p_case_id': caseId,
            'p_type': type,
            'p_from': from,
            'p_to': to,
            'p_text': (text?.trim().isNotEmpty ?? false) ? text!.trim() : null,
          },
        ));
    ref.invalidate(committeeDisputePortalProvider);
    ref.invalidate(executiveDisputeInboxProvider);
    ref.invalidate(myDisputePortalProvider);
  }

  /// 0202 — نقل حالة القضية (سكرتير/أدمن/لجنة)
  Future<String> transitionDisputeCase({
    required String caseId,
    required String action,
    String? reason,
    Map<String, dynamic>? metadata,
  }) async {
    final result = await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'transition_dispute_case',
          params: {
            'p_case_id': caseId,
            'p_action': action,
            'p_reason': reason?.trim(),
            'p_metadata': metadata ?? {},
          },
        ));
    ref.invalidate(committeeDisputePortalProvider);
    ref.invalidate(executiveDisputeInboxProvider);
    ref.invalidate(myDisputePortalProvider);
    return result?.toString() ?? action;
  }
}

extension MobileLearningCommands on MobileCommands {
  Future<void> transitionLearning(
    String enrollmentId,
    String status, {
    int? progress,
    double? score,
  }) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'transition_learning_enrollment',
          params: {
            'p_enrollment_id': enrollmentId,
            'p_status': status,
            'p_progress': progress,
            'p_score': score,
          },
        ));
    ref.invalidate(myLearningCatalogProvider);
  }
}

extension MobileServiceCommands on MobileCommands {
  Future<void> submitServiceRequest({
    required String catalogItemId,
    required String title,
    String? description,
    String priority = 'normal',
  }) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'submit_my_service_request',
          params: {
            'p_catalog_item_id': catalogItemId,
            'p_title': title.trim(),
            'p_description': description?.trim(),
            'p_priority': priority,
            'p_payload': <String, dynamic>{},
          },
        ));
    ref.invalidate(myServicePortalProvider);
  }
}

extension MobileNewFeaturesCommands on MobileCommands {
  /// مشاركة موقع استباقية للمدير التنفيذي — الموظف يُرسل موقعه دون طلب.
  Future<Map<String, dynamic>> shareMyLocationProactively({
    required double latitude,
    required double longitude,
    double? accuracy,
    int durationMinutes = 60,
    String? reason,
    int? batteryLevel,
  }) async {
    final result = await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'share_my_location_proactively',
          params: {
            'p_latitude': latitude,
            'p_longitude': longitude,
            'p_accuracy': accuracy,
            'p_duration_minutes': durationMinutes,
            'p_reason': reason,
            'p_battery_level': batteryLevel,
          },
        ));
    return Map<String, dynamic>.from(result as Map<dynamic, dynamic>);
  }

  /// تبديل الإعجاب على تقرير يومي.
  Future<void> toggleDailyReportLike(String reportId) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'toggle_daily_report_like',
          params: {'p_report_id': reportId},
        ));
    ref.invalidate(dailyReportsFeedProvider(null));
  }

  /// إضافة تعليق على تقرير يومي.
  Future<void> addDailyReportComment(String reportId, String comment) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'add_daily_report_comment',
          params: {
            'p_report_id': reportId,
            'p_comment': comment.trim(),
          },
        ));
    ref.invalidate(dailyReportsFeedProvider(null));
  }

  /// حذف تعليق على تقرير يومي (للصاحب فقط).
  Future<void> deleteDailyReportComment(String commentId) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'delete_daily_report_comment',
          params: {'p_comment_id': commentId},
        ));
    ref.invalidate(dailyReportsFeedProvider(null));
  }
}

extension MobileDailyCommands on MobileCommands {
  Future<void> transitionTask(String taskId, String status) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'transition_my_task',
          params: {'p_task_id': taskId, 'p_status': status},
        ));
    ref.invalidate(mobileTasksProvider);
    ref.invalidate(employeeHomeProvider);
  }

  Future<void> markNotificationsRead([List<String>? ids]) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>('mark_my_notifications_read', params: {'p_ids': ids}));
    ref.invalidate(myNotificationsProvider);
    ref.invalidate(employeeHomeProvider);
  }

  Future<void> saveDailyReport({
    required DateTime reportDate,
    required String achievements,
    String? blockers,
    String? tomorrowPlan,
  }) async {
    final date =
        '${reportDate.year.toString().padLeft(4, '0')}-${reportDate.month.toString().padLeft(2, '0')}-${reportDate.day.toString().padLeft(2, '0')}';
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'upsert_my_daily_report',
          params: {
            'p_report_date': date,
            'p_achievements': achievements,
            'p_blockers': blockers,
            'p_tomorrow_plan': tomorrowPlan,
          },
        ));
    ref.invalidate(mobileDailyReportsProvider(null));
    ref.invalidate(employeeHomeProvider);
  }

  Future<void> reviewDailyReport({
    required String reportId,
    required String comment,
    required String employeeId,
  }) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'review_daily_report',
          params: {
            'p_report_id': reportId,
            'p_manager_comment': comment.trim(),
          },
        ));
    ref.invalidate(mobileDailyReportsProvider(employeeId));
    ref.invalidate(mobileTeamProvider);
  }

  Future<void> createTeamTask({
    required String employeeId,
    required String title,
    String? description,
    String priority = 'medium',
    DateTime? dueDate,
  }) async {
    final due = dueDate == null
        ? null
        : '${dueDate.year.toString().padLeft(4, '0')}-${dueDate.month.toString().padLeft(2, '0')}-${dueDate.day.toString().padLeft(2, '0')}';
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'create_team_task',
          params: {
            'p_employee_id': employeeId,
            'p_title': title,
            'p_description': description,
            'p_priority': priority,
            'p_due_date': due,
          },
        ));
    ref.invalidate(mobileTeamProvider);
    ref.invalidate(managerDashboardProvider);
  }
}

extension MobileSelfServiceCommands on MobileCommands {
  Future<void> requestAttendanceCorrection({
    required DateTime workDate,
    required String type,
    required String reason,
    DateTime? checkIn,
    DateTime? checkOut,
    String? requestedStatus,
  }) async {
    String date(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'request_attendance_correction',
          params: {
            'p_work_date': date(workDate),
            'p_type': type,
            'p_reason': reason.trim(),
            'p_check_in': checkIn?.toUtc().toIso8601String(),
            'p_check_out': checkOut?.toUtc().toIso8601String(),
            'p_status': requestedStatus,
            'p_attachment_path': null,
          },
        ));
    ref.invalidate(myAttendanceServicesProvider);
    ref.invalidate(myAttendanceHistoryProvider);
  }

  /// V23: نموذج مبسط — بدون أولوية أو موقع أو مرفقات
  Future<String> submitDisputeV23({
    required String title,
    required String description,
    required String caseType,
    required List<String> respondentIds,
    List<String> witnessIds = const [],
  }) async {
    final data = await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'submit_my_dispute_v23',
          params: {
            'p_title': title.trim(),
            'p_description': description.trim(),
            'p_case_type': caseType,
            'p_parties': [
              for (final id in respondentIds)
                {'employeeId': id, 'type': 'respondent'},
            ],
            'p_witnesses': [
              for (final id in witnessIds)
                {'employeeId': id, 'type': 'witness'},
            ],
            'p_truth_confirmed': true,
            'p_confidentiality_accepted': true,
          },
        ));
    ref.invalidate(myDisputePortalProvider);
    return data as String;
  }

  Future<void> uploadDisputeEvidence({
    required String caseId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final client = ref.read(supabaseProvider);
    final normalizedMime = MobileCommands._allowedImageMime(mimeType, fileName);
    final extension = switch (normalizedMime) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    final path = '$caseId/${const Uuid().v4()}.$extension';
    await client.storage.from('dispute-evidence').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: normalizedMime, upsert: false),
        ).timeout(const Duration(seconds: 60));
    try {
      await _withTimeout(client.rpc<dynamic>(
        'register_dispute_evidence',
        params: {
          'p_case_id': caseId,
          'p_title': fileName,
          'p_storage_path': path,
          'p_mime_type': normalizedMime,
          'p_file_size_bytes': bytes.length,
          'p_visibility': 'submitter_and_committee',
          'p_description': null,
        },
      ));
    } catch (e) {
      await client.storage.from('dispute-evidence').remove([path]);
      rethrow;
    }
    ref.invalidate(myDisputePortalProvider);
  }

  Future<void> cancelDispute(String caseId, String reason) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'cancel_my_dispute',
          params: {'p_case_id': caseId, 'p_reason': reason.trim()},
        ));
    ref.invalidate(myDisputePortalProvider);
  }

  Future<void> appealDisputeDecision(String decisionId, String reason) async {
    await _withTimeout(ref
        .read(supabaseProvider)
        .rpc<dynamic>(
          'submit_dispute_appeal',
          params: {'p_decision_id': decisionId, 'p_reason': reason.trim()},
        ));
    ref.invalidate(myDisputePortalProvider);
  }
}

