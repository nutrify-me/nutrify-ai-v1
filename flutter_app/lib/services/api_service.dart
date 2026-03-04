import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/user.dart';
import '../models/nutrition.dart';
import '../models/fitness.dart';
import '../models/progress.dart';
import '../models/ai.dart';
import '../models/workout_session.dart';
import '../models/gamification.dart';
import 'request_cache_service.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, [this.statusCode]);

  @override
  String toString() => 'ApiException: $message';
}

class ApiService {
  // Azure-hosted backend — works from anywhere
  static const String _baseUrl = 'https://nutrify-backend.yellowdesert-8e1592bf.centralindia.azurecontainerapps.io/api/v1';
  static const String _storageKeyToken = 'auth_token';
  static const String _storageKeyRefreshToken = 'refresh_token';

  final http.Client _client = http.Client();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final Logger _logger = Logger();

  String? _cachedToken;
  String? _cachedUserId;

  // Singleton pattern
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  Future<String?> get _token async {
    _cachedToken ??= await _storage.read(key: _storageKeyToken);
    return _cachedToken;
  }

  Future<void> setToken(String token) async {
    await _storage.write(key: _storageKeyToken, value: token);
    _cachedToken = token;
  }

  /// Set user ID for cache key scoping
  void setUserId(String userId) {
    _cachedUserId = userId;
  }

  /// Get user-specific cache key
  String _getUserCacheKey(String baseKey) {
    if (_cachedUserId != null) {
      return '${baseKey}_user_${_cachedUserId}';
    }
    return baseKey; // Fallback for cases where user ID isn't set yet
  }

  /// Initialize user session after login/register
  Future<void> _initializeUserSession() async {
    try {
      // Clear any stale cache from previous users
      requestCache.clear();
      _logger.i('Cleared cache on login');

      // Fetch and store current user ID
      final user = await getCurrentUser(forceRefresh: true);
      _cachedUserId = user.id;
      _logger.i('Set user ID: ${_cachedUserId}');
    } catch (e) {
      _logger.e('Failed to initialize user session: $e');
    }
  }

  Future<void> _setToken(String? token) async {
    if (token != null) {
      await _storage.write(key: _storageKeyToken, value: token);
      _cachedToken = token;
    } else {
      await _storage.delete(key: _storageKeyToken);
      _cachedToken = null;
    }
  }

