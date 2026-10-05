/// Modal sheets: the entry gate, the privacy explainer, the legal page, the
/// rename dialog and the invalid-link notice. Port of the sheet layer in
/// `client/src/ui.ts`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../app_config.dart';
import '../../core/deep_links.dart';
import '../../core/names.dart';
import '../../core/recent_rooms.dart';
import '../../core/storage.dart';
import '../map/bee_marker.dart';
import '../room/room_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/floor_grid.dart';
import '../../ui/tokens.dart';
import '../../util/markup.dart';


HereBeeTokens _tk(BuildContext context) => HereBeeTokens.of(context);

Widget _panel(BuildContext context, Widget child, {required bool closable, EdgeInsets? padding}) {
  final t = _tk(context);
  final grid = t.panelGridLine;
  return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(t.panelRadius),
        boxShadow: [...t.shadow, ...t.sheetGlow],
      ),
      child: Material(
        color: t.sheetBg,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.panelRadius),
          side: BorderSide(color: t.panelBorder),
        ),
        child: Stack(
          children: [
            if (grid != null) Positioned.fill(child: IgnorePointer(child: PanelGrid(line: grid))),
            SingleChildScrollView(
              padding: padding ?? const EdgeInsets.fromLTRB(22, 26, 22, 24),
              child: child,
            ),
            if (closable)
              Positioned(
                top: 12,
                right: 14,
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    tooltip: L.of(context).close,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Text('×', style: TextStyle(color: _tk(context).muted, fontSize: 22, height: 1)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
}

Future<T?> _sheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
}) =>
    showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      barrierColor: const Color(0x73000000),
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: dismissible,
      enableDrag: dismissible,
      showDragHandle: false,
      constraints: const BoxConstraints(maxWidth: 544),
      builder: (context) => PopScope(
        canPop: dismissible,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _panel(context, builder(context), closable: dismissible),
            ),
          ),
        ),
      ),
    );

Future<void> _splash(BuildContext context, {required WidgetBuilder builder}) => showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x80000000),
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (context, animation, _, child) {
        final t = const Cubic(0.16, 1, 0.3, 1).transform(animation.value);
        return Opacity(
          opacity: animation.value,
          child: Transform.translate(offset: Offset(0, 20 * (1 - t)), child: child),
        );
      },
      pageBuilder: (context, _, _) => PopScope(
        canPop: false,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Material(
                  type: MaterialType.transparency,
                  child: _panel(context, builder(context),
                      closable: false, padding: const EdgeInsets.fromLTRB(22, 30, 22, 24)),
                ),
              ),
            ),
          ),
        ),
      ),
    );

TextStyle _body(BuildContext context) => TextStyle(color: _tk(context).muted, fontSize: 13.5, height: 1.55);
TextStyle _h2(BuildContext context) {
  final t = _tk(context);
  return TextStyle(
    color: t.mist,
    fontSize: 19,
    fontWeight: FontWeight.w700,
    letterSpacing: t.uppercase ? 0 : -0.38,
    shadows: t.sheetGlow.isEmpty ? null : const [Shadow(color: Color(0x99FF2BD6), blurRadius: 12)],
  );
}

Widget _fact(BuildContext context, String markup, {bool warn = false}) => DecoratedBox(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: _tk(context).hair))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 2, top: 6, right: 12),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: warn ? _tk(context).signal : _tk(context).beacon,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Expanded(
              child: MarkupText(markup,
                  style: TextStyle(color: _tk(context).mist, fontSize: 13, height: 1.5)),
            ),
          ],
        ),
      ),
    );

/// What a server other than the official one means for privacy. Shown in the
/// entry gate of every room on such a server, in the settings, and in the
/// question before switching to one.
Widget _serverWarningBox(BuildContext context, String origin) {
  final l = L.of(context);
  return Container(
    key: const ValueKey('server-warning'),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: _tk(context).signal.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _tk(context).signal.withValues(alpha: 0.45)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: _tk(context).signal, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(l.serverWarnTitle,
                  style: TextStyle(color: _tk(context).signal, fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        MarkupText(
          l.serverWarnBody(AppConfig.hostOf(origin), AppConfig.hostOf(AppConfig.officialOrigin)),
          style: TextStyle(color: _tk(context).mist, fontSize: 13, height: 1.5),
        ),
      ],
    ),
  );
}

/// Asks before the app talks to [origin], which is not the official server.
/// [fromLink] says the server came from a room link rather than from the user.
/// True means "use it anyway".
Future<bool> showServerWarning(BuildContext context, {required String origin, required bool fromLink}) async {
  final ok = await _sheet<bool>(
    context,
    dismissible: false,
    builder: (context) {
      final l = L.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (fromLink) ...[
            Text(l.serverWarnLink, style: _body(context)),
            const SizedBox(height: 12),
          ],
          _serverWarningBox(context, origin),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('server-warning-cancel'),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(l.serverWarnCancel, maxLines: 1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('server-warning-continue'),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: FittedBox(child: Text(l.serverWarnContinue, maxLines: 1)),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
  return ok ?? false;
}

/// The entry gate. Nothing has touched the network when this opens, and it
/// cannot be dismissed without a decision: becoming present is visible to the
/// whole room, so it must be deliberate. On a server other than the official
/// one it says so every time, not only when the server was first accepted.
Future<void> showWelcomeSheet(BuildContext context, {String origin = AppConfig.officialOrigin}) => _splash(
      context,
      builder: (context) {
        final l = L.of(context);
        final logo = math.min(220.0, MediaQuery.sizeOf(context).width * 0.54);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: logo,
                height: logo,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: const [
                    BoxShadow(color: Color(0x6B000000), blurRadius: 50, offset: Offset(0, 18)),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset('assets/brand/herebee-logo.png', fit: BoxFit.cover),
              ),
            ),
            Text(l.welcomeTitle, style: _h2(context), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(l.welcomeIntro, style: _body(context), textAlign: TextAlign.center),
            if (!AppConfig.isOfficial(origin)) ...[
              const SizedBox(height: 14),
              _serverWarningBox(context, origin),
            ],
            const SizedBox(height: 20),
            _fact(context, l.welcomeFact1),
            _fact(context, l.welcomeFact2),
            _fact(context, l.welcomeFact3),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.welcomeCta),
            ),
          ],
        );
      },
    );

