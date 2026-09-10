import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl ?? _resolveDefaultBaseUrl(),
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 15),
                headers: {
                  'Accept': 'application/json',
                  'Content-Type': 'application/json',
                },
              ),
            );

  static String _resolveDefaultBaseUrl() {
    if (kIsWeb) {
      return 'http://localhost:8000/api/v1';
    }
    try {
      if (Platform.isAndroid) {
        // Android emulator loopback alias
        return 'http://10.0.2.2:8000/api/v1';
      }
    } catch (_) {}
    return 'http://localhost:8000/api/v1';
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
      return const ApiException('Connection timed out. Check backend connectivity.');
    }
    final response = error.response;
    if (response != null && response.data is Map) {
      final data = response.data as Map;
      final msg = data['message'] ?? data['detail'] ?? 'An error occurred';
      return ApiException(
        msg.toString(),
        statusCode: response.statusCode,
        errorDetails: data['details'],
      );
    }
    return ApiException(
      error.message ?? 'Network error connecting to PaperGraph backend',
      statusCode: response?.statusCode,
    );
  }
}
