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
/// map style: [standard] over the light map, [dark] over the dark one and a
/// neon set ([synthwave] is Grid Toxic, then [outrun], [miami], [tron],
/// [vapor], [amber]) over the matching neon map. Keep them in step with the
/// `:root[data-map-theme=...]` blocks in client/src/style.css; on the phone the
/// primary button takes the web's --primary-bg as [signal].
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
    this.gridHeight = 0.55,
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

  static HereBeeTokens _neon({
    required Color ink,
    required Color ink2,
    required Color inkGlass,
    required Color hair,
    required Color mist,
    required Color muted,
    required Color primary,
    required Color onPrimary,
    required Color beacon,
    Color? ring,
    required Color glowA,
    required Color glowB,
    required Color outline,
    required Color panelBorder,
    required Color sheetBg,
    required Color gridLine,
    required Color gridWash,
    required Color panelGridLine,
    double gridHeight = 0.55,
  }) =>
      HereBeeTokens(
        ink: ink,
        ink2: ink2,
        inkGlass: inkGlass,
        hair: hair,
        mist: mist,
        muted: muted,
        signal: primary,
        onSignal: onPrimary,
        beacon: beacon,
        outline: outline,
        sheetBg: sheetBg,
        shadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 40, offset: Offset(0, 10))],
        chromeGlow: [BoxShadow(color: glowB, blurRadius: 16)],
        primaryGlow: [
          if (ring != null) BoxShadow(color: ring, spreadRadius: 2),
          BoxShadow(color: glowA, blurRadius: 22, spreadRadius: 2),
        ],
        sheetGlow: [BoxShadow(color: glowA, blurRadius: 40)],
        pillRadius: 999,
        panelRadius: 20,
        toastBg: beacon,
        toastFg: ink,
        dockIcon: beacon,
        sharingBorder: primary,
        panelBorder: panelBorder,
        gridLine: gridLine,
        gridWash: gridWash,
        gridHeight: gridHeight,
        panelGridLine: panelGridLine,
      );

  static final HereBeeTokens synthwave = _neon(
    ink: Color(0xFF030507),
    ink2: Color(0xFF0A110E),
    inkGlass: Color(0xE0060C0A),
    hair: Color(0x4762E04A),
    mist: Color(0xFFF0FFF4),
    muted: Color(0xFF8FBF9C),
    primary: Color(0xFFE255C2),
    onPrimary: Color(0xFF1A0016),
    beacon: Color(0xFF62E04A),
    glowA: Color(0x66E255C2),
    glowB: Color(0x3862E04A),
    outline: Color(0x8062E04A),
    panelBorder: Color(0x6662E04A),
    sheetBg: Color(0xFF060C09),
    gridLine: Color(0x33E255C2),
    gridWash: Color(0x14E255C2),
    panelGridLine: Color(0x0862E04A),
    gridHeight: 0.35,
  );

  static final HereBeeTokens outrun = _neon(
    ink: Color(0xFF0F0620),
    ink2: Color(0xFF1A0B33),
    inkGlass: Color(0xDB16092C),
    hair: Color(0x59FF4F9A),
    mist: Color(0xFFFFF1FA),
    muted: Color(0xFFC79AD8),
    primary: Color(0xFFFF4F9A),
    onPrimary: Color(0xFF1D0420),
    beacon: Color(0xFFFFB03B),
    glowA: Color(0x8CFF4F9A),
    glowB: Color(0x59FFB03B),
    outline: Color(0xB2FF4F9A),
    panelBorder: Color(0x80FF4F9A),
    sheetBg: Color(0xFF150A2B),
    gridLine: Color(0x59FF4F9A),
    gridWash: Color(0x2EFF783C),
    panelGridLine: Color(0x0DFF4F9A),
  );

  static final HereBeeTokens miami = _neon(
    ink: Color(0xFF071420),
    ink2: Color(0xFF0E2132),
    inkGlass: Color(0xDB091926),
    hair: Color(0x592EE6D6),
    mist: Color(0xFFF2FBFF),
    muted: Color(0xFF8FC3D4),
    primary: Color(0xFFFF7AC6),
    onPrimary: Color(0xFF2A0619),
    beacon: Color(0xFF2EE6D6),
    ring: Color(0xFF2EE6D6),
    glowA: Color(0x80FF7AC6),
    glowB: Color(0x592EE6D6),
    outline: Color(0xB22EE6D6),
    panelBorder: Color(0x802EE6D6),
    sheetBg: Color(0xFF0B1B2A),
    gridLine: Color(0x382EE6D6),
    gridWash: Color(0x1FFF7AC6),
    panelGridLine: Color(0x0D2EE6D6),
  );

  static final HereBeeTokens tron = _neon(
    ink: Color(0xFF01050A),
    ink2: Color(0xFF06121C),
    inkGlass: Color(0xE0020A12),
    hair: Color(0x662AD4FF),
    mist: Color(0xFFE8FBFF),
    muted: Color(0xFF7FB6C8),
    primary: Color(0xFFFF9A1F),
    onPrimary: Color(0xFF1C0D00),
    beacon: Color(0xFF2AD4FF),
    ring: Color(0xFF2AD4FF),
    glowA: Color(0x80FF9A1F),
    glowB: Color(0x732AD4FF),
    outline: Color(0xCC2AD4FF),
    panelBorder: Color(0x992AD4FF),
    sheetBg: Color(0xFF030B14),
    gridLine: Color(0x472AD4FF),
    gridWash: Color(0x1A2AD4FF),
    panelGridLine: Color(0x0F2AD4FF),
  );

  static final HereBeeTokens vapor = _neon(
    ink: Color(0xFF1D1736),
    ink2: Color(0xFF2A2250),
    inkGlass: Color(0xDB2A2250),
    hair: Color(0x59FF9AD5),
    mist: Color(0xFFFDF6FF),
    muted: Color(0xFFC2B4E8),
    primary: Color(0xFFFF9AD5),
    onPrimary: Color(0xFF2A1340),
    beacon: Color(0xFF8EF6E4),
    glowA: Color(0x59FF9AD5),
    glowB: Color(0x408EF6E4),
    outline: Color(0x99FF9AD5),
    panelBorder: Color(0x73FF9AD5),
    sheetBg: Color(0xFF251D47),
    gridLine: Color(0x408EF6E4),
    gridWash: Color(0x24FF9AD5),
    panelGridLine: Color(0x0AFFFFFF),
  );

  static final HereBeeTokens amber = _neon(
    ink: Color(0xFF080604),
    ink2: Color(0xFF15100A),
    inkGlass: Color(0xE0100C08),
    hair: Color(0x59E8762A),
    mist: Color(0xFFFFF4E6),
    muted: Color(0xFFC2A283),
    primary: Color(0xFFE8762A),
    onPrimary: Color(0xFF1A0A00),
    beacon: Color(0xFFE8762A),
    ring: Color(0xFF22D3EE),
    glowA: Color(0x80E8762A),
    glowB: Color(0x5922D3EE),
    outline: Color(0xB2E8762A),
    panelBorder: Color(0x80E8762A),
    sheetBg: Color(0xFF0F0B07),
    gridLine: Color(0x38E8762A),
    gridWash: Color(0x1AE8762A),
    panelGridLine: Color(0x0AE8762A),
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
  final double gridHeight;

  /// Faint grid inside sheets; null for none.
  final Color? panelGridLine;

  static HereBeeTokens of(BuildContext context) => Theme.of(context).extension<HereBeeTokens>() ?? standard;

  /// A pill-shaped control: a stadium, or a rounded rectangle for a smaller
  /// [pillRadius].
  OutlinedBorder pill([BorderSide side = BorderSide.none]) => pillRadius >= 999
      ? StadiumBorder(side: side)
      : RoundedRectangleBorder(borderRadius: BorderRadius.circular(pillRadius), side: side);

  /// A round icon control: a circle, or a rounded square for a smaller
  /// [pillRadius].
  OutlinedBorder round([BorderSide side = BorderSide.none]) => pillRadius >= 999
      ? CircleBorder(side: side)
      : RoundedRectangleBorder(borderRadius: BorderRadius.circular(pillRadius), side: side);

  String label(String text) => uppercase ? text.toUpperCase() : text;

  @override
  HereBeeTokens copyWith() => this;

  @override
  HereBeeTokens lerp(HereBeeTokens? other, double t) => t < 0.5 || other == null ? this : other;
}
