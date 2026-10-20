import 'package:flutter/material.dart';

class NetworkImageWithPlaceholder extends StatelessWidget {
  const NetworkImageWithPlaceholder({
    required this.url,
    this.height,
    this.width,
    this.fit = BoxFit.cover,
    this.placeholderColor = const Color(0xFFE0E0E0),
    this.errorIcon = Icons.broken_image,
    super.key,
  });

  final String url;
  final double? height;
  final double? width;
  final BoxFit fit;
  final Color placeholderColor;
  final IconData errorIcon;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      height: height,
      width: width,
      fit: fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          height: height,
          width: width,
          color: placeholderColor,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2.0)),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          height: height,
          width: width,
          color: placeholderColor,
          alignment: Alignment.center,
          child: Icon(errorIcon, color: Theme.of(context).colorScheme.onSurfaceVariant),
        );
      },
    );
  }
}
