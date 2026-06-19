/// Mirrors the backend passwordValidator.ts rules.
class PasswordRules {
  static bool minLen(String p) => p.length >= 8;
  static bool hasLetter(String p) => RegExp(r'[A-Za-z]').hasMatch(p);
  static bool hasDigit(String p) => RegExp(r'\d').hasMatch(p);
  static bool hasSpecial(String p) => RegExp(r'[^A-Za-z0-9]').hasMatch(p);

  static bool isValid(String p) =>
      minLen(p) && hasLetter(p) && hasDigit(p) && hasSpecial(p);

  static List<(String, bool)> checklist(String p) => [
        ('At least 8 characters', minLen(p)),
        ('A letter', hasLetter(p)),
        ('A number', hasDigit(p)),
        ('A special character', hasSpecial(p)),
      ];
}
