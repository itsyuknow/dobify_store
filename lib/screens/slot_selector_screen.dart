import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'colors.dart';
import 'address_book_screen.dart';
import 'order_success_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// Conditional import - uses web helper on web, stub on mobile
import '/helpers/razorpay_web_helper_stub.dart'
if (dart.library.js) 'package:your_store_app/helpers/razorpay_web_helper.dart';
import 'dart:async'; // For TimeoutException

class SlotSelectorScreen extends StatefulWidget {
  final double totalAmount;
  final List<Map<String, dynamic>> cartItems;
  final String? appliedCouponCode;
  final double discount;
  final bool addMinimumCartFee;
  final bool addPlatformFee;

  const SlotSelectorScreen({
    super.key,
    required this.totalAmount,
    required this.cartItems,
    this.appliedCouponCode,
    this.discount = 0.0,
    this.addMinimumCartFee = false,
    this.addPlatformFee = false,
  });

  @override
  State<SlotSelectorScreen> createState() => _SlotSelectorScreenState();
}

class _SlotSelectorScreenState extends State<SlotSelectorScreen> with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;

// NEW: User-controlled delivery settings
  bool _deliveryFeeEnabled = false;
  String _selectedDeliveryType = 'Standard'; // Standard or Express
  double _customDeliveryFee = 0.0; // Custom delivery fee amount

