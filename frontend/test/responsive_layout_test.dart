import 'package:care_connect_app/utils/responsive_utils.dart';
import 'package:care_connect_app/widgets/responsive_page_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpAtSize(WidgetTester tester, Size size) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.pumpWidget(
      const MaterialApp(
        home: ResponsivePageWrapper(
          child: SizedBox(key: Key('responsive-content')),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'TC-S4-REG-RESP-001 applies mobile and desktop page padding',
    (tester) async {
      await pumpAtSize(tester, const Size(390, 844));
      var padding = tester.widget<Padding>(
        find
            .ancestor(
              of: find.byKey(const Key('responsive-content')),
              matching: find.byType(Padding),
            )
            .first,
      );
      expect(padding.padding,
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16));

      await pumpAtSize(tester, const Size(1200, 800));
      padding = tester.widget<Padding>(
        find
            .ancestor(
              of: find.byKey(const Key('responsive-content')),
              matching: find.byType(Padding),
            )
            .first,
      );
      expect(padding.padding,
          const EdgeInsets.symmetric(horizontal: 96, vertical: 24));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'TC-S4-REG-RESP-002 changes grid columns at every responsive breakpoint',
    (tester) async {
      const cases = <(Size, int)>[
        (Size(599, 800), 1),
        (Size(600, 800), 2),
        (Size(900, 800), 3),
        (Size(1200, 800), 4),
      ];

      for (final (size, columnCount) in cases) {
        await pumpAtSize(tester, size);
        final context =
            tester.element(find.byKey(const Key('responsive-content')));
        expect(
          ResponsiveUtils.getGridColumnCount(context),
          columnCount,
          reason: 'width ${size.width}',
        );
      }
    },
  );
}
