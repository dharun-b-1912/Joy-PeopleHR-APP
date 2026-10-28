import '../../../../widgets/dialogs/location_prominent_disclosure_dialog.dart';
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/services/shift_tracking_service.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/services/google_geocoding_service.dart';

enum TimelineItemType { stay, trip }

class TimelineCluster {
  final TimelineItemType type;
  String title;
  final String subtitle;
  final DateTime startTime;
  final DateTime endTime;
  final LatLng startLatLng;
  final LatLng? endLatLng;
  final double distanceMeters;
  final double? avgSpeedKmh;
  final int waypointCount;
  String? resolvedAddress;

  TimelineCluster({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.startTime,
    required this.endTime,
    required this.startLatLng,
    this.endLatLng,
    this.distanceMeters = 0.0,
    this.avgSpeedKmh,
    this.waypointCount = 1,
    this.resolvedAddress,
  });

  String get durationString {
    final diff = endTime.difference(startTime);
    if (diff.inHours > 0) {
      final mins = diff.inMinutes % 60;
      return '${diff.inHours}h ${mins > 0 ? "${mins}m" : ""}';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes} mins';
    } else {
      return '< 1 min';
    }
  }

  String get timeRangeString {
    final s = startTime.toLocal();
    final e = endTime.toLocal();

    String fmt(DateTime dt) {
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '${h.toString().padLeft(2, '0')}:$m $ampm';
    }

    if (s.year == e.year &&
        s.month == e.month &&
        s.day == e.day &&
        s.hour == e.hour &&
        s.minute == e.minute) {
      return fmt(s);
    }
    return '${fmt(s)} – ${fmt(e)}';
  }
}

class EmployeeLocationScreen extends StatefulWidget {
  const EmployeeLocationScreen({super.key});

  @override
  State<EmployeeLocationScreen> createState() => _EmployeeLocationScreenState();
}

class _EmployeeLocationScreenState extends State<EmployeeLocationScreen> {
  GoogleMapController? _mapController;
  MapType _currentMapType = MapType.normal;

  Position? _currentPosition;
  int? _batteryLevel;
  bool _isCharging = false;
  bool _isLoadingGps = false;
  bool _isLoadingTrails = false;

  late String _selectedDate;
  List<Map<String, dynamic>> _rawTrails = [];
  List<TimelineCluster> _clusters = [];

