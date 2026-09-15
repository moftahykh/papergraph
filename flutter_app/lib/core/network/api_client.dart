import 'package:dio/dio.dart';

import '../../models/api_schemas.dart';
import '../../models/graph_models.dart';

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

  PaperGraphApiClient({
    Dio? dio,
    String? baseUrl,
  })  : baseUrl = baseUrl ?? _resolveDefaultBaseUrl(),
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
    dio.interceptors.add(_RetryInterceptor(dio: dio));
    return dio;
  }

  /// Override the backend URL at build/run time:
  ///   flutter run --dart-define=PAPERGRAPH_API_URL=https://api.example.com/api/v1
  ///   flutter build apk --dart-define=PAPERGRAPH_API_URL=https://api.example.com/api/v1
  static const String _envBaseUrl =
      String.fromEnvironment('PAPERGRAPH_API_URL');

  static String _resolveDefaultBaseUrl() {
    if (_envBaseUrl.isNotEmpty) {
      return _envBaseUrl;
    }
    // Default to production cloud backend on Render
    return 'https://papergraph-backend.onrender.com/api/v1';
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
      return SearchResponse.fromJson(Map<String, dynamic>.from(response.data as Map));
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
      return PaperResolveResponse.fromJson(Map<String, dynamic>.from(response.data as Map));
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
      return CreateGraphResponse.fromJson(Map<String, dynamic>.from(response.data as Map));
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
      return GraphStatusResponse.fromJson(Map<String, dynamic>.from(response.data as Map));
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
      return PaperDetailsResponse.fromJson(Map<String, dynamic>.from(response.data as Map));
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
        data: {
          'email': email.trim().toLowerCase(),
          'code': code.trim(),
        },
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
      final msg = data['message'] ?? data['detail'] ?? 'An unexpected server error occurred.';
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

/// Interceptor to automatically retry transient network and DNS errors before failing.
class _RetryInterceptor extends Interceptor {
  final Dio dio;
  static const int _maxRetries = 3;

  _RetryInterceptor({required this.dio});

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
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
