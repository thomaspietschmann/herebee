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

  test('synthwave is stored by name and read back after a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await Storage.open();
    await storage.setMapTheme(MapThemePref.synthwave);
    expect(storage.mapTheme, MapThemePref.synthwave);
    expect(storage.mapThemeListenable.value, MapThemePref.synthwave);
    expect((await SharedPreferences.getInstance()).getString('herebee.mapTheme'), 'synthwave');
    expect((await Storage.open()).mapTheme, MapThemePref.synthwave);
  });

  test('the other styles live next to the light one on the same origin', () {
    const origin = AppConfig.officialOrigin;
    expect(AppConfig.styleUrl(origin, 'de'), '$origin/style/de.json');
    expect(AppConfig.styleUrl(origin, 'de', theme: 'light'), '$origin/style/de.json');
    expect(AppConfig.styleUrl(origin, 'de', theme: 'dark'), '$origin/style/dark/de.json');
    expect(AppConfig.styleUrl(origin, 'en', theme: 'synthwave'), '$origin/style/synthwave/en.json');
  });
}
