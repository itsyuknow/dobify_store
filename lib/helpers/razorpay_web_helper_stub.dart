// This file is imported on mobile platforms (does nothing)
void openRazorpayWeb(Map<String, dynamic> options) {
  throw UnsupportedError('Web Razorpay is not supported on mobile');
}

void setupWebCallbacks({
  required Function(String) onSuccess,
  required Function() onDismiss,
  required Function(String) onError,
}) {
  // Do nothing on mobile
}

String createOptionsJson({
  required String razorpayKeyId,
  required int payablePaise,
  required String orderId,
  required String phone,
  required String email,
  required String colorHex,
}) {
  return '';
}