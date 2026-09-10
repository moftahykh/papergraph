class PaperModel {
  final String id;
  final String title;
  final List<String> authors;
  final String abstractText;
  final String category;
  final int year;
  final int citationsCount;
  final int influentialCitations;
  final List<String> connectedPaperIds;
  final String pdfUrl;
  final String journal;
  final String doi;
  final List<String> keyTakeaways;
  bool isFavorite;
  String personalNotes;

  PaperModel({
    required this.id,
    required this.title,
    required this.authors,
    required this.abstractText,
    required this.category,
    required this.year,
    required this.citationsCount,
    required this.influentialCitations,
    required this.connectedPaperIds,
    required this.pdfUrl,
    required this.journal,
    required this.doi,
    required this.keyTakeaways,
    this.isFavorite = false,
    this.personalNotes = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'authors': authors,
      'abstractText': abstractText,
      'category': category,
      'year': year,
      'citationsCount': citationsCount,
      'influentialCitations': influentialCitations,
      'connectedPaperIds': connectedPaperIds,
      'pdfUrl': pdfUrl,
      'journal': journal,
      'doi': doi,
      'keyTakeaways': keyTakeaways,
      'isFavorite': isFavorite,
      'personalNotes': personalNotes,
    };
  }

  factory PaperModel.fromMap(Map<dynamic, dynamic> map) {
    return PaperModel(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      authors: List<String>.from(map['authors'] ?? []),
      abstractText: map['abstractText'] ?? '',
      category: map['category'] ?? '',
      year: map['year'] ?? 2024,
      citationsCount: map['citationsCount'] ?? 0,
      influentialCitations: map['influentialCitations'] ?? 0,
      connectedPaperIds: List<String>.from(map['connectedPaperIds'] ?? []),
      pdfUrl: map['pdfUrl'] ?? '',
      journal: map['journal'] ?? '',
      doi: map['doi'] ?? '',
      keyTakeaways: List<String>.from(map['keyTakeaways'] ?? []),
      isFavorite: map['isFavorite'] ?? false,
      personalNotes: map['personalNotes'] ?? '',
    );
  }

  PaperModel copyWith({
    String? id,
    String? title,
    List<String>? authors,
    String? abstractText,
    String? category,
    int? year,
    int? citationsCount,
    int? influentialCitations,
    List<String>? connectedPaperIds,
    String? pdfUrl,
    String? journal,
    String? doi,
    List<String>? keyTakeaways,
    bool? isFavorite,
    String? personalNotes,
  }) {
    return PaperModel(
      id: id ?? this.id,
      title: title ?? this.title,
      authors: authors ?? this.authors,
      abstractText: abstractText ?? this.abstractText,
      category: category ?? this.category,
      year: year ?? this.year,
      citationsCount: citationsCount ?? this.citationsCount,
      influentialCitations: influentialCitations ?? this.influentialCitations,
      connectedPaperIds: connectedPaperIds ?? this.connectedPaperIds,
      pdfUrl: pdfUrl ?? this.pdfUrl,
      journal: journal ?? this.journal,
      doi: doi ?? this.doi,
      keyTakeaways: keyTakeaways ?? this.keyTakeaways,
      isFavorite: isFavorite ?? this.isFavorite,
      personalNotes: personalNotes ?? this.personalNotes,
    );
  }
}
