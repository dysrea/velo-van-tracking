import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class MapScreen extends StatefulWidget {
  final String serverUrl;
  final String role;  
  final String vanId;

  const MapScreen({
    super.key, 
    required this.serverUrl, 
    required this.role, 
    required this.vanId
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  WebSocketChannel? _channel;
  LatLng _currentPos = const LatLng(21.1458, 79.0882); 
  // bool _isTracking = false;
  StreamSubscription<Position>? _positionStream;

  @override
  void initState() {
    super.initState();
    if (widget.role == 'agency') {
      _connectToLiveFeed();
    } else {
      _requestGpsPermission();
    }
  }

  void _connectToLiveFeed() {
    final wsUrl = widget.serverUrl.replaceAll("http", "ws") + "/ws/location";
    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    _channel!.stream.listen((message) {
      final data = jsonDecode(message);
      if (data['van_id'] == widget.vanId) {
        setState(() {
          _currentPos = LatLng(data['lat'], data['lng']);
        });
        _mapController.move(_currentPos, 15.0);
      }
    });
  }

  Future<void> _requestGpsPermission() async {
    LocationPermission permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
      _startDriverTracking();
    }
  }

  void _startDriverTracking() {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10)
    ).listen((Position position) {
      final newPos = LatLng(position.latitude, position.longitude);
      setState(() { _currentPos = newPos; });
      _mapController.move(newPos, 15.0);
      _sendLocationToServer(newPos);
    });
  }

  Future<void> _sendLocationToServer(LatLng pos) async {
    try {
      await http.post(
        Uri.parse("${widget.serverUrl}/update-location"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "van_id": widget.vanId,
          "lat": pos.latitude,
          "lng": pos.longitude,
          "status": "moving"
        }),
      );
    } catch (e) { debugPrint("Update Error: $e"); }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.role == 'driver' ? "Driver Mode" : "Monitoring")),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(initialCenter: _currentPos, initialZoom: 15.0),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.app',
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: _currentPos,
                width: 40,
                height: 40,
                child: Icon(
                  Icons.location_on, 
                  color: widget.role == 'driver' ? Colors.blue : Colors.red, 
                  size: 40
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}