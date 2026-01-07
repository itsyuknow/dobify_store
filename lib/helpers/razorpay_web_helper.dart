// lib/helpers/razorpay_web_helper.dart
// This file is ONLY imported on web
import 'dart:js' as js;

// Store callbacks at module level
Function(String)? _onSuccessCallback;
Function()? _onDismissCallback;
Function(String)? _onErrorCallback;

void setupWebCallbacks({
  required Function(String) onSuccess,
  required Function() onDismiss,
  required Function(String) onError,
}) {
  print('📝 Setting up Razorpay web callbacks');

  // Store callbacks
  _onSuccessCallback = onSuccess;
  _onDismissCallback = onDismiss;
  _onErrorCallback = onError;

  // Setup global handlers that Razorpay will call
  js.context['razorpaySuccessHandler'] = (dynamic response) {
    print('🎉 Razorpay success handler called');
    print('📦 Response type: ${response.runtimeType}');

    try {
      String? paymentId;
      String? orderId;
      String? signature;

      // Razorpay returns a JS object, we need to extract properties
      if (response != null) {
        // Try to get all possible fields
        try {
          // Check if response is a JsObject
          if (response is js.JsObject) {
            paymentId = response['razorpay_payment_id']?.toString();
            orderId = response['razorpay_order_id']?.toString();
            signature = response['razorpay_signature']?.toString();
          } else {
            // Try to convert to JsObject
            final jsObject = js.JsObject.fromBrowserObject(response);
            paymentId = jsObject['razorpay_payment_id']?.toString();
            orderId = jsObject['razorpay_order_id']?.toString();
            signature = jsObject['razorpay_signature']?.toString();
          }

          print('💳 Payment ID: $paymentId');
          print('🆔 Order ID: $orderId');
          if (signature != null && signature.isNotEmpty) {
            final length = signature.length > 10 ? 10 : signature.length;
            print('🔐 Signature: ${signature.substring(0, length)}...');
          } else {
            print('🔐 Signature: null');
          }
        } catch (e) {
          print('Direct access failed: $e');
        }

        // Last resort: Convert to string and parse
        if (paymentId == null) {
          try {
            String responseStr = response.toString();
            print('📄 Response string: $responseStr');

            // Try to extract payment ID from string representation
            final match = RegExp(r'razorpay_payment_id["\s:]+([a-zA-Z0-9_]+)').firstMatch(responseStr);
            if (match != null && match.groupCount > 0) {
              paymentId = match.group(1);
              print('💳 Payment ID (regex): $paymentId');
            }
          } catch (e) {
            print('String parsing failed: $e');
          }
        }
      }

      print('💳 Final Payment ID: $paymentId');

      if (paymentId != null && paymentId.isNotEmpty && paymentId != 'null') {
        print('✅ Valid payment ID found, calling callback');
        _onSuccessCallback?.call(paymentId);
        print('✅ Callback executed');
      } else {
        print('⚠️ No valid payment ID found');
        _onErrorCallback?.call('Payment ID not received from Razorpay');
      }
    } catch (e, stackTrace) {
      print('❌ Error in success handler: $e');
      print('📍 Stack: $stackTrace');
      _onErrorCallback?.call('Error processing payment: ${e.toString()}');
    }
  };

  js.context['razorpayDismissHandler'] = () {
    print('🚪 Razorpay dismiss handler called');
    try {
      _onDismissCallback?.call();
    } catch (e) {
      print('❌ Error in dismiss handler: $e');
    }
  };

  js.context['razorpayErrorHandler'] = (dynamic error) {
    print('💥 Razorpay error handler called: $error');
    try {
      final errorMsg = error?.toString() ?? 'Unknown payment error';
      _onErrorCallback?.call(errorMsg);
    } catch (e) {
      print('❌ Error in error handler: $e');
    }
  };

  print('✓ All callbacks registered');
}

void openRazorpayWeb(Map<String, dynamic> options) {
  try {
    print('🌐 Opening Razorpay on Web');
    print('📦 Options keys: ${options.keys.join(', ')}');

    // Check if Razorpay is loaded
    if (js.context['Razorpay'] == null) {
      throw Exception('Razorpay SDK not loaded. Check index.html');
    }

    // Ensure callbacks are set
    if (js.context['razorpaySuccessHandler'] == null) {
      throw Exception('Success handler not registered. Call setupWebCallbacks first.');
    }

    print('✅ Razorpay SDK found');
    print('✅ Success handler registered');

    // Create JS options object
    final jsOptions = js.JsObject.jsify({
      'key': options['key'],
      'amount': options['amount'],
      'currency': options['currency'] ?? 'INR',
      'order_id': options['order_id'],
      'name': options['name'] ?? 'Dobify',
      'description': options['description'] ?? 'Payment',
      'image': options['image'] ?? '',
      'prefill': {
        'contact': options['prefill']?['contact'] ?? '',
        'email': options['prefill']?['email'] ?? '',
      },
      'theme': {
        'color': options['theme']?['color'] ?? '#3399cc',
      },
      'modal': {
        'ondismiss': () {
          print('🚪 Modal dismissed via ondismiss');
          final dismissHandler = js.context['razorpayDismissHandler'];
          if (dismissHandler != null) {
            dismissHandler();
          }
        },
      },
      'handler': js.context['razorpaySuccessHandler'],
    });

    print('🚀 Creating Razorpay instance');
    print('🔑 Key: ${options['key']}');
    print('💰 Amount: ${options['amount']}');
    print('🆔 Order ID: ${options['order_id']}');

    // Get the Razorpay constructor and create instance
    final razorpayConstructor = js.context['Razorpay'];
    final razorpayInstance = js.JsObject(razorpayConstructor, [jsOptions]);

    print('🎬 Opening Razorpay modal');
    // Open the Razorpay modal
    razorpayInstance.callMethod('open');

    print('✅ Razorpay opened successfully');

  } catch (e, stackTrace) {
    print('❌ openRazorpayWeb error: $e');
    print('📍 Stack: $stackTrace');
    _onErrorCallback?.call('Failed to open payment: ${e.toString()}');
  }
}