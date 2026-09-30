/// Email, phone, and file validation utilities for WorkForceOS.
class Validators {
  static final _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// Validates whether a given string is a valid UUID format.
  static bool isValidUuid(String? str) {
    if (str == null || str.trim().isEmpty) return false;
    return _uuidRegex.hasMatch(str.trim());
  }

  /// RFC 5322 simplified email regex.
  static final _emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
  );

  /// Validates an email address.
  static bool isValidEmail(String email) {
    return _emailRegex.hasMatch(email.trim());
  }

  /// Validates a phone number (digits only, optional + prefix, 10-15 characters).
  static bool isValidPhone(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    return RegExp(r'^\+?[0-9]{10,15}$').hasMatch(cleaned);
  }

  /// Sanitizes a filename to prevent path traversal attacks.
  /// Removes path separators, null bytes, and limits length.
  static String sanitizeFileName(String fileName) {
    final sanitized = fileName
        .replaceAll(RegExp(r'[\/\\]'), '') // Remove path separators
        .replaceAll('\x00', '') // Remove null bytes
        .replaceAll(RegExp(r'\.\.'), '') // Remove parent directory references
        .replaceAll(RegExp(r'[^\w\.\-]'), '_'); // Replace special chars with underscore
    return sanitized.substring(0, sanitized.length.clamp(0, 200)); // Limit length
  }
}