  // Default coordinate: Tiruppur / Coimbatore office hub
  static const LatLng _fallbackCenter = LatLng(11.0844, 77.1263);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    _loadCurrentLocationAndBattery();
    _loadHistoricalTrails(_selectedDate);
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentLocationAndBattery() async {
    setState(() => _isLoadingGps = true);
    try {
      try {
        final battery = Battery();
        _batteryLevel = await battery.batteryLevel;
        final state = await battery.batteryState;
        _isCharging =
            state == BatteryState.charging || state == BatteryState.full;
      } catch (_) {}

      await ShiftTrackingService.instance.syncCurrentDeviceLocation();
      Position? pos = ShiftTrackingService.instance.lastRecordedPosition;
      if (pos == null) {
        try {
          pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 10),
            ),
          );
        } catch (_) {
          pos = await Geolocator.getLastKnownPosition();
        }
      }

      if (mounted) {
        setState(() {
          _currentPosition = pos;
          _isLoadingGps = false;
        });

        if (pos != null && _mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(pos.latitude, pos.longitude),
              16.5,
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingGps = false);
      }
    }
  }

  Future<void> _loadHistoricalTrails(String dateStr) async {
    setState(() => _isLoadingTrails = true);
    try {
      final data =
          await ShiftTrackingService.instance.getHistoricalTrails(dateStr);
      if (mounted) {
        final clustered = _clusterWaypointsIntoStopsAndTrips(data);
        setState(() {
          _rawTrails = data;
          _clusters = clustered;
          _isLoadingTrails = false;
        });

        _fitBoundsToRoute();
        _resolveClusterAddresses();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingTrails = false);
      }
    }
  }

  /// Asynchronously fetches real Google Maps street addresses and place names for each detected Stop
  Future<void> _resolveClusterAddresses() async {
    for (final c in _clusters) {
      if (c.type == TimelineItemType.stay &&
          (c.resolvedAddress == null || c.resolvedAddress!.isEmpty)) {
        final result = await GoogleGeocodingService.instance.resolveLocation(
          c.startLatLng.latitude,
          c.startLatLng.longitude,
        );
        if (mounted && result.address.isNotEmpty) {
          setState(() {
            if (result.title.isNotEmpty && !result.title.startsWith('Lat:')) {
              c.title = result.title;
            }
            c.resolvedAddress = result.address;
          });
        }
      }
    }
  }

  /// Groups raw telemetry logs into meaningful "Stops" (<50m) and "Trips" (>=50m)
  List<TimelineCluster> _clusterWaypointsIntoStopsAndTrips(
      List<Map<String, dynamic>> raw) {
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    if (raw.isEmpty) {
      if (_selectedDate == todayStr && _currentPosition != null) {
        return [
          TimelineCluster(
            type: TimelineItemType.stay,
            title: 'Current Location (Live)',
            subtitle: 'Stationary • Active Live GPS Station',
            startTime: DateTime.now().subtract(const Duration(minutes: 15)),
            endTime: DateTime.now(),
            startLatLng:
                LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            distanceMeters: 0,
            waypointCount: 1,
            resolvedAddress: null,
          ),
        ];
      }
      return [];
    }

    final List<TimelineCluster> clusters = [];
    final List<Map<String, dynamic>> sorted = List.from(raw)
      ..sort((a, b) {
        final tA =
            DateTime.tryParse(a['recorded_at']?.toString() ?? '') ?? DateTime(0);
        final tB =
            DateTime.tryParse(b['recorded_at']?.toString() ?? '') ?? DateTime(0);
        return tA.compareTo(tB);
      });

    List<Map<String, dynamic>> currentStopPoints = [];

    for (int i = 0; i < sorted.length; i++) {
      final point = sorted[i];
      final lat = (point['latitude'] as num?)?.toDouble() ?? 0.0;
      final lng = (point['longitude'] as num?)?.toDouble() ?? 0.0;
      if (lat == 0.0 && lng == 0.0) continue;

      if (currentStopPoints.isEmpty) {
        currentStopPoints.add(point);
        continue;
      }

      final anchor = currentStopPoints.first;
      final anchorLat = (anchor['latitude'] as num?)?.toDouble() ?? 0.0;
      final anchorLng = (anchor['longitude'] as num?)?.toDouble() ?? 0.0;

      final dist = Geolocator.distanceBetween(anchorLat, anchorLng, lat, lng);

      // Stationary cluster threshold: 30 meters
      if (dist < 30.0) {
        currentStopPoints.add(point);
      } else {
        // Close the previous Stay cluster
        clusters.add(_createStayCluster(currentStopPoints, clusters.length + 1));

        // Create a Trip cluster representing movement
        final prevPoint = currentStopPoints.last;
        final prevLat = (prevPoint['latitude'] as num?)?.toDouble() ?? 0.0;
        final prevLng = (prevPoint['longitude'] as num?)?.toDouble() ?? 0.0;
        final prevTime = DateTime.tryParse(
                prevPoint['recorded_at']?.toString() ?? '')?.toLocal() ??
            DateTime.now();
        final currTime =
            DateTime.tryParse(point['recorded_at']?.toString() ?? '')?.toLocal() ??
                DateTime.now();

        final speed = (point['speed'] as num?)?.toDouble();
        final speedKmh = speed != null && speed > 0 ? speed * 3.6 : null;

        clusters.add(TimelineCluster(
          type: TimelineItemType.trip,
          title: 'Transit / Commute',
          subtitle:
              '${(dist / 1000).toStringAsFixed(2)} km displacement • ${speedKmh != null ? "${speedKmh.toStringAsFixed(0)} km/h" : "In motion"}',
          startTime: prevTime,
          endTime: currTime,
          startLatLng: LatLng(prevLat, prevLng),
          endLatLng: LatLng(lat, lng),
          distanceMeters: dist,
          avgSpeedKmh: speedKmh,
          waypointCount: 1,
        ));

        currentStopPoints = [point];
      }
    }

    if (currentStopPoints.isNotEmpty) {
      clusters.add(_createStayCluster(currentStopPoints, clusters.length + 1));
    }

    // Connect to current live position if displaced from the last cluster
    if (_selectedDate == todayStr && _currentPosition != null && clusters.isNotEmpty) {
      final lastCluster = clusters.last;
      final liveLatLng = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      final lastLatLng = lastCluster.endLatLng ?? lastCluster.startLatLng;
      final distToLive = Geolocator.distanceBetween(
        lastLatLng.latitude,
        lastLatLng.longitude,
        liveLatLng.latitude,
        liveLatLng.longitude,
      );

      if (distToLive >= 40.0) {
        clusters.add(TimelineCluster(
          type: TimelineItemType.trip,
          title: 'Transit / Commute',
          subtitle: '${(distToLive / 1000).toStringAsFixed(2)} km displacement to Current Location',
          startTime: lastCluster.endTime,
          endTime: DateTime.now(),
          startLatLng: lastLatLng,
          endLatLng: liveLatLng,
          distanceMeters: distToLive,
          waypointCount: 1,
        ));

        clusters.add(TimelineCluster(
          type: TimelineItemType.stay,
          title: 'Current Location (Live)',
          subtitle: 'Active Live GPS Station',
          startTime: DateTime.now().subtract(const Duration(minutes: 5)),
          endTime: DateTime.now(),
          startLatLng: liveLatLng,
          distanceMeters: 0,
          waypointCount: 1,
          resolvedAddress: null,
        ));
      }
    }

    return clusters;
  }

  TimelineCluster _createStayCluster(
      List<Map<String, dynamic>> points, int index) {
    final first = points.first;
    final last = points.last;

    final lat = (first['latitude'] as num?)?.toDouble() ?? 0.0;
    final lng = (first['longitude'] as num?)?.toDouble() ?? 0.0;
    final sTime =
        DateTime.tryParse(first['recorded_at']?.toString() ?? '')?.toLocal() ??
            DateTime.now();
    final eTime =
        DateTime.tryParse(last['recorded_at']?.toString() ?? '')?.toLocal() ??
            DateTime.now();

    final isOnlyOne = points.length == 1;
    final countText =
        isOnlyOne ? 'Initial Check-in fix' : '${points.length} telemetry heartbeats';

    return TimelineCluster(
      type: TimelineItemType.stay,
      title: index == 1 ? 'Shift Origin' : 'Stop #$index',
      subtitle:
          'Stationary at ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)} • $countText',
      startTime: sTime,
      endTime: eTime,
      startLatLng: LatLng(lat, lng),
      distanceMeters: 0.0,
      waypointCount: points.length,
      resolvedAddress: null,
    );
  }

  void _fitBoundsToRoute() {
    if (_mapController == null) return;
    final points = _getAllPolylinePoints();
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final List<LatLng> targetPoints = List.from(points);
    if (_selectedDate == todayStr && _currentPosition != null) {
      targetPoints.add(LatLng(_currentPosition!.latitude, _currentPosition!.longitude));
    }

    if (targetPoints.isEmpty) {
      if (_currentPosition != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            16.5,
          ),
        );
      }
      return;
    }

    if (targetPoints.length == 1) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(targetPoints.first, 16.5),
      );
      return;
    }

    double minLat = targetPoints.first.latitude;
    double maxLat = targetPoints.first.latitude;
    double minLng = targetPoints.first.longitude;
    double maxLng = targetPoints.first.longitude;

    for (final p in targetPoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    if ((maxLat - minLat).abs() < 0.0001 && (maxLng - minLng).abs() < 0.0001) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(minLat, minLng), 16.5),
      );
      return;
    }

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        60,
      ),
    );
  }

  List<LatLng> _getAllPolylinePoints() {
    final List<LatLng> list = [];
    for (final r in _rawTrails) {
      final lat = (r['latitude'] as num?)?.toDouble();
      final lng = (r['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
        list.add(LatLng(lat, lng));
      }
    }

    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    if (_selectedDate == todayStr && _currentPosition != null) {
      final livePos = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      if (list.isEmpty) {
        list.add(livePos);
      } else {
        final last = list.last;
        final d = Geolocator.distanceBetween(last.latitude, last.longitude, livePos.latitude, livePos.longitude);
        if (d >= 20.0) {
          list.add(livePos);
        }
      }
    }

    return list;
  }

  Set<Polyline> _buildPolylines() {
    final points = _getAllPolylinePoints();
    if (points.length < 2) return {};

    return {
      Polyline(
        polylineId: const PolylineId('route_trail'),
        points: points,
        color: const Color(0xFF0EA5E9),
        width: 5,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
    };
  }

  Set<Marker> _buildMarkers() {
    final Set<Marker> markers = {};

    // 1. Live position marker
    if (_currentPosition != null) {
      final pos = LatLng(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );
      final user = UserService.instance.currentUser;

      markers.add(
        Marker(
          markerId: const MarkerId('current_live_gps'),
          position: pos,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueCyan,
          ),
          infoWindow: InfoWindow(
            title: '${user.name.isNotEmpty ? user.name : "My Location"} (Live)',
            snippet:
                'Battery: ${_batteryLevel != null ? "$_batteryLevel%" : "100%"} • Live GPS',
          ),
          zIndexInt: 10,
        ),
      );
    }

    // 2. Stop markers for each stay cluster
    int stopIdx = 1;
    for (final c in _clusters) {
      if (c.type == TimelineItemType.stay) {
        markers.add(
          Marker(
            markerId: MarkerId('stop_${c.startLatLng.latitude}_${c.startLatLng.longitude}'),
            position: c.startLatLng,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              stopIdx == 1
                  ? BitmapDescriptor.hueGreen
                  : BitmapDescriptor.hueAzure,
            ),
            infoWindow: InfoWindow(
              title: c.resolvedAddress != null && c.resolvedAddress!.isNotEmpty
                  ? c.resolvedAddress!
                  : c.title,
              snippet: '${c.timeRangeString} (${c.durationString})',
            ),
            onTap: () {
              _mapController?.animateCamera(
                CameraUpdate.newLatLngZoom(c.startLatLng, 17.5),
              );
            },
          ),
        );
        stopIdx++;
      }
    }

    return markers;
  }

  double _calculateTotalDistanceKm() {
    if (_rawTrails.isEmpty) return 0.0;
    double meters = 0.0;
    for (final r in _rawTrails) {
      final d = (r['displacement_meters'] as num?)?.toDouble() ?? 0.0;
      meters += d;
    }
    return meters / 1000;
  }

  String _formatActiveWindow() {
    if (_rawTrails.isEmpty) return '--:--';
    try {
      final first = _rawTrails.first['recorded_at']?.toString() ?? '';
      final last = _rawTrails.last['recorded_at']?.toString() ?? '';
      final fDt = DateTime.parse(first).toLocal();
      final lDt = DateTime.parse(last).toLocal();

      final s1 =
          '${fDt.hour.toString().padLeft(2, '0')}:${fDt.minute.toString().padLeft(2, '0')}';
      final s2 =
          '${lDt.hour.toString().padLeft(2, '0')}:${lDt.minute.toString().padLeft(2, '0')}';
      return '$s1 - $s2';
    } catch (_) {
      return 'Active';
    }
  }

  Future<void> _openInExternalGoogleMaps(double lat, double lng) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = UserService.instance.currentUser;
    final totalKm = _calculateTotalDistanceKm();
    final activeWindow = _formatActiveWindow();
    final stopCount =
        _clusters.where((c) => c.type == TimelineItemType.stay).length;
    final initialPos = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : _fallbackCenter;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left, color: Color(0xFF1E293B)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Locations',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
                fontSize: 18,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              '${user.name.isNotEmpty ? user.name : "Employee"} • Live Timeline',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.info_circle_fill, color: Color(0xFF0EA5E9)),
            tooltip: 'Location Disclosure & Consent',
            onPressed: () {
              LocationProminentDisclosureDialog.show(context);
            },
          ),
          IconButton(
            icon: _isLoadingGps || _isLoadingTrails
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF0EA5E9),
                    ),
                  )
                : const Icon(CupertinoIcons.arrow_clockwise,
                    color: Color(0xFF0EA5E9)),
            onPressed: () {
              _loadCurrentLocationAndBattery();
              _loadHistoricalTrails(_selectedDate);
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // ─── 1. INTERACTIVE GOOGLE MAP (Full Screen Base) ───────
          GoogleMap(
            mapType: _currentMapType,
            initialCameraPosition: CameraPosition(
              target: initialPos,
              zoom: 16.5,
            ),
            markers: _buildMarkers(),
            polylines: _buildPolylines(),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: true,
            mapToolbarEnabled: false,
            onMapCreated: (controller) {
              _mapController = controller;
              if (_currentPosition != null) {
                controller.animateCamera(
                  CameraUpdate.newLatLngZoom(
                    LatLng(_currentPosition!.latitude,
                        _currentPosition!.longitude),
                    16.5,
                  ),
                );
              }
            },
          ),

          // ─── 2. FLOATING MAP CONTROL BUTTONS ────────────────────
          Positioned(
            top: 16,
            right: 16,
            child: Column(
              children: [
                // Street / Satellite Toggle
                _MapControlButton(
                  icon: _currentMapType == MapType.normal
                      ? CupertinoIcons.globe
                      : CupertinoIcons.map,
                  tooltip: _currentMapType == MapType.normal
                      ? 'Satellite View'
                      : 'Street View',
                  onTap: () {
                    setState(() {
                      _currentMapType = _currentMapType == MapType.normal
                          ? MapType.satellite
                          : MapType.normal;
                    });
                  },
                ),
                const SizedBox(height: 10),

                // Recenter GPS Button
                _MapControlButton(
                  icon: CupertinoIcons.location_fill,
                  color: const Color(0xFF0EA5E9),
                  tooltip: 'Recenter on My GPS',
                  onTap: () {
                    if (_currentPosition != null && _mapController != null) {
                      _mapController!.animateCamera(
                        CameraUpdate.newLatLngZoom(
                          LatLng(_currentPosition!.latitude,
                              _currentPosition!.longitude),
                          17.0,
                        ),
                      );
                    } else {
                      _loadCurrentLocationAndBattery();
                    }
                  },
                ),
                const SizedBox(height: 10),

                // Fit Full Route Button
                if (_getAllPolylinePoints().isNotEmpty) ...[
                  _MapControlButton(
                    icon: CupertinoIcons.arrow_up_left_arrow_down_right,
                    tooltip: 'Fit Today Route',
                    onTap: _fitBoundsToRoute,
                  ),
                  const SizedBox(height: 10),
                ],

                // Open in External Google Maps app
                _MapControlButton(
                  icon: CupertinoIcons.map_pin_ellipse,
                  tooltip: 'Open in Google Maps App',
                  color: const Color(0xFF059669),
                  onTap: () {
                    if (_currentPosition != null) {
                      _openInExternalGoogleMaps(
                        _currentPosition!.latitude,
                        _currentPosition!.longitude,
                      );
                    }
                  },
                ),
              ],
            ),
          ),

          // ─── 3. TOP TELEMETRY PILL (Snapchat style floating badge) ─
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.90),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _currentPosition != null && _currentPosition!.speed > 0.8
                        ? 'Moving • ${(_currentPosition!.speed * 3.6).toStringAsFixed(0)} km/h'
                        : 'Live GPS',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 1,
                    height: 12,
                    color: Colors.white24,
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _isCharging
                        ? CupertinoIcons.battery_charging
                        : CupertinoIcons.battery_100,
                    size: 14,
                    color: const Color(0xFF38BDF8),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${_batteryLevel ?? 100}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ─── 4. DRAGGABLE BOTTOM SHEET TIMELINE (Google / Uber) ──
          DraggableScrollableSheet(
            initialChildSize: 0.38,
            minChildSize: 0.16,
            maxChildSize: 0.88,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 20,
                      offset: const Offset(0, -6),
                    ),
                  ],
                ),
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  children: [
                    // Grab handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Quick Date Selector
                    Row(
                      children: [
                        _DateTab(
                          label: 'Today',
                          isSelected: _isToday(_selectedDate),
                          onTap: () {
                            final now = DateTime.now();
                            final d =
                                '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
                            setState(() => _selectedDate = d);
                            _loadHistoricalTrails(d);
                          },
                        ),
                        const SizedBox(width: 8),
                        _DateTab(
                          label: 'Yesterday',
                          isSelected: _isYesterday(_selectedDate),
                          onTap: () {
                            final y = DateTime.now().subtract(const Duration(days: 1));
                            final d =
                                '${y.year}-${y.month.toString().padLeft(2, '0')}-${y.day.toString().padLeft(2, '0')}';
                            setState(() => _selectedDate = d);
                            _loadHistoricalTrails(d);
                          },
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: DateTime.tryParse(_selectedDate) ??
                                    DateTime.now(),
                                firstDate: DateTime(2025),
                                lastDate: DateTime.now(),
                              );
                              if (picked != null) {
                                final d =
                                    '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                                setState(() => _selectedDate = d);
                                _loadHistoricalTrails(d);
                              }
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: (!_isToday(_selectedDate) &&
                                          !_isYesterday(_selectedDate))
                                      ? const Color(0xFF0EA5E9)
                                      : const Color(0xFFE2E8F0),
                                ),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(CupertinoIcons.calendar,
                                      size: 14, color: Color(0xFF64748B)),
                                  const SizedBox(width: 6),
                                  Text(
                                    _formatDateHeader(_selectedDate),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF334155),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Metrics Strip (Distance, Active, Stops, Allowance)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _MetricColumn(
                            title: 'DISTANCE',
                            value: '${totalKm.toStringAsFixed(2)} km',
                            valueColor: const Color(0xFF0EA5E9),
                          ),
                          _MetricDivider(),
                          _MetricColumn(
                            title: 'ACTIVE',
                            value: activeWindow,
                            valueColor: const Color(0xFFF59E0B),
                          ),
                          _MetricDivider(),
                          _MetricColumn(
                            title: 'STOPS',
                            value: '$stopCount',
                            valueColor: const Color(0xFF10B981),
                          ),
                          _MetricDivider(),
                          _MetricColumn(
                            title: 'ALLOWANCE',
                            value: '₹${(totalKm * 6).toStringAsFixed(0)}',
                            valueColor: const Color(0xFF6366F1),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Timeline Section Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(CupertinoIcons.time,
                                size: 16, color: Color(0xFF0F172A)),
                            SizedBox(width: 6),
                            Text(
                              'Travel Timeline',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '$stopCount Stops • ${_rawTrails.length} Pings',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Clustered Timeline List (Stops and Trips)
                    if (_clusters.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        alignment: Alignment.center,
                        child: const Text(
                          'No travel movements recorded for this date.',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 13,
                          ),
                        ),
                      )
                    else
                      ..._clusters.map((cluster) => _TimelineClusterTile(
                            cluster: cluster,
                            onTap: () {
                              _mapController?.animateCamera(
                                CameraUpdate.newLatLngZoom(
                                  cluster.startLatLng,
                                  17.0,
                                ),
                              );
                            },
                          )),

                    const SizedBox(height: 40),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  bool _isToday(String dateStr) {
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return dateStr == todayStr;
  }

  bool _isYesterday(String dateStr) {
    final y = DateTime.now().subtract(const Duration(days: 1));
    final yStr =
        '${y.year}-${y.month.toString().padLeft(2, '0')}-${y.day.toString().padLeft(2, '0')}';
    return dateStr == yStr;
  }

  String _formatDateHeader(String dateStr) {
    try {
      final parts = dateStr.split('-');
      if (parts.length == 3) {
        final d = DateTime(
            int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        const months = [
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
        ];
        return '${d.day} ${months[d.month - 1]}';
      }
    } catch (_) {}
    return dateStr;
  }
}

// ─── MAP FLOATING CONTROL BUTTON ──────────────────────────────────
class _MapControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  final String? tooltip;

  const _MapControlButton({
    required this.icon,
    required this.onTap,
    this.color,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: color ?? const Color(0xFF1E293B), size: 20),
        onPressed: onTap,
        tooltip: tooltip,
      ),
    );
  }
}

