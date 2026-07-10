import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/app_colors.dart';
import 'partner_models.dart';

/// Outcome the checkout screen resolves with. Mirrors the query params the
/// backend's `/admin/deposit/result` redirect carries.
class DepositOutcome {
  final String status; // success | failed | pending | cancelled
  final double amount;
  final String error;

  /// Payment succeeded but the wallet credit threw server-side; finance will
  /// reconcile. Treated as "not failed" so the partner isn't told it bounced.
  final bool pendingCredit;

  const DepositOutcome({
    required this.status,
    this.amount = 0,
    this.error = '',
    this.pendingCredit = false,
  });

  bool get isSuccess => status == 'success';
  bool get isCancelled => status == 'cancelled';
}

/// Runs the HyperPay COPYandPAY widget in a WebView.
///
/// The widget submits the card to HyperPay, runs 3-D Secure, then the whole
/// page redirects to the backend callback (`shopperResultUrl`), which credits
/// the wallet and 302-redirects to `${PORTAL}/admin/deposit/result?status=…`.
/// We intercept that final navigation, read the outcome, and pop — the app
/// never needs to know the portal's URL, only the `/admin/deposit/result`
/// path.
class DepositCheckoutScreen extends StatefulWidget {
  const DepositCheckoutScreen({super.key, required this.init});
  final DepositInit init;

  @override
  State<DepositCheckoutScreen> createState() => _DepositCheckoutScreenState();
}

class _DepositCheckoutScreenState extends State<DepositCheckoutScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _resolved = false; // guard: pop exactly once

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: _onNavigation,
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onWebResourceError: (err) {
          // The widget/3-D Secure pages load sub-resources that occasionally
          // error; only a hard main-frame failure is worth surfacing.
          if (err.isForMainFrame == true) {
            _resolve(const DepositOutcome(
                status: 'failed', error: 'Could not load the payment page.'));
          }
        },
      ))
      ..loadHtmlString(_html, baseUrl: _baseUrl);
  }

  /// Same origin as the shopperResultUrl (the backend callback), so the shell
  /// and the redirect target aren't cross-origin.
  String get _baseUrl {
    final u = Uri.tryParse(widget.init.shopperResultUrl);
    return u == null ? 'https://localhost' : '${u.scheme}://${u.host}';
  }

  NavigationDecision _onNavigation(NavigationRequest req) {
    final uri = Uri.tryParse(req.url);
    if (uri != null && uri.path.contains('/admin/deposit/result')) {
      final q = uri.queryParameters;
      _resolve(DepositOutcome(
        status: q['status'] ?? 'pending',
        amount: double.tryParse(q['amount'] ?? '') ?? widget.init.amount,
        error: q['error'] ?? '',
        pendingCredit: q['pendingCredit'] == '1',
      ));
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  void _resolve(DepositOutcome outcome) {
    if (_resolved || !mounted) return;
    _resolved = true;
    Navigator.of(context).pop(outcome);
  }

  Future<bool> _confirmCancel() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel payment?'),
        content: const Text(
            'Your deposit has not been completed. You can try again from '
            'the earnings screen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep paying')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancel')),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmCancel()) {
          _resolve(const DepositOutcome(status: 'cancelled'));
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Deposit AED ${widget.init.amount.toStringAsFixed(2)}'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () async {
              if (await _confirmCancel()) {
                _resolve(const DepositOutcome(status: 'cancelled'));
              }
            },
          ),
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading)
              const ColoredBox(
                color: Colors.white,
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.brand600),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The COPYandPAY shell. `paymentTarget:'_top'` makes the whole WebView
  /// navigate through 3-D Secure and on to the result (no iframe), which is
  /// exactly what we intercept.
  String get _html {
    final i = widget.init;
    final integrityAttrs = i.integrity.isEmpty
        ? ''
        : 'integrity="${i.integrity}" crossorigin="anonymous"';
    // shopperResultUrl is a server-issued backend URL; still HTML-escape the
    // quote just in case, so it can't break out of the JS string / attribute.
    final safeResult = i.shopperResultUrl.replaceAll("'", '%27');
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
  <style>
    body { margin: 0; padding: 16px; font-family: -apple-system, Roboto, sans-serif; background:#fff; }
    .wpwl-form { max-width: 480px; margin: 0 auto; }
  </style>
  <script type="text/javascript">
    var wpwlOptions = {
      style: 'card',
      locale: 'en',
      brandDetection: true,
      paymentTarget: '_top',
      shopperResultUrl: '$safeResult'
    };
  </script>
  <script src="${i.widgetBase}/v1/paymentWidgets.js?checkoutId=${i.checkoutId}" $integrityAttrs></script>
</head>
<body>
  <form action="$safeResult" class="paymentWidgets" data-brands="${i.brands}"></form>
</body>
</html>
''';
  }
}
