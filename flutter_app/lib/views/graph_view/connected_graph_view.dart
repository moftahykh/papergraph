import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import '../../core/theme/app_theme.dart';
import '../../cubits/graph/graph_cubit.dart';
import '../../cubits/graph/graph_state.dart';
import '../../cubits/library/library_cubit.dart';
import '../../cubits/notification/notification_cubit.dart';
import '../../cubits/notification/notification_state.dart';
import '../../cubits/paper_details/paper_details_cubit.dart';
import '../../models/graph_job_status.dart';
import '../../models/graph_models.dart';
import '../../models/paper_model.dart';
import '../paper_details/paper_details_view.dart';
import 'painters/graph_canvas_painter.dart';
import 'widgets/graph_bottom_sheet.dart';
import 'widgets/graph_year_legend.dart';

extension GraphJobStatusDisplay on GraphJobStatus {
  String get displayTitle {
    switch (this) {
      case GraphJobStatus.queued:
        return 'Queueing graph task...';
      case GraphJobStatus.resolvingOrigin:
        return 'Resolving seed paper identity...';
      case GraphJobStatus.generatingCandidates:
        return 'Generating candidate literature pool...';
      case GraphJobStatus.preRanking:
        return 'Applying PreScore quotas...';
      case GraphJobStatus.enrichingMetadata:
        return 'Enriching canonical paper metadata...';
      case GraphJobStatus.enrichingReferences:
        return 'Harvesting foundational references...';
      case GraphJobStatus.computingWbc:
        return 'Computing Co-Citation (WBC) matrix...';
      case GraphJobStatus.enrichingCitations:
        return 'Harvesting derivative citations...';
      case GraphJobStatus.computingNcc:
        return 'Computing Bibliographic Coupling (NCC)...';
      case GraphJobStatus.computingFinalScores:
        return 'Computing safe hybrid ranking scores...';
      case GraphJobStatus.extractingPriorWorks:
        return 'Extracting foundational prior works...';
      case GraphJobStatus.extractingDerivativeWorks:
        return 'Extracting subsequent derivative works...';
      case GraphJobStatus.buildingLayout:
        return 'Synthesizing 2D force-directed layout...';
      case GraphJobStatus.completed:
        return 'Graph generation complete';
      case GraphJobStatus.partial:
        return 'Graph generated with partial coverage';
      case GraphJobStatus.failed:
        return 'Graph generation failed';
    }
  }
}

class ConnectedGraphView extends StatefulWidget {
  final PaperModel? centerPaper;
  final String? seedDoi;
  final GraphSnapshot? initialSnapshot;

  const ConnectedGraphView({
    super.key,
    this.centerPaper,
    this.seedDoi,
    this.initialSnapshot,
  });

  @override
  State<ConnectedGraphView> createState() => _ConnectedGraphViewState();
}

