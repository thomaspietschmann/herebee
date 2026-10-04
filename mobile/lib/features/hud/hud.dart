/// The floating chrome over the map: brand + connection chip, the roster, and
/// the bottom dock. Port of the HUD in `client/index.html` and
/// `client/src/ui.ts`.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../l10n/app_localizations.dart';
import '../map/bee_marker.dart';
import '../room/room_controller.dart';
import '../sheets/sheets.dart';
import '../../ui/tokens.dart';

const _fitAllSvg =
    '<svg viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="1.9"><circle cx="12" cy="12" r="9.5"/>'
    '<g fill="#000" stroke="none"><circle cx="9" cy="8.6" r="1.7"/><circle cx="15.6" cy="10.4" r="1.7"/>'
    '<circle cx="10.6" cy="15.6" r="1.7"/></g></svg>';

class Hud extends StatelessWidget {
  const Hud({
    required this.controller,
    required this.onFitAll,
    required this.onGoTo,
    required this.onShareLink,
    required this.onToggleShare,
    required this.onInfo,
    required this.onRooms,
    this.brandKey,
    this.hintKey,
    this.controlsKey,
    super.key,
  });

  final RoomController controller;
  final VoidCallback onFitAll;
  final void Function(String seed) onGoTo;
  final VoidCallback onShareLink;
  final VoidCallback onToggleShare;
  final VoidCallback onInfo;

  /// Opens the rooms sheet: recent rooms and a fresh one.
  final VoidCallback onRooms;

  final GlobalKey? brandKey;
  final GlobalKey? hintKey;
  final GlobalKey? controlsKey;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Stack(
      children: [
        Positioned(
          top: math.max(14, padding.top),
          left: 14,
          child: _ConnChip(key: brandKey, state: controller.connection, onTap: onRooms),
        ),
        if (controller.entered && (controller.presence >= 2 || controller.peers.entries.isNotEmpty))
          Positioned(
            top: math.max(14, padding.top),
            right: 14,
            child: SizedBox(
              height: 46,
              child: _RosterButton(controller: controller, onFitAll: onFitAll, onGoTo: onGoTo),
            ),
          ),
        Positioned(
          left: 14,
          right: 14,
          bottom: math.max(16, padding.bottom),
          child: _Dock(
            onShareLink: onShareLink,
            onToggleShare: onToggleShare,
            onInfo: onInfo,
            sharing: controller.sharing,
            busy: controller.toggling,
            hintKey: hintKey,
            controlsKey: controlsKey,
          ),
        ),
      ],
    );
  }
}

const double _controlHeight = 48;