/// A hand-edited or truncated link. Room links are generated; they cannot be
/// typed, so there is nothing for the user to correct.
Future<void> showInvalidLinkSheet(BuildContext context) => _splash(
      context,
      builder: (context) {
        final l = L.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.invalidTitle, style: _h2(context), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(l.invalidBody, style: _body(context), textAlign: TextAlign.center),
          ],
        );
      },
    );

Future<void> showInfoSheet(BuildContext context, {RoomController? controller}) => _sheet<void>(
      context,
      builder: (context) {
        final l = L.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (controller != null) ...[
              Text(l.mapTheme, style: _h2(context)),
              const SizedBox(height: 10),
              _MapThemePicker(controller: controller),
              const SizedBox(height: 20),
              Text(l.serverTitle, style: _h2(context)),
              const SizedBox(height: 10),
              _ServerSetting(controller: controller),
              const SizedBox(height: 20),
              if (Theme.of(context).platform == TargetPlatform.android) ...[
                _PowerSaveSetting(controller: controller),
                const SizedBox(height: 20),
              ],
            ],
            Text(l.infoTitle, style: _h2(context)),
            const SizedBox(height: 10),
            MarkupText(l.infoIntro, style: _body(context)),
            const SizedBox(height: 14),
            _fact(context, l.infoFact1),
            _fact(context, l.infoFact2),
            _fact(context, l.infoFact3),
            _fact(context, l.infoFactRecent),
            _fact(context, l.infoFact4, warn: true),
            _fact(context, l.infoFact5, warn: true),
            const SizedBox(height: 6),
            Text(
              l.mapCredits('Protomaps', 'OpenStreetMap'),
              style: TextStyle(color: _tk(context).muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                showLegalSheet(context);
              },
              child: Text(l.legalLink),
            ),
          ],
        );
      },
    );