class _ConnectedGraphViewState extends State<ConnectedGraphView>
    with SingleTickerProviderStateMixin {
  late TransformationController _transformController;
  late AnimationController _pulseController;

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
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

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
      // If current state is initial or not for this paper, dispatch graph generation
      if (graphCubit.state is GraphInitial) {
        graphCubit.buildGraphFromDoi(seed);
      }
    }
  }

  void _centerCanvas() {
    // Centers the 2000x2000 canvas in the middle of viewport
    final screenSize = MediaQuery.of(context).size;
    final dx = (screenSize.width - _canvasSize) / 2;
    final dy = (screenSize.height - _canvasSize) / 2;
    _transformController.value = Matrix4.identity()
      ..setTranslationRaw(dx, dy, 0.0);
  }

  void _resetZoom() {
    setState(() {
      _centerCanvas();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
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

  void _onPanStart(DragStartDetails details, List<GraphNode> nodes, int maxCitations) {
    final hit = _hitTestNode(details.localPosition, nodes, maxCitations);
    if (hit != null) {
      setState(() {
        _draggingNodeId = hit.canonicalId;
        _selectedNode = hit;
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
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

  void _onPanEnd(DragEndDetails details) {
    if (_draggingNodeId != null) {
      setState(() {
        _draggingNodeId = null;
      });
    }
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
      abstractText: 'Synthesized node from PaperGraph discovery engine.',
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
      backgroundColor: isDark ? const Color(0xFF090D16) : const Color(0xFFF1F5F9),
      body: BlocConsumer<GraphCubit, GraphState>(
        listener: (context, state) {
          if (state is GraphLoaded && state.snapshot.nodes.isNotEmpty) {
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
        },
        builder: (context, state) {
          if (state is GraphCreating || state is GraphPolling) {
            return _buildProgressiveLoadingView(state, isDark);
          }

          if (state is GraphError) {
            return _buildErrorView(state, isDark);
          }

          if (state is GraphLoaded) {
            return _buildGraphCanvasView(state.snapshot, state.isPartial, state.fromOfflineCache, isDark);
          }

          // Fallback initial or empty state
          return _buildEmptyStateView(isDark);
        },
      ),
    );
  }

  // 1. PROGRESSIVE LOADING STATE (Tracking all 16 lifecycle stages)
  Widget _buildProgressiveLoadingView(GraphState state, bool isDark) {
    GraphJobStatus currentStage = GraphJobStatus.queued;
    double progress = 0.05;

    if (state is GraphPolling) {
      currentStage = state.currentStage;
      progress = state.progress.clamp(0.05, 0.98);
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 28),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 140 : 30),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated Pulse Spinner
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 4.5,
                    backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryBlue),
                  ),
                ),
                Icon(
                  Icons.hub_rounded,
                  size: 32,
                  color: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue,
                ),
              ],
            ),

            const SizedBox(height: 24),

            Text(
              'Synthesizing Literature Graph',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),

            const SizedBox(height: 8),

            // Current Stage Description
            Text(
              currentStage.displayTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
              ),
            ),

            const SizedBox(height: 16),

            // Linear Progress Bar with percentage
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryBlue),
              ),
            ),

            const SizedBox(height: 8),

            Text(
              '${(progress * 100).toInt()}% completed',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),

            const SizedBox(height: 20),

            // Cancel Button
            OutlinedButton.icon(
              onPressed: () => context.read<GraphCubit>().cancel(),
              icon: const Icon(Icons.cancel_outlined, size: 16),
              label: const Text('Cancel Job', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFEF4444),
                side: const BorderSide(color: Color(0xFFEF4444)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 2. ERROR STATE WITH RETRY ACTION
  Widget _buildErrorView(GraphError state, bool isDark) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFEF4444).withAlpha(100)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: Color(0xFFEF4444)),
            const SizedBox(height: 16),
            Text(
              'Unable to Generate Graph',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              state.message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Go Back'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => context.read<GraphCubit>().retry(),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ),
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
        // Interactive 2D Hardware-Accelerated Canvas
        GestureDetector(
          onTapUp: (details) => _onTapCanvas(details, snapshot.nodes, maxCitations),
          onPanStart: (details) => _onPanStart(details, snapshot.nodes, maxCitations),
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          onDoubleTap: _resetZoom,
          child: InteractiveViewer(
            transformationController: _transformController,
            boundaryMargin: const EdgeInsets.all(1200),
            minScale: 0.25,
            maxScale: 3.5,
            panEnabled: _draggingNodeId == null,
            child: SizedBox(
              width: _canvasSize,
              height: _canvasSize,
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) {
                  return CustomPaint(
                    size: const Size(_canvasSize, _canvasSize),
                    painter: GraphCanvasPainter(
                      nodes: snapshot.nodes,
                      citationEdges: snapshot.citationEdges,
                      similarityEdges: snapshot.similarityEdges,
                      selectedNodeId: _selectedNode?.canonicalId,
                      pulseValue: _pulseController.value,
                      isDark: isDark,
                      draggedPositions: _draggedPositions,
                    ),
                  );
                },
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
                            color: isDark ? const Color(0xDD0F172A) : const Color(0xDDFFFFFF),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                snapshot.origin.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${snapshot.nodes.length} papers • ${snapshot.citationEdges.length} citations • ${snapshot.similarityEdges.length} similarities',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
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
                        backgroundColor: isDark ? const Color(0xDD0F172A) : const Color(0xDDFFFFFF),
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
                ],
              ),
            ),
          ),
        ),

        // FLOATING CANVAS CONTROL BUTTONS (Right Side)
        Positioned(
          right: 16,
          bottom: _isBottomSheetOpen ? 390 : 80,
          child: Column(
            children: [
              _buildFloatingControlButton(
                icon: Icons.center_focus_strong_rounded,
                tooltip: 'Reset Zoom & Center',
                isDark: isDark,
                onPressed: _resetZoom,
              ),
              const SizedBox(height: 8),
              _buildFloatingControlButton(
                icon: Icons.list_alt_rounded,
                tooltip: 'Open Paper List',
                isDark: isDark,
                onPressed: () {
                  setState(() {
                    _isBottomSheetOpen = true;
                    _bottomSheetTab = 3;
                  });
                },
              ),
              const SizedBox(height: 8),
              _buildFloatingControlButton(
                icon: _isBottomSheetOpen ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
                tooltip: _isBottomSheetOpen ? 'Hide Details' : 'Show Details',
                isDark: isDark,
                onPressed: () {
                  setState(() {
                    _isBottomSheetOpen = !_isBottomSheetOpen;
                  });
                },
              ),
            ],
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

  Widget _buildFloatingControlButton({
    required IconData icon,
    required String tooltip,
    required bool isDark,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xDD0F172A) : const Color(0xDDFFFFFF),
        shape: BoxShape.circle,
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 80 : 25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, size: 20),
        color: isDark ? Colors.white : AppTheme.primaryBlue,
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }

  // 4. EMPTY STATE VIEW
  Widget _buildEmptyStateView(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.hub_outlined,
            size: 64,
            color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
          ),
          const SizedBox(height: 16),
          Text(
            'No Graph Loaded',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select a seed paper or enter a DOI to synthesize a new literature graph.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.search_rounded, size: 16),
            label: const Text('Explore Literature'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}
