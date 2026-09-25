/// Modal sheets: the entry gate, the privacy explainer, the legal page, the
/// rename dialog and the invalid-link notice. Port of the sheet layer in
/// `client/src/ui.ts`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/recent_rooms.dart';
import '../../l10n/app_localizations.dart';
import '../../util/markup.dart';

const Color _sheetBg = Color(0xFF12161D);

Future<T?> _sheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
}) =>
    showModalBottomSheet<T>(
      context: context,
      backgroundColor: _sheetBg,
      isScrollControlled: true,
      isDismissible: dismissible,
      enableDrag: dismissible,
      showDragHandle: dismissible,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (context) => PopScope(
        canPop: dismissible,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
            child: SingleChildScrollView(child: builder(context)),
          ),
        ),
      ),
    );

TextStyle get _body => const TextStyle(color: Colors.white70, fontSize: 14, height: 1.45);
TextStyle get _h2 =>
    const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700);

Widget _fact(String markup, {bool warn = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 10),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: warn ? const Color(0xFFFBBF24) : const Color(0xFF4ADE80),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(child: MarkupText(markup, style: _body)),
        ],
      ),
    );

/// The entry gate. Nothing has touched the network when this opens, and it
/// cannot be dismissed without a decision: becoming present is visible to the
/// whole room, so it must be deliberate.
Future<void> showWelcomeSheet(BuildContext context) async {
  await _sheet<void>(
    context,
    dismissible: false,
    builder: (context) {
      final l = L.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 14),
          Text(l.welcomeTitle, style: _h2),
          const SizedBox(height: 10),
          Text(l.welcomeIntro, style: _body),
          const SizedBox(height: 16),
          _fact(l.welcomeFact1),
          _fact(l.welcomeFact2),
          _fact(l.welcomeFact3),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: const Color(0xFFF5B301),
                foregroundColor: const Color(0xFF17120D),
              ),
              child: Text(l.welcomeCta,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      );
    },
  );
}

/// A hand-edited or truncated link. Room links are generated; they cannot be
/// typed, so there is nothing for the user to correct.
Future<void> showInvalidLinkSheet(BuildContext context) => _sheet<void>(
      context,
      dismissible: false,
      builder: (context) {
        final l = L.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Text(l.invalidTitle, style: _h2),
            const SizedBox(height: 10),
            Text(l.invalidBody, style: _body),
            const SizedBox(height: 18),
          ],
        );
      },
    );

