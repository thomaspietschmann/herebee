import 'package:flutter/material.dart';

// The standard palette, mirroring the CSS custom properties in
// client/src/style.css (:root). Widgets read the active set through
// [HereBeeTokens.of]; these constants are its defaults.
const Color ink = Color(0xFF0E1116);
const Color ink2 = Color(0xFF171B22);
const Color inkGlass = Color(0xD90E1116);
const Color hair = Color(0x1AE8EDF2);
const Color mist = Color(0xFFE8EDF2);
const Color muted = Color(0xFF8A94A6);
const Color signal = Color(0xFFFF5A4D);
const Color onSignal = Color(0xFF1A0603);
const Color beacon = Color(0xFF34E1B4);

const List<BoxShadow> shadow = [BoxShadow(color: Color(0x80000000), blurRadius: 40, offset: Offset(0, 10))];

const double panelRadius = 20;

/// The colours, shapes and type of the app chrome, swapped as a whole by the
/// map style: [standard] over the light map, [dark] over the dark one and
/// [synthwave] over the synthwave map ("Grid Toxic"). Keep [dark] and
/// [synthwave] in step with the matching `:root[data-map-theme=...]` blocks in
/// client/src/style.css.
@immutable
class HereBeeTokens extends ThemeExtension<HereBeeTokens> {
  const HereBeeTokens({
    required this.ink,
    required this.ink2,
    required this.inkGlass,
    required this.hair,
    required this.mist,
    required this.muted,
    required this.signal,
    required this.onSignal,
    required this.beacon,
    required this.outline,
    required this.sheetBg,
    required this.shadow,
    required this.chromeGlow,
    required this.primaryGlow,
    required this.sheetGlow,
    required this.pillRadius,
    required this.panelRadius,
    required this.toastBg,
    required this.toastFg,
    required this.dockIcon,
    required this.sharingBorder,
    required this.panelBorder,
    this.fontFamily,
    this.fontFamilyFallback,
    this.uppercase = false,
    this.gridLine,
    this.gridWash,
    this.panelGridLine,
  });

  /// The app's own look, over the light map.
  static const HereBeeTokens standard = HereBeeTokens(
    // Literal values (the top-level constants above) because the field names
    // shadow them inside this class.
    ink: Color(0xFF0E1116),
    ink2: Color(0xFF171B22),
    inkGlass: Color(0xD90E1116),
    hair: Color(0x1AE8EDF2),
    mist: Color(0xFFE8EDF2),
    muted: Color(0xFF8A94A6),
    signal: Color(0xFFFF5A4D),
    onSignal: Color(0xFF1A0603),
    beacon: Color(0xFF34E1B4),
    outline: Color(0x1AE8EDF2),
    sheetBg: Color(0xFF171B22),
    shadow: [BoxShadow(color: Color(0x80000000), blurRadius: 40, offset: Offset(0, 10))],
    chromeGlow: [],
    primaryGlow: [],
    sheetGlow: [],
    pillRadius: 999,
    panelRadius: 20,
    toastBg: Color(0xFFE8EDF2),
    toastFg: Color(0xFF0E1116),
    dockIcon: Color(0xFFE8EDF2),
    sharingBorder: Color(0x1AE8EDF2),
    panelBorder: Color(0x1AE8EDF2),
  );

  static const HereBeeTokens dark = HereBeeTokens(
    ink: Color(0xFF1C222B),
    ink2: Color(0xFF262D38),
    inkGlass: Color(0xE6262D38),
    hair: Color(0x2EE8EDF2),
    mist: Color(0xFFE8EDF2),
    muted: Color(0xFF9AA4B5),
    signal: Color(0xFFFF5A4D),
    onSignal: Color(0xFF1A0603),
    beacon: Color(0xFF34E1B4),
    outline: Color(0x40E8EDF2),
    sheetBg: Color(0xFF262D38),
    shadow: [BoxShadow(color: Color(0x80000000), blurRadius: 40, offset: Offset(0, 10))],
    chromeGlow: [],
    primaryGlow: [],
    sheetGlow: [],
    pillRadius: 999,
    panelRadius: 20,
    toastBg: Color(0xFFE8EDF2),
    toastFg: Color(0xFF0E1116),
    dockIcon: Color(0xFFE8EDF2),
    sharingBorder: Color(0x40E8EDF2),
    panelBorder: Color(0x2EE8EDF2),
  );

