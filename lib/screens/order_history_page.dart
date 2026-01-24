import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';
import 'dart:async';

import '../widgets/order_skeleton_loader.dart';



class StoreOrderHistoryPage extends StatefulWidget {
  final String storeUserId;

  const StoreOrderHistoryPage({
    super.key,
    required this.storeUserId,
  });

  @override
  State<StoreOrderHistoryPage> createState() => _StoreOrderHistoryPageState();
}

class _StoreOrderHistoryPageState extends State<StoreOrderHistoryPage> {
  final SupabaseClient supabase = Supabase.instance.client;

  List<Map<String, dynamic>> allOrders = [];
  bool isLoading = true;
  String? errorMessage;
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 0;
  final int _pageSize = 15;
  bool isLoadingMore = false;
  bool hasMore = true;
  final Map<String, Map<String, dynamic>> _detailsCache = {};

  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String _searchQuery = '';
  List<Map<String, dynamic>> filteredOrders = [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);  // ADD THIS LINE
    _loadOrders();
    _searchController.addListener(_onSearchChanged);
  }


  // ADD THIS METHOD: Handle search text changes
  void _onSearchChanged() {
    final query = _searchController.text.trim();
    setState(() {
      _searchQuery = query;
      _isSearching = query.isNotEmpty;

      if (query.isEmpty) {
        filteredOrders = List.from(allOrders);
      } else {
        filteredOrders = allOrders.where((order) {
          final customerName = _getCustomerName(order).toLowerCase();
          final orderId = order['id']?.toString().toLowerCase() ?? '';
          return customerName.contains(query.toLowerCase()) ||
              orderId.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

// ADD THIS METHOD: Clear search
  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _isSearching = false;
      filteredOrders = List.from(allOrders);
    });
  }

// UPDATE THIS METHOD: Modify _loadOrders to also update filteredOrders
  Future<void> _loadOrders() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
      _currentPage = 0;
      allOrders.clear();
      filteredOrders.clear(); // ADD THIS LINE
    });

    try {
      // Load ONLY essential fields
      final ordersResponse = await supabase
          .from('orders')
          .select('id, created_at, order_status, total_amount, payment_method, address_details, pickup_date, pickup_slot_display_time, delivery_date, delivery_slot_display_time')
          .eq('store_user_id', widget.storeUserId)
          .order('created_at', ascending: false)
          .limit(_pageSize);

      // Get item counts in single query
      final orderIds = ordersResponse.map((o) => o['id']).toList();
      final itemCounts = await supabase
          .from('order_items')
          .select('order_id')
          .inFilter('order_id', orderIds);

      final Map<String, int> counts = {};
      for (var item in itemCounts) {
        counts[item['order_id'].toString()] = (counts[item['order_id'].toString()] ?? 0) + 1;
      }

      if (mounted) {
        setState(() {
          allOrders = ordersResponse.map((o) {
            final order = Map<String, dynamic>.from(o);
            order['item_count'] = counts[o['id'].toString()] ?? 0;
            return order;
          }).toList();
          filteredOrders = List.from(allOrders); // ADD THIS LINE
          isLoading = false;
          hasMore = ordersResponse.length == _pageSize;
          _currentPage = 1;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = 'Failed to load orders: $e';
          isLoading = false;
        });
      }
    }
  }

