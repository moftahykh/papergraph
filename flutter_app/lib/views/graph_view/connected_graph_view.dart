import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import '../../core/theme/app_theme.dart';
import '../../cubits/graph/graph_cubit.dart';
import '../../cubits/graph/graph_state.dart';
import '../../cubits/library/library_cubit.dart';
import '../../cubits/library/library_state.dart';
import '../../cubits/notification/notification_cubit.dart';
import '../../cubits/notification/notification_state.dart';
import '../../cubits/paper_details/paper_details_cubit.dart';
import '../../models/graph_models.dart';
import '../../models/paper_model.dart';
import '../paper_details/paper_details_view.dart';
import 'painters/graph_canvas_painter.dart';
import 'widgets/graph_bottom_sheet.dart';
import 'widgets/graph_floating_controls.dart';
import 'widgets/graph_list_view_tab.dart';
import 'widgets/graph_loading_overlay.dart';
import 'widgets/graph_state_views.dart';
import 'widgets/graph_view_mode_switcher.dart';
import 'widgets/graph_year_legend.dart';

class ConnectedGraphView extends StatelessWidget {
  final PaperModel? centerPaper;
  final String? seedDoi;
  final GraphSnapshot? initialSnapshot;
  final GraphCubit? cubit;

  const ConnectedGraphView({
    super.key,
    this.centerPaper,
    this.seedDoi,
    this.initialSnapshot,
    this.cubit,
  });

  @override
  Widget build(BuildContext context) {
    if (cubit != null) {
      return BlocProvider<GraphCubit>.value(
        value: cubit!,
        child: _ConnectedGraphContentView(
          centerPaper: centerPaper,
          seedDoi: seedDoi,
          initialSnapshot: initialSnapshot,
        ),
      );
    }

    bool hasParentCubit = false;
    try {
      BlocProvider.of<GraphCubit>(context, listen: false);
      hasParentCubit = true;
    } catch (_) {
      hasParentCubit = false;
    }

    if (hasParentCubit) {
      return _ConnectedGraphContentView(
        centerPaper: centerPaper,
        seedDoi: seedDoi,
        initialSnapshot: initialSnapshot,
      );
    }

    return BlocProvider<GraphCubit>(
      create: (_) => GraphCubit(),
      child: _ConnectedGraphContentView(
        centerPaper: centerPaper,
        seedDoi: seedDoi,
        initialSnapshot: initialSnapshot,
      ),
    );
  }
}

class _ConnectedGraphContentView extends StatefulWidget {
  final PaperModel? centerPaper;
  final String? seedDoi;
  final GraphSnapshot? initialSnapshot;

  const _ConnectedGraphContentView({
    this.centerPaper,
    this.seedDoi,
    this.initialSnapshot,
  });

  @override
  State<_ConnectedGraphContentView> createState() =>
      _ConnectedGraphContentViewState();
}

