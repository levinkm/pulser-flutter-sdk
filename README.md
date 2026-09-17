# Pulser SDK for Flutter

Multi-channel notification SDK for Flutter. Supports push notifications (FCM + APNs direct), persistent inbox, in-app messages, event tracking, analytics instrumentation, delivery/open/dismiss tracking, and user preferences with real-time WebSocket delivery and automatic reconnection.

---

## Table of Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Android Setup](#android-setup)
- [iOS Setup](#ios-setup)
- [Initialization](#initialization)
- [Identify a User](#identify-a-user)
- [Anonymous Identity & Alias](#anonymous-identity--alias)
- [Push Notifications](#push-notifications)
- [APNs Direct (iOS)](#apns-direct-ios)
- [Notification Inbox](#notification-inbox)
- [Real-Time (WebSocket)](#real-time-websocket)
- [In-App Messages](#in-app-messages)
- [Analytics Event Tracking](#analytics-event-tracking)
- [Raw Event Tracking](#raw-event-tracking)
- [User Preferences](#user-preferences)
- [Consent Management](#consent-management)
- [Delivery, Open & Dismiss Tracking](#delivery-open--dismiss-tracking)
- [Logout](#logout)
- [API Reference](#api-reference)
- [Error Handling](#error-handling)

---

## Requirements

| | Minimum |
|---|---|
| Flutter | 3.10.0 |
| Dart | 3.0.0 |
| Android | API 21 (Android 5.0) |
| iOS | 13.0 |

The SDK requires **Firebase Cloud Messaging (FCM)** for push delivery on Android. On iOS, FCM is used as a fallback; the server prefers direct APNs when credentials are configured.

---

## Installation

### Option A - Git

```yaml
# pubspec.yaml
dependencies:
  pulser_sdk:
    git:
      url: https://github.com/levinkm/pulser-flutter-sdk.git
      ref: main
```

### Option B - Local path (monorepo)

```yaml
dependencies:
  pulser_sdk:
    path: ../path/to/sdks/flutter
```

Then run:

```bash
flutter pub get
```

---

## Android Setup

### 1. Set default notification channel

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<application ...>
    <meta-data
        android:name="com.google.firebase.messaging.default_notification_channel_id"
        android:value="high_importance_channel" />
    <meta-data
        android:name="com.google.firebase.messaging.default_notification_icon"
        android:value="@drawable/ic_launcher_foreground" />
</application>
```

### 2. Add internet permission

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

### 3. Emulator base URL

When running on an Android emulator, use `10.0.2.2` instead of `localhost` to reach your host machine:

```dart
final baseURL = Platform.isAndroid
    ? 'http://10.0.2.2:8080'
    : 'http://localhost:8080';
```

---

## iOS Setup

### 1. Enable Push Notifications capability

In Xcode: **Signing & Capabilities → + Capability → Push Notifications**

### 2. Enable Background Modes

In Xcode: **Signing & Capabilities → + Capability → Background Modes**  
Check: **Remote notifications**

### 3. Request permission in your app

```dart
await FirebaseMessaging.instance.requestPermission(
  alert: true,
  badge: true,
  sound: true,
);
```

---

## Initialization

Initialize Firebase first, then create the `Pulser` instance. Do this before `runApp`.

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:pulser_sdk/notif_sdk.dart';

// Background FCM handler - must be a top-level function
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await NotificationTracker.persistBackgroundDelivery(message.data);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 2. Register background handler
  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

  // 3. Create Pulser instance
  final pulser = Pulser(
    config: PulserConfig(
      baseURL: 'https://your-pulser-server.com',
      apiKey: 'pk_your_api_key_here',
      appId: 'your-app-id-here',
    ),
  );

  // 4. (iOS only) Init APNs token handling before identify()
  await pulser.initAPNs();

  // 5. Wire foreground FCM messages
  FirebaseMessaging.onMessage.listen((message) {
    final title = message.data['title'] ?? message.notification?.title ?? '';
    final body  = message.data['body']  ?? message.notification?.body  ?? '';
    pulser.notifications.handleForegroundMessage(title, body, message.data);
  });

  runApp(MyApp(pulser: pulser));
}
```

---

## Identify a User

Call `identify()` after login, once you have the FCM token. This registers the device with the server and opens the WebSocket connection.

```dart
Future<void> onUserLoggedIn(String userId) async {
  final fcmToken = await FirebaseMessaging.instance.getToken();

  await pulser.identify(
    userId: userId,
    pushToken: fcmToken,
    email: 'user@example.com',   // optional, enables email channel
    username: 'Jane Doe',        // optional
  );

  // Track login event with analytics context
  await pulser.analytics.trackLogin(method: 'email');
}
```

Handle token refresh:

```dart
FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
  pulser.updatePushToken(newToken);
});
```

---

## Anonymous Identity & Alias

The SDK auto-generates an anonymous ID on first launch. When the user logs in, alias it to their identified user ID so pre-login events are attributed correctly:

```dart
// Call alias BEFORE or alongside identify()
await pulser.alias(userId);
await pulser.identify(userId: userId, pushToken: fcmToken);
```

Check if an anonymous session exists:

```dart
if (await pulser.hasAnonymousSession) {
  await pulser.alias(userId);
}
```

---

## Push Notifications

### Foreground notifications

The SDK calls your `onForegroundMessage` handler when a message arrives while the app is open:

```dart
pulser.onForegroundMessage = (title, body, notificationId) {
  // Show a local notification or in-app banner
};
```

### Background / terminated tap handling

```dart
// Tapped from background
FirebaseMessaging.onMessageOpenedApp.listen((message) {
  final id = message.data['notification_id'];
  if (id != null) {
    pulser.notifications.markDelivered(id);
    pulser.notifications.markOpened(id);
    // Track tap for analytics
    pulser.analytics.trackNotificationTapped(
      notificationId: id,
      channel: 'push',
    );
  }
});

// Tapped from terminated state
final initial = await FirebaseMessaging.instance.getInitialMessage();
if (initial != null) {
  final id = initial.data['notification_id'];
  if (id != null) {
    pulser.notifications.markDelivered(id);
    pulser.notifications.markOpened(id);
  }
}
```

### Background delivery tracking

```dart
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await NotificationTracker.persistBackgroundDelivery(message.data);
}
```

Delivery IDs are flushed automatically when `identify()` completes.

---

## APNs Direct (iOS)

Call `initAPNs()` once before `identify()`. The SDK handles APNs token registration, rotation, and environment detection (sandbox vs production) automatically, no manual configuration required.

```dart
final pulser = Pulser(config: PulserConfig(...));

// Must be called before identify()
await pulser.initAPNs();

await pulser.identify(userId: userId, pushToken: fcmToken);
```

If the APNs token arrives before `identify()` is called, it is stored and sent automatically on the next `identify()` call.

---

## Notification Inbox

Fetch the user's notification history:

```dart
final resp = await pulser.inbox.fetch(limit: 20);

print('${resp.items.length} items, ${resp.unreadCount} unread');

for (final item in resp.items) {
  print('${item.title} - ${item.isRead ? 'read' : 'unread'}');
}
```

### Pagination

```dart
final page1 = await pulser.inbox.fetch(limit: 20);

if (page1.hasMore) {
  final page2 = await pulser.inbox.fetch(limit: 20, cursor: page1.nextCursor);
}
```

### Mark as read

```dart
await pulser.inbox.markRead([item.id]);
await pulser.inbox.markAllRead();
```

### Unread count

```dart
final count = await pulser.inbox.unreadCount();
```

### InboxItem fields

| Field | Type | Description |
|---|---|---|
| `id` | `String` | Unique notification ID |
| `seq` | `int` | Monotonic sequence number |
| `title` | `String` | Notification title |
| `body` | `String` | Notification body |
| `category` | `String?` | Category slug (e.g. `payment`, `promo`) |
| `imageUrl` | `String?` | Optional image URL |
| `isRead` | `bool` | Read state |
| `actions` | `List<InboxAction>` | CTA buttons |
| `createdAt` | `DateTime` | Creation timestamp |

---

## Real-Time (WebSocket)

The SDK connects automatically after `identify()`. New inbox items are pushed in real-time:

```dart
pulser.onNotification = (InboxItem item) {
  setState(() => _inbox.insert(0, item));
};

pulser.onConnectionChange = (bool connected) {
  print(connected ? 'Connected' : 'Disconnected');
};
```

The WebSocket reconnects automatically with exponential backoff, pauses in the background, and performs a gap-free sync on reconnect using sequence numbers.

---

## In-App Messages

Evaluate and display in-app messages for a given screen:

```dart
final messages = await pulser.inApp.evaluate(screen: 'home');

for (final msg in messages) {
  showInAppBanner(msg);
  await pulser.inApp.recordImpression(msg.id);
}
```

Record interactions:

```dart
await pulser.inApp.recordClick(msg.id, action.action);
await pulser.inApp.recordDismissal(msg.id);
```

Real-time in-app messages via WebSocket:

```dart
pulser.onInAppMessage = (List<InAppMessage> messages) {
  for (final msg in messages) {
    showInAppBanner(msg);
  }
};
```

---

## Analytics Event Tracking

The `analytics` service provides typed helpers for the full event taxonomy. Device context (`platform`, `os_version`, `app_version`) is automatically attached to every event, no manual enrichment needed.

### Authentication

```dart
// On login success
await pulser.analytics.trackLogin(
  method: 'email',       // 'email' | 'phone' | 'google' | 'apple'
  country: 'GH',         // optional, GeoIP enrichment handles this server-side
  timezone: 'Africa/Accra',
);

await pulser.analytics.trackLoginFailed(reason: 'wrong_password');

// On logout
await pulser.analytics.trackLogout(sessionDurationSeconds: stopwatch.elapsed.inSeconds);
```

### Registration funnel

```dart
await pulser.analytics.trackRegisterStart(referrer: 'organic');

// On each step
await pulser.analytics.trackRegisterStep('email', timeOnStepSeconds: 12);
await pulser.analytics.trackRegisterStep('phone', timeOnStepSeconds: 8);
await pulser.analytics.trackRegisterStep('otp',   timeOnStepSeconds: 20, attempts: 2);
await pulser.analytics.trackRegisterStep('profile', timeOnStepSeconds: 35);

// On completion
await pulser.analytics.trackRegisterComplete(
  timeToCompleteSeconds: stopwatch.elapsed.inSeconds,
  stepsCount: 4,
  referrer: 'organic',
);

// On app background/close before completion
AppLifecycleListener(
  onPause: () {
    if (_registrationStarted && !_registrationComplete) {
      pulser.analytics.trackRegisterAbandoned(
        lastStep: _lastStep,
        timeSpentSeconds: _stopwatch.elapsed.inSeconds,
      );
    }
  },
);
```

### Navigation

```dart
// On every screen transition
await pulser.analytics.trackScreenView(
  screen: 'wallet',
  previousScreen: 'home',
);

await pulser.analytics.trackScreenExit(
  screen: 'wallet',
  timeOnScreenSeconds: _screenStopwatch.elapsed.inSeconds,
);
```

### Engagement

```dart
await pulser.analytics.trackFeatureUsed(feature: 'send_money');

await pulser.analytics.trackSearchPerformed(
  queryLength: query.length,
  resultsCount: results.length,
);

// Crash reporting
await pulser.analytics.trackAppCrash(stackTraceHash: hash);
```

### Notification interactions

```dart
// User tapped a notification
await pulser.analytics.trackNotificationTapped(
  notificationId: id,
  channel: 'push',
  screenOpened: 'wallet',
);

// User dismissed a notification
await pulser.analytics.trackNotificationDismissed(
  notificationId: id,
  channel: 'push',
);
```

---

## Raw Event Tracking

For custom events not covered by the analytics helpers, use `events.track()` directly:

```dart
await pulser.events.track('custom_event_name');

await pulser.events.track(
  'purchase_completed',
  properties: {
    'amount': 49.99,
    'currency': 'GBP',
    'product_id': 'prod_123',
  },
  tags: ['conversion', 'revenue'],
);
```

---

## User Preferences

```dart
final prefs = await pulser.preferences.get();

await pulser.preferences.update(prefs.copyWith(emailEnabled: false));

await pulser.preferences.optOutChannel('email');
await pulser.preferences.optInChannel('push');

await pulser.preferences.optOutCategory('marketing');
await pulser.preferences.optInCategory('transactional');

// Set quiet hours (24h format)
await pulser.preferences.setQuietHours('22:00', '08:00');
```

---

## Consent Management

Consent is always **channel + purpose** specific.

### ConsentPurpose values

| Value | Description |
|---|---|
| `marketing` | Promotional messages, offers, campaigns |
| `transactional` | Receipts, OTPs, security alerts |
| `product` | Feature announcements, onboarding, product updates |
| `research` | Surveys, feedback, NPS |

### Record consent at signup

```dart
await pulser.identify(
  userId: 'user_123',
  pushToken: fcmToken,
  consent: [
    ConsentInput(channel: 'email', purpose: ConsentPurpose.marketing, consented: true),
    ConsentInput(channel: 'push',  purpose: ConsentPurpose.marketing, consented: true),
  ],
);
```

### Grant / revoke after signup

```dart
await pulser.consent.grant(channel: 'email', purpose: ConsentPurpose.product);
await pulser.consent.revoke(channel: 'push',  purpose: ConsentPurpose.marketing);
```

### Check consent

```dart
final hasConsent = await pulser.consent.check(
  channel: 'push',
  purpose: ConsentPurpose.marketing,
);
```

Returns `true` if no record exists (fail-open model).

---

## Delivery, Open & Dismiss Tracking

```dart
// Delivered (foreground, handled automatically via handleForegroundMessage)
pulser.notifications.handleForegroundMessage(title, body, data);

// Delivered (background tap)
pulser.notifications.markDelivered(notificationId);

// Opened (user tapped)
pulser.notifications.markOpened(notificationId);

// Dismissed (user swiped away)
pulser.notifications.markDismissed(notificationId, channel: 'push');
```

All calls made before `identify()` completes are queued and flushed automatically. `markDismissed` fires a `notification_dismissed` event which feeds the notification fatigue computed trait.

---

## Logout

```dart
await pulser.logout();
```

Deactivates the device on the server, disconnects the WebSocket, and clears all stored credentials.

---

## API Reference

### `Pulser`

| Member | Type | Description |
|---|---|---|
| `identify(...)` | `Future<void>` | Register device and open WebSocket |
| `alias(userId)` | `Future<void>` | Link anonymous ID to identified user |
| `updatePushToken(token)` | `Future<void>` | Update FCM token |
| `initAPNs()` | `Future<void>` | iOS: init APNs token handling (call before identify) |
| `logout()` | `Future<void>` | Deregister device and disconnect |
| `dispose()` | `void` | Release all resources |
| `inbox` | `InboxService` | Inbox operations |
| `events` | `EventService` | Raw event tracking |
| `analytics` | `AnalyticsService` | Typed analytics event helpers |
| `notifications` | `NotificationTracker` | Delivery / open / dismiss tracking |
| `preferences` | `PreferenceService` | User notification preferences |
| `inApp` | `InAppService` | In-app message evaluation and tracking |
| `consent` | `ConsentService` | Per-channel consent management |
| `users` | `UserService` | User profile and tag management |
| `onNotification` | `NotificationListener?` | Real-time inbox item callback |
| `onInAppMessage` | `InAppListener?` | Real-time in-app message callback |
| `onConnectionChange` | `ConnectionListener?` | WebSocket connection state callback |
| `onForegroundMessage` | `ForegroundMessageHandler?` | Foreground FCM message callback |
| `isIdentified` | `bool` | Whether identify() has been called |
| `hasAnonymousSession` | `Future<bool>` | Whether an anonymous ID is pending alias |

### `PulserConfig`

| Parameter | Type | Required | Default |
|---|---|---|---|
| `baseURL` | `String` | Yes | - |
| `apiKey` | `String` | Yes | - |
| `appId` | `String` | Yes | - |
| `timeout` | `Duration` | No | `10s` |
| `debug` | `bool` | No | `false` |
| `pinnedCertificates` | `List<String>?` | No | `null` |

### `AnalyticsService`

| Method | Event fired |
|---|---|
| `trackLogin(method, country?, timezone?)` | `login_success` |
| `trackLoginFailed(reason)` | `login_failed` |
| `trackLogout(sessionDurationSeconds?)` | `logout` |
| `trackTokenRefresh()` | `token_refresh` |
| `trackPasswordResetRequested()` | `password_reset_requested` |
| `trackPasswordResetCompleted()` | `password_reset_completed` |
| `trackRegisterStart(referrer?)` | `register_start` |
| `trackRegisterStep(step, timeOnStepSeconds?, attempts?)` | `register_step_{step}` |
| `trackRegisterComplete(...)` | `register_complete` |
| `trackRegisterAbandoned(lastStep, timeSpentSeconds?)` | `register_abandoned` |
| `trackScreenView(screen, previousScreen?)` | `screen_view` |
| `trackScreenExit(screen, timeOnScreenSeconds?)` | `screen_exit` |
| `trackFeatureUsed(feature)` | `feature_used` |
| `trackNotificationTapped(notificationId, channel?, screenOpened?)` | `notification_tapped` |
| `trackNotificationDismissed(notificationId, channel?)` | `notification_dismissed` |
| `trackSearchPerformed(queryLength, resultsCount)` | `search_performed` |
| `trackAppCrash(stackTraceHash?)` | `app_crash` |

---

## Error Handling

| Exception | Cause |
|---|---|
| `PulserAuthException` | `identify()` not called or device token missing |
| `PulserNetworkException` | Network unreachable or timeout after retries |
| `PulserApiException` | Server returned 4xx/5xx |
| `PulserRateLimitException` | 429, includes `retryAfterSeconds` |

```dart
try {
  await pulser.identify(userId: userId, pushToken: token);
} on PulserAuthException catch (e) {
  print('Auth error: ${e.message}');
} on PulserNetworkException catch (e) {
  print('Network error: ${e.message}');
} on PulserApiException catch (e) {
  print('API error ${e.statusCode}: ${e.message}');
} on PulserRateLimitException catch (e) {
  print('Rate limited, retry in ${e.retryAfterSeconds}s');
}
```