// UPDATE THIS METHOD: Modify _loadMoreOrders to also update filteredOrders
  Future<void> _loadMoreOrders() async {
    if (isLoadingMore || !hasMore) return;
    setState(() => isLoadingMore = true);

    try {
      final ordersResponse = await supabase
          .from('orders')
          .select('id, created_at, order_status, total_amount, payment_method, address_details, pickup_date, pickup_slot_display_time, delivery_date, delivery_slot_display_time')
          .eq('store_user_id', widget.storeUserId)
          .order('created_at', ascending: false)
          .range(_currentPage * _pageSize, (_currentPage + 1) * _pageSize - 1);

      final orderIds = ordersResponse.map((o) => o['id']).toList();
      final itemCounts = await supabase
          .from('order_items')
          .select('order_id')
          .inFilter('order_id', orderIds);

      final Map<String, int> counts = {};
      for (var item in itemCounts) {
        counts[item['order_id'].toString()] = (counts[item['order_id'].toString()] ?? 0) + 1;
      }

      if (mounted) {
        setState(() {
          final newOrders = ordersResponse.map((o) {
            final order = Map<String, dynamic>.from(o);
            order['item_count'] = counts[o['id'].toString()] ?? 0;
            return order;
          }).toList();

          allOrders.addAll(newOrders);
          // Update filtered orders based on current search
          if (_searchQuery.isEmpty) {
            filteredOrders.addAll(newOrders);
          } else {
            // Filter the new orders by search query
            final filteredNewOrders = newOrders.where((order) {
              final customerName = _getCustomerName(order).toLowerCase();
              final orderId = order['id']?.toString().toLowerCase() ?? '';
              return customerName.contains(_searchQuery.toLowerCase()) ||
                  orderId.contains(_searchQuery.toLowerCase());
            }).toList();
            filteredOrders.addAll(filteredNewOrders);
          }

          isLoadingMore = false;
          hasMore = ordersResponse.length == _pageSize;
          _currentPage++;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoadingMore = false);
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      if (!isLoadingMore && hasMore) {
        _loadMoreOrders();
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose(); // ADD THIS LINE
    super.dispose();
  }

  String _formatDate(dynamic dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString.toString());
      return DateFormat('dd MMM yyyy, hh:mm a').format(date);
    } catch (e) {
      return 'N/A';
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
      case 'accepted':
      case 'reached':
      case 'received':
      case 'ready_for_delivery':
      case 'delivered':
        return Colors.white;
      case 'cancelled':
        return Colors.grey;
      case 'pending':
        return Colors.white70;
      default:
        return Colors.white60;
    }
  }

  // Replace your existing _showOrderDetails method with this updated version:

  Future<void> _showOrderDetails(Map<String, dynamic> order) async {
    final orderId = order['id'].toString();

    // Check cache first
    if (_detailsCache.containsKey(orderId)) {
      _displayOrderDetails(_detailsCache[orderId]!);
      return;
    }

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    try {
      // Load full details with billing info
      final fullOrder = await supabase
          .from('orders')
          .select('''
          *,
          order_items!inner (
            *,
            products (id, product_name, image_url, product_price, category_id)
          )
        ''')
          .eq('id', orderId)
          .single();

      // Fetch billing details separately
      final billingResponse = await supabase
          .from('order_billing_details')
          .select('*')
          .eq('order_id', orderId)
          .maybeSingle();

      // Process and cache
      Map<String, dynamic> orderData = Map<String, dynamic>.from(fullOrder);

      // Add billing details to order data
      if (billingResponse != null) {
        orderData['billing_details'] = billingResponse;
      }

      if (fullOrder['order_items'] != null) {
        orderData['order_items'] = (fullOrder['order_items'] as List).map((item) {
          Map<String, dynamic> processedItem = Map<String, dynamic>.from(item);
          if (item['products'] != null) {
            processedItem['products'] = {
              'id': item['products']['id'],
              'name': item['products']['product_name'],
              'image_url': item['product_image'] ?? item['products']['image_url'],
              'price': item['products']['product_price'],
              'category_id': item['products']['category_id'],
            };
          }
          return processedItem;
        }).toList();
      }

      _detailsCache[orderId] = orderData;

      if (mounted) {
        Navigator.of(context).pop(); // Close loading
        _displayOrderDetails(orderData);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _displayOrderDetails(Map<String, dynamic> order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StoreOrderDetailsSheet(order: order),
    );
  }

  String _getCustomerName(Map<String, dynamic> order) {
    // Check if we have customer name in the order data
    final Map<String, dynamic>? address = order['address_info'] ?? order['address_details'];

    if (address != null) {
      // Try to get name from various possible fields
      final String? name = address['recipient_name']?.toString() ??
          address['name']?.toString() ??
          address['customer_name']?.toString();

      if (name != null && name.isNotEmpty) {
        // Return first name if full name is long
        if (name.length > 12) {
          final parts = name.split(' ');
          return parts.isNotEmpty ? parts[0] : name.substring(0, 10) + '...';
        }
        return name;
      }
    }

    // Fallback to "Customer" if no name found
    return 'Customer';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: isLoading
          ? const OrderSkeletonLoader()
          : errorMessage != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.white70,
              ),
              const SizedBox(height: 16),
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadOrders,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
        ),
      )
          : Column(
        children: [
          // SEARCH BAR SECTION - ADD THIS
          // SEARCH BAR SECTION
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[800]!),
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Icon(
                      Icons.search,
                      color: Colors.grey[400],
                      size: 20,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search by customer name or order ID...',
                        hintStyle: TextStyle(color: Colors.grey[500]),
                        border: InputBorder.none, // This removes all borders
                        enabledBorder: InputBorder.none, // Remove enabled state border
                        focusedBorder: InputBorder.none, // Remove focused state border
                        disabledBorder: InputBorder.none, // Remove disabled state border
                        errorBorder: InputBorder.none, // Remove error border
                        focusedErrorBorder: InputBorder.none, // Remove focused error border
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      cursorColor: Colors.white,
                    ),
                  ),
                  if (_isSearching)
                    IconButton(
                      onPressed: _clearSearch,
                      icon: Icon(
                        Icons.clear,
                        color: Colors.grey[400],
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ORDER COUNT INDICATOR - ADD THIS
          if (_isSearching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Text(
                    '${filteredOrders.length} order${filteredOrders.length != 1 ? 's' : ''} found',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  if (filteredOrders.isEmpty)
                    TextButton(
                      onPressed: _clearSearch,
                      child: Text(
                        'Clear search',
                        style: TextStyle(
                          color: Colors.blue[300],
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // ORDERS LIST
          Expanded(
            child: filteredOrders.isEmpty && !isLoading
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isSearching
                        ? Icons.search_off
                        : Icons.inbox_outlined,
                    size: 64,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isSearching
                        ? 'No orders found for "$_searchQuery"'
                        : 'No orders yet',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isSearching
                        ? 'Try a different name or order ID'
                        : 'Your order history will appear here',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  if (_isSearching)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: ElevatedButton(
                        onPressed: _clearSearch,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                        ),
                        child: const Text('Clear Search'),
                      ),
                    ),
                ],
              ),
            )
                : RefreshIndicator(
              onRefresh: _loadOrders,
              color: Colors.white,
              backgroundColor: Colors.black,
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: filteredOrders.length + (isLoadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == filteredOrders.length) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    );
                  }
                  return _buildOrderCard(filteredOrders[index], index);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order, int index) {
    final itemCount = order['item_count'] ?? 0;
    final totalAmount = order['total_amount']?.toString() ?? '0.00';
    final createdAt = _formatDate(order['created_at']);
    final orderId = order['id']?.toString() ?? 'N/A';
    final shortOrderId = orderId.length > 8 ? orderId.substring(0, 8) : orderId;
    final orderStatus = order['order_status']?.toString().toUpperCase() ?? 'PENDING';
    final statusColor = _getStatusColor(order['order_status']?.toString() ?? 'pending');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[800]!, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showOrderDetails(order),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.receipt_long,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Order #$shortOrderId',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            orderId.length > 24
                                ? '${orderId.substring(0, 24)}...'
                                : orderId,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusColor.withOpacity(0.3)),
                      ),
                      child: Text(
                        orderStatus,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoBox(
                        Icons.shopping_bag,
                        'Items',
                        '$itemCount',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildInfoBox(
                        Icons.currency_rupee,
                        'Amount',
                        '₹$totalAmount',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Customer name row
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoBox(Icons.access_time, 'Placed', createdAt),
                    ),
                    if (order.containsKey('address_info') || order.containsKey('address_details')) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[850],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[800]!),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.person, size: 20, color: Colors.grey[400]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Customer',
                                      style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                                    ),
                                    Text(
                                      _getCustomerName(order),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () => _showOrderDetails(order),
                    icon: const Icon(Icons.visibility),
                    label: const Text(
                      'View Details',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoBox(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[400]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class StoreOrderDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> order;

  const StoreOrderDetailsSheet({
    super.key,
    required this.order,
  });

  String _formatDate(dynamic dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString.toString());
      return DateFormat('dd MMM yyyy').format(date);
    } catch (e) {
      return 'N/A';
    }
  }

  Future<void> _openGoogleMaps(
      BuildContext context,
      Map<String, dynamic>? address,
      ) async {
    if (address == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No address available')),
      );
      return;
    }

    double? _toDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString().trim());
    }

    final lat = _toDouble(
      address['latitude'] ??
          address['lat'] ??
          address['geo_latitude'] ??
          address['Latitude'],
    );

    final lng = _toDouble(
      address['longitude'] ??
          address['lng'] ??
          address['lon'] ??
          address['long'] ??
          address['geo_longitude'] ??
          address['Longitude'],
    );

    final addressParts = <String>[
      address['address_line_1']?.toString().trim() ?? '',
      address['address_line_2']?.toString().trim() ?? '',
      address['area']?.toString().trim() ??
          address['locality']?.toString().trim() ??
          '',
      address['city']?.toString().trim() ?? '',
      address['state']?.toString().trim() ?? '',
      address['pincode']?.toString().trim() ?? '',
    ].where((part) => part.isNotEmpty).toList();

    final addressString = addressParts.join(', ');
    final encodedAddress = Uri.encodeComponent(addressString);

    Uri? urlToLaunch;

    if (lat != null && lng != null) {
      urlToLaunch = Uri.parse('google.navigation:q=$lat,$lng');

      try {
        bool launched = await launchUrl(
          urlToLaunch,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return;
      } catch (e) {
        debugPrint('Google Maps app not available: $e');
      }

      urlToLaunch = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
      );
    } else if (addressString.isNotEmpty) {
      urlToLaunch = Uri.parse('geo:0,0?q=$encodedAddress');

      try {
        bool launched = await launchUrl(
          urlToLaunch,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return;
      } catch (e) {
        debugPrint('geo: scheme failed: $e');
      }

      urlToLaunch = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$encodedAddress',
      );
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid address data')),
        );
      }
      return;
    }

    try {
      bool launched = await launchUrl(
        urlToLaunch,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        throw Exception('Could not launch URL');
      }
    } catch (e) {
      debugPrint('❌ Failed to open maps: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open maps: $e')),
        );
      }
    }
  }



  // ADD these methods to your StoreOrderDetailsSheet class:

