import 'package:flutter/material.dart';

/// A circular avatar that shows a network image when available and gracefully
/// falls back to [placeholder] while loading or if the image 404s/fails —
/// stale or missing files must never show a broken image or throw.
class ProfileAvatar extends StatelessWidget {
  final String? url;
  final double size;
  final Widget placeholder;
  final Color? backgroundColor;
  final BoxBorder? border;

  const ProfileAvatar({
    super.key,
    required this.url,
    required this.size,
    required this.placeholder,
    this.backgroundColor,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: border,
      ),
      child: (url == null || url!.isEmpty)
          ? Center(child: placeholder)
          : Image.network(
              url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(child: placeholder),
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : Center(child: placeholder),
            ),
    );
  }
}
