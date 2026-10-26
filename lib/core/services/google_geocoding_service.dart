import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/secure_log.dart';

class GoogleGeocodingResult {
  final String title;
  final String address;

  const GoogleGeocodingResult({required this.title, required this.address});

  Map<String, dynamic> toJson() => {'title': title, 'address': address};
  factory GoogleGeocodingResult.fromJson(Map<String, dynamic> json) => GoogleGeocodingResult(
        title: json['title']?.toString() ?? '',
        address: json['address']?.toString() ?? '',
      );
}

/// GoogleGeocodingService
///
/// Fetches real location names and street addresses directly from Google Maps Platform:
/// 1. Google Places API (New) searchNearby — retrieves real POIs/landmarks (e.g., "NIBA WEIGH BRIDGE")
/// 2. Google Geocoding API — fallback for street/route/locality reverse geocoding
class GoogleGeocodingService {
  static final GoogleGeocodingService instance = GoogleGeocodingService._internal();
  GoogleGeocodingService._internal();

  static const String googleMapsApiKey = 'AIzaSyCjt7M299tgviXLU0SQCzRxdwaFxqneej4';
  final Map<String, GoogleGeocodingResult> _resultCache = {};

  void _saveToCache(String cacheKey, GoogleGeocodingResult res) {
    _resultCache[cacheKey] = res;
    // Persist to disk to optimize Google Cloud API quota across app restarts
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('geo_cache_$cacheKey', jsonEncode(res.toJson()));
    }).catchError((_) {});
  }

  /// Resolves (latitude, longitude) into the real Google Maps place name and address.
  Future<GoogleGeocodingResult> resolveLocation(double lat, double lng) async {
    if (lat == 0.0 && lng == 0.0) {
      return const GoogleGeocodingResult(
        title: 'Location unavailable',
        address: 'GPS coordinates unavailable',
      );
    }

    final cacheKey = '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}';
    if (_resultCache.containsKey(cacheKey)) {
      return _resultCache[cacheKey]!;
    }

    // Check disk storage cache (avoids repeat API bills)
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString('geo_cache_$cacheKey');
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final res = GoogleGeocodingResult.fromJson(jsonDecode(cachedJson));
        if (res.title.isNotEmpty) {
          _resultCache[cacheKey] = res;
          return res;
        }
      }
    } catch (_) {}

    // ─── 1. Attempt Google Places API (New) for real POI / Landmark ──
    try {
      final placesUri = Uri.parse('https://places.googleapis.com/v1/places:searchNearby');
      final response = await http
          .post(
            placesUri,
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': googleMapsApiKey,
              'X-Goog-FieldMask': 'places.displayName,places.formattedAddress,places.types',
            },
            body: jsonEncode({
              'maxResultCount': 5,
              'rankPreference': 'DISTANCE',
              'locationRestriction': {
                'circle': {
                  'center': {'latitude': lat, 'longitude': lng},
                  'radius': 120.0,
                }
              }
            }),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['places'] is List && (data['places'] as List).isNotEmpty) {
          final places = List<Map<String, dynamic>>.from(data['places']);

          // Select the nearest valid named landmark or business establishment
          Map<String, dynamic>? selected;
          for (final p in places) {
            final name = p['displayName']?['text']?.toString() ?? '';
            if (name.isNotEmpty) {
              selected = p;
              break;
            }
          }
          selected ??= places.first;

          final placeName = selected['displayName']?['text']?.toString() ?? '';
          var placeAddress = selected['formattedAddress']?.toString() ?? '';

          if (placeAddress.isNotEmpty) {
            // Strip plus codes like "34MG+QF, "
            placeAddress = placeAddress.replaceAll(RegExp(r'^[A-Z0-9]{4,8}\+[A-Z0-9]{2,4},\s*'), '');
          }

          if (placeName.isNotEmpty) {
            final res = GoogleGeocodingResult(
              title: placeName,
              address: placeAddress.isNotEmpty ? placeAddress : placeName,
            );
            _saveToCache(cacheKey, res);
            return res;
          }
        }
      } else {
        secureLog('[GooglePlaces] HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      secureLog('[GooglePlaces] searchNearby notice: $e');
    }

    // ─── 2. Fall back to Google Geocoding API ──────────────────────────
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$googleMapsApiKey',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'OK' && data['results'] is List && (data['results'] as List).isNotEmpty) {
          final results = data['results'] as List;

          String? detectedTitle;
          String? cleanAddress;

          // Look for cleanest route or sublocality first
          for (final r in results) {
            final types = List<String>.from(r['types'] ?? []);
            if (types.contains('route')) {
              // Extract the route name for the title (e.g., Peelamedu - Pudur Main Rd)
              final comps = List<Map<String, dynamic>>.from(r['address_components'] ?? []);
              for (final c in comps) {
                final cTypes = List<String>.from(c['types'] ?? []);
                if (cTypes.contains('route')) {
                  detectedTitle ??= c['long_name']?.toString();
                }
              }
              cleanAddress ??= r['formatted_address']?.toString();
              break;
            }
          }

          cleanAddress ??= results.first['formatted_address']?.toString();

          if (cleanAddress != null && cleanAddress.isNotEmpty) {
            // Strip raw plus code prefix
            cleanAddress = cleanAddress.replaceAll(RegExp(r'^[A-Z0-9]{4,8}\+[A-Z0-9]{2,4},\s*'), '');

            // If the road has duplicated Tiruppur / Arasur postal text, make it clean
            if (cleanAddress.contains('Arasur') && cleanAddress.contains('Tiruppur')) {
              cleanAddress = cleanAddress.replaceAll('Tiruppur, Arasur', 'Arasur, Coimbatore');
            }

            detectedTitle ??= cleanAddress.split(',').first.trim();

            final res = GoogleGeocodingResult(
              title: detectedTitle,
              address: cleanAddress,
            );
            _saveToCache(cacheKey, res);
            return res;
          }
        }
      }
    } catch (e) {
      secureLog('[GoogleGeocoding] Reverse geocoding failed: $e');
    }

    final fallback = '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
    final fallbackRes = GoogleGeocodingResult(
      title: 'Location Fix',
      address: fallback,
    );
    _resultCache[cacheKey] = fallbackRes;
    return fallbackRes;
  }

  /// Backward-compatible string helper
  Future<String> reverseGeocode(double lat, double lng) async {
    final res = await resolveLocation(lat, lng);
    return res.address;
  }
}
