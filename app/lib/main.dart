import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const ImportProfitApp());
}

class ImportProfitApp extends StatelessWidget {
  const ImportProfitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Syntex Imports',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6B5B95)),
        useMaterial3: true,
      ),
      home: const BootScreen(),
    );
  }
}

/// ----------------------
/// Models
/// ----------------------

enum ShipmentStatus { draft, active, sold }

class ProductLine {
  String name;
  int qty;
  double buyPriceRmb; // per item
  double sellPricePkr; // per item

  ProductLine({
    required this.name,
    required this.qty,
    required this.buyPriceRmb,
    required this.sellPricePkr,
  });

  double get totalBuyRmb => buyPriceRmb * qty;
  double get totalSellPkr => sellPricePkr * qty;

  Map<String, dynamic> toJson() => {
        'name': name,
        'qty': qty,
        'buyPriceRmb': buyPriceRmb,
        'sellPricePkr': sellPricePkr,
      };

  static ProductLine fromJson(Map<String, dynamic> j) => ProductLine(
        name: (j['name'] ?? '').toString(),
        qty: (j['qty'] ?? 0) as int,
        buyPriceRmb: (j['buyPriceRmb'] ?? 0).toDouble(),
        sellPricePkr: (j['sellPricePkr'] ?? 0).toDouble(),
      );
}

class Shipment {
  String id;
  String title; // Shipment 1 / custom name
  DateTime? landingDate;

  // Costs
  double rmbToPkrRate; // 1 RMB = ? PKR
  double shippingCostPkr;
  double inventoryCostPkr; // Manual shipment purchase total, separate from freight
  double landingCostPkr; // customs/landing misc in PKR

  String warrantiesNote;

  ShipmentStatus status;

  List<ProductLine> items;

  /// Cashflow flags to avoid double apply
  bool costDeductedFromBalance;
  bool saleAddedToBalance;

  Shipment({
    required this.id,
    required this.title,
    required this.landingDate,
    required this.rmbToPkrRate,
    required this.shippingCostPkr,
    this.inventoryCostPkr = 0,
    required this.landingCostPkr,
    required this.warrantiesNote,
    required this.status,
    required this.items,
    required this.costDeductedFromBalance,
    required this.saleAddedToBalance,
  });

  double get totalBuyRmb => items.fold(0.0, (s, x) => s + x.totalBuyRmb);
  double get totalBuyPkr => inventoryCostPkr > 0 ? inventoryCostPkr : totalBuyRmb * rmbToPkrRate;
  double get totalCostPkr => totalBuyPkr + shippingCostPkr + landingCostPkr;

  double get totalSellPkr => items.fold(0.0, (s, x) => s + x.totalSellPkr);

  double get profitPkr => totalSellPkr - totalCostPkr;

  double get profitPercent {
    final c = totalCostPkr;
    if (c <= 0) return 0;
    return (profitPkr / c) * 100.0;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'landingDate': landingDate?.toIso8601String(),
        'rmbToPkrRate': rmbToPkrRate,
        'shippingCostPkr': shippingCostPkr,
        'inventoryCostPkr': inventoryCostPkr,
        'landingCostPkr': landingCostPkr,
        'warrantiesNote': warrantiesNote,
        'status': status.name,
        'items': items.map((e) => e.toJson()).toList(),
        'costDeductedFromBalance': costDeductedFromBalance,
        'saleAddedToBalance': saleAddedToBalance,
      };

  static Shipment fromJson(Map<String, dynamic> j) => Shipment(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? 'Shipment').toString(),
        landingDate: j['landingDate'] == null || (j['landingDate'] as String).isEmpty
            ? null
            : DateTime.tryParse(j['landingDate']),
        rmbToPkrRate: (j['rmbToPkrRate'] ?? 0).toDouble(),
        shippingCostPkr: (j['shippingCostPkr'] ?? 0).toDouble(),
        inventoryCostPkr: (j['inventoryCostPkr'] ?? 0).toDouble(),
        landingCostPkr: (j['landingCostPkr'] ?? 0).toDouble(),
        warrantiesNote: (j['warrantiesNote'] ?? '').toString(),
        status: _statusFromName((j['status'] ?? 'draft').toString()),
        items: ((j['items'] ?? []) as List).map((e) => ProductLine.fromJson(e)).toList(),
        costDeductedFromBalance: (j['costDeductedFromBalance'] ?? false) as bool,
        saleAddedToBalance: (j['saleAddedToBalance'] ?? false) as bool,
      );
}

