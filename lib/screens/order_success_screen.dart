import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'orders_screen.dart';
import 'colors.dart';
import 'order_history_page.dart';
import 'orders_screen.dart';
import 'home_shell.dart';

class OrderSuccessScreen extends StatefulWidget {
  final String orderId;
  final double totalAmount;
  final List<Map<String, dynamic>> cartItems;
  final String paymentMethod;
  final String? paymentId;
  final String? appliedCouponCode;
  final double discount;
  final Map<String, dynamic> selectedAddress;
  final DateTime pickupDate;
  final Map<String, dynamic> pickupSlot;
  final DateTime deliveryDate;
  final Map<String, dynamic> deliverySlot;
  final bool isExpressDelivery;

  const OrderSuccessScreen({
    super.key,
    required this.orderId,
    required this.totalAmount,
    required this.cartItems,
    required this.paymentMethod,
    this.paymentId,
    this.appliedCouponCode,
    required this.discount,
    required this.selectedAddress,
    required this.pickupDate,
    required this.pickupSlot,
    required this.deliveryDate,
    required this.deliverySlot,
    required this.isExpressDelivery,
  });

  @override
  State<OrderSuccessScreen> createState() => _OrderSuccessScreenState();
}

class _OrderSuccessScreenState extends State<OrderSuccessScreen>
    with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  // ✅ RESPONSIVE: Screen size variables
  late double screenWidth;
  late double screenHeight;
  late bool isSmallScreen;
  late bool isTablet;
  late double cardMargin;
  late double cardPadding;

  // Billing details from database
  Map<String, dynamic>? billingDetails;
  bool isLoadingBilling = true;

  // ✅ NEW: Expanded items state
  bool _isOrderDetailsExpanded = false;

  late AnimationController _mainController;
  late AnimationController _checkController;
  late AnimationController _textController;
  late AnimationController _confettiController;
  late AnimationController _pulseController;
  late AnimationController _backgroundController;
  late AnimationController _expansionController;

  // Background animations
  late Animation<double> _backgroundFadeAnimation;
  late Animation<double> _gradientAnimation;

  // Main animations
  late Animation<double> _cardScaleAnimation;
  late Animation<Offset> _cardSlideAnimation;

  // Check mark animations
  late Animation<double> _checkScaleAnimation;
  late Animation<double> _checkFadeAnimation;
  late Animation<double> _checkRotationAnimation;

  // Text animations
  late Animation<Offset> _titleSlideAnimation;
  late Animation<double> _titleFadeAnimation;
  late Animation<Offset> _subtitleSlideAnimation;
  late Animation<double> _subtitleFadeAnimation;
  late Animation<Offset> _detailsSlideAnimation;
  late Animation<double> _detailsFadeAnimation;

  // Confetti and effects
  late Animation<double> _confettiAnimation;
  late Animation<double> _pulseAnimation;

  // ✅ NEW: Expansion animation
  late Animation<double> _expansionAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadBillingDetails();
    _startAnimationSequence();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ✅ RESPONSIVE: Initialize screen dimensions
    final screenSize = MediaQuery.of(context).size;
    screenWidth = screenSize.width;
    screenHeight = screenSize.height;
    isSmallScreen = screenWidth < 360;
    isTablet = screenWidth > 600;
    cardMargin = isSmallScreen ? 12.0 : 16.0;
    cardPadding = isSmallScreen ? 16.0 : 20.0;
  }

  void _initializeAnimations() {
    // Background controller for gradient effects
    _backgroundController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );

    // Main controller for overall flow
    _mainController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );

    // Check mark controller
    _checkController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // Text animations controller
    _textController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    // Confetti controller
    _confettiController = AnimationController(
      duration: const Duration(milliseconds: 4000),
      vsync: this,
    );

    // Pulse controller
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    // ✅ NEW: Expansion controller
    _expansionController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    // Background animations
    _backgroundFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
    ));

    _gradientAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _backgroundController,
      curve: Curves.easeInOut,
    ));

    // Card animations
    _cardScaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.2, 0.8, curve: Curves.elasticOut),
    ));

    _cardSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic),
    ));

    // Check mark animations
    _checkScaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _checkController,
      curve: const Interval(0.0, 0.7, curve: Curves.elasticOut),
    ));

    _checkFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _checkController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
    ));

    _checkRotationAnimation = Tween<double>(
      begin: -0.8,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _checkController,
      curve: const Interval(0.0, 0.7, curve: Curves.elasticOut),
    ));

    // Text animations
    _titleSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _textController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
    ));

    _titleFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _textController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
    ));

    _subtitleSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _textController,
      curve: const Interval(0.3, 0.7, curve: Curves.easeOutCubic),
    ));

    _subtitleFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _textController,
      curve: const Interval(0.3, 0.7, curve: Curves.easeIn),
    ));

    _detailsSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _textController,
      curve: const Interval(0.5, 0.9, curve: Curves.easeOutCubic),
    ));

    _detailsFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _textController,
      curve: const Interval(0.5, 0.9, curve: Curves.easeIn),
    ));

    // Confetti animation
    _confettiAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _confettiController,
      curve: Curves.easeOut,
    ));

    // Pulse animation
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    // ✅ NEW: Expansion animation
    _expansionAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _expansionController,
      curve: Curves.easeInOutCubic,
    ));
  }

  void _startAnimationSequence() async {
    // Start background animation
    _backgroundController.repeat(reverse: true);

    // Start main animation
    _mainController.forward();

    // Start check animation after delay
    await Future.delayed(const Duration(milliseconds: 1000));
    if (mounted) {
      _checkController.forward();

      // Start pulse animation
      _pulseController.repeat(reverse: true);
    }

    // Start text animations
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) {
      _textController.forward();
    }

    // Start confetti
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) {
      _confettiController.forward();
    }
  }

  // ✅ NEW: Toggle order details expansion
  void _toggleOrderDetailsExpansion() {
    setState(() {
      _isOrderDetailsExpanded = !_isOrderDetailsExpanded;
    });

    if (_isOrderDetailsExpanded) {
      _expansionController.forward();
    } else {
      _expansionController.reverse();
    }
  }

  // Load billing details from database
  Future<void> _loadBillingDetails() async {
    try {
      final response = await supabase
          .from('order_billing_details')
          .select()
          .eq('order_id', widget.orderId)
          .single();

      setState(() {
        billingDetails = response;
        isLoadingBilling = false;
      });
    } catch (e) {
      print('Error loading billing details: $e');
      setState(() {
        isLoadingBilling = false;
      });
    }
  }

  // ✅ ENHANCED: Handle back button press with attractive popup design
  Future<bool> _onWillPop() async {
    // Show enhanced dialog with attractive design
    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: EdgeInsets.all(cardPadding * 1.2),
          margin: EdgeInsets.symmetric(horizontal: cardMargin * 1.25),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.amber, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.amber.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Success Icon
              Container(
                width: isSmallScreen ? 60 : 80,
                height: isSmallScreen ? 60 : 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.amber,
                      Colors.amber.withOpacity(0.8),
                    ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.amber.withOpacity(0.5),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.check_circle_rounded,
                  color: Colors.black,
                  size: isSmallScreen ? 30 : 40,
                ),
              ),

              SizedBox(height: cardPadding),

              // Title
              Text(
                'Order Confirmed!',
                style: TextStyle(
                  fontSize: isSmallScreen ? 18 : 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber,
                ),
                textAlign: TextAlign.center,
              ),

              SizedBox(height: cardPadding * 0.6),

              // Subtitle
              Text(
                'Your order has been placed successfully.\nWhat would you like to do next?',
                style: TextStyle(
                  fontSize: isSmallScreen ? 12 : 14,
                  color: Colors.amber.withOpacity(0.8),
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),

              SizedBox(height: cardPadding * 1.2),

              // Order ID Badge
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: cardPadding * 0.8,
                  vertical: cardPadding * 0.4,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.amber,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.receipt_long,
                      color: Colors.amber,
                      size: isSmallScreen ? 14 : 16,
                    ),
                    SizedBox(width: cardPadding * 0.3),
                    Text(
                      'Order: ${widget.orderId.length > 15 ? widget.orderId.substring(0, 15) + '...' : widget.orderId}',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 10 : 12,
                        color: Colors.amber,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: cardPadding * 1.4),

              // Action Buttons
              Column(
                children: [
                  // Continue Shopping Button - Enhanced
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop(false);
                        _navigateToOrdersScreen(); // ✅ FIXED: Navigate to OrdersScreen
                      },
                      icon: Icon(
                        Icons.shopping_bag_rounded,
                        color: Colors.black,
                        size: isSmallScreen ? 16 : 20,
                      ),
                      label: Text(
                        'Continue Shopping',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 14 : 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: EdgeInsets.symmetric(
                          vertical: isSmallScreen ? 12 : 14,
                          horizontal: isSmallScreen ? 20 : 24,
                        ),
                        elevation: 4,
                        shadowColor: Colors.amber.withOpacity(0.5),
                      ),
                    ),
                  ),

                  SizedBox(height: cardPadding * 0.6),

                  // Stay Here Button - Enhanced
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: Icon(
                        Icons.visibility_rounded,
                        color: Colors.amber,
                        size: isSmallScreen ? 16 : 20,
                      ),
                      label: Text(
                        'Stay Here',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 14 : 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.amber,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: Colors.amber,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: EdgeInsets.symmetric(
                          vertical: isSmallScreen ? 12 : 14,
                          horizontal: isSmallScreen ? 20 : 24,
                        ),
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: cardPadding * 0.8),

              // Additional info
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.amber.withOpacity(0.6),
                    size: isSmallScreen ? 12 : 14,
                  ),
                  SizedBox(width: cardPadding * 0.3),
                  Flexible(
                    child: Text(
                      'You can always view your order details later',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 9 : 11,
                        color: Colors.amber.withOpacity(0.7),
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return false; // Always prevent back navigation
  }

  // ✅ Navigate to order history (Profile screen with order history opened)
  void _navigateToOrderHistory() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => const HomeShell(initialIndex: 3), // Profile tab
      ),
          (route) => false,
    );
  }
  // ✅ Navigate to home screen and clear entire navigation stack
  void _navigateToHome() {
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  void _navigateToOrdersScreen() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => const HomeShell(initialIndex: 1), // Orders tab
      ),
          (route) => false,
    );
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    _mainController.dispose();
    _checkController.dispose();
    _textController.dispose();
    _confettiController.dispose();
    _pulseController.dispose();
    _expansionController.dispose(); // ✅ NEW: Dispose expansion controller
    super.dispose();
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
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  String _buildFullAddress(Map<String, dynamic> a) {
    String v(dynamic x) => (x ?? '').toString().trim();
    String pick(List<String> keys) {
      for (final k in keys) {
        final s = v(a[k]);
        if (s.isNotEmpty) return s;
      }
      return '';
    }

    // Common key aliases so it works with your data structure
    final name     = pick(['contact_name','name','full_name','recipient_name']);
    final phone    = pick(['phone','phone_number','mobile','contact']);
    final line1    = pick(['address_line_1','line1','address1','street']);
    final line2    = pick(['address_line_2','line2','address2','area2']);
    final landmark = pick(['landmark','nearby','near','reference']);
    final area     = pick(['area','locality','sublocality']);
    final city     = pick(['city','district','town']);
    final state    = pick(['state','state_name']);
    final pincode  = pick(['pincode','zip','postal_code']);

    final lines = <String>[
      // Name & Phone always on top (if they exist)
      [name, phone].where((s) => s.isNotEmpty).join(' • '),

      // Address lines
      [line1, line2].where((s) => s.isNotEmpty).join(', '),

      // Landmark/area (optional)
      [landmark, area].where((s) => s.isNotEmpty).join(', '),

      // City/State/Pincode
      [city, state, pincode].where((s) => s.isNotEmpty).join(', '),
    ].where((s) => s.trim().isNotEmpty).toList();

    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _backgroundController,
        _mainController,
        _checkController,
        _textController,
        _confettiController,
        _pulseController,
        _expansionController, // ✅ NEW: Add expansion controller
      ]),
      builder: (context, child) {
        return PopScope(
          // ✅ Prevent back navigation - use PopScope for newer Flutter versions
          canPop: false,
          onPopInvoked: (didPop) async {
            if (!didPop) {
              await _onWillPop();
            }
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black,
                    Colors.black,
                    Colors.black,
                    Colors.black,
                  ],
                ),
              ),
              child: Stack(
                children: [
                  // Animated Background Circles
                  ...List.generate(5, (index) => _buildBackgroundCircle(index)),

                  // Confetti Effect
                  if (_confettiAnimation.value > 0)
                    ...List.generate(30, (index) => _buildConfettiParticle(index)),

                  // Main Content
                  SafeArea(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: EdgeInsets.all(cardMargin * 1.25),
                        child: SlideTransition(
                          position: _cardSlideAnimation,
                          child: ScaleTransition(
                            scale: _cardScaleAnimation,
                            child: FadeTransition(
                              opacity: _backgroundFadeAnimation,
                              child: Container(
                                width: double.infinity,
                                padding: EdgeInsets.all(cardPadding * 1.2),
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: Colors.amber, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.amber.withOpacity(0.3),
                                      blurRadius: 20,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    // Success Icon
                                    ScaleTransition(
                                      scale: _pulseAnimation,
                                      child: RotationTransition(
                                        turns: _checkRotationAnimation,
                                        child: FadeTransition(
                                          opacity: _checkFadeAnimation,
                                          child: ScaleTransition(
                                            scale: _checkScaleAnimation,
                                            child: Container(
                                              width: isSmallScreen ? 80 : 100,
                                              height: isSmallScreen ? 80 : 100,
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    Colors.amber,
                                                    Colors.amber.withOpacity(0.8),
                                                  ],
                                                ),
                                                shape: BoxShape.circle,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.amber.withOpacity(0.5),
                                                    blurRadius: 15,
                                                    offset: const Offset(0, 8),
                                                  ),
                                                ],
                                              ),
                                              child: Icon(
                                                Icons.check_rounded,
                                                color: Colors.black,
                                                size: isSmallScreen ? 40 : 50,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                    SizedBox(height: cardPadding * 1.2),

                                    // Success Title
                                    SlideTransition(
                                      position: _titleSlideAnimation,
                                      child: FadeTransition(
                                        opacity: _titleFadeAnimation,
                                        child: Column(
                                          children: [
                                            Text(
                                              'Order Placed',
                                              style: TextStyle(
                                                fontSize: isSmallScreen ? 18 : 22,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.amber,
                                              ),
                                            ),
                                            Text(
                                              'Successfully!',
                                              style: TextStyle(
                                                fontSize: isSmallScreen ? 18 : 22,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.amber,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    SizedBox(height: cardPadding),

                                    // Order ID
                                    SlideTransition(
                                      position: _subtitleSlideAnimation,
                                      child: FadeTransition(
                                        opacity: _subtitleFadeAnimation,
                                        child: Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: cardPadding,
                                            vertical: cardPadding * 0.6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: Colors.amber),
                                          ),
                                          child: Column(
                                            children: [
                                              Text(
                                                'Order ID',
                                                style: TextStyle(
                                                  fontSize: isSmallScreen ? 10 : 12,
                                                  color: Colors.amber.withOpacity(0.8),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              SizedBox(height: cardPadding * 0.2),
                                              Text(
                                                widget.orderId,
                                                style: TextStyle(
                                                  fontSize: isSmallScreen ? 14 : 16,
                                                  color: Colors.amber,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),

                                    SizedBox(height: cardPadding * 1.2),

                                    // Order Details
                                    SlideTransition(
                                      position: _detailsSlideAnimation,
                                      child: FadeTransition(
                                        opacity: _detailsFadeAnimation,
                                        child: Column(
                                          children: [
                                            _buildOrderDetailsCard(),
                                            SizedBox(height: cardPadding * 0.8),
                                            _buildScheduleCard(),
                                            SizedBox(height: cardPadding * 0.8),
                                            _buildBillCard(),
                                            SizedBox(height: cardPadding * 0.8),
                                            _buildInfoCard(),
                                          ],
                                        ),
                                      ),
                                    ),

                                    SizedBox(height: cardPadding * 1.6),

                                    // ✅ ENHANCED Action Buttons with smooth animations
                                    SlideTransition(
                                      position: _detailsSlideAnimation,
                                      child: FadeTransition(
                                        opacity: _detailsFadeAnimation,
                                        child: Column(
                                          children: [
                                            // ✅ NEW: View Your Orders Button (goes to profile with order history)
                                            SizedBox(
                                              width: double.infinity,
                                              child: ElevatedButton.icon(
                                                onPressed: _navigateToOrderHistory,
                                                icon: Icon(
                                                  Icons.receipt_long_rounded,
                                                  color: Colors.black,
                                                  size: isSmallScreen ? 16 : 20,
                                                ),
                                                label: Text(
                                                  'View Your Orders',
                                                  style: TextStyle(
                                                    fontSize: isSmallScreen ? 14 : 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.black,
                                                  ),
                                                ),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.amber,
                                                  foregroundColor: Colors.black,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(16),
                                                  ),
                                                  padding: EdgeInsets.symmetric(
                                                    vertical: isSmallScreen ? 14 : 16,
                                                    horizontal: isSmallScreen ? 20 : 24,
                                                  ),
                                                  elevation: 4,
                                                  shadowColor: Colors.amber.withOpacity(0.5),
                                                ),
                                              ),
                                            ),

                                            SizedBox(height: cardPadding * 0.6),

                                            // ✅ NEW: Continue Shopping Button (goes to OrdersScreen)
                                            SizedBox(
                                              width: double.infinity,
                                              child: OutlinedButton.icon(
                                                onPressed: _navigateToOrdersScreen,
                                                icon: Icon(
                                                  Icons.shopping_bag_outlined,
                                                  color: Colors.amber,
                                                  size: isSmallScreen ? 16 : 20,
                                                ),
                                                label: Text(
                                                  'Continue Shopping',
                                                  style: TextStyle(
                                                    fontSize: isSmallScreen ? 14 : 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.amber,
                                                  ),
                                                ),
                                                style: OutlinedButton.styleFrom(
                                                  side: BorderSide(
                                                    color: Colors.amber,
                                                    width: 2,
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(16),
                                                  ),
                                                  padding: EdgeInsets.symmetric(
                                                    vertical: isSmallScreen ? 14 : 16,
                                                    horizontal: isSmallScreen ? 20 : 24,
                                                  ),
                                                  backgroundColor: Colors.transparent,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    SizedBox(height: cardPadding * 0.5),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ✅ ENHANCED Order Details Card with expandable functionality
  Widget _buildOrderDetailsCard() {
    return Container(
      padding: EdgeInsets.all(cardPadding * 0.8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long, color: Colors.amber, size: isSmallScreen ? 18 : 20),
              SizedBox(width: cardPadding * 0.4),
              Text(
                'Order Details',
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.amber,
                ),
              ),
            ],
          ),
          SizedBox(height: cardPadding * 0.6),

          // Always show first 3 items
          ...widget.cartItems.take(3).map((item) => Padding(
            padding: EdgeInsets.only(bottom: cardPadding * 0.4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '${item['product_name']} x${item['product_quantity']}',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 12 : 14,
                      color: Colors.amber.withOpacity(0.9),
                    ),
                  ),
                ),
                Text(
                  '₹${item['total_price']?.toStringAsFixed(2) ?? '0.00'}',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 12 : 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.amber,
                  ),
                ),
              ],
            ),
          )).toList(),

          // ✅ ENHANCED: Show expandable section for remaining items
          if (widget.cartItems.length > 3) ...[
            // Expandable content with smooth animation
            SizeTransition(
              sizeFactor: _expansionAnimation,
              child: FadeTransition(
                opacity: _expansionAnimation,
                child: Column(
                  children: widget.cartItems.skip(3).map((item) => Padding(
                    padding: EdgeInsets.only(bottom: cardPadding * 0.4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${item['product_name']} x${item['product_quantity']}',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 12 : 14,
                              color: Colors.amber.withOpacity(0.9),
                            ),
                          ),
                        ),
                        Text(
                          '₹${item['total_price']?.toStringAsFixed(2) ?? '0.00'}',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 12 : 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.amber,
                          ),
                        ),
                      ],
                    ),
                  )).toList(),
                ),
              ),
            ),

            // ✅ ENHANCED: Smooth toggle button with rotation animation
            SizedBox(height: cardPadding * 0.4),
            GestureDetector(
              onTap: _toggleOrderDetailsExpansion,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: EdgeInsets.symmetric(
                  horizontal: cardPadding * 0.6,
                  vertical: cardPadding * 0.4,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(_isOrderDetailsExpanded ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.amber,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isOrderDetailsExpanded
                          ? 'View Less'
                          : 'View ${widget.cartItems.length - 3} More Items',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 10 : 12,
                        color: Colors.amber,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: cardPadding * 0.2),
                    AnimatedRotation(
                      duration: const Duration(milliseconds: 300),
                      turns: _isOrderDetailsExpanded ? 0.5 : 0.0,
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        color: Colors.amber,
                        size: isSmallScreen ? 14 : 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScheduleCard() {
    return Container(
      padding: EdgeInsets.all(cardPadding * 0.8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule, color: Colors.amber, size: isSmallScreen ? 18 : 20),
              SizedBox(width: cardPadding * 0.4),
              Text(
                'Schedule',
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.amber,
                ),
              ),
            ],
          ),
          SizedBox(height: cardPadding * 0.6),
          _buildScheduleRow(
            Icons.local_laundry_service,
            'Pickup',
            '${_formatDate(widget.pickupDate)} at ${widget.pickupSlot['display_time'] ?? '${widget.pickupSlot['start_time']} - ${widget.pickupSlot['end_time']}'}',
          ),
          SizedBox(height: cardPadding * 0.4),
          _buildScheduleRow(
            Icons.local_shipping,
            'Delivery',
            '${_formatDate(widget.deliveryDate)} at ${widget.deliverySlot['display_time'] ?? '${widget.deliverySlot['start_time']} - ${widget.deliverySlot['end_time']}'}',
          ),
          SizedBox(height: cardPadding * 0.4),
          _buildScheduleRow(
            Icons.flash_on,
            'Delivery Type',
            widget.isExpressDelivery ? 'Express Delivery' : 'Standard Delivery',
          ),
          SizedBox(height: cardPadding * 0.4),
          _buildScheduleRow(
            Icons.location_on,
            'Address',
            _buildFullAddress(widget.selectedAddress),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.amber, size: isSmallScreen ? 14 : 16),
        SizedBox(width: cardPadding * 0.4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: isSmallScreen ? 10 : 12,
                  color: Colors.amber.withOpacity(0.8),
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: isSmallScreen ? 12 : 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.amber.withOpacity(0.9),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBillCard() {
    if (isLoadingBilling) {
      return Container(
        padding: EdgeInsets.all(cardPadding * 1.6),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.amber),
        ),
        child: Center(child: CircularProgressIndicator(color: Colors.amber)),
      );
    }

    return Container(
      padding: EdgeInsets.all(cardPadding * 0.8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt, color: Colors.amber, size: isSmallScreen ? 18 : 20),
              SizedBox(width: cardPadding * 0.4),
              Text(
                'Bill Summary',
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.amber,
                ),
              ),
            ],
          ),
          SizedBox(height: cardPadding * 0.6),

          if (billingDetails != null) ...[
            _buildBillRow('Subtotal', '₹${billingDetails!['subtotal']?.toStringAsFixed(2) ?? '0.00'}'),
            if ((billingDetails!['minimum_cart_fee']?.toDouble() ?? 0.0) > 0)
              _buildBillRow('Minimum Cart Fee', '₹${billingDetails!['minimum_cart_fee']?.toStringAsFixed(2) ?? '0.00'}'),
            _buildBillRow('Platform Fee', '₹${billingDetails!['platform_fee']?.toStringAsFixed(2) ?? '0.00'}'),
            _buildBillRow('Service Tax', '₹${billingDetails!['service_tax']?.toStringAsFixed(2) ?? '0.00'}'),
            _buildBillRow(
              'Delivery Fee (${billingDetails!['delivery_type'] == 'express' ? 'Express' : 'Standard'})',
              '₹${billingDetails!['delivery_fee']?.toStringAsFixed(2) ?? '0.00'}',
            ),

            // ✅ Discount row with coupon code inline
            if ((billingDetails!['discount_amount']?.toDouble() ?? 0.0) > 0)
              _buildBillRow(
                (billingDetails!['applied_coupon_code'] != null &&
                    (billingDetails!['applied_coupon_code'] as String).isNotEmpty)
                    ? 'Discount (${billingDetails!['applied_coupon_code']})'
                    : 'Discount',
                '-₹${billingDetails!['discount_amount']?.toStringAsFixed(2) ?? '0.00'}',
                color: Colors.amber,
              ),
          ] else ...[
            _buildBillRow('Subtotal', '₹${(widget.totalAmount + widget.discount).toStringAsFixed(2)}'),
            if (widget.discount > 0)
              _buildBillRow(
                (widget.appliedCouponCode != null && widget.appliedCouponCode!.isNotEmpty)
                    ? 'Discount (${widget.appliedCouponCode})'
                    : 'Discount',
                '-₹${widget.discount.toStringAsFixed(2)}',
                color: Colors.amber,
              ),
          ],

          Divider(height: cardPadding * 0.8, color: Colors.amber.withOpacity(0.3)),
          _buildBillRow(
            'Total Amount',
            '₹${billingDetails?['total_amount']?.toStringAsFixed(2) ?? widget.totalAmount.toStringAsFixed(2)}',
            isTotal: true,
          ),
          SizedBox(height: cardPadding * 0.4),
          _buildBillRow('Payment Method', widget.paymentMethod == 'online' ? 'Online Payment' : 'Cash on Delivery'),
          if (widget.paymentId != null)
            _buildBillRow('Payment ID', widget.paymentId!),
        ],
      ),
    );
  }

  Widget _buildBillRow(String label, String value, {Color? color, bool isTotal = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: cardPadding * 0.2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: isTotal ? (isSmallScreen ? 13 : 15) : (isSmallScreen ? 12 : 14),
                fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
                color: color ?? Colors.amber.withOpacity(0.9),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? (isSmallScreen ? 13 : 15) : (isSmallScreen ? 12 : 14),
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
              color: color ?? Colors.amber,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: EdgeInsets.all(cardPadding * 0.8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber),
      ),
      child: Column(
        children: [
          _buildInfoRow(
            Icons.schedule_rounded,
            'Your items will be picked up as scheduled',
          ),
          SizedBox(height: cardPadding * 0.6),
          _buildInfoRow(
            Icons.notifications_active_rounded,
            'You\'ll receive updates via SMS and notifications',
          ),
          SizedBox(height: cardPadding * 0.6),
          _buildInfoRow(
            Icons.support_agent_rounded,
            '24/7 customer support available',
          ),
          if (widget.isExpressDelivery) ...[
            SizedBox(height: cardPadding * 0.6),
            _buildInfoRow(
              Icons.flash_on_rounded,
              'Express delivery selected for faster service',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(isSmallScreen ? 4 : 6),
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: Colors.amber,
            size: isSmallScreen ? 14 : 16,
          ),
        ),
        SizedBox(width: cardPadding * 0.6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: isSmallScreen ? 11 : 13,
              color: Colors.amber.withOpacity(0.9),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBackgroundCircle(int index) {
    final random = (index * 234) % 1000;
    final size = (isSmallScreen ? 40.0 : 60.0) + (random % (isSmallScreen ? 40 : 80));
    final left = (random % 100) / 100.0;
    final top = ((random * 3) % 100) / 100.0;
    final opacity = 0.02 + (random % 3) / 100.0;

    return Positioned(
      left: screenWidth * left - size / 2,
      top: screenHeight * top - size / 2,
      child: AnimatedBuilder(
        animation: _backgroundController,
        builder: (context, child) {
          return Transform.scale(
            scale: 1.0 + (_gradientAnimation.value * 0.2),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.amber.withOpacity(opacity),
                    Colors.amber.withOpacity(opacity * 0.3),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildConfettiParticle(int index) {
    final random = (index * 456) % 1000;
    final startX = (random % 100) / 100.0;
    final size = (isSmallScreen ? 3.0 : 4.0) + (random % (isSmallScreen ? 4 : 6));
    final colors = [
      Colors.amber,
      Colors.amber.withOpacity(0.8),
      Colors.amber.withOpacity(0.6),
      Colors.amber.withOpacity(0.4),
    ];
    final color = colors[random % colors.length];

    return Positioned(
      left: screenWidth * startX,
      top: -20 + (_confettiAnimation.value * (screenHeight + 40)),
      child: Transform.rotate(
        angle: _confettiAnimation.value * 6.28 * 3,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: random % 2 == 0 ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: random % 2 != 0 ? BorderRadius.circular(2) : null,
          ),
        ),
      ),
    );
  }
}