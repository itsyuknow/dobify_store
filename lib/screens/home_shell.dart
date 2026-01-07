import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart';
import '../utils/globals.dart';
import '../screens/orders_screen.dart';
import 'order_history_page.dart';
import '../screens/cart_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required int initialIndex});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  String? _storeUserId;

  @override
  void initState() {
    super.initState();
    _loadStoreUserId();
  }

  Future<void> _loadStoreUserId() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      setState(() {
        _storeUserId = user.id;
      });
    }
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final viewPadding = MediaQuery.of(context).padding;
    final bottomBarHeight = 64.0;
    final safeBottom = viewPadding.bottom;
    final barTotalHeight = bottomBarHeight + max(0.0, safeBottom);

    // Wait until we have the store user ID
    if (_storeUserId == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: DobifyColors.yellow),
        ),
      );
    }

    final pages = [
      const OrdersScreen(),
      StoreOrderHistoryPage(storeUserId: _storeUserId!),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_index == 0 ? 'Orders' : 'Order History'),
        actions: [
          // ALWAYS show cart icon (site-like)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () async {
                if (!mounted) return;
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CartScreen()),
                );
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const SizedBox(width: 44, height: 44),
                  const Icon(Icons.shopping_cart_outlined, color: DobifyColors.yellow),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: ValueListenableBuilder<int>(
                      valueListenable: cartCountNotifier,
                      builder: (_, count, __) {
                        if (count <= 0) return const SizedBox.shrink();
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: DobifyColors.yellow,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            count > 99 ? '99+' : '$count',
                            style: const TextStyle(
                              color: DobifyColors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      extendBody: true,
      body: Padding(
        // keep content clear of the bottom bar
        padding: EdgeInsets.only(bottom: barTotalHeight + 8),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: pages[_index],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
        child: _BottomBar(
          height: bottomBarHeight,
          index: _index,
          onTap: (i) => setState(() => _index = i),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final double height;
  final int index;
  final ValueChanged<int> onTap;

  const _BottomBar({
    required this.height,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: DobifyColors.black,
        border: Border(
          top: BorderSide(color: DobifyColors.yellow, width: 1.2),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _NavButton(
            label: 'Orders',
            icon: Icons.list_alt_outlined,
            active: index == 0,
            onTap: () => onTap(0),
          ),
          const SizedBox(width: 12),
          _NavButton(
            label: 'History',
            icon: Icons.history,
            active: index == 1,
            onTap: () => onTap(1),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _NavButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: double.infinity,
        decoration: BoxDecoration(
          color: active ? DobifyColors.yellow : DobifyColors.black,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: DobifyColors.yellow,
            width: 1.2,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: active ? DobifyColors.black : DobifyColors.yellow,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: active ? DobifyColors.black : DobifyColors.yellow,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}