// 1. Method to build WhatsApp message
  String _buildWhatsAppMessage(Map<String, dynamic> order) {
    final orderItems = order['order_items'] as List<dynamic>? ?? [];
    final billingDetails = order['billing_details']; // FIXED
    final address = order['address_info'] ?? order['address_details'];

    String message = '🛍️ *Order Details*\n\n';
    message += '📋 *Order ID:* ${order['id']}\n';
    message += '📅 *Date:* ${_formatDate(order['created_at'])}\n';
    message += '📊 *Status:* ${order['order_status']?.toString().toUpperCase()}\n\n';

    message += '📦 *Items (${orderItems.length}):*\n';
    for (var item in orderItems) {
      final product = item['products'];
      final name = product?['name'] ?? item['product_name'] ?? 'Unknown';
      final serviceType = item['service_type']?.toString() ?? '';
      final qty = item['quantity'] ?? 1;
      final price = item['total_price'] ?? '0.00';

      // Add service type in parentheses if available
      final itemName = serviceType.isNotEmpty && serviceType.toLowerCase() != 'n/a'
          ? '$name ($serviceType)'
          : name;

      message += '• $itemName x$qty - ₹$price\n';
    }

    message += '\n💰 *Bill Summary:*\n';
    if (billingDetails != null) {
      message += 'Subtotal: ₹${billingDetails['subtotal'] ?? '0.00'}\n';
      if ((billingDetails['minimum_cart_fee'] ?? 0) > 0)
        message += 'Min Cart Fee: ₹${billingDetails['minimum_cart_fee']}\n';
      if ((billingDetails['platform_fee'] ?? 0) > 0)
        message += 'Platform Fee: ₹${billingDetails['platform_fee']}\n';
      if ((billingDetails['service_tax'] ?? 0) > 0)
        message += 'Service Tax: ₹${billingDetails['service_tax']}\n';
      if ((billingDetails['delivery_fee'] ?? 0) > 0)
        message += 'Delivery Fee: ₹${billingDetails['delivery_fee']}\n';
      if ((billingDetails['discount_amount'] ?? 0) > 0)
        message += 'Discount: -₹${billingDetails['discount_amount']}\n';
      message += '━━━━━━━━━━━━━━━\n';
      message += '*Total: ₹${billingDetails['total_amount'] ?? order['total_amount']}*\n';
    } else {
      message += '*Total: ₹${order['total_amount']}*\n';
    }

    message += '\n💳 *Payment:* ${order['payment_method']?.toString().toUpperCase()}\n';

    if (address != null) {
      message += '\n📍 *Delivery Address:*\n';
      message += '${address['recipient_name'] ?? 'Customer'}\n';
      final phone = address['phone'] ?? address['phone_number'] ?? address['mobile'];
      if (phone != null) message += '📞 $phone\n';

      if (address['address_line_1'] != null) message += '${address['address_line_1']}\n';
      if (address['address_line_2'] != null) message += '${address['address_line_2']}\n';

      final cityState = '${address['city'] ?? ''}, ${address['state'] ?? ''}'.trim();
      final pincode = address['pincode'];
      if (cityState.isNotEmpty || pincode != null) {
        message += '$cityState${pincode != null ? ' - $pincode' : ''}\n';
      }
    }

    if (order['pickup_date'] != null) {
      message += '\n⏰ *Pickup:* ${_formatDate(order['pickup_date'])}';
      final pickupTime = order['pickup_slot_display_time']?.toString();
      if (pickupTime != null && pickupTime.isNotEmpty) {
        message += ' • $pickupTime\n';
      } else {
        message += '\n';
      }
    }

    if (order['delivery_date'] != null) {
      message += '🚚 *Delivery:* ${_formatDate(order['delivery_date'])}';
      final deliveryTime = order['delivery_slot_display_time']?.toString();
      if (deliveryTime != null && deliveryTime.isNotEmpty) {
        message += ' • $deliveryTime\n';
      } else {
        message += '\n';
      }
    }

    message += '\n✨ *Thank you for choosing Dobify!*';

    return message;
  }


  Future<void> _sendWhatsApp(BuildContext context, Map<String, dynamic> order) async {
    try {
      // Helper function to safely parse numbers
      double _parseAmount(dynamic value) {
        if (value == null) return 0.0;
        if (value is num) return value.toDouble();
        final parsed = double.tryParse(value.toString());
        return parsed ?? 0.0;
      }

      // Get billing details from multiple possible sources
      Map<String, dynamic>? billingDetails;
      if (order['billing_details'] != null && order['billing_details'] is Map) {
        billingDetails = Map<String, dynamic>.from(order['billing_details'] as Map);
      } else if (order['order_billing_details'] != null &&
          order['order_billing_details'] is List &&
          (order['order_billing_details'] as List).isNotEmpty) {
        billingDetails = Map<String, dynamic>.from((order['order_billing_details'] as List).first);
      }

      // If billing details are not in order, fetch them
      if (billingDetails == null) {
        try {
          final SupabaseClient supabaseClient = Supabase.instance.client;
          final orderId = order['id']?.toString() ?? '';

          final billingResponse = await supabaseClient
              .from('order_billing_details')
              .select('*')
              .eq('order_id', orderId)
              .maybeSingle();

          if (billingResponse != null) {
            order['billing_details'] = billingResponse;
          }
        } catch (e) {
          debugPrint('⚠️ Could not fetch billing details: $e');
        }
      }

      final address = order['address_info'] ?? order['address_details'];
      String phoneNumber = '';

      if (address != null) {
        phoneNumber = (address['phone'] ??
            address['phone_number'] ??
            address['mobile'] ?? '').toString();

        phoneNumber = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');

        if (phoneNumber.isNotEmpty && !phoneNumber.startsWith('91')) {
          phoneNumber = '91$phoneNumber';
        }
      }

      if (phoneNumber.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Customer phone number not available'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final message = _buildWhatsAppMessage(order);
      final encodedMessage = Uri.encodeComponent(message);

      // Send the text message
      final whatsappUrl = Uri.parse('whatsapp://send?phone=$phoneNumber&text=$encodedMessage');
      bool launched = false;

      try {
        launched = await launchUrl(
          whatsappUrl,
          mode: LaunchMode.externalApplication,
        );
      } catch (e) {
        launched = false;
      }

      if (!launched) {
        final webWhatsappUrl = Uri.parse('https://wa.me/$phoneNumber?text=$encodedMessage');
        launched = await launchUrl(
          webWhatsappUrl,
          mode: LaunchMode.externalApplication,
        );
      }

      if (!launched) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open WhatsApp'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Success message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Opening WhatsApp...'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error sending WhatsApp: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // 🆕 NEW METHOD: Send Payment QR separately
  Future<void> _sendPaymentQR(BuildContext context, Map<String, dynamic> order) async {
    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          backgroundColor: Colors.grey[900],
          content: Row(
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Loading Payment QR...',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );

      final ByteData imageData = await rootBundle.load('assets/images/payment_qr.png');
      final Uint8List imageBytes = imageData.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/payment_qr.png');
      await file.writeAsBytes(imageBytes);

      if (Navigator.canPop(context)) Navigator.of(context).pop();

      // Share the QR image with proper message
      final amount = order['total_amount']?.toString() ?? '0.00';
      final message = '''
Greetings from Dobify, a Venture of Leoworks Private Limited.

Kindly scan the QR code using your preferred payment method (cards or UPI) to complete your transaction.

Total Billing Amount: Rs $amount

Thank you for choosing Dobify.
''';

      await Share.shareXFiles(
        [XFile(file.path)],
        text: message,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Payment QR shared successfully!'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (Navigator.canPop(context)) Navigator.of(context).pop();

      debugPrint('Error sharing payment QR: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ==========================================
// COMPLETE FIXED INVOICE PDF GENERATION
// ==========================================

  Future<Uint8List> _buildInvoicePdfBytes(Map<String, dynamic> order) async {
    String _text(dynamic v) => (v == null || v.toString() == 'null') ? '' : v.toString();
    num _num(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v;
      return num.tryParse(v.toString()) ?? 0;
    }
    Map<String, dynamic> _map(dynamic v) {
      if (v == null) return <String, dynamic>{};
      if (v is Map) return Map<String, dynamic>.from(v as Map);
      return <String, dynamic>{};
    }
    List<Map<String, dynamic>> _listOfMaps(dynamic v) {
      if (v is List) return v.map((e) => _map(e)).toList();
      return <Map<String, dynamic>>[];
    }

    final pdf = pw.Document();

    pw.ImageProvider? logoImage;
    try {
      final logoData = await rootBundle.load('assets/images/dobify_inv_logo.jpg');
      logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (_) {
      logoImage = null;
    }

    // 🆕 FIXED: Properly get billing details from multiple possible sources
    Map<String, dynamic> billing = {};

    if (order['billing_details'] != null && order['billing_details'] is Map) {
      billing = _map(order['billing_details']);
    } else if (order['order_billing_details'] != null &&
        order['order_billing_details'] is List &&
        (order['order_billing_details'] as List).isNotEmpty) {
      billing = _map((order['order_billing_details'] as List).first);
    }

    // If billing is still empty, try to construct from order-level data
    if (billing.isEmpty) {
      billing = {
        'subtotal': order['subtotal'] ?? 0,
        'minimum_cart_fee': order['minimum_cart_fee'] ?? 0,
        'platform_fee': order['platform_fee'] ?? 0,
        'service_tax': order['service_tax'] ?? 0,
        'delivery_fee': order['delivery_fee'] ?? 0,
        'discount_amount': order['discount_amount'] ?? 0,
        'total_amount': order['total_amount'] ?? 0,
        'applied_coupon_code': order['applied_coupon_code'],
      };
    }

    final address = _map(order['address_info']).isNotEmpty
        ? _map(order['address_info'])
        : _map(order['address_details']);
    final items = _listOfMaps(order['order_items']);
    final createdAt = _text(order['created_at']);
    final orderId = _text(order['id'] ?? order['order_code']);
    final paymentMethod = _text(order['payment_method']).toUpperCase();

    final double serviceTaxPercent = (_num(billing['service_tax_percent'])).toDouble() > 0
        ? (_num(billing['service_tax_percent'])).toDouble()
        : 0.0;
    final double deliveryGstPercent = (_num(billing['delivery_gst_percent'])).toDouble() > 0
        ? (_num(billing['delivery_gst_percent'])).toDouble()
        : 0.0;

    final double minCartBase = (_num(billing['minimum_cart_fee'])).toDouble();
    final double platformBase = (_num(billing['platform_fee'])).toDouble();
    final double deliveryBase = (_num(billing['delivery_fee'])).toDouble();
    final double totalDiscount = (_num(billing['discount_amount'])).toDouble();

    double itemsBaseSubtotal = 0;
    for (final it in items) {
      itemsBaseSubtotal += (_num(it['total_price'])).toDouble();
    }
    final billedSubtotal = (_num(billing['subtotal'])).toDouble();
    if (billedSubtotal > 0) itemsBaseSubtotal = billedSubtotal;

    // 🆕 FIXED: Properly get total amount - prefer billing total, fall back to order total
    final billedTotalOpt = (_num(billing['total_amount'])).toDouble();
    final orderTotal = (_num(order['total_amount'])).toDouble();
    final actualTotal = billedTotalOpt > 0 ? billedTotalOpt : orderTotal;

    String _formatDate(String isoDate) {
      if (isoDate.isEmpty) return '';
      try {
        final dt = DateTime.parse(isoDate);
        return '${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.year}';
      } catch (_) {
        return isoDate;
      }
    }
    final invoiceDate = _formatDate(createdAt);

    String _genInvoiceNo() {
      final now = DateTime.tryParse(createdAt) ?? DateTime.now();
      final y = now.year.toString();
      final m = now.month.toString().padLeft(2, '0');
      final d = now.day.toString().padLeft(2, '0');
      final h = now.hour.toString().padLeft(2, '0');
      final min = now.minute.toString().padLeft(2, '0');
      final s = now.second.toString().padLeft(2, '0');
      return '$y$m$d$h$min$s';
    }
    final invoiceNo = _text(billing['invoice_no']).isNotEmpty
        ? _text(billing['invoice_no'])
        : _genInvoiceNo();

    String _numberToWords(double amount) {
      final ones = ['', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine'];
      final teens = ['ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen'];
      final tens = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];
      final scales = ['', 'thousand', 'lakh', 'crore'];
      String convertBelow1000(int num) {
        if (num == 0) return '';
        String result = '';
        final hundreds = num ~/ 100;
        final remainder = num % 100;
        if (hundreds > 0) result += '${ones[hundreds]} hundred ';
        if (remainder >= 20) {
          result += '${tens[remainder ~/ 10]} ';
          if (remainder % 10 > 0) result += '${ones[remainder % 10]} ';
        } else if (remainder >= 10) {
          result += '${teens[remainder - 10]} ';
        } else if (remainder > 0) {
          result += '${ones[remainder]} ';
        }
        return result.trim();
      }
      final rupees = amount.toInt();
      final paise = ((amount - rupees) * 100).toInt();
      if (rupees == 0 && paise == 0) return 'Zero';
      String result = '';
      int scaleIndex = 0;
      int num = rupees;
      final parts = [];
      while (num > 0) {
        if (num % 1000 > 0) {
          parts.insert(0, '${convertBelow1000(num % 1000)} ${scales[scaleIndex]}');
        }
        num ~/= 1000;
        scaleIndex++;
      }
      result = parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (paise > 0) {
        result += ' and ${convertBelow1000(paise)} paise';
      }
      return result.replaceAll(RegExp(r'\s+'), ' ').trim();
    }

    pw.Widget buildCell(String text, {bool bold = false, pw.TextAlign align = pw.TextAlign.center}) {
      return pw.Padding(
        padding: pw.EdgeInsets.all(4),
        child: pw.Text(
          text,
          maxLines: 3,
          textAlign: align,
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );
    }

    double qtySum = 0;
    double taxableSum = 0;
    double cgstSum = 0;
    double sgstSum = 0;
    double grandTotal = 0;
    double discountSum = 0;

    final recipientName = _text(address['recipient_name']).isEmpty
        ? 'Customer'
        : _text(address['recipient_name']);
    final recipientPhone = _text(address['phone']).isNotEmpty
        ? _text(address['phone'])
        : (_text(address['phone_number']).isNotEmpty
        ? _text(address['phone_number'])
        : (_text(address['mobile']).isNotEmpty
        ? _text(address['mobile'])
        : _text(address['contact'])));

    final colW = <int, pw.TableColumnWidth>{
      0: pw.FixedColumnWidth(30),
      1: pw.FlexColumnWidth(5),
      2: pw.FixedColumnWidth(45),
      3: pw.FixedColumnWidth(48),
      4: pw.FixedColumnWidth(30),
      5: pw.FixedColumnWidth(30),
      6: pw.FixedColumnWidth(45),
      7: pw.FixedColumnWidth(52),
      8: pw.FixedColumnWidth(35),
      9: pw.FixedColumnWidth(40),
      10: pw.FixedColumnWidth(35),
      11: pw.FixedColumnWidth(40),
      12: pw.FixedColumnWidth(54),
    };

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(20),
        build: (ctx) {
          pw.Widget headerCell(String text) => pw.Container(
            padding: pw.EdgeInsets.fromLTRB(4, 6, 4, 6),
            alignment: pw.Alignment.center,
            constraints: pw.BoxConstraints(minHeight: 26),
            child: pw.Text(
              text,
              maxLines: 3,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          );

          return pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: 2, color: PdfColors.black),
            ),
            padding: pw.EdgeInsets.all(12),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(
                  child: pw.Container(
                    padding: pw.EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
                    child: pw.Text(
                      'Tax Invoice',
                      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                ),
                pw.SizedBox(height: 10),

                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      flex: 3,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Invoice From',
                              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                          pw.SizedBox(height: 4),
                          pw.Text('LEOWORKS PRIVATE LIMITED',
                              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                          pw.Text('Ground Floor, Plot No-362, Damana Road,', style: pw.TextStyle(fontSize: 8)),
                          pw.Text('Chandrasekharpur, Bhubaneswar-751024', style: pw.TextStyle(fontSize: 8)),
                          pw.Text('Khordha, Odisha', style: pw.TextStyle(fontSize: 8)),
                          pw.SizedBox(height: 4),
                          pw.Text('Email ID: info@dobify.in', style: pw.TextStyle(fontSize: 8)),
                          pw.Text('PIN Code: 751016', style: pw.TextStyle(fontSize: 8)),
                          pw.Text('GSTIN: 21AAGCL4609M1ZH', style: pw.TextStyle(fontSize: 8)),
                          pw.Text('CIN: U62011OD2025PTC050462', style: pw.TextStyle(fontSize: 8)),
                          pw.Text('PAN: AAGCL4609M', style: pw.TextStyle(fontSize: 8)),
                          pw.Text('TAN: BBNL01690D', style: pw.TextStyle(fontSize: 8)),
                        ],
                      ),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          if (logoImage != null)
                            pw.Container(width: 80, height: 80, child: pw.Image(logoImage!, fit: pw.BoxFit.contain)),
                          pw.SizedBox(height: 8),
                          pw.Text('Order Id: $orderId', style: pw.TextStyle(fontSize: 8)),
                          pw.Text('Invoice No: $invoiceNo', style: pw.TextStyle(fontSize: 8)),
                          pw.Text('Invoice Date: $invoiceDate', style: pw.TextStyle(fontSize: 8)),
                          pw.Text('Place of Supply: Odisha', style: pw.TextStyle(fontSize: 8)),
                          pw.Text('State Code: 21', style: pw.TextStyle(fontSize: 8)),
                        ],
                      ),
                    ),
                  ],
                ),

                pw.SizedBox(height: 10),

                pw.Container(
                  padding: pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Invoice To',
                          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 4),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Expanded(
                            child: pw.Text(
                              recipientName,
                              maxLines: 2,
                              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                            ),
                          ),
                          if (recipientPhone.isNotEmpty)
                            pw.Text('Ph: $recipientPhone', style: pw.TextStyle(fontSize: 8)),
                        ],
                      ),
                      if (_text(address['address_line_1']).isNotEmpty)
                        pw.Text(_text(address['address_line_1']), style: pw.TextStyle(fontSize: 8), maxLines: 2),
                      if (_text(address['address_line_2']).isNotEmpty)
                        pw.Text(_text(address['address_line_2']), style: pw.TextStyle(fontSize: 8), maxLines: 2),
                      pw.Text(
                        '${_text(address['city']).isNotEmpty ? _text(address['city']) : ''}'
                            '${_text(address['city']).isNotEmpty && _text(address['state']).isNotEmpty ? ', ' : ''}'
                            '${_text(address['state']).isNotEmpty ? _text(address['state']) : ''}'
                            '${_text(address['pincode']).isNotEmpty ? ' - ${_text(address['pincode'])}' : ''}',
                        style: pw.TextStyle(fontSize: 8),
                        maxLines: 2,
                      ),
                      pw.SizedBox(height: 4),
                      pw.Row(
                        children: [
                          pw.Text('Category: B2C', style: pw.TextStyle(fontSize: 8)),
                          pw.SizedBox(width: 20),
                          pw.Text('Reverse Charges Applicable: No', style: pw.TextStyle(fontSize: 8)),
                        ],
                      ),
                      pw.Text('Transaction Type: $paymentMethod', style: pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ),

                pw.SizedBox(height: 10),

                pw.Table(
                  border: pw.TableBorder.all(width: 0.5),
                  columnWidths: colW,
                  children: [
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: PdfColors.grey300),
                      children: [
                        headerCell('Sr. No.'),
                        headerCell('Items'),
                        headerCell('HSN/SAC'),
                        headerCell('Unit Price (INR)'),
                        headerCell('Qty.'),
                        headerCell('UQC'),
                        headerCell('Discount (INR)'),
                        headerCell('Taxable Amount\n(INR)'),
                        headerCell('CGST\n(%)'),
                        headerCell('CGST\n(INR)'),
                        headerCell('SGST\n(%)'),
                        headerCell('SGST\n(INR)'),
                        headerCell('Total (INR)'),
                      ],
                    ),

                    ...items.asMap().entries.map((entry) {
                      final idx = entry.key + 1;
                      final it = entry.value;
                      final prod = _map(it['products']);
                      final name = _text(prod['name']).isNotEmpty ? _text(prod['name']) : _text(it['product_name']);
                      final qty = (_num(it['quantity'])).toDouble();
                      final base = (_num(it['total_price'])).toDouble();

                      final unitPrice = qty > 0 ? (base / qty) : 0.0;
                      final itemDiscount = itemsBaseSubtotal > 0
                          ? (base / itemsBaseSubtotal) * totalDiscount
                          : 0.0;
                      final taxableAfterDiscount = base - itemDiscount;

                      final cg = serviceTaxPercent > 0 ? (taxableAfterDiscount * (serviceTaxPercent / 2) / 100.0) : 0.0;
                      final sg = serviceTaxPercent > 0 ? (taxableAfterDiscount * (serviceTaxPercent / 2) / 100.0) : 0.0;
                      final rowTotal = taxableAfterDiscount + cg + sg;

                      qtySum += qty;
                      taxableSum += taxableAfterDiscount;
                      cgstSum += cg;
                      sgstSum += sg;
                      grandTotal += rowTotal;
                      discountSum += itemDiscount;

                      return pw.TableRow(
                        children: [
                          buildCell('$idx'),
                          buildCell(name.isEmpty ? 'Item' : name),
                          buildCell('9997'),
                          buildCell(unitPrice.toStringAsFixed(2)),
                          buildCell(qty.toStringAsFixed(0)),
                          buildCell('NOS'),
                          buildCell(itemDiscount.toStringAsFixed(2)),
                          buildCell(taxableAfterDiscount.toStringAsFixed(2)),
                          buildCell(serviceTaxPercent > 0 ? '${(serviceTaxPercent / 2).toStringAsFixed(2)}%' : '0%'),
                          buildCell(cg.toStringAsFixed(2)),
                          buildCell(serviceTaxPercent > 0 ? '${(serviceTaxPercent / 2).toStringAsFixed(2)}%' : '0%'),
                          buildCell(sg.toStringAsFixed(2)),
                          buildCell(rowTotal.toStringAsFixed(2)),
                        ],
                      );
                    }),

                    if (platformBase > 0)
                      (() {
                        final cg = serviceTaxPercent > 0 ? (platformBase * (serviceTaxPercent / 2) / 100.0) : 0.0;
                        final sg = serviceTaxPercent > 0 ? (platformBase * (serviceTaxPercent / 2) / 100.0) : 0.0;
                        final total = platformBase + cg + sg;

                        taxableSum += platformBase;
                        cgstSum += cg;
                        sgstSum += sg;
                        grandTotal += total;

                        return pw.TableRow(
                          children: [
                            buildCell('${items.length + 1}'),
                            buildCell('Platform Fee'),
                            buildCell('9997'),
                            buildCell(platformBase.toStringAsFixed(2)),
                            buildCell('1'),
                            buildCell('OTH'),
                            buildCell('0'),
                            buildCell(platformBase.toStringAsFixed(2)),
                            buildCell(serviceTaxPercent > 0 ? '${(serviceTaxPercent / 2).toStringAsFixed(2)}%' : '0%'),
                            buildCell(cg.toStringAsFixed(2)),
                            buildCell(serviceTaxPercent > 0 ? '${(serviceTaxPercent / 2).toStringAsFixed(2)}%' : '0%'),
                            buildCell(sg.toStringAsFixed(2)),
                            buildCell(total.toStringAsFixed(2)),
                          ],
                        );
                      }()),

                    if (minCartBase > 0)
                      (() {
                        final cg = serviceTaxPercent > 0 ? (minCartBase * (serviceTaxPercent / 2) / 100.0) : 0.0;
                        final sg = serviceTaxPercent > 0 ? (minCartBase * (serviceTaxPercent / 2) / 100.0) : 0.0;
                        final total = minCartBase + cg + sg;

                        taxableSum += minCartBase;
                        cgstSum += cg;
                        sgstSum += sg;
                        grandTotal += total;

                        final sr = items.length + (platformBase > 0 ? 2 : 1);
                        return pw.TableRow(
                          children: [
                            buildCell('$sr'),
                            buildCell('Minimum Cart Fee'),
                            buildCell('9997'),
                            buildCell(minCartBase.toStringAsFixed(2)),
                            buildCell('1.00'),
                            buildCell('OTH'),
                            buildCell('0'),
                            buildCell(minCartBase.toStringAsFixed(2)),
                            buildCell(serviceTaxPercent > 0 ? '${(serviceTaxPercent / 2).toStringAsFixed(2)}%' : '0%'),
                            buildCell(cg.toStringAsFixed(2)),
                            buildCell(serviceTaxPercent > 0 ? '${(serviceTaxPercent / 2).toStringAsFixed(2)}%' : '0%'),
                            buildCell(sg.toStringAsFixed(2)),
                            buildCell(total.toStringAsFixed(2)),
                          ],
                        );
                      }()),

                    if (deliveryBase > 0)
                      (() {
                        final cg = deliveryGstPercent > 0 ? (deliveryBase * (deliveryGstPercent / 2) / 100.0) : 0.0;
                        final sg = deliveryGstPercent > 0 ? (deliveryBase * (deliveryGstPercent / 2) / 100.0) : 0.0;
                        final total = deliveryBase + cg + sg;

                        taxableSum += deliveryBase;
                        cgstSum += cg;
                        sgstSum += sg;
                        grandTotal += total;

                        final sr = items.length +
                            (platformBase > 0 ? 1 : 0) +
                            (minCartBase > 0 ? 1 : 0) +
                            1;
                        return pw.TableRow(
                          children: [
                            buildCell('$sr'),
                            buildCell('Delivery Fee'),
                            buildCell('996813'),
                            buildCell(deliveryBase.toStringAsFixed(2)),
                            buildCell('1.00'),
                            buildCell('OTH'),
                            buildCell('0'),
                            buildCell(deliveryBase.toStringAsFixed(2)),
                            buildCell(deliveryGstPercent > 0 ? '${(deliveryGstPercent / 2).toStringAsFixed(2)}%' : '0%'),
                            buildCell(cg.toStringAsFixed(2)),
                            buildCell(deliveryGstPercent > 0 ? '${(deliveryGstPercent / 2).toStringAsFixed(2)}%' : '0%'),
                            buildCell(sg.toStringAsFixed(2)),
                            buildCell(total.toStringAsFixed(2)),
                          ],
                        );
                      }()),

                    // 🆕 FIXED: Use actualTotal instead of conditional
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        buildCell('Total', bold: true),
                        buildCell('', bold: true),
                        buildCell('', bold: true),
                        buildCell('', bold: true),
                        buildCell(qtySum.toStringAsFixed(0), bold: true),
                        buildCell('', bold: true),
                        buildCell(discountSum.toStringAsFixed(2), bold: true),
                        buildCell(taxableSum.toStringAsFixed(2), bold: true),
                        buildCell('', bold: true),
                        buildCell(cgstSum.toStringAsFixed(2), bold: true),
                        buildCell('', bold: true),
                        buildCell(sgstSum.toStringAsFixed(2), bold: true),
                        buildCell(actualTotal.toStringAsFixed(2), bold: true),
                      ],
                    ),
                  ],
                ),

                pw.SizedBox(height: 8),

                if (_text(billing['applied_coupon_code']).isNotEmpty)
                  pw.Text('Coupon Applied: ${_text(billing['applied_coupon_code'])}',
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),

                pw.SizedBox(height: 4),
                pw.Text('Amount in Words:',
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                // 🆕 FIXED: Use actualTotal instead of conditional
                pw.Text(
                  'Rupees ${_numberToWords(actualTotal)} only',
                  style: pw.TextStyle(fontSize: 9),
                ),

                pw.SizedBox(height: 10),

                pw.Container(
                  padding: pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('For Dobify',
                          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      pw.Text('A trade of Leoworks Private Limited', style: pw.TextStyle(fontSize: 8)),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Registered Office: Ground Floor, Plot No-362, Damana Road, Chandrasekharpur, Bhubaneswar-751024, Khordha, Odisha',
                        style: pw.TextStyle(fontSize: 7),
                      ),
                      pw.Text(
                        'Email: info@dobify.in | Contact: +91 7326019870 | Website: www.dobify.in',
                        style: pw.TextStyle(fontSize: 7),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text('Digitally Signed by', style: pw.TextStyle(fontSize: 8)),
                            pw.Text('Leoworks Private Limited.',
                                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                            pw.Text(invoiceDate, style: pw.TextStyle(fontSize: 8)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                pw.SizedBox(height: 8),

                pw.Text('Note:', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                pw.Text(
                  'This is a digitally signed computer-generated invoice and does not require a signature. All transactions are subject to the terms and conditions of Dobify.',
                  style: pw.TextStyle(fontSize: 7),
                ),
                pw.SizedBox(height: 6),
                pw.Text('Terms & Conditions:', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                pw.Text(
                  '1. If you have any issues or queries regarding your order, please contact our customer chat support through the Dobify platform or email us at info@dobify.in',
                  style: pw.TextStyle(fontSize: 7),
                ),
                pw.Text(
                  '2. For your safety, please note that Dobify never asks for sensitive banking details such as CVV, account number, UPI PIN, or passwords through any support channel. Do not share these details with anyone over any medium.',
                  style: pw.TextStyle(fontSize: 7),
                ),
                pw.Text('3. All services are provided by Dobify, a trade of Leoworks Private Limited.',
                    style: pw.TextStyle(fontSize: 7)),
                pw.Text(
                  '4. Refunds or cancellations, if applicable, will be processed as per Dobify\'s refund and cancellation policy.',
                  style: pw.TextStyle(fontSize: 7),
                ),
                pw.Text('5. Dobify shall not be held responsible for delays or issues arising from factors beyond its control.',
                    style: pw.TextStyle(fontSize: 7)),
                pw.Text('6. Any disputes shall be subject to the jurisdiction of Bhubaneswar, Odisha.', style: pw.TextStyle(fontSize: 7)),
              ],
            ),
          );
        },
      ),
    );

    return await pdf.save();
  }

