/// Renders the tiny subset of inline HTML the shared strings use.
///
/// The strings come from `client/src/i18n.ts`, where they are inserted with
/// innerHTML and may contain <strong>, <em> and <code>. Keeping the markup means
/// the two clients stay one source of truth; this turns it into TextSpans.
/// Anything it does not recognise is rendered as literal text rather than
/// dropped, so a new tag shows up as a visible bug instead of silent data loss.
library;

import 'package:flutter/material.dart';

final RegExp _tag = RegExp(r'<(/?)(strong|em|code)>', caseSensitive: false);

TextSpan richFromMarkup(String source, TextStyle? base) {
  final children = <TextSpan>[];
  var bold = 0;
  var italic = 0;
  var mono = 0;
  var index = 0;

  TextStyle? styleNow() {
    var s = base ?? const TextStyle();
    if (bold > 0) s = s.copyWith(fontWeight: FontWeight.w700);
    if (italic > 0) s = s.copyWith(fontStyle: FontStyle.italic);
    if (mono > 0) s = s.copyWith(fontFamily: 'monospace');
    return s;
  }

  void emit(String text) {
    if (text.isEmpty) return;
    children.add(TextSpan(text: text, style: styleNow()));
  }

  for (final match in _tag.allMatches(source)) {
    emit(source.substring(index, match.start));
    final closing = match.group(1) == '/';
    switch (match.group(2)!.toLowerCase()) {
      case 'strong':
        bold += closing ? -1 : 1;
      case 'em':
        italic += closing ? -1 : 1;
      case 'code':
        mono += closing ? -1 : 1;
    }
    index = match.end;
  }
  emit(source.substring(index));
  return TextSpan(children: children);
}

/// Convenience widget for a paragraph of markup text.
class MarkupText extends StatelessWidget {
  const MarkupText(this.source, {super.key, this.style, this.textAlign});

  final String source;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => Text.rich(
        richFromMarkup(source, style ?? DefaultTextStyle.of(context).style),
        textAlign: textAlign,
      );
}