class _ConnChip extends StatelessWidget {
  const _ConnChip({required this.state, required this.onTap, super.key});
  final LinkState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final t = HereBeeTokens.of(context);
    final (color, text) = switch (state) {
      LinkState.on => (t.beacon, l.connOn),
      LinkState.off => (t.signal, l.connOff),
      LinkState.connecting => (t.muted, l.connConnecting),
    };
    // The brand chip doubles as the way to your rooms. A dedicated button
    // would cost HUD space; the chip is already the one fixed landmark.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.inkGlass,
        borderRadius: BorderRadius.circular(t.pillRadius),
        border: Border.all(color: t.outline),
        boxShadow: [...t.shadow, ...t.chromeGlow],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const ValueKey('rooms-chip'),
          borderRadius: BorderRadius.circular(t.pillRadius),
          onTap: onTap,
          child: Semantics(
            button: true,
            label: l.roomsTitle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 7, 14, 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      SvgPicture.asset('assets/brand/herebee-pill-mark.svg', width: 30, height: 30),
                      Positioned(
                        right: -3,
                        bottom: -3,
                        // The dot carries the state for screen readers, as its
                        // own node, so a change is announced without re-reading
                        // the brand name with it.
                        child: Semantics(
                          container: true,
                          liveRegion: true,
                          label: text,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(color: t.ink, width: 2),
                              boxShadow: [
                                if (state == LinkState.on) BoxShadow(color: t.beacon, blurRadius: 8),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 9),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: t.label('Here')),
                        TextSpan(
                          text: t.label('Bee'),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: t.beacon,
                            shadows: t.chromeGlow.isEmpty ? null : [Shadow(color: t.beacon, blurRadius: 10)],
                          ),
                        ),
                      ],
                    ),
                    style: TextStyle(
                      color: t.mist,
                      fontSize: t.uppercase ? 13 : 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: t.uppercase ? 1.8 : -0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RosterButton extends StatelessWidget {
  const _RosterButton({
    required this.controller,
    required this.onFitAll,
    required this.onGoTo,
  });

  final RoomController controller;
  final VoidCallback onFitAll;
  final void Function(String seed) onGoTo;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final t = HereBeeTokens.of(context);
    final roster = controller.roster();
    final sharerPips = roster.take(5).toList();
    final hollow = math.min(controller.watchers, math.max(0, 5 - sharerPips.length));
    final pips = <Widget>[
      for (final r in sharerPips)
        _Pip(color: colorFromHue(r.identity.hue), offline: r.offline),
      for (var i = 0; i < hollow; i++) const _Pip(),
    ];
    final count = controller.offlineSharers > 0
        ? l.hereActiveOffline('${controller.presence}', '${controller.offlineSharers}')
        : l.here('${controller.presence}');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _GlassButton(
          onTap: () => _openRoster(context),
          shape: t.pill(BorderSide(color: t.outline)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pips.isNotEmpty) ...[
                  for (var i = 0; i < pips.length; i++)
                    Align(widthFactor: i == pips.length - 1 ? 1 : 12 / 20, child: pips[i]),
                  const SizedBox(width: 9),
                ],
                Text(count,
                    style: TextStyle(color: t.mist, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          button: true,
          label: l.fitAll,
          excludeSemantics: true,
          child: _GlassButton(
            onTap: onFitAll,
            shape: CircleBorder(side: BorderSide(color: t.outline)),
            child: SizedBox(
              width: 46,
              height: 46,
              child: Center(
                child: SvgPicture.string(
                  _fitAllSvg,
                  width: 23,
                  height: 23,
                  colorFilter: ColorFilter.mode(t.mist, BlendMode.srcIn),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          button: true,
          toggled: controller.bubblesVisible,
          label: controller.bubblesVisible ? l.bubblesHide : l.bubblesShow,
          excludeSemantics: true,
          child: _GlassButton(
            key: const ValueKey('bubbles-toggle'),
            onTap: () => controller.setBubblesVisible(!controller.bubblesVisible),
            shape: CircleBorder(side: BorderSide(color: t.outline)),
            child: SizedBox(
              width: 46,
              height: 46,
              child: Center(
                child: Icon(
                  controller.bubblesVisible ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded,
                  color: controller.bubblesVisible ? t.mist : t.muted,
                  size: 21,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _openRoster(BuildContext context) => showParticipantsSheet(context, controller, onGoTo);
}

class _Beat extends StatefulWidget {
  const _Beat();

  @override
  State<_Beat> createState() => _BeatState();
}

class _BeatState extends State<_Beat> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final signal = HereBeeTokens.of(context).signal;
          final t = Curves.easeOut.transform((_c.value / 0.7).clamp(0.0, 1.0));
          return Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: signal,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: signal.withValues(alpha: 0.55 * (1 - t)), spreadRadius: 9 * t),
              ],
            ),
          );
        },
      );
}

class _Pip extends StatelessWidget {
  const _Pip({this.color, this.offline = false});

  final Color? color;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final t = HereBeeTokens.of(context);
    final watcher = color == null;
    final fill = watcher ? t.ink2 : (offline ? Color.lerp(color, t.muted, 0.85)! : color!);
    return Opacity(
      opacity: offline ? 0.5 : 1,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: Border.all(color: watcher ? t.muted : t.ink, width: 2),
        ),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.onTap, required this.shape, required this.child, super.key});

  final VoidCallback onTap;
  final ShapeBorder shape;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = HereBeeTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(shape is CircleBorder ? 999 : t.pillRadius),
        boxShadow: [...t.shadow, ...t.chromeGlow],
      ),
      child: Material(
        color: t.inkGlass,
        shape: shape,
        child: InkWell(customBorder: shape, onTap: onTap, child: child),
      ),
    );
  }
}

