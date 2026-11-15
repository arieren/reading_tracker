import 'package:material_ui/material_ui.dart';

import '../services/reading_link_service.dart';
import '../screens/browse_screen.dart';

class ReadingSourceSetting extends StatefulWidget {
  const ReadingSourceSetting({super.key, this.preferences});
  final ReadingSourcePreferences? preferences;
  @override
  State<ReadingSourceSetting> createState() => _ReadingSourceSettingState();
}

class _ReadingSourceSettingState extends State<ReadingSourceSetting> {
  late final _preferences = widget.preferences ?? ReadingSourcePreferences();
  ReadingSource _source = ReadingSource.atsu;
  List<ReadingSource> _choices = [ReadingSource.atsu];
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = await _preferences.load();
      final choices = await _preferences.available();
      if (mounted) {
        setState(() {
          _source = value;
          _choices = choices;
        });
      }
    } on Object {
      if (mounted) setState(() => _error = 'Could not load this preference.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(ReadingSource? source) async {
    if (source == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _preferences.save(source);
      if (mounted) setState(() => _source = source);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not save this preference. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Reading links', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
          'When adding manga, manhwa or light novels without a link, look for an exact title on this site.',
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<ReadingSource>(
          key: ValueKey(_source),
          initialValue: _source,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Preferred reading site',
          ),
          items: _choices
              .map(
                (source) => DropdownMenuItem(
                  value: source,
                  child: Text(
                    source.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: _busy ? null : _save,
        ),
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Automatic search is best effort. You can also open any saved website and save a story from its page.',
          ),
        ),
        TextButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const BrowseScreen()),
                  );
                  if (mounted) await _load();
                },
          icon: const Icon(Icons.language_outlined),
          label: const Text('Manage websites'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
  );
}
