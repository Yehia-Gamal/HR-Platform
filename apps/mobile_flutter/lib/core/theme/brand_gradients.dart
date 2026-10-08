import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:flutter/material.dart';

/// تدرّجات البطاقات البارزة ذات النص الأبيض (بطاقة الترحيب، بطاقة الهوية،
/// رؤوس التقارير…) — ثابتة في الوضعين الفاتح والداكن.
///
/// كانت تُبنى من `scheme.primary`/`scheme.secondary`، وهما في الوضع الداكن
/// فاتحان (#8AB9FF / #5BD6FF) فيضيع النص الأبيض فوقهما ويتحوّل ظل البطاقة إلى
/// شريط أزرق فاتح أسفلها.
abstract final class BrandGradients {
  /// أزرق العلامة العميق ← أزرق مخضرّ (تباين النص الأبيض ≥ 4.4:1 حتى الطرف).
  static const List<Color> hero = [
    AppColors.brandPrimaryStrong,
    AppColors.brandPrimary,
    Color(0xFF0680BE),
  ];

  /// ظل البطاقة البارزة — عميق في الوضعين بدل توهّج فاتح في الداكن.
  static List<BoxShadow> heroShadow({double alpha = .25}) => [
    BoxShadow(
      color: AppColors.brandPrimaryStrong.withValues(alpha: alpha),
      blurRadius: 24,
      offset: const Offset(0, 10),
    ),
  ];
}
