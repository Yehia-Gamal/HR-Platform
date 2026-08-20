import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';

/// بوابة صلاحيات مركزية للتحكم في ظهور العناصر أو حماية المسارات
class PermissionGate extends ConsumerWidget {
  const PermissionGate({
    super.key,
    required this.permission,
    required this.child,
    this.fallback,
    this.anyOf,
  });

  /// كود الصلاحية المطلوب (مثال: 'requests.request.decide')
  final String? permission;

  /// أو أي من هذه الصلاحيات
  final List<String>? anyOf;

  /// الويدجت التي تظهر في حال توفر الصلاحية
  final Widget child;

  /// الويدجت البديلة عند انعدام الصلاحية (افتراضياً فراغ)
  final Widget? fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(accessContextProvider).value;
    if (access == null) {
      return fallback ?? const SizedBox.shrink();
    }

    final hasPerm = permission != null && access.hasPermission(permission!);
    final hasAny = anyOf != null && access.hasAnyPermission(anyOf!);

    if (hasPerm || hasAny) {
      return child;
    }

    return fallback ??
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 48,
                  color: Colors.amber,
                ),
                const SizedBox(height: 12),
                const Text(
                  'غير مصرّح لك بالوصول إلى هذه الخاصية',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                if (permission != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'الصلاحية المطلوبة: $permission',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        );
  }
}