Future<void> showLegalSheet(BuildContext context) => _sheet<void>(
      context,
      builder: (context) {
        Widget p(String markup) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: MarkupText(markup, style: _body(context)),
            );
        Widget h(String title) => Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 6),
              child: MarkupText('<strong>$title</strong>', style: _body(context)),
            );
        Widget fact(String markup) => _fact(context, markup);
        final de = L.of(context).localeName.startsWith('de');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: de
              ? [
                  Text('Datenschutz', style: _h2(context)),
                  const SizedBox(height: 10),
                  p('<strong>Kurz gesagt:</strong> Keine Konten, keine Datenbank, keine Cookies, kein '
                      'Tracking. Standort, Name und Nachrichten werden auf deinem Gerät verschlüsselt. '
                      'Der Server leitet sie nur weiter und kann sie nicht lesen.'),
                  h('Was wir verarbeiten'),
                  fact('Deine <strong>IP-Adresse</strong>, solange du verbunden bist. Ohne sie erreicht '
                      'dich der Server nicht; außerdem begrenzt er damit die Verbindungen pro Adresse, '
                      'um Missbrauch zu verhindern.'),
                  fact('<strong>Verschlüsselte Datenpakete</strong> deines Raums (Standort, Name, '
                      'Nachricht). Der Server reicht sie an die anderen im Raum weiter, ohne sie lesen '
                      'zu können.'),
                  fact('Die <strong>Kartenkacheln</strong>, die die App lädt. Daran ließe sich grob '
                      'ablesen, welche Gegend du gerade ansiehst.'),
                  fact('<strong>Fehlerberichte</strong>, aber nur, wenn du ausdrücklich zustimmst '
                      '(siehe unten).'),
                  const SizedBox(height: 8),
                  h('Was wir nicht erheben'),
                  fact('Keine Konten, keine E-Mail-Adresse, keine Telefonnummer, keine Kontakte.'),
                  fact('Keine lesbaren Koordinaten, Namen oder Nachrichten und niemals den '
                      'Raum-Schlüssel.'),
                  fact('Keine Standorthistorie, keine Datenbank, keine Zugriffs-Logs der Anwendung.'),
                  fact('Keine Cookies, keine Analyse, keine Werbung, keine Tracking- oder '
                      'Absturzdienste Dritter, keine Google Play Services.'),
                  const SizedBox(height: 8),
                  h('So funktioniert das Standortteilen'),
                  p('Jeder Raum hat einen 256-Bit-Schlüssel, der nur im Link hinter <code>#</code> '
                      'steht und nie an den Server geht. Die App leitet daraus die Raum-Kennung und '
                      'einen AES-256-GCM-Schlüssel ab und verschlüsselt damit Standort, Anzeigenamen '
                      'und Nachrichten, bevor etwas das Gerät verlässt. Der Server sieht weder '
                      'Koordinaten noch Namen noch den Schlüssel.'),
                  p('Alles ist flüchtig: Ein Raum existiert nur im Arbeitsspeicher des Servers und '
                      'verschwindet, sobald der letzte Teilnehmer geht. Dein Standort wird nur '
                      'übertragen, solange du teilst; eine Nachricht ist zehn Minuten lang sichtbar. '
                      'Nichts davon wird gespeichert.'),
                  p('Die App nutzt die Ortungsdienste des Geräts erst, wenn du die Berechtigung '
                      'erteilt und das Teilen eingeschaltet hast. Angefordert wird nur „bei '
                      'App-Nutzung“, nie „immer erlauben“. Du kannst jederzeit mit dem Stopp-Knopf '
                      'aufhören oder die Berechtigung im Betriebssystem entziehen. Verwendet werden die '
                      'Ortungsdienste des Betriebssystems (Android: <code>LocationManager</code>, iOS: '
                      'CoreLocation); was diese selbst verarbeiten, regeln Google bzw. Apple.'),
                  p('Das Teilen läuft weiter, wenn du das Display sperrst oder die App in den '
                      'Hintergrund legst. Das ist sichtbar: Android zeigt eine Benachrichtigung mit '
                      'Stopp-Knopf, iOS die blaue Standortanzeige. Wenn du die App wegwischst, endet das '
                      'Teilen.'),
                  p('Wer den vollständigen Link hat, sieht den Raum – teile ihn nur mit Leuten, denen '
                      'du vertraust. Deine Biene ist in jedem Raum eine andere: Ihre Kennung wird aus '
                      'einem geheimen Geräteschlüssel und dem Raum abgeleitet, und Namen gelten nur in '
                      'dem Raum, in dem sie vergeben wurden. Wiedererkennbar bist du über Räume hinweg '
                      'nur an deinem Standort oder an einem Namen, den du selbst in mehreren Räumen '
                      'verwendest.'),
                  h('Server und IP-Adressen'),
                  p('Der offizielle Server (herebee.app) steht in Deutschland. Die HereBee-Software '
                      'protokolliert und speichert weder IP-Adressen noch Inhalte; deine IP liegt nur '
                      'kurzzeitig im Arbeitsspeicher, um Missbrauch zu begrenzen. Die Infrastruktur davor '
                      '(Hosting-Anbieter, Proxy) kann eigene technische Logs mit IP-Adressen führen, '
                      'die nach deren Fristen gelöscht werden.'),
                  p('Du kannst in der App einen anderen HereBee-Server einstellen oder einen Raum-Link '
                      'eines anderen Servers öffnen; die App warnt vorher. Für diesen Server ist allein '
                      'sein Betreiber verantwortlich, und diese Erklärung gilt dort nicht. Inhalte '
                      'bleiben auch dann Ende-zu-Ende-verschlüsselt, aber er sieht deine IP-Adresse, '
                      'wann du in welchem Raum bist und über die Kartenkacheln grob deine Region.'),
                  h('Fehlerberichte'),
                  p('Stürzt die App ab oder tritt ein unerwarteter Fehler auf, fragt sie dich, ob sie '
                      'einen Bericht senden darf. Nur wenn du auf „Senden“ tippst, geht er an den '
                      'Server, den die App gerade nutzt, und von dort per E-Mail an dessen Betreiber. '
                      'Der Server speichert und protokolliert ihn nicht.'),
                  p('Ein Bericht enthält App-Version, Betriebssystem-Version, den technischen '
                      'Fehlerverlauf, den Zeitpunkt und deinen optionalen Kommentar; bei Abstürzen '
                      'unter Android zusätzlich Gerätehersteller und -modell, Paketname und eine '
                      'zufällige Berichts-ID. Raum-Schlüssel, Raum-Links und alles, was wie eine '
                      'Koordinate aussieht, werden vorher entfernt. Standorte, Namen und Nachrichten '
                      'sind nie enthalten.'),
                  h('Karten'),
                  p('Karten, Schriften und Symbole kommen vom HereBee-Server selbst (Kartendaten © '
                      'OpenStreetMap-Mitwirkende, Format von Protomaps). Kartendienste Dritter wie '
                      'Google Maps werden nicht aufgerufen.'),
                  h('Auf deinem Gerät gespeichert'),
                  p('Der geheime Geräteschlüssel (in Keychain bzw. Keystore), pro Raum die Namen, die du '
                      'anderen gegeben hast, dein eigener Name und ob du ihn teilst, sowie deine '
                      'Einstellungen. Außerdem die letzten fünf Räume samt Schlüssel und den Bienen, '
                      'die du dort getroffen hast, für drei Tage in Keychain bzw. Keystore; jeder '
                      'Eintrag lässt sich löschen. An den Server geht zusätzlich nur ein zufälliges '
                      'Token für die Wiederverbindung, das bei jedem App-Start neu entsteht.'),
                  p('Unter Android sind Sicherungen der App-Daten abgeschaltet; unter iOS können die '
                      'Einstellungen (ohne Geräte- und Raum-Schlüssel) Teil einer Geräte- oder '
                      'iCloud-Sicherung sein. Beim Löschen der App werden alle Daten entfernt. Die App '
                      'selbst wird nur über den App-Store bzw. das signierte Installationspaket '
                      'aktualisiert, nicht vom Server nachgeladen.'),
                  h('Dritte'),
                  p('Wir geben keine Daten weiter und verkaufen nichts. Dienstleister sind nur der '
                      'Hosting-Anbieter, der den Server für uns betreibt, und der E-Mail-Anbieter, '
                      'über den Fehlerberichte zugestellt werden, denen du zugestimmt hast.'),
                  h('Kinder'),
                  p('HereBee ist nicht speziell für Kinder gemacht. Da es keine Konten gibt, fragen wir '
                      'kein Alter ab und erheben wissentlich keine Daten von Kindern. Lässt du ein Kind '
                      'seinen Standort teilen, gib den Link nur an Menschen, denen du vertraust.'),
                  h('Deine Rechte'),
                  p('Du hast das Recht auf Auskunft, Berichtigung, Löschung und Widerspruch sowie das '
                      'Recht, dich bei einer Datenschutzbehörde zu beschweren. Da HereBee über die '
                      'laufende Verbindung hinaus nichts über dich speichert, gibt es in der Regel '
                      'nichts herauszugeben oder zu löschen.'),
                  h('Änderungen'),
                  p('Ändert sich HereBee, passen wir diese Seite an. Es gilt die hier veröffentlichte '
                      'Fassung; das Datum unten zeigt den Stand.'),
                  h('Kontakt'),
                  p('Fragen zum Datenschutz oder zu HereBee erreichen uns über die Kontaktangaben im '
                      'App Store bzw. bei Google Play.'),
                  const SizedBox(height: 14),
                  Text('Über HereBee', style: _h2(context)),
                  const SizedBox(height: 10),
                  p('<strong>Betreiber:</strong> HereBee'),
                  p('Für alle Anliegen zu HereBee – auch rechtliche – nutze die Kontaktangaben im '
                      'App Store bzw. bei Google Play.'),
                  p('Stand: 3. Oktober 2026'),
                ]
              : [
                  Text('Privacy', style: _h2(context)),
                  const SizedBox(height: 10),
                  p('<strong>In short:</strong> No accounts, no database, no cookies, no tracking. Your '
                      'location, name and messages are encrypted on your device. The server only passes '
                      'them on and cannot read them.'),
                  h('What we process'),
                  fact('Your <strong>IP address</strong>, while you are connected. The server cannot '
                      'reach you without it, and it uses it to limit connections per address against '
                      'abuse.'),
                  fact('<strong>Encrypted data packets</strong> of your room (location, name, message). '
                      'The server hands them to the others in the room without being able to read '
                      'them.'),
                  fact('The <strong>map tiles</strong> the app loads. They could reveal roughly which '
                      'area you are looking at.'),
                  fact('<strong>Crash reports</strong>, but only if you explicitly agree (see below).'),
                  const SizedBox(height: 8),
                  h('What we don\'t collect'),
                  fact('No accounts, no e-mail address, no phone number, no contacts.'),
                  fact('No readable coordinates, names or messages, and never the room key.'),
                  fact('No location history, no database, no access logs kept by the application.'),
                  fact('No cookies, no analytics, no ads, no third-party tracking or crash services, no '
                      'Google Play Services.'),
                  const SizedBox(height: 8),
                  h('How location sharing works'),
                  p('Every room has a 256-bit key that lives only in the link after <code>#</code> and '
                      'is never sent to the server. The app derives the room ID and an AES-256-GCM key '
                      'from it and encrypts your location, display name and messages before anything '
                      'leaves your device. The server never sees coordinates, names or the key.'),
                  p('Everything is ephemeral: a room exists only in the server\'s memory and disappears '
                      'when the last participant leaves. Your location is sent only while you share; a '
                      'message stays visible for ten minutes. None of it is stored.'),
                  p('The app uses your device\'s location services only after you granted permission '
                      'and turned sharing on. It only asks for "while using the app", never "always". '
                      'You can stop at any time with the stop button or revoke the permission in your '
                      'system settings. It uses the operating system\'s location services (Android: '
                      '<code>LocationManager</code>, iOS: CoreLocation); what those process themselves '
                      'is governed by Google or Apple.'),
                  p('Sharing continues when you lock the screen or put the app in the background. This '
                      'is visible: Android shows a notification with a stop button, iOS the blue '
                      'location indicator. Swiping the app away ends sharing.'),
                  p('Anyone with the full link can see the room, so only share it with people you '
                      'trust. Your bee is a different one in every room: its ID is derived from a '
                      'secret device key and the room, and names only apply in the room where they were '
                      'given. Across rooms you can only be recognised by your location or by a name you '
                      'use in several rooms yourself.'),
                  h('Server and IP addresses'),
                  p('The official server (herebee.app) is located in Germany. The HereBee software '
                      'neither logs nor stores IP addresses or content; your IP is held in memory only '
                      'briefly, to limit abuse. The infrastructure in front of it (hosting provider, '
                      'proxy) may keep its own technical logs including IP addresses, deleted according '
                      'to its own retention periods.'),
                  p('You can set a different HereBee server in the app or open a room link from another '
                      'server; the app warns you first. That server\'s operator alone is responsible '
                      'for it, and this policy does not apply there. Content stays end-to-end encrypted, '
                      'but that operator sees your IP address, when you are in which room, and roughly '
                      'your area from the map tiles.'),
                  h('Crash reports'),
                  p('If the app crashes or hits an unexpected error, it asks whether it may send a '
                      'report. Only if you tap "Send" does it go to the server the app is using, which '
                      'e-mails it to its operator. The server neither stores nor logs it.'),
                  p('A report contains the app version, OS version, the technical error trace, the time '
                      'and your optional comment; for Android crashes also the device brand and model, '
                      'package name and a random report ID. Room keys, room links and anything that '
                      'looks like a coordinate are removed first. Locations, names and messages are '
                      'never included.'),
                  h('Map tiles'),
                  p('Maps, fonts and icons are served by the HereBee server itself (map data © '
                      'OpenStreetMap contributors, format by Protomaps). No third-party map services '
                      'such as Google Maps are contacted.'),
                  h('Stored on your device'),
                  p('The secret device key (in Keychain or Keystore), per room the names you gave '
                      'others, your own name and whether you share it, and your settings. Also your last '
                      'five rooms, with their keys and the bees you met there, for three days in '
                      'Keychain or Keystore; each entry can be deleted. The only other thing sent to the '
                      'server is a random reconnect token, created anew on every app start.'),
                  p('On Android, backups of app data are turned off; on iOS, the app\'s settings '
                      '(without device or room keys) may be part of a device or iCloud backup. '
                      'Uninstalling the app removes all data. The app itself is only updated through '
                      'the app store or the signed installation package, never loaded from the '
                      'server.'),
                  h('Third parties'),
                  p('We don\'t share or sell any data. The only service providers are the hosting '
                      'provider that runs the server for us and the e-mail provider that delivers crash '
                      'reports you agreed to send.'),
                  h('Children'),
                  p('HereBee is not made for children specifically. As there are no accounts, we don\'t '
                      'ask for age and don\'t knowingly collect data from children. If you let a child '
                      'share their location, only give the link to people you trust.'),
                  h('Your rights'),
                  p('You have the right to access, correct and delete your data, to object, and to '
                      'complain to a data protection authority. Since HereBee stores nothing about you '
                      'beyond the active connection, there is usually nothing to hand over or delete.'),
                  h('Changes'),
                  p('When HereBee changes, we update this page. The version published here applies; the '
                      'date below shows when it was last updated.'),
                  h('Contact'),
                  p('For questions about privacy or HereBee, use the contact details in the App Store '
                      'or on Google Play.'),
                  const SizedBox(height: 14),
                  Text('About HereBee', style: _h2(context)),
                  const SizedBox(height: 10),
                  p('<strong>Operator:</strong> HereBee'),
                  p('For any matter concerning HereBee, including legal ones, use the contact details '
                      'in the App Store or on Google Play.'),
                  p('Last updated: October 3, 2026'),
                ],
        );
      },
    );

