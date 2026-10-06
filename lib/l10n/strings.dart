import 'package:flutter/material.dart';
import 'catalog.dart';

/// Translate only authored display copy. Player names are rendered as plain Text.
/// Longest matches preserve whole sentences inside composed labels and briefings.
class GameStrings {
  const GameStrings(this.language);
  final String language;
  static final _phrases = RegExp(
    (germanCatalog.keys.toList()..sort((a, b) => b.length.compareTo(a.length)))
        .map(RegExp.escape)
        .join('|'),
  );
  static final _letter = RegExp('[A-Za-z]');
  String tr(String text) {
    if (language != 'de') return text;
    return text.replaceAllMapped(_phrases, (match) {
      if ((match.start > 0 &&
              _letter.hasMatch(text[match.start - 1]) &&
              _letter.hasMatch(text[match.start])) ||
          (match.end < text.length &&
              _letter.hasMatch(text[match.end]) &&
              _letter.hasMatch(text[match.end - 1]))) {
        return match[0]!;
      }
      return germanCatalog[match[0]]!;
    });
  }

  static GameStrings of(BuildContext context) =>
      GameStrings(Localizations.localeOf(context).languageCode);
}

class LText extends StatelessWidget {
  const LText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  @override
  Widget build(BuildContext context) => Text(
    GameStrings.of(context).tr(data),
    style: style,
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: overflow,
  );
}

class LTooltip extends StatelessWidget {
  const LTooltip({super.key, required this.message, required this.child});
  final String message;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      Tooltip(message: GameStrings.of(context).tr(message), child: child);
}
