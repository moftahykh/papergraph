import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_core/firebase_core.dart';

import '../../models/api_schemas.dart';
import '../../models/graph_models.dart';
import '../../models/research_monitoring_models.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic errorDetails;

  const ApiException(this.message, {this.statusCode, this.errorDetails});

  @override
  String toString() => 'ApiException: $message (status: $statusCode)';
}

class PaperGraphApiClient {
  final Dio _dio;
  final String baseUrl;

  PaperGraphApiClient({Dio? dio, String? baseUrl})
    : baseUrl = baseUrl ?? _resolveDefaultBaseUrl(),
      _dio = dio ?? _createDefaultDio(baseUrl ?? _resolveDefaultBaseUrl());

  static Dio _createDefaultDio(String base) {
    final dio = Dio(
      BaseOptions(
        baseUrl: base,
        connectTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    );
    dio.interceptors.add(_FirebaseAuthInterceptor());
    dio.interceptors.add(_RetryInterceptor(dio: dio));
    return dio;
  }

  /// Override the backend URL at build/run time:
  ///   flutter run --dart-define=PAPERGRAPH_API_URL=https://api.example.com/api/v1
  ///   flutter build apk --dart-define=PAPERGRAPH_API_URL=https://api.example.com/api/v1
  static const String _envBaseUrl = String.fromEnvironment(
    'PAPERGRAPH_API_URL',
  );

  static String _resolveDefaultBaseUrl() {
    if (_envBaseUrl.isNotEmpty) {
      return _envBaseUrl;
    }
    // Default to production cloud backend on Render
    return 'https://papergraph-backend.onrender.com/api/v1';
  }

  /// Loads server-managed discovery topics and an optional user-grounded
  /// recommendation. The backend intentionally returns no recommendation when
  /// there is no real research signal instead of inventing featured content.
  Future<DiscoveryHomeResponse> getDiscoveryHome({
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.get(
        '/discover/home',
        cancelToken: cancelToken,
      );
      return DiscoveryHomeResponse.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Performs academic literature search.
  Future<SearchResponse> search(
    String query, {
    int limit = 10,
    int offset = 0,
    String? provider,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.get(
        '/search',
        queryParameters: {
          'query': query,
          'limit': limit,
          'offset': offset,
          'provider': ?provider,
        },
        cancelToken: cancelToken,
      );
      return SearchResponse.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Resolves raw DOI, URL, PMID, or title to a CanonicalPaper.
  Future<PaperResolveResponse> resolve(
    String identifier, {
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.post(
        '/papers/resolve',
        data: {'identifier': identifier},
        cancelToken: cancelToken,
      );
      return PaperResolveResponse.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Dispatches asynchronous graph synthesis (returns HTTP 202 Accepted).
  Future<CreateGraphResponse> createGraph(
    CreateGraphRequest request, {
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.post(
        '/graphs',
        data: request.toJson(),
        cancelToken: cancelToken,
      );
      return CreateGraphResponse.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Polls current status of an asynchronous graph generation job.
  Future<GraphStatusResponse> pollGraph(
    String graphId, {
    CancelToken? cancelToken,
  }) async {
    try {
      final cleanId = graphId.startsWith('/api/v1/graphs/')
          ? graphId.replaceFirst('/api/v1/graphs/', '')
          : graphId;
      final response = await _dio.get(
        '/graphs/$cleanId',
        cancelToken: cancelToken,
      );
      return GraphStatusResponse.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Registers a saved graph for automatic research monitoring.
  ///
  /// The endpoint is account-scoped server-side. Anonymous users keep the
  /// local graph, but are not registered for remote monitoring.
  Future<void> registerMonitoredGraph(GraphSnapshot snapshot) async {
    final papers = <Map<String, dynamic>>[];
    final seen = <String>{};

    void addPaper({
      required String canonicalId,
      required String title,
      int? year,
      String? doi,
    }) {
      final cleanId = canonicalId.trim();
      if (cleanId.isEmpty || !seen.add(cleanId)) return;
      papers.add({
        'canonical_id': cleanId,
        'title': title.trim().isEmpty ? 'Untitled work' : title.trim(),
        'year': year,
        'doi': doi,
      });
    }

    addPaper(
      canonicalId: snapshot.origin.canonicalId.isNotEmpty
          ? snapshot.origin.canonicalId
          : snapshot.origin.id,
      title: snapshot.origin.title,
      year: snapshot.origin.year,
      doi: snapshot.origin.doi,
    );
    for (final node in snapshot.nodes) {
      addPaper(
        canonicalId: node.canonicalId.isNotEmpty ? node.canonicalId : node.id,
        title: node.title,
        year: node.year,
        doi: node.doi,
      );
    }

    if (papers.isEmpty) {
      throw const ApiException(
        'The graph has no identifiable papers to monitor.',
      );
    }

    try {
      await _dio.post(
        '/monitoring/graphs',
        data: {
          'local_graph_id': snapshot.graphId,
          'graph_title': snapshot.origin.title,
          'papers': papers,
          'frequency': 'daily',
          'timezone': 'Asia/Riyadh',
        },
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Stops remote monitoring for a locally deleted saved graph.
  Future<void> removeMonitoredGraph(String localGraphId) async {
    try {
      await _dio.delete('/monitoring/graphs/by-local/$localGraphId');
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Lists the signed-in user's saved research-monitoring subscriptions.
  Future<List<MonitoredGraphSummary>> listMonitoredGraphs() async {
    try {
      final response = await _dio.get('/monitoring/graphs');
      final data = response.data as List<dynamic>? ?? const [];
      return data
          .map(
            (item) => MonitoredGraphSummary.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Loads research updates for one monitored graph.
  Future<List<ResearchUpdate>> getResearchUpdates(
    String monitorId, {
    int limit = 50,
  }) async {
    try {
      final response = await _dio.get(
        '/monitoring/graphs/$monitorId/updates',
        queryParameters: {'limit': limit},
      );
      final data = response.data as List<dynamic>? ?? const [];
      return data
          .map(
            (item) =>
                ResearchUpdate.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList();
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Pauses or resumes research monitoring for a saved graph.
  Future<MonitoredGraphSummary> updateMonitoredGraph(
    String monitorId, {
    String? status,
    String? frequency,
    String? timezone,
  }) async {
    try {
      final response = await _dio.patch(
        '/monitoring/graphs/$monitorId',
        data: {
          ...?status == null ? null : {'status': status},
          ...?frequency == null ? null : {'frequency': frequency},
          ...?timezone == null ? null : {'timezone': timezone},
        },
      );
      return MonitoredGraphSummary.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Marks one update as read for the signed-in user.
  Future<ResearchUpdate> markResearchUpdateRead(
    String monitorId,
    String updateId,
  ) async {
    try {
      final response = await _dio.post(
        '/monitoring/graphs/$monitorId/updates/$updateId/read',
      );
      return ResearchUpdate.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Records that the user chose to add an update to the graph.
  ///
  /// The backend currently records the intent; graph snapshot mutation remains
  /// a separate, explicit feature and is never performed automatically.
  Future<ResearchUpdate> markResearchUpdateAdded(
    String monitorId,
    String updateId,
  ) async {
    try {
      final response = await _dio.post(
        '/monitoring/graphs/$monitorId/updates/$updateId/add-to-graph',
      );
      return ResearchUpdate.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Registers the current device token for authenticated research updates.
  Future<void> registerDeviceToken({
    required String fcmToken,
    required String platform,
  }) async {
    try {
      await _dio.post(
        '/monitoring/device-token',
        data: {'fcm_token': fcmToken, 'platform': platform},
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Deactivates a device token when the user opts out or signs out.
  Future<void> removeDeviceToken({
    required String fcmToken,
    required String platform,
  }) async {
    try {
      await _dio.delete(
        '/monitoring/device-token',
        data: {'fcm_token': fcmToken, 'platform': platform},
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Retrieves deep on-demand paper metadata and BibTeX citation.
  Future<PaperDetailsResponse> getPaperDetails(
    String paperId, {
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.get(
        '/papers/$paperId/details',
        cancelToken: cancelToken,
      );
      return PaperDetailsResponse.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Sends a 6-digit verification code to the specified email address via Resend.
  Future<Map<String, dynamic>> sendOtp(String email) async {
    try {
      final response = await _dio.post(
        '/auth/send-otp',
        data: {'email': email.trim().toLowerCase()},
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Verifies the 6-digit OTP code against the backend store.
  Future<Map<String, dynamic>> verifyOtp(String email, String code) async {
    try {
      final response = await _dio.post(
        '/auth/verify-otp',
        data: {'email': email.trim().toLowerCase(), 'code': code.trim()},
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// Checks health status of backend API.
  Future<bool> checkHealth() async {
    try {
      final response = await _dio.get('/health');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  bool get hasAuthenticatedFirebaseUser {
    try {
      return Firebase.apps.isNotEmpty &&
          firebase_auth.FirebaseAuth.instance.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  ApiException _handleDioError(DioException error) {
    if (error.type == DioExceptionType.cancel) {
      return const ApiException('Request was cancelled.');
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return const ApiException(
        'The server took too long to respond. Please try again.',
      );
    }
    if (error.type == DioExceptionType.connectionError ||
        (error.message != null &&
            (error.message!.contains('Failed host lookup') ||
                error.message!.contains('SocketException')))) {
      return const ApiException(
        'Unable to connect to the server. Please check your internet connection and try again.',
      );
    }
    final response = error.response;
    if (response != null && response.data is Map) {
      final data = response.data as Map;
      final msg =
          data['message'] ??
          data['detail'] ??
          'An unexpected server error occurred.';
      return ApiException(
        msg.toString(),
        statusCode: response.statusCode,
        errorDetails: data['details'],
      );
    }
    return const ApiException(
      'Unable to connect to the server. Please check your internet connection and try again.',
    );
  }
}

/// Adds the current Firebase ID token when a signed-in Firebase app is ready.
///
/// Public endpoints remain usable for anonymous users. Protected endpoints
/// should enforce authentication server-side; this interceptor only transports
/// the token and never treats a local Firebase session as proof of authorization.
class _FirebaseAuthInterceptor extends Interceptor {
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      if (Firebase.apps.isNotEmpty) {
        final user = firebase_auth.FirebaseAuth.instance.currentUser;
        if (user != null) {
          final token = await user.getIdToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        }
      }
    } catch (_) {
      // Keep anonymous/public requests usable when Firebase is unavailable.
    }
    handler.next(options);
  }
}

/// Interceptor to automatically retry transient network and DNS errors before failing.
class _RetryInterceptor extends Interceptor {
  final Dio dio;
  static const int _maxRetries = 3;

  _RetryInterceptor({required this.dio});

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Retrying POST requests can create duplicate graph jobs or send duplicate
    // OTPs when the server accepted the first request but its response was
    // interrupted. Retry only idempotent reads unless the backend introduces
    // an explicit idempotency-key contract.
    final method = err.requestOptions.method.toUpperCase();
    const retryableMethods = {'GET', 'HEAD', 'OPTIONS'};
    if (!retryableMethods.contains(method)) {
      return super.onError(err, handler);
    }

    final bool isTransientError =
        err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.unknown ||
        (err.message != null &&
            (err.message!.contains('Failed host lookup') ||
                err.message!.contains('SocketException')));

    if (!isTransientError) {
      return super.onError(err, handler);
    }

    DioException lastError = err;
    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      await Future.delayed(Duration(milliseconds: 1500 * attempt));
      try {
        final response = await dio.fetch(err.requestOptions);
        return handler.resolve(response);
      } on DioException catch (retryErr) {
        lastError = retryErr;
        final bool stillTransient =
            retryErr.type == DioExceptionType.connectionError ||
            retryErr.type == DioExceptionType.connectionTimeout ||
            retryErr.type == DioExceptionType.unknown ||
            (retryErr.message != null &&
                (retryErr.message!.contains('Failed host lookup') ||
                    retryErr.message!.contains('SocketException')));
        if (!stillTransient) {
          return super.onError(retryErr, handler);
        }
      } catch (_) {
        return super.onError(lastError, handler);
      }
    }

    return super.onError(lastError, handler);
  }
}
