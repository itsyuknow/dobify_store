import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

import 'package:permission_handler/permission_handler.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'colors.dart'; // Replace with your actual theme import
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'dart:convert';

// ⬆️ put this near your imports, not inside a class
const String _gmapsKey = 'AIzaSyDjxtVK1EXQuaYOc0-a0V5-Wb8xR-koHZ0';


// ---------- Google Places helpers (TOP-LEVEL, not inside a class) ----------
class PlacePrediction {
  final String description;
  final String placeId;
  const PlacePrediction({required this.description, required this.placeId});
}

Future<List<PlacePrediction>> _placesAutocomplete(String input) async {
  if (input.trim().isEmpty) return [];

  final uri = Uri.parse(
    'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=${Uri.encodeComponent(input)}'
        '&types=geocode'
        '&components=country:in' // limit to India; remove for global
        '&key=$_gmapsKey',
  );

  final res = await http.get(uri);
  if (res.statusCode != 200) return [];

  final data = json.decode(res.body);
  if (data['status'] != 'OK') return [];

  final preds = (data['predictions'] as List?) ?? [];
  return preds.map((p) {
    final desc = (p['description'] ?? '').toString();
    final id = (p['place_id'] ?? '').toString();
    if (desc.isEmpty || id.isEmpty) return null;
    return PlacePrediction(description: desc, placeId: id);
  }).whereType<PlacePrediction>().toList(growable: false);
}

Future<LatLng?> _placeDetailsLatLng(String placeId) async {
  final uri = Uri.parse(
    'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=$placeId'
        '&fields=geometry,formatted_address'
        '&key=$_gmapsKey',
  );

  final res = await http.get(uri);
  if (res.statusCode != 200) return null;

  final data = json.decode(res.body);
  if (data['status'] != 'OK') return null;

  final loc = data['result']?['geometry']?['location'];
  if (loc == null) return null;

  return LatLng(
    (loc['lat'] as num).toDouble(),
    (loc['lng'] as num).toDouble(),
  );
}



class AddressBookScreen extends StatefulWidget {
  final Function(Map<String, dynamic>) onAddressSelected;

  const AddressBookScreen({super.key, required this.onAddressSelected});


  @override
  State<AddressBookScreen> createState() => _AddressBookScreenState();
}

