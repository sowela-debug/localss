import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LocalSSApp());
}

class LocalSSApp extends StatelessWidget {
  const LocalSSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LocalSS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F1117),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF222633),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const LoginScreen(),
    );
  }
}

class LocalSSApi {
  static String server = 'http://127.0.0.1:3000';

  static const storage = FlutterSecureStorage();

  static String? token;

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    server = prefs.getString('server') ??
        'http://127.0.0.1:3000';

    token = await storage.read(key: 'token');
  }

  static Future<void> setServer(String address) async {
    server = address.trim().replaceAll(RegExp(r'/$'), '');

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('server', server);
  }

  static Map<String, String> headers() {
    return {
      'Content-Type': 'application/json',
      if (token != null)
        'Authorization': 'Bearer $token',
    };
  }

  static Future<dynamic> get(String path) async {
    final response = await http
        .get(
          Uri.parse('$server$path'),
          headers: headers(),
        )
        .timeout(const Duration(seconds: 15));

    return handleResponse(response);
  }

  static Future<dynamic> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await http
        .post(
          Uri.parse('$server$path'),
          headers: headers(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));

    return handleResponse(response);
  }

  static Future<dynamic> delete(String path) async {
    final response = await http
        .delete(
          Uri.parse('$server$path'),
          headers: headers(),
        )
        .timeout(const Duration(seconds: 15));

    return handleResponse(response);
  }

  static dynamic handleResponse(http.Response response) {
    final data = jsonDecode(response.body);

    if (response.statusCode >= 400) {
      throw Exception(
        data['detail'] ?? 'Request failed',
      );
    }

    return data;
  }

  static Future<void> saveToken(String value) async {
    token = value;
    await storage.write(key: 'token', value: value);
  }

  static Future<void> logout() async {
    try {
      await post('/auth/logout', {});
    } catch (_) {
      // Clear local credentials even when server is unavailable.
    }

    token = null;
    await storage.delete(key: 'token');
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final username = TextEditingController();
  final password = TextEditingController();

  bool loading = false;
  bool hidePassword = true;

  @override
  void initState() {
    super.initState();
    LocalSSApi.initialize();
  }

  Future<void> login() async {
    setState(() => loading = true);

    try {
      final data = await LocalSSApi.post('/auth/login', {
        'username': username.text.trim(),
        'password': password.text,
      });

      await LocalSSApi.saveToken(data['access_token']);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DashboardScreen(
            username: data['username'],
            isAdmin: data['is_admin'] == true,
          ),
        ),
      );
    } catch (e) {
      showError(context, e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              color: const Color(0xFF181B24),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.hub_rounded,
                      size: 64,
                      color: Color(0xFF6366F1),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'LocalSS',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Local Network Sharing & Chat',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 32),
                    TextField(
                      controller: username,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: password,
                      obscureText: hidePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            hidePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setState(() {
                              hidePassword = !hidePassword;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: loading ? null : login,
                        child: Text(
                          loading ? 'Connecting...' : 'Login',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RegisterScreen(),
                          ),
                        );
                      },
                      child: const Text('Create Account'),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.settings_ethernet),
                      label: const Text('Server Settings'),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ServerSettingsScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final username = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();

  bool loading = false;

  Future<void> register() async {
    if (password.text != confirm.text) {
      showError(context, 'Passwords do not match');
      return;
    }

    setState(() => loading = true);

    try {
      await LocalSSApi.post('/auth/register', {
        'username': username.text.trim(),
        'password': password.text,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account created. Please log in.'),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      showError(context, e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(
                Icons.person_add_alt_1,
                size: 60,
                color: Color(0xFF6366F1),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: username,
                decoration: const InputDecoration(
                  labelText: 'Username',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirm,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm Password',
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: loading ? null : register,
                child: Text(
                  loading ? 'Creating...' : 'Register',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }
}

class ServerSettingsScreen extends StatefulWidget {
  const ServerSettingsScreen({super.key});

  @override
  State<ServerSettingsScreen> createState() =>
      _ServerSettingsScreenState();
}

class _ServerSettingsScreenState
    extends State<ServerSettingsScreen> {
  final controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    controller.text = LocalSSApi.server;
  }

  Future<void> save() async {
    await LocalSSApi.setServer(controller.text);

    if (!mounted) return;

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Server Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.dns,
                  size: 60,
                  color: Color(0xFF6366F1),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Server Address',
                    hintText: 'http://192.168.1.100:3000',
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: save,
                    child: const Text('Save Server Address'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

class DashboardScreen extends StatefulWidget {
  final String username;
  final bool isAdmin;

  const DashboardScreen({
    super.key,
    required this.username,
    required this.isAdmin,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<dynamic> users = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadUsers();
  }

  Future<void> loadUsers() async {
    try {
      await LocalSSApi.post('/users/heartbeat', {});

      final data = await LocalSSApi.get('/users');

      if (!mounted) return;

      setState(() {
        users = data;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => loading = false);
      showError(context, e.toString());
    }
  }

  Future<void> logout() async {
    await LocalSSApi.logout();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LocalSS'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: loadUsers,
            icon: const Icon(Icons.refresh),
          ),
          if (widget.isAdmin)
            IconButton(
              tooltip: 'Admin Panel',
              icon: const Icon(Icons.admin_panel_settings),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdminScreen(),
                  ),
                );
              },
            ),
          IconButton(
            tooltip: 'Logout',
            onPressed: logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: loadUsers,
              child: ListView.builder(
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final user = users[index];

                  final online = user['online'] == true;

                  return Card(
                    color: const Color(0xFF181B24),
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 5,
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: online
                            ? Colors.green
                            : Colors.grey,
                        child: const Icon(
                          Icons.person,
                          color: Colors.white,
                        ),
                      ),
                      title: Text(user['username']),
                      subtitle: Text(
                        online ? 'Online' : 'Offline',
                      ),
                      trailing: const Icon(Icons.chat_bubble_outline),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              userId: user['id'],
                              username: user['username'],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final int userId;
  final String username;

  const ChatScreen({
    super.key,
    required this.userId,
    required this.username,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final messageController = TextEditingController();

  List<dynamic> messages = [];

  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadMessages();
  }

  Future<void> loadMessages() async {
    try {
      final data = await LocalSSApi.get(
        '/messages/${widget.userId}',
      );

      if (!mounted) return;

      setState(() {
        messages = data;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => loading = false);
      showError(context, e.toString());
    }
  }

  Future<void> sendMessage() async {
    final content = messageController.text.trim();

    if (content.isEmpty) return;

    try {
      await LocalSSApi.post('/messages/send', {
        'receiver_id': widget.userId,
        'content': content,
      });

      messageController.clear();

      await loadMessages();
    } catch (e) {
      if (mounted) showError(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.username),
        actions: [
          IconButton(
            onPressed: loadMessages,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];

                      return Card(
                        color: const Color(0xFF222633),
                        child: ListTile(
                          title: Text(message['content']),
                          subtitle: Text(
                            message['created_at'],
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: messageController,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                    ),
                    onSubmitted: (_) => sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: sendMessage,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    messageController.dispose();
    super.dispose();
  }
}

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<dynamic> users = [];

  @override
  void initState() {
    super.initState();
    loadUsers();
  }

  Future<void> loadUsers() async {
    try {
      final data = await LocalSSApi.get('/admin/users');

      if (!mounted) return;

      setState(() => users = data);
    } catch (e) {
      if (mounted) showError(context, e.toString());
    }
  }

  Future<void> deleteUser(int id) async {
    try {
      await LocalSSApi.delete('/admin/users/$id');
      await loadUsers();
    } catch (e) {
      if (mounted) showError(context, e.toString());
    }
  }

  Future<void> deleteHistory() async {
    try {
      await LocalSSApi.delete('/admin/history');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chat history deleted'),
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Super User Dashboard'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: deleteHistory,
              icon: const Icon(Icons.delete_sweep),
              label: const Text('Delete All Chat History'),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: users.length,
              itemBuilder: (context, index) {
                final user = users[index];

                return ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(user['username']),
                  subtitle: Text(
                    user['is_admin'] == 1
                        ? 'Administrator'
                        : 'Normal User',
                  ),
                  trailing: user['is_admin'] == 1
                      ? null
                      : IconButton(
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.red,
                          ),
                          onPressed: () {
                            deleteUser(user['id']);
                          },
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

void showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: Colors.red.shade800,
    ),
  );
}