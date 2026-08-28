import 'dart:async';

import 'package:activelook_sdk/activelook_sdk.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _sdk = ActivelookSdk();
  final _found = <ActiveLookDiscoveredGlasses>[];

  StreamSubscription<ActiveLookDiscoveredGlasses>? _scanSub;
  StreamSubscription<ActiveLookConnectionState>? _connectionSub;
  ActiveLookConnectionState _connectionState = ActiveLookConnectionState.disconnected;

  @override
  void initState() {
    super.initState();
    _connectionSub = _sdk.connectionState.listen((state) {
      if (mounted) setState(() => _connectionState = state);
    });
  }

  void _startScan() {
    setState(_found.clear);
    _scanSub = _sdk.startScan().listen((glasses) {
      setState(() => _found.add(glasses));
    });
  }

  void _stopScan() {
    _scanSub?.cancel();
    _sdk.stopScan();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _connectionSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('activelook_sdk example')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Connection: ${_connectionState.name}'),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(onPressed: _startScan, child: const Text('Scan')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _stopScan, child: const Text('Stop scan')),
              ],
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _found.length,
                itemBuilder: (context, index) {
                  final glasses = _found[index];
                  return ListTile(
                    title: Text(glasses.name),
                    subtitle: Text(glasses.id),
                    onTap: () => _sdk.connect(glasses.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
