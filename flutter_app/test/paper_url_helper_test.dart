import 'package:flutter_test/flutter_test.dart';
import 'package:paper_graph/core/utils/paper_url_helper.dart';

void main() {
  group('PaperUrlHelper Resolution Tests', () {
    test('resolves direct openAccessUrl if provided', () {
      final url = PaperUrlHelper.resolvePaperUrl(
        openAccessUrl: 'https://openaccess.thecvf.com/paper.pdf',
        doi: '10.1109/CVPR.2023.12345',
        title: 'Deep Image Matting',
      );
      expect(url, equals('https://openaccess.thecvf.com/paper.pdf'));
    });

    test('resolves direct pdfUrl when openAccessUrl is null', () {
      final url = PaperUrlHelper.resolvePaperUrl(
        pdfUrl: 'https://arxiv.org/pdf/2301.00001.pdf',
        doi: '10.1109/CVPR.2023.12345',
        title: 'Deep Image Matting',
      );
      expect(url, equals('https://arxiv.org/pdf/2301.00001.pdf'));
    });

    test('resolves standard DOI into doi.org URL', () {
      final url = PaperUrlHelper.resolvePaperUrl(
        doi: '10.1145/3290605.3300233',
        title: 'Sample Paper',
      );
      expect(url, equals('https://doi.org/10.1145/3290605.3300233'));
    });

    test('resolves DOI with doi: prefix cleanly', () {
      final url = PaperUrlHelper.resolvePaperUrl(
        doi: 'doi:10.1038/nature12345',
        title: 'Nature Paper',
      );
      expect(url, equals('https://doi.org/10.1038/nature12345'));
    });

    test('resolves DOI already formatted as URL without duplication', () {
      final url = PaperUrlHelper.resolvePaperUrl(
        doi: 'https://doi.org/10.1038/nature12345',
      );
      expect(url, equals('https://doi.org/10.1038/nature12345'));
    });

    test('resolves arXiv canonicalId with prefix', () {
      final url = PaperUrlHelper.resolvePaperUrl(
        canonicalId: 'arXiv:1706.03762',
        title: 'Attention Is All You Need',
      );
      expect(url, equals('https://arxiv.org/abs/1706.03762'));
    });

    test('resolves arXiv canonicalId regex matching 4.4 digits', () {
      final url = PaperUrlHelper.resolvePaperUrl(
        canonicalId: '2104.08865',
        title: 'Depth Pro',
      );
      expect(url, equals('https://arxiv.org/abs/2104.08865'));
    });

    test('resolves canonicalId that starts with 10. as DOI', () {
      final url = PaperUrlHelper.resolvePaperUrl(
        canonicalId: '10.1109/TPAMI.2023.12345',
      );
      expect(url, equals('https://doi.org/10.1109/TPAMI.2023.12345'));
    });

    test('falls back to Google Scholar search when only title is available', () {
      final url = PaperUrlHelper.resolvePaperUrl(
        title: 'Deep Image Matting: A Comprehensive Survey',
      );
      expect(
        url,
        equals('https://scholar.google.com/scholar?q=Deep%20Image%20Matting%3A%20A%20Comprehensive%20Survey'),
      );
    });

    test('returns empty string when no identifier or title is available', () {
      final url = PaperUrlHelper.resolvePaperUrl(
        openAccessUrl: '',
        pdfUrl: '',
        doi: '',
        canonicalId: '',
        title: '',
      );
      expect(url, isEmpty);
    });
  });
}
