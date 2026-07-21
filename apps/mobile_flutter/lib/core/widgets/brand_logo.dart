import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:flutter/material.dart';

class BrandLogo extends StatelessWidget {
  const BrandLogo({
    this.inverse = false,
    this.compact = false,
    this.markSize = 52,
    super.key,
  });

  final bool inverse;
  final bool compact;
  final double markSize;

  @override
  Widget build(BuildContext context) {
    final primaryText = inverse
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;
    final secondaryText = inverse
        ? AppColors.inverseSubtitle
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Semantics(
      label: 'جمعية خواطر أحلى شباب',
      image: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BrandLogoMark(inverse: inverse, size: markSize),
          if (!compact) ...[
            const SizedBox(width: 11),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'جمعية خواطر أحلى شباب',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: primaryText,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'منظومة الإدارة المؤسسية',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: secondaryText,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class BrandLogoMark extends StatelessWidget {
  const BrandLogoMark({this.inverse = false, this.size = 44, super.key});

  final bool inverse;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    padding: EdgeInsets.all(size * .055),
    decoration: BoxDecoration(
      color: inverse
          ? Colors.white.withValues(alpha: .09)
          : Colors.white.withValues(alpha: .94),
      borderRadius: BorderRadius.circular(size * .29),
      border: Border.all(
        color: inverse
            ? Colors.white.withValues(alpha: .18)
            : Theme.of(context).colorScheme.outlineVariant,
      ),
      boxShadow: [
        BoxShadow(
          color: AppColors.brandPrimaryStrong.withValues(alpha: .13),
          blurRadius: 18,
          offset: const Offset(0, 7),
        ),
      ],
    ),
    child: Image.asset(
      inverse
          ? 'assets/brand/association-logo-white.png'
          : 'assets/brand/association-logo-blue.png',
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      excludeFromSemantics: true,
    ),
  );
}
