import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'review_cart_screen.dart';
import '../utils/globals.dart';
import '../theme.dart';            // for DobifyColors
import "package:dobify_store/colors.dart";           // for kPrimaryColor alias -> DobifyColors.yellow

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _cartItems = [];
  bool _isLoading = true;
  bool _isClearingCart = false;

  // per-item loading state
  final Map<String, bool> _itemLoadingStates = {};

  // animations
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initAnims();
    _loadCart();
  }

  void _initAnims() {
    _fadeController = AnimationController(duration: const Duration(milliseconds: 500), vsync: this);
    _slideController = AnimationController(duration: const Duration(milliseconds: 400), vsync: this);

    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut);
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _loadCart() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _cartItems = [];
        _isLoading = false;
      });
      cartCountNotifier.value = 0;
      return;
    }

    try {
      setState(() => _isLoading = true);

      final response = await supabase
          .from('cart')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: true);

      setState(() {
        _cartItems = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });

      await _updateGlobalCartCount();
    } catch (e) {
      setState(() {
        _cartItems = [];
        _isLoading = false;
      });
      _toast('Failed to load cart');
      await _updateGlobalCartCount();
    }
  }

  Future<void> _updateGlobalCartCount() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      cartCountNotifier.value = 0;
      return;
    }

    try {
      final response =
      await supabase.from('cart').select('product_quantity').eq('user_id', user.id);
      final items = List<Map<String, dynamic>>.from(response);
      final totalCount =
      items.fold<int>(0, (sum, row) => sum + (row['product_quantity'] as int? ?? 0));
      cartCountNotifier.value = totalCount;
    } catch (_) {
      cartCountNotifier.value = 0;
    }
  }

  double get totalCartValue =>
      _cartItems.fold(0.0, (sum, item) => sum + ((item['total_price'] ?? 0).toDouble()));

  Future<void> _clearCart() async {
    final confirmed = await _confirmClearDialog();
    if (!confirmed) return;

    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      setState(() => _isClearingCart = true);

      await supabase.from('cart').delete().eq('user_id', user.id);

      setState(() {
        _cartItems.clear();
        _isClearingCart = false;
      });

      await _updateGlobalCartCount();
      _toast('Cart cleared', success: true);
    } catch (e) {
      setState(() => _isClearingCart = false);
      _toast('Failed to clear cart');
    }
  }

  Future<bool> _confirmClearDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DobifyColors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: DobifyColors.yellow, width: 1.2),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: DobifyColors.yellow),
            SizedBox(width: 12),
            Text('Clear Cart?', style: TextStyle(color: DobifyColors.yellow)),
          ],
        ),
        content: const Text(
          'Are you sure you want to remove all items from your cart?',
          style: TextStyle(color: DobifyColors.yellow),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: DobifyColors.yellow)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: DobifyColors.yellow,
              foregroundColor: DobifyColors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Clear', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    ) ??
        false;
  }

  Future<void> _updateQuantity(Map<String, dynamic> item, int delta) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final itemId = item['id'].toString();
    final currentQ = item['product_quantity'] as int? ?? 0;
    final newQ = currentQ + delta;

    if (newQ <= 0) {
      await _removeItem(item);
      return;
    }

    try {
      setState(() => _itemLoadingStates[itemId] = true);

      final unitPrice =
          (item['product_price'] ?? 0).toDouble() + (item['service_price'] ?? 0).toDouble();
      final newTotal = unitPrice * newQ;

      await supabase
          .from('cart')
          .update({
        'product_quantity': newQ,
        'total_price': newTotal,
        'updated_at': DateTime.now().toIso8601String(),
      })
          .eq('id', item['id']);

      setState(() {
        final i = _cartItems.indexWhere((c) => c['id'] == item['id']);
        if (i != -1) {
          _cartItems[i]['product_quantity'] = newQ;
          _cartItems[i]['total_price'] = newTotal;
        }
        _itemLoadingStates.remove(itemId);
      });

      await _updateGlobalCartCount();
    } catch (e) {
      setState(() => _itemLoadingStates.remove(itemId));
      _toast('Failed to update quantity');
    }
  }

  Future<void> _removeItem(Map<String, dynamic> item) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      await supabase.from('cart').delete().eq('id', item['id']);
      setState(() => _cartItems.removeWhere((c) => c['id'] == item['id']));
      await _updateGlobalCartCount();
    } catch (_) {
      _toast('Failed to remove item');
    }
  }

  void _onProceed() {
    if (_isLoading) {
      _toast('Cart is still loading...');
      return;
    }
    if (_cartItems.isEmpty) {
      _toast('Your cart is empty!');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewCartScreen(
          cartItems: List<Map<String, dynamic>>.from(_cartItems),
          subtotal: totalCartValue,
        ),
      ),
    );
  }

  void _toast(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: DobifyColors.black,
        content: Row(
          children: [
            Icon(success ? Icons.check_circle : Icons.info_outline,
                color: DobifyColors.yellow, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(msg, style: const TextStyle(color: DobifyColors.yellow)),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: DobifyColors.yellow, width: 1.2),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DobifyColors.black,
      appBar: _appBar(),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: _isLoading
              ? _loading()
              : _cartItems.isEmpty
              ? _empty()
              : Column(
            children: [
              if (_cartItems.isNotEmpty) _swipeHint(),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _cartItems.length,
                  itemBuilder: (_, i) => _dismissible(_cartItems[i]),
                ),
              ),
              _bottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  AppBar _appBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: DobifyColors.black,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      iconTheme: const IconThemeData(color: DobifyColors.yellow),
      foregroundColor: DobifyColors.yellow,
      title: const Text(
        'My Cart',
        style: TextStyle(
          color: DobifyColors.yellow,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      actions: [
        if (_cartItems.isNotEmpty)
          IconButton(
            tooltip: 'Clear Cart',
            onPressed: _isClearingCart ? null : _clearCart,
            icon: _isClearingCart
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: DobifyColors.yellow,
                strokeWidth: 2,
              ),
            )
                : const Icon(Icons.delete_sweep, color: DobifyColors.yellow),
          ),
        const SizedBox(width: 6),
      ],
    );
  }

  Widget _loading() {
    return const Center(
      child: CircularProgressIndicator(color: DobifyColors.yellow),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.shopping_cart_outlined, size: 80, color: DobifyColors.yellow),
            SizedBox(height: 24),
            Text(
              'Your cart is empty!',
              style: TextStyle(
                color: DobifyColors.yellow,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Add some items to get started',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: DobifyColors.yellow,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _swipeHint() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DobifyColors.yellow, width: 1.2),
      ),
      child: const Row(
        children: [
          Icon(Icons.swipe, color: DobifyColors.yellow, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Swipe left on any item to remove it',
              style: TextStyle(color: DobifyColors.yellow, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dismissible(Map<String, dynamic> item) {
    return Dismissible(
      key: Key(item['id'].toString()),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: DobifyColors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: DobifyColors.yellow, width: 1.2),
            ),
            title: const Text('Remove Item?',
                style: TextStyle(color: DobifyColors.yellow)),
            content: Text(
              'Remove "${item['product_name']}" from your cart?',
              style: const TextStyle(color: DobifyColors.yellow),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel', style: TextStyle(color: DobifyColors.yellow)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: DobifyColors.yellow,
                  foregroundColor: DobifyColors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Remove', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ) ??
            false;
      },
      onDismissed: (_) => _removeItem(item),
      background: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: DobifyColors.yellow,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: DobifyColors.black, size: 26),
      ),
      child: _cartCard(item),
    );
  }

  Widget _cartCard(Map<String, dynamic> item) {
    final itemId = (item['id'] ?? '').toString();
    final isLoading = _itemLoadingStates[itemId] ?? false;
    final category = (item['category'] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: DobifyColors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DobifyColors.yellow, width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // image + category
            Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: DobifyColors.black,
                      border: Border.all(color: DobifyColors.yellow, width: 1.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Image.network(
                      item['product_image'] ?? '',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                      const Icon(Icons.image_outlined, color: DobifyColors.yellow),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                if (category.isNotEmpty)
                  Text(
                    category,
                    style: const TextStyle(
                      fontSize: 10,
                      color: DobifyColors.yellow,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),

            // details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['product_name'] ?? 'Unknown Product',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: DobifyColors.yellow,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if ((item['service_type'] ?? '').toString().trim().isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: DobifyColors.yellow,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${item['service_type']}',
                        style: const TextStyle(
                          color: DobifyColors.black,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // qty + price
            Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: DobifyColors.yellow,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _qtyBtn(icon: Icons.remove, onTap: () => _updateQuantity(item, -1), busy: isLoading),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: isLoading
                            ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: DobifyColors.black,
                            strokeWidth: 2,
                          ),
                        )
                            : Text(
                          '${item['product_quantity']}',
                          style: const TextStyle(
                            color: DobifyColors.black,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      _qtyBtn(icon: Icons.add, onTap: () => _updateQuantity(item, 1), busy: isLoading),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '₹${(item['total_price'] ?? 0).toString()}',
                  style: const TextStyle(
                    color: DobifyColors.yellow,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _qtyBtn({required IconData icon, required VoidCallback onTap, required bool busy}) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 16, color: DobifyColors.black),
      ),
    );
  }

  Widget _bottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: DobifyColors.black,
        border: Border(top: BorderSide(color: DobifyColors.yellow, width: 1.2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Total Amount',
                      style: TextStyle(color: DobifyColors.yellow, fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(
                    '₹${totalCartValue.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: DobifyColors.yellow, fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _onProceed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: DobifyColors.yellow,
                  foregroundColor: DobifyColors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Row(
                  children: [
                    Text('Proceed',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, size: 18),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
