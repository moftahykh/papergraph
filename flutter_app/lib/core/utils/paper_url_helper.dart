import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

/// Helper utility to resolve and launch external research paper URLs.
class PaperUrlHelper {
  PaperUrlHelper._();

  /// Resolves the best available external URL for a research paper using a fallback hierarchy:
  /// 1. Direct openAccessUrl or pdfUrl
  /// 2. DOI resolver (https://doi.org/...)
  /// 3. arXiv resolver (https://arxiv.org/abs/...)
  /// 4. Google Scholar search fallback with paper title
  static String resolvePaperUrl({
    String? openAccessUrl,
    String? pdfUrl,
    String? doi,
    String? canonicalId,
    String? title,
  }) {
    // 1. Direct Open Access URL
    if (openAccessUrl != null && openAccessUrl.trim().isNotEmpty) {
      final clean = openAccessUrl.trim();
      if (clean.startsWith('http://') || clean.startsWith('https://')) {
        return clean;
      }
    }

    // 2. Direct PDF URL
    if (pdfUrl != null && pdfUrl.trim().isNotEmpty) {
      final clean = pdfUrl.trim();
      if (clean.startsWith('http://') || clean.startsWith('https://')) {
        return clean;
      }
    }

    // 3. DOI Resolver
    final effectiveDoi = (doi != null && doi.trim().isNotEmpty)
        ? doi.trim()
        : (canonicalId != null && canonicalId.trim().startsWith('10.'))
        ? canonicalId.trim()
        : null;

    if (effectiveDoi != null && effectiveDoi.isNotEmpty) {
      String cleanDoi = effectiveDoi;
      if (cleanDoi.toLowerCase().startsWith('doi:')) {
        cleanDoi = cleanDoi.substring(4).trim();
      }
      if (cleanDoi.startsWith('https://doi.org/') ||
          cleanDoi.startsWith('http://doi.org/')) {
        return cleanDoi;
      }
      return 'https://doi.org/$cleanDoi';
    }

    // 4. arXiv Resolver
    final cleanId = canonicalId?.trim() ?? '';
    if (cleanId.isNotEmpty) {
      if (cleanId.startsWith('http://') || cleanId.startsWith('https://')) {
        return cleanId;
      }
      final lower = cleanId.toLowerCase();
      if (lower.startsWith('arxiv:')) {
        final arxivId = cleanId.substring(6).trim();
        return 'https://arxiv.org/abs/$arxivId';
      }
      final arxivRegex = RegExp(r'^\d{4}\.\d{4,5}(v\d+)?$');
      if (arxivRegex.hasMatch(cleanId)) {
        return 'https://arxiv.org/abs/$cleanId';
      }
    }

    // 5. Fallback: Google Scholar search query
    final cleanTitle = title?.trim() ?? '';
    if (cleanTitle.isNotEmpty) {
      return 'https://scholar.google.com/scholar?q=${Uri.encodeComponent(cleanTitle)}';
    }

    return '';
  }

  /// Launches the paper URL in an external browser or system application.
  /// Falls back to clipboard copying if the launcher fails.
  static Future<bool> launchPaper(
    BuildContext context, {
    required String url,
    String? title,
  }) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No external URL or DOI available for this paper.'),
          backgroundColor: AppTheme.accentAmber,
          duration: Duration(seconds: 2),
        ),
      );
      return false;
    }

    final uri = Uri.tryParse(cleanUrl);
    if (uri == null || !uri.hasScheme) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid paper URL: $cleanUrl'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return false;
    }

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        // Retry with platform default
        final retry = await launchUrl(uri, mode: LaunchMode.platformDefault);
        if (!retry) {
          throw 'Could not launch URL';
        }
      }
      return true;
    } catch (e) {
      // Graceful fallback: copy URL to clipboard and notify user
      await Clipboard.setData(ClipboardData(text: cleanUrl));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not open browser automatically. Link copied to clipboard:\n$cleanUrl',
            ),
            backgroundColor: AppTheme.primaryBlue,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
      return false;
    }
  }
}