ShipmentStatus _statusFromName(String s) {
  for (final v in ShipmentStatus.values) {
    if (v.name == s) return v;
  }
  return ShipmentStatus.draft;
}

/// ----------------------
/// Persistence
/// ----------------------

class AppData {
  double initialCapitalPkr;
  double currentBalancePkr;
  List<Shipment> shipments;

  AppData({
    required this.initialCapitalPkr,
    required this.currentBalancePkr,
    required this.shipments,
  });

  Map<String, dynamic> toJson() => {
        'initialCapitalPkr': initialCapitalPkr,
        'currentBalancePkr': currentBalancePkr,
        'shipments': shipments.map((s) => s.toJson()).toList(),
      };

  static AppData fromJson(Map<String, dynamic> j) => AppData(
        initialCapitalPkr: (j['initialCapitalPkr'] ?? 0).toDouble(),
        currentBalancePkr: (j['currentBalancePkr'] ?? 0).toDouble(),
        shipments: ((j['shipments'] ?? []) as List).map((e) => Shipment.fromJson(e)).toList(),
      );
}

class Storage {
  static const _key = 'import_profit_app_data_v1';

  static Future<AppData> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return AppData(initialCapitalPkr: 0, currentBalancePkr: 0, shipments: []);
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return AppData.fromJson(map);
    } catch (_) {
      return AppData(initialCapitalPkr: 0, currentBalancePkr: 0, shipments: []);
    }
  }

  static Future<void> save(AppData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(data.toJson()));
  }

  static Future<String?> cloudBase() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('syntex_drive_base');
  }
  static Future<void> setCloudBase(String text) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('syntex_drive_base', text);
  }
}

// Google Drive Document provider: user chooses a Drive file with Android's file picker.
// No OAuth client ID or extra Google account password is required.
class DriveDocument {
  static const MethodChannel _ch = MethodChannel('syntex.drive');
  static Future<bool> linked() async => await _ch.invokeMethod<bool>('connected') ?? false;
  static Future<String> create() async => await _ch.invokeMethod<String>('create') ?? '';
  static Future<String> open() async => await _ch.invokeMethod<String>('open') ?? '';
  static Future<String> read() async => await _ch.invokeMethod<String>('read') ?? '';
  static Future<void> write(String json) async => _ch.invokeMethod<void>('write', json);
}

/// ----------------------
/// Boot screen
/// ----------------------

class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> {
  AppData? data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await Storage.load();
    setState(() => data = d);
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (d == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return HomeScreen(initialData: d);
  }
}

/// ----------------------
/// Home
/// ----------------------

class HomeScreen extends StatefulWidget {
  final AppData initialData;
  const HomeScreen({super.key, required this.initialData});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late AppData data;

  final _money = NumberFormat('#,##0.00');

  @override
  void initState() {
    super.initState();
    data = widget.initialData;
  }

  Future<void> _persist() async {
    await Storage.save(data);
    await _autoCloudSave();
    if (mounted) setState(() {});
  }

