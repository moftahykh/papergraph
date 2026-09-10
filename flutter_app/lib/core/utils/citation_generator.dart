import '../../models/paper_model.dart';

class CitationGenerator {
  /// Generate APA 7th Edition Citation
  static String toAPA(PaperModel paper) {
    final authorStr = paper.authors.join(', ');
    return '$authorStr (${paper.year}). ${paper.title}. ${paper.journal}. https://doi.org/${paper.doi}';
  }

  /// Generate BibTeX Citation Entry
  static String toBibTeX(PaperModel paper) {
    final firstAuthorLastName = paper.authors.isNotEmpty
        ? paper.authors.first.split(' ').last.toLowerCase()
        : 'paper';
    final citeKey = '$firstAuthorLastName${paper.year}${paper.id}';
    final authorsFormatted = paper.authors.join(' and ');

    return '''@article{$citeKey,
  title = {${paper.title}},
  author = {$authorsFormatted},
  journal = {${paper.journal}},
  year = {${paper.year}},
  doi = {${paper.doi}},
  citations = {${paper.citationsCount}}
}''';
  }

  /// Generate MLA 9th Edition Citation
  static String toMLA(PaperModel paper) {
    final authorsStr = paper.authors.join(', ');
    return '$authorsStr. "${paper.title}." ${paper.journal}, ${paper.year}, doi:${paper.doi}.';
  }

  /// Generate Chicago Author-Date Citation
  static String toChicago(PaperModel paper) {
    final authorsStr = paper.authors.join(', ');
    return '$authorsStr. ${paper.year}. "${paper.title}." ${paper.journal}. https://doi.org/${paper.doi}.';
  }
}
