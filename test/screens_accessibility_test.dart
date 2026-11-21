// The unit page and the pairing code as a screen reader, a switch user and
// someone with large text meet them. Companion to accessibility_test.dart,
// which covers the controls one by one.

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:breeze/src/l10n.dart';
import 'package:breeze/src/a11y.dart';
import 'package:breeze/src/app_controller.dart';
import 'package:breeze/src/app_scope.dart';
import 'package:breeze/src/layout.dart';
import 'package:breeze/src/models.dart';
import 'package:breeze/src/screens/unit_page.dart';
import 'package:breeze/src/secure_store.dart';

UnitState _state({bool online = true}) => UnitState(
      id: '1',
      name: 'Living room',
      ip: '192.0.2.10',
      online: online,
      powerState: true,
      operationalMode: 'HEAT',
      targetTemperature: 23.5,
      indoorTemperature: 21.0,
      outdoorTemperature: 4.0,
      fanSpeed: 102,
      swingMode: 'VERTICAL',
      eco: false,
      turbo: false,
    );

Widget _unitPage(double textScale, {bool online = true}) => AppScope(
      controller: AppController(SecureStore()),
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: appSupportedLocales,
        home: Builder(
          // The test screen's size, with only the text scaled.
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: Scaffold(
              body: UnitPage(
                state: _state(online: online),
                onControl: (_) {},
                onRename: () {},
                onRemove: () {},
                onTimer: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  test('an open foldable with its system bars is still roomy; no phone is', () {
    expect(pageIsRoomy(const Size(560, 593)), isTrue); // Pixel Fold, gesture bar
    expect(pageIsRoomy(const Size(560, 569)), isTrue); // the same, taskbar
    expect(pageIsRoomy(const Size(430, 900)), isFalse); // a big phone, upright
    expect(pageIsRoomy(const Size(900, 400)), isFalse); // and on its side
  });

  test('a pairing code is spelled out, character by character', () {
    expect(spelled('JH7S-XT2P'), 'J H 7 S, X T 2 P');
    expect(spelled('ABCD'), 'A B C D');
  });

  group('unit page', () {
    setUp(() {
      final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.physicalSize = const Size(360, 740);
      view.devicePixelRatio = 1;
    });
    tearDown(() {
      final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    testWidgets('at normal text size it fits, without scrolling', (tester) async {
      await tester.pumpWidget(_unitPage(1.0));
      expect(tester.takeException(), isNull);
      // Upright, the page is always ready to scroll (a short window needs
      // it, below), but here there is nothing to scroll: it fits.
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      expect(scroll.position.maxScrollExtent, 0);
    });

    // With the system bars taken out, many phones are shorter than the
    // page: 360 x 740 with three-button navigation leaves it 360 x 562 below
    // the app bar. Fixed in height, the bottom controls were cut off there.
    testWidgets('at normal text on a short window it scrolls instead of cutting off the bottom', (tester) async {
      tester.view.physicalSize = const Size(360, 562);
      await tester.pumpWidget(_unitPage(1.0));
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Turbo'), 200);
      expect(find.text('Turbo').hitTestable(), findsOneWidget);
    });

    // Android's font sizes from "Large" up, on a small phone as well.
    for (final (size, scale) in const [
      (Size(360, 740), 2.0),
      (Size(360, 640), 1.15),
      (Size(360, 640), 1.3),
      (Size(360, 640), 2.0),
    ]) {
      testWidgets(
          'at ${scale}x text on ${size.width.round()}x${size.height.round()} '
          'it scrolls instead of cutting off the bottom', (tester) async {
        tester.view.physicalSize = size;
        await tester.pumpWidget(_unitPage(scale));
        expect(tester.takeException(), isNull);
        expect(find.byType(SingleChildScrollView), findsOneWidget);
        // Turbo, the last control, can be reached.
        await tester.scrollUntilVisible(find.text('Turbo'), 200);
        expect(find.text('Turbo').hitTestable(), findsOneWidget);
      });
    }

    testWidgets('every control is named and big enough to hit', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_unitPage(1.0));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('the name is a heading; the timer and menu say what they are',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_unitPage(1.0));
      expect(tester.getSemantics(find.text('Living room')), isSemantics(isHeader: true));
      expect(find.bySemanticsLabel(RegExp(r'^Timer')), findsOneWidget);
      expect(find.byTooltip('More options for Living room'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('an offline unit says so', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_unitPage(1.0, online: false));
      expect(
        tester.getSemantics(find.text('offline — last known settings')),
        isSemantics(isLiveRegion: true),
      );
      handle.dispose();
    });
  });
}
