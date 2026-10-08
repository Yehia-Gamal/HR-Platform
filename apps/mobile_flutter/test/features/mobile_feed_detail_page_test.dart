import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_feed_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final testFeedItemMap = {
    'id': 'ann-1',
    'kind': 'announcement',
    'title': 'تنبيه هام بخصوص دوام الخميس',
    'body': 'تنبيه هام بخصوص دوام الخميس\nنحيطكم علماً بأن الدوام سينتهي في تمام الساعة 2:00 ظهراً.',
    'priority': 'urgent',
    'status': 'published',
    'publishedAt': '2026-10-05T08:00:00Z',
    'imageUrl': null,
    'viewCount': 3,
    'reactionCount': 2,
    'myReaction': 'like',
    'reactionSummary': {'like': 2},
    'requiresAcknowledgement': true,
    'myAcknowledged': false,
  };

  final testEngagementData = {
    'announcementId': 'ann-1',
    'viewerCount': 3,
    'reactionCount': 2,
    'acknowledgedCount': 1,
    'viewers': [
      {
        'employeeId': 'emp-1',
        'name': 'يحيى جمال السبع',
        'photoUrl': null,
        'at': '2026-10-05T09:33:00Z',
        'viewCount': 1,
      },
    ],
    'reactions': [
      {
        'employeeId': 'emp-1',
        'name': 'يحيى جمال السبع',
        'photoUrl': null,
        'reactionType': 'like',
        'at': '2026-10-05T09:35:00Z',
      },
    ],
    'acknowledgements': [
      {
        'employeeId': 'emp-1',
        'name': 'يحيى جمال السبع',
        'photoUrl': null,
        'at': '2026-10-05T09:34:00Z',
      },
    ],
  };

  Widget buildTestApp({bool acknowledged = false}) {
    final item = MobileFeedItem.fromJson({
      ...testFeedItemMap,
      'myAcknowledged': acknowledged,
    });

    return ProviderScope(
      overrides: [
        mobileFeedDetailProvider((kind: 'announcement', id: 'ann-1'))
            .overrideWith((ref) async => item),
        announcementEngagementProvider('ann-1')
            .overrideWith((ref) async => testEngagementData),
      ],
      child: const MaterialApp(
        locale: Locale('ar'),
        supportedLocales: [Locale('ar'), Locale('en')],
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MobileFeedDetailPage(kind: 'announcement', itemId: 'ann-1'),
      ),
    );
  }

  testWidgets('renders announcement with deduplicated body, 4 reaction buttons, and unacknowledged card',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildTestApp(acknowledged: false));
    await tester.pumpAndSettle();

    // 1. Verify AppBar title
    expect(find.text('الخبر الرسمي'), findsOneWidget);

    // 2. Verify title and deduplicated body
    expect(find.text('تنبيه هام بخصوص دوام الخميس'), findsOneWidget);
    expect(
      find.text('نحيطكم علماً بأن الدوام سينتهي في تمام الساعة 2:00 ظهراً.'),
      findsOneWidget,
    );

    // 3. Verify acknowledgment requirement card
    expect(find.text('مطلوب إقرار إداري إلزامي'), findsOneWidget);
    expect(find.text('أقر بالاطلاع والعلم بهذا الإعلان'), findsOneWidget);

    // 4. Verify 4 balanced reaction buttons
    expect(find.text('أعجبني'), findsOneWidget);
    expect(find.text('احتفال'), findsOneWidget);
    expect(find.text('دعم'), findsOneWidget);
    expect(find.text('مفيد'), findsOneWidget);

    // 5. Verify stats chips and engagement button
    expect(find.text('3 مشاهدة'), findsOneWidget);
    expect(find.text('2 تفاعل'), findsOneWidget);
    expect(find.text('من شاهد وتفاعل؟'), findsOneWidget);
  });

  testWidgets('shows success card when user already acknowledged', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildTestApp(acknowledged: true));
    await tester.pumpAndSettle();

    expect(find.text('تم تسجيل إقرارك بالاطلاع والعلم ✓'), findsOneWidget);
    expect(find.text('أقر بالاطلاع والعلم بهذا الإعلان'), findsNothing);
  });

  testWidgets('opens engagement bottom sheet with tabs and person rows',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    // Tap "من شاهد وتفاعل؟"
    await tester.tap(find.text('من شاهد وتفاعل؟'));
    await tester.pumpAndSettle();

    // Verify bottom sheet title and tabs
    expect(find.text('تفاعل ومشاهدات الإعلان'), findsOneWidget);
    expect(find.text('المشاهدات (3)'), findsOneWidget);
    expect(find.text('التفاعلات (2)'), findsOneWidget);
    expect(find.text('الإقرارات (1)'), findsOneWidget);

    // Default tab is viewers
    expect(find.text('يحيى جمال السبع'), findsOneWidget);
    expect(find.textContaining('شاهد في'), findsOneWidget);

    // Switch to reactions tab
    await tester.tap(find.text('التفاعلات (2)'));
    await tester.pumpAndSettle();

    expect(find.textContaining('أعجبني'), findsWidgets);

    // Switch to acknowledgements tab
    await tester.tap(find.text('الإقرارات (1)'));
    await tester.pumpAndSettle();

    expect(find.textContaining('أقر بالعلم في'), findsOneWidget);
  });
}
