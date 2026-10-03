import 'package:flutter/widgets.dart';

/// يعلن أن سلفًا في الشجرة يعرض شريط العنوان بالفعل — رأس المساحة
/// (`WorkspaceScaffold`) أو `MobileSubpage` — فالصفحة المضمّنة تحته لا تضيف
/// شريطًا ثانيًا فوق محتواها (كان تبويب «الحضور» مثلًا يعرض شريطين متراكبين).
///
/// المسارات المفتوحة بـ Navigator تُبنى خارج هذا النطاق، فالصفحة نفسها حين
/// تُفتح منفردة تعرض شريطها وزر الرجوع كالمعتاد.
class HostAppBarScope extends InheritedWidget {
  const HostAppBarScope({required super.child, super.key});

  /// هل يعرض سلفٌ شريط العنوان؟ عندها تُسقط الصفحة شريطها.
  static bool isActive(BuildContext context) =>
      context.getInheritedWidgetOfExactType<HostAppBarScope>() != null;

  @override
  bool updateShouldNotify(HostAppBarScope oldWidget) => false;
}