class _ConnectedGraphContentViewState extends State<_ConnectedGraphContentView>
    with SingleTickerProviderStateMixin {
  late TransformationController _transformController;
  late AnimationController _animController;
  Animation<Matrix4>? _matrixAnimation;

  GraphViewMode _currentViewMode = GraphViewMode.graph;
  GraphNode? _selectedNode;
  bool _isBottomSheetOpen = false;
  String? _draggingNodeId;
  final Map<String, Offset> _draggedPositions = {};
  double _currentZoom = 0.75;
  GraphSnapshot? _displayedSnapshot;
  String? _lastFittedGraphId;

  static const double _canvasSize = 2000.0;

  @override
  void initState() {
    super.initState();
    _transformController = TransformationController();
    _transformController.addListener(_handleTransformChanged);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeGraph();
      _centerCanvas(animate: false);
    });
  }

  void _initializeGraph() {
    final graphCubit = context.read<GraphCubit>();

    if (widget.initialSnapshot != null) {
      graphCubit.openCachedGraph(widget.initialSnapshot!);
      return;
    }

    if (widget.seedDoi != null && widget.seedDoi!.isNotEmpty) {
      graphCubit.buildGraphFromDoi(widget.seedDoi!);
      return;
    }

    if (widget.centerPaper != null) {
      final seed = widget.centerPaper!.doi.isNotEmpty
          ? widget.centerPaper!.doi
          : widget.centerPaper!.id;
      graphCubit.buildGraphFromDoi(seed);
      return;
    }

    final currentState = graphCubit.state;
    if (currentState is GraphLoaded) {
      _displayedSnapshot = currentState.snapshot;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fitGraphToViewport(currentState.snapshot.nodes, animate: false);
      });
    }
  }

  void _centerCanvas({bool animate = true}) {
    if (!mounted) return;
    final screenSize = MediaQuery.of(context).size;
    final isWide = screenSize.width >= 1024;
    const double initialScale = 0.75;
    final targetWidth = isWide ? screenSize.width - 380 : screenSize.width;
    final dx = targetWidth / 2;
    final dy = screenSize.height * (isWide ? 0.50 : 0.38);

    final targetMatrix = Matrix4.identity()
      ..setTranslationRaw(dx, dy, 0.0)
      ..scaleByDouble(initialScale, initialScale, 1.0, 1.0);

    if (animate) {
      _animateToMatrix(targetMatrix);
    } else {
      _transformController.value = targetMatrix;
    }
  }

  void _focusOnNode(GraphNode node) {
    if (!mounted) return;
    final screenSize = MediaQuery.of(context).size;
    final isWide = screenSize.width >= 1024;
    const double targetScale = 1.25;

    final nodePos =
        _draggedPositions[node.canonicalId] ?? Offset(node.x, node.y);
    final targetWidth = isWide ? screenSize.width - 380 : screenSize.width;
    final targetX = targetWidth / 2 - nodePos.dx * targetScale;
    final targetY =
        (screenSize.height * (isWide ? 0.50 : 0.38)) - nodePos.dy * targetScale;

    final targetMatrix = Matrix4.identity()
      ..setTranslationRaw(targetX, targetY, 0.0)
      ..scaleByDouble(targetScale, targetScale, 1.0, 1.0);

    _animateToMatrix(targetMatrix);

    setState(() {
      _selectedNode = node;
      _isBottomSheetOpen = true;
    });
  }

  void _animateToMatrix(Matrix4 targetMatrix) {
    _animController.stop();
    _matrixAnimation =
        Matrix4Tween(
            begin: _transformController.value,
            end: targetMatrix,
          ).animate(
            CurvedAnimation(
              parent: _animController,
              curve: Curves.easeOutCubic,
            ),
          )
          ..addListener(() {
            _transformController.value = _matrixAnimation!.value;
          });

    _animController.reset();
    _animController.forward();
  }

  void _resetZoom() {
    final snapshot = _displayedSnapshot;
    if (snapshot != null && snapshot.nodes.isNotEmpty) {
      _fitGraphToViewport(snapshot.nodes, animate: true);
    } else {
      _centerCanvas(animate: true);
    }
  }

  void _fitGraphToViewport(List<GraphNode> nodes, {bool animate = true}) {
    if (!mounted || nodes.isEmpty) return;

    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    var minY = double.infinity;
    var maxY = double.negativeInfinity;
    for (final node in nodes) {
      final position =
          _draggedPositions[node.canonicalId] ?? Offset(node.x, node.y);
      minX = math.min(minX, position.dx);
      maxX = math.max(maxX, position.dx);
      minY = math.min(minY, position.dy);
      maxY = math.max(maxY, position.dy);
    }

    final screen = MediaQuery.of(context).size;
    final isWide = screen.width >= 1024;
    final viewportWidth = math.max(
      240.0,
      isWide ? screen.width - 430 : screen.width - 28,
    );
    final viewportHeight = math.max(320.0, screen.height - 180);
    const graphPadding = 180.0;
    final graphWidth = math.max(1.0, maxX - minX + graphPadding);
    final graphHeight = math.max(1.0, maxY - minY + graphPadding);
    final scale = math
        .min(viewportWidth / graphWidth, viewportHeight / graphHeight)
        .clamp(0.45, 1.10)
        .toDouble();
    final graphCenter = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    final viewportCenter = Offset(viewportWidth / 2, viewportHeight / 2);
    final targetMatrix = Matrix4.identity()
      ..setTranslationRaw(
        viewportCenter.dx - graphCenter.dx * scale,
        viewportCenter.dy - graphCenter.dy * scale,
        0,
      )
      ..scaleByDouble(scale, scale, 1.0, 1.0);

    if (animate) {
      _animateToMatrix(targetMatrix);
    } else {
      _transformController.value = targetMatrix;
    }
  }

  void _handleTransformChanged() {
    final nextZoom = _transformController.value
        .getMaxScaleOnAxis()
        .clamp(0.20, 4.0)
        .toDouble();
    if ((nextZoom - _currentZoom).abs() < 0.06 || !mounted) return;
    setState(() => _currentZoom = nextZoom);
  }

  @override
  void dispose() {
    _transformController.removeListener(_handleTransformChanged);
    _animController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  // Hit-testing to identify tapped node
  GraphNode? _hitTestNode(
    Offset localPos,
    List<GraphNode> nodes,
    int maxCitations,
  ) {
    final Matrix4 inverse = Matrix4.inverted(_transformController.value);
    final Vector3 canvasPoint = inverse.transform3(
      Vector3(localPos.dx, localPos.dy, 0.0),
    );
    final Offset canvasOffset = Offset(canvasPoint.x, canvasPoint.y);

    GraphNode? hit;
    double minDistance = double.infinity;

    for (final node in nodes) {
      final pos = _draggedPositions[node.canonicalId] ?? Offset(node.x, node.y);
      final radius = GraphCanvasPainter.computeNodeRadius(
        node.citationCount,
        maxCitations,
      );
      final dist = (canvasOffset - pos).distance;

      // Keep a roughly 44px minimum touch target even when zoomed out.
      final touchTolerance = 16.0 / _currentZoom;
      if (dist <= radius + touchTolerance && dist < minDistance) {
        minDistance = dist;
        hit = node;
      }
    }
    return hit;
  }

  void _onTapCanvas(
    TapUpDetails details,
    List<GraphNode> nodes,
    int maxCitations,
  ) {
    final hit = _hitTestNode(details.localPosition, nodes, maxCitations);
    setState(() {
      if (hit != null) {
        _selectedNode = hit;
        _isBottomSheetOpen = true;
      } else {
        _selectedNode = null;
        _isBottomSheetOpen = false;
      }
    });
  }

  void _onLongPressStart(
    LongPressStartDetails details,
    List<GraphNode> nodes,
    int maxCitations,
  ) {
    final hit = _hitTestNode(details.localPosition, nodes, maxCitations);
    if (hit != null) {
      setState(() {
        _draggingNodeId = hit.canonicalId;
        _selectedNode = hit;
      });
    }
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (_draggingNodeId != null) {
      final Matrix4 inverse = Matrix4.inverted(_transformController.value);
      final Vector3 canvasPoint = inverse.transform3(
        Vector3(details.localPosition.dx, details.localPosition.dy, 0.0),
      );
      setState(() {
        _draggedPositions[_draggingNodeId!] = Offset(
          canvasPoint.x,
          canvasPoint.y,
        );
      });
    }
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (_draggingNodeId != null) {
      setState(() {
        _draggingNodeId = null;
      });
    }
  }

  void _zoomIn() {
    final matrix = _transformController.value.clone()
      ..scaleByDouble(1.25, 1.25, 1.0, 1.0);
    _animateToMatrix(matrix);
  }

  void _zoomOut() {
    final matrix = _transformController.value.clone()
      ..scaleByDouble(0.80, 0.80, 1.0, 1.0);
    _animateToMatrix(matrix);
  }

  Future<void> _saveGraphToLibrary(GraphSnapshot snapshot) async {
    final saved = await context.read<LibraryCubit>().cacheGraph(snapshot);
    if (!mounted) return;
    context.read<NotificationCubit>().notify(
      title: saved ? 'Graph saved' : 'Graph not saved',
      message: saved
          ? 'This graph is available without internet.'
          : 'Keep this graph open and try saving it again.',
      type: saved ? NotificationType.success : NotificationType.error,
    );
  }

  void _openDetailsForNode(GraphNode node) {
    context.read<PaperDetailsCubit>().loadDetails(node.canonicalId);
    final paper = PaperModel(
      id: node.canonicalId,
      title: node.title,
      authors: node.authors,
      year: node.year ?? 2020,
      journal: node.venue ?? 'Academic Literature',
      abstractText: '',
      citationsCount: node.citationCount,
      influentialCitations: 0,
      connectedPaperIds: const [],
      pdfUrl: '',
      keyTakeaways: const [],
      category: node.archetype ?? 'Research Paper',
      doi: node.canonicalId.startsWith('10.') ? node.canonicalId : '',
    );

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PaperDetailsView(paper: paper)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : const Color(0xFFF8FAFC),
      body: BlocConsumer<GraphCubit, GraphState>(
        listener: (context, state) {
          if (state is GraphLoaded) {
            _displayedSnapshot = state.snapshot;
            if (_lastFittedGraphId != state.snapshot.graphId) {
              _lastFittedGraphId = state.snapshot.graphId;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _fitGraphToViewport(state.snapshot.nodes, animate: false);
              });
            }
            if (state.snapshot.nodes.isNotEmpty) {
              final originNode = state.snapshot.nodes.firstWhere(
                (n) => n.isOrigin,
                orElse: () => state.snapshot.nodes.first,
              );
              if (_selectedNode == null) {
                setState(() {
                  _selectedNode = originNode;
                });
              }
            }
          }
        },
        builder: (context, state) {
          if (state is GraphCreating || state is GraphPolling) {
            return GraphProgressiveLoadingView(state: state, isDark: isDark);
          }

          if (state is GraphError) {
            return GraphErrorView(
              message: state.message,
              isDark: isDark,
              onRetry: () => context.read<GraphCubit>().retry(),
              onGoBack: () => Navigator.of(context).maybePop(),
            );
          }

          if (state is GraphLoaded) {
            return _buildMainLayout(
              state.snapshot,
              state.isPartial,
              state.fromOfflineCache,
              isDark,
            );
          }

          return GraphEmptyStateView(
            isDark: isDark,
            onExplore: () => Navigator.of(context).maybePop(),
          );
        },
      ),
    );
  }

  Widget _buildMainLayout(
    GraphSnapshot snapshot,
    bool isPartial,
    bool fromOfflineCache,
    bool isDark,
  ) {
    final isWide = MediaQuery.of(context).size.width >= 1024;

    return SafeArea(
      child: Column(
        children: [
          // Top Navigation Bar with View Mode Switcher
          _buildTopBar(snapshot, isPartial, fromOfflineCache, isDark),

          // Main View (Canvas or Categorized List)
          Expanded(
            child: _currentViewMode == GraphViewMode.list
                ? GraphListViewTab(
                    snapshot: snapshot,
                    selectedNode: _selectedNode,
                    isDark: isDark,
                    onNodeSelected: (node) =>
                        setState(() => _selectedNode = node),
                    onFocusInGraph: (node) {
                      setState(() {
                        _currentViewMode = GraphViewMode.graph;
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _focusOnNode(node);
                      });
                    },
                    onOpenFullDetails: (node) => _openDetailsForNode(node),
                  )
                : (isWide
                      ? _buildResponsiveWideLayout(
                          snapshot,
                          fromOfflineCache,
                          isDark,
                        )
                      : _buildMobileCanvasLayout(
                          snapshot,
                          fromOfflineCache,
                          isDark,
                        )),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(
    GraphSnapshot snapshot,
    bool isPartial,
    bool fromOfflineCache,
    bool isDark,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 500;
    final citationLinkLabel = snapshot.citationEdges.length == 1
        ? 'citation link'
        : 'citation links';
    final similarityLinkLabel = snapshot.similarityEdges.length == 1
        ? 'similarity link'
        : 'similarity links';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 10 : 14,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppTheme.darkBorder : const Color(0xFFE5E7EB),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Back Button
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: 'Back to Explore',
              ),
              SizedBox(width: isCompact ? 6 : 8),

              // Paper Title & Counts
              Expanded(
                child: Tooltip(
                  message: snapshot.origin.title,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        snapshot.origin.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isCompact ? 12.5 : 13.5,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppTheme.darkTextPrimary
                              : const Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${snapshot.nodes.length} papers · ${snapshot.citationEdges.length} $citationLinkLabel · ${snapshot.similarityEdges.length} $similarityLinkLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isCompact ? 10 : 11,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : const Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: isCompact ? 6 : 8),

              // View Mode Switcher [ Graph | List ]
              GraphViewModeSwitcher(
                currentMode: _currentViewMode,
                isDark: isDark,
                isCompact: isCompact,
                onModeChanged: (mode) =>
                    setState(() => _currentViewMode = mode),
              ),
              SizedBox(width: isCompact ? 4 : 6),

              // Bookmark / Save Graph Action
              BlocSelector<LibraryCubit, LibraryState, bool>(
                selector: (libraryState) {
                  return libraryState is LibraryLoaded &&
                      libraryState.isGraphCached(snapshot.graphId);
                },
                builder: (context, isSaved) {
                  return IconButton(
                    icon: Icon(
                      isSaved
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_add_outlined,
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    color: isSaved
                        ? (isDark ? Colors.white : const Color(0xFF18181B))
                        : (isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary),
                    disabledColor: isDark ? Colors.white : const Color(0xFF18181B),
                    tooltip: isSaved ? 'Saved to library' : 'Save graph',
                    onPressed: isSaved
                        ? null
                        : () => _saveGraphToLibrary(snapshot),
                  );
                },
              ),
            ],
          ),

          // Offline / Partial Warning Badges
          if (fromOfflineCache) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    size: 13,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Available offline',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (isPartial) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      snapshot.warnings.isNotEmpty
                          ? snapshot.warnings.first.message
                          : 'Partial graph: External providers throttled.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (snapshot.isExpired) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.history_toggle_off_rounded,
                    size: 13,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Refresh recommended. Connect to update this graph.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Mobile Canvas Layout with Floating Dock and Sliding Bottom Sheet
  Widget _buildMobileCanvasLayout(
    GraphSnapshot snapshot,
    bool fromOfflineCache,
    bool isDark,
  ) {
    final maxCitations = GraphCanvasPainter.calcMaxCitations(snapshot.nodes);
    final minYear = GraphCanvasPainter.calcMinYear(snapshot.nodes);
    final maxYear = GraphCanvasPainter.calcMaxYear(snapshot.nodes);

    return Stack(
      children: [
        // 2D Hardware-Accelerated Canvas
        GestureDetector(
          onTapUp: (details) =>
              _onTapCanvas(details, snapshot.nodes, maxCitations),
          onDoubleTap: _resetZoom,
          onLongPressStart: (details) =>
              _onLongPressStart(details, snapshot.nodes, maxCitations),
          onLongPressMoveUpdate: _onLongPressMoveUpdate,
          onLongPressEnd: _onLongPressEnd,
          child: InteractiveViewer(
            transformationController: _transformController,
            boundaryMargin: const EdgeInsets.all(1500),
            minScale: 0.20,
            maxScale: 4.0,
            panEnabled: _draggingNodeId == null,
            scaleEnabled: _draggingNodeId == null,
            child: SizedBox(
              width: _canvasSize,
              height: _canvasSize,
              child: RepaintBoundary(
                child: CustomPaint(
                  size: const Size(_canvasSize, _canvasSize),
                  painter: GraphCanvasPainter(
                    nodes: snapshot.nodes,
                    citationEdges: snapshot.citationEdges,
                    similarityEdges: snapshot.similarityEdges,
                    selectedNodeId: _selectedNode?.canonicalId,
                    isDark: isDark,
                    draggedPositions: _draggedPositions,
                    zoomScale: _currentZoom,
                  ),
                ),
              ),
            ),
          ),
        ),

        // Floating Controls Dock (Right Side)
        Positioned(
          right: 14,
          bottom: _isBottomSheetOpen ? 305 : 24,
          child: GraphFloatingControls(
            isDark: isDark,
            isBottomSheetOpen: _isBottomSheetOpen,
            hasSelectedNode: _selectedNode != null,
            onZoomIn: _zoomIn,
            onZoomOut: _zoomOut,
            onResetZoom: _resetZoom,
            onFocusSelected: _selectedNode != null
                ? () => _focusOnNode(_selectedNode!)
                : null,
            onOpenPaperList: () {
              setState(() {
                _currentViewMode = GraphViewMode.list;
              });
            },
            onToggleBottomSheet: () {
              setState(() {
                _isBottomSheetOpen = !_isBottomSheetOpen;
              });
            },
          ),
        ),

        // Bottom Year & Relationship Legend
        if (!_isBottomSheetOpen)
          Positioned(
            bottom: 18,
            left: 14,
            right: 80,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: GraphYearLegend(
                  minYear: minYear,
                  maxYear: maxYear,
                  isDark: isDark,
                ),
              ),
            ),
          ),

        // Sliding Contextual Bottom Sheet
        if (_isBottomSheetOpen)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: GraphBottomSheet(
              snapshot: snapshot,
              selectedNode: _selectedNode,
              onNodeSelected: (node) => setState(() => _selectedNode = node),
              onFocusNode: (node) => _focusOnNode(node),
              onRecenterGraph: (canonicalId) {
                if (fromOfflineCache) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Cannot synthesize new graphs in offline mode. Connect to the internet to explore new papers.',
                      ),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  return;
                }
                context.read<GraphCubit>().buildGraphFromDoi(canonicalId);
                setState(() {
                  _draggedPositions.clear();
                  _isBottomSheetOpen = false;
                });
              },
              onOpenFullDetails: (node) => _openDetailsForNode(node),
              onClose: () => setState(() => _isBottomSheetOpen = false),
            ),
          ),
      ],
    );
  }

  // Tablet / Desktop Split Layout with Side Panel
  Widget _buildResponsiveWideLayout(
    GraphSnapshot snapshot,
    bool fromOfflineCache,
    bool isDark,
  ) {
    final maxCitations = GraphCanvasPainter.calcMaxCitations(snapshot.nodes);
    final minYear = GraphCanvasPainter.calcMinYear(snapshot.nodes);
    final maxYear = GraphCanvasPainter.calcMaxYear(snapshot.nodes);

    return Row(
      children: [
        // Main Interactive Canvas
        Expanded(
          child: Stack(
            children: [
              GestureDetector(
                onTapUp: (details) =>
                    _onTapCanvas(details, snapshot.nodes, maxCitations),
                onDoubleTap: _resetZoom,
                child: InteractiveViewer(
                  transformationController: _transformController,
                  boundaryMargin: const EdgeInsets.all(1500),
                  minScale: 0.20,
                  maxScale: 4.0,
                  child: SizedBox(
                    width: _canvasSize,
                    height: _canvasSize,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        size: const Size(_canvasSize, _canvasSize),
                        painter: GraphCanvasPainter(
                          nodes: snapshot.nodes,
                          citationEdges: snapshot.citationEdges,
                          similarityEdges: snapshot.similarityEdges,
                          selectedNodeId: _selectedNode?.canonicalId,
                          isDark: isDark,
                          draggedPositions: _draggedPositions,
                          zoomScale: _currentZoom,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Dock on Canvas
              Positioned(
                right: 16,
                bottom: 24,
                child: GraphFloatingControls(
                  isDark: isDark,
                  isBottomSheetOpen: true,
                  hasSelectedNode: _selectedNode != null,
                  onZoomIn: _zoomIn,
                  onZoomOut: _zoomOut,
                  onResetZoom: _resetZoom,
                  onFocusSelected: _selectedNode != null
                      ? () => _focusOnNode(_selectedNode!)
                      : null,
                  onOpenPaperList: () =>
                      setState(() => _currentViewMode = GraphViewMode.list),
                  onToggleBottomSheet: () {},
                ),
              ),

              // Legend
              Positioned(
                bottom: 16,
                left: 16,
                child: GraphYearLegend(
                  minYear: minYear,
                  maxYear: maxYear,
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ),

        // Right Contextual Inspector Side Panel
        Container(
          width: 380,
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurface : Colors.white,
            border: Border(
              left: BorderSide(
                color: isDark ? AppTheme.darkBorder : const Color(0xFFE5E7EB),
                width: 1,
              ),
            ),
          ),
          child: GraphBottomSheet(
            snapshot: snapshot,
            selectedNode: _selectedNode,
            onNodeSelected: (node) => setState(() => _selectedNode = node),
            onFocusNode: (node) => _focusOnNode(node),
            onRecenterGraph: (canonicalId) {
              if (fromOfflineCache) return;
              context.read<GraphCubit>().buildGraphFromDoi(canonicalId);
            },
            onOpenFullDetails: (node) => _openDetailsForNode(node),
            onClose: () {},
          ),
        ),
      ],
    );
  }
}
