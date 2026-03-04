import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../providers/auth_provider.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  Map<String, dynamic>? _subscription;
  List<dynamic> _paymentHistory = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSubscription();
    _loadPaymentHistory();
  }

  Future<void> _loadSubscription() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      final subscription = await apiService.getCurrentSubscription();
      setState(() {
        _subscription = subscription;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadPaymentHistory() async {
    try {
      final apiService = ref.read(apiServiceProvider);
      final payments = await apiService.getPaymentHistory();
      setState(() {
        _paymentHistory = payments;
      });
    } catch (e) {
      // Silently fail for payment history
      print('Failed to load payment history: $e');
    }
  }

  Future<void> _subscribe(String tier, String billingPeriod) async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final apiService = ref.read(apiServiceProvider);
      final result = await apiService.createCheckoutSession(
        tier: tier,
        billingPeriod: billingPeriod,
        successUrl: 'nutrify://subscription/success',
        cancelUrl: 'nutrify://subscription/cancel',
      );

      final url = result['url'] as String;
      if (await canLaunch(url)) {
        await launch(url);
      } else {
        throw 'Could not launch $url';
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create checkout: $e')),
      );
    }
  }

  Future<void> _openCustomerPortal() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final apiService = ref.read(apiServiceProvider);
      final result = await apiService.createPortalSession(
        returnUrl: 'nutrify://subscription',
      );

      final url = result['url'] as String;
      if (await canLaunch(url)) {
        await launch(url);
      } else {
        throw 'Could not launch $url';
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open portal: $e')),
      );
    }
  }

  Future<void> _cancelSubscription() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Subscription'),
        content: const Text(
          'Are you sure you want to cancel your subscription? '
          'You will still have access until the end of your billing period.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      setState(() {
        _isLoading = true;
      });

      final apiService = ref.read(apiServiceProvider);
      await apiService.cancelSubscription();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Subscription will be canceled at the end of the billing period'),
        ),
      );

      await _loadSubscription();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to cancel: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription'),
        actions: [
          if (_subscription != null && _subscription!['tier'] != 'free')
            IconButton(
              icon: const Icon(Icons.manage_accounts),
              onPressed: _openCustomerPortal,
              tooltip: 'Manage Subscription',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _loadSubscription();
                await _loadPaymentHistory();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null)
                      Card(
                        color: Colors.red.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(Icons.error, color: Colors.red.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: TextStyle(color: Colors.red.shade700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    _buildCurrentPlanCard(),
                    const SizedBox(height: 24),
                    if (_subscription == null || _subscription!['tier'] == 'free')
                      _buildUpgradeSection(),
                    if (_paymentHistory.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildPaymentHistorySection(),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildCurrentPlanCard() {
    final tier = _subscription?['tier'] ?? 'free';
    final status = _subscription?['status'] ?? 'active';
    final cancelAtPeriodEnd = _subscription?['cancel_at_period_end'] ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Current Plan',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Chip(
                  label: Text(tier.toUpperCase()),
                  backgroundColor: tier == 'premium'
                      ? Colors.purple.shade100
                      : tier == 'enterprise'
                          ? Colors.blue.shade100
                          : Colors.grey.shade200,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (tier != 'free') ...[
              _buildInfoRow('Status', status),
              _buildInfoRow(
                'Billing',
                _subscription?['billing_period'] ?? 'N/A',
              ),
              _buildInfoRow(
                'Amount',
                '₹${_subscription?['amount'] ?? 0}',
              ),
              if (_subscription?['current_period_end'] != null)
                _buildInfoRow(
                  cancelAtPeriodEnd ? 'Expires' : 'Renews',
                  _formatDate(_subscription!['current_period_end']),
                ),
              if (cancelAtPeriodEnd)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Your subscription will be canceled at the end of the billing period.',
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              if (!cancelAtPeriodEnd)
                ElevatedButton(
                  onPressed: _cancelSubscription,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                  ),
                  child: const Text('Cancel Subscription'),
                ),
            ] else ...[
              const Text('You are on the free plan with limited features.'),
              const SizedBox(height: 8),
              const Text('Upgrade to Premium or Enterprise for:'),
              const SizedBox(height: 8),
              _buildFeatureBullet('Adaptive AI-powered plans'),
              _buildFeatureBullet('Auto-tracking and analysis'),
              _buildFeatureBullet('Advanced insights'),
              _buildFeatureBullet('Priority support'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUpgradeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Upgrade Your Plan',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        _buildPlanCard(
          'Premium',
          '₹1,249/month',
          'Perfect for individuals',
          [
            'Adaptive AI nutrition plans',
            'Adaptive AI workout plans',
            'Auto-tracking & analysis',
            'Advanced insights',
            'Priority support',
          ],
          Colors.purple,
          () => _subscribe('premium', 'monthly'),
        ),
        const SizedBox(height: 16),
        _buildPlanCard(
          'Premium Yearly',
          '₹9,999/year',
          'Save 33% with annual billing',
          [
            'All Premium features',
            '4 months free',
          ],
          Colors.purple.shade700,
          () => _subscribe('premium', 'yearly'),
        ),
      ],
    );
  }

  Widget _buildPlanCard(
    String name,
    String price,
    String description,
    List<String> features,
    Color color,
    VoidCallback onSubscribe,
  ) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  name,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Text(
                  price,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            ...features.map((feature) => _buildFeatureBullet(feature)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onSubscribe,
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Subscribe Now'),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                '14-day free trial included',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Payment History',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        ..._paymentHistory.map((payment) => Card(
              child: ListTile(
                leading: Icon(
                  payment['status'] == 'succeeded'
                      ? Icons.check_circle
                      : Icons.error,
                  color: payment['status'] == 'succeeded'
                      ? Colors.green
                      : Colors.red,
                ),
                title: Text('₹${payment['amount']}'),
                subtitle: Text(_formatDate(payment['created_at'])),
                trailing: Chip(
                  label: Text(payment['status']),
                  backgroundColor: payment['status'] == 'succeeded'
                      ? Colors.green.shade100
                      : Colors.red.shade100,
                ),
              ),
            )),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Text(value),
        ],
      ),
    );
  }

  Widget _buildFeatureBullet(String feature) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.check, size: 20, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(child: Text(feature)),
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateStr;
    }
  }
}
