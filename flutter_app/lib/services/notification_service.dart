import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

final _logger = Logger();

/// Service for handling push notifications via Firebase Cloud Messaging.
/// Requires google-services.json (Android) and GoogleService-Info.plist (iOS)
/// to be properly configured in the native projects.
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  bool _initialized = false;

  /// Initialize push notifications — call once after login
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Request permission (iOS requires explicit request)
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        announcement: false,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        _logger.w('Push notification permission denied');
        return;
      }

      // Get FCM token
      final token = await _messaging.getToken();
      if (token != null) {
        _logger.i('FCM token obtained: ${token.substring(0, 20)}...');
        await _registerToken(token);
      }

      // Listen for token refresh
      _messaging.onTokenRefresh.listen(_registerToken);

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle background/terminated message taps
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

      // Check for initial message (app opened from notification)
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleMessageTap(initialMessage);
      }

      _initialized = true;
      _logger.i('Push notifications initialized');
    } catch (e) {
      _logger.e('Failed to initialize push notifications: $e');
      // Non-fatal — app works without push notifications
    }
  }

  /// Register FCM token with backend for targeted pushes
  Future<void> _registerToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastToken = prefs.getString('fcm_token');

      // Only register if token changed
      if (lastToken == token) return;

      // Store locally — backend registration can be added when endpoint exists
      await prefs.setString('fcm_token', token);
      _logger.d('FCM token registered locally');
    } catch (e) {
      _logger.w('Failed to register FCM token: $e');
    }
  }

  /// Handle messages received while app is in foreground
  void _handleForegroundMessage(RemoteMessage message) {
    _logger.d('Foreground message: ${message.notification?.title}');
    // The message is received but no system notification is shown automatically
    // in foreground. We could show a snackbar or in-app notification here.
  }

  /// Handle when user taps on a notification
  void _handleMessageTap(RemoteMessage message) {
    _logger.d('Notification tapped: ${message.data}');
    // Could navigate to specific screen based on message.data['type']
    // e.g., 'workout_reminder' -> /fitness, 'meal_reminder' -> /nutrition
  }

  /// Subscribe to topic-based notifications
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      _logger.d('Subscribed to topic: $topic');
    } catch (e) {
      _logger.w('Failed to subscribe to topic $topic: $e');
    }
  }

  /// Unsubscribe from topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      _logger.d('Unsubscribed from topic: $topic');
    } catch (e) {
      _logger.w('Failed to unsubscribe from topic $topic: $e');
    }
  }
}