/// The server new rooms open on, and the room's own server if it differs.
///
/// A server is taken only after it answered /healthz like a HereBee server and,
/// unless it is the official one, after the warning was confirmed. The open
/// room keeps its server: its link and its peers live there.
class _ServerSetting extends StatefulWidget {
  const _ServerSetting({required this.controller});

  final RoomController controller;

  @override
  State<_ServerSetting> createState() => _ServerSettingState();
}

class _ServerSettingState extends State<_ServerSetting> {
  late final TextEditingController _input =
      TextEditingController(text: AppConfig.hostOf(widget.controller.storage.serverOrigin));
  String? _error;
  bool _checking = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _apply(String text) async {
    final l = L.of(context);
    final storage = widget.controller.storage;
    final origin = normalizeOrigin(text);
    if (origin == null) {
      setState(() => _error = l.serverInvalid);
      return;
    }
    if (origin == storage.serverOrigin) {
      setState(() => _error = null);
      return;
    }
    setState(() {
      _error = null;
      _checking = true;
    });
    final reachable = await isHereBeeServer(origin);
    if (!mounted) return;
    setState(() => _checking = false);
    if (!reachable) {
      setState(() => _error = l.serverUnreachable);
      return;
    }
    if (!AppConfig.isOfficial(origin) &&
        !await showServerWarning(context, origin: origin, fromLink: false)) {
      return;
    }
    await storage.setServerOrigin(origin);
    if (!mounted) return;
    _input.text = AppConfig.hostOf(origin);
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.serverSaved), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _reset() async {
    await widget.controller.storage.setServerOrigin(null);
    if (!mounted) return;
    _input.text = AppConfig.hostOf(widget.controller.storage.serverOrigin);
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final storage = widget.controller.storage;
    final configured = storage.serverOrigin;
    final roomOrigin = widget.controller.origin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.serverHint, style: _body(context)),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('server-input'),
          controller: _input,
          enabled: !_checking,
          style: TextStyle(color: _tk(context).mist),
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onSubmitted: _apply,
          decoration: InputDecoration(
            prefixIcon: Icon(
              AppConfig.isOfficial(configured) ? Icons.verified_user_outlined : Icons.warning_amber_rounded,
              color: AppConfig.isOfficial(configured) ? _tk(context).beacon : _tk(context).signal,
            ),
            hintText: l.serverPlaceholder,
            hintStyle: TextStyle(color: _tk(context).muted),
            helperText: _checking
                ? l.serverChecking
                : (AppConfig.isOfficial(configured) ? l.serverOfficial : l.serverUnofficial),
            helperStyle: TextStyle(color: AppConfig.isOfficial(configured) ? _tk(context).muted : _tk(context).signal),
            errorText: _error,
            suffixIcon: IconButton(
              tooltip: l.serverUse,
              icon: Icon(Icons.check, color: _tk(context).mist),
              onPressed: _checking ? null : () => _apply(_input.text),
            ),
          ),
        ),
        if (storage.serverChosen && !AppConfig.isOfficial(configured))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: _reset, child: Text(l.serverReset)),
          ),
        if (!AppConfig.isOfficial(roomOrigin)) ...[
          const SizedBox(height: 10),
          _serverWarningBox(context, roomOrigin),
        ],
      ],
    );
  }
}

