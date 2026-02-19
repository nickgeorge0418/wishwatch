import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

void main() {
  runApp(const WishWatchApp());
}

class WishItem {
  final String url;
  final DateTime addedAt;

  // New fields
  final double? currentPrice;
  final double? targetPrice;

  WishItem({
    required this.url,
    required this.addedAt,
    this.currentPrice,
    this.targetPrice,
  });

  WishItem copyWith({
    String? url,
    DateTime? addedAt,
    double? currentPrice,
    double? targetPrice,
  }) {
    return WishItem(
      url: url ?? this.url,
      addedAt: addedAt ?? this.addedAt,
      currentPrice: currentPrice ?? this.currentPrice,
      targetPrice: targetPrice ?? this.targetPrice,
    );
  }

  Map<String, dynamic> toMap() => {
        'url': url,
        'addedAt': addedAt.toIso8601String(),
        'currentPrice': currentPrice,
        'targetPrice': targetPrice,
      };

  factory WishItem.fromMap(Map<String, dynamic> map) => WishItem(
        url: map['url'] as String,
        addedAt: DateTime.parse(map['addedAt'] as String),
        currentPrice: (map['currentPrice'] as num?)?.toDouble(),
        targetPrice: (map['targetPrice'] as num?)?.toDouble(),
      );
}

class WishWatchApp extends StatelessWidget {
  const WishWatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WishWatch',
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _targetController = TextEditingController();

  final List<WishItem> _wishlist = [];

  StreamSubscription? _intentSubscription;

  @override
  void initState() {
    super.initState();
    _loadWishlist();

    if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android)) {
    _listenForSharedLinks();
    }
  }

  @override
  void dispose() {
    _intentSubscription?.cancel();
    _urlController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  void _listenForSharedLinks() {
  // While app is running (foreground/background)
  _intentSubscription =
      ReceiveSharingIntent.instance.getMediaStream().listen(
    (List<SharedMediaFile> files) {
      if (files.isEmpty) return;

      final shared = files.first;

      // For text/URL shares, the URL/text is usually in .path
      final candidate = (shared.path).trim();

      if (candidate.startsWith('http')) {
        setState(() {
          _urlController.text = candidate;
        });
      }
    },
    onError: (err) {
      // optional
      // debugPrint("Share stream error: $err");
    },
  );

  // If the app was launched via Share (cold start)
  ReceiveSharingIntent.instance.getInitialMedia().then(
    (List<SharedMediaFile> files) {
      if (files.isEmpty) return;

      final shared = files.first;
      final candidate = (shared.path).trim();

      if (candidate.startsWith('http')) {
        setState(() {
          _urlController.text = candidate;
        });
      }

      // Optional but recommended: prevents the same initial share being reused
      ReceiveSharingIntent.instance.reset();
    },
  );
}


  // ---------- Persistence ----------
  Future<void> _loadWishlist() async {
    final prefs = await SharedPreferences.getInstance();
    final savedList = prefs.getStringList('wishlist');

    if (savedList == null) return;

    final items = savedList
        .map((s) => WishItem.fromMap(jsonDecode(s) as Map<String, dynamic>))
        .toList();

    setState(() {
      _wishlist
        ..clear()
        ..addAll(items);
    });
  }

  Future<void> _saveWishlist() async {
    final prefs = await SharedPreferences.getInstance();
    final listAsJsonString =
        _wishlist.map((item) => jsonEncode(item.toMap())).toList();
    await prefs.setStringList('wishlist', listAsJsonString);
  }

  // ---------- Helpers ----------
  double? _parsePrice(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return null;
    final cleaned = raw.replaceAll('\$', '').replaceAll(',', '');
    return double.tryParse(cleaned);
  }

  bool _isValidUrl(String text) {
    final uri = Uri.tryParse(text);
    return uri != null && uri.hasScheme && uri.hasAuthority;
  }

  // ---------- Actions ----------
  void _addItem() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    if (!_isValidUrl(url)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid URL')),
      );
      return;
    }

    final targetPrice = _parsePrice(_targetController.text);

    setState(() {
      _wishlist.add(
        WishItem(
          url: url,
          addedAt: DateTime.now(),
          targetPrice: targetPrice,
          currentPrice: null, // Start unknown; update later per-item
        ),
      );
      _urlController.clear();
      _targetController.clear();
    });

    _saveWishlist();
  }

  Future<void> _promptUpdateCurrentPrice(int index) async {
    final controller = TextEditingController(
      text: _wishlist[index].currentPrice?.toStringAsFixed(2) ?? '',
    );

    final result = await showDialog<double?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Update current price'),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Current price',
              hintText: 'e.g. 49.99',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final parsed = _parsePrice(controller.text);
                Navigator.of(context).pop(parsed);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    // Cancel
    if (!mounted || result == null && controller.text.trim().isNotEmpty) {
      // Note: If they typed something invalid (result null) we could warn.
      // Keeping it simple: empty => clear price; invalid => clear as null.
    }

    final newPrice = _parsePrice(controller.text);

    setState(() {
      _wishlist[index] = _wishlist[index].copyWith(currentPrice: newPrice);
    });

    await _saveWishlist();
  }

  void _deleteItem(int index) {
    setState(() {
      _wishlist.removeAt(index);
    });
    _saveWishlist();
  }

  // ---------- UI helpers ----------
  Widget _statusChip(WishItem item) {
    final current = item.currentPrice;
    final target = item.targetPrice;

    // Unknown
    if (current == null || target == null) {
      return const Chip(
        label: Text('UNKNOWN'),
      );
    }

    // Buy now vs waiting
    final isDeal = current <= target;
    return Chip(
      label: Text(isDeal ? 'BUY NOW' : 'WAITING'),
    );
  }

  String _money(double? v) => v == null ? '—' : '\$${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WishWatch'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Paste product URL',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _targetController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Target price (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _addItem,
              child: const Text('Add to Wishlist'),
            ),
            const SizedBox(height: 20),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Your Wishlist',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: _wishlist.length,
                itemBuilder: (context, index) {
                  final item = _wishlist[index];

                  return Card(
                    child: ListTile(
                      title: Text(item.url),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            _statusChip(item),
                            const SizedBox(width: 12),
                            Text('Current: ${_money(item.currentPrice)}'),
                            const SizedBox(width: 12),
                            Text('Target: ${_money(item.targetPrice)}'),
                          ],
                        ),
                      ),
                      trailing: Wrap(
                        spacing: 6,
                        children: [
                          IconButton(
                            tooltip: 'Update current price',
                            icon: const Icon(Icons.edit),
                            onPressed: () => _promptUpdateCurrentPrice(index),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteItem(index),
                          ),
                        ],
                      ),
                    ),
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