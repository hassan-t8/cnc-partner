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
      // NO baseUrl — deliberately.
      //
      // HyperPay checks the origin of the page hosting the widget against the
      // `merchant.url` baked into the checkout, and the backend sets that to the
      // PARTNER PORTAL origin (partnerDepositController → partnerPortalBase()).
      // We were passing the BACKEND origin here (derived from shopperResultUrl),
      // so the widget presented a concrete origin that did not match
      // merchant.url — and HyperPay rejected the card on Pay with
      // "invalid or missing parameters".
      //
      // Passing no baseUrl leaves the page on an opaque (about:blank) origin,
      // which has nothing to mismatch. That is exactly what the customer app
      // (cncapp) does against the same gateway, and it works in production.
      // A concrete-but-wrong origin is worse than no origin at all.
      ..loadHtmlString(_html);
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
    final amountStr = i.amount.toStringAsFixed(2);
    // Card design mirrors the cncapp customer payment screen (buildHyperPayHtml)
    // — a dark gradient amount card, a CARD DETAILS row, the styled HyperPay
    // form and a trust footer. The functional bits stay: shopperResultUrl +
    // paymentTarget '_top' + the window.wpwl mirror + integrity, which the
    // deposit flow relies on to intercept the 3-D Secure result.
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=2.0, user-scalable=yes">
  <style>
    * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
    html, body { margin: 0; }
    body { font-family: -apple-system, 'Poppins', Arial, sans-serif; background: #ffffff; color: #111827; padding: 16px 16px 28px; }

    .amount-card {
      background: linear-gradient(135deg, #23272E 0%, #3A4352 100%);
      border-radius: 24px; padding: 20px; color: #fff; margin-bottom: 18px;
      box-shadow: 0 8px 18px rgba(35,39,46,0.25);
    }
    .amount-top { display: flex; align-items: flex-start; justify-content: space-between; }
    .amount-label { font-size: 10px; letter-spacing: 2px; font-weight: 800; color: rgba(255,255,255,0.6); }
    .amount-value { font-size: 26px; font-weight: 900; margin-top: 6px; line-height: 1; }
    .amount-value .cur { font-size: 15px; font-weight: 700; color: #36B864; margin-right: 4px; }

    .brand-row { display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px; }
    .brand-row .lbl { font-size: 10.5px; letter-spacing: 1.4px; font-weight: 800; color: #6B7280; }
    .brand-row .brands { font-size: 12px; font-weight: 900; color: #374151; letter-spacing: 0.5px; }
    .brand-row .brands .amex { color: #9CA3AF; font-weight: 700; }

    .wpwl-form { max-width: 100% !important; background: transparent !important; border: none !important; box-shadow: none !important; padding: 0 !important; margin: 0 !important; }
    .wpwl-group { margin: 0 0 16px 0 !important; width: 100% !important; float: none !important; clear: both !important; display: block !important; position: relative !important; overflow: visible !important; }
    .wpwl-wrapper { width: 100% !important; float: none !important; display: block !important; position: relative !important; }
    .wpwl-label { font-size: 13px !important; color: #4B5563 !important; font-weight: 600 !important; margin-bottom: 8px !important; display: block !important; }
    .wpwl-control { height: 48px !important; width: 100% !important; border-radius: 12px !important; border: 1px solid #E5E7EB !important; font-size: 15px !important; padding: 0 14px !important; box-shadow: none !important; background: #F9FAFB !important; position: relative !important; z-index: 2 !important; }
    .wpwl-control:focus, .wpwl-control-focus { border-color: #36B864 !important; background: #ffffff !important; outline: none !important; }
    .wpwl-brand, .wpwl-brand-container, .wpwl-brand-custom { pointer-events: none !important; position: absolute !important; right: 12px !important; top: 50% !important; transform: translateY(-50%) !important; max-height: 24px !important; width: auto !important; margin: 0 !important; z-index: 3 !important; }
    .wpwl-group-mobilePhoneCountryCode,
    .wpwl-group-mobilePhoneNumber,
    .wpwl-group-birthDate,
    .wpwl-group-clickToPayConfirmation,
    .wpwl-group-visaInstallmentConfirmation,
    .wpwl-group-registration,
    .wpwl-sib-registration,
    .wpwl-group-total { display: none !important; }
    .wpwl-button-pay { background: #36B864 !important; border: none !important; border-radius: 12px !important; height: 52px !important; font-weight: 700 !important; text-transform: none !important; font-size: 16px !important; box-shadow: 0 4px 14px rgba(54,184,100,0.35) !important; margin-top: 8px !important; width: 100% !important; }
    .wpwl-button-pay:active { opacity: 0.9 !important; }
    .wpwl-hint { font-size: 11px !important; color: #9CA3AF !important; }
    .wpwl-message, .wpwl-error { border-radius: 10px !important; font-size: 12.5px !important; }

    .trust { text-align: center; margin-top: 18px; }
    .trust .line1 { font-size: 11px; font-weight: 600; color: #9CA3AF; }
    .trust .line2 { font-size: 10.5px; color: #C4C9D0; margin-top: 4px; }
  </style>
  <script type="text/javascript">
    var wpwlOptions = {
      style: 'card',
      locale: 'en',
      brandDetection: true,
      paymentTarget: '_top',
      shopperResultUrl: '$safeResult',
      iframeStyles: {
        'card-number-placeholder': { 'color': '#9CA3AF', 'font-size': '15px' },
        'cvv-placeholder': { 'color': '#9CA3AF', 'font-size': '15px' }
      }
    };
    // The web sets wpwl.options as well as wpwlOptions — mirror it, so the
    // widget reads the same config however it looks it up.
    window.wpwl = window.wpwl || { options: wpwlOptions };
    window.wpwl.options = wpwlOptions;
  </script>
  <script src="${i.widgetBase}/v1/paymentWidgets.js?checkoutId=${i.checkoutId}" $integrityAttrs></script>
</head>
<body>
  <div class="amount-card">
    <div class="amount-top">
      <div>
        <div class="amount-label">DEPOSIT AMOUNT</div>
        <div class="amount-value"><span class="cur">AED</span>$amountStr</div>
      </div>
    </div>
  </div>

  <div class="brand-row">
    <span class="lbl">CARD DETAILS</span>
    <span class="brands">VISA · Mastercard <span class="amex">· Amex</span></span>
  </div>

  <!-- No action attribute: the result URL is supplied via
       wpwlOptions.shopperResultUrl, exactly as the partner web portal does. -->
  <form class="paymentWidgets" data-brands="${i.brands}"></form>

  <div class="trust">
    <div class="line1">🔒 Card details never leave your device · HyperPay encrypted</div>
    <div class="line2">You may be redirected to your bank for 3-D Secure verification.</div>
  </div>
</body>
</html>
''';
  }
}