class _PowerSaveSetting extends StatefulWidget {
  const _PowerSaveSetting({required this.controller});

  final RoomController controller;

  @override
  State<_PowerSaveSetting> createState() => _PowerSaveSettingState();
}

class _PowerSaveSettingState extends State<_PowerSaveSetting> {
  late bool _on = widget.controller.powerSave;

  void _set(bool on) {
    setState(() => _on = on);
    unawaited(widget.controller.setPowerSave(on));
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final t = _tk(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.powerSaveTitle, style: _h2(context)),
              const SizedBox(height: 6),
              Text(l.powerSaveHint, style: _body(context)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch(
          key: const ValueKey('power-save'),
          value: _on,
          onChanged: _set,
          activeThumbColor: t.beacon,
        ),
      ],
    );
  }
}

/// Whether [origin] answers like a HereBee server. Only the liveness probe is
/// fetched: it carries nothing about anyone, and a wrong address fails fast
/// rather than at the first room.
Future<bool> isHereBeeServer(String origin, {HttpClient? client}) async {
  final http = client ?? HttpClient();
  http.connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await http.getUrl(Uri.parse(AppConfig.healthUrl(origin))).timeout(const Duration(seconds: 8));
    req.followRedirects = false;
    final res = await req.close().timeout(const Duration(seconds: 8));
    if (res.statusCode != HttpStatus.ok) {
      await res.drain<void>();
      return false;
    }
    final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 8));
    final decoded = jsonDecode(body);
    return decoded is Map && decoded['ok'] == true;
  } catch (_) {
    return false;
  } finally {
    if (client == null) http.close(force: true);
  }
}

class _MapThemePicker extends StatefulWidget {
  const _MapThemePicker({required this.controller});

  final RoomController controller;

  @override
  State<_MapThemePicker> createState() => _MapThemePickerState();
}

