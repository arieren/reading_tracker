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
  ReadingSource? _source;
  List<ReadingSource> _choices = [];
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

  Future<void> _save(String? url) async {
    if (url == null || _busy) return;
    final source = _choices.where((source) => source.url == url).firstOrNull;
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
        Text(
          'Link preferences',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const Text('Optional lookup for entries with no link.'),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: ValueKey(_source),
          initialValue: _source?.url ?? '',
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Lookup website'),
          items: [
            const DropdownMenuItem(
              value: '',
              child: Text(
                'Off — no automatic lookup',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ..._choices.map(
              (source) => DropdownMenuItem(
                value: source.url,
                child: Text(
                  source.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: _busy ? null : _save,
        ),
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Results depend on the website. Links can always be entered manually.',
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
