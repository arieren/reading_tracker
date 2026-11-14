import 'package:material_ui/material_ui.dart';

import 'book_cover.dart';

class BookMetadata extends StatelessWidget {
  const BookMetadata({super.key, required this.type, required this.chapter});
  final String type;
  final int chapter;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: bookTypeColor(type).withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          type,
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark
                ? Color.lerp(bookTypeColor(type), Colors.white, 0.4)
                : bookTypeColor(type),
            fontSize: 12,
          ),
        ),
      ),
      Text('Ch. $chapter', style: const TextStyle(fontSize: 12)),
    ],
  );
}