const _neonNames = {
  MapThemePref.synthwave: 'Grid Toxic',
  MapThemePref.outrun: 'Outrun',
  MapThemePref.miami: 'Miami Vice',
  MapThemePref.tron: 'Tron',
  MapThemePref.vapor: 'Vaporwave',
  MapThemePref.amber: 'Blade Runner',
};

const _neonSwatches = {
  MapThemePref.synthwave: (Color(0xFF030507), Color(0xFFC24AA8), Color(0xFF62E04A)),
  MapThemePref.outrun: (Color(0xFF0F0620), Color(0xFFFF4F9A), Color(0xFFFFB03B)),
  MapThemePref.miami: (Color(0xFF071420), Color(0xFFFF7AC6), Color(0xFF2EE6D6)),
  MapThemePref.tron: (Color(0xFF01050A), Color(0xFF2AD4FF), Color(0xFFFF9A1F)),
  MapThemePref.vapor: (Color(0xFF1D1736), Color(0xFFFF9AD5), Color(0xFF8EF6E4)),
  MapThemePref.amber: (Color(0xFF080604), Color(0xFFE8762A), Color(0xFF22D3EE)),
};

class _MapThemePickerState extends State<_MapThemePicker> {
  late MapThemePref _pref = widget.controller.mapTheme;
  bool _neonOpen = false;

  void _pick(MapThemePref pref) {
    setState(() {
      _pref = pref;
      _neonOpen = false;
    });
    unawaited(widget.controller.setMapTheme(pref));
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final t = _tk(context);
    Widget seg({required Key key, required bool active, required VoidCallback onTap, required Widget child}) {
      return Expanded(
        child: Semantics(
          button: true,
          selected: active,
          child: GestureDetector(
            key: key,
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? t.beacon : Colors.transparent,
                borderRadius: BorderRadius.circular(t.pillRadius),
                boxShadow: active ? t.chromeGlow : null,
              ),
              child: FittedBox(fit: BoxFit.scaleDown, child: child),
            ),
          ),
        ),
      );
    }

    TextStyle segText(bool active) => TextStyle(
          color: active ? t.ink : t.muted,
          fontSize: t.uppercase ? 11 : 12,
          fontWeight: FontWeight.w600,
        );

    Widget plain(MapThemePref pref, String label) => seg(
          key: ValueKey('map-theme-${pref.name}'),
          active: pref == _pref,
          onTap: () => _pick(pref),
          child: Text(label, maxLines: 1, style: segText(pref == _pref)),
        );

    final neonActive = _pref.isNeon;
    final neonSeg = seg(
      key: const ValueKey('map-theme-neon'),
      active: neonActive,
      onTap: () => setState(() => _neonOpen = !_neonOpen),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(neonActive ? _neonNames[_pref]! : l.mapThemeSynthwave, maxLines: 1, style: segText(neonActive)),
          const SizedBox(width: 2),
          AnimatedRotation(
            turns: _neonOpen ? 0.5 : 0,
            duration: const Duration(milliseconds: 160),
            child: Icon(Icons.arrow_drop_down, size: 16, color: neonActive ? t.ink : t.muted),
          ),
        ],
      ),
    );

    Widget option(MapThemePref pref) {
      final active = pref == _pref;
      final (ground, major, highway) = _neonSwatches[pref]!;
      return Semantics(
        button: true,
        selected: active,
        child: GestureDetector(
          key: ValueKey('map-theme-${pref.name}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _pick(pref),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: active ? t.ink2 : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: active ? t.beacon : Colors.transparent),
            ),
            child: Row(
              children: [
                _NeonSwatch(ground: ground, major: major, highway: highway),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _neonNames[pref]!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.mist, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final neon = MapThemePref.neon;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: t.ink,
            borderRadius: BorderRadius.circular(t.pillRadius),
            border: Border.all(color: t.hair),
          ),
          child: Row(
            children: [
              plain(MapThemePref.auto, l.mapThemeAuto),
              const SizedBox(width: 4),
              plain(MapThemePref.light, l.mapThemeLight),
              const SizedBox(width: 4),
              plain(MapThemePref.dark, l.mapThemeDark),
              const SizedBox(width: 4),
              neonSeg,
            ],
          ),
        ),
        if (_neonOpen)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: t.ink,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.hair),
            ),
            child: Column(
              children: [
                for (var i = 0; i < neon.length; i += 2)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
                    child: Row(
                      children: [
                        Expanded(child: option(neon[i])),
                        const SizedBox(width: 6),
                        Expanded(child: option(neon[i + 1])),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _NeonSwatch extends StatelessWidget {
  const _NeonSwatch({required this.ground, required this.major, required this.highway});

  final Color ground;
  final Color major;
  final Color highway;

  @override
  Widget build(BuildContext context) => Container(
        width: 28,
        height: 20,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0x1FFFFFFF)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [ground, ground, major, major, ground, ground, highway, highway, ground, ground],
            stops: const [0, 0.38, 0.38, 0.5, 0.5, 0.7, 0.7, 0.8, 0.8, 1],
          ),
        ),
      );
}

/// Returns the new name, an empty string to reset to the generated one, or null
/// if the user cancelled. Names are local to this device and never transmitted.
Future<String?> showRenameSheet(
  BuildContext context, {
  required String current,
  required bool hasCustom,
}) {
  final controller = TextEditingController(text: hasCustom ? current : '');
  return _sheet<String>(
    context,
    builder: (context) {
      final l = L.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.renameTitle, style: _h2(context)),
          const SizedBox(height: 8),
          Text(l.renameBody, style: _body(context)),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            autofocus: true,
            maxLength: 40,
            style: TextStyle(color: _tk(context).mist),
            decoration: InputDecoration(
              hintText: l.renamePlaceholder,
              hintStyle: TextStyle(color: _tk(context).muted),
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
          Row(
            children: [
              if (hasCustom)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(''),
                  child: Text(l.renameReset),
                ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(controller.text.trim()),
                child: Text(l.save),
              ),
            ],
          ),
        ],
      );
    },
  );
}

