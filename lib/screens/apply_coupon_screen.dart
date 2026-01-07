import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'colors.dart'; // Replace with your actual theme import

class ApplyCouponScreen extends StatefulWidget {
  final double subtotal;
  final List<Map<String, dynamic>> cartItems; // ✅ NEW
  final Function(String couponCode, double discount) onCouponApplied;

  const ApplyCouponScreen({
    super.key,
    required this.subtotal,
    required this.cartItems, // ✅ NEW
    required this.onCouponApplied,
  });

  @override
  State<ApplyCouponScreen> createState() => _ApplyCouponScreenState();
}

class _ApplyCouponScreenState extends State<ApplyCouponScreen>
    with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  final TextEditingController _couponController = TextEditingController();

  // ✅ NEW: Iron-only service IDs (UPDATE WITH YOUR ACTUAL SERVICE IDs)
  static const Set<String> _ironOnlyServiceIds = {
    'bdfd29d1-7af8-4578-a915-896e75d263a2', // Ironing (Steam)
    'e1962f17-318d-491e-9fc5-989510d97e63', // Ironing (Regular)
  };

  // ✅ NEW: Check if cart has wash services
  bool _hasWashServices() {
    for (final item in widget.cartItems) {
      final serviceId = item['service_id']?.toString() ?? '';
      if (serviceId.isNotEmpty && !_ironOnlyServiceIds.contains(serviceId)) {
        return true;
      }
    }
    return false;
  }

  // ✅ NEW: Check if cart has iron services
  bool _hasIronServices() {
    for (final item in widget.cartItems) {
      final serviceId = item['service_id']?.toString() ?? '';
      if (serviceId.isNotEmpty && _ironOnlyServiceIds.contains(serviceId)) {
        return true;
      }
    }
    return false;
  }

  List<Map<String, dynamic>> _coupons = [];
  List<Map<String, dynamic>> _topCoupons = [];
  bool _isLoading = true;
  bool _isApplying = false;

  // Animation controllers
  late AnimationController _slideController;
  late AnimationController _fadeController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _loadCoupons();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );

    _slideController.forward();
    _fadeController.forward();
  }

  Future<void> _loadCoupons() async {
    try {
      final response = await supabase
          .from('coupons')
          .select()
          .eq('is_active', true)
          .order('created_at', ascending: false);

      // ✅ NEW: Filter coupons based on cart services
      final allCoupons = List<Map<String, dynamic>>.from(response);
      final filteredCoupons = _filterCouponsByService(allCoupons);

      setState(() {
        _coupons = filteredCoupons;
        _topCoupons =
            _coupons.where((coupon) => coupon['is_featured'] == true).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading coupons: $e");
      setState(() => _isLoading = false);
    }
  }

  // ✅ NEW: Filter coupons based on service type
  List<Map<String, dynamic>> _filterCouponsByService(
      List<Map<String, dynamic>> coupons) {
    final hasWash = _hasWashServices();
    final hasIron = _hasIronServices();

    return coupons.where((coupon) {
      final appliesTo = coupon['applies_to_services']?.toString() ?? 'both';

      if (appliesTo == 'both') return true;
      if (appliesTo == 'wash' && hasWash) return true;
      if (appliesTo == 'iron' && hasIron && !hasWash) return true;

      return false;
    }).toList();
  }

  Future<void> _applyCoupon(String couponCode) async {
    if (couponCode.isEmpty) return;

    setState(() {
      _isApplying = true;
    });

    try {
      final couponResponse = await supabase
          .from('coupons')
          .select()
          .eq('code', couponCode.toUpperCase())
          .eq('is_active', true)
          .maybeSingle();

      if (couponResponse == null) {
        _showErrorSnackBar('Invalid coupon code');
        setState(() => _isApplying = false);
        return;
      }

      final coupon = couponResponse;

      // ✅ NEW: Check if coupon applies to current cart services
      if (!_isCouponApplicableToCart(coupon)) {
        final appliesTo = coupon['applies_to_services']?.toString() ?? 'both';
        if (appliesTo == 'iron') {
          _showErrorSnackBar('This coupon is only valid for ironing services');
        } else if (appliesTo == 'wash') {
          _showErrorSnackBar('This coupon is only valid for wash services');
        }
        setState(() => _isApplying = false);
        return;
      }

      // Validate other conditions
      final isValid = await _isCouponValid(coupon);
      if (!isValid) {
        setState(() => _isApplying = false);
        return;
      }

      final double discount = _calculateDiscount(coupon);

      widget.onCouponApplied(couponCode.toUpperCase(), discount);

      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint("Error applying coupon: $e");
      _showErrorSnackBar('Error applying coupon');
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  // ✅ NEW: Check if coupon is applicable to cart
  bool _isCouponApplicableToCart(Map<String, dynamic> coupon) {
    final appliesTo = coupon['applies_to_services']?.toString() ?? 'both';

    if (appliesTo == 'both') return true;

    final hasWash = _hasWashServices();
    final hasIron = _hasIronServices();

    if (appliesTo == 'wash' && hasWash) return true;
    if (appliesTo == 'iron' && hasIron && !hasWash) return true;

    return false;
  }

  // ✅ Now async to allow Supabase check for per-user limit
  Future<bool> _isCouponValid(Map<String, dynamic> coupon) async {
    final now = DateTime.now();

    // Expiry
    if (coupon['expiry_date'] != null) {
      final expiryDate = DateTime.parse(coupon['expiry_date'].toString());
      if (now.isAfter(expiryDate)) {
        _showErrorSnackBar('Coupon has expired');
        return false;
      }
    }

    // Minimum order
    if (coupon['minimum_order_value'] != null) {
      final minOrderValue = (coupon['minimum_order_value'] as num).toDouble();
      if (widget.subtotal < minOrderValue) {
        _showErrorSnackBar(
            'Minimum order value of ₹${minOrderValue.toStringAsFixed(0)} required');
        return false;
      }
    }

    // Global usage limit
    if (coupon['usage_limit'] != null && coupon['usage_count'] != null) {
      if ((coupon['usage_count'] as num) >= (coupon['usage_limit'] as num)) {
        _showErrorSnackBar('Coupon usage limit exceeded');
        return false;
      }
    }

    // ✅ Per-user usage limit
    final userId = supabase.auth.currentUser?.id;
    if (coupon['per_user_limit'] != null && userId != null) {
      // fetch all usages for this user+coupon and count them
      final usageResp = await supabase
          .from('coupon_usages')
          .select('id')
          .eq('user_id', userId)
          .eq('coupon_code', coupon['code']);

      final usageCount = (usageResp is List) ? usageResp.length : 0;
      if (usageCount >= (coupon['per_user_limit'] as int)) {
        _showErrorSnackBar('You have already used this coupon maximum times');
        return false;
      }
    }

    return true;
  }

  double _calculateDiscount(Map<String, dynamic> coupon) {
    double discount = 0.0;

    if (coupon['discount_type'] == 'percentage') {
      discount = (widget.subtotal * (coupon['discount_value'] as num)) / 100.0;

      if (coupon['max_discount_amount'] != null) {
        final maxDiscount = (coupon['max_discount_amount'] as num).toDouble();
        if (discount > maxDiscount) discount = maxDiscount;
      }
    } else if (coupon['discount_type'] == 'fixed') {
      discount = (coupon['discount_value'] as num).toDouble();
    }

    return discount;
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // Tag colors from DB tag
  List<Color> _getTagColorsFromDB(String tag) {
    switch (tag.toUpperCase()) {
      case 'NEW':
        return [Colors.green.shade600, Colors.green.shade500];
      case 'EXCLUSIVE':
        return [Colors.purple.shade600, Colors.purple.shade500];
      case 'LIMITED':
        return [Colors.red.shade600, Colors.red.shade500];
      case 'MEGA DEAL':
        return [Colors.orange.shade600, Colors.orange.shade500];
      case 'HOT':
        return [Colors.pink.shade600, Colors.pink.shade500];
      case 'POPULAR':
        return [Colors.blue.shade600, Colors.blue.shade500];
      case 'TRENDING':
        return [Colors.teal.shade600, Colors.teal.shade500];
      default:
        return [Colors.grey.shade600, Colors.grey.shade500];
    }
  }

  @override
  void dispose() {
    _couponController.dispose();
    _slideController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                kPrimaryColor,
                kPrimaryColor.withOpacity(0.8),
              ],
            ),
          ),
        ),
        automaticallyImplyLeading: true,
        title: const Text(
          "Apply Coupon",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: SafeArea(
            bottom: true, // ✅ prevents bottom cut-off
            // ✅ Disable glow but keep bounce everywhere (Android & iOS)
            child: NotificationListener<OverscrollIndicatorNotification>(
              onNotification: (overscroll) {
                overscroll.disallowIndicator();
                return true;
              },
              child: SingleChildScrollView(
                // ✅ BOUNCING + always scrollable so you can pull-to-bounce even with little content
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  24 + MediaQuery.of(context).padding.bottom, // ✅ extra bottom padding
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Coupon Code Input
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border:
                        Border.all(color: kPrimaryColor.withOpacity(0.2)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _couponController,
                              decoration: InputDecoration(
                                hintText: 'Enter coupon code',
                                hintStyle: TextStyle(
                                    color: Colors.grey.shade500, fontSize: 14),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                prefixIcon: Icon(Icons.local_offer_outlined,
                                    color: kPrimaryColor, size: 20),
                              ),
                              textCapitalization: TextCapitalization.characters,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: ElevatedButton(
                              onPressed: _isApplying
                                  ? null
                                  : () => _applyCoupon(_couponController.text),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kPrimaryColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                elevation: 2,
                              ),
                              child: _isApplying
                                  ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                  AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                                  : const Text(
                                'Apply',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_topCoupons.isNotEmpty) ...[
                      _buildSectionHeader('⭐ Featured Coupons',
                          Icons.star_rounded),
                      const SizedBox(height: 12),
                      ...(_topCoupons
                          .map((coupon) => _buildCompactCouponCard(coupon, true))),
                      const SizedBox(height: 20),
                    ],
                    if (_coupons
                        .where((c) => c['is_featured'] != true)
                        .isNotEmpty) ...[
                      _buildSectionHeader(
                          '🎟️ More Coupons', Icons.local_offer_rounded),
                      const SizedBox(height: 12),
                      ...(_coupons
                          .where((c) => c['is_featured'] != true)
                          .map((coupon) =>
                          _buildCompactCouponCard(coupon, false))),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Section Header
  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                kPrimaryColor.withOpacity(0.1),
                kPrimaryColor.withOpacity(0.05)
              ],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: kPrimaryColor, size: 18),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  // Compact coupon card (tap to show details)
  Widget _buildCompactCouponCard(Map<String, dynamic> coupon, bool isFeatured) {
    final isEligible = _isCouponEligible(coupon);

    // Dynamic colors based on discount type
    Color accentColor;
    if (coupon['discount_type'] == 'percentage') {
      accentColor = Colors.purple.shade600;
    } else {
      accentColor = Colors.green.shade600;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showCouponDetailsDialog(coupon), // ✅ details popup
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
            isEligible ? accentColor.withOpacity(0.3) : Colors.grey.shade200,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // icon chip
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          accentColor.withOpacity(0.1),
                          accentColor.withOpacity(0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.local_offer_rounded,
                      color: accentColor,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                (coupon['code'] ?? '').toString(),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isEligible
                                      ? accentColor
                                      : Colors.grey.shade700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (coupon['tag'] != null &&
                                coupon['tag'].toString().isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: _getTagColorsFromDB(
                                        coupon['tag'].toString()),
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  coupon['tag'].toString().toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // ✅ clearer description (2 lines, darker)
                        Text(
                          (coupon['description'] ?? '').toString(),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black87,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (coupon['minimum_order_value'] != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Min order: ₹${((coupon['minimum_order_value'] as num).toDouble()).toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Apply button
                  SizedBox(
                    height: 32,
                    child: ElevatedButton(
                      onPressed: isEligible && !_isApplying
                          ? () => _applyCoupon((coupon['code'] ?? '').toString())
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                        isEligible ? accentColor : Colors.grey.shade300,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        elevation: isEligible ? 2 : 0,
                      ),
                      child: Text(
                        'Apply',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color:
                          isEligible ? Colors.white : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // brand strip
            if (coupon['brand_logo'] != null)
              Container(
                height: 20,
                padding: const EdgeInsets.only(bottom: 8, right: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Image.network(
                      coupon['brand_logo'].toString(),
                      height: 12,
                      width: 40,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox(),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _isCouponEligible(Map<String, dynamic> coupon) {
    // ✅ NEW: Check service applicability
    if (!_isCouponApplicableToCart(coupon)) return false;

    // minimum order
    if (coupon['minimum_order_value'] != null) {
      final minOrderValue = (coupon['minimum_order_value'] as num).toDouble();
      if (widget.subtotal < minOrderValue) return false;
    }

    // expiry
    if (coupon['expiry_date'] != null) {
      final expiryDate = DateTime.parse(coupon['expiry_date'].toString());
      if (DateTime.now().isAfter(expiryDate)) return false;
    }

    // usage limit
    if (coupon['usage_limit'] != null && coupon['usage_count'] != null) {
      if ((coupon['usage_count'] as num) >= (coupon['usage_limit'] as num)) {
        return false;
      }
    }

    return true;
  }

  // ===== Details Dialog (NO per-user rows) =====
  Future<void> _showCouponDetailsDialog(Map<String, dynamic> coupon) async {
    final String code = (coupon['code'] ?? '').toString();
    final String description = (coupon['description'] ?? '').toString();
    final String type = (coupon['discount_type'] ?? '').toString();
    final double value = (coupon['discount_value'] as num?)?.toDouble() ?? 0;

    final double? maxDiscount = coupon['max_discount_amount'] != null
        ? (coupon['max_discount_amount'] as num).toDouble()
        : null;

    final double? minOrder = coupon['minimum_order_value'] != null
        ? (coupon['minimum_order_value'] as num).toDouble()
        : null;

    final String? expiry = coupon['expiry_date'] != null
        ? DateTime.tryParse(coupon['expiry_date'].toString())
        ?.toLocal()
        .toString()
        .split('.')
        .first
        : null;

    final String? tag = coupon['tag']?.toString();
    final String appliesTo =
        coupon['applies_to_services']?.toString() ?? 'both'; // ✅ NEW

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white, Colors.blue.shade50],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: kPrimaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.local_offer_rounded,
                          color: kPrimaryColor, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        code,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (tag != null && tag.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: kPrimaryColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          tag.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: kPrimaryColor,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                if (description.isNotEmpty)
                  Text(
                    description,
                    style: const TextStyle(
                        fontSize: 13.5, color: Colors.black87, height: 1.35),
                  ),

                const SizedBox(height: 12),

                _detailRow('Type', type == 'percentage' ? 'Percentage' : 'Flat'),
                _detailRow(
                  'Value',
                  type == 'percentage'
                      ? '${value.toStringAsFixed(0)} %'
                      : '₹${value.toStringAsFixed(0)}',
                ),
                if (maxDiscount != null)
                  _detailRow(
                      'Max Discount', '₹${maxDiscount.toStringAsFixed(0)}'),
                if (minOrder != null)
                  _detailRow(
                      'Minimum Order', '₹${minOrder.toStringAsFixed(0)}'),
                _detailRow(
                  // ✅ NEW
                  'Applies To',
                  appliesTo == 'iron'
                      ? 'Iron Services Only'
                      : appliesTo == 'wash'
                      ? 'Wash Services Only'
                      : 'All Services',
                ),
                if (expiry != null) _detailRow('Valid Till', expiry),

                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}