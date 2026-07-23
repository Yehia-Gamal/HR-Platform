import 'package:flutter/material.dart';

class AppAvatar extends StatelessWidget {
  const AppAvatar({
    required this.name,
    this.photoUrl,
    this.radius = 22,
    this.announceName = true,
    super.key,
  });

  final String name;
  final String? photoUrl;
  final double radius;
  final bool announceName;

  String get _initial {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '؟' : String.fromCharCode(trimmed.runes.first);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final diameter = radius * 2;
    final fallback = ColoredBox(
      color: scheme.primaryContainer,
      child: Center(
        child: Text(
          _initial,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: scheme.onPrimaryContainer,
            fontSize: radius * .72,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
    final url = photoUrl?.trim();

    return Semantics(
      image: true,
      label: announceName ? 'الصورة الشخصية: $name' : null,
      excludeSemantics: true,
      child: ClipOval(
        child: SizedBox.square(
          dimension: diameter,
          child: url == null || url.isEmpty
              ? fallback
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  cacheWidth: (diameter * MediaQuery.devicePixelRatioOf(context))
                      .round(),
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => fallback,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        fallback,
                        Center(
                          child: SizedBox.square(
                            dimension: radius * .7,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              value: progress.expectedTotalBytes == null
                                  ? null
                                  : progress.cumulativeBytesLoaded /
                                      progress.expectedTotalBytes!,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }
}
