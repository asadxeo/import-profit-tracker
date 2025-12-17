import 'dart:convert';
import 'package:flutter/material.dart';
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
      title: 'Import Profit Tracker',
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
    required this.landingCostPkr,
    required this.warrantiesNote,
    required this.status,
    required this.items,
    required this.costDeductedFromBalance,
    required this.saleAddedToBalance,
  });

  double get totalBuyRmb => items.fold(0.0, (s, x) => s + x.totalBuyRmb);
  double get totalBuyPkr => totalBuyRmb * rmbToPkrRate;
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
    if (mounted) setState(() {});
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
        content: const Text('This will remove it from your record.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );

    if (ok == true) {
      setState(() => data.shipments.removeWhere((x) => x.id == s.id));
      await _persist();
    }
  }

  @override
  Widget build(BuildContext context) {
    final shipments = data.shipments;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Profit Tracker'),
        actions: [
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
            _row('Buying (PKR)', 'PKR ${_money.format(s.totalBuyPkr)}'),
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
      _landing.text = e.landingCostPkr.toString();
      _warranty.text = e.warrantiesNote;
      landingDate = e.landingDate;
      status = e.status;
      items = e.items.map((x) => ProductLine(name: x.name, qty: x.qty, buyPriceRmb: x.buyPriceRmb, sellPricePkr: x.sellPricePkr)).toList();
    } else {
      _title.text = 'Shipment ${DateTime.now().millisecondsSinceEpoch % 10000}';
      _rate.text = '40.0';
      _shipping.text = '0';
      _landing.text = '0';
    }
  }

  Shipment _buildResult() {
    final id = widget.existing?.id ?? 'S-${DateTime.now().millisecondsSinceEpoch}';

    final r = double.tryParse(_rate.text.trim()) ?? 0;
    final ship = double.tryParse(_shipping.text.trim()) ?? 0;
    final land = double.tryParse(_landing.text.trim()) ?? 0;

    final existing = widget.existing;

    return Shipment(
      id: id,
      title: _title.text.trim().isEmpty ? 'Shipment' : _title.text.trim(),
      landingDate: landingDate,
      rmbToPkrRate: r,
      shippingCostPkr: ship,
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
  double get _landingVal => double.tryParse(_landing.text.trim()) ?? 0;

  double get _totalCostPkr => (_totalBuyRmb * _rateVal) + _shippingVal + _landingVal;
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
