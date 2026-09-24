import 'package:flutter_test/flutter_test.dart';
import 'package:progressive_jewellery/main.dart';

void main() {
  testWidgets('renders the Progressive Jewellery sign-in screen', (
    tester,
  ) async {
    await tester.pumpWidget(const ProgressiveJewelleryApp());

    expect(find.byType(LoginPage), findsOneWidget);
  });
}
