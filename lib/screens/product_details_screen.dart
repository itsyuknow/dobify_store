import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/globals.dart';
import '../theme.dart';

class ProductDetailsScreen extends StatefulWidget {
  final String productId;
  const ProductDetailsScreen({Key? key, required this.productId}) : super(key: key);

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen>
    with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  Map<String, dynamic>? _product;
  List<Map<String, dynamic>> _services = [];
  String? _recommendedServiceId;
  int _quantity = 0;
  int _currentCartQuantity = 0;
  String _selectedService = '';
  int _selectedServicePrice = 0;
  bool _addedToCart = false;
  bool _isLoading = false;
  bool _isAddingToCart = false;

  late AnimationController _fadeController;
  late AnimationController _buttonController;
  late AnimationController _successController;
  late AnimationController _floatController;

  late Animation<double> _fadeAnimation;
  late Animation<double> _buttonScale;
  late Animation<double> _successScale;
  late Animation<double> _floatAnimation;

  List<String> _parseServiceIds(dynamic raw) {
    try {
      if (raw == null) return [];
      if (raw is List) {
        return raw.map((e) => e?.toString().trim() ?? '').where((s) => s.isNotEmpty).toList();
      }
      if (raw is String) {
        final s = raw.trim();
        if (s.isEmpty) return [];
        if ((s.startsWith('[') && s.endsWith(']')) || (s.startsWith('"') && s.endsWith('"'))) {
          final decoded = jsonDecode(s);
          if (decoded is List) {
            return decoded.map((e) => e?.toString().trim() ?? '').where((x) => x.isNotEmpty).toList();
          }
        }
        if (s.contains(',')) {
          return s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        }
        return [s];
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> _fetchProductDetails() async {
    setState(() => _isLoading = true);
    try {
      final response = await supabase
          .from('products')
          .select(
          'id, product_name, product_price, image_url, category_id, is_enabled, created_at, recommended_service_id, services_provided, categories(name)')
          .eq('id', widget.productId)
          .eq('is_enabled', true)
          .maybeSingle();

      if (response != null) {
        setState(() {
          _product = response;
          _recommendedServiceId = response['recommended_service_id']?.toString();
          _isLoading = false;
        });
        await _fetchServices();
        await _fetchCurrentCartQuantity();
      } else {
        await _fetchProductDetailsFallback();
      }
    } catch (_) {
      await _fetchProductDetailsFallback();
    }
  }

  Future<void> _fetchProductDetailsFallback() async {
    try {
      final response = await supabase
          .from('products')
          .select('*')
          .eq('id', widget.productId)
          .eq('is_enabled', true)
          .maybeSingle();

      if (response != null) {
        String categoryName = 'General';
        if (response['category_id'] != null) {
          try {
            final categoryResponse = await supabase
                .from('categories')
                .select('name')
                .eq('id', response['category_id'])
                .eq('is_active', true)
                .maybeSingle();
            if (categoryResponse != null) {
              categoryName = categoryResponse['name'] ?? 'General';
            }
          } catch (_) {}
        }
        response['categories'] = {'name': categoryName};

        setState(() {
          _product = response;
          _recommendedServiceId = response['recommended_service_id']?.toString();
          _isLoading = false;
        });

        await _fetchServices();
        await _fetchCurrentCartQuantity();
      } else {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: DobifyColors.black,
              content: Text('Product not found', style: TextStyle(color: DobifyColors.yellow)),
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: DobifyColors.black,
            content: Text('Error loading product: $e', style: const TextStyle(color: DobifyColors.yellow)),
          ),
        );
      }
    }
  }

  Future<void> _fetchServices() async {
    try {
      // Fetch product-specific service prices
      final resp = await supabase
          .from('product_service_prices')
          .select('*, services:service_id(id, name, service_description, service_full_description, icon, color_hex)')
          .eq('product_id', widget.productId)
          .eq('is_available', true)
          .order('price', ascending: true);

      final servicePrices = List<Map<String, dynamic>>.from(resp ?? []);

      setState(() {
        // Transform the data to match existing structure
        _services = servicePrices.map((priceData) {
          final serviceData = priceData['services'] as Map<String, dynamic>;
          return {
            'id': serviceData['id'],
            'name': serviceData['name'],
            'price': (priceData['price'] as num?)?.toInt() ?? 0,
            'regular_wash_price': (priceData['regular_wash_price'] as num?)?.toInt(), // ✅ ADD THIS
            'heavy_wash_price': (priceData['heavy_wash_price'] as num?)?.toInt(),     // ✅ ADD THIS
            'service_description': serviceData['service_description'] ?? '',
            'service_full_description': serviceData['service_full_description'] ?? 'No description available',
            'icon': serviceData['icon'],
            'color_hex': serviceData['color_hex'],
          };
        }).toList();

        if (_services.isNotEmpty) {
          final recId = (_recommendedServiceId ?? '').toString();
          Map<String, dynamic>? recommendedService;
          if (recId.isNotEmpty) {
            try {
              recommendedService = _services.firstWhere((s) => (s['id']?.toString() ?? '') == recId);
            } catch (_) {}
          }
          final chosen = recommendedService ?? _services.first;
          _selectedService = chosen['name'] ?? '';
          _selectedServicePrice = (chosen['price'] as num?)?.toInt() ?? 0;
        } else {
          _selectedService = '';
          _selectedServicePrice = 0;
        }
      });

      await _fetchCurrentCartQuantity();
    } catch (e) {
      debugPrint('Error fetching services: $e');
    }
  }

  bool _isRecommendedService(String serviceId) {
    return _recommendedServiceId != null && _recommendedServiceId == serviceId;
  }

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _fetchProductDetails();
    cartCountNotifier.addListener(_onCartCountChanged);
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(duration: const Duration(milliseconds: 600), vsync: this);
    _buttonController = AnimationController(duration: const Duration(milliseconds: 200), vsync: this);
    _successController = AnimationController(duration: const Duration(milliseconds: 800), vsync: this);
    _floatController = AnimationController(duration: const Duration(milliseconds: 2000), vsync: this);

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
    _buttonScale = Tween<double>(begin: 1.0, end: 0.95).animate(CurvedAnimation(parent: _buttonController, curve: Curves.easeInOut));
    _successScale = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _successController, curve: Curves.elasticOut));
    _floatAnimation = Tween<double>(begin: -3.0, end: 3.0).animate(CurvedAnimation(parent: _floatController, curve: Curves.easeInOutSine));

    _fadeController.forward();
    _floatController.repeat(reverse: true);
  }

  Future<void> _fetchCurrentCartQuantity() async {
    final user = supabase.auth.currentUser;
    if (user == null || _product == null || _selectedService.isEmpty) return;

    try {
      // Check if the selected service is a wash service
      final selectedServiceId = _services.firstWhere(
            (s) => s['name'] == _selectedService,
        orElse: () => {'id': ''},
      )['id']?.toString() ?? '';

      final washDetails = await _getWashServiceDetails(selectedServiceId);
      final isWashService = washDetails != null;

      // For wash services, we need to check both regular and heavy wash types
      final response = await supabase
          .from('cart')
          .select('id, product_quantity, service_type')
          .eq('user_id', user.id)
          .eq('product_id', _product!['id'].toString())
          .ilike('service_type', '$_selectedService%'); // Use ilike to match with or without wash type

      int totalQuantity = 0;

      for (final item in response) {
        final serviceType = item['service_type'] as String? ?? '';
        final quantity = item['product_quantity'] as int? ?? 0;

        if (isWashService) {
          // For wash services, count all items with this service (any wash type)
          totalQuantity += quantity;
        } else {
          // For non-wash services, only count exact matches
          if (serviceType == _selectedService) {
            totalQuantity += quantity;
          }
        }
      }

      setState(() {
        _currentCartQuantity = totalQuantity;
        _quantity = totalQuantity;
      });
    } catch (_) {
      setState(() {
        _currentCartQuantity = 0;
        _quantity = 0;
      });
    }
  }

  // NEW: Method to check if a service is a wash service (has heavy wash price)
  Future<Map<String, dynamic>?> _getWashServiceDetails(String serviceId) async {
    try {
      final response = await supabase
          .from('product_service_prices')
          .select('regular_wash_price, heavy_wash_price')
          .eq('product_id', widget.productId)
          .eq('service_id', serviceId)
          .maybeSingle();

      if (response != null) {
        final regularPrice = (response['regular_wash_price'] as num?)?.toInt();
        final heavyPrice = (response['heavy_wash_price'] as num?)?.toInt();

        if (regularPrice != null && heavyPrice != null) {
          return {
            'regular_price': regularPrice,
            'heavy_price': heavyPrice,
          };
        }
      }
    } catch (e) {
      debugPrint('Error fetching wash service details: $e');
    }
    return null;
  }



  // Replace the existing _showWashTypeSelection method with this:

  Future<void> _showWashTypeSelection(String serviceId, String serviceName) async {
    if (!mounted) return;

    final washDetails = await _getWashServiceDetails(serviceId);

    if (washDetails == null) {
      // Not a wash service, directly add to cart
      await _addToCartDirectly();
      return;
    }

    // ✅ GET BASE SERVICE PRICE (the service's normal price like ₹20 for Wash & Fold)
    final baseServicePrice = _services.firstWhere(
          (s) => s['id'] == serviceId,
      orElse: () => {'price': 0},
    )['price'] as int;

    // ✅ CALCULATE PRICES CORRECTLY:
    // Regular Wash = Base price only (₹20)
    final regularPrice = baseServicePrice;

    // Heavy Wash = Base price + Heavy wash additional charge (₹20 + ₹15 = ₹35)
    final heavyWashAdditionalCharge = (washDetails['heavy_price'] as int);
    final heavyPrice = baseServicePrice + heavyWashAdditionalCharge;

    await showModalBottomSheet(
      context: context,
      backgroundColor: DobifyColors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: DobifyColors.yellow, width: 1.2),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle at top
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: DobifyColors.yellow,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              const Text(
                'Select Wash Type',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: DobifyColors.yellow,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                serviceName,
                style: const TextStyle(
                  fontSize: 14,
                  color: DobifyColors.yellow,
                ),
              ),
              const SizedBox(height: 20),

              // Regular Wash Option
              InkWell(
                onTap: () {
                  Navigator.pop(context);
                  _addToCartWithWashType('Regular Wash', regularPrice);
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: DobifyColors.black,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: DobifyColors.yellow, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: DobifyColors.yellow.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.water_drop_outlined,
                          color: DobifyColors.yellow,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Regular Wash',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: DobifyColors.yellow,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Standard cleaning',
                              style: TextStyle(
                                fontSize: 12,
                                color: DobifyColors.yellow,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '₹$regularPrice',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: DobifyColors.yellow,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Heavy Wash Option
              InkWell(
                onTap: () {
                  Navigator.pop(context);
                  _addToCartWithWashType('Heavy Wash', heavyPrice);
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: DobifyColors.black,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.water_damage,
                          color: Colors.orange,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Heavy Wash',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Deep cleaning (+₹$heavyWashAdditionalCharge extra)',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '₹$heavyPrice',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Cancel Button
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 16,
                    color: DobifyColors.yellow,
                  ),
                ),
              ),

              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
        );
      },
    );
  }



  // NEW: Add to cart with wash type
  Future<void> _addToCartWithWashType(String washType, int price) async {
    // Store the original quantity
    final originalQuantity = _quantity;

    // Update the selected service price with the wash type price
    setState(() {
      _selectedServicePrice = price;
    });

    // Call the existing add to cart method
    await _addToCartDirectly(washType: washType);

    // Restore the quantity (in case it was changed)
    if (mounted) {
      setState(() {
        _quantity = originalQuantity;
      });
    }
  }



  // MODIFIED: Direct add to cart with optional wash type
  Future<void> _addToCartDirectly({String? washType}) async {
    final user = supabase.auth.currentUser;
    if (user == null || _product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: DobifyColors.black,
          content: Text('Please login to add items to cart', style: TextStyle(color: DobifyColors.yellow)),
        ),
      );
      return;
    }
    if (_selectedService.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: DobifyColors.black,
          content: Text('Please select a service', style: TextStyle(color: DobifyColors.yellow)),
        ),
      );
      return;
    }

    setState(() => _isAddingToCart = true);
    _buttonController.forward();

    try {
      final productId = _product!['id'].toString();
      final name = _product!['product_name'];
      final image = _product!['image_url'] ?? '';
      final category = _product!['categories']?['name'] ?? 'General';

      // Use the current selected service price (which may have been updated for wash type)
      final finalPrice = _selectedServicePrice;
      final totalPrice = finalPrice * _quantity;

      // Get the selected service ID
      final selectedServiceId = _services.firstWhere(
            (s) => s['name'] == _selectedService,
        orElse: () => {'id': ''},
      )['id']?.toString() ?? '';

      // Prepare service type with wash type
      final bool isWashService = washType != null;
      final String fullServiceType = isWashService
          ? '$_selectedService - $washType'
          : _selectedService;

      // Check for existing item with same service type (including wash type)
      final existing = await supabase
          .from('cart')
          .select('*')
          .eq('user_id', user.id)
          .eq('product_id', productId)
          .eq('service_id', selectedServiceId)
          .eq('service_type', fullServiceType) // Match exact service type
          .maybeSingle();

      if (existing != null) {
        if (_quantity <= 0) {
          await supabase.from('cart').delete().eq('id', existing['id']);
          setState(() {
            _currentCartQuantity = 0;
            _addedToCart = true;
          });
        } else {
          await supabase.from('cart').update({
            'product_quantity': _quantity,
            'total_price': totalPrice,
          }).eq('id', existing['id']);
          setState(() {
            _currentCartQuantity = _quantity;
            _addedToCart = true;
          });
        }
      } else {
        if (_quantity > 0) {
          await supabase.from('cart').insert({
            'user_id': user.id,
            'product_id': productId,
            'product_name': name,
            'product_price': finalPrice.toDouble(),
            'product_image': image,
            'category': category,
            'service_id': selectedServiceId,
            'service_type': fullServiceType, // Store with wash type
            'wash_type': isWashService ? washType : null, // Store wash type separately
            'service_price': 0.0,
            'product_quantity': _quantity,
            'total_price': totalPrice,
          });
          setState(() {
            _currentCartQuantity = _quantity;
            _addedToCart = true;
          });
        } else {
          setState(() {
            _currentCartQuantity = 0;
            _addedToCart = true;
          });
        }
      }

      _successController.forward();
      await _updateCartCount();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: DobifyColors.black,
            content: Text('Cart updated!', style: TextStyle(color: DobifyColors.yellow)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) {
        setState(() => _addedToCart = false);
        _successController.reset();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: DobifyColors.black,
            content: Text('Error updating cart: $e', style: const TextStyle(color: DobifyColors.yellow)),
          ),
        );
      }
    } finally {
      setState(() => _isAddingToCart = false);
      _buttonController.reverse();
    }
  }

  void _onCartCountChanged() async => _fetchCurrentCartQuantity();

  Future<void> _addToCart() async {
    final user = supabase.auth.currentUser;
    if (user == null || _product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: DobifyColors.black,
          content: Text('Please login to add items to cart', style: TextStyle(color: DobifyColors.yellow)),
        ),
      );
      return;
    }
    if (_selectedService.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: DobifyColors.black,
          content: Text('Please select a service', style: TextStyle(color: DobifyColors.yellow)),
        ),
      );
      return;
    }

    // Get the selected service ID
    final selectedServiceId = _services.firstWhere(
          (s) => s['name'] == _selectedService,
      orElse: () => {'id': ''},
    )['id']?.toString() ?? '';

    // Check if this is a wash service
    final washDetails = await _getWashServiceDetails(selectedServiceId);

    if (washDetails != null) {
      // Show wash type selection for wash services
      await _showWashTypeSelection(selectedServiceId, _selectedService);
    } else {
      // Directly add for non-wash services
      await _addToCartDirectly();
    }
  }

  Future<void> _updateCartCount() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final data = await supabase
          .from('cart')
          .select('product_quantity')
          .eq('user_id', user.id);
      final totalCount =
      data.fold<int>(0, (sum, item) => sum + (item['product_quantity'] as int? ?? 0));
      cartCountNotifier.value = totalCount;
    } catch (_) {}
  }

  @override
  void dispose() {
    cartCountNotifier.removeListener(_onCartCountChanged);
    _fadeController.dispose();
    _buttonController.dispose();
    _successController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  // UI

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: DobifyColors.black,
        appBar: AppBar(
          backgroundColor: DobifyColors.black,
          foregroundColor: DobifyColors.yellow,
          title: const Text('Loading...'),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: DobifyColors.yellow),
        ),
      );
    }

    if (_product == null) {
      return Scaffold(
        backgroundColor: DobifyColors.black,
        appBar: AppBar(
          backgroundColor: DobifyColors.black,
          foregroundColor: DobifyColors.yellow,
          title: const Text('Product Not Found'),
        ),
        body: const Center(
          child: Text('Product not found', style: TextStyle(color: DobifyColors.yellow)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: DobifyColors.black,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: DobifyColors.black,
        foregroundColor: DobifyColors.yellow,
        title: Text(_product!['product_name'] ?? 'Product'),
      ),
      body: AnimatedBuilder(
        animation: _fadeAnimation,
        builder: (context, child) {
          return FadeTransition(
            opacity: _fadeAnimation,
            child: SafeArea(
              bottom: true,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildImage(),
                    const SizedBox(height: 16),
                    _buildServiceSelection(),
                    const SizedBox(height: 16),
                    _buildInfo(),
                    const SizedBox(height: 20),
                    _buildQuantity(),
                    const SizedBox(height: 20),
                    _buildAddButton(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildImage() {
    return AnimatedBuilder(
      animation: _floatAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _floatAnimation.value),
          child: Container(
            decoration: BoxDecoration(
              color: DobifyColors.black,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DobifyColors.yellow, width: 1.2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 1,
                child: Image.network(
                  _product!['image_url'] ?? '',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                  const Center(child: Icon(Icons.image_not_supported, color: DobifyColors.yellow, size: 40)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfo() {
    final singleItemPrice = _selectedServicePrice; // Price already includes everything

    final selectedService = _services.firstWhere(
          (s) => s['name'] == _selectedService,
      orElse: () => {'service_full_description': 'No description available', 'service_description': '', 'id': ''},
    );

    final selectedServiceDesc = selectedService['service_full_description'] ?? 'No description available';
    final serviceDescription = selectedService['service_description'] ?? '';
    final selectedServiceId = selectedService['id'] ?? '';
    final isCurrentServiceRecommended = _isRecommendedService(selectedServiceId.toString());

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DobifyColors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DobifyColors.yellow, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // price + tag
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: DobifyColors.yellow,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.currency_rupee, size: 14, color: DobifyColors.black),
                    Text(
                      '$singleItemPrice',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: DobifyColors.black),
                    ),
                  ],
                ),
              ),
              if (isCurrentServiceRecommended)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: DobifyColors.yellow,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Recommended',
                    style: TextStyle(color: DobifyColors.black, fontWeight: FontWeight.w700, fontSize: 11),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (serviceDescription.toString().isNotEmpty)
            Text(
              serviceDescription,
              style: const TextStyle(fontSize: 14, color: DobifyColors.yellow, fontWeight: FontWeight.w700),
            ),
          const SizedBox(height: 8),
          Text(
            selectedServiceDesc,
            style: TextStyle(fontSize: 14, color: DobifyColors.yellow.withOpacity(0.85), height: 1.5),
            textAlign: TextAlign.justify,
          ),
        ],
      ),
    );
  }

  Widget _buildServiceSelection() {
    if (_services.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: DobifyColors.black,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DobifyColors.yellow, width: 1.2),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: DobifyColors.yellow, size: 20),
            SizedBox(width: 12),
            Expanded(child: Text('Loading services...', style: TextStyle(color: DobifyColors.yellow))),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Select Service',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: DobifyColors.yellow)),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _services.map((service) {
              final String name = (service['name'] ?? '').toString();
              final int price = (service['price'] as num?)?.toInt() ?? 0;
              final bool selected = _selectedService == name;

              return Container(
                margin: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () => setState(() {
                    _selectedService = name;
                    _selectedServicePrice = price;
                    _fetchCurrentCartQuantity();
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected ? DobifyColors.yellow : DobifyColors.black,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: DobifyColors.yellow, width: 1.2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.local_laundry_service,
                            size: 16, color: selected ? DobifyColors.black : DobifyColors.yellow),
                        const SizedBox(width: 8),
                        Text(
                          name,
                          style: TextStyle(
                            color: selected ? DobifyColors.black : DobifyColors.yellow,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildQuantity() {
    final totalPrice = _selectedServicePrice * _quantity;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DobifyColors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DobifyColors.yellow, width: 1.2),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // quantity controls
              Row(
                children: [
                  const Text('Quantity',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: DobifyColors.yellow)),
                  const SizedBox(width: 16),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => setState(() {
                          if (_quantity > 0) _quantity--;
                        }),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _quantity > 0 ? DobifyColors.yellow : Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(color: DobifyColors.yellow, width: 1.2),
                          ),
                          child: Icon(Icons.remove,
                              color: _quantity > 0 ? DobifyColors.black : DobifyColors.yellow, size: 16),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: DobifyColors.yellow, width: 1.2),
                        ),
                        child: Text(
                          '$_quantity',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: DobifyColors.yellow),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _quantity++),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: DobifyColors.yellow,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.add, color: DobifyColors.black, size: 16),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // total price
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Total', style: TextStyle(fontSize: 12, color: DobifyColors.yellow)),
                  Text('₹$totalPrice',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: DobifyColors.yellow)),
                ],
              ),
            ],
          ),
          if (_currentCartQuantity > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DobifyColors.yellow, width: 1.2),
              ),
              child: Text(
                'Currently in cart: $_currentCartQuantity item${_currentCartQuantity > 1 ? 's' : ''} with $_selectedService',
                style: const TextStyle(fontSize: 12, color: DobifyColors.yellow),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAddButton() {
    final bool hasChanged = _currentCartQuantity != _quantity;
    final bool isInCart = _currentCartQuantity > 0;

    return AnimatedBuilder(
      animation: Listenable.merge([_buttonController, _successController]),
      builder: (_, __) {
        return Transform.scale(
          scale: _addedToCart ? _successScale.value : _buttonScale.value,
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: (_isAddingToCart || !hasChanged) ? null : _addToCart,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                _addedToCart ? Colors.green : (hasChanged ? DobifyColors.yellow : Colors.grey.shade700),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _isAddingToCart
                  ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _addedToCart
                        ? Icons.check_circle_rounded
                        : (isInCart ? Icons.refresh_rounded : Icons.shopping_cart_rounded),
                    color: _addedToCart ? Colors.white : DobifyColors.black,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _addedToCart
                        ? 'Updated!'
                        : (hasChanged ? (isInCart ? 'Update Cart' : 'Add to Cart') : 'No Changes'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _addedToCart ? Colors.white : DobifyColors.black,
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
}
