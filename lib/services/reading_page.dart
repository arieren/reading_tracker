import '../models/book_codec.dart';

bool isReadingUrl(String? value) =>
    value != null &&
    value.trim().isNotEmpty &&
    validWebUrl(value) &&
    (Uri.tryParse(value)?.userInfo.isEmpty ?? false);

/// Normalize browser-style form input without treating ordinary notes as URLs.
String normalizeWebAddress(String value) {
  final input = value.trim();
  if (input.isEmpty || isReadingUrl(input)) return input;
  final hostPort = RegExp(
    r'^(?:[^\s/:?#]+\.[^\s/:?#]+|localhost):\d+(?:[/?#]|$)',
    caseSensitive: false,
  ).hasMatch(input);
  if (input.contains('://') ||
      (RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false).hasMatch(input) &&
          !hostPort)) {
    return input;
  }
  final candidate = Uri.tryParse(
    input.startsWith('//') ? 'https:$input' : 'https://$input',
  );
  if (candidate == null || !isReadingUrl(candidate.toString())) return input;
  final host = candidate.host;
  final labels = host.split('.');
  final domain =
      labels.length > 1 &&
      labels.every(
        (label) => RegExp(
          r'^[\p{L}\p{N}](?:[\p{L}\p{N}-]*[\p{L}\p{N}])?$',
          unicode: true,
        ).hasMatch(label),
      );
  if (!domain &&
      host != 'localhost' &&
      !(input.startsWith('[') && host.contains(':'))) {
    return input;
  }
  return candidate.toString();
}

String normalizedStoryTitle(String title) =>
    title.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

int? chapterFromPageTitle(String title) {
  final match = RegExp(
    r'\b(?:chapter|ch\.?|episode|ep\.?)\s*[:#\-]?\s*(\d+(?:\.\d+)?)\b',
    caseSensitive: false,
  ).firstMatch(title);
  final value = int.tryParse(match?.group(1) ?? '');
  return value != null && value >= 0 && value <= 2147483647 ? value : null;
}

bool pageMatchesBook({
  required String savedUrl,
  required String currentUrl,
  required String bookTitle,
  required String pageTitle,
}) {
  if (!validWebUrl(currentUrl)) return false;
  final saved = Uri.tryParse(savedUrl), current = Uri.tryParse(currentUrl);
  if (saved == null ||
      current == null ||
      saved.host.toLowerCase() != current.host.toLowerCase() ||
      current.userInfo.isNotEmpty) {
    return false;
  }
  if (saved == current) return true;
  // Never replace a book's bookmark with a site's home, search or login page.
  if (current.pathSegments.isEmpty ||
      RegExp(
        r'^/(?:search|login|signin|account|auth|register)(?:/|$)',
        caseSensitive: false,
      ).hasMatch(current.path)) {
    return false;
  }
  final book = normalizedStoryTitle(bookTitle);
  if (book.length < 3) return false;
  return normalizedStoryTitle(suggestedStoryTitle(pageTitle)) == book &&
      chapterFromPageTitle(pageTitle) != null;
}

String suggestedStoryTitle(String pageTitle) {
  final title = pageTitle
      .replaceFirst(
        RegExp(
          r'\s*[-–|:]?\s*(?:chapter|ch\.?|episode|ep\.?)\s*[:#\-]?\s*\d+.*$',
          caseSensitive: false,
        ),
        '',
      )
      .trim();
  return title.length > 500 ? title.substring(0, 500) : title;
}
