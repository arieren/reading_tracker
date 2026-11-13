import 'package:material_ui/material_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';

Color bookTypeColor(String type) => switch (type) {
  'Novel' => Colors.blue,
  'Manga' => Colors.red,
  'Manhwa' => Colors.purple,
  'Light Novel' => Colors.amber.shade800,
  _ => Colors.grey,
};

class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    this.imageUrl,
    required this.type,
    this.width,
    this.height,
  });
  final String? imageUrl;
  final String type;
  final double? width, height;
  Widget _placeholder() => ColoredBox(
    color: bookTypeColor(type).withValues(alpha: 0.2),
    child: Center(
      child: Icon(Icons.book, color: bookTypeColor(type), size: 40),
    ),
  );
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: SizedBox(
      width: width,
      height: height,
      child: imageUrl == null || imageUrl!.isEmpty
          ? _placeholder()
          : CachedNetworkImage(
              imageUrl: imageUrl!,
              fit: BoxFit.cover,
              placeholder: (_, _) => _placeholder(),
              errorWidget: (_, _, _) => _placeholder(),
            ),
    ),
  );
}
