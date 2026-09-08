# Pulser SDK for Flutter

Multi-channel notification SDK for Flutter. Supports push notifications, persistent inbox, in-app messages, event tracking, delivery/open tracking (CTR), and user preferences — with real-time WebSocket delivery and automatic reconnection.

---

## Table of Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Android Setup](#android-setup)
- [iOS Setup](#ios-setup)
- [Initialization](#initialization)
- [Identify a User](#identify-a-user)
- [Push Notifications](#push-notifications)
- [Notification Inbox](#notification-inbox)
- [Real-Time (WebSocket)](#real-time-websocket)
- [In-App Messages](#in-app-messages)
- [Event Tracking](#event-tracking)
- [User Preferences](#user-preferences)
- [Consent Management](#consent-management)
- [Delivery & Open Tracking (CTR)](#delivery--open-tracking-ctr)
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

The SDK requires **Firebase Cloud Messaging (FCM)** for push delivery. Make sure your project has Firebase set up before integrating.

---

## Installation

### Option A — Local path (monorepo)

```yaml
# pubspec.yaml
dependencies:
  pulser_sdk:
    path: ../path/to/sdks/flutter
```

### Option B — Git

```yaml
dependencies:
  pulser_sdk:
    git:
      url: https://github.com/levinkm/notif-flutter-sdk
      ref: main
```

Then run:

```bash
flutter pub get
```

---

## Android Setup

### 1. Enable core library desugaring

Required by `flutter_local_notifications` (used for foreground notification display).

```kotlin
// android/app/build.gradle.kts
android {
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

### 2. Set default notification channel

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

### 3. Add internet permission

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

### 4. Emulator base URL

When running on an Android emulator, use `10.0.2.2` instead of `localhost` to reach your host machine:

```dart
final baseURL = Platform.isAndroid ? 'http://10.0.2.2:9090' : 'http://localhost:9090';
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

// Background FCM handler — must be top-level
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await NotificationTracker.persistBackgroundDelivery(message.data);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Firebase FIRST
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 2. Register background handler early
  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

  // 3. Create Pulser instance
  final pulser = Pulser(
    config: PulserConfig(
      baseURL: 'https://your-pulser-server.com',
      apiKey: 'pk_your_api_key_here',
      appId: 'your-app-id-here',
      debug: false,
    ),
  );

  // 4. Wire foreground FCM messages
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
  if (fcmToken == null) return;

  await pulser.identify(
    userId: userId,
    pushToken: fcmToken,
    username: 'Jane Doe',       // optional
  );
}
```

Handle token refresh:

```dart
FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
  pulser.updatePushToken(newToken);
});
```

---

## Push Notifications

### Foreground notifications

Android suppresses the system tray when the app is in the foreground and the FCM payload has a `notification` block. Use `flutter_local_notifications` to show them manually.

The SDK calls your `onForegroundMessage` handler automatically when `handleForegroundMessage` is called:

```dart
pulser.onForegroundMessage = (title, body, notificationId) {
  // Show a local notification using flutter_local_notifications
  flutterLocalNotifications.show(
    0,
    title,
    body,
    notificationDetails,
  );
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

The top-level background handler persists delivery IDs to SharedPreferences. They are flushed automatically when `identify()` completes:

```dart
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await NotificationTracker.persistBackgroundDelivery(message.data);
}
```

---

## Notification Inbox

Fetch the user's notification history:

```dart
final resp = await pulser.inbox.fetch(limit: 20);

print('${resp.items.length} items, ${resp.unreadCount} unread');

for (final item in resp.items) {
  print('${item.title} — ${item.isRead ? "read" : "unread"}');
}
```

### Pagination

```dart
// First page
final page1 = await pulser.inbox.fetch(limit: 20);

// Next page
if (page1.hasMore) {
  final page2 = await pulser.inbox.fetch(limit: 20, cursor: page1.nextCursor);
}
```

### Mark as read

```dart
// Mark specific items
await pulser.inbox.markRead([item.id]);

// Mark all
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
| `createdAt` | `DateTime` | Creation timestamp (local time) |

---

## Real-Time (WebSocket)

The SDK connects automatically after `identify()`. New inbox items are pushed in real-time:

```dart
pulser.onNotification = (InboxItem item) {
  // New notification arrived — update your UI
  setState(() => _inbox.insert(0, item));
};

pulser.onConnectionChange = (bool connected) {
  print(connected ? 'Connected' : 'Disconnected');
};
```

The WebSocket:
- Reconnects automatically with exponential backoff (2s → 60s max)
- Pauses when the app goes to background, resumes on foreground
- Performs a gap-free sync on reconnect using sequence numbers

---

## In-App Messages

Evaluate and display in-app messages for a given screen or event trigger:

```dart
// On screen load
final messages = await pulser.inApp.evaluate(screen: 'home');

for (final msg in messages) {
  // Show the message in your UI
  showInAppBanner(msg);

  // Record impression
  await pulser.inApp.recordImpression(msg.id);
}
```

Record interactions:

```dart
// User clicked a CTA
await pulser.inApp.recordClick(msg.id, action.action);

// User dismissed
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

## Event Tracking

Track custom user events for segmentation and campaign triggers:

```dart
// Simple event
await pulser.events.track('button_tapped');

// With properties and tags
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

Fetch and update notification preferences:

```dart
// Get current preferences
final prefs = await pulser.preferences.get();

// Update
await pulser.preferences.update(
  prefs.copyWith(emailEnabled: false),
);

// Opt out of a channel
await pulser.preferences.optOutChannel('sms');
await pulser.preferences.optInChannel('push');

// Opt out of a category
await pulser.preferences.optOutCategory('marketing');
await pulser.preferences.optInCategory('transactional');

// Set quiet hours (24h format)
await pulser.preferences.setQuietHours('22:00', '08:00');
```

---

## Consent Management

The SDK provides a consent service for recording and checking user consent decisions per channel and purpose. Consent is always **channel + purpose** specific.

### ConsentPurpose

| Value | Description |
|---|---|
| `marketing` | Promotional emails, offers, newsletters, campaigns |
| `transactional` | Receipts, OTPs, security alerts — always delivered, but good to record |
| `product` | Feature announcements, onboarding tips, product updates |
| `research` | Surveys, feedback requests, NPS |

### Record consent at signup

Pass consent decisions directly into `identify()` — they are recorded server-side with `source: 'identify'`:

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
// User opts in to product update emails
await pulser.consent.grant(channel: 'email', purpose: ConsentPurpose.product);

// User opts out of marketing push in settings
await pulser.consent.revoke(channel: 'push', purpose: ConsentPurpose.marketing);
```

### Check before showing a consent prompt

```dart
final hasConsent = await pulser.consent.check(
  channel: 'push',
  purpose: ConsentPurpose.marketing,
);

if (!hasConsent) {
  // Show opt-in prompt
}
```

`check()` returns `true` if no record exists (fail-open / opt-out model).

### List all consent records

```dart
final records = await pulser.consent.list();

for (final r in records) {
  print('${r.channel} / ${r.purpose.name}: ${r.consented ? "granted" : "revoked"} at ${r.createdAt}');
}
```

### ConsentRecord fields

| Field | Type | Description |
|---|---|---|
| `id` | `String` | Record ID |
| `channel` | `String` | `push`, `email`, `sms`, `in_app` |
| `purpose` | `ConsentPurpose` | What the consent covers |
| `consented` | `bool` | `true` = granted, `false` = revoked |
| `source` | `String` | Where it was recorded (`app`, `identify`, etc.) |
| `createdAt` | `DateTime` | When it was recorded |

---

## Delivery & Open Tracking (CTR)

The SDK handles delivery tracking automatically via `handleForegroundMessage` and `persistBackgroundDelivery`. For tap tracking you wire it manually:

```dart
// Foreground — handled automatically by the SDK
pulser.notifications.handleForegroundMessage(title, body, data);

// Background tap
pulser.notifications.markDelivered(notificationId);
pulser.notifications.markOpened(notificationId);

// Terminated tap
pulser.notifications.markDelivered(notificationId);
pulser.notifications.markOpened(notificationId);
```

Calls made before `identify()` completes are queued internally and flushed automatically once the user is identified.

---

## Logout

```dart
await pulser.logout();
```

This deactivates the device on the server, disconnects the WebSocket, and clears all stored credentials (device token, user ID, sequence number).

---

## API Reference

### `Pulser`

| Member | Type | Description |
|---|---|---|
| `identify(userId, pushToken, username?, consent?)` | `Future<void>` | Register device and open WS |
| `updatePushToken(token)` | `Future<void>` | Update FCM/APNs token |
| `logout()` | `Future<void>` | Deregister and disconnect |
| `dispose()` | `void` | Release all resources |
| `inbox` | `InboxService` | Inbox operations |
| `events` | `EventService` | Event tracking |
| `notifications` | `NotificationTracker` | Delivery/open tracking |
| `preferences` | `PreferenceService` | User preferences |
| `inApp` | `InAppService` | In-app message evaluation |
| `consent` | `ConsentService` | Consent management |
| `onNotification` | `NotificationListener?` | Real-time inbox callback |
| `onInAppMessage` | `InAppListener?` | Real-time in-app callback |
| `onConnectionChange` | `ConnectionListener?` | WS connection state callback |
| `onForegroundMessage` | `ForegroundMessageHandler?` | Foreground FCM callback |

### `PulserConfig`

| Parameter | Type | Required | Default |
|---|---|---|---|
| `baseURL` | `String` | ✅ | — |
| `apiKey` | `String` | ✅ | — |
| `appId` | `String` | ✅ | — |
| `timeout` | `Duration` | ❌ | `10s` |
| `debug` | `bool` | ❌ | `false` |
| `pinnedCertificates` | `List<String>?` | ❌ | `null` |

---

## Error Handling

| Exception | Cause |
|---|---|
| `PulserAuthException` | `identify()` not called or device token missing |
| `PulserNetworkException` | Network unreachable or timeout |
| `PulserApiException` | Server returned 4xx/5xx |
| `PulserRateLimitException` | 429 — includes `retryAfterSeconds` |

```dart
try {
  await pulser.identify(userId: userId, pushToken: token);
} on PulserAuthException catch (e) {
  print('Auth error: ${e.message}');
} on PulserNetworkException catch (e) {
  print('Network error: ${e.message}');
} on PulserApiException catch (e) {
  print('API error ${e.statusCode}: ${e.message}');
}
```
