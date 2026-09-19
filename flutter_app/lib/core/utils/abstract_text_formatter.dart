import 'package:flutter/material.dart';

const _abstractHeadings = {
  'SUMMARY',
  'BACKGROUND',
  'INTRODUCTION',
  'OBJECTIVE',
  'OBJECTIVES',
  'PURPOSE',
  'METHODS',
  'METHOD',
  'DESIGN',
  'SETTING',
  'PARTICIPANTS',
  'INTERVENTIONS',
  'MEASUREMENTS',
  'RESULTS',
  'CONCLUSIONS',
  'CONCLUSION',
  'LIMITATIONS',
};

class AbstractSection {
  final String? heading;
  final String body;

  const AbstractSection({this.heading, required this.body});
}

/// Cleans provider formatting without changing the scientific content.
List<AbstractSection> parseAbstractSections(String raw) {
  var text = raw
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('\u00a0', ' ')
      .replaceAll('\u200b', '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');

  // Some providers return "BACKGROUND:" inline instead of on its own line.
  text = text.replaceAllMapped(
    RegExp(
      r'\s+(SUMMARY|BACKGROUND|INTRODUCTION|OBJECTIVES?|PURPOSE|METHODS?|DESIGN|SETTING|PARTICIPANTS|INTERVENTIONS|MEASUREMENTS|RESULTS|CONCLUSIONS?|LIMITATIONS)\s*:?',
      caseSensitive: false,
    ),
    (match) => '\n${match.group(1)!.toUpperCase()}\n',
  );

  text = text
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n[ \t]+'), '\n')
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .trim();

  // Keep common scientific notation together when a provider split it over
  // lines, e.g. "FEV\n1" or "FEV 1".
  text = text.replaceAll(
    RegExp(r'\bFEV\s*[\n ]+\s*1\b', caseSensitive: false),
    'FEV₁',
  );

  final sections = <AbstractSection>[];
  String? heading;
  final body = <String>[];

  void flush() {
    final value = body.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (value.isNotEmpty) {
      sections.add(AbstractSection(heading: heading, body: value));
    }
    body.clear();
  }

  for (final line in text.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final normalized = trimmed.replaceFirst(RegExp(r':$'), '').toUpperCase();
    if (_abstractHeadings.contains(normalized)) {
      flush();
      heading = normalized[0] + normalized.substring(1).toLowerCase();
    } else {
      body.add(trimmed);
    }
  }
  flush();

  if (sections.isEmpty && text.isNotEmpty) {
    return [AbstractSection(body: text.replaceAll(RegExp(r'\s+'), ' '))];
  }
  return sections;
}

String abstractPreview(String raw, {int maxCharacters = 360}) {
  final compact = parseAbstractSections(raw)
      .map((section) => section.body)
      .join(' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (compact.length <= maxCharacters) return compact;
  return '${compact.substring(0, maxCharacters).trimRight()}…';
}

class FormattedAbstract extends StatelessWidget {
  final String text;
  final TextStyle? bodyStyle;
  final TextStyle? headingStyle;

  const FormattedAbstract({
    super.key,
    required this.text,
    this.bodyStyle,
    this.headingStyle,
  });

  @override
  Widget build(BuildContext context) {
    final sections = parseAbstractSections(text);
    final muted = Theme.of(context).brightness == Brightness.dark
        ? Colors.white54
        : const Color(0xFF73747D);
    final accent = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFAAB5FF)
        : const Color(0xFF5269F4);

    // A completely unstructured abstract should remain a clean reading block.
    // Structured abstracts get deliberate section rhythm so headings do not
    // visually disappear inside one long paragraph.
    if (sections.length == 1 && sections.first.heading == null) {
      return SelectableText(
        sections.first.body,
        textAlign: TextAlign.start,
        style: bodyStyle ?? const TextStyle(fontSize: 15.5, height: 1.7),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          Container(
            width: double.infinity,
            margin: EdgeInsets.only(top: i == 0 ? 0 : 20),
            padding: EdgeInsets.only(
              left: sections[i].heading == null ? 0 : 12,
            ),
            decoration: sections[i].heading == null
                ? null
                : BoxDecoration(
                    border: Border(left: BorderSide(color: accent, width: 2)),
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (sections[i].heading != null) ...[
                  Text(
                    sections[i].heading!.toUpperCase(),
                    style:
                        headingStyle ??
                        TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: muted,
                        ),
                  ),
                  const SizedBox(height: 7),
                ],
                SelectableText(
                  sections[i].body,
                  textAlign: TextAlign.start,
                  style:
                      bodyStyle ?? const TextStyle(fontSize: 15.5, height: 1.7),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