// ─── DATE TAB BUTTON ──────────────────────────────────────────────
class _DateTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _DateTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F172A) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }
}

// ─── METRIC COLUMN ────────────────────────────────────────────────
class _MetricColumn extends StatelessWidget {
  final String title;
  final String value;
  final Color valueColor;

  const _MetricColumn({
    required this.title,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Color(0xFF94A3B8),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _MetricDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      color: const Color(0xFFE2E8F0),
    );
  }
}

// ─── CLUSTERED TIMELINE TILE (STOPS & TRIPS) ──────────────────────
class _TimelineClusterTile extends StatelessWidget {
  final TimelineCluster cluster;
  final VoidCallback onTap;

  const _TimelineClusterTile({
    required this.cluster,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isStay = cluster.type == TimelineItemType.stay;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Indicator Icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isStay
                    ? const Color(0xFFECFDF5)
                    : const Color(0xFFF0F9FF),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isStay
                      ? const Color(0xFF10B981)
                      : const Color(0xFF0EA5E9),
                  width: 1.5,
                ),
              ),
              child: Icon(
                isStay ? CupertinoIcons.location_solid : CupertinoIcons.car_detailed,
                size: 16,
                color: isStay ? const Color(0xFF059669) : const Color(0xFF0284C7),
              ),
            ),
            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        cluster.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        cluster.durationString,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isStay
                              ? const Color(0xFF059669)
                              : const Color(0xFF0284C7),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    cluster.resolvedAddress != null && cluster.resolvedAddress!.isNotEmpty
                        ? cluster.resolvedAddress!
                        : cluster.subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: cluster.resolvedAddress != null ? FontWeight.w600 : FontWeight.normal,
                      color: cluster.resolvedAddress != null ? const Color(0xFF1E293B) : const Color(0xFF64748B),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    cluster.timeRangeString,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