  /// Near-black glass, green outlines and accents, a pink primary with a
  /// green ring and a faint pink floor grid over the bottom of the map. Shapes
  /// and type stay those of [standard].
  static const HereBeeTokens synthwave = HereBeeTokens(
    ink: Color(0xFF010403),
    ink2: Color(0xFF06100B),
    inkGlass: Color(0xD6010604),
    hair: Color(0x6639FF14),
    mist: Color(0xFFEEFFF2),
    muted: Color(0xFF8FD0A2),
    signal: Color(0xFFFF2BD6),
    onSignal: Color(0xFF1A0016),
    beacon: Color(0xFF39FF14),
    outline: Color(0xBF39FF14),
    sheetBg: Color(0xFF030A06),
    shadow: [BoxShadow(color: Color(0x99000000), blurRadius: 40, offset: Offset(0, 10))],
    chromeGlow: [BoxShadow(color: Color(0x6B39FF14), blurRadius: 16)],
    primaryGlow: [
      BoxShadow(color: Color(0xFF39FF14), spreadRadius: 2),
      BoxShadow(color: Color(0x99FF2BD6), blurRadius: 22, spreadRadius: 2),
    ],
    sheetGlow: [BoxShadow(color: Color(0x80FF2BD6), blurRadius: 40)],
    pillRadius: 999,
    panelRadius: 20,
    toastBg: Color(0xFF39FF14),
    toastFg: Color(0xFF010403),
    dockIcon: Color(0xFF39FF14),
    sharingBorder: Color(0xFFFF2BD6),
    panelBorder: Color(0x9939FF14),
    gridLine: Color(0x4DFF2BD6),
    gridWash: Color(0x24FF2BD6),
    panelGridLine: Color(0x0D39FF14),
  );

  final Color ink;
  final Color ink2;
  final Color inkGlass;
  final Color hair;
  final Color mist;
  final Color muted;

  /// Live / you are sharing; also the primary button and warnings.
  final Color signal;
  final Color onSignal;

  /// Connected / present; the accent.
  final Color beacon;

  /// Border of the floating chrome (chips, dock buttons).
  final Color outline;
  final Color sheetBg;
  final List<BoxShadow> shadow;

  /// Extra glow around the floating chrome; empty in the standard look.
  final List<BoxShadow> chromeGlow;

  /// Ring and glow around the primary button while it is filled.
  final List<BoxShadow> primaryGlow;
  final List<BoxShadow> sheetGlow;

  /// Corner radius of "pill" controls; 999 means a true stadium.
  final double pillRadius;
  final double panelRadius;
  final Color toastBg;
  final Color toastFg;

  /// The share and settings glyphs in the dock.
  final Color dockIcon;

  /// Edge of the primary button while sharing (it is then unfilled).
  final Color sharingBorder;

  /// Edge of sheets and dialogs.
  final Color panelBorder;
  final String? fontFamily;
  final List<String>? fontFamilyFallback;

  /// Dock and wordmark labels in capitals.
  final bool uppercase;

  /// Floor grid over the bottom of the map; null for none.
  final Color? gridLine;
  final Color? gridWash;

  /// Faint grid inside sheets; null for none.
  final Color? panelGridLine;

  static HereBeeTokens of(BuildContext context) => Theme.of(context).extension<HereBeeTokens>() ?? standard;

  /// A pill-shaped control: a stadium in the standard look, a rounded
  /// rectangle in synthwave.
  OutlinedBorder pill([BorderSide side = BorderSide.none]) => pillRadius >= 999
      ? StadiumBorder(side: side)
      : RoundedRectangleBorder(borderRadius: BorderRadius.circular(pillRadius), side: side);

  /// A round icon control: a circle, or a rounded square in synthwave.
  OutlinedBorder round([BorderSide side = BorderSide.none]) => pillRadius >= 999
      ? CircleBorder(side: side)
      : RoundedRectangleBorder(borderRadius: BorderRadius.circular(pillRadius), side: side);

  String label(String text) => uppercase ? text.toUpperCase() : text;

  @override
  HereBeeTokens copyWith() => this;

  @override
  HereBeeTokens lerp(HereBeeTokens? other, double t) => t < 0.5 || other == null ? this : other;
}