  void _notice(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // Safe automatic write: do not overwrite a Drive file modified by another phone.
  Future<void> _autoCloudSave() async {
    try {
      if (!await DriveDocument.linked()) return;
      final local = jsonEncode(data.toJson());
      final remote = await DriveDocument.read();
      final base = await Storage.cloudBase();
      if (remote == local) { await Storage.setCloudBase(local); return; }
      if ((base != null && remote == base) || (base == null && remote.isEmpty)) {
        await DriveDocument.write(local);
        await Storage.setCloudBase(local);
      } else {
        _notice('Drive changed elsewhere. Tap Cloud > Sync now to resolve conflict.');
      }
    } catch (e) {
      _notice('Saved on phone. Drive upload failed; use Cloud > Sync now.');
    }
  }

  Future<void> _createCloudFile() async {
    try {
      await DriveDocument.create();
      final local = jsonEncode(data.toJson());
      await DriveDocument.write(local);
      await Storage.setCloudBase(local);
      _notice('Drive file created and phone data uploaded. Select Google Drive in the file picker.');
    } catch (e) {
      _notice('Drive file was not connected: ' + e.toString());
    }
  }

  Future<void> _openCloudFile() async {
    try {
      final remote = await DriveDocument.open();
      if (remote.isEmpty) {
        final local = jsonEncode(data.toJson());
        await DriveDocument.write(local);
        await Storage.setCloudBase(local);
        _notice('Empty Drive file linked and uploaded');
        return;
      }
      // Never silently replace shipment and investor records.
      await _chooseConflict(remote);
    } catch (e) {
      _notice('Drive file not opened: ' + e.toString());
    }
  }

  Future<void> _syncCloud() async {
    try {
      if (!await DriveDocument.linked()) {
        _notice('Choose Cloud > Create Drive file or Open existing Drive file');
        return;
      }
      final remote = await DriveDocument.read();
      final local = jsonEncode(data.toJson());
      if (remote == local) { await Storage.setCloudBase(local); _notice('Drive up to date'); return; }
      final base = await Storage.cloudBase();
      if (remote.isEmpty || (base != null && remote == base)) {
        await DriveDocument.write(local);
        await Storage.setCloudBase(local);
        _notice('Phone data uploaded to Google Drive');
      } else if (base != null && local == base) {
        await _applyCloud(remote);
      } else {
        await _chooseConflict(remote);
      }
    } catch (e) { _notice('Sync failed: ' + e.toString()); }
  }

  Future<void> _applyCloud(String remote) async {
    final decoded = jsonDecode(remote);
    if (decoded is! Map<String, dynamic> || decoded['shipments'] is! List
        || decoded['initialCapitalPkr'] == null) {
      throw const FormatException('Not a Syntex Imports backup file');
    }
    final updated = AppData.fromJson(decoded);
    await Storage.save(updated);
    await Storage.setCloudBase(remote);
    if (mounted) setState(() => data = updated);
    _notice('Downloaded Google Drive records');
  }

  Future<void> _chooseConflict(String remote) async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Choose data to keep'),
        content: const Text('This Drive file and the phone have different data. No merge is possible. Choose which FULL copy to keep. Export a separate backup first if needed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'drive'), child: const Text('Use Drive copy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'phone'), child: const Text('Use phone copy')),
        ],
      ),
    );
    if (chosen == 'drive') {
      try { await _applyCloud(remote); } catch (e) { _notice('Drive restore failed: ' + e.toString()); }
    } else if (chosen == 'phone') {
      try {
        final local = jsonEncode(data.toJson());
        await DriveDocument.write(local);
        await Storage.setCloudBase(local);
        _notice('Phone data uploaded to Drive');
      } catch (e) { _notice('Drive upload failed: ' + e.toString()); }
    }
  }

  Future<void> _editCapitalDialog() async {
    final ctrl = TextEditingController(text: data.initialCapitalPkr.toStringAsFixed(0));
    final ctrl2 = TextEditingController(text: data.currentBalancePkr.toStringAsFixed(0));

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Capital / Balance'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Initial Capital (PKR)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl2,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Current Balance (PKR)'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tip: Compounding works like this:\n'
              'Active shipment = cost deducted\n'
              'Sold shipment = sale added\n',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );

    if (ok == true) {
      final init = double.tryParse(ctrl.text.trim()) ?? data.initialCapitalPkr;
      final bal = double.tryParse(ctrl2.text.trim()) ?? data.currentBalancePkr;
      setState(() {
        data.initialCapitalPkr = init;
        data.currentBalancePkr = bal;
      });
      await _persist();
    }
  }

  Future<void> _addShipment() async {
    final created = await Navigator.push<Shipment>(
      context,
      MaterialPageRoute(builder: (_) => ShipmentEditorScreen(existing: null)),
    );

    if (created != null) {
      setState(() => data.shipments.insert(0, created));
      await _persist();
    }
  }

  Future<void> _openShipment(Shipment s) async {
    final updated = await Navigator.push<Shipment>(
      context,
      MaterialPageRoute(builder: (_) => ShipmentDetailScreen(shipment: s, balance: data.currentBalancePkr)),
    );

    if (updated != null) {
      final idx = data.shipments.indexWhere((x) => x.id == updated.id);
      if (idx >= 0) {
        setState(() => data.shipments[idx] = updated);
      }

      // Apply cashflow rules
      await _applyCashflow(updated);

      await _persist();
    }
  }

  Future<void> _applyCashflow(Shipment s) async {
    // If moved to active and cost not deducted -> deduct totalCost
    if (s.status == ShipmentStatus.active && !s.costDeductedFromBalance) {
      final cost = s.totalCostPkr;
      if (cost > 0 && data.currentBalancePkr >= cost) {
        data.currentBalancePkr -= cost;
        s.costDeductedFromBalance = true;
      }
    }

    // If moved to sold and sale not added -> add totalSell
    if (s.status == ShipmentStatus.sold && !s.saleAddedToBalance) {
      final sale = s.totalSellPkr;
      if (sale > 0) {
        data.currentBalancePkr += sale;
        s.saleAddedToBalance = true;
      }
    }
  }

  Future<void> _deleteShipment(Shipment s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete shipment?'),
        content: const Text('Permanently delete this shipment? Any balance entries applied for it will be reversed using its current costs and sales. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );

    if (ok == true) {
      setState(() {
        if (s.costDeductedFromBalance) data.currentBalancePkr += s.totalCostPkr;
        if (s.saleAddedToBalance) data.currentBalancePkr -= s.totalSellPkr;
        data.shipments.removeWhere((x) => x.id == s.id);
      });
      await _persist();
    }
  }

  @override
  Widget build(BuildContext context) {
    final shipments = data.shipments;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Syntex Imports'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Google Drive',
            icon: const Icon(Icons.cloud_sync_outlined),
            onSelected: (value) {
              if (value == 'create') _createCloudFile();
              if (value == 'open') _openCloudFile();
              if (value == 'sync') _syncCloud();
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'create', child: Text('Create Google Drive backup')),
              PopupMenuItem(value: 'open', child: Text('Open existing Drive backup')),
              PopupMenuItem(value: 'sync', child: Text('Sync now')),
            ],
          ),
          IconButton(
            onPressed: _editCapitalDialog,
            icon: const Icon(Icons.account_balance_wallet_outlined),
            tooltip: 'Capital / Balance',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addShipment,
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _summaryCard(),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Shipments', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${shipments.length} total'),
            ],
          ),
          const SizedBox(height: 8),
          if (shipments.isEmpty)
            _emptyState()
          else
            ...shipments.map((s) => _shipmentTile(s)),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _summaryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Capital', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _pill('Initial', 'PKR ${_money.format(data.initialCapitalPkr)}'),
                _pill('Current Balance', 'PKR ${_money.format(data.currentBalancePkr)}'),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Compounding rule:\n'
              '• Active = cost deducted from balance\n'
              '• Sold = sale added to balance\n'
              'So profit automatically compounds.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String a, String b) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(a, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(b, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Icon(Icons.inventory_2_outlined, size: 40),
            const SizedBox(height: 8),
            const Text('No shipments yet'),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _addShipment,
              icon: const Icon(Icons.add),
              label: const Text('Add New Shipment'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shipmentTile(Shipment s) {
    final money = NumberFormat('#,##0.00');
    final date = s.landingDate == null ? 'No date' : DateFormat('dd MMM yyyy').format(s.landingDate!);

    final badgeText = s.status == ShipmentStatus.sold
        ? '${s.profitPercent.toStringAsFixed(1)}% profit'
        : s.status == ShipmentStatus.active
            ? 'ACTIVE'
            : 'DRAFT';

    final badgeColor = s.status == ShipmentStatus.sold
        ? (s.profitPkr >= 0 ? Colors.green : Colors.red)
        : (s.status == ShipmentStatus.active ? Colors.blue : Colors.grey);

    return Card(
      child: ListTile(
        onTap: () => _openShipment(s),
        title: Text(s.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('$date • Items: ${s.items.length} • Cost: PKR ${money.format(s.totalCostPkr)}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: badgeColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                badgeText,
                style: TextStyle(color: badgeColor, fontWeight: FontWeight.w800, fontSize: 12),
              ),
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: () => _deleteShipment(s),
              child: const Icon(Icons.delete_outline, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

/// ----------------------
/// Shipment Detail
/// ----------------------

class ShipmentDetailScreen extends StatefulWidget {
  final Shipment shipment;
  final double balance;
  const ShipmentDetailScreen({super.key, required this.shipment, required this.balance});

  @override
  State<ShipmentDetailScreen> createState() => _ShipmentDetailScreenState();
}

class _ShipmentDetailScreenState extends State<ShipmentDetailScreen> {
  late Shipment s;
  final _money = NumberFormat('#,##0.00');

  @override
  void initState() {
    super.initState();
    s = Shipment.fromJson(widget.shipment.toJson()); // clone
  }

  Future<void> _edit() async {
    final updated = await Navigator.push<Shipment>(
      context,
      MaterialPageRoute(builder: (_) => ShipmentEditorScreen(existing: s)),
    );
    if (updated != null) setState(() => s = updated);
  }

  @override
  Widget build(BuildContext context) {
    final date = s.landingDate == null ? 'Not set' : DateFormat('dd MMM yyyy').format(s.landingDate!);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.title),
        actions: [
          IconButton(onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
          IconButton(
            onPressed: () => Navigator.pop(context, s),
            icon: const Icon(Icons.check_circle_outline),
            tooltip: 'Save & Back',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Status: ${s.status.name.toUpperCase()}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text('Landing date: $date'),
                  const SizedBox(height: 8),
                  Text('Rate: 1 RMB = ${s.rmbToPkrRate.toStringAsFixed(2)} PKR'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _totalsCard(),
          const SizedBox(height: 12),
          _itemsCard(),
          const SizedBox(height: 12),
          _warrantyCard(),
          const SizedBox(height: 12),
          _actionsCard(),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _totalsCard() {
    final profitColor = s.profitPkr >= 0 ? Colors.green : Colors.red;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Totals', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            _row('Buying (RMB)', s.totalBuyRmb.toStringAsFixed(2)),
            _row('Inventory buying (PKR)', 'PKR ${_money.format(s.totalBuyPkr)}'),
            _row('Shipping (PKR)', 'PKR ${_money.format(s.shippingCostPkr)}'),
            _row('Landing (PKR)', 'PKR ${_money.format(s.landingCostPkr)}'),
            const Divider(),
            _row('Final Cost', 'PKR ${_money.format(s.totalCostPkr)}', bold: true),
            _row('Total Selling', 'PKR ${_money.format(s.totalSellPkr)}', bold: true),
            const Divider(),
            Row(
              children: [
                const Expanded(child: Text('Profit', style: TextStyle(fontWeight: FontWeight.w900))),
                Text(
                  'PKR ${_money.format(s.profitPkr)}  (${s.profitPercent.toStringAsFixed(1)}%)',
                  style: TextStyle(fontWeight: FontWeight.w900, color: profitColor),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String a, String b, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500))),
          Text(b, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _itemsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Products', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (s.items.isEmpty)
              const Text('No products added yet.')
            else
              ...s.items.map((p) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${p.name} (x${p.qty})',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text('Buy RMB ${p.buyPriceRmb.toStringAsFixed(2)}'),
                      const SizedBox(width: 10),
                      Text('Sell PKR ${_money.format(p.sellPricePkr)}'),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _warrantyCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Warranties / Notes', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(s.warrantiesNote.isEmpty ? '—' : s.warrantiesNote),
          ],
        ),
      ),
    );
  }

  Widget _actionsCard() {
    final canActivate = s.status == ShipmentStatus.draft;
    final canSell = s.status == ShipmentStatus.active;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Actions', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text('Current Balance (PKR): ${_money.format(widget.balance)}', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 10),
            if (canActivate)
              FilledButton.icon(
                onPressed: () {
                  setState(() => s.status = ShipmentStatus.active);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Marked ACTIVE. Save (✓) to apply cost deduction.')),
                  );
                },
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Mark as ACTIVE (deduct cost from balance)'),
              ),
            if (canSell)
              FilledButton.icon(
                onPressed: () {
                  setState(() => s.status = ShipmentStatus.sold);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Marked SOLD. Save (✓) to add selling amount to balance.')),
                  );
                },
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Mark as SOLD (add sale to balance)'),
              ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, s),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save & Back'),
            ),
          ],
        ),
      ),
    );
  }
}

/// ----------------------
/// Shipment Editor (Create/Edit + Multi products)
/// ----------------------

class ShipmentEditorScreen extends StatefulWidget {
  final Shipment? existing;
  const ShipmentEditorScreen({super.key, required this.existing});

  @override
  State<ShipmentEditorScreen> createState() => _ShipmentEditorScreenState();
}

class _ShipmentEditorScreenState extends State<ShipmentEditorScreen> {
  final _title = TextEditingController();
  final _rate = TextEditingController();
  final _shipping = TextEditingController();
  final _inventory = TextEditingController();
  final _landing = TextEditingController();
  final _warranty = TextEditingController();

  DateTime? landingDate;
  ShipmentStatus status = ShipmentStatus.draft;

  List<ProductLine> items = [];

  final _money = NumberFormat('#,##0.00');

  @override
  void initState() {
    super.initState();

    final e = widget.existing;
    if (e != null) {
      _title.text = e.title;
      _rate.text = e.rmbToPkrRate.toString();
      _shipping.text = e.shippingCostPkr.toString();
      _inventory.text = e.inventoryCostPkr > 0 ? e.inventoryCostPkr.toStringAsFixed(2) : '';
      _landing.text = e.landingCostPkr.toString();
      _warranty.text = e.warrantiesNote;
      landingDate = e.landingDate;
      status = e.status;
      items = e.items.map((x) => ProductLine(name: x.name, qty: x.qty, buyPriceRmb: x.buyPriceRmb, sellPricePkr: x.sellPricePkr)).toList();
    } else {
      _title.text = 'Shipment ${DateTime.now().millisecondsSinceEpoch % 10000}';
      _rate.text = '40.0';
      _shipping.text = '0';
      _inventory.text = '';
      _landing.text = '0';
    }
  }

  Shipment _buildResult() {
    final id = widget.existing?.id ?? 'S-${DateTime.now().millisecondsSinceEpoch}';

    final r = double.tryParse(_rate.text.trim()) ?? 0;
    final ship = double.tryParse(_shipping.text.trim()) ?? 0;
    final inventory = double.tryParse(_inventory.text.trim()) ?? 0;
    final land = double.tryParse(_landing.text.trim()) ?? 0;

    final existing = widget.existing;

    return Shipment(
      id: id,
      title: _title.text.trim().isEmpty ? 'Shipment' : _title.text.trim(),
      landingDate: landingDate,
      rmbToPkrRate: r,
      shippingCostPkr: ship,
      inventoryCostPkr: inventory,
      landingCostPkr: land,
      warrantiesNote: _warranty.text.trim(),
      status: status,
      items: items,
      costDeductedFromBalance: existing?.costDeductedFromBalance ?? false,
      saleAddedToBalance: existing?.saleAddedToBalance ?? false,
    );
  }

  double get _totalBuyRmb => items.fold(0.0, (s, x) => s + x.totalBuyRmb);
  double get _rateVal => double.tryParse(_rate.text.trim()) ?? 0;
  double get _shippingVal => double.tryParse(_shipping.text.trim()) ?? 0;
  double get _inventoryVal => double.tryParse(_inventory.text.trim()) ?? 0;
  double get _landingVal => double.tryParse(_landing.text.trim()) ?? 0;

  double get _totalCostPkr => (_inventoryVal > 0 ? _inventoryVal : _totalBuyRmb * _rateVal) + _shippingVal + _landingVal;
  double get _totalSellPkr => items.fold(0.0, (s, x) => s + x.totalSellPkr);
  double get _profit => _totalSellPkr - _totalCostPkr;
  double get _profitPct => _totalCostPkr <= 0 ? 0 : (_profit / _totalCostPkr) * 100.0;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
      initialDate: landingDate ?? now,
    );
    if (picked != null) setState(() => landingDate = picked);
  }

  Future<void> _addOrEditProduct({ProductLine? existing, int? index}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final qtyCtrl = TextEditingController(text: (existing?.qty ?? 1).toString());
    final buyCtrl = TextEditingController(text: (existing?.buyPriceRmb ?? 0).toString());
    final sellCtrl = TextEditingController(text: (existing?.sellPricePkr ?? 0).toString());

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add Product' : 'Edit Product'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Product name')),
              const SizedBox(height: 8),
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: buyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Buying price per item (RMB)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: sellCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Selling price per item (PKR)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );

    if (ok == true) {
      final p = ProductLine(
        name: nameCtrl.text.trim().isEmpty ? 'Product' : nameCtrl.text.trim(),
        qty: int.tryParse(qtyCtrl.text.trim()) ?? 1,
        buyPriceRmb: double.tryParse(buyCtrl.text.trim()) ?? 0,
        sellPricePkr: double.tryParse(sellCtrl.text.trim()) ?? 0,
      );

      setState(() {
        if (index != null) {
          items[index] = p;
        } else {
          items.add(p);
        }
      });
    }
  }

  void _removeProduct(int index) {
    setState(() => items.removeAt(index));
  }

  void _save() {
    final res = _buildResult();
    Navigator.pop(context, res);
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = landingDate == null ? 'Set landing date' : DateFormat('dd MMM yyyy').format(landingDate!);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New Shipment' : 'Edit Shipment'),
        actions: [
          IconButton(onPressed: _save, icon: const Icon(Icons.check_circle_outline)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEditProduct(),
        icon: const Icon(Icons.add),
        label: const Text('Add Product'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  TextField(
                    controller: _title,
                    decoration: const InputDecoration(labelText: 'Shipment name (e.g. Shipment 1)'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickDate,
                          icon: const Icon(Icons.date_range_outlined),
                          label: Text(dateLabel),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<ShipmentStatus>(
                    value: status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: ShipmentStatus.values
                        .map((x) => DropdownMenuItem(value: x, child: Text(x.name.toUpperCase())))
                        .toList(),
                    onChanged: (v) => setState(() => status = v ?? ShipmentStatus.draft),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  TextField(
                    controller: _rate,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'RMB to PKR rate (1 RMB = ? PKR)'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _inventory,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Inventory buying cost (PKR)', helperText: 'Total cost of goods. Items are its breakdown, not extra charges.'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _shipping,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Shipping cost (PKR)'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _landing,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Landing cost (PKR)'),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Products in this shipment', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  if (items.isEmpty)
                    const Text('No products yet. Tap "Add Product".')
                  else
                    ...List.generate(items.length, (i) {
                      final p = items[i];
                      return Card(
                        child: ListTile(
                          title: Text('${p.name}  (x${p.qty})', style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            'Buy: RMB ${p.buyPriceRmb.toStringAsFixed(2)}  |  '
                            'Sell: PKR ${_money.format(p.sellPricePkr)}',
                          ),
                          trailing: Wrap(
                            spacing: 8,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _addOrEditProduct(existing: p, index: i),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _removeProduct(i),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Auto Profit (preview)', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  _kv('Total Buy (RMB)', _totalBuyRmb.toStringAsFixed(2)),
                  _kv('Inventory cost (PKR)', 'PKR ${_money.format(_inventoryVal > 0 ? _inventoryVal : _totalBuyRmb * _rateVal)}'),
                  _kv('Shipping (PKR)', 'PKR ${_money.format(_shippingVal)}'),
                  _kv('Final Cost (PKR)', 'PKR ${_money.format(_totalCostPkr)}'),
                  _kv('Total Selling (PKR)', 'PKR ${_money.format(_totalSellPkr)}'),
                  const Divider(),
                  _kv('Profit (PKR)', 'PKR ${_money.format(_profit)}', bold: true),
                  _kv('Profit %', '${_profitPct.toStringAsFixed(1)}%', bold: true),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: TextField(
                controller: _warranty,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Warranties / Notes',
                  hintText: 'e.g. 7 days warranty, supplier replacement terms, etc.',
                ),
              ),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _kv(String a, String b, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500))),
          Text(b, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w700)),
        ],
      ),
    );
  }
}
