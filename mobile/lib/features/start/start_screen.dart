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
  final String Function(String seed) nameFor;
  final void Function(RoomsChoice choice) onChoose;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ink,
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
                  const Padding(
                    padding: EdgeInsets.only(bottom: 26),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: 'Here'),
                        TextSpan(text: 'Bee', style: TextStyle(fontWeight: FontWeight.w800, color: beacon)),
                      ]),
                      style: TextStyle(color: mist, fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5),
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
