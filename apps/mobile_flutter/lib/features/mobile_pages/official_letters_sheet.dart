import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/sharing/whatsapp_share_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

enum OfficialLetterType {
  missionAssignment,
  associationAffiliation,
  salaryCertificate,
}

extension OfficialLetterTypeExt on OfficialLetterType {
  String get title {
    switch (this) {
      case OfficialLetterType.missionAssignment:
        return 'خطاب تكليف بمأمورية وقافلة ميدانية';
      case OfficialLetterType.associationAffiliation:
        return 'إثبات انتساب وتصريح حركة ميداني';
      case OfficialLetterType.salaryCertificate:
        return 'شهادة تعريف بالراتب (HR Letter)';
    }
  }

  IconData get icon {
    switch (this) {
      case OfficialLetterType.missionAssignment:
        return Icons.explore_rounded;
      case OfficialLetterType.associationAffiliation:
        return Icons.verified_user_rounded;
      case OfficialLetterType.salaryCertificate:
        return Icons.description_rounded;
    }
  }
}

/// فتح نافذة إصدار ومطالعة الخطابات والتكليفات الرسمية المعتمدة
Future<void> showOfficialLettersSheet(
  BuildContext context, {
  MobileProfile? profile,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => OfficialLettersSheet(profile: profile),
  );
}

class OfficialLettersSheet extends ConsumerStatefulWidget {
  const OfficialLettersSheet({this.profile, super.key});

  final MobileProfile? profile;

  @override
  ConsumerState<OfficialLettersSheet> createState() =>
      _OfficialLettersSheetState();
}

class _OfficialLettersSheetState extends ConsumerState<OfficialLettersSheet> {
  OfficialLetterType _selectedType = OfficialLetterType.missionAssignment;

  late TextEditingController _missionTitleController;
  late TextEditingController _missionDestinationController;
  late TextEditingController _recipientController;
  late TextEditingController _affiliationPurposeController;

  late String _serialNo;
  late String _issueDate;

  @override
  void initState() {
    super.initState();
    _missionTitleController = TextEditingController(
      text: 'قافلة ستر ودفا وإغاثة القرى الأكثر احتياجاً',
    );
    _missionDestinationController = TextEditingController(
      text: 'محافظة الجيزة — قرى مركز أطفيح',
    );
    _recipientController = TextEditingController(
      text: 'السادة / الأجهزة التنفيذية ولجان التنسيق الميداني',
    );
    _affiliationPurposeController = TextEditingController(
      text: 'تسهيل مهمة العمل الميداني والتعامل مع الجهات المعنية نيابة عن الجمعية',
    );

    final now = DateTime.now();
    _serialNo = 'DOC-${now.year}-${now.month.toString().padLeft(2, '0')}-${1000 + (now.millisecondsSinceEpoch % 9000)}';
    _issueDate = DateFormat('yyyy-MM-dd').format(now);
  }

  @override
  void dispose() {
    _missionTitleController.dispose();
    _missionDestinationController.dispose();
    _recipientController.dispose();
    _affiliationPurposeController.dispose();
    super.dispose();
  }

