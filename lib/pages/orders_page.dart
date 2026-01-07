import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // v2: no type args on select()
      final List<dynamic> data = await _client
          .from('orders')
          .select() // no <Map<String, dynamic>>
          .order('created_at', ascending: false)
          .limit(50);

      // normalize to List<Map<String, dynamic>>
      final mapped = data
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      setState(() => _orders = mapped);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: DobifyColors.black,
            content: const Text(
              'Failed to load orders',
              style: TextStyle(color: DobifyColors.yellow),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _subscribe() {
    _channel = _client
        .channel('public:orders')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'orders',
      callback: (payload) => _load(),
    )
        .subscribe();
  }

  String _fmtMoney(dynamic amount) {
    final n = (amount is num) ? amount.toDouble() : double.tryParse('$amount') ?? 0.0;
    final f = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
    return f.format(n);
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '-';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '-';
    return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: DobifyColors.yellow),
      );
    }

    if (_orders.isEmpty) {
      return const Center(
        child: Text(
          'No orders found.',
          style: TextStyle(color: DobifyColors.yellow),
        ),
      );
    }

    return RefreshIndicator(
      color: DobifyColors.yellow,
      backgroundColor: DobifyColors.black,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final row = _orders[i];
          final id = row['id']?.toString() ?? '-';
          final status = (row['order_status'] ?? '-').toString();
          final total = _fmtMoney(row['total_amount']);
          final createdAt = _fmtDate(row['created_at']?.toString());

          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              title: const Text(
                'Order', // keep const; the styled variant below is not const
                style: TextStyle(fontWeight: FontWeight.w700, color: DobifyColors.yellow),
              ),
              // If you want "Order • $id" styled, make it non-const:
              // title: Text('Order • $id',
              //   style: const TextStyle(fontWeight: FontWeight.w700, color: DobifyColors.yellow),
              // ),

              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Text('Placed: $createdAt', style: DobifyTextStyles.subtle),
                  const SizedBox(height: 2),
                  Text('Status: $status', style: DobifyTextStyles.subtle),
                ],
              ),
              trailing: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ❌ remove const because style isn't const
                  Text('Total', style: DobifyTextStyles.subtle),
                  Text(
                    total,
                    style: const TextStyle(
                      color: DobifyColors.yellow,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class DobifyTextStyles {
  static TextStyle subtle =
  TextStyle(color: DobifyColors.yellow.withOpacity(0.85), fontSize: 13.5);
}