class _Dock extends StatelessWidget {
  const _Dock({
    required this.onShareLink,
    required this.onToggleShare,
    required this.onInfo,
    required this.sharing,
    required this.busy,
    this.hintKey,
    this.controlsKey,
  });

  final VoidCallback onShareLink;
  final VoidCallback onToggleShare;
  final VoidCallback onInfo;
  final bool sharing;

  /// A start or stop is in flight. The control is disabled rather than hidden,
  /// so the button does not move under the user's finger.
  final bool busy;
  final GlobalKey? hintKey;
  final GlobalKey? controlsKey;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final t = HereBeeTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IgnorePointer(
          ignoring: sharing,
          child: AnimatedOpacity(
            opacity: sharing ? 0 : 1,
            duration: const Duration(milliseconds: 400),
            child: ConstrainedBox(
              key: hintKey,
              constraints: const BoxConstraints(maxWidth: 440),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: t.inkGlass,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: t.hair),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Text(
                    l.hint,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.muted, fontSize: 12, height: 1.45),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        FittedBox(
          key: controlsKey,
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The share glyph of the platform people are on: iOS's box with
              // an arrow, Android's three connected dots.
              _DockButton(
                key: const ValueKey('share-link'),
                onTap: onShareLink,
                round: true,
                semanticLabel: l.shareLink,
                child: Icon(
                  switch (Theme.of(context).platform) {
                    TargetPlatform.iOS || TargetPlatform.macOS => Icons.ios_share,
                    _ => Icons.share,
                  },
                  color: t.dockIcon,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              // The primary action. It reads "Stop sharing" while active, so
              // turning it off is never more than one tap away.
              _DockButton(
                onTap: busy ? null : onToggleShare,
                primary: true,
                sharing: sharing,
                child: Text(t.label(sharing ? l.stopSharing : l.shareLocation), maxLines: 1),
              ),
              const SizedBox(width: 10),
              // Settings, and the privacy explainer below them.
              _DockButton(
                key: const ValueKey('settings'),
                onTap: onInfo,
                round: true,
                semanticLabel: l.infoAria,
                child: Icon(Icons.settings_outlined, color: t.dockIcon, size: 22),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.onTap,
    required this.child,
    this.primary = false,
    this.sharing = false,
    this.round = false,
    this.semanticLabel,
    super.key,
  });

  final VoidCallback? onTap;
  final Widget child;
  final bool primary;
  final bool sharing;
  final bool round;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = HereBeeTokens.of(context);
    final filled = primary && !sharing;
    final Color fill = filled ? t.signal : (primary ? t.ink2 : t.inkGlass);
    final Color fg = filled ? t.onSignal : t.mist;
    final Color edge = filled ? Colors.transparent : (primary ? t.sharingBorder : t.outline);
    final shape = round ? t.round(BorderSide(color: edge)) : t.pill(BorderSide(color: edge));
    final glow = filled ? t.primaryGlow : t.chromeGlow;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(t.pillRadius),
          boxShadow: [...t.shadow, ...glow],
        ),
        child: Material(
          color: fill,
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: onTap,
            child: Opacity(
              opacity: onTap == null ? 0.6 : 1,
              child: SizedBox(
                height: _controlHeight,
                width: round ? _controlHeight : null,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: round ? 0 : (primary ? 26 : 22)),
                  child: Center(
                    widthFactor: 1,
                    child: DefaultTextStyle.merge(
                      style: TextStyle(
                        color: fg,
                        fontSize: t.uppercase ? 13 : 15,
                        fontWeight: t.uppercase && filled ? FontWeight.w800 : FontWeight.w600,
                        letterSpacing: t.uppercase ? 1 : -0.15,
                      ),
                      child: primary && sharing
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [const _Beat(), const SizedBox(width: 9), child],
                            )
                          : child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
