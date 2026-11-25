part of '../monthly_attendance_statement_page.dart';

class _RetroactiveDayChangeSheet extends StatefulWidget {
  const _RetroactiveDayChangeSheet({
    required this.dateStr,
    required this.dayNameAr,
    required this.currentStatus,
    this.isClinicStaff = false,
  });
  final String dateStr;
  final String dayNameAr;
  final String currentStatus;
  final bool isClinicStaff;

  @override
  State<_RetroactiveDayChangeSheet> createState() =>
      _RetroactiveDayChangeSheetState();
}

class _RetroactiveDayChangeSheetState
    extends State<_RetroactiveDayChangeSheet> {
  String _category = 'leave';
  String _leaveType = 'casual';
  final _locationCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _locationCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  List<({Color color, IconData icon, String id, String label})>
  get _categories => [
    (
      id: 'leave',
      label: 'إجازة معتمدة',
      icon: Icons.beach_access_rounded,
      color: const Color(0xFF4F46E5),
    ),
    if (!widget.isClinicStaff) ...[
      (
        id: 'mission',
        label: 'مأمورية عمل',
        icon: Icons.directions_car_rounded,
        color: const Color(0xFF0EA5E9),
      ),
      (
        id: 'convoy',
        label: 'قافلة مساعدات (كامب)',
        icon: Icons.volunteer_activism_rounded,
        color: const Color(0xFF8B5CF6),
      ),
      (
        id: 'fundraising',
        label: 'يوم ترفيهي (فاندي)',
        icon: Icons.celebration_rounded,
        color: const Color(0xFFEC4899),
      ),
    ],
  ];

  static const _leaveOptions = [
    (
      id: 'casual',
      label: 'إجازة عارضة',
      badge: 'تنفيذ فوري',
      desc: 'تخصم مباشرة من رصيد الإجازات العارضة المتاح.',
      color: Color(0xFF0F9F6E),
    ),
    (
      id: 'annual',
      label: 'إجازة اعتيادية',
      badge: 'اعتماد المدير',
      desc: 'تخصم من رصيدك السنوي بعد موافقة المدير المباشر.',
      color: Color(0xFF6366F1),
    ),
    (
      id: 'weekly_rest_comp',
      label: 'بدل راحة',
      badge: 'اعتماد المدير',
      desc: 'تعويض عن يوم راحة أسبوعية عملت به سابقاً.',
      color: Color(0xFFF59E0B),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // مقبض السحب
          Center(
            child: Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: .3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // الرأس: العنوان وتاريخ اليوم والحالة الحالية
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5).withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.published_with_changes_rounded,
                  color: Color(0xFF4F46E5),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'تعديل حالة اليوم',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${widget.dayNameAr} ${widget.dateStr}',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: .5),
                  ),
                ),
                child: Text(
                  widget.currentStatus,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // تنبيه توضيحي
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF6366F1).withValues(alpha: 0.25),
              ),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Color(0xFF4F46E5), size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'متاح تعديل حالة هذا اليوم طالما يقع في نفس الشهر الحالي. سيتم رفع الطلب لمديرك المباشر لاعتماده.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF3730A3),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 1. اختيار الفئة
          Text(
            'الحالة الجديدة المطلوبة لهذا اليوم:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),

          // بطاقات الفئات الأربع
          Row(
            children: _categories.map((cat) {
              final isSelected = _category == cat.id;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _category = cat.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? cat.color.withValues(alpha: .15)
                          : scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? cat.color
                            : scheme.outlineVariant.withValues(alpha: .4),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          cat.icon,
                          size: 22,
                          color: isSelected
                              ? cat.color
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          cat.label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.w900
                                : FontWeight.w600,
                            color: isSelected
                                ? cat.color
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 16),

          // 2. إذا كانت الفئة إجازة: عرض خيارات الإجازة (عارضة / اعتيادية / بدل راحة)
          if (_category == 'leave') ...[
            Text(
              'نوع الإجازة المطلوبة:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            ..._leaveOptions.map((opt) {
              final isSelected = _leaveType == opt.id;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: isSelected
                      ? opt.color.withValues(alpha: .09)
                      : scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _leaveType = opt.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? opt.color
                              : scheme.outlineVariant.withValues(alpha: .3),
                          width: isSelected ? 1.8 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: isSelected
                                ? opt.color
                                : scheme.onSurfaceVariant,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      opt.label,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: isSelected
                                            ? opt.color
                                            : scheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: opt.color.withValues(alpha: .15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        opt.badge,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: opt.color,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  opt.desc,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],

          // 3. إذا كانت مأمورية أو قافلة أو فاندي ترفيهي: إدخال الوجهة / الموقع
          if (_category != 'leave') ...[
            TextFormField(
              controller: _locationCtrl,
              decoration: InputDecoration(
                labelText: switch (_category) {
                  'mission' => 'وجهة / موضوع المأمورية الخارجية',
                  'convoy' => 'مقر القافلة / القرية المستهدفة للمساعدات (كامب)',
                  'fundraising' =>
                    'مكان اليوم الترفيهي (اسم الفيلا / المنتجع / المكان)',
                  _ => 'الموقع / الوجهة',
                },
                hintText: switch (_category) {
                  'mission' => 'مثال: زيارة فرع، مأمورية عمل خارجية...',
                  'convoy' => 'مثال: قافلة مساعدات أسقف ومياه - قرى الفيوم...',
                  'fundraising' => 'مثال: فيلا سقارة / منتجع وادي النخيل...',
                  _ => 'اكتب المكان أو الوجهة...',
                },
                prefixIcon: Icon(switch (_category) {
                    'mission' => Icons.directions_car_rounded,
                    'convoy' => Icons.volunteer_activism_rounded,
                    'fundraising' => Icons.celebration_rounded,
                    _ => Icons.place_rounded,
                }, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
          ],

          const SizedBox(height: 6),

          // 4. حقل سبب التعديل (إلزامي)
          TextFormField(
            controller: _reasonCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'سبب التعديل أو الملاحظات (إلزامي)',
              hintText: 'وضح سبب طلب تعديل حالة هذا اليوم...',
              prefixIcon: const Icon(Icons.edit_note_rounded, size: 22),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // زر الإرسال
          FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: const Color(0xFF4F46E5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _submit,
            icon: const Icon(Icons.send_rounded, size: 20),
            label: const Text(
              'إرسال طلب التعديل للاعتماد',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

}
