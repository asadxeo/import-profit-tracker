import 'package:flutter/material.dart';

void main() {
  runApp(const ImportProfitApp());
}

class ImportProfitApp extends StatelessWidget {
  const ImportProfitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Import Profit Tracker',
      theme: ThemeData(primarySwatch: Colors.green),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController capitalCtrl = TextEditingController();
  final TextEditingController itemsCtrl = TextEditingController();
  final TextEditingController buyPriceCtrl = TextEditingController();
  final TextEditingController shipCostCtrl = TextEditingController();
  final TextEditingController rateCtrl = TextEditingController();
  final TextEditingController sellCtrl = TextEditingController();

  double profit = 0;
  double closing = 0;

  void calculate() {
    final capital = double.tryParse(capitalCtrl.text) ?? 0;
    final items = double.tryParse(itemsCtrl.text) ?? 0;
    final buy = double.tryParse(buyPriceCtrl.text) ?? 0;
    final ship = double.tryParse(shipCostCtrl.text) ?? 0;
    final rate = double.tryParse(rateCtrl.text) ?? 0;
    final sell = double.tryParse(sellCtrl.text) ?? 0;

    final buyingRmb = items * buy;
    final buyingPkr = buyingRmb * rate;
    final totalCost = buyingPkr + ship;
    profit = sell - totalCost;
    closing = capital + profit;

    setState(() {});
  }

  Widget field(String label, TextEditingController c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import Shipment Profit')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            field('Initial Capital (PKR)', capitalCtrl),
            field('Total Items', itemsCtrl),
            field('Buying Price per Item (RMB)', buyPriceCtrl),
            field('Shipping Cost (PKR)', shipCostCtrl),
            field('RMB to PKR Rate', rateCtrl),
            field('Total Selling Amount (PKR)', sellCtrl),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: calculate,
              child: const Text('Calculate Profit'),
            ),
            const SizedBox(height: 20),
            Text('Profit: PKR ${profit.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 18)),
            Text('Closing Balance: PKR ${closing.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 18)),
          ],
        ),
      ),
    );
  }
}
