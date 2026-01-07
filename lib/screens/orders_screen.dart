import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart';
import '../colors.dart';
import '../utils/globals.dart';
import 'product_details_screen.dart';

class OrdersScreen extends StatefulWidget {
  final String? category;
  const OrdersScreen({Key? key, this.category}) : super(key: key);

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final supabase = Supabase.instance.client;

  List<Map<String, String>> _categories = const [{'id': 'ALL', 'name': 'All'}];
  String _selectedCategoryId = 'ALL';
  final Map<String, String> _categoryNameById = {};
  final List<Map<String, dynamic>> _products = [];
  final Map<String, int> _productQuantities = {};
  final Map<String, AnimationController> _controllers = {};
  final Map<String, AnimationController> _qtyAnimControllers = {};
  final Map<String, bool> _addedStatus = {};

  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _categoryKeys = {};

  bool _isLoading = false;

  final TextEditingController _searchController = TextInputController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _showSearchSuggestions = false;
  String _searchQuery = '';
  List<Map<String, dynamic>> _searchSuggestions = [];
  late AnimationController _searchAnimationController;
  late Animation<double> _searchSlideAnimation;
  late Animation<double> _searchFadeAnimation;

  bool _hasFetchedProducts = false;
  List<Map<String, dynamic>> _cachedProducts = [];
  List<Map<String, String>> _cachedCategories = const [{'id': 'ALL', 'name': 'All'}];

