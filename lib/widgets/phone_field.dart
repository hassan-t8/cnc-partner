import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';

class Country {
  final String code;
  final String dial;
  final String flag;
  final String name;
  final int digits;
  const Country(this.code, this.dial, this.flag, this.name, this.digits);
}

const kCountries = <Country>[
  Country('AE', '+971', '🇦🇪', 'United Arab Emirates', 9),
  Country('SA', '+966', '🇸🇦', 'Saudi Arabia', 9),
  Country('QA', '+974', '🇶🇦', 'Qatar', 8),
  Country('OM', '+968', '🇴🇲', 'Oman', 8),
  Country('BH', '+973', '🇧🇭', 'Bahrain', 8),
  Country('KW', '+965', '🇰🇼', 'Kuwait', 8),
  Country('IN', '+91', '🇮🇳', 'India', 10),
  Country('PK', '+92', '🇵🇰', 'Pakistan', 10),
  Country('GB', '+44', '🇬🇧', 'United Kingdom', 10),
  Country('US', '+1', '🇺🇸', 'United States', 10),
];

/// Phone input with a country (flag + dial code) picker. Emits the full
/// `+<dial><national>` string via [onChanged].
class PhoneField extends StatefulWidget {
  final String? initial;
  final ValueChanged<String> onChanged;
  final String label;
  const PhoneField(
      {super.key, this.initial, required this.onChanged, this.label = 'Phone'});

  @override
  State<PhoneField> createState() => _PhoneFieldState();
}

class _PhoneFieldState extends State<PhoneField> {
  late Country _country;
  final _digits = TextEditingController();

  @override
  void initState() {
    super.initState();
    _country = kCountries.first;
    final init = (widget.initial ?? '').trim();
    if (init.isNotEmpty) {
      final match = kCountries
          .where((c) => init.startsWith(c.dial))
          .toList()
        ..sort((a, b) => b.dial.length.compareTo(a.dial.length));
      if (match.isNotEmpty) {
        _country = match.first;
        _digits.text = init.substring(_country.dial.length);
      } else {
        _digits.text = init.replaceAll(RegExp(r'\D'), '');
      }
    }
  }

  @override
  void dispose() {
    _digits.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged('${_country.dial}${_digits.text.trim()}');

  Future<void> _pick() async {
    final picked = await showModalBottomSheet<Country>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text('Select country',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            for (final c in kCountries)
              ListTile(
                leading: Text(c.flag, style: const TextStyle(fontSize: 24)),
                title: Text(c.name),
                trailing: Text(c.dial,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pop(context, c),
              ),
          ],
        ),
      ),
    );
    if (picked != null) {
      setState(() => _country = picked);
      _emit();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(widget.label,
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600)),
        ),
        Row(
          children: [
            InkWell(
              onTap: _pick,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_country.flag, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 6),
                    Text(_country.dial,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Icon(Icons.arrow_drop_down, color: AppColors.textMuted),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _digits,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(12),
                ],
                onChanged: (_) => _emit(),
                decoration: const InputDecoration(hintText: 'Phone number'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
