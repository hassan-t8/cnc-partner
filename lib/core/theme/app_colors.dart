import 'package:flutter/material.dart';

/// Brand palette mirrored from the Carencleanss partner portal.
class AppColors {
  // Brand greens
  static const brand50 = Color(0xFFECFDF5);
  static const brand100 = Color(0xFFD1FAE5);
  static const brand500 = Color(0xFF10B981);
  static const brand600 = Color(0xFF059669); // primary
  static const brand700 = Color(0xFF047857);

  // Neutrals — runtime-swappable for dark mode (see [applyBrightness]).
  static Color bg = const Color(0xFFF9FAFB);
  static Color surface = Colors.white;
  static Color border = const Color(0xFFE5E7EB);
  static Color sidebar = const Color(0xFF111827);
  static Color textPrimary = const Color(0xFF111827);
  static Color textSecondary = const Color(0xFF374151);
  static Color textMuted = const Color(0xFF6B7280);
  static Color textFaint = const Color(0xFF9CA3AF);

  static bool isDark = false;

  /// Swap the neutral palette for the given brightness. Call before runApp and
  /// whenever the platform brightness changes.
  static void applyBrightness(Brightness b) {
    isDark = b == Brightness.dark;
    if (isDark) {
      bg = const Color(0xFF0B0F14);
      surface = const Color(0xFF161B22);
      border = const Color(0xFF2A323C);
      sidebar = const Color(0xFF0B0F14);
      textPrimary = const Color(0xFFF3F4F6);
      textSecondary = const Color(0xFFD1D5DB);
      textMuted = const Color(0xFF9CA3AF);
      textFaint = const Color(0xFF6B7280);
    } else {
      bg = const Color(0xFFF9FAFB);
      surface = Colors.white;
      border = const Color(0xFFE5E7EB);
      sidebar = const Color(0xFF111827);
      textPrimary = const Color(0xFF111827);
      textSecondary = const Color(0xFF374151);
      textMuted = const Color(0xFF6B7280);
      textFaint = const Color(0xFF9CA3AF);
    }
  }

  // Accents (status)
  static const sky = Color(0xFF0EA5E9);
  static const emerald = Color(0xFF10B981);
  static const violet = Color(0xFF8B5CF6);
  static const rose = Color(0xFFE11D48);
  static const amber = Color(0xFFF59E0B);
  static const star = Color(0xFFFBBF24);

  /// Booking dispatch status → (bg, fg).
  static (Color, Color) dispatchStatus(String status) {
    switch (status) {
      case 'pending_dispatch':
        return (const Color(0xFFFEF3C7), const Color(0xFF92400E));
      case 'awaiting_acceptance':
        return (const Color(0xFFE0F2FE), const Color(0xFF075985));
      case 'accepted':
        return (const Color(0xFFD1FAE5), const Color(0xFF065F46));
      case 'in_progress':
        return (const Color(0xFFEDE9FE), const Color(0xFF5B21B6));
      case 'declined':
      case 'failed_to_assign':
        return (const Color(0xFFFFE4E6), const Color(0xFF9F1239));
      case 'completed':
      case 'unassigned':
      case 'cancelled':
      default:
        return (const Color(0xFFF3F4F6), const Color(0xFF374151));
    }
  }

  /// Worker assignment/booking status → (bg, fg).
  static (Color, Color) workerStatus(String status) {
    switch (status) {
      case 'pending_acceptance':
        return (const Color(0xFFFEF3C7), const Color(0xFFB45309));
      case 'accepted':
        return (const Color(0xFFE0F2FE), const Color(0xFF0369A1));
      case 'in_progress':
        return (const Color(0xFFEDE9FE), const Color(0xFF6D28D9));
      case 'completed':
        return (const Color(0xFFD1FAE5), const Color(0xFF047857));
      case 'declined':
      case 'no_show':
        return (const Color(0xFFFFE4E6), const Color(0xFFBE123C));
      case 'cancelled':
      default:
        return (const Color(0xFFF3F4F6), const Color(0xFF374151));
    }
  }
}
