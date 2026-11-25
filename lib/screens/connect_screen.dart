import 'package:flutter/material.dart';
import '../api.dart';
import '../store.dart';
import '../theme.dart';

class ConnectScreen extends StatefulWidget {
  final String initialAddress;
  final Future<void> Function(Store store, String address, bool keep) onConnected;
  const ConnectScreen({super.key, required this.initialAddress, required this.onConnected});
  @override
  State<ConnectScreen> createState() => _ConnectState();
}

class _ConnectState extends State<ConnectScreen> {
  late final address = TextEditingController(text: widget.initialAddress);
  final phone = TextEditingController(), code = TextEditingController(), name = TextEditingController(), invite = TextEditingController();
  final userId = TextEditingController(), password = TextEditingController();
  bool byPassword = false, codeSent = false, busy = false, firstTime = false, keep = true;
  String? error;
  Api? api;

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await f();
    } on ApiError catch (e) {
      setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Api _api() => api = Api(address.text);

  Future<void> _finish(Api a) async {
    final s = Store(a);
    await s.start(live: true);
    await widget.onConnected(s, a.base, keep);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AksharSevak')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Center(child: CircleAvatar(radius: 28, backgroundColor: Colors.white, child: Text('Logo', style: TextStyle(color: baps_red, fontSize: 12)))),
        const SizedBox(height: 8),
        const Center(child: Text('Jai Swaminarayan', style: TextStyle(color: baps_red, fontSize: 18, fontWeight: FontWeight.w500))),
        const Center(child: Text('Sign in to serve')),
        const SizedBox(height: 4),
        const Text('Everything is kept on your center\'s server, so you need a connection.', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        TextField(controller: address, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Server address', hintText: 'https://...')),
        const SizedBox(height: 12),
        if (!byPassword) ...[
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone number', hintText: '+254...')),
          if (codeSent) TextField(controller: code, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'One-time code')),
          CheckboxListTile(contentPadding: EdgeInsets.zero, value: firstTime, onChanged: (v) => setState(() => firstTime = v ?? false), title: const Text('First time here')),
          if (firstTime) ...[
            TextField(controller: invite, decoration: const InputDecoration(labelText: 'Center code (from the QR)')),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Your name')),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy
                ? null
                : () => _run(() async {
                      final a = codeSent && api != null ? api! : _api();
                      if (!codeSent) {
                        await a.startPhone(phone.text.trim(), inviteCode: firstTime ? invite.text.trim() : null);
                        setState(() => codeSent = true);
                      } else {
                        await a.verifyPhone(phone.text.trim(), code.text.trim(), inviteCode: firstTime ? invite.text.trim() : null, name: firstTime ? name.text.trim() : null);
                        await _finish(a);
                      }
                    }),
            child: Text(codeSent ? 'Sign in' : 'Send me a code'),
          ),
        ] else ...[
          TextField(controller: userId, decoration: const InputDecoration(labelText: 'Sign-in name')),
          TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy
                ? null
                : () => _run(() async {
                      final a = _api();
                      await a.login(userId.text.trim(), password.text);
                      await _finish(a);
                    }),
            child: const Text('Sign in'),
          ),
        ],
        CheckboxListTile(contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, value: keep, onChanged: (v) => setState(() => keep = v ?? true), title: const Text('Keep me signed in')),
        if (busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        TextButton(onPressed: busy ? null : () => setState(() { byPassword = !byPassword; error = null; codeSent = false; }), child: Text(byPassword ? 'Use my phone number instead' : 'Coordinator? Sign in with a password')),
      ]),
    );
  }
}
