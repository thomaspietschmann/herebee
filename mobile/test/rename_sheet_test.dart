import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herebee/features/sheets/sheets.dart';
import 'package:herebee/l10n/app_localizations.dart';

void main() {
  testWidgets('rename field stays above the keyboard', (tester) async {
    const keyboard = 300.0;
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: const [
        L.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showRenameSheet(context, current: 'Biene', hasCustom: false),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
    await tester.pumpAndSettle();

    final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final field = tester.getRect(find.byType(TextField));
    expect(field.bottom, lessThanOrEqualTo(screenHeight - keyboard));
  });
}