  String _buildLetterText(MobileProfile emp) {
    final buffer = StringBuffer();
    buffer.writeln('مؤسسة أحلى شباب للتنمية والتشغيل');
    buffer.writeln('إدارة الموارد البشرية والعمليات المركزية');
    buffer.writeln('الرقم المرجعي: $_serialNo | التاريخ: $_issueDate');
    buffer.writeln('----------------------------------------');
    buffer.writeln(_selectedType.title);
    buffer.writeln('----------------------------------------');
    buffer.writeln('السادة / ${_recipientController.text.trim()} المحترمين،');
    buffer.writeln('تحية طيبة وبعد،،،');
    buffer.writeln();

    switch (_selectedType) {
      case OfficialLetterType.missionAssignment:
        buffer.writeln(
          'تفيد إدارة الموارد البشرية والعمليات المركزية بجمعية أحلى شباب بأن السيد/ ${emp.fullNameAr} '
          '(الكود: ${emp.employeeCode}، الوظيفة: ${emp.jobTitle ?? "أخصائي ميداني"} بـ ${emp.department ?? "العمليات"})، '
          'قد تم تكليفه رسمياً بالإشراف وتنفيذ المأمورية الميدانية التالية:',
        );
        buffer.writeln('• مسمى المأمورية: ${_missionTitleController.text.trim()}');
        buffer.writeln('• النطاق والوجهة: ${_missionDestinationController.text.trim()}');
        buffer.writeln('• تاريخ التكليف: $_issueDate');
        buffer.writeln();
        buffer.writeln(
          'برجاء من كافة الأجهزة المعنية ونقاط التفتيش تقديم التسهيلات اللازمة لتيسير مهمة فريق الإغاثة.',
        );
        break;

      case OfficialLetterType.associationAffiliation:
        buffer.writeln(
          'تشهد جمعية أحلى شباب بأن السيد/ ${emp.fullNameAr} '
          '(الكود: ${emp.employeeCode}، الوظيفة: ${emp.jobTitle ?? "أخصائي ميداني"})، '
          'هو أحد منسوبي الجمعية المعتمدين والمصرح لهم رسمياً بالتمثيل والتحرك الميداني.',
        );
        buffer.writeln('• غرض التصريح: ${_affiliationPurposeController.text.trim()}');
        buffer.writeln();
        buffer.writeln(
          'صدرت هذه الإفادة الرسمية بناءً على طلبه وهي سارية وصالحة للاستخدام أمام كافة الجهات الشريكة والحكومية.',
        );
        break;

      case OfficialLetterType.salaryCertificate:
        buffer.writeln(
          'تشهد جمعية أحلى شباب بأن السيد/ ${emp.fullNameAr} '
          '(الكود: ${emp.employeeCode})، يعمل لدينا بوظيفة (${emp.jobTitle ?? "موظف"}) '
          'بـ (${emp.department ?? "الإدارة العامة"})، ولا يزال على رأس عمله حتى تاريخه.',
        );
        buffer.writeln(
          'وقد أُعطيت له هذه الشهادة بناءً على طلبه دون أدنى مسؤولية مالية على الجمعية تجاه الغير.',
        );
        break;
    }

    buffer.writeln();
    buffer.writeln('ختم الجمعية الرقمي: معتمد وموثق برمز QR');
    buffer.writeln('المرجع: $_serialNo');
    return buffer.toString();
  }

