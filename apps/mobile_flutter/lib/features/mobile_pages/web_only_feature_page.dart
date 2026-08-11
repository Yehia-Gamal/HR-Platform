import 'package:ahla_shabab_management_os/core/network/session_cleanup.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// عنوان لوحة الويب الافتراضي للوصول إلى الميزات الإدارية المحذوفة من الجوال.
const String _kWebDashboardUrl = 'https://hr.ahlashabab.com/admin';

/// صفحة "ميزة ويب فقط" — تُعرض عندما يحاول مدير/مسؤول الوصول إلى ميزة
/// إدارية (إدارة فريقي، إدارة التشغيل، ملفات أعضاء الفريق) لم تعد متاحة
/// على الجوال وانتقلت إلى لوحة الويب. تُظهر للمستخدم رسالة واضحة توجهه
/// لاستخدام لوحة التحكم على المتصفح بدلًا من ذلك.
class WebOnlyFeaturePage extends ConsumerWidget {
  const WebOnlyFeaturePage({required this.featureName, super.key});

  /// اسم الميزة التي حاول المستخدم الوصول إليها (يُعرض داخل الرسالة).
  final String featureName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(featureName)),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
                      Icons.desktop_windows,
                      size: 48,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'هذه الميزة متاحة على لوحة الويب',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'يمكنك الوصول إلى $featureName من لوحة التحكم على المتصفح',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.8,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.link_rounded,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _kWebDashboardUrl,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await cleanupOnSignOut();
                      await ref.read(supabaseProvider).auth.signOut();
                      ref.invalidate(accessContextProvider);
                    },
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('تسجيل الخروج'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('العودة'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
