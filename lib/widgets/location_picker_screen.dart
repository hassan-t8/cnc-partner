import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../core/config/env.dart';
import '../core/theme/app_colors.dart';
import 'main_app_bar.dart';

/// Result of the location picker.
class PickedLocation {
  final double lat;
  final double lng;
  final String address;
  const PickedLocation(this.lat, this.lng, this.address);
}

/// Full-screen map picker: tap or drag the pin to choose a point, the address
/// is reverse-geocoded automatically. Mirrors the web's "Pick on map" modal.
class LocationPickerScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final String? initialAddress;
  final String title;
  const LocationPickerScreen({
    super.key,
    this.initialLat,
    this.initialLng,
    this.initialAddress,
    this.title = 'Pick location',
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  static const _uaeCenter = LatLng(24.4539, 54.3773);
  late LatLng _pos;
  late final TextEditingController _addr;
  bool _hasPin = false;
  bool _geocoding = false;

  @override
  void initState() {
    super.initState();
    _hasPin = widget.initialLat != null && widget.initialLng != null;
    _pos = _hasPin
        ? LatLng(widget.initialLat!, widget.initialLng!)
        : _uaeCenter;
    _addr = TextEditingController(text: widget.initialAddress ?? '');
  }

  @override
  void dispose() {
    _addr.dispose();
    super.dispose();
  }

  void _move(LatLng p) {
    setState(() {
      _pos = p;
      _hasPin = true;
    });
    _reverseGeocode(p);
  }

  // Reverse-geocode via the Google Geocoding REST API (uses the Maps key).
  Future<void> _reverseGeocode(LatLng p) async {
    if (Env.googleMapsApiKey.isEmpty) return;
    setState(() => _geocoding = true);
    try {
      final res = await Dio().get(
        'https://maps.googleapis.com/maps/api/geocode/json',
        queryParameters: {
          'latlng': '${p.latitude},${p.longitude}',
          'key': Env.googleMapsApiKey,
        },
      );
      final results = res.data is Map ? res.data['results'] : null;
      if (results is List && results.isNotEmpty && mounted) {
        _addr.text = (results.first['formatted_address'] ?? '').toString();
      }
    } catch (_) {
      // Keep whatever address is there; user can edit it manually.
    } finally {
      if (mounted) setState(() => _geocoding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyMissing = Env.googleMapsApiKey.isEmpty;
    return Scaffold(
      appBar: MainAppBar(widget.title),
      body: Column(
        children: [
          Expanded(
            child: keyMissing
                ? Container(
                    color: AppColors.bg,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(24),
                    child: Text(
                        'Map unavailable — enter the address manually below.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted)),
                  )
                : Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition:
                            CameraPosition(target: _pos, zoom: _hasPin ? 15 : 10),
                        onTap: _move,
                        markers: _hasPin
                            ? {
                                Marker(
                                  markerId: const MarkerId('pick'),
                                  position: _pos,
                                  draggable: true,
                                  onDragEnd: _move,
                                ),
                              }
                            : {},
                        myLocationButtonEnabled: false,
                      ),
                      if (!_hasPin)
                        const Positioned(
                          top: 12,
                          left: 12,
                          right: 12,
                          child: _Banner('Tap the map to drop a pin'),
                        ),
                      if (_geocoding)
                        const Positioned(
                          top: 12,
                          right: 12,
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          ),
                        ),
                    ],
                  ),
          ),
          // Address + confirm
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _addr,
                    minLines: 1,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: (_hasPin || _addr.text.trim().isNotEmpty)
                          ? () => Navigator.pop(
                              context,
                              PickedLocation(
                                  _pos.latitude, _pos.longitude, _addr.text.trim()))
                          : null,
                      child: const Text('Use this location'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  const _Banner(this.text);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 12.5)),
      );
}