Future<String?> showSaySheet(BuildContext context, {required String? current}) {
  final controller = TextEditingController(text: current ?? '');
  return _sheet<String>(
    context,
    builder: (context) {
      final l = L.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.sayTitle, style: _h2(context)),
          const SizedBox(height: 8),
          Text(l.sayBody, style: _body(context)),
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('say-input'),
            controller: controller,
            autofocus: true,
            maxLength: sharedMessageMax,
            textInputAction: TextInputAction.send,
            style: TextStyle(color: _tk(context).mist),
            decoration: InputDecoration(
              hintText: l.sayPlaceholder,
              hintStyle: TextStyle(color: _tk(context).muted),
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => value.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        key: const ValueKey('say-clear-input'),
                        tooltip: l.sayClearInput,
                        icon: Icon(Icons.close_rounded, color: _tk(context).muted, size: 20),
                        onPressed: controller.clear,
                      ),
              ),
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
          Row(
            children: [
              if (current != null)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(''),
                  child: Text(l.sayClear),
                ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(controller.text.trim()),
                child: Text(l.saySend),
              ),
            ],
          ),
        ],
      );
    },
  );
}

/// After naming yourself: may the others see it? Needs an answer, so the sheet
/// can't be dismissed; the answer is true for "share".
Future<bool> askShareName(BuildContext context, String name) async {
  final share = await _sheet<bool>(
    context,
    dismissible: false,
    builder: (context) {
      final l = L.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 18),
          Text(l.shareNameTitle, style: _h2(context)),
          const SizedBox(height: 8),
          Text(l.shareNameBody(name), style: _body(context)),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(l.shareNameNo),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(l.shareNameYes),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
  return share ?? false;
}

/// Hands the room link to the system share sheet, which is how people actually
/// pass it to one person in one messenger.
///
/// The link IS the key, so nothing extra is attached: no preview text that a
/// messenger might quote into a group, no subject line. If the sheet cannot be
/// opened, the link goes to the clipboard instead — failing to share the link is
/// the one outcome that leaves the user stuck.
Future<void> shareRoomLink(BuildContext context, String link) async {
  final l = L.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final box = context.findRenderObject() as RenderBox?;
  try {
    await SharePlus.instance.share(ShareParams(
      uri: Uri.parse(link),
      // iPad needs an anchor for the popover or the sheet throws.
      sharePositionOrigin:
          box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ));
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: link));
    messenger.showSnackBar(
      SnackBar(content: Text(l.linkCopied), behavior: SnackBarBehavior.floating),
    );
  }
}

/// What the user picked in the rooms sheet: a remembered room's secret, or
/// null for "open a new room".
class RoomsChoice {
  const RoomsChoice(this.secret, {this.origin, this.remembered = false});
  final String? secret;

  /// The server the room lives on; null for the configured one.
  final String? origin;

  /// A room from the recent list, whose server was accepted on first entry.
  final bool remembered;
}

/// Recent rooms and the way to a fresh one. Opened from the brand chip.
Future<RoomsChoice?> showRoomsSheet(
  BuildContext context, {
  required RecentRooms recent,
  required String currentSecret,
  required String Function(RecentRoom room, String seed) nameFor,
}) =>
    _sheet<RoomsChoice>(
      context,
      builder: (context) => RoomsPicker(
        recent: recent,
        currentSecret: currentSecret,
        nameFor: nameFor,
        onChoose: (choice) => Navigator.of(context).pop(choice),
      ),
    );

/// The rooms list itself: a "new room" button, the remembered rooms, forget
/// controls and the retention note. Shared by the rooms sheet and the start
/// screen, so both offer exactly the same choices.
///
/// Entries are titled by the peers met there, named exactly as on the map
/// (derived locally, in the current language), because a room has no name of
/// its own and a bare date tells you nothing.
class RoomsPicker extends StatelessWidget {
  const RoomsPicker({
    required this.recent,
    required this.nameFor,
    required this.onChoose,
    this.currentSecret,
    super.key,
  });

  final RecentRooms recent;
  final String Function(RecentRoom room, String seed) nameFor;
  final void Function(RoomsChoice choice) onChoose;

  /// The room currently open, if any; marked in the list.
  final String? currentSecret;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return ListenableBuilder(
      listenable: recent,
      builder: (context, _) {
        final rooms = recent.rooms;
        final forgettable = rooms.any((r) => r.secret != currentSecret);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.roomsTitle, style: _h2(context)),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => onChoose(const RoomsChoice(null)),
              icon: const Icon(Icons.add),
              label: Text(l.roomsNew),
            ),
            const SizedBox(height: 10),
            _RoomLinkField(onRoom: (secret, origin) => onChoose(RoomsChoice(secret, origin: origin))),
            if (rooms.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(l.roomsRecent,
                  style: TextStyle(color: _tk(context).muted, fontSize: 12, letterSpacing: 0.6)),
              const SizedBox(height: 4),
              for (final room in rooms)
                _RoomTile(
                  room: room,
                  current: room.secret == currentSecret,
                  nameFor: nameFor,
                  onOpen: () => onChoose(RoomsChoice(room.secret, origin: room.origin, remembered: true)),
                  onForget: () => recent.forget(room.secret),
                ),
              if (forgettable)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => recent.forgetAll(keep: currentSecret),
                    child: Text(l.roomsForgetAll),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Text(l.roomsNote, style: _body(context).copyWith(fontSize: 12, color: _tk(context).muted)),
          ],
        );
      },
    );
  }
}

/// Opens a room from a link pasted out of a chat, for as long as tapping the
/// link does not reach the app (no Universal Links without the paid program).
///
/// A valid link opens as soon as it lands in the field, so paste is the whole
/// gesture. On iOS the system edit menu is used: its Paste is user-initiated,
/// so iOS does not ask "Allow Paste?" as it would for a programmatic read.
class _RoomLinkField extends StatefulWidget {
  const _RoomLinkField({required this.onRoom});

