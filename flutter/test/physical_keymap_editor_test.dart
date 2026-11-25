import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/desktop/widgets/physical_keymap_editor.dart';

void main() {
  for (final mac in [false, true]) {
    testWidgets('edit and reopen the ${mac ? "Mac" : "Windows"} profile',
        (tester) async {
      String? saved;
      Future<void> open(String profile) => tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: PhysicalKeymapEditor(
                key: UniqueKey(),
                saved: profile,
                localMac: mac,
                label: (key) => key,
                onSave: (value) => saved = value,
                onCancel: () {},
              ),
            ),
          ));
      await open('');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<int>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(mac ? 'R Alt' : 'R Option').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      expect(saved, mac ? '227=230' : '224=230');
      await open(saved!);
      expect(
          tester
              .widget<DropdownButton<int>>(
                  find.byType(DropdownButton<int>).last)
              .value,
          230);
      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      expect(saved, '');
    });
  }
}
