import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/paper_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/papers_provider.dart';
import '../../providers/theme_provider.dart';
import '../graph_view/connected_graph_view.dart';
import '../paper_details/citation_bottom_sheet.dart';
import '../paper_details/paper_details_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final papersProvider = Provider.of<PapersProvider>(context);
    final favoritesProvider = Provider.of<FavoritesProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);

    final displayedPapers = papersProvider.papers;
    final trendingPapers = papersProvider.trendingPapers;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primaryBlue, AppTheme.accentCyan],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.hub_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              'PaperGraph',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              themeProvider.isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              color: themeProvider.isDark ? Colors.amber : AppTheme.primaryBlue,
            ),
            tooltip: 'Toggle Theme',
            onPressed: () => themeProvider.toggleTheme(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.delayed(const Duration(milliseconds: 500));
          setState(() {});
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome Banner
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                        : [const Color(0xFFEFF6FF), const Color(0xFFDBEAFE)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hello, ${authProvider.currentUser?.name ?? "Researcher"} 👋',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Explore connected networks & visual literature',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withAlpha(25),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.science_rounded,
                        color: AppTheme.primaryLightBlue,
                        size: 26,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Search Bar
              TextField(
                controller: _searchController,
                onChanged: (val) => papersProvider.setSearchQuery(val),
                decoration: InputDecoration(
                  hintText: 'Search papers, authors, topics, or models...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchController.clear();
                            papersProvider.setSearchQuery('');
                          },
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 18),

              // Category Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: papersProvider.categories.map((cat) {
                    final isSelected = papersProvider.selectedCategory == cat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(cat),
                        selected: isSelected,
                        onSelected: (_) => papersProvider.selectCategory(cat),
                        selectedColor: AppTheme.primaryBlue,
                        checkmarkColor: Colors.white,
                        labelStyle: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          fontSize: 12.5,
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 24),

              // Trending Research Papers (Horizontal Carousel)
              if (papersProvider.selectedCategory == 'All' && papersProvider.searchQuery.isEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '🔥 Landmark & Most Cited',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Top 5',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 175,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: trendingPapers.length,
                    itemBuilder: (context, index) {
                      final paper = trendingPapers[index];
                      return _buildTrendingCard(paper, isDark, favoritesProvider, papersProvider);
                    },
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Main Literature Feed
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Research Literature (${displayedPapers.length})',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (displayedPapers.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 48,
                          color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No papers match your search query',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: displayedPapers.length,
                  itemBuilder: (context, index) {
                    final paper = displayedPapers[index];
                    return _buildPaperCard(paper, isDark, favoritesProvider, papersProvider);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrendingCard(
    PaperModel paper,
    bool isDark,
    FavoritesProvider favoritesProvider,
    PapersProvider papersProvider,
  ) {
    return Container(
      width: 260,
      margin: const EdgeInsets.only(right: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PaperDetailsView(paper: paper)),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.accentEmerald.withAlpha(30),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${paper.citationsCount} cites',
                        style: const TextStyle(
                          color: AppTheme.accentEmerald,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${paper.year}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  paper.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
                const SizedBox(height: 4),
                Text(
                  paper.authors.join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ConnectedGraphView(centerPaper: paper),
                      ),
                    );
                  },
                  child: const Row(
                    children: [
                      Icon(Icons.hub_rounded, size: 16, color: AppTheme.accentCyan),
                      SizedBox(width: 4),
                      Text(
                        'View Graph',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accentCyan,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    favoritesProvider.isFavorite(paper.id)
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    color: favoritesProvider.isFavorite(paper.id)
                        ? AppTheme.accentAmber
                        : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
                    size: 20,
                  ),
                  onPressed: () => favoritesProvider.toggleFavorite(paper, papersProvider),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaperCard(
    PaperModel paper,
    bool isDark,
    FavoritesProvider favoritesProvider,
    PapersProvider papersProvider,
  ) {
    final isFav = favoritesProvider.isFavorite(paper.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PaperDetailsView(paper: paper)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category, Year, & Citations
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withAlpha(25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      paper.category,
                      style: const TextStyle(
                        color: AppTheme.primaryLightBlue,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${paper.year}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      const Icon(Icons.auto_graph_rounded, size: 14, color: AppTheme.accentEmerald),
                      const SizedBox(width: 4),
                      Text(
                        '${paper.citationsCount}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accentEmerald,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Title
              Text(
                paper.title,
                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, height: 1.3),
              ),
              const SizedBox(height: 6),

              // Authors
              Text(
                paper.authors.join(' • '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 12),

              // Action Toolbar
              Row(
                children: [
                  // Creative Feature Button
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ConnectedGraphView(centerPaper: paper),
                        ),
                      );
                    },
                    icon: const Icon(Icons.hub_rounded, size: 15),
                    label: const Text('Connected Graph', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accentCyan,
                      side: const BorderSide(color: AppTheme.accentCyan, width: 1.2),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Citation button
                  IconButton(
                    icon: const Icon(Icons.format_quote_rounded, size: 20),
                    tooltip: 'Cite Paper',
                    onPressed: () => CitationBottomSheet.show(context, paper),
                  ),
                  const Spacer(),

                  // Favorite / Bookmark
                  IconButton(
                    icon: Icon(
                      isFav ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                      color: isFav ? AppTheme.accentAmber : null,
                    ),
                    tooltip: isFav ? 'Remove from Library' : 'Save to Library (Hive)',
                    onPressed: () => favoritesProvider.toggleFavorite(paper, papersProvider),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
