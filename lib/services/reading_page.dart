import '../models/book_codec.dart';

bool isReadingUrl(String? value) =>
    value != null &&
    value.trim().isNotEmpty &&
    validWebUrl(value) &&
    (Uri.tryParse(value)?.userInfo.isEmpty ?? false);

Uri atsuTitleSearch(String title) =>
    Uri.https('atsu.moe', '/explore', {'search': title.trim()});

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
  var title = pageTitle
      .replaceFirst(
        RegExp(
          r'\s*[-–|:]?\s*(?:chapter|ch\.?|episode|ep\.?)\s*[:#\-]?\s*\d+.*$',
          caseSensitive: false,
        ),
        '',
      )
      .trim();
  title = title
      .replaceFirst(
        RegExp(
          r'\s*[-–|]\s*(?:atsumaru|atsu|webtoon|manga plus).*$',
          caseSensitive: false,
        ),
        '',
      )
      .trim();
  return title.length > 500 ? title.substring(0, 500) : title;
}