Future<void> showInfoSheet(BuildContext context) => _sheet<void>(
      context,
      builder: (context) {
        final l = L.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.infoTitle, style: _h2),
            const SizedBox(height: 10),
            MarkupText(l.infoIntro, style: _body),
            const SizedBox(height: 14),
            _fact(l.infoFact1),
            _fact(l.infoFact2),
            _fact(l.infoFact3),
            _fact(l.infoFactRecent),
            _fact(l.infoFact4, warn: true),
            _fact(l.infoFact5, warn: true),
            const SizedBox(height: 6),
            Text(
              l.mapCredits('Protomaps', 'OpenStreetMap'),
              style: const TextStyle(color: Colors.white38, fontSize: 12),
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

/// Impressum (§ 5 DDG) and Datenschutzerklärung (Art. 13 DSGVO), German-only as
/// is conventional for a German-operated service, and kept in step with what the
/// app actually does.
///
/// It deliberately differs from the web page in two ways. The app's code is
/// bundled rather than delivered per page load, so the web's "a compromised
/// server could ship different JavaScript" caveat does not apply here. And the
/// location section describes what the app actually does, including background
/// behaviour, which the browser cannot do at all.
///
/// Any change to how location is collected MUST be made here in the same commit.
/// A disclosure that lags the code by even one release is a false statement.
///
/// The `[…]` placeholders mark exactly what has to be filled in before any
/// public release. "In Entwicklung" stops being an exemption the moment the
/// service is publicly reachable.
Future<void> showLegalSheet(BuildContext context) => _sheet<void>(
      context,
      builder: (context) {
        Widget p(String markup) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: MarkupText(markup, style: _body),
            );
        Widget ph(String text) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(text,
                  style: const TextStyle(
                      color: Color(0xFFFBBF24), fontSize: 13, fontStyle: FontStyle.italic)),
            );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Impressum', style: _h2),
            const SizedBox(height: 10),
            p('Angaben gemäß § 5 DDG (Digitale-Dienste-Gesetz).'),
            p('<strong>Hinweis:</strong> HereBee befindet sich in aktiver Entwicklung und wird '
                'derzeit nicht öffentlich betrieben. Solange der Dienst nicht öffentlich erreichbar '
                'ist, besteht keine Impressumspflicht. Vor der öffentlichen Bereitstellung wird hier '
                'die vollständige Anbieterkennzeichnung mit ladungsfähiger Anschrift ergänzt.'),
            p('<strong>Diensteanbieter:</strong>'),
            ph('[Name – wird vor Veröffentlichung ergänzt]'),
            ph('[Ladungsfähige Anschrift – wird vor Veröffentlichung ergänzt]'),
            p('<strong>Kontakt:</strong>'),
            ph('[E-Mail – wird vor Veröffentlichung ergänzt]'),
            const SizedBox(height: 14),
            Text('Datenschutzerklärung', style: _h2),
            const SizedBox(height: 10),
            p('<strong>Verantwortlicher</strong> im Sinne der DSGVO ist der im Impressum genannte '
                'Diensteanbieter.'),
            p('<strong>Grundprinzip.</strong> HereBee ist bewusst datensparsam gebaut. Ein '
                '256-Bit-Schlüssel steckt ausschließlich im Link hinter <code>#</code> und wird nie '
                'an den Server übertragen. Die App leitet daraus die Raum-Kennung und einen '
                'AES-256-GCM-Schlüssel ab; alle Koordinaten und Anzeigenamen werden auf dem Gerät '
                'verschlüsselt. Der Server (Relay) leitet nur undurchsichtige, verschlüsselte '
                'Datenpakete weiter und kann sie nicht entschlüsseln.'),
            p('<strong>App statt Browser.</strong> Der Programmcode dieser App ist installiert und '
                'wird nicht bei jedem Aufruf vom Server geladen. Der Vorbehalt der Web-Version, dass '
                'ein kompromittierter Server künftig anderen Code ausliefern könnte, entfällt damit. '
                'Aktualisierungen kommen ausschließlich über den jeweiligen App-Store bzw. das '
                'signierte Installationspaket.'),
            p('<strong>Welche Daten verarbeitet werden:</strong>'),
            _fact('<strong>IP-Adresse</strong> – vorübergehend, um die WebSocket-Verbindung '
                'aufzubauen und die Zahl gleichzeitiger Verbindungen pro IP zu begrenzen '
                '(Missbrauchsschutz). Rechtsgrundlage: Art. 6 Abs. 1 lit. f DSGVO. Die Anwendung '
                'selbst speichert die IP nicht. Da die Kartenkacheln vom selben Server geladen '
                'werden, kann dieser anhand der angefragten Kacheln grob erkennen, welche Region du '
                'ansiehst; die Koordinaten selbst bleiben Ende-zu-Ende-verschlüsselt.'),
            _fact('<strong>Verschlüsselte Standort- und Namensdaten</strong> – werden nur '
                'weitergeleitet, nicht gespeichert und sind für den Betreiber nicht lesbar.'),
            _fact('<strong>Raumzustand</strong> – ausschließlich im Arbeitsspeicher; wird gelöscht, '
                'sobald der letzte Teilnehmer die Verbindung trennt. Keine Datenbank, keine '
                'Historie, keine Speicherung von Koordinaten oder Namen.'),
            p('<strong>Standortfreigabe.</strong> Die App greift auf die Ortungsdienste des '
                'Geräts zu, <strong>nur</strong> nachdem du die Berechtigung erteilt und das Teilen '
                'ausdrücklich eingeschaltet hast. Rechtsgrundlage ist deine Einwilligung '
                '(Art. 6 Abs. 1 lit. a DSGVO); du kannst sie jederzeit im Betriebssystem oder über '
                'den Stopp-Knopf widerrufen. Die Koordinaten werden auf dem Gerät verschlüsselt und '
                'sind für den Server nie sichtbar.'),
            p('<strong>Im Hintergrund.</strong> Das Teilen läuft weiter, wenn du das Display sperrst '
                'oder die App in den Hintergrund legst — sonst wäre die Funktion nutzlos. Das ist '
                'sichtbar: Android zeigt dauerhaft eine Benachrichtigung mit einem Stopp-Knopf, iOS '
                'die blaue Standortanzeige. Beendest du die App, indem du sie wegwischst, endet auch '
                'das Teilen. Angefordert wird ausschließlich die Berechtigung „bei App-Nutzung"; die '
                'weitergehende Berechtigung „immer erlauben" verlangt die App nicht.'),
            p('<strong>Ortungsquelle.</strong> Verwendet werden die Ortungsdienste des '
                'Betriebssystems: unter Android der System-Dienst <code>LocationManager</code> '
                '(GPS und Netzwerk), unter iOS CoreLocation. Google Play Services werden nicht '
                'eingebunden; die App läuft daher auch auf Geräten ohne Google-Dienste. Welche Daten '
                'das Betriebssystem selbst dabei verarbeitet, liegt außerhalb des Einflusses dieser '
                'App und richtet sich nach den Angaben des jeweiligen Herstellers.'),
            p('<strong>Auf dem Gerät gespeichert.</strong> Nur eine zufällige Kennung für die eigene '
                'Bienen-Identität, ein ebenso zufälliges Token für die Wiederverbindung und die '
                'Namen, die du anderen Teilnehmern selbst gegeben hast. Keine Standorthistorie, '
                'keine Protokolle, keine Liste besuchter Räume. Diese Daten verlassen das Gerät '
                'nicht und werden beim Löschen der App-Daten entfernt.'),
            p('<strong>Hosting.</strong> Die App wird auf einem Server in Deutschland betrieben. Der '
                'Hosting-Anbieter'),
            ph('[Anbieter, Anschrift – wird vor Veröffentlichung ergänzt]'),
            p('kann im Rahmen des Serverbetriebs Infrastruktur-/Server-Logs (einschließlich '
                'IP-Adresse) im Auftrag des Verantwortlichen verarbeiten; hierzu besteht ein '
                'Auftragsverarbeitungsvertrag nach Art. 28 DSGVO. Rechtsgrundlage: Art. 6 Abs. 1 '
                'lit. f DSGVO.'),
            p('<strong>Keine Cookies, kein Tracking.</strong> HereBee setzt keine Cookies, nutzt '
                'keine Analyse-, Absturzberichts- oder Tracking-Dienste und bindet keine fremden '
                'CDNs ein. Karten, Schriften und Symbole werden selbst gehostet. Die App enthält '
                'keine Bibliotheken von Google Play Services oder vergleichbaren Drittanbietern.'),
            p('<strong>Speicherdauer.</strong> Über die aktive Sitzung hinaus speichert die Anwendung '
                'nichts. Für etwaige Infrastruktur-Logs gilt die Aufbewahrungsfrist des '
                'Hosting-Anbieters.'),
            p('<strong>Deine Rechte.</strong> Du hast das Recht auf Auskunft, Berichtigung, Löschung, '
                'Einschränkung, Datenübertragbarkeit und Widerspruch (Art. 15–22 DSGVO). Da über die '
                'Sitzung hinaus keine personenbezogenen Daten gespeichert werden, ergibt eine '
                'Auskunft in der Regel, dass keine gespeicherten Daten vorliegen. Außerdem besteht '
                'ein Beschwerderecht bei einer Aufsichtsbehörde (Art. 77 DSGVO).'),
            p('<strong>Empfänger.</strong> Eine Weitergabe an Dritte erfolgt nicht, außer an den '
                'Hosting-Anbieter als Auftragsverarbeiter. Es findet keine Datenübermittlung in '
                'Drittländer statt.'),
            ph('Stand: [Datum – bei Veröffentlichung ergänzen]'),
          ],
        );
      },
    );

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
          Text(l.renameTitle, style: _h2),
          const SizedBox(height: 8),
          Text(l.renameBody, style: _body),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            autofocus: true,
            maxLength: 40,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: l.renamePlaceholder,
              hintStyle: const TextStyle(color: Colors.white30),
              border: const OutlineInputBorder(),
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
  const RoomsChoice(this.secret);
  final String? secret;
}

