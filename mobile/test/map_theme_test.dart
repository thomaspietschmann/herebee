import 'package:flutter_test/flutter_test.dart';
import 'package:herebee/app_config.dart';
import 'package:herebee/core/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the map style follows the system until the user picks one', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await Storage.open();
    expect(storage.mapTheme, MapThemePref.auto);
    await storage.setMapTheme(MapThemePref.dark);
    expect(storage.mapTheme, MapThemePref.dark);
    await storage.setMapTheme(MapThemePref.auto);
    expect(storage.mapTheme, MapThemePref.auto);
    expect((await SharedPreferences.getInstance()).getKeys(), isNot(contains('herebee.mapTheme')));
  });

  test('the dark style lives next to the light one on the same origin', () {
    expect(AppConfig.styleUrl('de'), '${AppConfig.origin}/style/de.json');
    expect(AppConfig.styleUrl('de', dark: true), '${AppConfig.origin}/style/dark/de.json');
  });
}
