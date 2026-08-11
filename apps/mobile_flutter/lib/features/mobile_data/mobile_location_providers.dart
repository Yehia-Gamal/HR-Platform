part of 'mobile_providers.dart';

final locationDirectoryProvider = FutureProvider.autoDispose
    .family<List<LocationDirectoryEmployee>, String>((ref, search) async {
      final data = await ref
          .watch(supabaseProvider)
          .rpc<dynamic>(
            'get_location_directory',
            params: {'p_search': search, 'p_limit': 100},
          )
          .timeout(const Duration(seconds: 15));
      return _asList(
        data,
      ).map(LocationDirectoryEmployee.fromJson).toList(growable: false);
    });
final myLocationRequestsProvider = FutureProvider<List<MobileLocationRequest>>((
  ref,
) async {
  final data = await ref
      .watch(supabaseProvider)
      .rpc<dynamic>('get_my_live_location_requests', params: {'p_limit': 30});
  return _asList(
    data,
  ).map(MobileLocationRequest.fromJson).toList(growable: false);
});

final locationRequestByIdProvider = FutureProvider.autoDispose
    .family<MobileLocationRequest, String>((ref, requestId) async {
      // جلب مباشر بالمعرّف بدل الاعتماد على قائمة آخر 100 طلب (للمستهدَف فقط).
      // get_live_location_request_by_id يسمح للمستهدَف والطالب وأصحاب الصلاحية
      // بفتح الطلب عبر deep link من الإشعار.
      final data = await ref
          .watch(supabaseProvider)
          .rpc<dynamic>(
            'get_live_location_request_by_id',
            params: {'p_request_id': requestId},
          )
          .timeout(const Duration(seconds: 15));
      return MobileLocationRequest.fromJson(_asMap(data));
    });

/// لوحة الحضور اليومي للمدير التنفيذي — تستدعي get_executive_attendance_today().
final executiveAttendanceTodayProvider =
    FutureProvider.autoDispose<List<AttendanceTodayEmployee>>((ref) async {
      final data = await ref
          .watch(supabaseProvider)
          .rpc<dynamic>('get_executive_attendance_today')
          .timeout(const Duration(seconds: 15));
      return _asList(
        data,
      ).map(AttendanceTodayEmployee.fromJson).toList(growable: false);
    });

/// يستطلع طلبات الموقع المعلقة للمستخدم الحالي كل 15 ثانية.
/// يُستخدم بواسطة [LocationIncomingListener] لعرض الشاشة المنبثقة عند ورود طلب.
/// ref.read بدلاً من ref.watch: لا يجب إعادة بناء المزوّد عند تغيّر supabaseProvider
/// من داخل async* (الـ watch لا يعمل كما هو متوقع بعد نقاط التعليق).
final pendingIncomingLocationRequestProvider =
    StreamProvider.autoDispose<MobileLocationRequest?>((ref) async* {
      final supabase = ref.read(supabaseProvider);
      while (true) {
        try {
          final data = await supabase.rpc<dynamic>(
            'get_my_live_location_requests',
            params: {'p_limit': 10},
          );
          final all = _asList(
            data,
          ).map(MobileLocationRequest.fromJson).toList();
          final pending = all.where((r) => r.status == 'pending').toList();
          yield pending.isEmpty ? null : pending.first;
        } catch (e) {
          if (kDebugMode) debugPrint('pendingLocationRequest poll failed: $e');
          yield null;
        }
        await Future<void>.delayed(const Duration(seconds: 15));
      }
    });

