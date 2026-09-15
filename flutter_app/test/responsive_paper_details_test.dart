import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:paper_graph/core/theme/app_theme.dart';
import 'package:paper_graph/cubits/library/library_cubit.dart';
import 'package:paper_graph/cubits/paper_details/paper_details_cubit.dart';
import 'package:paper_graph/models/paper_model.dart';
import 'package:paper_graph/providers/papers_provider.dart';
import 'package:paper_graph/views/paper_details/paper_details_view.dart';
import 'package:paper_graph/views/paper_details/citation_bottom_sheet.dart';

void main() {

  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PaperDetailsView renders on narrow 360px viewport without RenderFlex overflow', (tester) async {
    // Set small phone viewport (360 width, e.g. Samsung Galaxy / standard Android)
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final paper = PaperModel(
      id: 'paper-101',
      title: 'Deep Image Matting: A Comprehensive Survey and Experimental Study',
      authors: ['Jizhizi Li', 'Jing Zhang', 'Dacheng Tao'],
      abstractText: 'Synthesized node from PaperGraph discovery engine.',
      category: 'Computer Vision',
      year: 2023,
      citationsCount: 23,
      influentialCitations: 2,
      connectedPaperIds: const [],
      pdfUrl: 'https://arxiv.org/pdf/2301.00001.pdf',
      journal: 'arXiv.org',
      doi: '10.1109/TPAMI.2023.12345',
      keyTakeaways: [
        'Comprehensive taxonomy of image matting algorithms.',
        'Extensive benchmark on high-resolution alphamatting dataset.',
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PapersProvider>(create: (_) => PapersProvider.seeded()),
          BlocProvider<LibraryCubit>(create: (_) => LibraryCubit.seeded()),
          BlocProvider<PaperDetailsCubit>(create: (_) => PaperDetailsCubit()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: PaperDetailsView(paper: paper, loadDetailsOnOpen: false),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify Title and Section Headers render cleanly
    expect(find.text('Paper'), findsOneWidget);
    expect(find.text('Deep Image Matting: A Comprehensive Survey and Experimental Study'), findsOneWidget);
    expect(find.text('My notes'), findsOneWidget);

    // Verify Read Paper & Explore Graph buttons exist
    expect(find.text('Read paper'), findsOneWidget);
    expect(find.text('Explore graph'), findsOneWidget);
    expect(find.byIcon(Icons.share_outlined), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    expect(find.text('Abstract'), findsOneWidget);
    expect(find.text('Citations (23)'), findsOneWidget);
    expect(find.text('Connected papers (0)'), findsOneWidget);

    // Verify DOI is formatted cleanly with clickable link
    expect(find.text('DOI: 10.1109/TPAMI.2023.12345'), findsOneWidget);

    // Verify NO RenderFlex overflows occurred (zero exceptions thrown by tester)
    expect(tester.takeException(), isNull);
  });

  testWidgets('CitationBottomSheet with 45+ authors renders on 360x640 with ZERO overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Massive author list replicating the exact paper in the user's screenshot
    final massiveAuthors = List.generate(45, (i) => 'Researcher Name $i');
    final paper = PaperModel(
      id: 'nature-clofazimine-1',
      title: 'Clofazimine broadly inhibits coronaviruses including SARS-CoV-2',
      authors: massiveAuthors,
      abstractText: 'Study on broad coronavirus inhibition.',
      category: 'Medicine',
      year: 2021,
      citationsCount: 184,
      influentialCitations: 20,
      connectedPaperIds: const [],
      pdfUrl: '',
      journal: 'Nature',
      doi: '10.1038/s41586-021-03431-4',
      keyTakeaways: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => CitationBottomSheet.show(context, paper),
              child: const Text('Open Citation'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Citation'));
    await tester.pumpAndSettle();

    // Select BibTeX which caused the 65-pixel overflow in the user's screenshot
    await tester.tap(find.text('BibTeX'));
    await tester.pumpAndSettle();

    expect(find.text('Export Academic Citation'), findsOneWidget);
    expect(find.text('Copy BibTeX Citation'), findsOneWidget);

    // Verify ZERO RenderFlex exceptions
    expect(tester.takeException(), isNull);
  });
}
