/// Modal sheets: the entry gate, the privacy explainer, the legal page, the
/// rename dialog and the invalid-link notice. Port of the sheet layer in
/// `client/src/ui.ts`.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/deep_links.dart';
import '../../core/recent_rooms.dart';
import '../map/bee_marker.dart';
import '../room/room_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/tokens.dart' as tokens;
import '../../util/markup.dart';

const Color _sheetBg = tokens.ink2;

Widget _panel(BuildContext context, Widget child, {required bool closable, EdgeInsets? padding}) =>
    DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tokens.panelRadius),
        boxShadow: tokens.shadow,
      ),
      child: Material(
        color: tokens.ink2,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.panelRadius),
          side: const BorderSide(color: tokens.hair),
        ),
        child: Stack(
          children: [
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
                    icon: const Text('×', style: TextStyle(color: tokens.muted, fontSize: 22, height: 1)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

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

TextStyle get _body => const TextStyle(color: tokens.muted, fontSize: 13.5, height: 1.55);
TextStyle get _h2 => const TextStyle(
    color: tokens.mist, fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.38);

Widget _fact(String markup, {bool warn = false}) => DecoratedBox(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: tokens.hair))),
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
                  color: warn ? tokens.signal : tokens.beacon,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Expanded(
              child: MarkupText(markup,
                  style: const TextStyle(color: tokens.mist, fontSize: 13, height: 1.5)),
            ),
          ],
        ),
      ),
    );