  @override
  void initState() {
    super.initState();

    _searchAnimationController =
        AnimationController(duration: const Duration(milliseconds: 300), vsync: this);
    _searchSlideAnimation = Tween<double>(begin: -1.0, end: 0.0).animate(
      CurvedAnimation(parent: _searchAnimationController, curve: Curves.easeOutCubic),
    );
    _searchFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _searchAnimationController, curve: Curves.easeOut),
    );

    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(_onSearchFocusChanged);

    _loadCategoriesForTabs().then((_) async {
      await _fetchCategoriesAndProducts();
      if (widget.category != null && widget.category!.trim().isNotEmpty) {
        final name = widget.category!.trim();
        final found = _categories.firstWhere(
              (c) => c['name'] == name,
          orElse: () => const {'id': 'ALL', 'name': 'All'},
        );
        if (mounted) {
          setState(() => _selectedCategoryId = found['id'] ?? 'ALL');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _centerSelectedCategoryByName(found['name'] ?? 'All');
          });
        }
      }
    });

    _fetchCartData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final c in _qtyAnimControllers.values) {
      c.dispose();
    }
    _scrollController.dispose();
    _searchAnimationController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
      _generateSearchSuggestions();
      _showSearchSuggestions = _searchController.text.isNotEmpty;
    });
  }

  void _onSearchFocusChanged() {
    if (_searchFocusNode.hasFocus && _searchController.text.isNotEmpty) {
      setState(() => _showSearchSuggestions = true);
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _showSearchSuggestions = false;
    });
  }

  void _generateSearchSuggestions() {
    if (_searchQuery.isEmpty) {
      _searchSuggestions.clear();
      return;
    }
    final query = _searchQuery.toLowerCase();
    _searchSuggestions = _products
        .where((product) => product['product_name'].toString().toLowerCase().contains(query))
        .take(8)
        .toList();
  }

  Future<void> _loadCategoriesForTabs() async {
    try {
      final rows = await supabase
          .from('categories')
          .select('id,name,is_active')
          .eq('is_active', true)
          .order('sort_order', ascending: true);

      final list = <Map<String, String>>[
        {'id': 'ALL', 'name': 'All'}
      ];

      for (final r in List<Map<String, dynamic>>.from(rows ?? [])) {
        final id = (r['id'] ?? '').toString();
        final name = (r['name'] ?? '').toString().trim();
        if (id.isEmpty || name.isEmpty) continue;
        list.add({'id': id, 'name': name});
        _categoryNameById[id] = name;
      }

      if (mounted && list.length > 1) {
        setState(() => _categories = list);
        _cachedCategories = List<Map<String, String>>.from(list);
      }
    } catch (_) {}
  }

  Future<void> _fetchCategoriesAndProducts() async {
    if (mounted) setState(() => _isLoading = true);

    bool _truthy(dynamic v) {
      if (v == null) return false;
      if (v is bool) return v;
      if (v is num) return v != 0;
      final s = v.toString().toLowerCase().trim();
      return s == 'true' || s == '1' || s == 'yes';
    }

    bool _explicitlyDisabled(dynamic v) {
      if (v == null) return false;
      if (v is bool) return v == false;
      if (v is num) return v == 0;
      final s = v.toString().toLowerCase().trim();
      return s == 'false' || s == '0' || s == 'no';
    }

    bool _visible(Map<String, dynamic> p) {
      final hasEnabled = p.containsKey('is_enabled');
      final hasActive = p.containsKey('is_active');
      if (!hasEnabled && !hasActive) return true;
      if (_explicitlyDisabled(p['is_enabled']) || _explicitlyDisabled(p['is_active'])) {
        return false;
      }
      return _truthy(p['is_enabled']) || _truthy(p['is_active']) || (!hasEnabled && !hasActive);
    }

    try {
      final resp = await supabase
          .from('products')
          .select(
          'id, product_name, image_url, category_id, created_at, sort_order, tag, '
              'is_enabled, is_active, categories:category_id(name)'
      )
          .order('sort_order', ascending: true)
          .order('product_name', ascending: true);

      final all = List<Map<String, dynamic>>.from(resp ?? []);
      final visible = all.where(_visible).toList();

      _products
        ..clear()
        ..addAll(visible);

      _cachedProducts = List<Map<String, dynamic>>.from(_products);
      _hasFetchedProducts = true;
    } catch (e) {
      try {
        final resp = await supabase
            .from('products')
            .select('*')
            .order('sort_order', ascending: true)
            .order('created_at', ascending: false);

        final all = List<Map<String, dynamic>>.from(resp ?? []);
        final visible = all.where(_visible).toList();

        _products
          ..clear()
          ..addAll(visible);

        _cachedProducts = List<Map<String, dynamic>>.from(_products);
        _hasFetchedProducts = true;
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _centerSelectedCategoryByName(String name) {
    final key = _categoryKeys[name];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  Future<void> _fetchCartData() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final data = await supabase
          .from('cart')
          .select('product_id, product_quantity')
          .eq('user_id', user.id);

      _productQuantities.clear();

      for (final item in data) {
        final pid = (item['product_id'] ?? '').toString();
        if (pid.isEmpty) continue;
        final quantity = item['product_quantity'] as int? ?? 0;
        _productQuantities[pid] = (_productQuantities[pid] ?? 0) + quantity;
      }

      final totalCount =
      _productQuantities.values.fold<int>(0, (sum, qty) => sum + qty);
      cartCountNotifier.value = totalCount;

      if (mounted) setState(() {});
    } catch (_) {}
  }

  List<Map<String, dynamic>> _getFilteredProducts() {
    List<Map<String, dynamic>> filteredProducts;

    if (_selectedCategoryId == 'ALL') {
      filteredProducts = _products;
    } else {
      filteredProducts = _products
          .where((p) => (p['category_id']?.toString() ?? '') == _selectedCategoryId)
          .toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filteredProducts = filteredProducts
          .where((product) => product['product_name'].toString().toLowerCase().contains(query))
          .toList();
    }

    filteredProducts.sort((a, b) {
      final aOrder = (a['sort_order'] as int?) ?? 999;
      final bOrder = (b['sort_order'] as int?) ?? 999;
      if (aOrder != bOrder) return aOrder.compareTo(bOrder);

      final aName = (a['product_name'] as String?) ?? '';
      final bName = (b['product_name'] as String?) ?? '';
      return aName.compareTo(bName);
    });

    return filteredProducts;
  }

  Future<void> _onRefresh() async {
    await _fetchCategoriesAndProducts();
    await _fetchCartData();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: DobifyColors.black,
      appBar: _buildStoreAppBar(),
      body: Column(
        children: [
          const SizedBox(height: 12),
          _buildStoreCategoryTabs(),
          const SizedBox(height: 16),
          Expanded(
            child: RefreshIndicator(
              color: DobifyColors.yellow,
              backgroundColor: DobifyColors.black,
              onRefresh: _onRefresh,
              child: Stack(
                children: [
                  _buildContent(),
                  if (_showSearchSuggestions && _searchSuggestions.isNotEmpty)
                    _buildSearchSuggestions(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildStoreAppBar() {
    return AppBar(
      backgroundColor: DobifyColors.black,
      title: SafeArea(
        bottom: false,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(25),
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: DobifyColors.black,
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: DobifyColors.yellow, width: 1.2),
            ),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              textAlignVertical: TextAlignVertical.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: DobifyColors.yellow,
                height: 1.2,
              ),
              cursorColor: DobifyColors.yellow,
              decoration: InputDecoration(
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: const BorderSide(color: Colors.transparent, width: 0),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: const BorderSide(color: Colors.transparent, width: 0),
                ),
                filled: true,
                fillColor: Colors.transparent,
                isCollapsed: true,
                contentPadding: const EdgeInsets.only(top: 1),
                hintText: 'Search Products...',
                hintStyle: TextStyle(
                  fontSize: 15,
                  color: DobifyColors.yellow.withOpacity(0.7),
                  fontWeight: FontWeight.w400,
                  height: 1.2,
                ),
                prefixIcon: const SizedBox(
                  width: 42, height: 42,
                  child: Center(
                    child: Icon(Icons.search, size: 20, color: DobifyColors.yellow),
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 42),
                suffixIcon: (_searchQuery.isNotEmpty)
                    ? SizedBox(
                  width: 42,
                  height: 42,
                  child: Center(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(21),
                      onTap: _clearSearch,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: DobifyColors.yellow,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, size: 14, color: DobifyColors.black),
                      ),
                    ),
                  ),
                )
                    : null,
                suffixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 42),
              ),
              onChanged: (_) {
                setState(() {
                  _searchQuery = _searchController.text;
                  _generateSearchSuggestions();
                  _showSearchSuggestions = _searchController.text.isNotEmpty;
                });
              },
              onSubmitted: (_) {
                setState(() => _showSearchSuggestions = false);
                _searchFocusNode.unfocus();
              },
            ),
          ),
        ),
      ),
      actions: const [
        SizedBox(width: 8),
      ],
    );
  }

  Widget _buildStoreCategoryTabs() {
    return SizedBox(
      height: 50,
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = _selectedCategoryId == cat['id'];

          final key = _categoryKeys.putIfAbsent(cat['name']!, () => GlobalKey());

          return GestureDetector(
            onTap: () {
              setState(() => _selectedCategoryId = cat['id']!);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _centerSelectedCategoryByName(cat['name']!);
              });
            },
            child: Container(
              key: key,
              margin: const EdgeInsets.only(right: 12, top: 4, bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              constraints: const BoxConstraints(minWidth: 80),
              decoration: BoxDecoration(
                color: isSelected ? DobifyColors.yellow : DobifyColors.black,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: DobifyColors.yellow, width: 1.2),
              ),
              child: Center(
                child: Text(
                  cat['name']!,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: isSelected ? DobifyColors.black : DobifyColors.yellow,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent() {
    final products = _getFilteredProducts();

    if (_isLoading) {
      return ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator(color: DobifyColors.yellow)),
          SizedBox(height: 16),
          Center(
            child: Text(
              'Loading products...',
              style: TextStyle(fontSize: 16, color: DobifyColors.yellow),
            ),
          ),
          SizedBox(height: 120),
        ],
      );
    }

    if (products.isEmpty) {
      return ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: const [
          SizedBox(height: 120),
          Icon(Icons.shopping_bag_outlined, size: 80, color: DobifyColors.yellow),
          SizedBox(height: 16),
          Center(
            child: Text(
              'No products found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: DobifyColors.yellow,
              ),
            ),
          ),
          SizedBox(height: 24),
          SizedBox(height: 120),
        ],
      );
    }

    return _buildProductGrid(context, products);
  }

  Widget _buildProductGrid(BuildContext context, List<Map<String, dynamic>> products) {
    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: products.length,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 10, childAspectRatio: 0.75,
      ),
      itemBuilder: (ctx, idx) {
        final item = products[idx];
        final productId = (item['id'] ?? '').toString();
        final name = item['product_name'] ?? '';
        final qty = _productQuantities[productId] ?? 0;

        _controllers[productId] ??= AnimationController(
          vsync: this, duration: const Duration(milliseconds: 150), lowerBound: 0.95, upperBound: 1.05,
        )..addStatusListener((status) { if (status == AnimationStatus.completed) { _controllers[productId]?.reverse(); } });

        _qtyAnimControllers[productId] ??= AnimationController(
          vsync: this, duration: const Duration(milliseconds: 200), lowerBound: 0.9, upperBound: 1.1,
        );

        return ScaleTransition(
          scale: _controllers[productId]!,
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ProductDetailsScreen(productId: item['id'])),
              );
            },
            child: Container(
              decoration: BoxDecoration(
                color: DobifyColors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: DobifyColors.yellow, width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: DobifyColors.black,
                        border: Border.all(color: DobifyColors.yellow.withOpacity(0.5), width: 1),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          item['image_url'] ?? '',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => const Icon(
                            Icons.image_outlined, size: 40, color: DobifyColors.yellow,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13, color: DobifyColors.yellow, height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (qty > 0)
                          ScaleTransition(
                            scale: _qtyAnimControllers[productId]!,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: DobifyColors.yellow, borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('$qty in cart',
                                  style: const TextStyle(
                                      color: DobifyColors.black, fontWeight: FontWeight.w700, fontSize: 12)),
                            ),
                          ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity, height: 36,
                          child: _buildProductButton(item, productId),
                        ),
                      ],
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

  Widget _buildProductButton(Map<String, dynamic> item, String productId) {
    if (_addedStatus[productId] == true) {
      return Container(
        decoration: BoxDecoration(color: DobifyColors.yellow, borderRadius: BorderRadius.circular(12)),
        child: const Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: DobifyColors.black, size: 16),
              SizedBox(width: 6),
              Text('Added!', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: DobifyColors.black)),
            ],
          ),
        ),
      );
    }

    return ElevatedButton(
      onPressed: () => _showServiceSelectionPopup(item),
      style: ElevatedButton.styleFrom(
        backgroundColor: DobifyColors.yellow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0, padding: EdgeInsets.zero,
      ),
      child: const Text('Add', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: DobifyColors.black)),
    );
  }

  // NEW: Fetch product-specific service prices with wash type support
  Future<void> _showServiceSelectionPopup(Map<String, dynamic> product) async {
    final productId = (product['id'] ?? '').toString();
    if (productId.isEmpty) return;

    try {
      // Fetch available services with their prices for this specific product
      final resp = await supabase
          .from('product_service_prices')
          .select('*, services:service_id(id, name, service_description, icon, color_hex)')
          .eq('product_id', productId)
          .eq('is_available', true)
          .order('price', ascending: true);

      final servicePrices = List<Map<String, dynamic>>.from(resp ?? []);

      if (servicePrices.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: DobifyColors.black,
              content: Text('No services available for this product',
                  style: TextStyle(color: DobifyColors.yellow)),
            ),
          );
        }
        return;
      }

      final productName = product['product_name'] ?? '';

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return Dialog(
            backgroundColor: DobifyColors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: DobifyColors.yellow, width: 1.2),
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              constraints: const BoxConstraints(maxWidth: 320, maxHeight: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Choose Service',
                      style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800, color: DobifyColors.yellow,
                      )),
                  const SizedBox(height: 8),
                  Text(
                    'Select service for $productName',
                    style: const TextStyle(fontSize: 13, color: DobifyColors.yellow),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: servicePrices.length,
                      itemBuilder: (context, index) {
                        final priceData = servicePrices[index];
                        final serviceData = priceData['services'];

                        final serviceId = serviceData['id']?.toString() ?? '';
                        final serviceName = serviceData['name'] ?? '';

                        // Get BASE service price (this is what shows in Regular Wash)
                        final int basePrice = (priceData['price'] as num?)?.toInt() ??
                            (priceData['regular_wash_price'] as num?)?.toInt() ?? 0;

                        // Get SURCHARGE for heavy wash (additional amount to add to base price)
                        final int? heavySurcharge = (priceData['heavy_wash_surcharge'] as num?)?.toInt() ??
                            (priceData['heavy_wash_price'] as num?)?.toInt();

                        // Calculate final heavy wash price (base + surcharge)
                        final int? finalHeavyPrice = heavySurcharge != null ? (basePrice + heavySurcharge) : null;

                        final description = (serviceData['service_description'] ?? '').toString();

                        return GestureDetector(
                          onTap: () async {
                            Navigator.pop(context);
                            // Show wash type selection - pass basePrice and finalHeavyPrice
                            await _showWashTypeSelection(
                                product, serviceId, serviceName, basePrice, finalHeavyPrice, priceData);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: DobifyColors.black,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: DobifyColors.yellow, width: 1),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.local_laundry_service,
                                    color: DobifyColors.yellow, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        serviceName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13.5,
                                          color: DobifyColors.yellow,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                      const SizedBox(height: 4),
                                      if (description.isNotEmpty)
                                        Text(
                                          description,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: DobifyColors.yellow.withOpacity(0.85),
                                          ),
                                          maxLines: 2, overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'From ₹$basePrice',
                                  style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.bold, color: DobifyColors.yellow,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(color: DobifyColors.yellow)),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: DobifyColors.black,
          content: Text('Failed to load services: $e',
              style: const TextStyle(color: DobifyColors.yellow)),
        ),
      );
    }
  }


  // NEW: Show wash type selection modal
  Future<void> _showWashTypeSelection(
      Map<String, dynamic> product,
      String serviceId,
      String serviceName,
      int regularPrice,
      int? heavyPrice,
      Map<String, dynamic> priceData) async {
    if (!mounted) return;

    // Check if this is a wash service by checking if it has heavyPrice
    final isWashService = serviceName.toLowerCase().contains('wash') && heavyPrice != null;

    // If NOT a wash service, directly add to cart with service name
    if (!isWashService) {
      await _addToCartWithService(product, serviceId, serviceName, regularPrice, serviceName);
      return;
    }

    // If IS a wash service (and has heavyPrice), show the wash type selection modal
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
                  _addToCartWithService(product, serviceId, serviceName, regularPrice, 'Regular Wash');
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
                  _addToCartWithService(product, serviceId, serviceName, heavyPrice!, 'Heavy Wash');
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
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Heavy Wash',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Deep cleaning for tough stains',
                              style: TextStyle(
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

  // UPDATED: Add to cart with product-specific service price and wash type
  Future<void> _addToCartWithService(
      Map<String, dynamic> product,
      String serviceId,
      String serviceName,
      int finalPrice,
      String washType) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: DobifyColors.black,
            content: Text('Please login to add items to cart',
                style: TextStyle(color: DobifyColors.yellow)),
          ),
        );
      }
      return;
    }

    final productId = (product['id'] ?? '').toString();
    if (productId.isEmpty) return;

    final name = product['product_name'] ?? '';
    final image = product['image_url'] ?? '';
    final categoryId = (product['category_id'] ?? '').toString();
    final categoryName = _categoryNameById[categoryId] ?? (product['categories']?['name'] ?? '');

    try {
      if (mounted) setState(() => _addedStatus[productId] = true);

      // Determine if this is a wash service
      final bool isWashService = washType.contains('Wash');

      // Prepare service type with wash type
      final String fullServiceType = isWashService
          ? '$serviceName - $washType'
          : serviceName;

      // Check if item already exists in cart
      final existing = await supabase
          .from('cart')
          .select('*')
          .eq('user_id', user.id)
          .eq('product_id', productId)
          .eq('service_id', serviceId)
          .eq('service_type', fullServiceType) // Match exact service type including wash type
          .maybeSingle();

      if (existing != null) {
        // Update existing cart item
        final newQty = (existing['product_quantity'] as int) + 1;
        final newTotalPrice = finalPrice * newQty;
        await supabase
            .from('cart')
            .update({
          'product_quantity': newQty,
          'total_price': newTotalPrice,
        })
            .eq('id', existing['id']);
      } else {
        // Insert new cart item
        await supabase.from('cart').insert({
          'user_id': user.id,
          'product_id': productId,
          'product_name': name,
          'product_image': image,
          'product_price': finalPrice.toDouble(), // Store the final price
          'service_id': serviceId,
          'service_type': fullServiceType, // Store with wash type
          'wash_type': isWashService ? washType : null, // Store wash type separately if needed
          'service_price': 0.0, // No separate service price anymore
          'product_quantity': 1,
          'total_price': finalPrice.toDouble(),
          'category': categoryName,
        });
      }

      _productQuantities[productId] = (_productQuantities[productId] ?? 0) + 1;
      _controllers[productId]?.forward(from: 0.0);
      _qtyAnimControllers[productId]?.forward(from: 0.9);

      await _fetchCartData();

      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) setState(() => _addedStatus[productId] = false);
    } catch (e) {
      debugPrint('Error adding to cart: $e');
      if (mounted) setState(() => _addedStatus[productId] = false);
    }
  }

  Widget _buildSearchSuggestions() {
    return Positioned(
      top: 0, left: 16, right: 16,
      child: Material(
        color: DobifyColors.black,
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 300),
          decoration: BoxDecoration(
            color: DobifyColors.black,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: DobifyColors.yellow, width: 1.2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: DobifyColors.black,
                  border: Border(
                    bottom: BorderSide(color: DobifyColors.yellow, width: 1),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lightbulb_outline, color: DobifyColors.yellow, size: 18),
                    SizedBox(width: 8),
                    Text('Suggestions', style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: DobifyColors.yellow,
                    )),
                  ],
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _searchSuggestions.length,
                  separatorBuilder: (_, __) => const Divider(color: DobifyColors.yellow, height: 1),
                  itemBuilder: (context, index) {
                    final product = _searchSuggestions[index];
                    final productName = product['product_name'] as String;
                    final categoryId = (product['category_id'] ?? '').toString();
                    final categoryName = _categoryNameById[categoryId] ?? (product['categories']?['name'] ?? '');
                    final imageUrl = product['image_url'] ?? '';

                    return InkWell(
                      onTap: () {
                        _searchController.text = productName;
                        setState(() {
                          _searchQuery = productName;
                          _showSearchSuggestions = false;
                          _selectedCategoryId = categoryId.isNotEmpty ? categoryId : 'ALL';
                        });
                        _searchFocusNode.unfocus();

                        if (categoryId.isNotEmpty) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _centerSelectedCategoryByName(categoryName.toString());
                          });
                        }
                      },
                      child: Container(
                        color: DobifyColors.black,
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: DobifyColors.yellow),
                                color: DobifyColors.black,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  imageUrl,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.image_outlined,
                                    color: DobifyColors.yellow,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    productName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: DobifyColors.yellow,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  if (categoryName.toString().isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: DobifyColors.yellow,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        categoryName.toString(),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: DobifyColors.black,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward_ios, size: 14, color: DobifyColors.yellow),
                          ],
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
    );
  }
}

class TextInputController extends TextEditingController {}