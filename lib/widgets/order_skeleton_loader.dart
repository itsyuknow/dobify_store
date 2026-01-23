import 'package:flutter/material.dart';

class OrderSkeletonLoader extends StatefulWidget {
  const OrderSkeletonLoader({super.key});

  @override
  State<OrderSkeletonLoader> createState() => _OrderSkeletonLoaderState();
}

class _OrderSkeletonLoaderState extends State<OrderSkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5, // Show 5 skeleton cards
      itemBuilder: (context, index) => _buildSkeletonCard(),
    );
  }

  Widget _buildSkeletonCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[800]!, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              children: [
                _buildShimmerBox(40, 40, borderRadius: 8),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildShimmerBox(120, 16, borderRadius: 4),
                      const SizedBox(height: 6),
                      _buildShimmerBox(180, 12, borderRadius: 4),
                    ],
                  ),
                ),
                _buildShimmerBox(80, 28, borderRadius: 20),
              ],
            ),
            const SizedBox(height: 16),

            // Info Boxes Row
            Row(
              children: [
                Expanded(child: _buildSkeletonInfoBox()),
                const SizedBox(width: 12),
                Expanded(child: _buildSkeletonInfoBox()),
              ],
            ),
            const SizedBox(height: 12),

            // Time Info Box
            _buildSkeletonInfoBox(fullWidth: true),
            const SizedBox(height: 16),

            // Button
            _buildShimmerBox(double.infinity, 48, borderRadius: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonInfoBox({bool fullWidth = false}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildShimmerBox(60, 10, borderRadius: 4),
          const SizedBox(height: 6),
          _buildShimmerBox(fullWidth ? 150 : 80, 14, borderRadius: 4),
        ],
      ),
    );
  }

  Widget _buildShimmerBox(
      double width,
      double height, {
        double borderRadius = 4,
      }) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.grey[800]!.withOpacity(_animation.value),
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        );
      },
    );
  }
}