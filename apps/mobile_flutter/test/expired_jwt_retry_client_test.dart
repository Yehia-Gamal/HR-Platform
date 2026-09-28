import 'dart:convert';

import 'package:ahla_shabab_management_os/core/network/expired_jwt_retry_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// ساعة جهاز متأخرة: المكتبة ترسل رمزاً منتهياً على الخادم فيرجع 401 PGRST303.
// العميل يجب أن يجدّد مرة واحدة ويعيد الطلب نفسه بجسمه — ولا يلمس غير ذلك.
const _expiredBody =
    '{"code":"PGRST303","details":null,"hint":null,"message":"JWT expired"}';

void main() {
  late List<http.Request> sent;
  late int refreshes;
  String? current;

  ExpiredJwtRetryClient build(
    http.Response Function(http.Request) handler, {
    String? refreshed = 'fresh',
  }) {
    sent = [];
    refreshes = 0;
    return ExpiredJwtRetryClient(
      inner: MockClient((request) async {
        sent.add(request);
        return handler(request);
      }),
      currentAccessToken: () => current,
      refreshAccessToken: () async {
        refreshes++;
        current = refreshed;
        return refreshed;
      },
    );
  }

  http.Response expiredUnlessFresh(http.Request r) =>
      r.headers['Authorization'] == 'Bearer fresh'
      ? http.Response('[]', 200)
      : http.Response(_expiredBody, 401);

  setUp(() => current = 'stale');

  test('يجدد الجلسة ويعيد طلب RPC بنفس الجسم عند JWT expired', () async {
    final client = build(expiredUnlessFresh);
    final res = await client.post(
      Uri.parse('https://x.supabase.co/rest/v1/rpc/get_honor_board'),
      headers: {'Authorization': 'Bearer stale'},
      body: jsonEncode({'p_period': 'month'}),
    );
    expect(res.statusCode, 200);
    expect(refreshes, 1);
    expect(sent, hasLength(2));
    expect(sent.last.body, '{"p_period":"month"}');
  });

  test('لا يجدد ثانيةً إن جُدّدت الجلسة بطلب موازٍ', () async {
    final client = build(expiredUnlessFresh);
    current = 'fresh';
    final res = await client.post(
      Uri.parse('https://x.supabase.co/rest/v1/rpc/get_my_notifications'),
      headers: {'Authorization': 'Bearer stale'},
    );
    expect(res.statusCode, 200);
    expect(refreshes, 0);
  });

  test('401 صلاحيات (42501) لا يُعاد ويصل جسمه كما هو', () async {
    const denied =
        '{"code":"42501","message":"permission denied for function x"}';
    final client = build((_) => http.Response(denied, 401));
    final res = await client.post(
      Uri.parse('https://x.supabase.co/rest/v1/rpc/x'),
      headers: {'Authorization': 'Bearer stale'},
    );
    expect(res.statusCode, 401);
    expect(res.body, denied);
    expect(refreshes, 0);
    expect(sent, hasLength(1));
  });

  test('طلبات /auth/v1/ تمر دون تجديد (التجديد نفسه يمر من هنا)', () async {
    final client = build((_) => http.Response(_expiredBody, 401));
    final res = await client.post(
      Uri.parse('https://x.supabase.co/auth/v1/token?grant_type=refresh_token'),
    );
    expect(res.statusCode, 401);
    expect(refreshes, 0);
  });

  test('فشل التجديد يعيد الاستجابة الأصلية دون حلقة', () async {
    final client = build(expiredUnlessFresh, refreshed: null);
    final res = await client.post(
      Uri.parse('https://x.supabase.co/rest/v1/rpc/get_honor_board'),
      headers: {'Authorization': 'Bearer stale'},
    );
    expect(res.statusCode, 401);
    expect(res.body, _expiredBody);
    expect(refreshes, 1);
    expect(sent, hasLength(1));
  });
}
