import 'package:flutter/material.dart';
import 'package:pulser_sdk/notif_sdk.dart';
import 'profile_screen.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pulser SDK Example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final Pulser _pulser;
  final List<String> _log = [];
  bool _connected = false;
  List<InboxItem> _inbox = [];

  @override
  void initState() {
    super.initState();
    _pulser = Pulser(
      config: const PulserConfig(
        // Replace with your local server or deployed URL
        baseURL: 'http://10.0.2.2:9090',
        apiKey: 'nk_your_api_key_here',
        appId: 'your_app_id_here',
        debug: true,
      ),
    );

    _pulser.onConnectionChange = (connected) {
      setState(() => _connected = connected);
      _addLog(
          connected ? '🟢 WebSocket connected' : '🔴 WebSocket disconnected');
    };

    _pulser.onNotification = (item) {
      _addLog('📬 New notification: ${item.title}');
      setState(() => _inbox.insert(0, item));
    };

    _pulser.onInAppMessage = (messages) {
      _addLog('💬 In-app messages: ${messages.length}');
      for (final msg in messages) {
        _showInAppMessage(msg);
      }
    };

    // Track push interactions
    FirebaseMessaging.onMessage.listen((message) {
      final id = message.data['notification_id'];
      if (id != null) _pulser.notifications.markDelivered(id);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final id = message.data['notification_id'];
      if (id != null) {
        _pulser.notifications.markDelivered(id);
        _pulser.notifications.markOpened(id);
      }
    });

    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        final id = message.data['notification_id'];
        if (id != null) {
          _pulser.notifications.markDelivered(id);
          _pulser.notifications.markOpened(id);
        }
      }
    });

    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      _pulser.updatePushToken(token);
    });
  }

  @override
  void dispose() {
    _pulser.dispose();
    super.dispose();
  }

  void _addLog(String msg) {
    setState(() => _log.insert(0, '[${TimeOfDay.now().format(context)}] $msg'));
  }

  Future<void> _identify() async {
    try {
      await _pulser.identify(userId: 'user_demo_001', username: 'Demo User');
      _addLog('✅ Identified as user_demo_001');
    } catch (e) {
      _addLog('❌ identify failed: $e');
    }
  }

  Future<void> _fetchInbox() async {
    try {
      final resp = await _pulser.inbox.fetch(limit: 20);
      setState(() => _inbox = resp.items);
      _addLog(
          '📥 Fetched ${resp.items.length} items (${resp.unreadCount} unread)');
    } catch (e) {
      _addLog('❌ inbox fetch failed: $e');
    }
  }

  Future<void> _trackEvent() async {
    try {
      final id = await _pulser.events
          .track('button_tapped', properties: {'screen': 'home'});
      _addLog('📊 Event tracked: $id');
    } catch (e) {
      _addLog('❌ track failed: $e');
    }
  }

  Future<void> _evaluateInApp() async {
    try {
      final messages = await _pulser.inApp.evaluate(screen: 'home');
      _addLog('💬 Evaluated ${messages.length} in-app messages');
    } catch (e) {
      _addLog('❌ inapp evaluate failed: $e');
    }
  }

  Future<void> _logout() async {
    try {
      await _pulser.logout();
      setState(() {
        _inbox = [];
        _connected = false;
      });
      _addLog('👋 Logged out');
    } catch (e) {
      _addLog('❌ logout failed: $e');
    }
  }

  void _showInAppMessage(InAppMessage msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(msg.content.title ?? 'Message'),
        content: Text(msg.content.body ?? ''),
        actions: [
          ...msg.content.actions.map((a) => TextButton(
                onPressed: () {
                  _pulser.inApp.recordClick(msg.id, a.action);
                  Navigator.pop(context);
                },
                child: Text(a.label),
              )),
          TextButton(
            onPressed: () {
              _pulser.inApp.recordDismissal(msg.id);
              Navigator.pop(context);
            },
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pulser SDK Example'),
        actions: [
          Icon(_connected ? Icons.wifi : Icons.wifi_off,
              color: _connected ? Colors.green : Colors.red),
          const SizedBox(width: 4),
          IconButton(
            icon: const CircleAvatar(
              radius: 14,
              child: Icon(Icons.person, size: 16),
            ),
            tooltip: 'Profile',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ProfileScreen(
                  name: 'Demo User',
                  userId: 'user_demo_001',
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Action buttons
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                    onPressed: _identify, child: const Text('Identify')),
                ElevatedButton(
                    onPressed: _fetchInbox, child: const Text('Fetch Inbox')),
                ElevatedButton(
                    onPressed: _trackEvent, child: const Text('Track Event')),
                ElevatedButton(
                    onPressed: _evaluateInApp,
                    child: const Text('Eval In-App')),
                OutlinedButton(onPressed: _logout, child: const Text('Logout')),
              ],
            ),
          ),
          const Divider(),
          // Inbox
          if (_inbox.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Inbox',
                      style: TextStyle(fontWeight: FontWeight.bold))),
            ),
            SizedBox(
              height: 160,
              child: ListView.builder(
                itemCount: _inbox.length,
                itemBuilder: (_, i) {
                  final item = _inbox[i];
                  return ListTile(
                    dense: true,
                    leading: Icon(item.isRead ? Icons.mail_outline : Icons.mail,
                        color: item.isRead ? Colors.grey : Colors.indigo),
                    title:
                        Text(item.title, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(item.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12)),
                    onTap: () => _pulser.inbox.markRead([item.id]),
                  );
                },
              ),
            ),
            const Divider(),
          ],
          // Log
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Align(
                alignment: Alignment.centerLeft,
                child:
                    Text('Log', style: TextStyle(fontWeight: FontWeight.bold))),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _log.length,
              itemBuilder: (_, i) => Text(_log[i],
                  style:
                      const TextStyle(fontSize: 12, fontFamily: 'monospace')),
            ),
          ),
        ],
      ),
    );
  }
}