  Future<void> _setRefreshToken(String? refreshToken) async {
    if (refreshToken != null) {
      await _storage.write(key: _storageKeyRefreshToken, value: refreshToken);
    } else {
      await _storage.delete(key: _storageKeyRefreshToken);
    }
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  Future<Map<String, String>> get _authHeaders async {
    final token = await _token;
    return {
      ..._headers,
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<T> _makeRequest<T>(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
    bool requiresAuth = true,
    T Function(dynamic)? fromJson,
    Duration? timeout,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl$endpoint');
      final headers = requiresAuth ? await _authHeaders : _headers;
      final requestTimeout = timeout ?? const Duration(seconds: 60);

      _logger.d('$method $endpoint');

      http.Response response;
      switch (method.toLowerCase()) {
        case 'get':
          response = await _client.get(url, headers: headers).timeout(requestTimeout);
          break;
        case 'post':
          response = await _client.post(
            url,
            headers: headers,
            body: body != null ? json.encode(body) : null,
          ).timeout(requestTimeout);
          break;
        case 'put':
          response = await _client.put(
            url,
            headers: headers,
            body: body != null ? json.encode(body) : null,
          ).timeout(requestTimeout);
          break;
        case 'delete':
          response = await _client.delete(url, headers: headers).timeout(requestTimeout);
          break;
        default:
          throw ArgumentError('Unsupported method: $method');
      }

      _logger.d('Response ${response.statusCode}: ${response.body}');

      if (response.statusCode == 401 && requiresAuth) {
        // Token expired, try to refresh and retry request once
        _logger.d('Token expired, attempting refresh');
        await _refreshToken();

        // Retry the request with new token
        final newHeaders = await _authHeaders;
        http.Response retryResponse;
        switch (method.toLowerCase()) {
          case 'get':
            retryResponse = await _client.get(url, headers: newHeaders).timeout(requestTimeout);
            break;
          case 'post':
            retryResponse = await _client.post(
              url,
              headers: newHeaders,
              body: body != null ? json.encode(body) : null,
            ).timeout(requestTimeout);
            break;
          case 'put':
            retryResponse = await _client.put(
              url,
              headers: newHeaders,
              body: body != null ? json.encode(body) : null,
            ).timeout(requestTimeout);
            break;
          case 'delete':
            retryResponse = await _client.delete(url, headers: newHeaders).timeout(requestTimeout);
            break;
          default:
            throw ArgumentError('Unsupported method: $method');
        }

        if (retryResponse.statusCode >= 400) {
          final errorData = json.decode(retryResponse.body);
          throw ApiException(
            errorData['detail'] ?? 'Request failed after refresh',
            retryResponse.statusCode,
          );
        }

        response = retryResponse;
      }

      if (response.statusCode >= 400) {
        final errorData = json.decode(response.body);
        // Handle both string and list detail formats (FastAPI validation errors return a list)
        String errorMessage;
        final detail = errorData['detail'];
        if (detail is String) {
          errorMessage = detail;
        } else if (detail is List && detail.isNotEmpty) {
          // Extract first validation error message
          final firstError = detail.first;
          if (firstError is Map) {
            errorMessage = firstError['msg'] ?? 'Validation error';
          } else {
            errorMessage = detail.map((e) => e.toString()).join(', ');
          }
        } else {
          errorMessage = 'Request failed';
        }
        throw ApiException(errorMessage, response.statusCode);
      }

      if (response.body.isEmpty) {
        return null as T;
      }

      final responseData = json.decode(response.body);

      if (fromJson != null) {
        return fromJson(responseData);
      }

      return responseData as T;
    } on FormatException {
      throw ApiException('Invalid response format');
    } on TimeoutException {
      throw ApiException('Request timed out. Please try again.');
    } catch (e) {
      if (e is ApiException) rethrow;
      if (e.toString().contains('SocketException') || e.toString().contains('Connection refused')) {
        throw ApiException('Network connection failed');
      }
      throw ApiException('Request failed: $e');
    }
  }

  Future<void> _refreshToken() async {
    try {
      final refreshToken = await _storage.read(key: _storageKeyRefreshToken);
      if (refreshToken == null) {
        throw ApiException('No refresh token available');
      }

      _logger.d('Attempting to refresh token');

      final url = Uri.parse('$_baseUrl/auth/refresh');
      final response = await _client.post(
        url,
        headers: _headers,
        body: json.encode({'refresh_token': refreshToken}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final newToken = data['access_token'];
        final newRefreshToken = data['refresh_token'];

        await _setToken(newToken);
        await _setRefreshToken(newRefreshToken);

        _logger.d('Token refreshed successfully');
      } else {
        _logger.e('Token refresh failed: ${response.statusCode}');
        // Clear tokens and force re-login
        await logout();
        throw ApiException('Token refresh failed, please log in again');
      }
    } catch (e) {
      _logger.e('Error refreshing token: $e');
      await logout();
      throw ApiException('Token refresh failed, please log in again');
    }
  }

  // Authentication methods
  Future<AuthResponse> login(String email, String password) async {
    final response = await _makeRequest<Map<String, dynamic>>(
      'POST',
      '/auth/login',
      body: {
        'email': email,
        'password': password,
      },
      requiresAuth: false,
    );

    final authResponse = AuthResponse.fromJson(response);
    await _setToken(authResponse.token);
    await _setRefreshToken(authResponse.refreshToken);

    // Initialize user session (clear cache, fetch user ID)
    await _initializeUserSession();

    return authResponse;
  }

  Future<AuthResponse> googleSignIn() async {
    final response = await _makeRequest<Map<String, dynamic>>(
      'POST',
      '/auth/google',
      body: {},
      requiresAuth: false,
    );

    final authResponse = AuthResponse.fromJson(response);
    await _setToken(authResponse.token);
    await _setRefreshToken(authResponse.refreshToken);

    // Initialize user session (clear cache, fetch user ID)
    await _initializeUserSession();

    return authResponse;
  }

  Future<AuthResponse> register(String email, String password, String name) async {
    final response = await _makeRequest<Map<String, dynamic>>(
      'POST',
      '/auth/register',
      body: {
        'email': email,
        'password': password,
        'name': name,
      },
      requiresAuth: false,
    );

    final authResponse = AuthResponse.fromJson(response);
    await _setToken(authResponse.token);
    await _setRefreshToken(authResponse.refreshToken);

    // Initialize user session (clear cache, fetch user ID)
    await _initializeUserSession();

    return authResponse;
  }

  Future<void> logout() async {
    try {
      // Call backend logout endpoint
      await _makeRequest<void>(
        'POST',
        '/auth/logout',
        requiresAuth: true,
      );
    } catch (e) {
      _logger.e('Logout API call failed: $e');
      // Continue with local logout even if API call fails
    } finally {
      // Clear local tokens
      await _setToken(null);
      await _setRefreshToken(null);
      _cachedUserId = null;

      // CRITICAL: Clear ALL cached data when user logs out
      requestCache.clear();
      _logger.i('Cleared all cache on logout');
    }
  }

  Future<bool> get isLoggedIn async {
    final token = await _token;
    return token != null;
  }

  // User methods
  Future<User> getCurrentUser({bool forceRefresh = false}) async {
    return await requestCache.deduplicate(
      _getUserCacheKey('user_current'),
      () async {
        final response = await _makeRequest<Map<String, dynamic>>(
          'GET',
          '/users/me/basic',
        );
        return User.fromJson(response);
      },
      ttl: const Duration(minutes: 15),
      forceRefresh: forceRefresh,
    );
  }

  Future<UserProfile> getUserProfile({bool forceRefresh = false}) async {
    return await requestCache.deduplicate(
      _getUserCacheKey('user_profile'),
      () async {
        final response = await _makeRequest<Map<String, dynamic>>(
          'GET',
          '/users/me',
        );
        return UserProfile.fromJson(response);
      },
      ttl: const Duration(minutes: 15),
      forceRefresh: forceRefresh,
    );
  }

  Future<UserProfile> updateUserProfile(Map<String, dynamic> profileData) async {
    final response = await _makeRequest<Map<String, dynamic>>(
      'PUT',
      '/users/me',
      body: profileData,
    );
    // Invalidate user caches after profile update
    requestCache.invalidate(_getUserCacheKey('user_current'));
    requestCache.invalidate(_getUserCacheKey('user_profile'));
    return UserProfile.fromJson(response);
  }

  // Nutrition methods
  Future<NutritionPlan> getCurrentNutritionPlan({bool forceRefresh = false}) async {
    return await requestCache.deduplicate(
      _getUserCacheKey('nutrition_plan_current'),
      () async {
        final response = await _makeRequest<Map<String, dynamic>>(
          'GET',
          '/nutrition/current-plan',
        );
        return NutritionPlan.fromJson(response);
      },
      ttl: const Duration(minutes: 10),
      forceRefresh: forceRefresh,
    );
  }

  Future<NutritionPlan> generateNutritionPlan() async {
    final response = await _makeRequest<Map<String, dynamic>>(
      'POST',
      '/nutrition/generate',
      // AI generation can take 3-5 minutes
      timeout: const Duration(minutes: 6),
    );
    // Invalidate cached nutrition plan since we just generated a new one
    requestCache.invalidate(_getUserCacheKey('nutrition_plan_current'));
    return NutritionPlan.fromJson(response);
  }

  Future<Map<String, dynamic>> logMeal({
    required String mealDate,
    required String mealType,
    String? mealId,
    String? customMealName,
    int? calories,
    double? proteinGrams,
    double? carbsGrams,
    double? fatGrams,
    int? satisfactionRating,
    Map<String, dynamic>? customFoods,
  }) async {
    final response = await _makeRequest<Map<String, dynamic>>(
      'POST',
      '/nutrition/log-meal',
      body: {
        'meal_date': mealDate,
        'meal_type': mealType,
        if (mealId != null) 'meal_id': mealId,
        if (customMealName != null) 'custom_meal_name': customMealName,
        if (calories != null) 'calories': calories,
        if (proteinGrams != null) 'protein_grams': proteinGrams,
        if (carbsGrams != null) 'carbs_grams': carbsGrams,
        if (fatGrams != null) 'fat_grams': fatGrams,
        if (satisfactionRating != null) 'satisfaction_rating': satisfactionRating,
        if (customFoods != null) 'custom_foods': customFoods,
      },
    );
    return response;
  }

  Future<List<Map<String, dynamic>>> getMealLogs({int days = 7}) async {
    final response = await _makeRequest<List<dynamic>>(
      'GET',
      '/nutrition/meal-logs?days=$days',
    );
    return response.cast<Map<String, dynamic>>();
  }

  // Fitness methods
  Future<WorkoutPlan> getCurrentWorkoutPlan({bool forceRefresh = false}) async {
    return await requestCache.deduplicate(
      _getUserCacheKey('fitness_plan_current'),
      () async {
        final response = await _makeRequest<Map<String, dynamic>>(
          'GET',
          '/fitness/current-plan',
        );
        return WorkoutPlan.fromJson(response);
      },
      ttl: const Duration(minutes: 10),
      forceRefresh: forceRefresh,
    );
  }

  Future<WorkoutPlan> generateWorkoutPlan() async {
    final response = await _makeRequest<Map<String, dynamic>>(
      'POST',
      '/fitness/generate',
      // AI generation can take 3-5 minutes
      timeout: const Duration(minutes: 6),
    );
    // Invalidate cached fitness plan since we just generated a new one
    requestCache.invalidate(_getUserCacheKey('fitness_plan_current'));
    return WorkoutPlan.fromJson(response);
  }

  Future<Map<String, dynamic>> logWorkout({
    required String workoutDate,
    required int durationMinutes,
    String? workoutId,
    String? workoutName,
    int? caloriesBurned,
    int? perceivedExertion,
    int? moodAfter,
    bool completed = true,
    int? completionPercentage,
    String? notes,
  }) async {
    final response = await _makeRequest<Map<String, dynamic>>(
      'POST',
      '/fitness/log-workout',
      body: {
        'workout_date': workoutDate,
        'duration_minutes': durationMinutes,
        if (workoutId != null) 'workout_id': workoutId,
        if (workoutName != null) 'workout_name': workoutName,
        if (caloriesBurned != null) 'calories_burned': caloriesBurned,
        if (perceivedExertion != null) 'perceived_exertion': perceivedExertion,
        if (moodAfter != null) 'mood_after': moodAfter,
        'completed': completed,
        if (completionPercentage != null) 'completion_percentage': completionPercentage,
        if (notes != null) 'notes': notes,
      },
    );
    return response;
  }

  Future<List<Map<String, dynamic>>> getWorkoutLogs({int days = 7}) async {
    final response = await _makeRequest<List<dynamic>>(
      'GET',
      '/fitness/workout-logs?days=$days',
    );
    return response.cast<Map<String, dynamic>>();
  }

  // Progress methods
  Future<List<ProgressEntry>> getProgressHistory({int days = 30}) async {
    final response = await _makeRequest<List<dynamic>>(
      'GET',
      '/progress?days=$days',
    );
    return response.map((json) => ProgressEntry.fromJson(json)).toList();
  }

  Future<ProgressEntry> logProgress(ProgressEntry progressData) async {
    final response = await _makeRequest<Map<String, dynamic>>(
      'POST',
      '/progress',
      body: progressData.toJson(),
    );
    return ProgressEntry.fromJson(response);
  }

  Future<List<ProgressEntry>> getProgressEntries({int limit = 30}) async {
    final response = await _makeRequest<List<dynamic>>(
      'GET',
      '/progress?limit=$limit',
    );
    return response.map((json) => ProgressEntry.fromJson(json)).toList();
  }

  Future<ProgressEntry> createProgressEntry(ProgressEntryCreate progressData) async {
    final response = await _makeRequest<Map<String, dynamic>>(
      'POST',
      '/progress',
      body: progressData.toJson(),
    );
    return ProgressEntry.fromJson(response);
  }

  Future<ProgressEntry> updateProgressEntry(String id, ProgressEntry progressData) async {
    final response = await _makeRequest<Map<String, dynamic>>(
      'PUT',
      '/progress/$id',
      body: progressData.toJson(),
    );
    return ProgressEntry.fromJson(response);
  }

  Future<void> deleteProgressEntry(String id) async {
    await _makeRequest(
      'DELETE',
      '/progress/$id',
    );
  }

  // AI methods
  Future<List<AIInsight>> getAIInsights({int limit = 10}) async {
    final response = await _makeRequest<List<dynamic>>(
      'GET',
      '/ai/insights?limit=$limit',
    );
    return response.map((json) => AIInsight.fromJson(json)).toList();
  }

  Future<List<AIInsight>> requestAIAnalysis() async {
    final response = await _makeRequest<List<dynamic>>(
      'POST',
      '/ai/analyze',
    );
    return response.map((json) => AIInsight.fromJson(json)).toList();
  }

  Future<ChatResponse> chatWithAI(String message) async {
    final response = await _makeRequest<Map<String, dynamic>>(
      'POST',
      '/ai/chat',
      body: {'message': message},
    );
    return ChatResponse.fromJson(response);
  }

  // Subscription methods
  Future<Map<String, dynamic>?> getCurrentSubscription() async {
    try {
      final response = await _makeRequest<Map<String, dynamic>>(
        'GET',
        '/subscriptions/current',
      );
      return response;
    } catch (e) {
      _logger.e('Failed to get subscription: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> createCheckoutSession({
    required String tier,
    required String billingPeriod,
    required String successUrl,
    required String cancelUrl,
  }) async {
    final response = await _makeRequest<Map<String, dynamic>>(
      'POST',
      '/subscriptions/checkout',
      body: {
        'tier': tier,
        'billing_period': billingPeriod,
        'success_url': successUrl,
        'cancel_url': cancelUrl,
      },
    );
    return response;
  }

  Future<Map<String, dynamic>> createPortalSession({
    required String returnUrl,
  }) async {
    final response = await _makeRequest<Map<String, dynamic>>(
      'POST',
      '/subscriptions/portal',
      body: {
        'return_url': returnUrl,
      },
    );
    return response;
  }

  Future<void> cancelSubscription() async {
    await _makeRequest(
      'POST',
      '/subscriptions/cancel',
    );
  }

  Future<List<dynamic>> getPaymentHistory() async {
    final response = await _makeRequest<List<dynamic>>(
      'GET',
      '/subscriptions/payments',
    );
    return response;
  }

  // OCR Food Logging methods
  Future<Map<String, dynamic>> analyzeFoodImage(String imagePath) async {
    try {
      final url = Uri.parse('$_baseUrl/nutrition/analyze-food-image');
      final headers = await _authHeaders;

      var request = http.MultipartRequest('POST', url);
      request.headers.addAll(headers);
      request.files.add(await http.MultipartFile.fromPath('file', imagePath));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      _logger.d('Response ${response.statusCode}: ${response.body}');

      if (response.statusCode >= 400) {
        final errorData = json.decode(response.body);
        throw ApiException(
          errorData['detail'] ?? 'Failed to analyze food image',
          response.statusCode,
        );
      }

      return json.decode(response.body);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to analyze food image: $e');
    }
  }

  Future<Map<String, dynamic>> analyzeFoodFromUrl(String imageUrl) async {
    final response = await _makeRequest<Map<String, dynamic>>(
      'POST',
      '/nutrition/analyze-food-url',
      body: {'image_url': imageUrl},
    );
    return response;
  }

  Future<List<dynamic>> getFoodSuggestions(String query) async {
    final response = await _makeRequest<Map<String, dynamic>>(
      'GET',
      '/nutrition/food-suggestions?query=${Uri.encodeComponent(query)}',
    );
    return response['suggestions'] ?? [];
  }

  // === Async Generation Methods (SSE) ===

  /// Start async nutrition plan generation
  Future<Map<String, dynamic>> startNutritionPlanGeneration() async {
    final response = await _makeRequest<Map<String, dynamic>>(
      'POST',
      '/nutrition/generate-async',
    );
    return response;
  }

  /// Start async fitness plan generation
  Future<Map<String, dynamic>> startFitnessPlanGeneration() async {
    final response = await _makeRequest<Map<String, dynamic>>(
      'POST',
      '/fitness/generate-async',
    );
    return response;
  }

  /// Get generation status (polling)
  Future<Map<String, dynamic>> getNutritionGenerationStatus(String taskId) async {
    final response = await _makeRequest<Map<String, dynamic>>(
      'GET',
      '/nutrition/generation-status/$taskId',
    );
    return response;
  }

  /// Get fitness generation status (polling)
  Future<Map<String, dynamic>> getFitnessGenerationStatus(String taskId) async {
    final response = await _makeRequest<Map<String, dynamic>>(
      'GET',
      '/fitness/generation-status/$taskId',
    );
    return response;
  }

  /// Stream nutrition generation status via SSE
  Stream<GenerationEvent> streamNutritionGenerationStatus(String taskId) {
    return _streamGenerationStatus('/nutrition/generation-status/$taskId/stream');
  }

  /// Stream fitness generation status via SSE
  Stream<GenerationEvent> streamFitnessGenerationStatus(String taskId) {
    return _streamGenerationStatus('/fitness/generation-status/$taskId/stream');
  }

  /// Internal method to stream SSE events
  Stream<GenerationEvent> _streamGenerationStatus(String endpoint) async* {
    final token = await _token;
    final url = Uri.parse('$_baseUrl$endpoint');

    final client = http.Client();
    try {
      final request = http.Request('GET', url);
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache';
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      final response = await client.send(request);

      if (response.statusCode != 200) {
        yield GenerationEvent(
          event: 'error',
          data: {'error': 'Failed to connect to SSE stream'},
        );
        return;
      }

      String buffer = '';

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        buffer += chunk;

        // SSE format: "event: <type>\ndata: <json>\n\n"
        while (buffer.contains('\n\n')) {
          final index = buffer.indexOf('\n\n');
          final message = buffer.substring(0, index);
          buffer = buffer.substring(index + 2);

          final event = _parseSSEMessage(message);
          if (event != null) {
            yield event;

            // Stop streaming if done or error
            if (event.event == 'done' || event.event == 'error') {
              return;
            }
          }
        }
      }
    } catch (e) {
      _logger.e('SSE stream error: $e');
      yield GenerationEvent(
        event: 'error',
        data: {'error': e.toString()},
      );
    } finally {
      client.close();
    }
  }

  GenerationEvent? _parseSSEMessage(String message) {
    String? eventType;
    String? data;

    for (final line in message.split('\n')) {
      if (line.startsWith('event:')) {
        eventType = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        data = line.substring(5).trim();
      }
    }

    if (data != null) {
      try {
        final jsonData = json.decode(data) as Map<String, dynamic>;
        return GenerationEvent(
          event: eventType ?? 'message',
          data: jsonData,
        );
      } catch (e) {
        _logger.e('Failed to parse SSE data: $data');
        return null;
      }
    }
    return null;
  }

  // Fitness plan alias for sync service
  Future<WorkoutPlan?> getCurrentFitnessPlan() async {
    try {
      return await getCurrentWorkoutPlan();
    } catch (e) {
      if (e.toString().contains('404')) {
        return null;
      }
      rethrow;
    }
  }

  // === Workout Session Methods (Set-level tracking) ===

  /// Start a new workout session
  Future<WorkoutSession> startWorkoutSession({
    String? workoutId,
    required String workoutName,
  }) async {
    final response = await _makeRequest<Map<String, dynamic>>(
      'POST',
      '/workout-sessions/start',
      body: {
        if (workoutId != null) 'workout_id': workoutId,
        'workout_name': workoutName,
      },
    );
    _logger.d('startWorkoutSession response: $response');
    try {
      return WorkoutSession.fromJson(response);
    } catch (e, stackTrace) {
      _logger.e('Failed to parse WorkoutSession: $e');
      _logger.e('Response was: $response');
      _logger.e('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Get the current active workout session
  Future<WorkoutSession?> getActiveWorkoutSession() async {
    try {
      final response = await _makeRequest<Map<String, dynamic>?>(
        'GET',
        '/workout-sessions/active',
      );
      if (response == null) return null;
      return WorkoutSession.fromJson(response);
    } catch (e) {
      if (e.toString().contains('404')) {
        return null;
      }
      rethrow;
    }
  }

  /// Log a single set in the workout session
  Future<ExerciseSet> logWorkoutSet({
    required String sessionId,
    String? exerciseId,
    required String exerciseName,
    required int setNumber,
    required double weightKg,
    required int reps,
    bool isWarmup = false,
    int restSeconds = 90,
    String? notes,
  }) async {
    final response = await _makeRequest<Map<String, dynamic>>(
      'POST',
      '/workout-sessions/$sessionId/sets',
      body: {
        if (exerciseId != null) 'exercise_id': exerciseId,
        'exercise_name': exerciseName,
        'set_number': setNumber,
        'weight_kg': weightKg,
        'reps': reps,
        'is_warmup': isWarmup,
        'rest_seconds': restSeconds,
        if (notes != null) 'notes': notes,
      },
    );
    return ExerciseSet.fromJson(response);
  }

  /// Complete a workout session
  Future<WorkoutSessionSummary> completeWorkoutSession({
    required String sessionId,
    String? notes,
  }) async {
    final response = await _makeRequest<Map<String, dynamic>>(
      'PUT',
      '/workout-sessions/$sessionId/complete',
      body: {
        if (notes != null) 'notes': notes,
      },
    );
    return WorkoutSessionSummary.fromJson(response);
  }

  /// Batch sync workout session (new local-first approach)
  Future<Map<String, dynamic>> batchSyncWorkout({
    required String sessionId,
    String? workoutId,
    required String workoutName,
    required DateTime startedAt,
    DateTime? completedAt,
    required String status,
    required int totalVolume,
    required int durationSeconds,
    String? notes,
    required List<Map<String, dynamic>> sets,
  }) async {
    final response = await _makeRequest<Map<String, dynamic>>(
      'POST',
      '/workout-sessions/batch-sync',
      body: {
        'session': {
          'id': sessionId,
          'workout_id': workoutId,
          'workout_name': workoutName,
          'started_at': startedAt.toIso8601String(),
          'completed_at': completedAt?.toIso8601String(),
          'status': status,
          'total_volume': totalVolume,
          'duration_seconds': durationSeconds,
          'notes': notes,
        },
        'sets': sets,
      },
      timeout: const Duration(seconds: 120), // Longer timeout for batch operations
    );

    // Invalidate streak and gamification caches after workout completion
    if (status == 'completed') {
      requestCache.invalidate(_getUserCacheKey('gamification_streak'));
      requestCache.invalidate(_getUserCacheKey('gamification_achievements'));
      requestCache.invalidate(_getUserCacheKey('gamification_stats'));
      requestCache.invalidate('personal_records'); // PRs may have been set
    }

    return response;
  }

  /// Abandon a workout session
  Future<void> abandonWorkoutSession(String sessionId) async {
    await _makeRequest(
      'DELETE',
      '/workout-sessions/$sessionId',
    );
  }

  /// Update an existing workout session
  /// Updates workout name, duration, notes, and all exercise sets
  Future<WorkoutSession> updateWorkoutSession({
    required String sessionId,
    required String workoutName,
    required int durationSeconds,
    String? notes,
    required List<Map<String, dynamic>> sets,
  }) async {
    final response = await _makeRequest<Map<String, dynamic>>(
      'PUT',
      '/workout-sessions/$sessionId',
      body: {
        'workout_name': workoutName,
        'duration_seconds': durationSeconds,
        'notes': notes,
        'sets': sets,
      },
    );

    // Invalidate cache after update
    requestCache.invalidate(_getUserCacheKey('workout_history'));

    // Return the updated session from response
    return WorkoutSession.fromJson(response['session']);
  }

  /// Get workout session history
  Future<List<WorkoutSession>> getWorkoutSessionHistory({
    int limit = 20,
    int offset = 0,
  }) async {
    final response = await _makeRequest<List<dynamic>>(
      'GET',
      '/workout-sessions/history?limit=$limit&offset=$offset',
    );
    return response.map((json) => WorkoutSession.fromJson(json)).toList();
  }

  /// Get exercise history
  Future<ExerciseHistory> getExerciseHistory(String exerciseName) async {
    final response = await _makeRequest<Map<String, dynamic>>(
      'GET',
      '/workout-sessions/exercises/${Uri.encodeComponent(exerciseName)}/history',
    );
    return ExerciseHistory.fromJson(response);
  }

  /// Get all personal records
  Future<List<PersonalRecord>> getPersonalRecords({bool forceRefresh = false}) async {
    return await requestCache.deduplicate(
      'personal_records',
      () async {
        final response = await _makeRequest<List<dynamic>>(
          'GET',
          '/workout-sessions/personal-records',
        );
        return response.map((json) => PersonalRecord.fromJson(json)).toList();
      },
      ttl: const Duration(minutes: 5),
      forceRefresh: forceRefresh,
    );
  }

  // === Gamification Methods ===

  /// Get user's streak information
  Future<UserStreak> getStreak({bool forceRefresh = false}) async {
    return await requestCache.deduplicate(
      _getUserCacheKey('gamification_streak'),
      () async {
        final response = await _makeRequest<Map<String, dynamic>>(
          'GET',
          '/gamification/streak',
        );
        return UserStreak.fromJson(response);
      },
      ttl: const Duration(minutes: 5),
      forceRefresh: forceRefresh,
    );
  }

  /// Get all achievements with user's progress
  Future<List<AchievementProgress>> getAchievementsWithProgress({bool forceRefresh = false}) async {
    return await requestCache.deduplicate(
      _getUserCacheKey('gamification_achievements'),
      () async {
        final response = await _makeRequest<List<dynamic>>(
          'GET',
          '/gamification/achievements',
        );
        return response.map((json) => AchievementProgress.fromJson(json)).toList();
      },
      ttl: const Duration(minutes: 5),
      forceRefresh: forceRefresh,
    );
  }

  /// Get user's earned achievements
  Future<List<UserAchievement>> getEarnedAchievements() async {
    final response = await _makeRequest<List<dynamic>>(
      'GET',
      '/gamification/achievements/earned',
    );
    return response.map((json) => UserAchievement.fromJson(json)).toList();
  }

  /// Get unnotified achievements (new achievements to show user)
  Future<List<NewAchievementNotification>> getUnnotifiedAchievements() async {
    final response = await _makeRequest<List<dynamic>>(
      'GET',
      '/gamification/achievements/unnotified',
    );
    return response.map((json) => NewAchievementNotification.fromJson(json)).toList();
  }

  /// Get complete gamification stats for dashboard
  Future<GamificationStats> getGamificationStats({bool forceRefresh = false}) async {
    return await requestCache.deduplicate(
      _getUserCacheKey('gamification_stats'),
      () async {
        final response = await _makeRequest<Map<String, dynamic>>(
          'GET',
          '/gamification/stats',
        );
        return GamificationStats.fromJson(response);
      },
      ttl: const Duration(minutes: 5),
      forceRefresh: forceRefresh,
    );
  }

  // ─── Run Activity Methods ──────────────────────────────

  Future<Map<String, dynamic>> createRunActivity(Map<String, dynamic> data) async {
    return _makeRequest<Map<String, dynamic>>(
      'POST', '/runs',
      body: data,
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }

  Future<List<Map<String, dynamic>>> getRunActivities({int limit = 20, int offset = 0}) async {
    return _makeRequest<List<Map<String, dynamic>>>(
      'GET', '/runs?limit=$limit&offset=$offset',
      fromJson: (json) => (json as List).map((e) => e as Map<String, dynamic>).toList(),
    );
  }

  Future<Map<String, dynamic>> getRunActivity(String id) async {
    return _makeRequest<Map<String, dynamic>>(
      'GET', '/runs/$id',
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }

  Future<Map<String, dynamic>> getRunStats() async {
    return _makeRequest<Map<String, dynamic>>(
      'GET', '/runs/stats',
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }

  Future<void> deleteRunActivity(String id) async {
    await _makeRequest('DELETE', '/runs/$id');
  }
}

/// Event from SSE stream for generation progress
class GenerationEvent {
  final String event;
  final Map<String, dynamic> data;

  GenerationEvent({
    required this.event,
    required this.data,
  });

  String? get taskId => data['id'] as String?;
  String? get status => data['status'] as String?;
  int get progress => (data['progress'] as num?)?.toInt() ?? 0;
  String? get message => data['message'] as String?;
  String? get resultId => data['result_id'] as String?;
  String? get error => data['error'] as String?;

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isInProgress => status == 'in_progress';
}

// Provider for API service
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});