import 'package:flutter/material.dart';

// USB keyboard-page usages. Keep lock keys out: RustDesk synchronizes their
// state separately from physical key presses.
Map<int, String> _keyNames(bool mac) => {
      for (var side = 0; side < 2; side++)
        for (final entry in [
          'Ctrl',
          'Shift',
          mac ? 'Option' : 'Alt',
          mac ? 'Command' : 'Win'
        ].asMap().entries)
          224 + side * 4 + entry.key: '${side == 0 ? 'L' : 'R'} ${entry.value}',
      for (var i = 0; i < 26; i++) 4 + i: String.fromCharCode(65 + i),
      for (var i = 0; i < 10; i++) 30 + i: '${(i + 1) % 10}',
      40: 'Enter',
      41: 'Esc',
      42: 'Backspace',
      43: 'Tab',
      44: 'Space',
      45: '-',
      46: '=',
      47: '[',
      48: ']',
      49: '\\',
      51: ';',
      52: "'",
      53: '`',
      54: ',',
      55: '.',
      56: '/',
      for (var i = 0; i < 12; i++) 58 + i: 'F${i + 1}',
      74: 'Home',
      75: 'Page Up',
      76: 'Delete',
      77: 'End',
      78: 'Page Down',
      79: '→',
      80: '←',
      81: '↓',
      82: '↑',
    };

class PhysicalKeymapEditor extends StatefulWidget {
  final String saved;
  final bool localMac;
  final String Function(String) label;
  final ValueChanged<String> onSave;
  final VoidCallback onCancel;

  const PhysicalKeymapEditor({
    super.key,
    required this.saved,
    required this.localMac,
    required this.label,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<PhysicalKeymapEditor> createState() => _PhysicalKeymapEditorState();
}

class _PhysicalKeymapEditorState extends State<PhysicalKeymapEditor> {
  late final local = _keyNames(widget.localMac);
  late final remote = _keyNames(!widget.localMac);
  final rows = <MapEntry<int, int>>[];

  @override
  void initState() {
    super.initState();
    for (final rule in widget.saved.split(RegExp(r'\s+'))) {
      final parts = rule.split('=');
      if (parts.length != 2) continue;
      final from = int.tryParse(parts.first);
      final to = int.tryParse(parts.last);
      if (from != null &&
          to != null &&
          local.containsKey(from) &&
          remote.containsKey(to) &&
          !rows.any((row) => row.key == from)) {
        rows.add(MapEntry(from, to));
      }
    }
  }

  Widget selector(int index, bool source) {
    final row = rows[index];
    final names = source ? local : remote;
    return Expanded(
        child: DropdownButton<int>(
      isExpanded: true,
      menuMaxHeight: 320,
      value: source ? row.key : row.value,
      items: [
        for (final e in names.entries)
          if (!source || e.key == row.key || !rows.any((r) => r.key == e.key))
            DropdownMenuItem(value: e.key, child: Text(e.value)),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() => rows[index] =
            source ? MapEntry(value, row.value) : MapEntry(row.key, value));
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.label;
    final unused =
        local.keys.where((key) => !rows.any((row) => row.key == key));
    return SizedBox(
        width: 430,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '${widget.localMac ? "macOS → Windows" : "Windows → macOS"} · ${t("Map mode")}'),
            for (var i = 0; i < rows.length; i++)
              Row(children: [
                selector(i, true),
                const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward, size: 16)),
                selector(i, false),
                IconButton(
                    tooltip: t('Remove'),
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => setState(() => rows.removeAt(i))),
              ]),
            TextButton.icon(
              onPressed: unused.isEmpty
                  ? null
                  : () => setState(() {
                        final preferred = widget.localMac ? 227 : 224;
                        final from = unused.contains(preferred)
                            ? preferred
                            : unused.first;
                        rows.add(MapEntry(
                            from,
                            from == preferred
                                ? (widget.localMac ? 224 : 227)
                                : from));
                      }),
              icon: const Icon(Icons.add),
              label: Text(t('Add')),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: widget.onCancel, child: Text(t('Cancel'))),
              TextButton(
                onPressed: () => widget
                    .onSave(rows.map((r) => '${r.key}=${r.value}').join(' ')),
                child: Text(t('Save')),
              ),
            ]),
          ],
        ));
  }
}
