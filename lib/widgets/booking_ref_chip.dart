import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../core/theme/app_colors.dart';
import 'app_toast.dart';

/// Small "CNC-B-1234" chip so crew/drivers can identify a job at a glance.
/// Long-press copies the reference.
class BookingRefChip extends StatelessWidget {
  final String bookingRef;
  const BookingRefChip(this.bookingRef, {super.key});

  @override
  Widget build(BuildContext context) {
    if (bookingRef.trim().isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () async {
          await Clipboard.setData(ClipboardData(text: bookingRef));
          AppToast.success('Booking $bookingRef copied');
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.confirmation_number_outlined,
                  size: 12, color: AppColors.textFaint),
              const SizedBox(width: 5),
              Text(
                bookingRef,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