/// The entry gate. Nothing has touched the network when this opens, and it
/// cannot be dismissed without a decision: becoming present is visible to the
/// whole room, so it must be deliberate.
Future<void> showWelcomeSheet(BuildContext context) => _splash(
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
            Text(l.welcomeTitle, style: _h2, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(l.welcomeIntro, style: _body, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            _fact(l.welcomeFact1),
            _fact(l.welcomeFact2),
            _fact(l.welcomeFact3),
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
            Text(l.invalidTitle, style: _h2, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(l.invalidBody, style: _body, textAlign: TextAlign.center),
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
              style: const TextStyle(color: tokens.muted, fontSize: 12),
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
                      color: tokens.signal, fontSize: 13, fontStyle: FontStyle.italic)),
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
            p('<strong>Auf dem Gerät gespeichert.</strong> Eine zufällige Kennung für die eigene '
                'Bienen-Identität, die Namen, die du anderen Teilnehmern selbst gegeben hast, sowie '
                'pro Raum dein eigener Name und ob du ihn teilst. Außerdem die letzten fünf Räume, '
                'die du betreten hast, samt Schlüssel und den Bienen, die du dort getroffen hast – '
                'für drei Tage in der sicheren Ablage des Geräts (Keychain bzw. Keystore); jeder '
                'Eintrag lässt sich jederzeit löschen. Keine Standorthistorie, keine Protokolle.'),
            p('<strong>Was das Gerät verlässt.</strong> Die Bienen-Kennung und – nur wenn du es '
                'erlaubst – dein Name gehen Ende-zu-Ende-verschlüsselt an die anderen Teilnehmer '
                'des Raums; wer dich in mehreren Räumen trifft, kann deine Biene wiedererkennen. '
                'An den Server geht zusätzlich ein zufälliges Token für die Wiederverbindung, das '
                'nur im Arbeitsspeicher liegt und bei jedem App-Start neu erzeugt wird. Unter '
                'Android sind Sicherungen der App-Daten abgeschaltet; unter iOS können die '
                'Einstellungen der App (ohne die Raum-Schlüssel) Teil einer Geräte- oder '
                'iCloud-Sicherung sein. Beim Löschen der App werden alle Daten entfernt.'),
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
            p('<strong>Speicherdauer.</strong> Auf dem Server speichert die Anwendung über die aktive '
                'Sitzung hinaus nichts. Die Daten auf deinem Gerät bleiben, bis du sie löschst; '
                'gemerkte Räume verfallen nach drei Tagen von selbst. Für etwaige Infrastruktur-Logs '
                'gilt die Aufbewahrungsfrist des Hosting-Anbieters.'),
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
            style: const TextStyle(color: tokens.mist),
            decoration: InputDecoration(
              hintText: l.renamePlaceholder,
              hintStyle: const TextStyle(color: tokens.muted),
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
          Text(l.shareNameTitle, style: _h2),
          const SizedBox(height: 8),
          Text(l.shareNameBody(name), style: _body),
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
  const RoomsChoice(this.secret);
  final String? secret;
}

/// Recent rooms and the way to a fresh one. Opened from the brand chip.
Future<RoomsChoice?> showRoomsSheet(
  BuildContext context, {
  required RecentRooms recent,
  required String currentSecret,
  required String Function(String seed) nameFor,
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
  final String Function(String seed) nameFor;
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
            Text(l.roomsTitle, style: _h2),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => onChoose(const RoomsChoice(null)),
              icon: const Icon(Icons.add),
              label: Text(l.roomsNew),
            ),
            const SizedBox(height: 10),
            _RoomLinkField(onSecret: (secret) => onChoose(RoomsChoice(secret))),
            if (rooms.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(l.roomsRecent,
                  style: const TextStyle(color: tokens.muted, fontSize: 12, letterSpacing: 0.6)),
              const SizedBox(height: 4),
              for (final room in rooms)
                _RoomTile(
                  room: room,
                  current: room.secret == currentSecret,
                  nameFor: nameFor,
                  onOpen: () => onChoose(RoomsChoice(room.secret)),
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
            Text(l.roomsNote, style: _body.copyWith(fontSize: 12, color: tokens.muted)),
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
  const _RoomLinkField({required this.onSecret});

  final void Function(String secret) onSecret;

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
    final secret = secretFromText(text);
    if (secret != null) {
      widget.onSecret(secret);
      return;
    }
    if (_invalid) setState(() => _invalid = false);
  }

  void _submit(String text) {
    final secret = secretFromText(text);
    if (secret != null) {
      widget.onSecret(secret);
    } else if (text.trim().isNotEmpty) {
      setState(() => _invalid = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return TextField(
      controller: _controller,
      style: const TextStyle(color: tokens.mist),
      keyboardType: TextInputType.url,
      autocorrect: false,
      textInputAction: TextInputAction.go,
      onChanged: _changed,
      onSubmitted: _submit,
      contextMenuBuilder: (context, state) => SystemContextMenu.isSupportedByField(state)
          ? SystemContextMenu.editableText(editableTextState: state)
          : AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.link, color: tokens.muted),
        hintText: l.roomsLinkHint,
        hintStyle: const TextStyle(color: tokens.muted),
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
  final String Function(String seed) nameFor;
  final VoidCallback onOpen;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final title = room.seeds.isEmpty ? l.roomsUnnamed : room.seeds.map(nameFor).join(', ');
    final when = relativeTime(l, DateTime.now().difference(room.lastEntered));
    final tile = ListTile(
      contentPadding: current ? const EdgeInsets.only(left: 12, right: 8) : EdgeInsets.zero,
      onTap: onOpen,
      leading: Icon(current ? Icons.place : Icons.history,
          color: current ? _honey : tokens.muted),
      title: Text(title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: tokens.mist,
              fontSize: 15,
              fontWeight: current ? FontWeight.w600 : FontWeight.normal)),
      subtitle: Text(when, style: const TextStyle(color: tokens.muted, fontSize: 12)),
      // The open room cannot be forgotten from here, so it carries a badge
      // where the others have their close button.
      trailing: current
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: _honey, borderRadius: BorderRadius.circular(999)),
              child: Text(l.roomsCurrent,
                  style: const TextStyle(
                      color: _sheetBg, fontSize: 11, fontWeight: FontWeight.w700)),
            )
          : IconButton(
              tooltip: l.roomsForget,
              icon: const Icon(Icons.close, color: tokens.muted, size: 20),
              onPressed: onForget,
            ),
    );
    if (!current) return tile;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: _honey.withValues(alpha: 0.12),
        border: Border.all(color: _honey.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(type: MaterialType.transparency, child: tile),
    );
  }
}

const Color _honey = tokens.beacon;

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
            Text(l.participantsTitle, style: _h2),
            const SizedBox(height: 4),
            Text(
              controller.offlineSharers > 0
                  ? l.hereActiveOffline('${controller.presence}', '${controller.offlineSharers}')
                  : l.here('${controller.presence}'),
              style: _body,
            ),
            const SizedBox(height: 8),
            if (roster.isEmpty)
              Text(l.noSharers, style: _body)
            else
              for (final r in roster)
                DecoratedBox(
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: tokens.hair))),
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
                                    ? Color.lerp(colorFromHue(r.identity.hue), tokens.muted, 0.85)
                                    : colorFromHue(r.identity.hue),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              r.identity.name,
                              style: TextStyle(
                                color: r.offline ? tokens.muted : tokens.mist,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (r.offline)
                            Text(
                              l.offlineStatus.toUpperCase(),
                              style: const TextStyle(
                                color: tokens.signal,
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
                  style: const TextStyle(color: tokens.muted, fontSize: 13)),
            ],
          ],
        );
      },
    );