// Computed getters
  bool get isExpressDelivery => _selectedDeliveryType == 'Express';
  bool get isStandardDelivery => _selectedDeliveryType == 'Standard';


  // Iron-only service IDs
  static const Set<String> _ironOnlyServiceIds = {
    'bdfd29d1-7af8-4578-a915-896e75d263a2', // Ironing (Steam)
    'e1962f17-318d-491e-9fc5-989510d97e63', // Ironing (Regular)
  };

  Map<String, dynamic>? selectedAddress;
  bool isServiceAvailable = true;
  bool isLoadingServiceAvailability = false;
  bool onlinePaymentEnabled = true;

  Map<String, dynamic>? selectedPickupSlot;
  Map<String, dynamic>? selectedDeliverySlot;

  List<Map<String, dynamic>> pickupSlots = [];
  List<Map<String, dynamic>> deliverySlots = [];
  bool isLoadingSlots = true;

  bool _hasWashServices() {
    for (final item in widget.cartItems) {
      final serviceId = item['service_id']?.toString() ?? '';
      if (serviceId.isNotEmpty && !_ironOnlyServiceIds.contains(serviceId)) {
        return true;
      }
    }
    return false;
  }

  // Billing settings
  double minimumCartFee = 100.0;
  double platformFee = 0.0;
  double serviceTaxPercent = 0.0;
  double expressDeliveryFee = 0.0;
  double standardDeliveryFee = 0.0;
  bool isLoadingBillingSettings = true;
  bool _isBillingSummaryExpanded = false;
  double deliveryGstPercent = 0.0;
  double freeStandardThreshold = 300.0;

  Map<String, Map<String, String>> _billingNotes = {};

  // Animation controllers
  late AnimationController _billingAnimationController;
  late Animation<double> _billingExpandAnimation;

  int currentStep = 0; // 0: pickup date/slot, 1: delivery date/slot

  DateTime selectedPickupDate = DateTime.now();
  DateTime selectedDeliveryDate = DateTime.now();
  final ScrollController _pickupDateScrollController = ScrollController();
  final ScrollController _deliveryDateScrollController = ScrollController();
  final ScrollController _mainScrollController = ScrollController();
  final GlobalKey _deliverySlotSectionKey = GlobalKey();
  final GlobalKey _paymentSectionKey = GlobalKey();
  late List<DateTime> pickupDates;
  late List<DateTime> deliveryDates;

  // Payment related variables
  String _selectedPaymentMethod = 'online';
  bool _isProcessingPayment = false;
  late Razorpay _razorpay;

  String _formatPhone(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final p = raw.trim();
    if (p.startsWith('+')) return p;
    if (RegExp(r'^\d{10}$').hasMatch(p)) return '+91 $p';
    return p;
  }

  String _formatCompleteAddress(Map<String, dynamic> address) {
    final parts = <String>[];

    if ((address['address_line_1'] ?? '').toString().trim().isNotEmpty) {
      parts.add(address['address_line_1'].toString().trim());
    }

    if ((address['address_line_2'] ?? '').toString().trim().isNotEmpty) {
      parts.add(address['address_line_2'].toString().trim());
    }

    if ((address['landmark'] ?? '').toString().trim().isNotEmpty) {
      parts.add('Near ${address['landmark'].toString().trim()}');
    }

    final cityStatePincode = '${address['city']}, ${address['state']} - ${address['pincode']}';
    parts.add(cityStatePincode);

    return parts.join(', ');
  }

  @override
  void initState() {
    super.initState();
    _initializeDates();
    _loadBillingSettings();
    _loadSlots();
    _loadDefaultAddress();
    _initializeRazorpay();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _billingAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _billingExpandAnimation = CurvedAnimation(
      parent: _billingAnimationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _pickupDateScrollController.dispose();
    _deliveryDateScrollController.dispose();
    _billingAnimationController.dispose();
    _mainScrollController.dispose();
    _razorpay.clear();
    super.dispose();
  }

  void _initializeRazorpay() {
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    print('✅ Payment Success: ${response.paymentId}');
    _processOrderCompletion(paymentId: response.paymentId);
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    print('❌ Payment Error: ${response.code} - ${response.message}');
    setState(() {
      _isProcessingPayment = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Payment failed: ${response.message}'),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    print('🔄 External Wallet: ${response.walletName}');
  }

  void _initializeDates() {
    pickupDates = List.generate(7, (index) => DateTime.now().add(Duration(days: index)));

    // Initialize delivery dates based on service type
    final bool hasWash = _hasWashServices();
    final int minDeliveryHours = isExpressDelivery ? 36 : (hasWash ? 48 : 0);

    if (hasWash) {
      // For wash services, start delivery dates from minimum required hours
      deliveryDates = List.generate(7, (index) {
        return DateTime.now().add(Duration(hours: minDeliveryHours + (index * 24)));
      });
    } else {
      // For iron-only, use same-day delivery possibility
      deliveryDates = List.generate(7, (index) => selectedPickupDate.add(Duration(days: index)));
    }
  }

  void _updateDeliveryDates() {
    final bool hasWash = _hasWashServices();

    if (hasWash) {
      // For wash services: 48 hours Standard, 36 hours Express
      final int minHours = isExpressDelivery ? 36 : 48;
      final DateTime minDeliveryDate = selectedPickupDate.add(Duration(hours: minHours));

      deliveryDates = List.generate(7, (index) {
        return DateTime(
          minDeliveryDate.year,
          minDeliveryDate.month,
          minDeliveryDate.day,
        ).add(Duration(days: index));
      });

      selectedDeliveryDate = DateTime(
        minDeliveryDate.year,
        minDeliveryDate.month,
        minDeliveryDate.day,
      );
    } else {
      // For iron-only services
      if (isExpressDelivery) {
        // Express: Same day delivery possible (6 hours gap)
        deliveryDates = List.generate(7, (index) => selectedPickupDate.add(Duration(days: index)));

        if (selectedDeliveryDate.isBefore(selectedPickupDate)) {
          selectedDeliveryDate = selectedPickupDate;
        }
      } else {
        // Standard: Minimum 24 hours (next day)
        final DateTime minDeliveryDate = selectedPickupDate.add(Duration(hours: 24));
        deliveryDates = List.generate(7, (index) {
          return DateTime(
            minDeliveryDate.year,
            minDeliveryDate.month,
            minDeliveryDate.day,
          ).add(Duration(days: index));
        });

        selectedDeliveryDate = DateTime(
          minDeliveryDate.year,
          minDeliveryDate.month,
          minDeliveryDate.day,
        );
      }
    }
  }

  bool _hasAvailableDeliverySlots(DateTime date) {
    int dayOfWeek = date.weekday;

    List<Map<String, dynamic>> daySlots = deliverySlots.where((slot) {
      int slotDayOfWeek = slot['day_of_week'] ?? 0;
      bool dayMatches = slotDayOfWeek == dayOfWeek ||
          (dayOfWeek == 7 && slotDayOfWeek == 0) ||
          (slotDayOfWeek == 7 && dayOfWeek == 0);

      bool typeMatches = isExpressDelivery
          ? (slot['slot_type'] == 'express' || slot['slot_type'] == 'both')
          : (slot['slot_type'] == 'standard' || slot['slot_type'] == 'both');

      return dayMatches && typeMatches;
    }).toList();

    if (daySlots.isEmpty) return false;

    for (var slot in daySlots) {
      DateTime tempDeliveryDate = selectedDeliveryDate;
      setState(() {
        selectedDeliveryDate = date;
      });

      bool isAvailable = _isDeliverySlotAvailable(slot);

      setState(() {
        selectedDeliveryDate = tempDeliveryDate;
      });

      if (isAvailable) return true;
    }

    return false;
  }

  DateTime? _findNextAvailableDeliveryDate() {
    for (int i = 0; i < deliveryDates.length; i++) {
      DateTime date = deliveryDates[i];
      if (_hasAvailableDeliverySlots(date)) {
        return date;
      }
    }
    return null;
  }

  List<DateTime> _getAvailableDeliveryDates() {
    return deliveryDates.where((date) => _hasAvailableDeliverySlots(date)).toList();
  }

  Future<void> _loadBillingSettings() async {
    try {
      // Get the most recent billing setting (assuming we have multiple settings with timestamps)
      final response = await supabase
          .from('billing_settings')
          .select()
          .order('created_at', ascending: false)
          .limit(1)
          .single();

      final List<dynamic> notesResp = await supabase
          .from('billing_notes')
          .select()
          .or(
          'key.eq.minimum_cart_fee,'
              'key.eq.platform_fee,'
              'key.eq.service_tax,'
              'key.eq.delivery_standard,'
              'key.eq.delivery_standard_free,'
              'key.eq.delivery_express,'
              'key.eq.delivery_gst'
      );

      final Map<String, Map<String, String>> notesMap = {
        for (final row in notesResp)
          (row['key'] as String): {
            'title': row['title']?.toString() ?? '',
            'content': row['content']?.toString() ?? '',
          }
      };

      final dynamic _minCartRaw =
          response['minimum_cart_value'] ?? response['minimum_cart_fee'] ?? 100;

      final bool onlineEnabled = (response['online_payment_enabled'] ?? true) as bool;

      setState(() {
        minimumCartFee        = (_minCartRaw is num)
            ? _minCartRaw.toDouble()
            : double.tryParse(_minCartRaw.toString()) ?? 100.0;

        platformFee           = (response['platform_fee'] ?? 0).toDouble();
        serviceTaxPercent     = (response['service_tax_percent'] ?? 0).toDouble();
        expressDeliveryFee    = (response['express_delivery_fee'] ?? 0).toDouble();
        standardDeliveryFee   = (response['standard_delivery_fee'] ?? 0).toDouble();
        deliveryGstPercent    = (response['delivery_gst_percent'] ?? 0).toDouble();
        freeStandardThreshold = (response['free_standard_threshold'] ?? 300).toDouble();

        // Initialize custom delivery fee from database
        _customDeliveryFee    = standardDeliveryFee;

        onlinePaymentEnabled  = onlineEnabled;
        if (!onlinePaymentEnabled && _selectedPaymentMethod == 'online') {
          _selectedPaymentMethod = 'cod';
        }

        _billingNotes = notesMap;
        isLoadingBillingSettings = false;
      });
    } catch (e) {
      print('❌ Error loading billing settings: $e');

      // Fallback to default values if query fails
      setState(() {
        minimumCartFee        = 100.0;
        platformFee           = 0.0;
        serviceTaxPercent     = 0.0;
        expressDeliveryFee    = 0.0;
        standardDeliveryFee   = 0.0;
        deliveryGstPercent    = 0.0;
        freeStandardThreshold = 300.0;
        _customDeliveryFee    = standardDeliveryFee;
        _billingNotes         = {};
        isLoadingBillingSettings = false;

        // Show error message to user
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not load billing settings. Using default values.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
      });
    }
  }

  Future<void> _loadSlots() async {
    try {
      final pickupResponse = await supabase
          .from('pickup_slots')
          .select()
          .eq('is_active', true)
          .order('start_time', ascending: true);

      final deliveryResponse = await supabase
          .from('delivery_slots')
          .select()
          .eq('is_active', true)
          .order('start_time', ascending: true);

      setState(() {
        pickupSlots = List<Map<String, dynamic>>.from(pickupResponse);
        deliverySlots = List<Map<String, dynamic>>.from(deliveryResponse);
        isLoadingSlots = false;
      });
    } catch (e) {
      setState(() => isLoadingSlots = false);
    }
  }

  Future<void> _loadDefaultAddress() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final response = await supabase
          .from('user_addresses')
          .select()
          .eq('user_id', userId)
          .eq('is_default', true)
          .maybeSingle();
      if (response != null) {
        setState(() {
          selectedAddress = response;
        });
        _checkServiceAvailability(response['pincode']);
      }
    } catch (e) {}
  }

  Future<void> _checkServiceAvailability(String pincode) async {
    setState(() => isLoadingServiceAvailability = true);
    try {
      final response = await supabase
          .from('service_areas')
          .select()
          .eq('pincode', pincode)
          .eq('is_active', true)
          .maybeSingle();
      setState(() {
        isServiceAvailable = response != null;
        isLoadingServiceAvailability = false;
      });
    } catch (e) {
      setState(() {
        isServiceAvailable = false;
        isLoadingServiceAvailability = false;
      });
    }
  }

  String _money(double v) => '₹${v.toStringAsFixed(2)}';

  Widget _popoverBubble({
    required BuildContext context,
    required String title,
    String? description,
    required List<Widget> rows,
    Widget? footer,
  }) {
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        Positioned(
          bottom: 4,
          right: 20,
          child: Transform.rotate(
            angle: 45 * 3.14159 / 180,
            child: Container(width: 14, height: 14, color: const Color(0xFF1F1F1F)),
          ),
        ),
        Container(
          margin: const EdgeInsets.only(bottom: 10, right: 8),
          width: MediaQuery.of(context).size.width * 0.86,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1F1F1F),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 12))],
          ),
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white, fontSize: 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                if (description != null && description.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(description, style: TextStyle(color: Colors.white.withOpacity(0.85), height: 1.25)),
                ],
                const SizedBox(height: 10),
                ...rows,
                if (footer != null) ...[
                  const SizedBox(height: 10),
                  const Divider(color: Colors.white24, height: 20, thickness: 1),
                  footer,
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _rowLr(String l, String r, {bool bold = false, bool muted = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              l,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: muted ? Colors.white70 : Colors.white,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            r,
            style: TextStyle(
              color: muted ? Colors.white70 : Colors.white,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  void _showPopover(Widget child) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 130),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (_, a, __, ___) => Opacity(opacity: a.value, child: Center(child: child)),
    );
  }

  void _showInfoDialog(String title, String content) {
    _showPopover(
      _popoverBubble(
        context: context,
        title: title,
        description: content,
        rows: const [],
      ),
    );
  }

  void _showMinimumCartFeePopover(Map<String, double> billing) {
    final note = _billingNotes['minimum_cart_fee'];
    final base  = billing['minimumCartFee'] ?? 0;
    final gst   = billing['taxOnMinCart'] ?? 0;
    final total = base + gst;

    _showPopover(
      _popoverBubble(
        context: context,
        title: 'Minimum Cart Fee Breakdown',
        description: note?['content'],
        rows: [
          _rowLr('Fee before tax', _money(base), muted: true),
          _rowLr('GST @ ${serviceTaxPercent.toStringAsFixed(0)}%', _money(gst), muted: true),
        ],
        footer: _rowLr('Total (applied)', _money(total), bold: true),
      ),
    );
  }

  void _showPlatformFeePopover(Map<String, double> billing) {
    final note = _billingNotes['platform_fee'];
    final base  = billing['platformFee'] ?? 0;
    final gst   = billing['taxOnPlatform'] ?? 0;
    final total = base + gst;

    _showPopover(
      _popoverBubble(
        context: context,
        title: 'Platform Fee Breakdown',
        description: note?['content'],
        rows: [
          _rowLr('Fee before tax', _money(base), muted: true),
          _rowLr('GST @ ${serviceTaxPercent.toStringAsFixed(0)}%', _money(gst), muted: true),
        ],
        footer: _rowLr('Total (applied)', _money(total), bold: true),
      ),
    );
  }

  void _showServiceTaxesPopover(Map<String, double> billing) {
    final note = _billingNotes['service_tax'];
    final ds        = billing['discountedSubtotal'] ?? 0;
    final tItems    = billing['taxOnItems'] ?? 0;
    final tMinCart  = billing['taxOnMinCart'] ?? 0;
    final tPlatform = billing['taxOnPlatform'] ?? 0;
    final tDelivery = billing['taxOnDelivery'] ?? 0;
    final total     = billing['serviceTax'] ?? 0;

    _showPopover(
      _popoverBubble(
        context: context,
        title: 'Tax & Charges',
        description: note?['content'],
        rows: [
          _rowLr('Items tax @ ${serviceTaxPercent.toStringAsFixed(0)}% (on ₹${ds.toStringAsFixed(2)})', _money(tItems), muted: true),
          _rowLr('GST on Minimum Cart Fee @ ${serviceTaxPercent.toStringAsFixed(0)}%', _money(tMinCart), muted: true),
          _rowLr('GST on Platform Fee @ ${serviceTaxPercent.toStringAsFixed(0)}%', _money(tPlatform), muted: true),
          _rowLr('GST on Delivery @ ${deliveryGstPercent.toStringAsFixed(0)}%', _money(tDelivery), muted: true),
        ],
        footer: _rowLr('Total Taxes & Charges', _money(total), bold: true),
      ),
    );
  }

  void _showDeliveryFeePopover(Map<String, double> billing) {
    final bool isStandard = isStandardDelivery;
    final infoKey = isStandard ? 'delivery_standard' : 'delivery_express';
    final note = _billingNotes[infoKey] ?? _billingNotes['delivery_standard_free'];

    final fee      = billing['deliveryFee'] ?? 0;
    final gst      = billing['taxOnDelivery'] ?? 0;
    final total    = fee + gst;
    final ds       = billing['discountedSubtotal'] ?? 0;
    final qualifiesFreeStandard = isStandard && (ds >= freeStandardThreshold);

    final rows = <Widget>[
      if (isStandard && qualifiesFreeStandard)
        _rowLr('Standard Delivery — Free (≥ ₹${freeStandardThreshold.toStringAsFixed(0)})', _money(0), muted: true)
      else
        _rowLr('${isStandard ? 'Standard' : 'Express'} fee (before tax)', _money(fee), muted: true),
      _rowLr('GST @ ${deliveryGstPercent.toStringAsFixed(0)}%', _money(gst), muted: true),
    ];

    _showPopover(
      _popoverBubble(
        context: context,
        title: 'Delivery Partner Fee Breakup',
        description: note?['content'],
        rows: rows,
        footer: _rowLr('Total (applied)', _money(total), bold: true),
      ),
    );
  }

  Map<String, double> _calculateBilling() {
    final double itemSubtotal = widget.cartItems.fold(0.0, (sum, item) {
      return sum + (item['total_price']?.toDouble() ?? 0.0);
    });

    final double discountApplied = widget.discount.clamp(0.0, itemSubtotal);
    final double discountedSubtotal = itemSubtotal - discountApplied;

    // Only apply minimum cart fee if user enabled it in review cart
    final double minCartBase =
    discountedSubtotal < minimumCartFee ? (minimumCartFee - discountedSubtotal) : 0.0;
    final double minCartFeeApplied = widget.addMinimumCartFee ? minCartBase : 0.0;

    final bool qualifiesFreeStandard = isStandardDelivery && (discountedSubtotal >= freeStandardThreshold);


    final double expressCharges = _deliveryFeeEnabled
        ? 0.0  // No express charges when delivery fee toggle is ON
        : (isExpressDelivery ? _customDeliveryFee : 0.0);  // Use custom amount from popup when OFF

    final double deliveryFee = _deliveryFeeEnabled
        ? (isStandardDelivery
        ? (qualifiesFreeStandard ? 0.0 : _customDeliveryFee)  // ✅ CHANGED: Use custom amount
        : _customDeliveryFee)  // ✅ CHANGED: Use custom amount for express too
        : 0.0;  // No delivery fee when toggle is OFF

    final double taxOnItems     = (discountedSubtotal * serviceTaxPercent) / 100.0;
    final double taxOnMinCart   = (minCartFeeApplied * serviceTaxPercent) / 100.0;

    // Only apply platform fee if user enabled it in review cart
    final double platformFeeApplied = widget.addPlatformFee ? platformFee : 0.0;
    final double taxOnPlatform  = (platformFeeApplied * serviceTaxPercent) / 100.0;

    // Tax on both express charges and delivery fee
    final double taxOnExpress = expressCharges > 0 ? (expressCharges * deliveryGstPercent) / 100.0 : 0.0;
    final double taxOnDelivery = deliveryFee > 0 ? (deliveryFee * deliveryGstPercent) / 100.0 : 0.0;

    final double serviceTax = taxOnItems + taxOnMinCart + taxOnPlatform + taxOnExpress + taxOnDelivery;

    double totalAmount = discountedSubtotal + minCartFeeApplied + platformFeeApplied + expressCharges + deliveryFee + serviceTax;
    if (totalAmount < 0) totalAmount = 0;

    return {
      'subtotal'           : itemSubtotal,
      'discount'           : discountApplied,
      'discountedSubtotal' : discountedSubtotal,
      'minimumCartFee'     : minCartFeeApplied,
      'platformFee'        : platformFeeApplied,
      'expressCharges'     : expressCharges,
      'deliveryFee'        : deliveryFee,
      'taxOnItems'         : taxOnItems,
      'taxOnMinCart'       : taxOnMinCart,
      'taxOnPlatform'      : taxOnPlatform,
      'taxOnExpress'       : taxOnExpress,
      'taxOnDelivery'      : taxOnDelivery,
      'serviceTax'         : serviceTax,
      'totalAmount'        : totalAmount,
    };
  }

  double _calculateTotalAmount() {
    final billing = _calculateBilling();
    return billing['totalAmount']!;
  }

  Future<void> _saveBillingDetails(String orderId) async {
    try {
      // ✅ Get user_id from the order we just created
      final orderResponse = await supabase
          .from('orders')
          .select('user_id')
          .eq('id', orderId)
          .single();

      final userId = orderResponse['user_id'] as String;

      final billing = _calculateBilling();

      // ✅ FIXED: Calculate the actual delivery fee that was applied
      final double actualDeliveryFee = isExpressDelivery
          ? billing['expressCharges']!
          : billing['deliveryFee']!;

      await supabase.from('order_billing_details').insert({
        'order_id': orderId,
        'user_id': userId,
        'subtotal': billing['subtotal'],
        'minimum_cart_fee': billing['minimumCartFee'],
        'platform_fee': billing['platformFee'],
        'service_tax': billing['serviceTax'],

        // ✅ FIXED: Single delivery_fee field - no redundancy
        'delivery_fee': actualDeliveryFee,

        'discount_amount': billing['discount'],
        'total_amount': billing['totalAmount'],

        // ✅ delivery_type already tells us which type was used
        'delivery_type': isExpressDelivery ? 'express' : 'standard',

        'applied_coupon_code': widget.appliedCouponCode,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error saving billing details: $e');
    }
  }

  void _onAddressSelected(Map<String, dynamic> address) {
    setState(() {
      selectedAddress = address;
    });
    _checkServiceAvailability(address['pincode']);
  }

  void _onPickupDateSelected(DateTime date) {
    setState(() {
      selectedPickupDate = date;
      selectedPickupSlot = null;
      selectedDeliverySlot = null;
      _updateDeliveryDates();
    });
  }

  void _onDeliveryDateSelected(DateTime date) {
    setState(() {
      selectedDeliveryDate = date;
      selectedDeliverySlot = null;
    });
  }

  void _onPickupSlotSelected(Map<String, dynamic> slot) {
    setState(() {
      selectedPickupSlot = slot;
      selectedDeliverySlot = null;
      currentStep = 1;
      _updateDeliveryDates();

      DateTime? nextAvailableDate = _findNextAvailableDeliveryDate();
      if (nextAvailableDate != null) {
        selectedDeliveryDate = nextAvailableDate;
      } else {
        selectedDeliveryDate = selectedPickupDate;
      }
    });

    _autoScrollToDeliverySection();
  }

  void _onDeliverySlotSelected(Map<String, dynamic> slot) {
    setState(() {
      selectedDeliverySlot = slot;
    });

    _autoScrollToPaymentSection();
  }

  void _autoScrollToDeliverySection() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_deliverySlotSectionKey.currentContext != null && _mainScrollController.hasClients) {
        final RenderBox renderBox = _deliverySlotSectionKey.currentContext!.findRenderObject() as RenderBox;
        final position = renderBox.localToGlobal(Offset.zero);
        final screenHeight = MediaQuery.of(context).size.height;

        double scrollOffset = _mainScrollController.offset + position.dy - (screenHeight * 0.2);

        _mainScrollController.animateTo(
          scrollOffset.clamp(0.0, _mainScrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _autoScrollToPaymentSection() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_mainScrollController.hasClients) {
        _mainScrollController.animateTo(
          _mainScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _openAddressBook() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddressBookScreen(
          onAddressSelected: _onAddressSelected,
        ),
      ),
    );
  }

  TimeOfDay _parseTimeString(String timeString) {
    try {
      List<String> parts = timeString.split(':');
      int hour = int.parse(parts[0]);
      int minute = parts.length > 1 ? int.parse(parts[1]) : 0;
      return TimeOfDay(hour: hour, minute: minute);
    } catch (e) {
      return TimeOfDay(hour: 0, minute: 0);
    }
  }

  Map<String, dynamic>? _getCurrentTimeSlot(List<Map<String, dynamic>> slots) {
    final currentTime = TimeOfDay.now();

    for (var slot in slots) {
      final startTime = _parseTimeString(slot['start_time']);
      final endTime = _parseTimeString(slot['end_time']);

      if (_isTimeInRange(currentTime, startTime, endTime)) {
        return slot;
      }
    }
    return null;
  }

  bool _isTimeInRange(TimeOfDay current, TimeOfDay start, TimeOfDay end) {
    int currentMinutes = current.hour * 60 + current.minute;
    int startMinutes = start.hour * 60 + start.minute;
    int endMinutes = end.hour * 60 + end.minute;

    return currentMinutes >= startMinutes && currentMinutes < endMinutes;
  }

  List<Map<String, dynamic>> _getAllPickupSlots() {
    final now = DateTime.now();
    final isToday = selectedPickupDate.day == now.day &&
        selectedPickupDate.month == now.month &&
        selectedPickupDate.year == now.year;

    int selectedDayOfWeek = selectedPickupDate.weekday;

    List<Map<String, dynamic>> daySlots = pickupSlots.where((slot) {
      int slotDayOfWeek = slot['day_of_week'] ?? 0;
      bool dayMatches = slotDayOfWeek == selectedDayOfWeek ||
          (selectedDayOfWeek == 7 && slotDayOfWeek == 0) ||
          (slotDayOfWeek == 7 && selectedDayOfWeek == 0);

      bool typeMatches = isExpressDelivery
          ? (slot['slot_type'] == 'express' || slot['slot_type'] == 'both')
          : (slot['slot_type'] == 'standard' || slot['slot_type'] == 'both');

      return dayMatches && typeMatches;
    }).toList();

    daySlots.sort((a, b) {
      TimeOfDay timeA = _parseTimeString(a['start_time']);
      TimeOfDay timeB = _parseTimeString(b['start_time']);
      if (timeA.hour != timeB.hour) return timeA.hour.compareTo(timeB.hour);
      return timeA.minute.compareTo(timeB.minute);
    });

    return daySlots;
  }

  List<Map<String, dynamic>> _getFilteredPickupSlots() {
    List<Map<String, dynamic>> allSlots = _getAllPickupSlots();

    final now = DateTime.now();
    final isToday = selectedPickupDate.day == now.day &&
        selectedPickupDate.month == now.month &&
        selectedPickupDate.year == now.year;

    if (!isToday) {
      return allSlots;
    }

    final currentTime = TimeOfDay.now();
    int currentMinutes = currentTime.hour * 60 + currentTime.minute;

    // 🔍 DEBUG PRINT
    print('🕐 Current time: ${currentTime.hour}:${currentTime.minute} = $currentMinutes minutes');

    return allSlots.where((slot) {
      final slotEnd = _parseTimeString(slot['end_time']);
      int slotEndMinutes = slotEnd.hour * 60 + slotEnd.minute;

      // 🔍 DEBUG PRINT
      print('📦 Slot: ${slot['start_time']} - ${slot['end_time']} | End: $slotEndMinutes | Available: ${currentMinutes < slotEndMinutes}');

      return currentMinutes < slotEndMinutes;
    }).toList();
  }





  bool _isPickupSlotAvailable(Map<String, dynamic> slot) {
    final now = DateTime.now();
    final isToday = selectedPickupDate.day == now.day &&
        selectedPickupDate.month == now.month &&
        selectedPickupDate.year == now.year;

    if (!isToday) return true;

    final currentTime = TimeOfDay.now();
    final slotEnd = _parseTimeString(slot['end_time']);

    int currentMinutes = currentTime.hour * 60 + currentTime.minute;
    int slotEndMinutes = slotEnd.hour * 60 + slotEnd.minute;

    // Slot is available if current time hasn't passed the END time
    return currentMinutes < slotEndMinutes;
  }

  List<Map<String, dynamic>> _getAllDeliverySlots() {
    if (selectedPickupSlot == null) return [];

    final deliveryDate = selectedDeliveryDate;
    int deliveryDayOfWeek = deliveryDate.weekday;

    List<Map<String, dynamic>> daySlots = deliverySlots.where((slot) {
      int slotDayOfWeek = slot['day_of_week'] ?? 0;
      bool dayMatches = slotDayOfWeek == deliveryDayOfWeek ||
          (deliveryDayOfWeek == 7 && slotDayOfWeek == 0) ||
          (slotDayOfWeek == 7 && deliveryDayOfWeek == 0);

      bool typeMatches = isExpressDelivery
          ? (slot['slot_type'] == 'express' || slot['slot_type'] == 'both')
          : (slot['slot_type'] == 'standard' || slot['slot_type'] == 'both');

      return dayMatches && typeMatches;
    }).toList();

    daySlots.sort((a, b) {
      TimeOfDay timeA = _parseTimeString(a['start_time']);
      TimeOfDay timeB = _parseTimeString(b['start_time']);
      if (timeA.hour != timeB.hour) return timeA.hour.compareTo(timeB.hour);
      return timeA.minute.compareTo(timeB.minute);
    });

    return daySlots;
  }

  List<Map<String, dynamic>> _getFilteredDeliverySlots() {
    List<Map<String, dynamic>> allSlots = _getAllDeliverySlots();

    if (selectedPickupSlot == null) return [];

    final pickupDate = selectedPickupDate;
    final deliveryDate = selectedDeliveryDate;
    final bool hasWash = _hasWashServices();

    // Get current time for today's filtering
    final now = DateTime.now();
    final isDeliveryToday = deliveryDate.day == now.day &&
        deliveryDate.month == now.month &&
        deliveryDate.year == now.year;

    final pickupSlotStart = _parseTimeString(selectedPickupSlot!['start_time']);
    final pickupDateTime = DateTime(
      pickupDate.year,
      pickupDate.month,
      pickupDate.day,
      pickupSlotStart.hour,
      pickupSlotStart.minute,
    );

    // For wash services, use time-based filtering (48/36 hours)
    if (hasWash) {
      final int minHours = isExpressDelivery ? 36 : 48;
      final minDeliveryDateTime = pickupDateTime.add(Duration(hours: minHours));

      return allSlots.where((slot) {
        final slotStart = _parseTimeString(slot['start_time']);
        final slotDateTime = DateTime(
          deliveryDate.year,
          deliveryDate.month,
          deliveryDate.day,
          slotStart.hour,
          slotStart.minute,
        );

        // Filter out slots that have already passed today
        if (isDeliveryToday) {
          final currentTime = TimeOfDay.now();
          int currentMinutes = currentTime.hour * 60 + currentTime.minute;
          int slotEndMinutes = _parseTimeString(slot['end_time']).hour * 60 + _parseTimeString(slot['end_time']).minute;

          // Skip if slot has already ended
          if (currentMinutes >= slotEndMinutes) return false;
        }

        return slotDateTime.isAfter(minDeliveryDateTime) ||
            slotDateTime.isAtSameMomentAs(minDeliveryDateTime);
      }).toList();
    }

    // For iron-only services
    if (isExpressDelivery) {
      // Express iron: 6 hours minimum gap
      final minDeliveryDateTime = pickupDateTime.add(Duration(hours: 6));

      return allSlots.where((slot) {
        final slotStart = _parseTimeString(slot['start_time']);
        final slotDateTime = DateTime(
          deliveryDate.year,
          deliveryDate.month,
          deliveryDate.day,
          slotStart.hour,
          slotStart.minute,
        );

        // Filter out slots that have already passed today
        if (isDeliveryToday) {
          final currentTime = TimeOfDay.now();
          int currentMinutes = currentTime.hour * 60 + currentTime.minute;
          int slotEndMinutes = _parseTimeString(slot['end_time']).hour * 60 + _parseTimeString(slot['end_time']).minute;

          // Skip if slot has already ended
          if (currentMinutes >= slotEndMinutes) return false;
        }

        // ✅ CRITICAL: Slot must start AT LEAST 6 hours after pickup start time
        return slotDateTime.isAfter(minDeliveryDateTime) ||
            slotDateTime.isAtSameMomentAs(minDeliveryDateTime);
      }).toList();
    } else {
      // Standard iron: 24 hours minimum gap
      final minDeliveryDateTime = pickupDateTime.add(Duration(hours: 24));

      return allSlots.where((slot) {
        final slotStart = _parseTimeString(slot['start_time']);
        final slotDateTime = DateTime(
          deliveryDate.year,
          deliveryDate.month,
          deliveryDate.day,
          slotStart.hour,
          slotStart.minute,
        );

        // Filter out slots that have already passed today
        if (isDeliveryToday) {
          final currentTime = TimeOfDay.now();
          int currentMinutes = currentTime.hour * 60 + currentTime.minute;
          int slotEndMinutes = _parseTimeString(slot['end_time']).hour * 60 + _parseTimeString(slot['end_time']).minute;

          // Skip if slot has already ended
          if (currentMinutes >= slotEndMinutes) return false;
        }

        // ✅ CRITICAL: Slot must start AT LEAST 24 hours after pickup start time
        return slotDateTime.isAfter(minDeliveryDateTime) ||
            slotDateTime.isAtSameMomentAs(minDeliveryDateTime);
      }).toList();
    }
  }



  bool _isDeliverySlotAvailable(Map<String, dynamic> slot) {
    if (selectedPickupSlot == null) return false;

    final pickupDate = selectedPickupDate;
    final deliveryDate = selectedDeliveryDate;
    final bool hasWash = _hasWashServices();

    final now = DateTime.now();
    final isDeliveryToday = deliveryDate.day == now.day &&
        deliveryDate.month == now.month &&
        deliveryDate.year == now.year;

    // Always check if slot time has passed today
    if (isDeliveryToday) {
      final currentTime = TimeOfDay.now();
      final slotTime = _parseTimeString(slot['start_time']);

      if (slotTime.hour < currentTime.hour) return false;
      if (slotTime.hour == currentTime.hour && slotTime.minute < currentTime.minute) return false;
    }

    final pickupSlotStart = _parseTimeString(selectedPickupSlot!['start_time']);
    final pickupDateTime = DateTime(
      pickupDate.year,
      pickupDate.month,
      pickupDate.day,
      pickupSlotStart.hour,
      pickupSlotStart.minute,
    );

    final slotStart = _parseTimeString(slot['start_time']);
    final slotDateTime = DateTime(
      deliveryDate.year,
      deliveryDate.month,
      deliveryDate.day,
      slotStart.hour,
      slotStart.minute,
    );

    // For wash services: 48 hours Standard, 36 hours Express
    if (hasWash) {
      final int minHours = isExpressDelivery ? 36 : 48;
      final minDeliveryDateTime = pickupDateTime.add(Duration(hours: minHours));

      return slotDateTime.isAfter(minDeliveryDateTime) ||
          slotDateTime.isAtSameMomentAs(minDeliveryDateTime);
    }

    // For iron-only services
    if (isExpressDelivery) {
      // Express iron: 6 hours minimum
      final minDeliveryDateTime = pickupDateTime.add(Duration(hours: 6));
      return slotDateTime.isAfter(minDeliveryDateTime) ||
          slotDateTime.isAtSameMomentAs(minDeliveryDateTime);
    } else {
      // Standard iron: 24 hours minimum
      final minDeliveryDateTime = pickupDateTime.add(Duration(hours: 24));
      return slotDateTime.isAfter(minDeliveryDateTime) ||
          slotDateTime.isAtSameMomentAs(minDeliveryDateTime);
    }
  }

  bool _isSlotPassed(Map<String, dynamic> slot, DateTime selectedDate) {
    final now = DateTime.now();
    if (selectedDate.day != now.day ||
        selectedDate.month != now.month ||
        selectedDate.year != now.year) {
      return false;
    }
    try {
      final currentTime = TimeOfDay.now();
      String timeString = slot['start_time'];
      TimeOfDay slotTime = _parseTimeString(timeString);
      if (slotTime.hour < currentTime.hour) return true;
      if (slotTime.hour == currentTime.hour && slotTime.minute < currentTime.minute) return true;
      return false;
    } catch (e) {
      return false;
    }
  }

  void _goBackToPickup() {
    setState(() {
      currentStep = 0;
      selectedPickupSlot = null;
      selectedDeliverySlot = null;
    });
  }

  void _handleProceed() {
    if (selectedAddress == null ||
        selectedPickupSlot == null ||
        selectedDeliverySlot == null ||
        !isServiceAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete all selections and ensure service is available.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!onlinePaymentEnabled && _selectedPaymentMethod == 'online') {
      setState(() => _selectedPaymentMethod = 'cod');
    }

    if (_selectedPaymentMethod == 'online') {
      _initiateOnlinePayment();
    } else {
      _processOrderCompletion();
    }
  }

  Future<void> _initiateOnlinePayment() async {
    setState(() {
      _isProcessingPayment = true;
    });

    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('User not found');

      final totalAmount = _calculateTotalAmount();
      int payablePaise = (totalAmount * 100).round();
      if (payablePaise < 100) payablePaise = 100;

      final res = await supabase.functions.invoke(
        'create_razorpay_order',
        body: {'amount': payablePaise},
      );

      if (res.data == null) throw Exception('Null response from Edge Function');
      if (res.data['error'] != null) throw Exception('Server error: ${res.data['error']}');
      if (res.data['id'] == null) throw Exception('No order ID returned');

      final orderId = res.data['id'];
      const razorpayKeyId = 'rzp_live_RP0aiJW4EQDXKd';

      if (kIsWeb) {
        print('🌐 Setting up web payment callbacks');

        setupWebCallbacks(
          onSuccess: (paymentId) {
            print('✅ Web Payment Success: $paymentId');
            if (mounted) {
              setState(() => _isProcessingPayment = true);
            }
            _processOrderCompletion(paymentId: paymentId);
          },
          onDismiss: () {
            print('❌ Payment dismissed by user');
            if (mounted) {
              setState(() => _isProcessingPayment = false);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Payment cancelled'),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 3),
                ),
              );
            }
          },
          onError: (error) {
            print('❌ Payment error: $error');
            if (mounted) {
              setState(() => _isProcessingPayment = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Payment failed: $error'),
                  backgroundColor: Colors.red,
                  duration: Duration(seconds: 4),
                ),
              );
            }
          },
        );

        final options = {
          'key': razorpayKeyId,
          'amount': payablePaise,
          'currency': 'INR',
          'order_id': orderId,
          'name': 'Your Store Name',
          'description': 'Store Order Payment',
          'image': 'https://your-store.com/logo.png',
          'prefill': {
            'contact': user.phone ?? '',
            'email': user.email ?? '',
          },
          'theme': {
            'color': '#${kPrimaryColor.value.toRadixString(16).substring(2)}',
          },
        };

        print('🚀 Opening Razorpay Web with order: $orderId');
        openRazorpayWeb(options);

      } else {
        final options = {
          'key': razorpayKeyId,
          'amount': payablePaise,
          'currency': 'INR',
          'order_id': orderId,
          'name': 'Your Store Name',
          'description': 'Store Order Payment',
          'image': 'https://your-store.com/logo.png',
          'prefill': {
            'contact': user.phone ?? '',
            'email': user.email ?? '',
          },
          'retry': {'enabled': true, 'max_count': 1},
          'timeout': 180,
          'theme': {
            'color': '#${kPrimaryColor.value.toRadixString(16).substring(2)}',
          },
        };

        _razorpay.open(options);
      }

    } catch (e, stackTrace) {
      setState(() => _isProcessingPayment = false);
      debugPrint('❌ Payment initialization error: $e');
      debugPrint('Stack trace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment failed: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<String> _getOrCreateUser() async {
    if (selectedAddress == null) {
      throw Exception('Address not selected');
    }

    String phoneNumber = selectedAddress!['phone_number']?.toString().trim() ?? '';
    if (phoneNumber.isEmpty) {
      throw Exception('Phone number not found in address');
    }

    // Normalize phone format - remove ALL prefixes and spaces
    String phoneWithoutPrefix = phoneNumber
        .replaceAll('+91', '')
        .replaceAll('+', '')
        .replaceAll('91', '')  // ✅ ADDED: Also remove '91' prefix if present
        .replaceAll(' ', '')
        .replaceAll('-', '')
        .trim();

    // ✅ Now rebuild with consistent format
    String phoneClean = phoneWithoutPrefix;  // Just the 10 digits
    String phoneWith91Prefix = '91$phoneWithoutPrefix';
    String phoneWithPlusPrefix = '+91$phoneWithoutPrefix';

    print('🔍 Searching for user with phone: $phoneWithoutPrefix');
    print('   Variations: $phoneClean | $phoneWith91Prefix | $phoneWithPlusPrefix');

    try {
      // ✅ STEP 1: Check if user profile exists
      final existingProfile = await supabase
          .from('user_profiles')
          .select('user_id')
          .or('phone_number.eq.$phoneClean,phone_number.eq.$phoneWith91Prefix,phone_number.eq.$phoneWithPlusPrefix')
          .limit(1)
          .maybeSingle()
          .timeout(Duration(seconds: 5));

      if (existingProfile != null) {
        final existingUserId = existingProfile['user_id'] as String;
        print('✅ Found existing user profile: $existingUserId');
        return existingUserId;
      }

      // ✅ STEP 2: No profile found - use Edge Function to handle everything
      print('📝 No profile found. Using Edge Function to get/create user...');

      final recipientName = selectedAddress!['recipient_name']?.toString().trim() ?? 'Guest User';
      final nameParts = recipientName.split(' ');
      final firstName = nameParts.first;
      final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

      // ✅ Try with different phone formats
      List<String> phoneFormatsToTry = [
        phoneClean,           // 7008760211
        phoneWith91Prefix,    // 917008760211
        phoneWithPlusPrefix,  // +917008760211
      ];

      dynamic lastError;

      for (String phoneFormat in phoneFormatsToTry) {
        try {
          print('🔄 Trying Edge Function with phone: $phoneFormat');

          final response = await supabase.functions.invoke(
            'get-or-create-user-profile',
            body: {
              'phone_number': phoneFormat,
              'first_name': firstName,
              'last_name': lastName,
            },
          ).timeout(Duration(seconds: 15));

          if (response.data != null && response.data['user_id'] != null) {
            final userId = response.data['user_id'] as String;
            print('✅ Got user_id from Edge Function: $userId');
            return userId;
          }
        } catch (e) {
          print('⚠️ Failed with $phoneFormat: $e');
          lastError = e;
          // Continue to next format
        }
      }

      // ✅ If Edge Function failed with all formats, throw the last error
      throw lastError ?? Exception('Edge Function did not return user_id');

    } on TimeoutException catch (e) {
      print('❌ Timeout error: $e');
      throw Exception('Connection timed out. Please check your internet.');
    } catch (e) {
      print('❌ Error in _getOrCreateUser: $e');

      // ✅ FALLBACK: If everything fails, try one more profile check
      // (maybe another process created it)
      try {
        final retryProfile = await supabase
            .from('user_profiles')
            .select('user_id')
            .or('phone_number.eq.$phoneClean,phone_number.eq.$phoneWith91Prefix,phone_number.eq.$phoneWithPlusPrefix')
            .limit(1)
            .maybeSingle()
            .timeout(Duration(seconds: 3));

        if (retryProfile != null) {
          final userId = retryProfile['user_id'] as String;
          print('✅ Found user in retry: $userId');
          return userId;
        }
      } catch (retryError) {
        print('⚠️ Retry also failed: $retryError');
      }

      throw Exception('Unable to process order. Please try again.');
    }
  }


  Future<void> _processOrderCompletion({String? paymentId}) async {
    // ✅ DEBUG: Check who is logged in
    final currentUser = supabase.auth.currentUser;
    print('==========================================');
    print('🔐 CURRENTLY LOGGED IN USER:');
    print('   ID: ${currentUser?.id}');
    print('   Email: ${currentUser?.email}');
    print('   Phone: ${currentUser?.phone}');
    print('==========================================');

    // ✅ Show loading immediately
    setState(() {
      _isProcessingPayment = true;
    });

    // Force UI update before heavy operations
    await Future.delayed(Duration(milliseconds: 50));

    try {
      // ✅ STEP 1: Get or create user (with overall timeout)
      String userId = await _getOrCreateUser().timeout(
        Duration(seconds: 20),
        onTimeout: () => throw TimeoutException('User verification timed out'),
      );

      // ✅ Get the currently logged-in store user ID
      final storeUser = supabase.auth.currentUser;
      final storeUserId = storeUser?.id;

      if (storeUserId == null) {
        throw Exception('Store user not logged in');
      }

      print('🔍 Store User ID (logged in): $storeUserId');
      print('🔍 Customer User ID (order): $userId');

      final totalAmount = _calculateTotalAmount();
      final orderId = 'ORD${DateTime.now().millisecondsSinceEpoch}';

      // ✅ STEP 2: Create order
      await supabase.from('orders').insert({
        'id': orderId,
        'user_id': userId,
        'store_user_id': storeUserId,
        'total_amount': totalAmount,
        'payment_method': _selectedPaymentMethod,
        'payment_status': _selectedPaymentMethod == 'online' ? 'paid' : 'pending',
        'payment_id': paymentId,
        'order_status': 'confirmed',
        'status': 'confirmed',
        'pickup_date': selectedPickupDate.toIso8601String().split('T')[0],
        'pickup_slot_id': selectedPickupSlot!['id'],
        'delivery_date': selectedDeliveryDate.toIso8601String().split('T')[0],
        'delivery_slot_id': selectedDeliverySlot!['id'],
        'delivery_type': isExpressDelivery ? 'express' : 'standard',
        'delivery_address': _formatCompleteAddress(selectedAddress!),
        'address_details': selectedAddress,
        'applied_coupon_code': widget.appliedCouponCode,
        'discount_amount': widget.discount,
        'pickup_slot_display_time': selectedPickupSlot!['display_time'],
        'pickup_slot_start_time': selectedPickupSlot!['start_time'],
        'pickup_slot_end_time': selectedPickupSlot!['end_time'],
        'delivery_slot_display_time': selectedDeliverySlot!['display_time'],
        'delivery_slot_start_time': selectedDeliverySlot!['start_time'],
        'delivery_slot_end_time': selectedDeliverySlot!['end_time'],
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).timeout(
        Duration(seconds: 8),
        onTimeout: () => throw TimeoutException('Order creation timed out'),
      );

      print('✅ Order created: $orderId by store user: $storeUserId');

      // ✅ STEP 3: Insert order items
      for (final item in widget.cartItems) {
        await supabase.from('order_items').insert({
          'order_id': orderId,
          'product_name': item['product_name'],
          'product_image': item['product_image'],
          'product_price': item['product_price'],
          'service_type': item['service_type'],
          'service_price': item['service_price'],
          'quantity': item['product_quantity'],
          'total_price': item['total_price'],
        }).timeout(
          Duration(seconds: 5),
          onTimeout: () => throw TimeoutException('Order items insertion timed out'),
        );
      }

      print('✅ Order items inserted');

      // ✅ STEP 4: Save billing details
      await _saveBillingDetails(orderId).timeout(
        Duration(seconds: 5),
        onTimeout: () {
          print('⚠️ Billing details save timed out, continuing anyway');
          return null;
        },
      );

      print('✅ Billing details saved');

      // ✅ STEP 5: Clear cart for store user (EXACTLY LIKE DOBIFY)
      try {
        print('🧹 Clearing cart for store user: $storeUserId');

        await supabase
            .from('cart')  // ✅ CHANGED: Now using 'cart' table
            .delete()
            .eq('user_id', storeUserId)  // Store user who added items
            .timeout(
          Duration(seconds: 5),
          onTimeout: () {
            print('⚠️ Cart clearing timed out');
            return null;
          },
        );

        print('✅ Cart cleared successfully for store user: $storeUserId');
      } catch (e) {
        print('⚠️ Could not clear cart: $e');
        // Don't block order completion
      }

      // ✅ Navigate to success screen
      if (mounted) {
        _navigateToSuccessScreen(orderId, paymentId);
      }

    } on TimeoutException catch (e) {
      print('❌ Timeout error: $e');

      if (mounted) {
        setState(() {
          _isProcessingPayment = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection timed out. Please check your internet and try again.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      print('❌ Error processing order: $e');

      if (mounted) {
        setState(() {
          _isProcessingPayment = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to process order: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }





  void _navigateToSuccessScreen(String orderId, String? paymentId) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => OrderSuccessScreen(
          orderId: orderId,
          totalAmount: _calculateTotalAmount(),
          cartItems: widget.cartItems,
          paymentMethod: _selectedPaymentMethod,
          paymentId: paymentId,
          appliedCouponCode: widget.appliedCouponCode,
          discount: widget.discount,
          selectedAddress: selectedAddress!,
          pickupDate: selectedPickupDate,
          pickupSlot: selectedPickupSlot!,
          deliveryDate: selectedDeliveryDate,
          deliverySlot: selectedDeliverySlot!,
          isExpressDelivery: isExpressDelivery,
        ),
      ),
    );
  }

  void _autoScrollToSection(double offset, {int delay = 300}) {
    Future.delayed(Duration(milliseconds: delay), () {
      if (_mainScrollController.hasClients) {
        _mainScrollController.animateTo(
          offset,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _showDeliveryFeeSelector() {
    final baseAmount = isStandardDelivery ? standardDeliveryFee : expressDeliveryFee;
    final TextEditingController _feeController = TextEditingController(
      text: _customDeliveryFee.toStringAsFixed(0),
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: 24,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Handle bar
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      SizedBox(height: 20),

                      // Title
                      Row(
                        children: [
                          Icon(Icons.local_shipping, color: kPrimaryColor, size: 24),
                          SizedBox(width: 12),
                          Text(
                            'Set Delivery Fee',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),

                      Text(
                        'Base ${isStandardDelivery ? 'Standard' : 'Express'} Fee: ₹${baseAmount.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                        ),
                      ),

                      SizedBox(height: 24),

                      // Amount display with controls
                      Container(
                        padding: EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: kPrimaryColor.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: kPrimaryColor.withOpacity(0.2)),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Delivery Fee Amount',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.black54,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: 12),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Decrease button
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 8,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: IconButton(
                                    icon: Icon(Icons.remove, color: kPrimaryColor),
                                    onPressed: _customDeliveryFee > 10
                                        ? () {
                                      setModalState(() {
                                        _customDeliveryFee = (_customDeliveryFee - 10).clamp(0, 1000);
                                        _feeController.text = _customDeliveryFee.toStringAsFixed(0);
                                      });
                                      setState(() {});
                                    }
                                        : null,
                                    iconSize: 24,
                                  ),
                                ),

                                SizedBox(width: 20),

                                // Manual input field
                                Container(
                                  width: 140,
                                  child: TextField(
                                    controller: _feeController,
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: kPrimaryColor,
                                    ),
                                    decoration: InputDecoration(
                                      prefixText: '₹',
                                      prefixStyle: TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                        color: kPrimaryColor,
                                      ),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: kPrimaryColor, width: 2),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: kPrimaryColor, width: 2),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: kPrimaryColor, width: 2.5),
                                      ),
                                    ),
                                    onChanged: (value) {
                                      final amount = double.tryParse(value) ?? 0;
                                      setModalState(() {
                                        _customDeliveryFee = amount.clamp(0, 1000);
                                      });
                                      setState(() {});
                                    },
                                  ),
                                ),

                                SizedBox(width: 20),

                                // Increase button
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 8,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: IconButton(
                                    icon: Icon(Icons.add, color: kPrimaryColor),
                                    onPressed: _customDeliveryFee < 1000
                                        ? () {
                                      setModalState(() {
                                        _customDeliveryFee = (_customDeliveryFee + 10).clamp(0, 1000);
                                        _feeController.text = _customDeliveryFee.toStringAsFixed(0);
                                      });
                                      setState(() {});
                                    }
                                        : null,
                                    iconSize: 24,
                                  ),
                                ),
                              ],
                            ),

                            SizedBox(height: 16),

                            // Quick amount buttons
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                _quickAmountButton(baseAmount, setModalState, _feeController),
                                _quickAmountButton(50, setModalState, _feeController),
                                _quickAmountButton(100, setModalState, _feeController),
                                _quickAmountButton(150, setModalState, _feeController),
                              ],
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: 24),

                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  _customDeliveryFee = baseAmount;
                                });
                                Navigator.pop(context);
                              },
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.symmetric(vertical: 14),
                                side: BorderSide(color: Colors.grey.shade300),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'Reset',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: () {
                                // Update from text field before closing
                                final finalAmount = double.tryParse(_feeController.text) ?? _customDeliveryFee;
                                setState(() {
                                  _customDeliveryFee = finalAmount.clamp(0, 1000);
                                });
                                Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kPrimaryColor,
                                padding: EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 2,
                              ),
                              child: Text(
                                'Apply',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showExpressChargeSelector({required Function(double) onAmountSet}) {
    final baseAmount = expressDeliveryFee;
    final TextEditingController _expressController = TextEditingController(
      text: _customDeliveryFee.toStringAsFixed(0), // Use current custom fee, not base
    );
    double tempAmount = _customDeliveryFee; // Use current custom fee, not base

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: false, // Force user to set amount
      enableDrag: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return WillPopScope(
              onWillPop: () async => false, // Prevent back button dismiss
              child: SafeArea(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  padding: EdgeInsets.only(
                    left: 24,
                    right: 24,
                    top: 24,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Handle bar
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        SizedBox(height: 20),

                        // Title with icon
                        Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.bolt, color: Colors.orange, size: 24),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Express Delivery Charges',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'Set the express delivery charge',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),

                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, size: 16, color: Colors.orange.shade700),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Base Express Fee: ₹${baseAmount.toStringAsFixed(0)} • You can enter any amount (including ₹0)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: 24),

                        // Amount display with controls
                        Container(
                          padding: EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.orange.withOpacity(0.3), width: 2),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'Express Charge Amount',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(height: 12),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Decrease button
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.1),
                                          blurRadius: 8,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: IconButton(
                                      icon: Icon(Icons.remove, color: Colors.orange),
                                      onPressed: tempAmount > 0
                                          ? () {
                                        setModalState(() {
                                          tempAmount = (tempAmount - 10).clamp(0, 1000);
                                          _expressController.text = tempAmount.toStringAsFixed(0);
                                        });
                                      }
                                          : null,
                                      iconSize: 24,
                                    ),
                                  ),

                                  SizedBox(width: 20),

                                  // Manual input field
                                  Container(
                                    width: 140,
                                    child: TextField(
                                      controller: _expressController,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange,
                                      ),
                                      decoration: InputDecoration(
                                        prefixText: '₹',
                                        prefixStyle: TextStyle(
                                          fontSize: 32,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange,
                                        ),
                                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Colors.orange, width: 2),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Colors.orange, width: 2),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Colors.orange, width: 2.5),
                                        ),
                                      ),
                                      onChanged: (value) {
                                        final amount = double.tryParse(value) ?? 0;
                                        setModalState(() {
                                          tempAmount = amount.clamp(0, 1000);
                                        });
                                      },
                                    ),
                                  ),

                                  SizedBox(width: 20),

                                  // Increase button
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.1),
                                          blurRadius: 8,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: IconButton(
                                      icon: Icon(Icons.add, color: Colors.orange),
                                      onPressed: tempAmount < 1000
                                          ? () {
                                        setModalState(() {
                                          tempAmount = (tempAmount + 10).clamp(0, 1000);
                                          _expressController.text = tempAmount.toStringAsFixed(0);
                                        });
                                      }
                                          : null,
                                      iconSize: 24,
                                    ),
                                  ),
                                ],
                              ),

                              SizedBox(height: 16),

                              // Quick amount buttons
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.center,
                                children: [
                                  _quickExpressAmountButton(0, tempAmount, setModalState, _expressController),
                                  _quickExpressAmountButton(baseAmount, tempAmount, setModalState, _expressController),
                                  _quickExpressAmountButton(50, tempAmount, setModalState, _expressController),
                                  _quickExpressAmountButton(100, tempAmount, setModalState, _expressController),
                                  _quickExpressAmountButton(150, tempAmount, setModalState, _expressController),
                                ],
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: 24),

                        // Action buttons
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  // Reset to Standard delivery
                                  setState(() {
                                    _selectedDeliveryType = 'Standard';
                                  });
                                  Navigator.pop(context);
                                },
                                style: OutlinedButton.styleFrom(
                                  padding: EdgeInsets.symmetric(vertical: 14),
                                  side: BorderSide(color: Colors.grey.shade300),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  'Cancel',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black54,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed: () {
                                  final finalAmount = double.tryParse(_expressController.text) ?? tempAmount;
                                  onAmountSet(finalAmount.clamp(0, 1000));
                                  Navigator.pop(context);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  padding: EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 2,
                                ),
                                child: Text(
                                  'Set Express Charge',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _quickExpressAmountButton(
      double amount,
      double currentAmount,
      StateSetter setModalState,
      TextEditingController controller
      ) {
    final isSelected = currentAmount == amount;
    return InkWell(
      onTap: () {
        setModalState(() {
          controller.text = amount.toStringAsFixed(0);
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.orange : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.orange : Colors.grey.shade300,
          ),
        ),
        child: Text(
          amount == 0 ? 'Free' : '₹${amount.toStringAsFixed(0)}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _quickAmountButton(double amount, StateSetter setModalState, TextEditingController controller) {
    final isSelected = _customDeliveryFee == amount;
    return InkWell(
      onTap: () {
        setModalState(() {
          _customDeliveryFee = amount;
          controller.text = amount.toStringAsFixed(0);
        });
        setState(() {});
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? kPrimaryColor : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? kPrimaryColor : Colors.grey.shade300,
          ),
        ),
        child: Text(
          '₹${amount.toStringAsFixed(0)}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    final isSmallScreen = screenWidth < 360;
    final cardMargin = isSmallScreen ? 12.0 : 16.0;
    final cardPadding = isSmallScreen ? 12.0 : 16.0;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.yellow,
        automaticallyImplyLeading: true,
        title: Text(
          "Select Slot",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: isSmallScreen ? 18 : 20,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  controller: _mainScrollController,
                  physics: const BouncingScrollPhysics(),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: cardMargin / 2),
                    child: Column(
                      children: [
                        _buildAddressSection(cardMargin, cardPadding, isSmallScreen),
                        _buildDeliveryControls(cardMargin, cardPadding, isSmallScreen), // NEW!
                        _buildProgressIndicator(cardMargin, isSmallScreen),
                        if (currentStep == 0) ...[
                          _buildDateSelector(true, cardMargin, isSmallScreen),
                          if (isLoadingSlots)
                            Container(
                              padding: EdgeInsets.all(cardPadding * 2),
                              child: Center(
                                child: CircularProgressIndicator(color: kPrimaryColor),
                              ),
                            )
                          else
                            _buildPickupSlotsSection(cardMargin, cardPadding, isSmallScreen),
                        ],
                        if (currentStep == 1) ...[
                          _buildDateSelector(false, cardMargin, isSmallScreen),
                          if (isLoadingSlots)
                            Container(
                              padding: EdgeInsets.all(cardPadding * 2),
                              child: Center(
                                child: CircularProgressIndicator(color: kPrimaryColor),
                              ),
                            )
                          else
                            Container(
                              key: _deliverySlotSectionKey,
                              child: _buildDeliverySlotsSection(cardMargin, cardPadding, isSmallScreen),
                            ),
                        ],
                        if (selectedPickupSlot != null || selectedDeliverySlot != null)
                          _buildSelectionSummary(cardMargin, cardPadding, isSmallScreen),

                        if (selectedPickupSlot != null && selectedDeliverySlot != null)
                          _buildBillingSummary(cardMargin, cardPadding, isSmallScreen),

                        if (selectedPickupSlot != null && selectedDeliverySlot != null)
                          Container(
                            key: _paymentSectionKey,
                            child: _buildPaymentMethodSelection(cardMargin, cardPadding, isSmallScreen),
                          ),

                        SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (!isServiceAvailable && selectedAddress != null)
            Container(
              color: Colors.black54,
              child: Center(
                child: Container(
                  margin: EdgeInsets.all(cardMargin * 2),
                  padding: EdgeInsets.all(cardPadding * 1.5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_off, size: isSmallScreen ? 48 : 64, color: Colors.red.shade400),
                      SizedBox(height: cardPadding),
                      Text(
                        'Service Unavailable',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 18 : 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: cardPadding / 2),
                      Text(
                        'Sorry, we are currently not available in ${selectedAddress!['pincode']}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isSmallScreen ? 12 : 14,
                          color: Colors.black54,
                        ),
                      ),
                      SizedBox(height: cardPadding),
                      ElevatedButton(
                        onPressed: _openAddressBook,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimaryColor,
                          padding: EdgeInsets.symmetric(
                            horizontal: cardPadding * 1.5,
                            vertical: cardPadding,
                          ),
                        ),
                        child: Text(
                          'Change Address',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 14 : 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(isSmallScreen),
    );
  }

  Widget _buildDeliveryControls(double cardMargin, double cardPadding, bool isSmallScreen) {
    final bool hasWash = _hasWashServices();

    return Container(
      margin: EdgeInsets.symmetric(horizontal: cardMargin, vertical: cardMargin / 2),
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kPrimaryColor.withOpacity(0.2), Colors.grey.shade900],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kPrimaryColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Delivery Fee Toggle with clickable amount
          Row(
            children: [
              Icon(Icons.local_shipping, color: kPrimaryColor, size: isSmallScreen ? 18 : 20),
              SizedBox(width: cardPadding / 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Delivery Fee',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 14 : 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    GestureDetector(
                      onTap: _deliveryFeeEnabled ? _showDeliveryFeeSelector : null,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _deliveryFeeEnabled
                              ? kPrimaryColor.withOpacity(0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: _deliveryFeeEnabled
                              ? Border.all(color: kPrimaryColor.withOpacity(0.3))
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _deliveryFeeEnabled
                                  ? '₹${_customDeliveryFee.toStringAsFixed(0)} - Tap to change'
                                  : 'Not included',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 11 : 12,
                                color: _deliveryFeeEnabled
                                    ? Colors.black87
                                    : Colors.orange.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (_deliveryFeeEnabled) ...[
                              SizedBox(width: 4),
                              Icon(
                                Icons.edit,
                                size: 14,
                                color: Colors.black87,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _deliveryFeeEnabled,
                onChanged: (val) {
                  setState(() {
                    _deliveryFeeEnabled = val;
                    if (val) {
                      // Initialize with base amount when enabling
                      final baseAmount = isStandardDelivery ? standardDeliveryFee : expressDeliveryFee;
                      if (_customDeliveryFee == 0) {
                        _customDeliveryFee = baseAmount;
                      }
                    }
                  });
                },
                activeColor: Colors.white,
                activeTrackColor: kPrimaryColor,
              ),
            ],
          ),

          // Delivery Type Selector (Always visible)
          SizedBox(height: cardPadding),
          Container(
            padding: EdgeInsets.all(cardPadding * 0.75),
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade700),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.schedule, color: kPrimaryColor, size: isSmallScreen ? 16 : 18),
                    SizedBox(width: cardPadding / 2),
                    Text(
                      'Delivery Type:',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 13 : 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(width: cardPadding),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isExpressDelivery ? Colors.orange.shade100 : Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButton<String>(
                        value: _selectedDeliveryType,
                        underline: const SizedBox(),
                        isDense: true,
                        icon: Icon(
                          Icons.arrow_drop_down,
                          color: isExpressDelivery ? Colors.orange.shade800 : Colors.blue.shade800,
                        ),
                        style: TextStyle(
                          color: isExpressDelivery ? Colors.orange.shade800 : Colors.blue.shade800,
                          fontWeight: FontWeight.bold,
                          fontSize: isSmallScreen ? 11 : 12,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'Standard',
                            child: Text('STANDARD'),
                          ),
                          DropdownMenuItem(
                            value: 'Express',
                            child: Text('EXPRESS'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            // If switching to Express and delivery fee is OFF, show popup
                            if (value == 'Express' && !_deliveryFeeEnabled) {
                              _showExpressChargeSelector(onAmountSet: (amount) {
                                setState(() {
                                  _selectedDeliveryType = value;
                                  _customDeliveryFee = amount; // Use the amount entered by user
                                  selectedPickupSlot = null;
                                  selectedDeliverySlot = null;
                                  _updateDeliveryDates();
                                });
                              });
                            } else {
                              setState(() {
                                _selectedDeliveryType = value;
                                // Update custom fee to new base when switching types
                                final newBase = value == 'Express' ? expressDeliveryFee : standardDeliveryFee;
                                _customDeliveryFee = newBase;
                                // Reset slots when delivery type changes
                                selectedPickupSlot = null;
                                selectedDeliverySlot = null;
                                _updateDeliveryDates();
                              });
                            }
                          }
                        },
                      ),
                    ),
                  ],
                ),
                SizedBox(height: cardPadding / 2),
                Container(
                  padding: EdgeInsets.all(cardPadding * 0.5),
                  decoration: BoxDecoration(
                    color: (isExpressDelivery ? Colors.orange : Colors.blue).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: isSmallScreen ? 14 : 16,
                        color: isExpressDelivery ? Colors.orange.shade700 : Colors.blue.shade700,
                      ),
                      SizedBox(width: cardPadding / 2),
                      Expanded(
                        child: Text(
                          hasWash
                              ? (isExpressDelivery
                              ? 'Wash services: 36 hours for Express'
                              : 'Wash services: 48 hours for Standard')
                              : (isExpressDelivery
                              ? 'Iron-only: Same day (6 hours min)'
                              : 'Iron-only: Next day (24 hours min)'),
                          style: TextStyle(
                            fontSize: isSmallScreen ? 10 : 11,
                            color: isExpressDelivery ? Colors.orange.shade700 : Colors.blue.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillingSummary(double cardMargin, double cardPadding, bool isSmallScreen) {
    if (isLoadingBillingSettings) {
      return Container(
        margin: EdgeInsets.all(cardMargin),
        padding: EdgeInsets.all(cardPadding * 2),
        child: Center(child: CircularProgressIndicator(color: kPrimaryColor)),
      );
    }

    final billing = _calculateBilling();
    final bool hasDiscount = (billing['discount'] ?? 0) > 0;
    final String discountLabel = hasDiscount && (widget.appliedCouponCode?.isNotEmpty ?? false)
        ? 'Discount (${widget.appliedCouponCode})'
        : 'Discount';

    final double sub = billing['subtotal'] ?? 0;
    final double disc = billing['discount'] ?? 0;
    final bool qualifiesFreeStandard = isStandardDelivery && ((sub - disc) >= freeStandardThreshold);

    return Container(
      margin: EdgeInsets.all(cardMargin),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kPrimaryColor.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _isBillingSummaryExpanded = !_isBillingSummaryExpanded;
              });
              if (_isBillingSummaryExpanded) {
                _billingAnimationController.forward();
              } else {
                _billingAnimationController.reverse();
              }
            },
            child: Container(
              padding: EdgeInsets.all(cardPadding),
              decoration: BoxDecoration(
                color: kPrimaryColor.withOpacity(0.05),
                borderRadius: _isBillingSummaryExpanded
                    ? const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                )
                    : BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(isSmallScreen ? 6 : 8),
                    decoration: BoxDecoration(
                      color: kPrimaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.receipt_long, color: kPrimaryColor, size: isSmallScreen ? 18 : 20),
                  ),
                  SizedBox(width: cardPadding * 0.75),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bill Summary',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 14 : 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.yellow, // ✅ ADDED WHITE COLOR
                          ),
                        ),
                        Text(
                          'Total: ₹${billing['totalAmount']!.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 12 : 14,
                            fontWeight: FontWeight.bold,
                            color: kPrimaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _isBillingSummaryExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: kPrimaryColor,
                      size: isSmallScreen ? 20 : 24,
                    ),
                  ),
                ],
              ),
            ),
          ),

          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: _isBillingSummaryExpanded ? null : 0,
            child: _isBillingSummaryExpanded
                ? Container(
              padding: EdgeInsets.all(cardPadding),
              child: Column(
                children: [
                  _buildBillingRow(
                    'Subtotal',
                    billing['subtotal'] ?? 0,
                    isSmallScreen: isSmallScreen,
                  ),

                  if (hasDiscount)
                    _buildBillingRow(
                      discountLabel,
                      -(billing['discount'] ?? 0),
                      color: Colors.green,
                      isSmallScreen: isSmallScreen,
                    ),

                  if ((billing['minimumCartFee'] ?? 0) > 0)
                    _buildBillingRow(
                      'Minimum Cart Fee',
                      billing['minimumCartFee'] ?? 0,
                      infoKey: 'minimum_cart_fee',
                      isSmallScreen: isSmallScreen,
                    ),

                  _buildBillingRow(
                    'Platform Fee',
                    billing['platformFee'] ?? 0,
                    infoKey: 'platform_fee',
                    isSmallScreen: isSmallScreen,
                  ),

                  if ((billing['expressCharges'] ?? 0) > 0)
                    _buildBillingRow(
                      'Express Charges',
                      billing['expressCharges'] ?? 0,
                      infoKey: 'delivery_express',
                      isSmallScreen: isSmallScreen,
                    ),

                  if ((billing['deliveryFee'] ?? 0) > 0)
                    _buildBillingRow(
                      isExpressDelivery ? 'Delivery Fee (Express)' : 'Delivery Fee (Standard)',  // ✅ CHANGED: Dynamic label
                      billing['deliveryFee'] ?? 0,
                      infoKey: isStandardDelivery
                          ? (qualifiesFreeStandard
                          ? 'delivery_standard_free'
                          : 'delivery_standard')
                          : 'delivery_express',  // ✅ CHANGED: Use express info key
                      overrideTitle:
                      (isStandardDelivery && qualifiesFreeStandard) ? 'Standard Delivery — Free' : null,
                      isSmallScreen: isSmallScreen,
                    ),

                  _buildBillingRow(
                    'Service Taxes',
                    billing['serviceTax'] ?? 0,
                    infoKey: 'service_tax',
                    isSmallScreen: isSmallScreen,
                  ),

                  const Divider(height: 20, color: Colors.grey), // ✅ ADDED GREY DIVIDER

                  _buildBillingRow(
                    'Total Amount',
                    billing['totalAmount'] ?? 0,
                    isTotal: true,
                    color: kPrimaryColor,
                    isSmallScreen: isSmallScreen,
                  ),
                ],
              ),
            )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildBillingRow(
      String label,
      double amount, {
        bool isTotal = false,
        Color? color,
        String? customValue,
        String? infoKey,
        String? overrideTitle,
        required bool isSmallScreen,
        Color? textColor, // ✅ NEW PARAMETER
      }) {
    final bool clickable = infoKey != null && (_billingNotes[infoKey] != null);

    final TextStyle labelStyle = TextStyle(
      fontSize: isTotal ? (isSmallScreen ? 14 : 16) : (isSmallScreen ? 12 : 14),
      fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
      color: textColor ?? color ?? Colors.white, // ✅ USE textColor FIRST
    );

    final TextStyle valueStyle = TextStyle(
      fontSize: isTotal ? (isSmallScreen ? 14 : 16) : (isSmallScreen ? 12 : 14),
      fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
      color: textColor ?? color ?? Colors.white, // ✅ USE textColor FIRST
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          InkWell(
            onTap: () {
              if (infoKey == null) return;

              final billing = _calculateBilling();

              if (infoKey == 'minimum_cart_fee') {
                _showMinimumCartFeePopover(billing);
                return;
              }
              if (infoKey == 'platform_fee') {
                _showPlatformFeePopover(billing);
                return;
              }
              if (infoKey == 'service_tax') {
                _showServiceTaxesPopover(billing);
                return;
              }
              if (infoKey == 'delivery_standard' || infoKey == 'delivery_express' || infoKey == 'delivery_standard_free') {
                _showDeliveryFeePopover(billing);
                return;
              }

              final note = _billingNotes[infoKey];
              _showInfoDialog(overrideTitle ?? (note?['title'] ?? label), note?['content'] ?? '');
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: labelStyle),
                if (_billingNotes[infoKey ?? ''] != null) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.info_outline, size: 14, color: textColor ?? color ?? Colors.white),
                ],
              ],
            ),
          ),

          Text(
            customValue ?? '₹${amount.toStringAsFixed(2)}',
            style: valueStyle,
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodSelection(double cardMargin, double cardPadding, bool isSmallScreen) {
    if (!onlinePaymentEnabled && _selectedPaymentMethod == 'online') {
      _selectedPaymentMethod = 'cod';
    }

    return Container(
      margin: EdgeInsets.all(cardMargin),
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.payment, color: kPrimaryColor, size: isSmallScreen ? 18 : 20),
              SizedBox(width: cardPadding / 2),
              Text(
                'Payment Method',
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: cardPadding),

          if (!onlinePaymentEnabled)
            Container(
              width: double.infinity,
              margin: EdgeInsets.only(bottom: cardPadding * 0.75),
              padding: EdgeInsets.all(cardPadding * 0.75),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: isSmallScreen ? 16 : 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Online payment is temporarily unavailable. Please choose Pay on Delivery.',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 10.5 : 12,
                        color: Colors.orange.shade800,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          if (onlinePaymentEnabled)
            Container(
              margin: EdgeInsets.only(bottom: cardPadding * 0.75),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedPaymentMethod == 'online' ? kPrimaryColor : Colors.grey.shade300,
                  width: 2,
                ),
                color: _selectedPaymentMethod == 'online'
                    ? kPrimaryColor.withOpacity(0.05)
                    : Colors.white,
              ),
              child: RadioListTile<String>(
                value: 'online',
                groupValue: _selectedPaymentMethod,
                onChanged: (value) {
                  setState(() {
                    _selectedPaymentMethod = value!;
                  });
                },
                title: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(isSmallScreen ? 4 : 6),
                      decoration: BoxDecoration(
                        color: kPrimaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.payment,
                        color: kPrimaryColor,
                        size: isSmallScreen ? 14 : 16,
                      ),
                    ),
                    SizedBox(width: cardPadding * 0.6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pay Online',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: isSmallScreen ? 12 : 14,
                            ),
                          ),
                          Text(
                            'UPI, Card, Net Banking, Wallet',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 9 : 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_selectedPaymentMethod == 'online')
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isSmallScreen ? 4 : 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'RECOMMENDED',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: isSmallScreen ? 7 : 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                activeColor: kPrimaryColor,
              ),
            ),

          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _selectedPaymentMethod == 'cod' ? kPrimaryColor : Colors.grey.shade300,
                width: 2,
              ),
              color: _selectedPaymentMethod == 'cod'
                  ? kPrimaryColor.withOpacity(0.05)
                  : Colors.white,
            ),
            child: RadioListTile<String>(
              value: 'cod',
              groupValue: _selectedPaymentMethod,
              onChanged: (value) {
                setState(() {
                  _selectedPaymentMethod = value!;
                });
              },
              title: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(isSmallScreen ? 4 : 6),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.money,
                      color: Colors.orange,
                      size: isSmallScreen ? 14 : 16,
                    ),
                  ),
                  SizedBox(width: cardPadding * 0.6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pay on Delivery',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: isSmallScreen ? 12 : 14,
                          ),
                        ),
                        Text(
                          'Cash payment when order is delivered',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 9 : 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              activeColor: kPrimaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionSummary(double cardMargin, double cardPadding, bool isSmallScreen) {
    if (selectedPickupSlot == null) return const SizedBox.shrink();

    return Container(
      margin: EdgeInsets.all(cardMargin),
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        color: Colors.grey.shade900, // ✅ CHANGED: Dark grey outer container
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kPrimaryColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: kPrimaryColor, size: isSmallScreen ? 18 : 20),
              SizedBox(width: cardPadding / 2),
              Text(
                'Selection Summary',
                style: TextStyle(
                  color: kPrimaryColor,
                  fontWeight: FontWeight.w600,
                  fontSize: isSmallScreen ? 14 : 16,
                ),
              ),
            ],
          ),
          SizedBox(height: cardPadding * 0.75),
          Container(
            padding: EdgeInsets.all(cardPadding * 0.75),
            decoration: BoxDecoration(
              color: Colors.grey.shade800, // ✅ CHANGED: Slightly lighter grey for inner container
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade700), // ✅ CHANGED: Grey border
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.schedule, color: kPrimaryColor, size: isSmallScreen ? 14 : 16),
                    SizedBox(width: cardPadding / 2),
                    Expanded(
                      child: Text(
                        'Pickup: ${_formatDate(selectedPickupDate)} at ${selectedPickupSlot!['display_time'] ?? '${selectedPickupSlot!['start_time']} - ${selectedPickupSlot!['end_time']}'}',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: isSmallScreen ? 12 : 14,
                          color: Colors.white, // ✅ ADDED: White text on dark background
                        ),
                      ),
                    ),
                  ],
                ),
                if (selectedDeliverySlot != null) ...[
                  SizedBox(height: cardPadding / 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.local_shipping, color: kPrimaryColor, size: isSmallScreen ? 14 : 16),
                      SizedBox(width: cardPadding / 2),
                      Expanded(
                        child: Text(
                          'Delivery: ${_formatDate(selectedDeliveryDate)} at ${selectedDeliverySlot!['display_time'] ?? '${selectedDeliverySlot!['start_time']} - ${selectedDeliverySlot!['end_time']}'}',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: isSmallScreen ? 12 : 14,
                            color: Colors.white, // ✅ ADDED: White text on dark background
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.day == now.day && date.month == now.month && date.year == now.year) {
      return 'Today';
    } else if (date.day == now.add(const Duration(days: 1)).day &&
        date.month == now.add(const Duration(days: 1)).month &&
        date.year == now.add(const Duration(days: 1)).year) {
      return 'Tomorrow';
    } else {
      return '${date.day}/${date.month}';
    }
  }

  Widget _buildDateSelector(bool isPickup, double cardMargin, bool isSmallScreen) {
    DateTime selectedDate = isPickup ? selectedPickupDate : selectedDeliveryDate;
    ScrollController controller = isPickup ? _pickupDateScrollController : _deliveryDateScrollController;
    List<DateTime> availableDates = isPickup ? pickupDates : _getAvailableDeliveryDates();

    return Container(
      margin: EdgeInsets.symmetric(horizontal: cardMargin, vertical: cardMargin / 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today, color: kPrimaryColor, size: isSmallScreen ? 18 : 20),
              SizedBox(width: cardMargin / 2),
              Text(
                'Select ${isPickup ? 'Pickup' : 'Delivery'} Date',
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: cardMargin * 0.75),
          SizedBox(
            height: isSmallScreen ? 70 : 80,
            child: ListView.builder(
              controller: controller,
              scrollDirection: Axis.horizontal,
              itemCount: availableDates.length,
              itemBuilder: (context, index) {
                final date = availableDates[index];
                final isSelected = date.day == selectedDate.day &&
                    date.month == selectedDate.month &&
                    date.year == selectedDate.year;
                final isToday = date.day == DateTime.now().day &&
                    date.month == DateTime.now().month &&
                    date.year == DateTime.now().year;

                bool isDisabled = false;
                if (!isPickup) {
                  isDisabled = date.isBefore(selectedPickupDate);
                }

                return GestureDetector(
                  onTap: isDisabled ? null : () {
                    if (isPickup) {
                      _onPickupDateSelected(date);
                    } else {
                      _onDeliveryDateSelected(date);
                    }
                  },
                  child: Container(
                    width: isSmallScreen ? 50 : 60,
                    margin: EdgeInsets.only(right: cardMargin / 2),
                    decoration: BoxDecoration(
                      color: isDisabled
                          ? Colors.white
                          : isSelected ? kPrimaryColor : Colors.grey.shade900,
                      border: Border.all(
                        color: isDisabled
                            ? Colors.white
                            : isSelected ? kPrimaryColor : Colors.grey.shade600,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: isSelected && !isDisabled
                          ? [BoxShadow(color: kPrimaryColor.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))]
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _getDayName(date.weekday),
                          style: TextStyle(
                            fontSize: isSmallScreen ? 9 : 10,
                            fontWeight: FontWeight.w600,
                            color: isDisabled
                                ? Colors.grey.shade500
                                : isSelected ? Colors.white : Colors.black54,
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 2 : 4),
                        Text(
                          date.day.toString(),
                          style: TextStyle(
                            fontSize: isSmallScreen ? 14 : 16,
                            fontWeight: FontWeight.bold,
                            color: isDisabled
                                ? Colors.grey.shade500
                                : isSelected ? Colors.white : Colors.black,
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 1 : 2),
                        if (isToday)
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isSmallScreen ? 4 : 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: isDisabled
                                  ? Colors.grey.shade400
                                  : isSelected ? Colors.white : kPrimaryColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Today',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 7 : 8,
                                fontWeight: FontWeight.w600,
                                color: isDisabled
                                    ? Colors.white
                                    : isSelected ? kPrimaryColor : Colors.white,
                              ),
                            ),
                          )
                        else
                          Text(
                            _getMonthName(date.month),
                            style: TextStyle(
                              fontSize: isSmallScreen ? 7 : 8,
                              fontWeight: FontWeight.w500,
                              color: isDisabled
                                  ? Colors.grey.shade500
                                  : isSelected ? Colors.white70 : Colors.black45,
                            ),
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
    );
  }

  String _getDayName(int weekday) {
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return days[weekday - 1];
  }

  String _getMonthName(int month) {
    const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    return months[month - 1];
  }

  Widget _buildProgressIndicator(double cardMargin, bool isSmallScreen) {
    return Container(
        margin: EdgeInsets.symmetric(horizontal: cardMargin, vertical: cardMargin / 2),
        child: Row(
          children: [
            Container(
              width: isSmallScreen ? 20 : 24,
              height: isSmallScreen ? 20 : 24,
              decoration: BoxDecoration(
                color: currentStep >= 0 ? kPrimaryColor : Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
              child: Icon(
                selectedPickupSlot != null ? Icons.check : Icons.schedule,
                color: Colors.white,
                size: isSmallScreen ? 12 : 16,
              ),
            ),
            Expanded(
              child: Container(
                height: 2,
                color: currentStep >= 1 ? kPrimaryColor : Colors.grey.shade300,
              ),
            ),
            Container(
              width: isSmallScreen ? 20 : 24,
              height: isSmallScreen ? 20 : 24,
              decoration: BoxDecoration(
                color: currentStep >= 1 ? kPrimaryColor : Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
              child: Icon(
                selectedDeliverySlot != null ? Icons.check : Icons.local_shipping,
                color: Colors.white,
                size: isSmallScreen ? 12 : 16,
              ),
            ),
          ],
        ));
    }

  Widget _buildAddressSection(double cardMargin, double cardPadding, bool isSmallScreen) {
    return Container(
      margin: EdgeInsets.all(cardMargin),
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on, color: kPrimaryColor, size: isSmallScreen ? 18 : 20),
              SizedBox(width: cardPadding / 2),
              Text(
                'Delivery Address',
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _openAddressBook,
                child: Text(
                  selectedAddress == null ? 'Select' : 'Change',
                  style: TextStyle(
                    color: kPrimaryColor,
                    fontSize: isSmallScreen ? 12 : 14,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: cardPadding / 2),

          if (selectedAddress != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.person, size: isSmallScreen ? 14 : 16, color: Colors.yellow),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    (selectedAddress!['recipient_name'] ?? '').toString().trim(),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: isSmallScreen ? 12 : 14,
                      color: Colors.yellow,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),

            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.phone, size: isSmallScreen ? 13 : 15, color: Colors.yellow),
                SizedBox(width: 6),
                Text(
                  _formatPhone((selectedAddress!['phone_number'] ?? '').toString().trim()),
                  style: TextStyle(
                    fontSize: isSmallScreen ? 12 : 13,
                    color: Colors.yellow,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),

            Text(
              selectedAddress!['address_line_1'] ?? '',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: isSmallScreen ? 12 : 14,
              ),
            ),
            if ((selectedAddress!['address_line_2'] ?? '').toString().trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  selectedAddress!['address_line_2'],
                  style: TextStyle(fontSize: isSmallScreen ? 12 : 14),
                ),
              ),
            if ((selectedAddress!['landmark'] ?? '').toString().trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Near ${selectedAddress!['landmark']}',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 11 : 13,
                    color: Colors.grey.shade400,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${selectedAddress!['city']}, ${selectedAddress!['state']} - ${selectedAddress!['pincode']}',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: isSmallScreen ? 11 : 13,
                ),
              ),
            ),

            if (isLoadingServiceAvailability)
              Padding(
                padding: EdgeInsets.only(top: cardPadding / 2),
                child: Text(
                  'Checking availability...',
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: isSmallScreen ? 10 : 12,
                  ),
                ),
              )
            else if (!isServiceAvailable)
              Padding(
                padding: EdgeInsets.only(top: cardPadding / 2),
                child: Text(
                  '❌ Service not available',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: isSmallScreen ? 10 : 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            else
              Padding(
                padding: EdgeInsets.only(top: cardPadding / 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_box, size: isSmallScreen ? 12 : 14, color: Colors.green),
                    SizedBox(width: 4),
                    Text(
                      'Service available',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: isSmallScreen ? 10 : 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ] else ...[
            GestureDetector(
              onTap: _openAddressBook,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(cardPadding),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.add_location, color: Colors.grey.shade600, size: isSmallScreen ? 18 : 20),
                    SizedBox(width: cardPadding * 0.75),
                    Text(
                      'Select delivery address',
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: isSmallScreen ? 14 : 16,
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.arrow_forward_ios, size: isSmallScreen ? 14 : 16, color: Colors.grey.shade600),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPickupSlotsSection(double cardMargin, double cardPadding, bool isSmallScreen) {
    List<Map<String, dynamic>> allSlots = _getFilteredPickupSlots();  // ✅ CORRECT
    return Container(
      margin: EdgeInsets.all(cardMargin),
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule, color: kPrimaryColor, size: isSmallScreen ? 18 : 20),
              SizedBox(width: cardPadding / 2),
              Text(
                'Schedule Pickup',
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: kPrimaryColor,
                ),
              ),
            ],
          ),
          SizedBox(height: cardPadding),
          _buildTimeSlots(allSlots, true, isSmallScreen),
        ],
      ),
    );
  }

  Widget _buildDeliverySlotsSection(double cardMargin, double cardPadding, bool isSmallScreen) {
    List<Map<String, dynamic>> allSlots = _getFilteredDeliverySlots();  // ✅ CORRECT
    return Container(
      margin: EdgeInsets.all(cardMargin),
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: _goBackToPickup,
                icon: Icon(Icons.arrow_back, size: isSmallScreen ? 18 : 20, color: kPrimaryColor),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              SizedBox(width: cardPadding / 2),
              Icon(Icons.local_shipping, color: kPrimaryColor, size: isSmallScreen ? 18 : 20),
              SizedBox(width: cardPadding / 2),
              Expanded(
                child: Text(
                  'Schedule Delivery ${isExpressDelivery ? '(Express)' : '(Standard)'}',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 14 : 16,
                    fontWeight: FontWeight.w600,
                    color: kPrimaryColor,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: cardPadding),
          _buildTimeSlots(allSlots, false, isSmallScreen),
        ],
      ),
    );
  }

  Widget _buildTimeSlots(List<Map<String, dynamic>> slots, bool isPickup, bool isSmallScreen) {
    if (slots.isEmpty) {
      return Container(
        padding: EdgeInsets.all(isSmallScreen ? 20 : 24),
        child: Column(
          children: [
            Icon(Icons.schedule, size: isSmallScreen ? 40 : 48, color: Colors.grey.shade400),
            SizedBox(height: isSmallScreen ? 6 : 8),
            Text(
              'No ${isPickup ? 'pickup' : 'delivery'} slots available',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: isSmallScreen ? 12 : 14,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isSmallScreen ? 1 : 2,
        childAspectRatio: isSmallScreen ? 4 : 3,
        crossAxisSpacing: isSmallScreen ? 6 : 8,
        mainAxisSpacing: isSmallScreen ? 6 : 8,
      ),
      itemCount: slots.length,
      itemBuilder: (context, index) {
        final slot = slots[index];
        bool isSelected = isPickup
            ? (selectedPickupSlot?['id'] == slot['id'])
            : (selectedDeliverySlot?['id'] == slot['id']);

        // ✅ REMOVED: Don't check availability again - slots are already filtered
        // All slots in the list are available

        return GestureDetector(
          onTap: () {
            if (isPickup) {
              _onPickupSlotSelected(slot);
            } else {
              _onDeliverySlotSelected(slot);
            }
          },
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isSmallScreen ? 8 : 12,
              vertical: isSmallScreen ? 6 : 8,
            ),
            decoration: BoxDecoration(
              color: isSelected ? kPrimaryColor : Colors.grey.shade900,
              border: Border.all(
                color: isSelected ? kPrimaryColor : Colors.grey.shade600,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: isSelected
                  ? [BoxShadow(color: kPrimaryColor.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))]
                  : null,
            ),
            child: Center(
              child: Text(
                slot['display_time'] ?? '${slot['start_time']} - ${slot['end_time']}',
                style: TextStyle(
                  color: isSelected ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: isSmallScreen ? 11 : 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar(bool isSmallScreen) {
    double totalAmount = _calculateTotalAmount();
    bool canProceed = selectedAddress != null &&
        selectedPickupSlot != null &&
        selectedDeliverySlot != null &&
        isServiceAvailable &&
        !isLoadingBillingSettings;

    final buttonText = _selectedPaymentMethod == 'online' ? 'Pay Now' : 'Place Order';
    final buttonIcon = _selectedPaymentMethod == 'online' ? Icons.payment : Icons.shopping_bag;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 16 : 20,
        vertical: isSmallScreen ? 10 : 12,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade700)),
        color: Colors.black,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Total Amount",
                    style: TextStyle(
                      fontSize: isSmallScreen ? 11 : 13,
                      color: Colors.grey.shade400,
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 2 : 4),
                  if (isLoadingBillingSettings)
                    SizedBox(
                      width: isSmallScreen ? 16 : 20,
                      height: isSmallScreen ? 16 : 20,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Text(
                      "₹${totalAmount.toStringAsFixed(2)}",
                      style: TextStyle(
                        fontSize: isSmallScreen ? 16 : 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),

            Container(
              height: isSmallScreen ? 44 : 50,
              child: ElevatedButton(
                onPressed: (canProceed && !_isProcessingPayment) ? _handleProceed : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  padding: EdgeInsets.symmetric(
                    horizontal: isSmallScreen ? 20 : 24,
                    vertical: isSmallScreen ? 12 : 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                  elevation: canProceed ? 8 : 0,
                  shadowColor: kPrimaryColor.withOpacity(0.3),
                ),
                child: _isProcessingPayment
                    ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: isSmallScreen ? 14 : 16,
                      height: isSmallScreen ? 14 : 16,
                      child: const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                    SizedBox(width: isSmallScreen ? 6 : 8),
                    Text(
                      'Processing...',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 12 : 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                )
                    : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      buttonIcon,
                      color: Colors.white,
                      size: isSmallScreen ? 16 : 18,
                    ),
                    SizedBox(width: isSmallScreen ? 4 : 6),
                    Text(
                      isLoadingBillingSettings ? "Loading..." : buttonText,
                      style: TextStyle(
                        fontSize: isSmallScreen ? 13 : 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
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