// ==========================================
// COMPLETE

  // Replace your _sharePdfOnWhatsApp method with this fixed version:

  Future<void> _sharePdfOnWhatsApp(BuildContext context, Map<String, dynamic> order) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.grey[900],
        content: Row(
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                'Preparing invoice...',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );

    try {
      final SupabaseClient supabaseClient = Supabase.instance.client;
      final orderId = order['id']?.toString() ?? 'unknown';

      // 🆕 FETCH BILLING DETAILS if not already present
      if (order['billing_details'] == null && order['order_billing_details'] == null) {
        try {
          final billingResponse = await supabaseClient
              .from('order_billing_details')
              .select('*')
              .eq('order_id', orderId)
              .maybeSingle();

          if (billingResponse != null) {
            order['billing_details'] = billingResponse;
          }
        } catch (e) {
          debugPrint('⚠️ Could not fetch billing details: $e');
          // Continue anyway - PDF will use order-level data as fallback
        }
      }

      // Generate PDF bytes
      final Uint8List pdfBytes = await _buildInvoicePdfBytes(order);

      // Get customer phone number
      final address = order['address_info'] ?? order['address_details'];
      String phoneNumber = '';

      if (address != null) {
        phoneNumber = (address['phone'] ??
            address['phone_number'] ??
            address['mobile'] ?? '').toString();

        phoneNumber = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');

        if (phoneNumber.isNotEmpty &&
            !phoneNumber.startsWith('+') &&
            phoneNumber.length == 10) {
          phoneNumber = '+91$phoneNumber';
        }
      }

      String publicUrl = '';

      try {
        // Upload to Supabase Storage
        final storagePath = 'store_Invoices/Invoice_$orderId.pdf';

        await supabaseClient
            .storage
            .from('invoices')
            .uploadBinary(
          storagePath,
          pdfBytes,
          fileOptions: FileOptions(
            contentType: 'application/pdf',
            upsert: true,
          ),
        );

        // Get public URL
        publicUrl = supabaseClient
            .storage
            .from('invoices')
            .getPublicUrl(storagePath);

        debugPrint('✅ Invoice uploaded to: $storagePath');
        debugPrint('✅ Public URL: $publicUrl');

      } catch (uploadError) {
        debugPrint('❌ Upload error: $uploadError');

        if (Navigator.canPop(context)) Navigator.of(context).pop();

        // Fallback to local file sharing
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/Invoice_$orderId.pdf');
        await file.writeAsBytes(pdfBytes);

        if (context.mounted) {
          await Share.shareXFiles(
            [XFile(file.path, mimeType: 'application/pdf')],
            text: 'Invoice for Order #$orderId',
            subject: 'Invoice for Order #$orderId',
          );
        }
        return;
      }

      if (Navigator.canPop(context)) Navigator.of(context).pop();

      // Create WhatsApp message
      final String message = '''
📄 *DOBIFY INVOICE* 📄

Order: #$orderId
Amount: ₹${order['total_amount']?.toString() ?? '0.00'}

📥 Download: $publicUrl

Thank you! 🛍️
''';

      final encodedMessage = Uri.encodeComponent(message);

      // Send via WhatsApp
      bool whatsappLaunched = false;

      if (phoneNumber.isNotEmpty) {
        // Try WhatsApp direct
        final whatsappUrl = Uri.parse('whatsapp://send?phone=$phoneNumber&text=$encodedMessage');

        try {
          whatsappLaunched = await launchUrl(
            whatsappUrl,
            mode: LaunchMode.externalApplication,
          );
        } catch (e) {
          debugPrint('WhatsApp direct failed: $e');
        }

        // If WhatsApp direct failed, try WhatsApp Web
        if (!whatsappLaunched) {
          final webUrl = Uri.parse('https://wa.me/$phoneNumber?text=$encodedMessage');
          whatsappLaunched = await launchUrl(
            webUrl,
            mode: LaunchMode.externalApplication,
          );
        }
      }

      // Handle results
      if (whatsappLaunched) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('Invoice sent via WhatsApp!'),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else if (phoneNumber.isEmpty) {
        // No phone number - copy link
        if (context.mounted) {
          await Clipboard.setData(ClipboardData(text: publicUrl));

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Invoice link copied to clipboard'),
              backgroundColor: Colors.blue,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        // WhatsApp not available
        if (context.mounted) {
          await Share.share(
            'Invoice for Order #$orderId\n\nDownload: $publicUrl',
            subject: 'Invoice for Order #$orderId',
          );
        }
      }

    } catch (e, st) {
      if (Navigator.canPop(context)) Navigator.of(context).pop();
      debugPrint('❌ Error: $e\n$st');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send invoice: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }



// 3. Method to share order details
  Future<void> _shareOrderDetails(BuildContext context, Map<String, dynamic> order) async {
    try {
      final message = _buildWhatsAppMessage(order);
      await Share.share(
        message,
        subject: 'Order Details - ${order['id']}',
      );
    } catch (e) {
      debugPrint('Error sharing: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }



  Widget _buildBillingSection(Map<String, dynamic> order) {
    // Helper function to safely parse numbers
    double _parseAmount(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      final parsed = double.tryParse(value.toString());
      return parsed ?? 0.0;
    }

    // Try to get billing details from different possible locations
    Map<String, dynamic>? billingDetails;

    if (order['billing_details'] != null) {
      billingDetails = order['billing_details'] is Map
          ? Map<String, dynamic>.from(order['billing_details'] as Map)
          : null;
    } else if (order['order_billing_details'] != null &&
        order['order_billing_details'] is List &&
        (order['order_billing_details'] as List).isNotEmpty) {
      billingDetails = Map<String, dynamic>.from((order['order_billing_details'] as List).first);
    }

    // Get all values - try billing details first, then fall back to order level
    final subtotal = _parseAmount(billingDetails?['subtotal'] ?? order['subtotal']);
    final minCartFee = _parseAmount(billingDetails?['minimum_cart_fee'] ?? order['minimum_cart_fee']);
    final platformFee = _parseAmount(billingDetails?['platform_fee'] ?? order['platform_fee']);
    final serviceTax = _parseAmount(billingDetails?['service_tax'] ?? order['service_tax']);
    final deliveryFee = _parseAmount(billingDetails?['delivery_fee'] ?? order['delivery_fee']);
    final expressDeliveryFee = _parseAmount(billingDetails?['express_delivery_fee'] ?? order['express_delivery_fee']);
    final standardDeliveryFee = _parseAmount(billingDetails?['standard_delivery_fee'] ?? order['standard_delivery_fee']);
    final discountAmount = _parseAmount(billingDetails?['discount_amount'] ?? order['discount_amount']);

    // Get total - prefer billing_details, then order
    final totalAmount = _parseAmount(billingDetails?['total_amount']) > 0
        ? _parseAmount(billingDetails?['total_amount'])
        : _parseAmount(order['total_amount']);

    final appliedCoupon = (billingDetails?['applied_coupon_code'] ?? order['applied_coupon_code'])?.toString();
    final deliveryType = (billingDetails?['delivery_type'] ?? order['delivery_type'])?.toString()?.toUpperCase();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Subtotal - Show only if > 0
          if (subtotal > 0)
            _buildBillRow('Subtotal', '₹${subtotal.toStringAsFixed(2)}'),

          // Minimum Cart Fee - Show only if > 0
          if (minCartFee > 0)
            _buildBillRow('Minimum Cart Fee', '₹${minCartFee.toStringAsFixed(2)}'),

          // Platform Fee - Show only if > 0
          if (platformFee > 0)
            _buildBillRow('Platform Fee', '₹${platformFee.toStringAsFixed(2)}'),

          // Service Tax - Show only if > 0
          if (serviceTax > 0)
            _buildBillRow('Service Tax (GST)', '₹${serviceTax.toStringAsFixed(2)}'),

          // Delivery Fee - Show only if > 0
          if (deliveryFee > 0)
            _buildBillRow(
              'Delivery Fee${deliveryType != null && deliveryType.isNotEmpty ? ' ($deliveryType)' : ''}',
              '₹${deliveryFee.toStringAsFixed(2)}',
            ),

          // Express Delivery Fee - Show only if > 0
          if (expressDeliveryFee > 0)
            _buildBillRow('Express Delivery Fee', '₹${expressDeliveryFee.toStringAsFixed(2)}'),

          // Standard Delivery Fee - Show only if > 0
          if (standardDeliveryFee > 0)
            _buildBillRow('Standard Delivery Fee', '₹${standardDeliveryFee.toStringAsFixed(2)}'),

          // Discount - Show only if > 0
          if (discountAmount > 0)
            _buildBillRow(
              'Discount',
              '-₹${discountAmount.toStringAsFixed(2)}',
              isDiscount: true,
            ),

          // Coupon Applied - Show if exists and not empty
          if (appliedCoupon != null && appliedCoupon.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withOpacity(0.4), width: 1.5),
              ),
              child: Row(
                children: [
                  Icon(Icons.local_offer, size: 18, color: Colors.green[400]),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Coupon Applied: $appliedCoupon',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.green[300],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],

          // Divider before total - only show if we have at least one item above
          if (subtotal > 0 || minCartFee > 0 || platformFee > 0 ||
              serviceTax > 0 || deliveryFee > 0 || expressDeliveryFee > 0 ||
              standardDeliveryFee > 0 || discountAmount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1, thickness: 1.5, color: Colors.grey[700]),
            ),

          // Total Amount - ALWAYS SHOW
          _buildBillRow(
            'Total Amount',
            '₹${totalAmount.toStringAsFixed(2)}',
            isTotal: true,
          ),

          const SizedBox(height: 16),

          // Payment Method - ALWAYS SHOW
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey[850],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey[700]!, width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.payment, size: 18, color: Colors.white70),
                    const SizedBox(width: 10),
                    const Text(
                      'Payment Method',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    order['payment_method']?.toString().toUpperCase() ?? 'N/A',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }



// 5. Helper method for bill rows
  Widget _buildBillRow(String label, String value,
      {bool isTotal = false, bool isDiscount = false, bool isInfo = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: isTotal ? 16 : 13,
                fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
                color: isTotal ? Colors.white : Colors.white70,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
              color: isTotal
                  ? Colors.white
                  : isDiscount
                  ? Colors.green[400]
                  : isInfo
                  ? Colors.blue[300]
                  : Colors.white70,
            ),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final orderItems = order['order_items'] as List<dynamic>? ?? [];
    final address = order['address_info'] ?? order['address_details'];
    final orderStatus = order['order_status']?.toString().toUpperCase() ?? 'PENDING';

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          ),
          child: Stack(
            children: [
              Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 50,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[700],
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[900],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.receipt_long,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Order Details',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Complete order information',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: Colors.grey[800]),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      physics: const BouncingScrollPhysics(), // ✅ ADDED BOUNCE PHYSICS
                      padding: EdgeInsets.fromLTRB(
                        20,
                        20,
                        20,
                        MediaQuery.of(context).padding.bottom + 160, // ✅ CHANGED 100 to 160
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSection(
                            'Order Information',
                            Icons.info_outline,
                            [
                              _buildDetailRow('Order ID', order['id']?.toString() ?? 'N/A'),
                              _buildDetailRow('Status', orderStatus),
                              _buildDetailRow('Created', _formatDate(order['created_at'])),
                              _buildDetailRow(
                                'Payment Method',
                                order['payment_method']?.toString().toUpperCase() ?? 'N/A',
                              ),
                              _buildDetailRow(
                                'Total Amount',
                                '₹${order['total_amount']?.toString() ?? '0.00'}',
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          _buildSectionHeader(
                            'Order Items (${orderItems.length})',
                            Icons.shopping_bag,
                          ),
                          const SizedBox(height: 12),
                          ...orderItems.map((item) => _buildOrderItem(item)).toList(),
                          const SizedBox(height: 20),

                          // 🆕 BILLING SECTION
                          _buildSectionHeader('Bill Details', Icons.receipt_long),
                          const SizedBox(height: 12),
                          _buildBillingSection(order),
                          const SizedBox(height: 20),

                          // Pickup Slot Section
                          if (order['pickup_date'] != null) ...[
                            _buildSection(
                              'Pickup Slot',
                              Icons.schedule,
                              [
                                _buildDetailRow('Date', _formatDate(order['pickup_date'])),
                                _buildDetailRow(
                                  'Time',
                                  order['pickup_slot_display_time']?.toString() ?? 'N/A',
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                          ],

// Delivery Slot Section
                          if (order['delivery_date'] != null) ...[
                            _buildSection(
                              'Delivery Slot',
                              Icons.local_shipping,
                              [
                                _buildDetailRow('Date', _formatDate(order['delivery_date'])),
                                _buildDetailRow(
                                  'Time',
                                  order['delivery_slot_display_time']?.toString() ?? 'N/A',
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                          ],
                          // Delivery Address Section
                          if (address != null) ...[
                            _buildDeliveryAddressSection(context, address),
                            const SizedBox(height: 20),
                          ],],
                      ),
                    ),
                  ),
                ],
              ),

              // 🆕 FIXED BOTTOM BUTTONS - 3 BUTTONS WITH PROPER SPACING
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    MediaQuery.of(context).padding.bottom + 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border(
                      top: BorderSide(color: Colors.grey[800]!, width: 1),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5), // ✅ STRONGER SHADOW
                        blurRadius: 15,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Row 1: WhatsApp + Invoice
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 50,
                              child: ElevatedButton.icon(
                                onPressed: () => _sendWhatsApp(context, order),
                                icon: const Icon(Icons.phone, size: 20),
                                label: const Text(
                                  'WhatsApp',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF25D366),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 50,
                              child: ElevatedButton.icon(
                                onPressed: () => _sharePdfOnWhatsApp(context, order),
                                icon: const Icon(Icons.picture_as_pdf, size: 20),
                                label: const Text(
                                  'Invoice',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Row 2: Payment QR Button - ONLY FOR COD ORDERS
                      if (order['payment_method']?.toString().toUpperCase() == 'COD' ||
                          order['payment_method']?.toString().toUpperCase() == 'CASH ON DELIVERY')
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: () => _sendPaymentQR(context, order),
                            icon: const Icon(Icons.qr_code_2, size: 22),
                            label: const Text(
                              'Share Payment QR',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue[700],
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) => Row(
    children: [
      Icon(icon, size: 20, color: Colors.white),
      const SizedBox(width: 8),
      Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    ],
  );

  Widget _buildSection(String title, IconData icon, List<Widget> children) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[800]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(title, icon),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );

  Widget _buildDeliveryAddressSection(
      BuildContext context,
      Map<String, dynamic> address,
      ) {
    String _s(dynamic v) => v?.toString().trim() ?? '';

    final name = _s(address['recipient_name'] ?? address['name']);
    final phone = _s(address['phone'] ?? address['phone_number']);
    final line1 = _s(address['address_line_1']);
    final line2 = _s(address['address_line_2']);
    final area = _s(address['area'] ?? address['locality'] ?? address['landmark']);
    final city = _s(address['city']);
    final state = _s(address['state']);
    final pincode = _s(address['pincode']);
    final country = _s(address['country']);

    double? _toDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString().trim());
    }

    final lat = _toDouble(
      address['latitude'] ??
          address['lat'] ??
          address['geo_latitude'] ??
          address['geo_lat'] ??
          address['Latitude'] ??
          address['Lat'],
    );
    final lng = _toDouble(
      address['longitude'] ??
          address['lng'] ??
          address['lon'] ??
          address['long'] ??
          address['geo_longitude'] ??
          address['geo_lng'] ??
          address['Longitude'] ??
          address['Lng'] ??
          address['Long'],
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSectionHeader('Delivery Address', Icons.location_on),
              ),
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: () => _openGoogleMaps(context, address),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.map, color: Colors.black, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          (lat != null && lng != null) ? 'Open (GPS)' : 'Open in Maps',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (name.isNotEmpty) _buildDetailRow('Name', name),
          if (phone.isNotEmpty) _buildDetailRow('Phone', phone),
          if (line1.isNotEmpty) _buildDetailRow('Address Line 1', line1),
          if (line2.isNotEmpty) _buildDetailRow('Address Line 2', line2),
          if (area.isNotEmpty) _buildDetailRow('Area / Landmark', area),
          if (city.isNotEmpty) _buildDetailRow('City', city),
          if (state.isNotEmpty) _buildDetailRow('State', state),
          if (pincode.isNotEmpty) _buildDetailRow('Pincode', pincode),
          if (country.isNotEmpty) _buildDetailRow('Country', country),
          if (lat != null && lng != null)
            _buildDetailRow(
              'Coordinates',
              '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Colors.white,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildOrderItem(Map<String, dynamic> item) {
    final product = item['products'];
    final imageUrl = item['product_image'] ?? product?['image_url'];
    final serviceType = item['service_type']?.toString() ?? 'N/A';

    final productPrice =
        double.tryParse(item['product_price']?.toString() ?? '0') ?? 0.0;
    final servicePrice =
        double.tryParse(item['service_price']?.toString() ?? '0') ?? 0.0;

    final quantity = (item['quantity'] is num)
        ? (item['quantity'] as num).toInt()
        : int.tryParse('${item['quantity']}') ?? 1;
    final unitPrice = productPrice + servicePrice;
    final itemTotal = unitPrice * quantity;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[800]!),
            ),
            child: imageUrl != null
                ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                const Icon(
                  Icons.image_not_supported,
                  color: Colors.grey,
                ),
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                          : null,
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  );
                },
              ),
            )
                : const Icon(Icons.shopping_bag, color: Colors.grey),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['product_name'] ??
                      product?['name']?.toString() ??
                      'Unknown Product',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.white,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey[700]!),
                  ),
                  child: Text(
                    serviceType,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Item price: ₹${unitPrice.toStringAsFixed(1)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Qty: $quantity   •   Total: ₹${itemTotal.toStringAsFixed(1)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}