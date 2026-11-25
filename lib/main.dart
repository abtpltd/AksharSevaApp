import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'screens/connect_screen.dart';
import 'screens/meetings_screen.dart';
import 'store.dart';
import 'theme.dart';
import 'vault.dart';

void main() => runApp(AksharSevakApp(vault: SecureVault()));

class AksharSevakApp extends StatefulWidget {
  final Vault vault;
  const AksharSevakApp({super.key, required this.vault});
  @override
  State<AksharSevakApp> createState() => _AppState();
}

class _AppState extends State<AksharSevakApp> {
  Store? store;
  String savedAddress = '';
  bool ready = false, offline = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// Opens the saved address, and signs in again with the kept token when the person chose to stay signed in.
  Future<void> _init() async {
    var address = '';
    try {
      address = (await SharedPreferences.getInstance()).getString('aksharsevak.server') ?? '';
    } catch (_) {}
    Store? s;
    var off = false;
    final token = await widget.vault.read();
    if (token != null && address.isNotEmpty) {
      try {
        final api = Api(address)..useToken(token);
        s = Store(api);
        await s.start(live: true);
      } on ApiError catch (e) {
        s?.dispose();
        s = null;
        if (e.status == 401) {
          await widget.vault.clear(); // the sign-in ran out: ask again
        } else {
          off = true; // no connection: keep the token and let the person try again
        }
      }
    }
    if (!mounted) return;
    setState(() {
      savedAddress = address;
      store = s;
      offline = off;
      ready = true;
    });
  }

  Future<void> _connected(Store s, String address, bool keep) async {
    try {
      (await SharedPreferences.getInstance()).setString('aksharsevak.server', address);
    } catch (_) {}
    final t = s.api.token;
    if (keep && t != null) {
      await widget.vault.write(t);
    } else {
      await widget.vault.clear();
    }
    setState(() => store = s);
  }

  Future<void> _signOut() async {
    store?.api.signOut();
    store?.dispose();
    await widget.vault.clear();
    setState(() => store = null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AksharSevak',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: !ready
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : store != null
              ? MeetingsScreen(store: store!, onSignOut: _signOut)
              : offline
                  ? Scaffold(
                      appBar: AppBar(title: const Text('AksharSevak')),
                      body: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          const Text('Could not reach your center\'s server. You are still signed in.', textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton(onPressed: () { setState(() { ready = false; offline = false; }); _init(); }, child: const Text('Try again')),
                          TextButton(onPressed: () async { await widget.vault.clear(); setState(() => offline = false); }, child: const Text('Sign in again')),
                        ]),
                      ),
                    )
                  : ConnectScreen(initialAddress: savedAddress, onConnected: _connected),
    );
  }
}
