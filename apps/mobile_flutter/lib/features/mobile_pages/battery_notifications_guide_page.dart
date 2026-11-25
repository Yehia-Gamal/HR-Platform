import 'dart:io' show Platform;

import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/push_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

enum DeviceVendorGroup {
  xiaomi('شاومي / ريدمي / بوكو (MIUI / HyperOS)', [
    'افتح إعدادات الهاتف ← التطبيقات ← إدارة التطبيقات ← أحلى شباب.',
    'فعّل خيار «التشغيل التلقائي (Autostart)» في الخلفية.',
    'ادخل إلى «موفر البطارية (Battery saver)» واختر «لا قيود (No restrictions)».',
    'من «الإشعارات»، فعّل الإشعارات العائمة وشاشة القفل والصوت لطلبات الموقع.',
  ]),
  samsung('سامسونج (One UI)', [
    'افتح الضبط ← التطبيقات ← أحلى شباب ← البطارية.',
    'اختر «غير مقيد (Unrestricted)» بدلاً من «محسّن».',
    'تأكد من عدم وجود التطبيق في «التطبيقات النائمة أو العميقة النوم» داخل العناية بالجهاز.',
    'من «الإشعارات»، تأكد من تفعيل فئات الإشعارات العاجلة والشاملة.',
  ]),
  oppo('أوبو / ريلمي / ون بلس (ColorOS)', [
    'افتح الإعدادات ← إدارة التطبيقات ← أحلى شباب ← استخدام البطارية.',
    'فعّل «السماح بنشاط الخلفية (Allow background activity)» و«التشغيل التلقائي».',
    'عطّل تحسين البطارية للتطبيق من إعدادات البطارية الإضافية.',
    'اقفل بطاقة التطبيق في شاشة التطبيقات الأخيرة إذا احتجت بقاءه نشطاً.',
  ]),
  huawei('هواوي / هونر (EMUI / MagicOS)', [
    'افتح الإعدادات ← البطارية ← تشغيل التطبيقات (App launch).',
    'ابحث عن «أحلى شباب» وحوّل الوضع من تلقائي إلى «إدارة يدوياً».',
    'فعّل الثلاثة خيارات: التشغيل التلقائي، التشغيل الثانوي، والتشغيل في الخلفية.',
  ]),
  generic('أندرويد العام (Google Pixel / Nokia / وغيرها)', [
    'افتح الإعدادات ← التطبيقات ← أحلى شباب ← البطارية.',
    'اختر «غير مقيد (Unrestricted)» لضمان وصول إشعارات الموقع في الخلفية.',
    'تأكد من السماح بالبيانات في الخلفية وعدم تفعيل «توفير البيانات» على التطبيق.',
  ]);

  const DeviceVendorGroup(this.label, this.steps);
  final String label;
  final List<String> steps;

  static DeviceVendorGroup detectFromManufacturer(String manufacturer) {
    final m = manufacturer.toLowerCase();
    if (m.contains('xiaomi') || m.contains('redmi') || m.contains('poco')) {
      return DeviceVendorGroup.xiaomi;
    }
    if (m.contains('samsung')) return DeviceVendorGroup.samsung;
    if (m.contains('oppo') || m.contains('realme') || m.contains('oneplus') || m.contains('vivo')) {
      return DeviceVendorGroup.oppo;
    }
    if (m.contains('huawei') || m.contains('honor')) return DeviceVendorGroup.huawei;
    return DeviceVendorGroup.generic;
  }
}

/// دليل تفاعلي لضبط إعدادات البطارية والإشعارات حسب نوع هاتف الموظف.
class BatteryNotificationsGuidePage extends StatefulWidget {
  const BatteryNotificationsGuidePage({
    super.key,
    this.initialVendor,
  });

  final DeviceVendorGroup? initialVendor;

  @override
  State<BatteryNotificationsGuidePage> createState() =>
      _BatteryNotificationsGuidePageState();
}

class _BatteryNotificationsGuidePageState
    extends State<BatteryNotificationsGuidePage> with WidgetsBindingObserver {
  DeviceVendorGroup _selected = DeviceVendorGroup.generic;
  String? _detectedManufacturer;
  bool? _isExempt;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.initialVendor != null) {
      _selected = widget.initialVendor!;
    }
    _loadDeviceAndBatteryStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshExemption();
    }
  }

  Future<void> _loadDeviceAndBatteryStatus() async {
    var vendor = widget.initialVendor;
    String? brand;
    if (vendor == null && !kIsWeb && Platform.isAndroid) {
      try {
        final info = await DeviceInfoPlugin().androidInfo;
        brand = '${info.manufacturer} ${info.model}'.trim();
        vendor = DeviceVendorGroup.detectFromManufacturer(info.manufacturer);
      } catch (_) {
        vendor = DeviceVendorGroup.generic;
      }
    }
    final exempt = await PushService.isBatteryOptimizationExempt();
    if (!mounted) return;
    setState(() {
      _selected = vendor ?? DeviceVendorGroup.generic;
      _detectedManufacturer = brand;
      _isExempt = exempt;
      _loading = false;
    });
  }

  Future<void> _refreshExemption() async {
    final exempt = await PushService.isBatteryOptimizationExempt();
    if (!mounted) return;
    setState(() => _isExempt = exempt);
  }

  Future<void> _requestExemption() async {
    await PushService.requestBatteryOptimizationExemption();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _refreshExemption();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات البطارية والإشعارات')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            Semantics(
              liveRegion: true,
              child: Card(
                color: _isExempt == true
                    ? AppColors.statusSuccess.withValues(alpha: 0.1)
                    : scheme.secondaryContainer.withValues(alpha: 0.45),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _isExempt == true
                                ? Icons.battery_charging_full_rounded
                                : Icons.battery_alert_rounded,
                            color: _isExempt == true
                                ? AppColors.statusSuccess
                                : scheme.secondary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _loading
                                  ? 'جارٍ فحص حالة البطارية...'
                                  : _isExempt == true
                                      ? 'التطبيق معفى من قيود البطارية ✓'
                                      : _isExempt == false
                                          ? 'التطبيق مقيّد بتحسين البطارية'
                                          : 'إرشادات التشغيل في الخلفية',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_detectedManufacturer != null &&
                          _detectedManufacturer!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'نوع الهاتف المكتشف: $_detectedManufacturer',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      const Text(
                        'بعض الشركات تغلق التطبيقات في الخلفية فتتأخر إشعارات طلبات الموقع والقرارات العاجلة. اتبع الخطوات المناسبة لهاتفك لضمان وصول كل الإشعارات.',
                        style: TextStyle(fontSize: 13, height: 1.45),
                      ),
                      if (_isExempt != true && !kIsWeb) ...[
                        const SizedBox(height: 12),
                        Semantics(
                          button: true,
                          label: 'تفعيل استثناء البطارية للتطبيق',
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _requestExemption,
                              icon: const Icon(Icons.bolt_rounded),
                              label: const Text('استثناء التطبيق من قيود البطارية'),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: Text(
                'اختر الشركة المصنّعة لهاتفك:',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final vendor in DeviceVendorGroup.values)
                  ChoiceChip(
                    label: Text(vendor.label.split('(').first.trim()),
                    selected: _selected == vendor,
                    onSelected: (_) => setState(() => _selected = vendor),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selected.label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (var i = 0; i < _selected.steps.length; i++) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 13,
                            backgroundColor: scheme.primaryContainer,
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _selected.steps[i],
                              style: const TextStyle(fontSize: 13.5, height: 1.5),
                            ),
                          ),
                        ],
                      ),
                      if (i + 1 < _selected.steps.length)
                        const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
