/// Shown on a plain launch when rooms are remembered. The app does not decide
/// for the user which room to be in: it asks, and only after that choice does
/// a room (and its entry gate) appear. With nothing remembered, main.dart skips
/// this screen and mints a fresh room directly, as before.
library;

import 'package:flutter/material.dart';

import '../../core/recent_rooms.dart';
import '../sheets/sheets.dart';
import '../../ui/tokens.dart';

class StartScreen extends StatelessWidget {
  const StartScreen({
    required this.recent,
    required this.nameFor,
    required this.onChoose,
    super.key,
  });

  final RecentRooms recent;
  final String Function(RecentRoom room, String seed) nameFor;
  final void Function(RoomsChoice choice) onChoose;

  @override
  Widget build(BuildContext context) {
    final t = HereBeeTokens.of(context);
    return Scaffold(
      backgroundColor: t.ink,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 160,
                      height: 160,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: const [
                          BoxShadow(color: Color(0x6B000000), blurRadius: 50, offset: Offset(0, 18)),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset('assets/brand/herebee-logo.png', fit: BoxFit.cover),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 26),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: t.label('Here')),
                        TextSpan(
                            text: t.label('Bee'), style: TextStyle(fontWeight: FontWeight.w800, color: t.beacon)),
                      ]),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: t.mist,
                          fontSize: t.uppercase ? 22 : 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: t.uppercase ? 3 : -0.5),
                    ),
                  ),
                  RoomsPicker(recent: recent, nameFor: nameFor, onChoose: onChoose),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
