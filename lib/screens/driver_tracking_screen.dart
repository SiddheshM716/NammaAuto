import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class DriverTrackingScreen extends StatelessWidget {
  final LatLng driverLocation;
  final String otp;

  DriverTrackingScreen({required this.driverLocation, required this.otp});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Driver Tracking'),
      ),
      body: Column(
        children: [
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: driverLocation,
                zoom: 14,
              ),
              markers: {
                Marker(
                  markerId: MarkerId('driver'),
                  position: driverLocation,
                  infoWindow: InfoWindow(title: 'Driver Location'),
                ),
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('OTP: $otp', style: TextStyle(fontSize: 24)),
          ),
        ],
      ),
    );
  }
}