class _AddressBookScreenState extends State<AddressBookScreen> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> addresses = [];
  bool isLoading = true;
  String? selectedAddressId;

  // Add these variables to your existing state variables
  TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredAddresses = [];
  String _searchQuery = '';



  Future<Map<String, String>> _reverseGeocodeWeb(LatLng loc) async {
    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/geocode/json'
          '?latlng=${loc.latitude},${loc.longitude}&key=$_gmapsKey',
    );
    final res = await http.get(uri);
    if (res.statusCode != 200) return {};
    final data = json.decode(res.body);
    final results = (data['results'] as List?) ?? [];
    if (data['status'] != 'OK' || results.isEmpty) return {};

    final comps = (results.first['address_components'] as List).cast<dynamic>();
    String? postal, city, state, route, sublocality;
    for (final c in comps) {
      final types = (c['types'] as List).cast<String>();
      if (types.contains('postal_code')) postal = c['long_name'];
      if (types.contains('locality')) city = c['long_name'];
      if (types.contains('administrative_area_level_1')) state = c['long_name'];
      if (types.contains('route')) route = c['long_name'];
      if (types.contains('sublocality') || types.contains('sublocality_level_1')) {
        sublocality = c['long_name'];
      }
    }

    final line1 = [route].where((e) => (e ?? '').isNotEmpty).join(', ');
    final line2 = [sublocality, city].where((e) => (e ?? '').isNotEmpty).join(', ');

    return {
      'line1': line1,
      'line2': line2,
      'city': city ?? '',
      'state': state ?? '',
      'pincode': postal ?? '',
      'formatted': results.first['formatted_address'] ?? '',
    };
  }

  Future<LatLng?> _forwardGeocodeWeb(String query) async {
    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/geocode/json'
          '?address=${Uri.encodeComponent(query)}&key=$_gmapsKey',
    );
    final res = await http.get(uri);
    if (res.statusCode != 200) return null;
    final data = json.decode(res.body);
    final results = (data['results'] as List?) ?? [];
    if (data['status'] != 'OK' || results.isEmpty) return null;

    final loc = results.first['geometry']['location'];
    return LatLng((loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble());
  }



  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }






  Future<void> _loadAddresses() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final response = await supabase
          .from('user_addresses')
          .select()
          .eq('user_id', userId)
          .order('is_default', ascending: false)
          .order('created_at', ascending: false);

      setState(() {
        addresses = List<Map<String, dynamic>>.from(response);
        _filteredAddresses = List<Map<String, dynamic>>.from(response); // Initialize filtered list
        isLoading = false;
      });
    } catch (e) {
      print("Error loading addresses: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load addresses'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() {
        isLoading = false;
      });
    }
  }

  void _filterAddresses(String query) {
    setState(() {
      _searchQuery = query;

      if (query.isEmpty) {
        _filteredAddresses = List.from(addresses);
      } else {
        _filteredAddresses = addresses.where((address) {
          final name = (address['recipient_name'] ?? '').toString().toLowerCase();
          final phone = (address['phone_number'] ?? '').toString().toLowerCase();
          final searchLower = query.toLowerCase();

          return name.contains(searchLower) || phone.contains(searchLower);
        }).toList();
      }
    });
  }

  Future<void> _setDefaultAddress(String addressId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // First, unset all addresses as default
      await supabase
          .from('user_addresses')
          .update({'is_default': false})
          .eq('user_id', userId);

      // Then set the selected address as default
      await supabase
          .from('user_addresses')
          .update({'is_default': true})
          .eq('id', addressId)
          .eq('user_id', userId);

      _loadAddresses();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Default address updated'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print("Error setting default address: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating address: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteAddress(String addressId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await supabase
          .from('user_addresses')
          .delete()
          .eq('id', addressId)
          .eq('user_id', userId);

      _loadAddresses();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Address deleted'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      print("Error deleting address: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting address: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showAddressOptions(Map<String, dynamic> address) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pill handle
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Set as default
                if (!address['is_default']) ...[
                  ListTile(
                    leading: const Icon(Icons.home_outlined),
                    title: const Text('Set as default'),
                    onTap: () {
                      Navigator.pop(context);
                      _setDefaultAddress(address['id']);
                    },
                  ),
                ],

                // Edit address
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit address'),
                  onTap: () {
                    Navigator.pop(context);
                    _openAddAddressScreen(address);
                  },
                ),

                // Delete address
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    'Delete address',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showDeleteConfirmation(address);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  void _showDeleteConfirmation(Map<String, dynamic> address) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Address'),
          content: const Text('Are you sure you want to delete this address?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _deleteAddress(address['id']);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  void _openAddAddressScreen([Map<String, dynamic>? existingAddress]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddAddressScreen(
          existingAddress: existingAddress,
          onAddressSaved: () {
            _loadAddresses();
          },
        ),
      ),
    );
  }

  void _selectAddress(Map<String, dynamic> address) {
    // Find the actual index in the filtered list
    final index = _filteredAddresses.indexWhere((a) => a['id'] == address['id']);
    if (index != -1) {
      setState(() {
        selectedAddressId = address['id'];
      });
    }
  }

  void _confirmSelection() {
    if (selectedAddressId != null) {
      final selectedAddress = _filteredAddresses.firstWhere(
            (address) => address['id'] == selectedAddressId,
        orElse: () => addresses.firstWhere(
              (address) => address['id'] == selectedAddressId,
          orElse: () => {},
        ),
      );

      if (selectedAddress.isNotEmpty) {
        widget.onAddressSelected(selectedAddress);
        Navigator.pop(context);
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.yellow,
        automaticallyImplyLeading: true,
        title: const Text(
          "Address Book",
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.arrow_back,
            color: Colors.white,
            size: 24,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => _openAddAddressScreen(),
            icon: const Icon(
              Icons.add,
              color: Colors.white,
            ),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // SEARCH BAR - Add this section
          _buildSearchBar(),

          // Conditional content
          if (_filteredAddresses.isEmpty && _searchQuery.isNotEmpty)
            _buildNoResultsState()
          else if (_filteredAddresses.isEmpty)
            Expanded(child: _buildEmptyState())
          else
            Expanded(child: _buildAddressList()),

          if (selectedAddressId != null && _filteredAddresses.isNotEmpty)
            _buildSelectionFooter(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.location_off,
              size: 80,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            const Text(
              'No addresses found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add your first address to get started',
              style: TextStyle(
                color: Colors.black54,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _openAddAddressScreen(),
              icon: const Icon(Icons.add),
              label: const Text('Add Address'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.yellow,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade100,
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _filterAddresses,
                decoration: InputDecoration(
                  hintText: 'Search by name or phone number...',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  prefixIcon: Icon(
                    Icons.search,
                    color: Colors.grey.shade600,
                    size: 22,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                    icon: Icon(
                      Icons.clear,
                      color: Colors.grey.shade600,
                      size: 20,
                    ),
                    onPressed: () {
                      _searchController.clear();
                      _filterAddresses('');
                    },
                  )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  isDense: true,
                ),
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.yellow,
                ),
              ),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '${_filteredAddresses.length} found',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }


  Widget _buildNoResultsState() {
    return Expanded(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                'No addresses found',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'No addresses match "$_searchQuery"',
                style: TextStyle(
                  color: Colors.grey.shade500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () {
                  _searchController.clear();
                  _filterAddresses('');
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: kPrimaryColor,
                  side: BorderSide(color: kPrimaryColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text('Clear search'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddressList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredAddresses.length,
      itemBuilder: (context, index) {
        final address = _filteredAddresses[index];
        return _buildAddressCard(address);
      },
    );
  }

  Widget _buildAddressCard(Map<String, dynamic> address) {
    final isSelected = selectedAddressId == address['id'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? Colors.blue
              : address['is_default']
              ? kPrimaryColor
              : Colors.grey.shade200,
          width: isSelected ? 2 : address['is_default'] ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade100,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _selectAddress(address),
          onLongPress: () => _showAddressOptions(address),
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
                        color: _getAddressTypeColor(address['address_type']).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _getAddressTypeIcon(address['address_type']),
                        color: _getAddressTypeColor(address['address_type']),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  address['address_type'] ?? 'Address',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (address['is_default']) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: kPrimaryColor,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text(
                                    'DEFAULT',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                              if (address['latitude'] != null && address['longitude'] != null) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.location_on,
                                        size: 10,
                                        color: Colors.green.shade700,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        'MAP',
                                        style: TextStyle(
                                          color: Colors.green.shade700,
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (address['recipient_name'] != null)
                            Text(
                              address['recipient_name'],
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _showAddressOptions(address),
                      icon: Icon(
                        Icons.more_vert,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  address['address_line_1'] ?? '',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (address['address_line_2'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    address['address_line_2'],
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  '${address['city']}, ${address['state']} - ${address['pincode']}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (address['phone_number'] != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.phone,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          address['phone_number'],
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                if (isSelected) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, color: Colors.blue, size: 16),
                        const SizedBox(width: 6),
                        const Text(
                          'Selected',
                          style: TextStyle(
                            color: Colors.blue,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionFooter() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), // <-- same as MapView
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _confirmSelection,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
                elevation: 2,
              ),
              child: const Text(
                'Use This Address',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _getAddressTypeIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'home':
        return Icons.home;
      case 'office':
      case 'work':
        return Icons.business;
      case 'other':
        return Icons.location_on;
      default:
        return Icons.location_on;
    }
  }

  Color _getAddressTypeColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'home':
        return Colors.blue;
      case 'office':
      case 'work':
        return Colors.orange;
      case 'other':
        return Colors.purple;
      default:
        return kPrimaryColor;
    }
  }
}

class AddAddressScreen extends StatefulWidget {
  final Map<String, dynamic>? existingAddress;
  final VoidCallback onAddressSaved;
  final LatLng? preselectedLocation;
  final String? preselectedAddress;

  const AddAddressScreen({
    super.key,
    this.existingAddress,
    required this.onAddressSaved,
    this.preselectedLocation,
    this.preselectedAddress,
  });

  @override
  State<AddAddressScreen> createState() => _AddAddressScreenState();
}

// ---- Web Geocoding helpers (TOP-LEVEL, not inside a class) ----
Future<Map<String, String>> _reverseGeocodeWeb(LatLng loc) async {
  final uri = Uri.parse(
    'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${loc.latitude},${loc.longitude}&key=$_gmapsKey',
  );
  final res = await http.get(uri);
  if (res.statusCode != 200) return {};
  final data = json.decode(res.body);
  final results = (data['results'] as List?) ?? [];
  if (data['status'] != 'OK' || results.isEmpty) return {};

  final comps = (results.first['address_components'] as List).cast<dynamic>();
  String? postal, city, state, route, sublocality;
  for (final c in comps) {
    final types = (c['types'] as List).cast<String>();
    if (types.contains('postal_code')) postal = c['long_name'];
    if (types.contains('locality')) city = c['long_name'];
    if (types.contains('administrative_area_level_1')) state = c['long_name'];
    if (types.contains('route')) route = c['long_name'];
    if (types.contains('sublocality') || types.contains('sublocality_level_1')) {
      sublocality = c['long_name'];
    }
  }

  final line1 = [route].where((e) => (e ?? '').isNotEmpty).join(', ');
  final line2 = [sublocality, city].where((e) => (e ?? '').isNotEmpty).join(', ');

  return {
    'line1': line1,
    'line2': line2,
    'city': city ?? '',
    'state': state ?? '',
    'pincode': postal ?? '',
    'formatted': results.first['formatted_address'] ?? '',
  };
}

Future<LatLng?> _forwardGeocodeWeb(String query) async {
  final uri = Uri.parse(
    'https://maps.googleapis.com/maps/api/geocode/json'
        '?address=${Uri.encodeComponent(query)}&key=$_gmapsKey',
  );
  final res = await http.get(uri);
  if (res.statusCode != 200) return null;
  final data = json.decode(res.body);
  final results = (data['results'] as List?) ?? [];
  if (data['status'] != 'OK' || results.isEmpty) return null;

  final loc = results.first['geometry']['location'];
  return LatLng((loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble());
}


class _AddAddressScreenState extends State<AddAddressScreen> with TickerProviderStateMixin {

  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _recipientNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressLine1Controller = TextEditingController();
  final _addressLine2Controller = TextEditingController();
  final _landmarkController = TextEditingController();
  final _pincodeController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();


  String selectedAddressType = 'Home';
  bool isDefault = false;
  bool isLoading = false;
  bool isServiceAvailable = true;
  bool isCheckingService = false;
  bool isDetectingLocation = false;

  // Location variables
  Position? currentPosition;
  double? latitude;
  double? longitude;
  bool _showMap = false;
  bool _hasSelectedLocation = false;

  Set<Marker> _markers = {};
  bool _isLoadingAddress = false;
  bool _isSearching = false;

  LatLng? _selectedLocation;
  GoogleMapController? _mapController;
  final TextEditingController _searchController = TextEditingController();

  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  Position? _currentPosition;
  String? _selectedAddress;

  Future<void> _moveCameraAndSetLocation(LatLng latLng) async {
    _selectedLocation = latLng;

    if (_mapController != null) {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(latLng, 16),
      );
    }

    await _onMapTap(latLng); // fetch address and set selected
  }



  @override
  void initState() {
    super.initState();
    if (widget.existingAddress != null) {
      _showMap = false;
      _populateFields();
    } else {
      _showMap = true;
      _getCurrentLocationOnInit();
    }

    if (widget.preselectedLocation != null) {
      _populateFromMapSelection();
    }

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    _slideController.forward();
  }

  Future<void> _onMapTap(LatLng location) async {
    setState(() {
      _selectedLocation = location;
      _isLoadingAddress = true;
    });

    try {
      if (kIsWeb) {
        final data = await _reverseGeocodeWeb(location);
        if (data.isNotEmpty) {
          _addressLine1Controller.text = data['line1'] ?? '';
          _addressLine2Controller.text = data['line2'] ?? '';
          _cityController.text = data['city'] ?? '';
          _stateController.text = data['state'] ?? '';
          _pincodeController.text = data['pincode'] ?? '';
          latitude = location.latitude;
          longitude = location.longitude;
          _selectedAddress = data['formatted'] ?? '';
        }
      } else {
        final placemarks = await placemarkFromCoordinates(
          location.latitude, location.longitude,
        );
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          final address =
              '${place.street ?? ''}, ${place.locality ?? ''}, ${place.postalCode ?? ''}';
          _addressLine1Controller.text = place.street ?? '';
          _cityController.text = place.locality ?? '';
          _pincodeController.text = place.postalCode ?? '';
          _stateController.text = place.administrativeArea ?? '';
          latitude = location.latitude;
          longitude = location.longitude;
          _selectedAddress = address;
        }
      }
    } catch (e) {
      print('Error getting address from tap: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingAddress = false);
      }
    }
  }


  Future<void> _getCurrentLocationOnInit() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final latLng = LatLng(position.latitude, position.longitude);

      setState(() {
        currentPosition = position;
        latitude = position.latitude;
        longitude = position.longitude;
        _hasSelectedLocation = true;
      });

      _selectedLocation = latLng;
      if (_mapController != null) {
        await _mapController!.animateCamera(CameraUpdate.newLatLngZoom(latLng, 16));
      }

      // Update address immediately
      await _onMapTap(latLng);

      // (No snackbar here)

    } catch (e) {
      // Silent fail is OK for init; keep your log if you want
      print('Auto location detection failed: $e');
    }
  }


  void _populateFields() {
    final address = widget.existingAddress!;
    _recipientNameController.text = address['recipient_name'] ?? '';
    _phoneController.text = address['phone_number'] ?? '';
    _addressLine1Controller.text = address['address_line_1'] ?? '';
    _addressLine2Controller.text = address['address_line_2'] ?? '';
    _landmarkController.text = address['landmark'] ?? '';
    _pincodeController.text = address['pincode'] ?? '';
    _cityController.text = address['city'] ?? '';
    _stateController.text = address['state'] ?? '';
    selectedAddressType = address['address_type'] ?? 'Home';
    isDefault = address['is_default'] ?? false;
    latitude = address['latitude']?.toDouble();
    longitude = address['longitude']?.toDouble();

    if (latitude != null && longitude != null) {
      _addMarker(LatLng(latitude!, longitude!));
      _hasSelectedLocation = true;
    }
  }

  void _populateFromMapSelection() {
    if (widget.preselectedLocation != null) {
      latitude = widget.preselectedLocation!.latitude;
      longitude = widget.preselectedLocation!.longitude;
      _addMarker(widget.preselectedLocation!);
      _hasSelectedLocation = true;

      if (widget.preselectedAddress != null) {
        _parseAddressString(widget.preselectedAddress!);
      }
    }
  }

  void _parseAddressString(String addressString) {
    List<String> parts = addressString.split(', ');
    if (parts.isNotEmpty) {
      _addressLine1Controller.text = parts[0];
      if (parts.length > 1) {
        _addressLine2Controller.text = parts[1];
      }
      if (parts.length > 2) {
        _cityController.text = parts[2];
      }

      if (parts.isNotEmpty) {
        String lastPart = parts.last;
        RegExp pincodeRegex = RegExp(r'\b\d{6}\b');
        Match? match = pincodeRegex.firstMatch(lastPart);
        if (match != null) {
          _pincodeController.text = match.group(0)!;
          String stateText = lastPart.replaceAll(match.group(0)!, '').trim();
          stateText = stateText.replaceAll('-', '').trim();
          _stateController.text = stateText;
        }
      }
    }
  }

  Future<void> _searchLocation(String query) async {
    if (query.trim().isEmpty) return;

    setState(() => _isSearching = true);

    try {
      LatLng? newPosition;
      if (kIsWeb) {
        newPosition = await _forwardGeocodeWeb(query);
      } else {
        final locations = await locationFromAddress(query);
        if (locations.isNotEmpty) {
          final l = locations.first;
          newPosition = LatLng(l.latitude, l.longitude);
        }
      }

      if (newPosition != null) {
        _addMarker(newPosition);
        if (_mapController != null) {
          await _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(newPosition, 15),
          );
        }
        setState(() => _searchController.clear());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location found successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not find location: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }


  Future<void> _checkServiceAvailability(String pincode) async {
    if (pincode.length != 6) return;

    setState(() {
      isCheckingService = true;
    });

    try {
      final response = await supabase
          .from('service_areas')
          .select()
          .eq('pincode', pincode)
          .eq('is_active', true)
          .maybeSingle();

      setState(() {
        isServiceAvailable = response != null;
        isCheckingService = false;
      });
    } catch (e) {
      print("Error checking service availability: $e");
      setState(() {
        isServiceAvailable = false;
        isCheckingService = false;
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      isDetectingLocation = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled. Please enable them in settings.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied');
      }

      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final latLng = LatLng(position.latitude, position.longitude);

      // Save coords
      setState(() {
        currentPosition = position;
        latitude = position.latitude;
        longitude = position.longitude;
        _hasSelectedLocation = true;
      });

      // Center the map immediately (preserve current zoom)
      _selectedLocation = latLng;
      if (_mapController != null) {
        try {
          final currentZoom = await _mapController!.getZoomLevel();
          await _mapController!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(target: latLng, zoom: currentZoom),
            ),
          );
        } catch (_) {
          // Fallback if getZoomLevel() isn't available on a platform
          await _mapController!.animateCamera(CameraUpdate.newLatLng(latLng));
        }
      }

// Update address right away (don’t wait for onCameraIdle)
      await _onMapTap(latLng);


      // ❌ Removed the green success snackbar

    } catch (e) {
      setState(() {
        isDetectingLocation = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error detecting location: ${e.toString()}'),
          backgroundColor: Colors.red,
          action: e.toString().contains('disabled')
              ? SnackBarAction(
            label: 'Settings',
            onPressed: () => Geolocator.openLocationSettings(),
          )
              : null,
        ),
      );
      return;
    }

    setState(() {
      isDetectingLocation = false;
    });
  }


  void _proceedToForm() {
    if (!_hasSelectedLocation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a location on the map'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _showMap = false;
    });
  }

  void _goBackToMap() {
    setState(() {
      _showMap = true;
    });
  }

  void _addMarker(LatLng position) {
    setState(() {
      latitude = position.latitude;
      longitude = position.longitude;
      _hasSelectedLocation = true;
      _markers.clear();
      _markers.add(Marker(
        markerId: const MarkerId('selectedLocation'),
        position: position,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        draggable: true,
        onDragEnd: (newPosition) {
          _addMarker(newPosition);
          _getAddressFromCoordinates(newPosition);
        },
      ));
    });

    _getAddressFromCoordinates(position);
  }

  Future<void> _getAddressFromCoordinates(LatLng position) async {
    setState(() => _isLoadingAddress = true);

    try {
      if (kIsWeb) {
        final data = await _reverseGeocodeWeb(position);
        if (data.isNotEmpty) {
          _addressLine1Controller.text = data['line1'] ?? '';
          _addressLine2Controller.text = data['line2'] ?? '';
          _cityController.text = data['city'] ?? '';
          _stateController.text = data['state'] ?? '';
          _pincodeController.text = data['pincode'] ?? '';
          if ((data['pincode'] ?? '').length == 6) {
            _checkServiceAvailability(data['pincode']!);
          }
        }
      } else {
        final placemarks = await placemarkFromCoordinates(
          position.latitude, position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          _addressLine1Controller.text =
              '${place.street ?? ''} ${place.name ?? ''}'.trim();
          _addressLine2Controller.text =
              '${place.subLocality ?? ''} ${place.locality ?? ''}'.trim();
          _landmarkController.text = place.subThoroughfare ?? '';
          _cityController.text = place.locality ?? '';
          _stateController.text = place.administrativeArea ?? '';
          _pincodeController.text = place.postalCode ?? '';
          if ((place.postalCode ?? '').length == 6) {
            _checkServiceAvailability(place.postalCode!);
          }
        }
      }
    } catch (e) {
      print('Error getting address: $e');
    } finally {
      if (mounted) setState(() => _isLoadingAddress = false);
    }
  }


  Future<void> _saveAddress() async {
    // First validate the form
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all required fields correctly'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Check service availability
    if (!isServiceAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Service not available in this pincode'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validate pincode length
    if (_pincodeController.text.trim().length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid 6-digit pincode'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validate location selection
    if (latitude == null || longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a location on the map first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => isLoading = true);

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User not logged in'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final nowIso = DateTime.now().toIso8601String();

      // Prepare address data - ensure no null values for required fields
      final addressData = {
        'user_id': userId,
        'recipient_name': _recipientNameController.text.trim(),
        'phone_number': _phoneController.text.trim(),
        'address_line_1': _addressLine1Controller.text.trim(),
        'address_line_2': _addressLine2Controller.text.trim().isNotEmpty
            ? _addressLine2Controller.text.trim()
            : null,
        'landmark': _landmarkController.text.trim().isNotEmpty
            ? _landmarkController.text.trim()
            : null,
        'pincode': _pincodeController.text.trim(),
        'city': _cityController.text.trim(),
        'state': _stateController.text.trim(),
        'address_type': selectedAddressType,
        'is_default': isDefault,
        'latitude': latitude,
        'longitude': longitude,
        'updated_at': nowIso,
      };

      print('Saving address data: $addressData');

      // If this address should be default, unset all others first
      if (isDefault) {
        await supabase
            .from('user_addresses')
            .update({'is_default': false})
            .eq('user_id', userId);
      }

      if (widget.existingAddress != null) {
        // EDIT FLOW
        final id = widget.existingAddress!['id'];

        // For edit, ensure we don't conflict with unique constraint
        if (isDefault) {
          await supabase
              .from('user_addresses')
              .update({'is_default': false})
              .eq('user_id', userId)
              .neq('id', id);
        }

        final response = await supabase
            .from('user_addresses')
            .update(addressData)
            .eq('id', id)
            .eq('user_id', userId);

        print('Update response: $response');
      } else {
        // CREATE FLOW
        final dataToInsert = {
          ...addressData,
          'created_at': nowIso,
        };

        final response = await supabase
            .from('user_addresses')
            .insert(dataToInsert);

        print('Insert response: $response');
      }

      // Success
      if (mounted) {
        widget.onAddressSaved();
        Navigator.pop(context);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.existingAddress != null
                ? 'Address updated successfully'
                : 'Address added successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print("Error saving address: $e");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving address: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }




  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      // ❗ No AppBar on map view
      appBar: _showMap
          ? null
          : AppBar(
        elevation: 0,
        backgroundColor: Colors.yellow, // ✅ Changed from blue to yellow
        automaticallyImplyLeading: true,
        title: Text(
          widget.existingAddress != null ? "Edit Address" : "Add Address",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
        ),
        actions: [
          IconButton(
            onPressed: _goBackToMap,
            icon: const Icon(Icons.map, color: Colors.white),
            tooltip: 'Select on map',
          ),
        ],
      ),

      body: _showMap ? _buildMapView() : _buildFormView(),
    );
  }


  Widget _buildMapView() {
    final topPad = MediaQuery.of(context).padding.top;

    // layout constants
    const double sideGap = 12;
    const double circleDiameter = 40;
    const double betweenGap = 8;

    final double searchLeft = sideGap + circleDiameter + betweenGap;
    final double searchRight = sideGap;

    // 🔧 Lift the visual pin so its TIP sits at the map center (logical px)
    // For a ~70px tall pin, 28–32 works well. Tune if you change the asset.
    const double pinTipLift = 30;

    // ✅ Confirm button style: Solid Blue + premium shape
    final ButtonStyle confirmStyle = ElevatedButton.styleFrom(
      elevation: 2,
      backgroundColor: kPrimaryColor, // solid blue
      foregroundColor: Colors.white,  // text & loader white
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12), // premium 12px radius
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
    );

    return Stack(
      children: [
        // --- MAP ---
        GoogleMap(
          onMapCreated: (GoogleMapController controller) {
            _mapController = controller;
          },
          initialCameraPosition: CameraPosition(
            target: _selectedLocation ?? const LatLng(20.2961, 85.8245),
            zoom: 15.0,
          ),
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,

          // Keep track of the visual center (not the pin tip yet)
          onCameraMove: (CameraPosition p) => _selectedLocation = p.target,

          // When camera stops, compute the TIP LatLng and reverse-geocode that
          onCameraIdle: () async {
            if (_selectedLocation == null || _mapController == null) return;

            // Convert the visual center to screen coords, then shift UP by the
            // amount we visually lifted the pin so we get the TIP position.
            final dpr = MediaQuery.of(context).devicePixelRatio;
            final centerScreen =
            await _mapController!.getScreenCoordinate(_selectedLocation!);
            final tipScreen = ScreenCoordinate(
              x: centerScreen.x,
              y: (centerScreen.y - (pinTipLift * dpr)).round(),
            );

            final tipLatLng = await _mapController!.getLatLng(tipScreen);

            // Now reverse-geocode / update address based on the TIP's LatLng
            await _onMapTap(tipLatLng);
          },
        ),

        // --- CENTER PIN (tip aligned) ---
        Center(
          child: IgnorePointer(
            ignoring: true,
            child: Transform.translate(
              offset: const Offset(0, -pinTipLift),
              child: Container(
                decoration: BoxDecoration(
                  boxShadow: [
                    // Soft shadow for contrast on light map tiles
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/images/blue_pin.png',
                  width: 70,
                  height: 70,
                  filterQuality: FilterQuality.high, // crisper scaling
                ),
              ),
            ),
          ),
        ),

        // --- TOP LEFT BACK BUTTON ---
        Positioned(
          top: topPad + 8,
          left: sideGap,
          child: Material(
            color: Colors.white,
            shape: const CircleBorder(),
            elevation: 2,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.pop(context),
              child: SizedBox(
                width: circleDiameter,
                height: circleDiameter,
                child: Center(
                  child: Icon(Icons.arrow_back, size: 20, color: kPrimaryColor),
                ),
              ),
            ),
          ),
        ),

        // --- SEARCH PILL with WHITE background ---
        Positioned(
          top: topPad + 8,
          left: searchLeft,
          right: searchRight,
          child: SlideTransition(
            position: _slideAnimation,
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white, // ✅ Solid white background
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.grey.shade300, width: 1), // Added border for visibility
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TypeAheadField<Map<String, String>>(
                  controller: _searchController,
                  suggestionsCallback: (pattern) async {
                    if (pattern.trim().isEmpty) return [];

                    try {
                      final uri = Uri.parse(
                        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
                            '?input=${Uri.encodeComponent(pattern)}'
                            '&types=geocode'
                            '&components=country:in'
                            '&key=$_gmapsKey',
                      );

                      final res = await http.get(uri);
                      if (res.statusCode != 200) return [];

                      final data = json.decode(res.body);
                      if (data['status'] != 'OK') return [];

                      final List preds = (data['predictions'] as List?) ?? [];
                      return preds
                          .map<Map<String, String>>((p) => {
                        'description': (p['description'] ?? '').toString(),
                        'place_id': (p['place_id'] ?? '').toString(),
                      })
                          .where((m) =>
                      (m['description'] ?? '').isNotEmpty &&
                          (m['place_id'] ?? '').isNotEmpty)
                          .take(8)
                          .toList();
                    } catch (_) {
                      return [];
                    }
                  },
                  itemBuilder: (context, prediction) {
                    return ListTile(
                      leading: Icon(Icons.location_on, color: kPrimaryColor),
                      title: Text(
                        prediction['description']!,
                        style: const TextStyle(fontSize: 14),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                  onSelected: (prediction) async {
                    try {
                      final detailsUri = Uri.parse(
                        'https://maps.googleapis.com/maps/api/place/details/json'
                            '?place_id=${prediction['place_id']}'
                            '&fields=geometry,formatted_address'
                            '&key=$_gmapsKey',
                      );
                      final res = await http.get(detailsUri);
                      if (res.statusCode == 200) {
                        final data = json.decode(res.body);
                        if (data['status'] == 'OK') {
                          final loc = data['result']?['geometry']?['location'] as Map?;
                          if (loc != null) {
                            final lat = (loc['lat'] as num).toDouble();
                            final lng = (loc['lng'] as num).toDouble();
                            final latLng = LatLng(lat, lng);

                            await _moveCameraAndSetLocation(latLng);

                            setState(() {
                              _selectedAddress = (data['result']
                              ?['formatted_address'] as String?) ??
                                  prediction['description']!;
                            });
                          }
                        }
                      }
                    } catch (_) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not fetch place location'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    } finally {
                      _searchController.clear();
                      FocusScope.of(context).unfocus();
                    }
                  },
                  builder: (context, controller, focusNode) {
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      style: const TextStyle(
                        color: Colors.black, // ✅ Changed text color to black
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlignVertical: TextAlignVertical.center,
                      decoration: InputDecoration(
                        hintText: 'Search area, address or pincode',
                        hintStyle: TextStyle(
                          color: Colors.grey.shade600, // ✅ Changed hint to grey
                          fontSize: 15,
                        ),
                        filled: false, // ✅ Remove any fill color
                        fillColor: Colors.transparent, // ✅ Ensure transparent
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: Colors.grey.shade700, // ✅ Changed icon to grey
                          size: 20,
                        ),
                        suffixIcon: controller.text.isNotEmpty
                            ? IconButton(
                          icon: Icon(Icons.close_rounded,
                              color: Colors.grey.shade700), // ✅ Changed close icon to grey
                          onPressed: () {
                            controller.clear();
                            FocusScope.of(context).unfocus();
                          },
                        )
                            : null,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),

        // --- BOTTOM STACK ---
        SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Current Location Button
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: isDetectingLocation ? null : _getCurrentLocation,
                      icon: isDetectingLocation
                          ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.my_location,
                          size: 20, color: Colors.white),
                      label: const Text(
                        'Current Location',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryColor,
                        elevation: 6,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Address Card
                  Container(
                    padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Text(
                      _selectedAddress ?? 'Fetching address...',
                      style: TextStyle(
                        color: kPrimaryColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ✅ Confirm Button (solid blue now)
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _selectedLocation != null && !_isLoadingAddress
                          ? _proceedToForm
                          : null,
                      style: confirmStyle,
                      child: _isLoadingAddress
                          ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.2))
                          : const Text(
                        'Confirm and Proceed',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }







  Widget _loadingSuggestionTile() {
    return ListTile(
      leading: Icon(Icons.location_on, color: Color(0xFF42A5F5)),
      title: Text('Loading...', style: TextStyle(color: Color(0xFF42A5F5))),
    );
  }


  Widget _buildFormView() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (latitude != null && longitude != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: InkWell(
                        onTap: _goBackToMap,
                        child: Row(
                          children: [
                            Icon(Icons.location_on,
                                color: Colors.green.shade600, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Location selected from map',
                                    style: TextStyle(
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    'Tap to change location',
                                    style: TextStyle(
                                      color: Colors.green.shade600,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.edit,
                              color: Colors.green.shade600,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),

                  _buildSectionTitle('Contact Information'),

                  // FULL NAME — alphabets + spaces only
                  _buildTextField(
                    controller: _recipientNameController,
                    label: 'Full Name',
                    hint: 'Enter recipient name',
                    icon: Icons.person_outline,
                    validator: (value) {
                      if (value?.trim().isEmpty ?? true) {
                        return 'Name is required';
                      }
                      final v = value!.trim();

                      // Allow only letters (Unicode) and spaces
                      final nameOk = RegExp(r'^[\p{L} ]+$', unicode: true).hasMatch(v);
                      if (!nameOk) {
                        return 'Only alphabets and spaces are allowed';
                      }

                      // Optional: basic length sanity
                      if (v.replaceAll(' ', '').length < 2) {
                        return 'Enter a valid name';
                      }
                      return null;
                    },
                    inputFormatters: [
                      // Block non-letter characters while typing
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[\p{L} ]', unicode: true),
                      ),
                      LengthLimitingTextInputFormatter(50),
                    ],
                  ),

                  const SizedBox(height: 16),

                  _buildTextField(
                    controller: _phoneController,
                    label: 'Phone Number',
                    hint: 'Enter 10-digit phone number',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    validator: (value) {
                      if (value?.trim().isEmpty ?? true) {
                        return 'Phone number is required';
                      }
                      if (value!.length != 10) {
                        return 'Enter valid 10-digit phone number';
                      }
                      // Check if phone number starts with 6-9
                      String firstDigit = value[0];
                      if (!['6', '7', '8', '9'].contains(firstDigit)) {
                        return 'Phone number must start with 6, 7, 8, or 9';
                      }
                      // Check if all characters are digits
                      if (!RegExp(r'^[0-9]+$').hasMatch(value)) {
                        return 'Phone number must contain only digits';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 24),

                  _buildSectionTitle('Address Details'),
                  _buildTextField(
                    controller: _addressLine1Controller,
                    label: 'Address Line 1',
                    hint: 'House/Flat/Office No, Building Name',
                    icon: Icons.home_outlined,
                    validator: (value) {
                      if (value?.trim().isEmpty ?? true) {
                        return 'Address is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _addressLine2Controller,
                    label: 'Address Line 2 (Optional)',
                    hint: 'Area, Street, Sector, Village',
                    icon: Icons.location_on_outlined,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _landmarkController,
                    label: 'Landmark (Optional)',
                    hint: 'Nearby landmark',
                    icon: Icons.place_outlined,
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _buildTextField(
                          controller: _pincodeController,
                          label: 'Pincode',
                          hint: '000000',
                          icon: Icons.pin_drop_outlined,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          validator: (value) {
                            if (value?.trim().isEmpty ?? true) {
                              return 'Pincode is required';
                            }
                            if (value!.length != 6) {
                              return 'Enter valid 6-digit pincode';
                            }
                            // Check if all characters are digits
                            if (!RegExp(r'^[0-9]+$').hasMatch(value)) {
                              return 'Pincode must contain only digits';
                            }
                            return null;
                          },
                          onChanged: (value) {
                            if (value.length == 6) {
                              _checkServiceAvailability(value);
                              _fetchLocationFromPincode(value);
                            } else {
                              setState(() {
                                isServiceAvailable = true;
                                isCheckingService = false;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 3,
                        child: _buildTextField(
                          controller: _cityController,
                          label: 'City',
                          hint: 'Enter city',
                          icon: Icons.location_city_outlined,
                          validator: (value) {
                            if (value?.trim().isEmpty ?? true) {
                              return 'City is required';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _stateController,
                    label: 'State',
                    hint: 'Enter state',
                    icon: Icons.map_outlined,
                    validator: (value) {
                      if (value?.trim().isEmpty ?? true) {
                        return 'State is required';
                      }
                      return null;
                    },
                  ),

                  if (_pincodeController.text.length == 6) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isCheckingService
                            ? Colors.orange.shade50
                            : isServiceAvailable
                            ? Colors.green.shade50
                            : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isCheckingService
                              ? Colors.orange.shade200
                              : isServiceAvailable
                              ? Colors.green.shade200
                              : Colors.red.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          if (isCheckingService)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Icon(
                              isServiceAvailable
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              color: isServiceAvailable
                                  ? Colors.green
                                  : Colors.red,
                              size: 16,
                            ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isCheckingService
                                  ? 'Checking service availability...'
                                  : isServiceAvailable
                                  ? 'Service available in this area'
                                  : 'Service not available in this pincode',
                              style: TextStyle(
                                color: isCheckingService
                                    ? Colors.orange.shade700
                                    : isServiceAvailable
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  _buildSectionTitle('Address Type'),
                  _buildAddressTypeSelector(),
                  const SizedBox(height: 16),

                  CheckboxListTile(
                    value: isDefault,
                    onChanged: (value) {
                      setState(() {
                        isDefault = value ?? false;
                      });
                    },
                    title: const Text('Set as default address'),
                    subtitle: const Text('Use this address for future orders'),
                    activeColor: kPrimaryColor,
                    contentPadding: EdgeInsets.zero,
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),

          // Footer
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
              color: Colors.white,
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _saveAddress,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black, // Changed from kPrimaryColor to black
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 8,
                      shadowColor: Colors.black.withOpacity(0.3), // Changed shadow color
                    ),
                    child: isLoading
                        ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    )
                        : Text(
                      widget.existingAddress != null
                          ? 'Update Address'
                          : 'Save Address',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


// ALSO ADD THIS NEW METHOD TO YOUR CLASS:
  Future<void> _fetchLocationFromPincode(String pincode) async {
    if (pincode.length != 6) return;

    try {
      if (kIsWeb) {
        final loc = await _forwardGeocodeWeb('$pincode, India');
        if (loc != null) {
          final data = await _reverseGeocodeWeb(loc);
          setState(() {
            _cityController.text = data['city'] ?? '';
            _stateController.text = data['state'] ?? '';
            latitude ??= loc.latitude;
            longitude ??= loc.longitude;
          });
        }
      } else {
        final locations = await locationFromAddress('$pincode, India');
        if (locations.isNotEmpty) {
          final l = locations.first;
          final placemarks = await placemarkFromCoordinates(l.latitude, l.longitude);
          if (placemarks.isNotEmpty) {
            final place = placemarks.first;
            setState(() {
              _cityController.text =
                  place.locality ?? place.subAdministrativeArea ?? '';
              _stateController.text = place.administrativeArea ?? '';
              latitude ??= l.latitude;
              longitude ??= l.longitude;
            });
          }
        }
      }
    } catch (e) {
      print('Error fetching location from pincode: $e');
    }
  }


  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      onChanged: onChanged,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      style: const TextStyle(color: Colors.black), // ✅ Text input color black
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.black), // ✅ Label color black
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400), // Hint text grey
        filled: false,
        fillColor: Colors.transparent,
        prefixIcon: icon == Icons.phone_outlined
            ? Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 12),
            Icon(icon, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(
              '+91 ',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        )
            : Icon(icon, color: Colors.grey.shade600),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: kPrimaryColor),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.red),
        ),
        counterText: maxLength != null ? '' : null,
        counterStyle: const TextStyle(color: Colors.black), // ✅ Counter text black
      ),
    );
  }




  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.black, // Changed from yellow to black
        ),
      ),
    );
  }



  Widget _buildAddressTypeSelector() {
    final types = ['Home', 'Office', 'Other'];

    return Row(
      children: types.map((type) {
        bool isSelected = selectedAddressType == type;
        return Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                selectedAddressType = type;
              });
            },
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? kPrimaryColor : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? kPrimaryColor : Colors.grey.shade300,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    type == 'Home'
                        ? Icons.home
                        : type == 'Office'
                        ? Icons.business
                        : Icons.location_on,
                    color: isSelected ? Colors.white : Colors.grey.shade600,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    type,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  void dispose() {
    _recipientNameController.dispose();
    _phoneController.dispose();
    _addressLine1Controller.dispose();
    _addressLine2Controller.dispose();
    _landmarkController.dispose();
    _pincodeController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _searchController.dispose();
    _mapController?.dispose();
    _slideController.dispose();

    super.dispose();
  }
}


