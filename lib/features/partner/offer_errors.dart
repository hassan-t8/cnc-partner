import '../../core/network/api_client.dart';

/// Reasons the backend refuses an accept/decline because the offer is DEAD —
/// withdrawn, expired, already taken by another partner, or the booking is gone.
///
/// `offerEngine.acceptOffer` / `declineOffer` return these as
/// `{ ok: false, error: <reason> }` with a 409 (or 404 for a missing offer), and
/// ApiClient maps `data['error']` onto ApiException.code.
const _deadOfferCodes = {
  'offer_not_found',
  'offer_not_open',
  'offer_expired',
  'booking_not_found',
  'already_assigned',
  'booking_already_assigned',
};

/// True when the failure means the offer can never succeed — so the UI must stop
/// showing it as actionable: drop the card and refresh the list, rather than
/// leaving a dead offer on screen with a toast the partner will just tap again.
bool isStaleOffer(ApiException e) {
  final code = e.code?.toLowerCase().trim();
  if (code != null && _deadOfferCodes.contains(code)) return true;
  // Any 404/409 on an accept/decline is a race we lost: the offer is no longer
  // open to us. Treat it as stale even if a new reason code appears server-side.
  return e.status == 404 || e.status == 409;
}

/// Partner-facing wording for a dead offer.
String staleOfferMessage(ApiException e) {
  switch (e.code?.toLowerCase().trim()) {
    case 'already_assigned':
    case 'booking_already_assigned':
      return 'This booking was just assigned to another partner.';
    case 'offer_expired':
      return 'This request expired.';
    case 'offer_not_open':
    case 'offer_not_found':
      return 'This request is no longer available.';
    case 'booking_not_found':
      return 'This booking no longer exists.';
    default:
      return e.message;
  }
}
