import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_for_me/features/notes/presentation/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('HomeScreen renders Notes For Me and starter notes', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Notes For Me'), findsOneWidget);
    expect(find.text('Welcome to Notes For Me'), findsOneWidget);
    expect(find.text('Daily Setup Checklist'), findsOneWidget);
  });
}