/// Recent rooms and the way to a fresh one. Opened from the brand chip.
///
/// Entries are titled by the peers met there, named exactly as on the map
/// (derived locally, in the current language), because a room has no name of
/// its own and a bare date tells you nothing.
Future<RoomsChoice?> showRoomsSheet(
  BuildContext context, {
  required RecentRooms recent,
  required String currentSecret,
  required String Function(String seed) nameFor,
}) =>
    _sheet<RoomsChoice>(
      context,
      builder: (context) {
        final l = L.of(context);
        return ListenableBuilder(
          listenable: recent,
          builder: (context, _) {
            final rooms = recent.rooms;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.roomsTitle, style: _h2),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(const RoomsChoice(null)),
                  icon: const Icon(Icons.add),
                  label: Text(l.roomsNew),
                ),
                if (rooms.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(l.roomsRecent,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12, letterSpacing: 0.6)),
                  const SizedBox(height: 4),
                  for (final room in rooms)
                    _RoomTile(
                      room: room,
                      current: room.secret == currentSecret,
                      nameFor: nameFor,
                      onOpen: () => Navigator.of(context).pop(RoomsChoice(room.secret)),
                      onForget: () => recent.forget(room.secret),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: recent.forgetAll,
                      child: Text(l.roomsForgetAll),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(l.roomsNote, style: _body.copyWith(fontSize: 12, color: Colors.white54)),
              ],
            );
          },
        );
      },
    );

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
  final String Function(String seed) nameFor;
  final VoidCallback onOpen;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final title = room.seeds.isEmpty ? l.roomsUnnamed : room.seeds.map(nameFor).join(', ');
    final when = relativeTime(l, DateTime.now().difference(room.lastEntered));
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onOpen,
      leading: Icon(current ? Icons.place : Icons.history,
          color: current ? const Color(0xFFF5B301) : Colors.white54),
      title: Text(title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 15)),
      subtitle: Text(current ? '$when · ${l.roomsCurrent}' : when,
          style: const TextStyle(color: Colors.white54, fontSize: 12)),
      trailing: IconButton(
        tooltip: l.roomsForget,
        icon: const Icon(Icons.close, color: Colors.white54, size: 20),
        onPressed: onForget,
      ),
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
