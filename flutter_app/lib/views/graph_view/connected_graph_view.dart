import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import '../../core/services/local_notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../../cubits/graph/graph_cubit.dart';
import '../../cubits/graph/graph_state.dart';
import '../../cubits/library/library_cubit.dart';
import '../../cubits/notification/notification_cubit.dart';
import '../../cubits/notification/notification_state.dart';
import '../../cubits/paper_details/paper_details_cubit.dart';
import '../../models/graph_models.dart';
import '../../models/paper_model.dart';
import '../paper_details/paper_details_view.dart';
import 'painters/graph_canvas_painter.dart';
import 'widgets/graph_bottom_sheet.dart';
import 'widgets/graph_floating_controls.dart';
import 'widgets/graph_loading_overlay.dart';
import 'widgets/graph_state_views.dart';
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

class _ConnectedGraphContentViewState extends State<_ConnectedGraphContentView> {
  late TransformationController _transformController;

  GraphNode? _selectedNode;
  bool _isBottomSheetOpen = false;
  int _bottomSheetTab = 0;
  String? _draggingNodeId;
  final Map<String, Offset> _draggedPositions = {};

  static const double _canvasSize = 2000.0;

  @override
  void initState() {
    super.initState();
    _transformController = TransformationController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeGraph();
      _centerCanvas();
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
    }
  }

  void _centerCanvas() {
    // The backend layout places the origin node at (0,0) and spreads candidates
    // within roughly ±450px of it. So center the VIEW on that content origin —
    // NOT on the middle of the 2000px canvas (that pushed every node off-screen,
    // leaving the canvas looking blank on load).
    final screenSize = MediaQuery.of(context).size;
    const double initialScale = 0.75;
    final dx = screenSize.width / 2;       // canvas (0,0) lands on horizontal center
    final dy = screenSize.height * 0.38;   // slightly above center: leaves room for the bottom sheet
    _transformController.value = Matrix4.identity()
      ..setTranslationRaw(dx, dy, 0.0)
      ..scaleByDouble(initialScale, initialScale, 1.0, 1.0);
  }

  void _resetZoom() {
    setState(() {
      _centerCanvas();
    });
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  // Hit-testing to identify tapped node
  GraphNode? _hitTestNode(Offset localPos, List<GraphNode> nodes, int maxCitations) {
    final Matrix4 inverse = Matrix4.inverted(_transformController.value);
    final Vector3 canvasPoint = inverse.transform3(Vector3(localPos.dx, localPos.dy, 0.0));
    final Offset canvasOffset = Offset(canvasPoint.x, canvasPoint.y);

    GraphNode? hit;
    double minDistance = double.infinity;

    for (final node in nodes) {
      final pos = _draggedPositions[node.canonicalId] ?? Offset(node.x, node.y);
      final radius = GraphCanvasPainter.computeNodeRadius(node.citationCount, maxCitations);
      final dist = (canvasOffset - pos).distance;

      // Allow 8.0px touch tolerance padding
      if (dist <= radius + 8.0 && dist < minDistance) {
        minDistance = dist;
        hit = node;
      }
    }
    return hit;
  }

  void _onTapCanvas(TapUpDetails details, List<GraphNode> nodes, int maxCitations) {
    final hit = _hitTestNode(details.localPosition, nodes, maxCitations);
    setState(() {
      if (hit != null) {
        _selectedNode = hit;
        _isBottomSheetOpen = true;
        _bottomSheetTab = 0;
      } else {
        _selectedNode = null;
        _isBottomSheetOpen = false;
      }
    });
  }

  void _onLongPressStart(LongPressStartDetails details, List<GraphNode> nodes, int maxCitations) {
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
        _draggedPositions[_draggingNodeId!] = Offset(canvasPoint.x, canvasPoint.y);
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
    final matrix = _transformController.value.clone()..scaleByDouble(1.25, 1.25, 1.0, 1.0);
    _transformController.value = matrix;
  }

  void _zoomOut() {
    final matrix = _transformController.value.clone()..scaleByDouble(0.8, 0.8, 1.0, 1.0);
    _transformController.value = matrix;
  }

  void _saveGraphToLibrary(GraphSnapshot snapshot) {
    context.read<LibraryCubit>().cacheGraph(snapshot);
    context.read<NotificationCubit>().notify(
      title: 'Graph Cached',
      message: 'Literature graph with ${snapshot.nodes.length} papers saved for offline access.',
      type: NotificationType.success,
    );
  }

  void _openDetailsForNode(GraphNode node) {
    context.read<PaperDetailsCubit>().loadDetails(node.canonicalId);
    // Convert to PaperModel for existing details view
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
      MaterialPageRoute(
        builder: (_) => PaperDetailsView(paper: paper),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : const Color(0xFFF1F5F9),
      body: BlocConsumer<GraphCubit, GraphState>(
        listener: (context, state) {
          if (state is GraphLoaded) {
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
            // Trigger contextual completion notice if this was an active network job
            if (!state.fromOfflineCache) {
              LocalNotificationService.onGraphCompleted(
                graphId: state.snapshot.graphId,
                nodeCount: state.snapshot.nodes.length,
                isPartial: state.isPartial,
                notificationCubit: context.read<NotificationCubit>(),
              );
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
            return _buildGraphCanvasView(state.snapshot, state.isPartial, state.fromOfflineCache, isDark);
          }

          // Fallback initial or empty state
          return GraphEmptyStateView(
            isDark: isDark,
            onExplore: () => Navigator.of(context).maybePop(),
          );
        },
      ),
    );
  }

  // 3. INTERACTIVE GRAPH CANVAS VIEW
  Widget _buildGraphCanvasView(
    GraphSnapshot snapshot,
    bool isPartial,
    bool fromOfflineCache,
    bool isDark,
  ) {
    final maxCitations = GraphCanvasPainter.calcMaxCitations(snapshot.nodes);
    final minYear = GraphCanvasPainter.calcMinYear(snapshot.nodes);
    final maxYear = GraphCanvasPainter.calcMaxYear(snapshot.nodes);

    return Stack(
      children: [
        // Interactive 2D Hardware-Accelerated Canvas with unhindered native pinch-to-zoom
        GestureDetector(
          onTapUp: (details) => _onTapCanvas(details, snapshot.nodes, maxCitations),
          onDoubleTap: _resetZoom,
          onLongPressStart: (details) => _onLongPressStart(details, snapshot.nodes, maxCitations),
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
                  ),
                ),
              ),
            ),
          ),
        ),

        // TOP OVERLAYS (Navigation, Info, Warnings, Controls)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // App Bar Row
                  Row(
                    children: [
                      // Back Button
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: isDark ? const Color(0xDD0F172A) : const Color(0xDDFFFFFF),
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back_rounded, size: 20),
                          onPressed: () => Navigator.of(context).maybePop(),
                          tooltip: 'Back',
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Graph Header Title and Count
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark ? AppTheme.darkCard.withValues(alpha: 0.92) : const Color(0xDDFFFFFF),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                snapshot.origin.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? AppTheme.darkTextPrimary : const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${snapshot.nodes.length} papers • ${snapshot.citationEdges.length} citations • ${snapshot.similarityEdges.length} similarities',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isDark ? AppTheme.darkTextSecondary : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Save to Library Action
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: isDark ? AppTheme.darkCard.withValues(alpha: 0.92) : const Color(0xDDFFFFFF),
                        child: IconButton(
                          icon: const Icon(Icons.bookmark_add_outlined, size: 20),
                          color: AppTheme.primaryLightBlue,
                          onPressed: () => _saveGraphToLibrary(snapshot),
                          tooltip: 'Cache Graph Offline',
                        ),
                      ),
                    ],
                  ),

                  // Offline / Partial Warning Badges
                  if (fromOfflineCache) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withAlpha(35),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF38BDF8)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off_rounded, size: 14, color: Color(0xFF38BDF8)),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Offline Cached Graph Snapshot',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF38BDF8),
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
                        color: const Color(0xFFF59E0B).withAlpha(35),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFF59E0B)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              snapshot.warnings.isNotEmpty
                                  ? snapshot.warnings.first.message
                                  : 'Partial graph: External providers throttled.',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFF59E0B),
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
                        color: const Color(0xFFF59E0B).withAlpha(35),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFF59E0B)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history_toggle_off_rounded, size: 14, color: Color(0xFFF59E0B)),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Stale Snapshot: Generated >14 days ago. Connect online to refresh.',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFF59E0B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),

        // FLOATING CANVAS CONTROL BUTTONS (Right Side)
        Positioned(
          right: 16,
          bottom: _isBottomSheetOpen ? 390 : 80,
          child: GraphFloatingControls(
            isDark: isDark,
            isBottomSheetOpen: _isBottomSheetOpen,
            onZoomIn: _zoomIn,
            onZoomOut: _zoomOut,
            onResetZoom: _resetZoom,
            onOpenPaperList: () {
              setState(() {
                _isBottomSheetOpen = true;
                _bottomSheetTab = 3;
              });
            },
            onToggleBottomSheet: () {
              setState(() {
                _isBottomSheetOpen = !_isBottomSheetOpen;
              });
            },
          ),
        ),

        // BOTTOM YEAR SPECTRUM LEGEND
        if (!_isBottomSheetOpen)
          Positioned(
            bottom: 18,
            left: 16,
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

        // 4-TAB SLIDING BOTTOM SHEET
        if (_isBottomSheetOpen)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: GraphBottomSheet(
              snapshot: snapshot,
              selectedNode: _selectedNode,
              initialTabIndex: _bottomSheetTab,
              onNodeSelected: (node) {
                setState(() {
                  _selectedNode = node;
                });
              },
              onRecenterGraph: (canonicalId) {
                if (fromOfflineCache) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Cannot synthesize new graphs in offline mode. Connect to the internet to explore new papers.'),
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
              onClose: () {
                setState(() {
                  _isBottomSheetOpen = false;
                });
              },
            ),
          ),
      ],
    );
  }
}