  void _copyToClipboard(MobileProfile emp) {
    Clipboard.setData(ClipboardData(text: _buildLetterText(emp)));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ نص الخطاب الرسمي إلى الحافظة بنجاح'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _shareViaWhatsApp(MobileProfile emp) {
    String? details;
    if (_selectedType == OfficialLetterType.missionAssignment) {
      details = '${_missionTitleController.text.trim()} — ${_missionDestinationController.text.trim()}';
    } else if (_selectedType == OfficialLetterType.associationAffiliation) {
      details = _affiliationPurposeController.text.trim();
    }

    WhatsAppShareService.shareOfficialLetter(
      employeeName: emp.fullNameAr,
      docTitle: _selectedType.title,
      serialNo: _serialNo,
      recipient: _recipientController.text.trim(),
      details: details,
      phone: emp.phoneE164,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final profileAsync = ref.watch(mobileProfileProvider);

    final emp = widget.profile ??
        profileAsync.asData?.value ??
        const MobileProfile(
          id: 'preview',
          employeeCode: 'EMP-01042',
          fullNameAr: 'أحمد محمد إبراهيم',
          fullNameEn: 'Ahmed Mohamed',
          phoneE164: null,
          photoUrl: null,
          status: 'active',
          hireDate: null,
          contractEnd: null,
          jobTitle: 'أخصائي أول عمليات ميدانية',
          position: null,
          grade: null,
          department: 'إدارة العمليات واللوجستيات',
          team: null,
          branch: 'المقر الرئيسي',
          workSite: null,
          managerName: null,
          documents: [],
          assets: [],
        );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .3),
              blurRadius: 20,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: Column(
          children: [
            // Grab Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),

            // Header Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.brandPrimary.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.verified_rounded,
                      color: AppColors.brandPrimary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'الخطابات والتكليفات الرسمية المعتمدة',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'توليد وثائق رسمية فورية بختم الجمعية وكود التحقق الذكي QR',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'إغلاق',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Content Scroll
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  // Type Selector Tabs
                  const Text(
                    'اختر نوع الوثيقة المطلوبة:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: OfficialLetterType.values.map((type) {
                        final isSelected = _selectedType == type;
                        return Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: ChoiceChip(
                            avatar: Icon(
                              type.icon,
                              size: 16,
                              color: isSelected ? Colors.white : AppColors.brandPrimary,
                            ),
                            label: Text(type.title),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() {
                                  _selectedType = type;
                                  if (type == OfficialLetterType.missionAssignment) {
                                    _recipientController.text =
                                        'السادة / الأجهزة التنفيذية ولجان التنسيق الميداني';
                                  } else {
                                    _recipientController.text = 'إلى من يهمه الأمر';
                                  }
                                });
                              }
                            },
                            selectedColor: AppColors.brandPrimary,
                            labelStyle: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Configurable Fields Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: .04) : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? Colors.white12 : Colors.grey.shade200,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'بيانات وتخصيص الوثيقة:',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _recipientController,
                          decoration: InputDecoration(
                            labelText: 'الجهة الموجه إليها الخطاب',
                            labelStyle: const TextStyle(fontSize: 11),
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          style: const TextStyle(fontSize: 12),
                        ),
                        if (_selectedType == OfficialLetterType.missionAssignment) ...[
                          const SizedBox(height: 10),
                          TextField(
                            controller: _missionTitleController,
                            decoration: InputDecoration(
                              labelText: 'مسمى المأمورية / القافلة الإغاثية',
                              labelStyle: const TextStyle(fontSize: 11),
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _missionDestinationController,
                            decoration: InputDecoration(
                              labelText: 'النطاق الجغرافي والوجهة الميدانية',
                              labelStyle: const TextStyle(fontSize: 11),
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                        if (_selectedType == OfficialLetterType.associationAffiliation) ...[
                          const SizedBox(height: 10),
                          TextField(
                            controller: _affiliationPurposeController,
                            maxLines: 2,
                            decoration: InputDecoration(
                              labelText: 'غرض التصريح والتفويض الميداني',
                              labelStyle: const TextStyle(fontSize: 11),
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Official Printable Preview Document Card
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.grey.shade300, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .08),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Letterhead
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'مؤسسة أحلى شباب للتنمية والتشغيل',
                                  style: TextStyle(
                                    color: Color(0xFF0F172A),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'إدارة الموارد البشرية والعمليات المركزية',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: const Color(0xFF0F172A), width: 1.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'OFFICIAL',
                                    style: TextStyle(
                                      color: Color(0xFF0F172A),
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _serialNo,
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                Text(
                                  _issueDate,
                                  style: const TextStyle(color: Colors.black45, fontSize: 8),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const Divider(color: Color(0xFF0F172A), thickness: 1.5, height: 22),

                        // Title
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _selectedType.title,
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Salutation
                        Text(
                          'السادة / ${_recipientController.text.trim()} المحترمين،',
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'تحية طيبة وبعد،،،',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
                        ),
                        const SizedBox(height: 10),

                        // Body text based on type
                        if (_selectedType == OfficialLetterType.missionAssignment) ...[
                          Text(
                            'تفيد إدارة الموارد البشرية والعمليات بجمعية أحلى شباب للتنمية بأن السيد/ ${emp.fullNameAr} (الكود الوظيفي: ${emp.employeeCode})، والذي يشغل وظيفة ${emp.jobTitle ?? "أخصائي ميداني"} بـ ${emp.department ?? "العمليات واللوجستيات"}، قد تم تكليفه رسمياً بتنفيذ ومتابعة القافلة الميدانية:',
                            style: const TextStyle(color: Color(0xFF1E293B), fontSize: 11, height: 1.6),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text('• مسمى القافلة: ', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.black87)),
                                    Expanded(
                                      child: Text(
                                        _missionTitleController.text.trim(),
                                        style: const TextStyle(fontSize: 10.5, color: AppColors.brandPrimary, fontWeight: FontWeight.w900),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Text('• النطاق والوجهة: ', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.black87)),
                                    Expanded(
                                      child: Text(
                                        _missionDestinationController.text.trim(),
                                        style: const TextStyle(fontSize: 10.5, color: Colors.black87, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'نرجو من سيادتكم ومن كافة الجهات المعنية تقديم كافة التسهيلات اللوجستية وتيسير مهام حركة القافلة وفريق العمل الإنساني بالقرى المستهدفة.',
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 10, height: 1.5),
                          ),
                        ] else if (_selectedType == OfficialLetterType.associationAffiliation) ...[
                          Text(
                            'تشهد جمعية أحلى شباب للتنمية بأن السيد/ ${emp.fullNameAr} (الكود الوظيفي: ${emp.employeeCode})، هو أحد منسوبي الجمعية المعتمدين، ويعمل لدينا بصفة منتظمة بوظيفة ${emp.jobTitle ?? "أخصائي ميداني"} بـ ${emp.department ?? "الإدارة العامة"}.',
                            style: const TextStyle(color: Color(0xFF1E293B), fontSize: 11, height: 1.6),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('بيان التفويض: ', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.black87)),
                                Expanded(
                                  child: Text(
                                    '«${_affiliationPurposeController.text.trim()}»',
                                    style: const TextStyle(fontSize: 10.5, color: AppColors.brandPrimary, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'أُعطيت له هذه الإفادة الرسمية لتيسير مهمته وإثبات انتسابه القانوني والتنظيمي دون تحمل الجمعية أي التزامات مالية فردية.',
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 10, height: 1.5),
                          ),
                        ] else ...[
                          Text(
                            'تشهد جمعية أحلى شباب للتنمية بأن السيد/ ${emp.fullNameAr} (الكود الوظيفي: ${emp.employeeCode})، يعمل لدينا بصفة منتظمة بوظيفة ${emp.jobTitle ?? "موظف"} بـ ${emp.department ?? "الإدارة العامة"}، ولا يزال على رأس عمله حتى تاريخه.',
                            style: const TextStyle(color: Color(0xFF1E293B), fontSize: 11, height: 1.6),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'وقد أُعطيت له هذه الشهادة بناءً على طلبه دون أدنى مسؤولية مالية على الجمعية تجاه الغير.',
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 10, height: 1.5),
                          ),
                        ],

                        const SizedBox(height: 16),

                        // Smart QR Verification Badge
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              // Simulated QR Matrix
                              Container(
                                width: 44,
                                height: 44,
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.grey.shade400),
                                ),
                                child: CustomPaint(
                                  painter: _QrMatrixPainter(),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.shield_outlined, size: 12, color: Color(0xFF10B981)),
                                        SizedBox(width: 4),
                                        Text(
                                          'رمز التحقق الذكي المعتمد (Smart QR)',
                                          style: TextStyle(
                                            color: Color(0xFF0F172A),
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Ref: $_serialNo | Ahla Shabab Verified',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 8.5,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Seals and signatures row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Employee signature
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'الموظف المكلف',
                                  style: TextStyle(color: Colors.black54, fontSize: 8.5, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  emp.fullNameAr,
                                  style: const TextStyle(color: Color(0xFF0F172A), fontSize: 9.5, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),

                            // Digital Seal Badge
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF1E3A8A).withValues(alpha: .6),
                                  width: 1.5,
                                ),
                                color: const Color(0xFF1E3A8A).withValues(alpha: .06),
                              ),
                              child: const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'جمعية أحلى شباب',
                                    style: TextStyle(
                                      color: Color(0xFF1E3A8A),
                                      fontSize: 6.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    'SEAL & VERIFIED',
                                    style: TextStyle(
                                      color: Color(0xFF1E3A8A),
                                      fontSize: 5.5,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // HR Approval
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text(
                                  'اعتماد العمليات والموارد البشرية',
                                  style: TextStyle(color: Colors.black54, fontSize: 8.5, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'HR Operations Approval',
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: 8.5,
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Action Buttons Row
                  Row(
                    children: [
                      // WhatsApp Share Button
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _shareViaWhatsApp(emp),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.share_rounded, size: 18),
                          label: const Text(
                            'مشاركة إشعار (WhatsApp)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Copy text button
                      OutlinedButton.icon(
                        onPressed: () => _copyToClipboard(emp),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text(
                          'نسخ النص',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// رسم نمط كود QR دقيق ومحاكى للمعاينة
class _QrMatrixPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;

    // Corner Finder Patterns
    // Top-left
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width * 0.32, size.height * 0.32), paint);
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.08, size.height * 0.08, size.width * 0.16, size.height * 0.16),
      Paint()..color = Colors.white,
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.12, size.height * 0.12, size.width * 0.08, size.height * 0.08),
      paint,
    );

    // Top-right
    canvas.drawRect(Rect.fromLTWH(size.width * 0.68, 0, size.width * 0.32, size.height * 0.32), paint);
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.76, size.height * 0.08, size.width * 0.16, size.height * 0.16),
      Paint()..color = Colors.white,
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.80, size.height * 0.12, size.width * 0.08, size.height * 0.08),
      paint,
    );

    // Bottom-left
    canvas.drawRect(Rect.fromLTWH(0, size.height * 0.68, size.width * 0.32, size.height * 0.32), paint);
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.08, size.height * 0.76, size.width * 0.16, size.height * 0.16),
      Paint()..color = Colors.white,
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.12, size.height * 0.80, size.width * 0.08, size.height * 0.08),
      paint,
    );

    // Inner data matrix dots
    final step = size.width / 8;
    canvas.drawRect(Rect.fromLTWH(step * 4, step * 1, step * 0.8, step * 0.8), paint);
    canvas.drawRect(Rect.fromLTWH(step * 3.5, step * 3.5, step * 1.5, step * 1.5), paint);
    canvas.drawRect(Rect.fromLTWH(step * 5, step * 4, step * 0.8, step * 0.8), paint);
    canvas.drawRect(Rect.fromLTWH(step * 4, step * 6, step * 0.8, step * 0.8), paint);
    canvas.drawRect(Rect.fromLTWH(step * 6, step * 6, step * 1.2, step * 0.8), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