  /// A pasted room link: its secret and the server it names (null: configured).
  final void Function(String secret, String? origin) onRoom;

  @override
  State<_RoomLinkField> createState() => _RoomLinkFieldState();
}

class _RoomLinkFieldState extends State<_RoomLinkField> {
  final TextEditingController _controller = TextEditingController();
  bool _invalid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _changed(String text) {
    final room = roomFromText(text);
    if (room != null) {
      widget.onRoom(room.secret, room.origin);
      return;
    }
    if (_invalid) setState(() => _invalid = false);
  }

  void _submit(String text) {
    final room = roomFromText(text);
    if (room != null) {
      widget.onRoom(room.secret, room.origin);
    } else if (text.trim().isNotEmpty) {
      setState(() => _invalid = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return TextField(
      controller: _controller,
      style: TextStyle(color: _tk(context).mist),
      keyboardType: TextInputType.url,
      autocorrect: false,
      textInputAction: TextInputAction.go,
      onChanged: _changed,
      onSubmitted: _submit,
      contextMenuBuilder: (context, state) => SystemContextMenu.isSupportedByField(state)
          ? SystemContextMenu.editableText(editableTextState: state)
          : AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
      decoration: InputDecoration(
        prefixIcon: Icon(Icons.link, color: _tk(context).muted),
        hintText: l.roomsLinkHint,
        hintStyle: TextStyle(color: _tk(context).muted),
        errorText: _invalid ? l.roomsLinkInvalid : null,
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({
    required this.room,
    required this.current,
    required this.nameFor,
    required this.onOpen,
    required this.onForget,
  });

  final RecentRoom room;
  final bool current;
  final String Function(RecentRoom room, String seed) nameFor;
  final VoidCallback onOpen;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final title = room.seeds.isEmpty ? l.roomsUnnamed : room.seeds.map((seed) => nameFor(room, seed)).join(', ');
    final when = relativeTime(l, DateTime.now().difference(room.lastEntered));
    final tile = ListTile(
      contentPadding: current ? const EdgeInsets.only(left: 12, right: 8) : EdgeInsets.zero,
      onTap: onOpen,
      leading: Icon(current ? Icons.place : Icons.history,
          color: current ? _tk(context).beacon : _tk(context).muted),
      title: Text(title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: _tk(context).mist,
              fontSize: 15,
              fontWeight: current ? FontWeight.w600 : FontWeight.normal)),
      // A room on another server says which, so it is never mistaken for one
      // on the official server.
      subtitle: Text(
          AppConfig.isOfficial(room.origin) ? when : '$when · ${AppConfig.hostOf(room.origin)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: AppConfig.isOfficial(room.origin) ? _tk(context).muted : _tk(context).signal, fontSize: 12)),
      // The open room cannot be forgotten from here, so it carries a badge
      // where the others have their close button.
      trailing: current
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: _tk(context).beacon, borderRadius: BorderRadius.circular(999)),
              child: Text(l.roomsCurrent,
                  style: TextStyle(
                      color: _tk(context).sheetBg, fontSize: 11, fontWeight: FontWeight.w700)),
            )
          : IconButton(
              tooltip: l.roomsForget,
              icon: Icon(Icons.close, color: _tk(context).muted, size: 20),
              onPressed: onForget,
            ),
    );
    if (!current) return tile;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: _tk(context).beacon.withValues(alpha: 0.12),
        border: Border.all(color: _tk(context).beacon.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(type: MaterialType.transparency, child: tile),
    );
  }
}



/// "just now" up to "n days ago", in the app's own words. Placeholders are
/// strings on purpose, matching the web (see scripts/i18n-to-arb.ts).
String relativeTime(L l, Duration d) {
  if (d.inSeconds < 60) return l.justNow;
  if (d.inMinutes < 60) return l.minsAgo('${d.inMinutes}');
  if (d.inHours < 48) return l.hoursAgo('${d.inHours}');
  return l.daysAgo('${d.inDays}');
}

Future<void> showParticipantsSheet(
  BuildContext context,
  RoomController controller,
  void Function(String seed) onGoTo,
) =>
    _sheet<void>(
      context,
      builder: (context) {
        final l = L.of(context);
        final roster = controller.roster();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.participantsTitle, style: _h2(context)),
            const SizedBox(height: 4),
            Text(
              controller.offlineSharers > 0
                  ? l.hereActiveOffline('${controller.presence}', '${controller.offlineSharers}')
                  : l.here('${controller.presence}'),
              style: _body(context),
            ),
            const SizedBox(height: 8),
            if (roster.isEmpty)
              Text(l.noSharers, style: _body(context))
            else
              for (final r in roster)
                DecoratedBox(
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: _tk(context).hair))),
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                      onGoTo(r.seed);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
                      child: Row(
                        children: [
                          Opacity(
                            opacity: r.offline ? 0.5 : 1,
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: r.offline
                                    ? Color.lerp(colorFromHue(r.identity.hue), _tk(context).muted, 0.85)
                                    : colorFromHue(r.identity.hue),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.identity.name,
                                  style: TextStyle(
                                    color: r.offline ? _tk(context).muted : _tk(context).mist,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (r.entry.message != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '💬 ${r.entry.message}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: _tk(context).muted, fontSize: 12.5),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (r.offline)
                            Text(
                              l.offlineStatus.toUpperCase(),
                              style: TextStyle(
                                color: _tk(context).signal,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.35,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            if (controller.watchers > 0) ...[
              const SizedBox(height: 12),
              Text(l.watchingLine('${controller.watchers}'),
                  style: TextStyle(color: _tk(context).muted, fontSize: 13)),
            ],
          ],
        );
      },
    );
