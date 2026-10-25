// lib/widgets/ui/client_avatar.dart

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Avatar circulaire d'un client, construit à partir de ses initiales.
class ClientAvatar extends StatelessWidget {
  final String name;
  final double size;

  const ClientAvatar({super.key, required this.name, this.size = 44});

  /// Initiales : première lettre des deux premiers mots significatifs.
  static String initialsOf(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    final first = words.first.substring(0, 1).toUpperCase();
    if (words.length == 1) return first;
    return '$first${words[1].substring(0, 1).toUpperCase()}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final trimmed = name.trim();
    final isUnknown = trimmed.isEmpty || trimmed.toLowerCase() == 'client inconnu';

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: isUnknown
          ? Icon(Icons.person_outline, size: size * 0.5, color: colors.primary)
          : Text(
              initialsOf(trimmed),
              style: TextStyle(
                color: colors.primary,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.34,
              ),
            ),
    );
  }
}
