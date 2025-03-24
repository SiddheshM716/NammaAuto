import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  // Generate a random 6-digit OTP
  String _generateOTP() {
    Random random = Random();
    int otp = 1000 + random.nextInt(9000); // Generates a number between 100000 and 999999
    return otp.toString();
  }

  // Insert a new ride request with OTP
  Future<void> insertRideRequest({
    required int userId,
    required String userName,
    required String userPhno,
    required double pickUpLat,
    required double pickUpLng,
    required double dropLat,
    required double dropLng,
    required String dropAddress,
    required String pickupAddress,
  }) async {
    try {
      String otp = _generateOTP(); // Generate OTP

      await _client.from('ride_request').insert({
        'user_id': userId,
        'user_name': userName,
        'user_phno': userPhno,
        'pick_up_lat': pickUpLat,
        'pick_up_lng': pickUpLng,
        'drop_lat': dropLat,
        'drop_lng': dropLng,
        'drop_address': dropAddress,
        'pick_up_address': pickupAddress,
        'otp': otp, // Store the OTP in the database
      });
    } catch (e) {
      print('Error inserting ride request: $e');
      rethrow;
    }
  }
  // Check if a ride request has been accepted by a driver
Future<Map<String, dynamic>?> checkRideRequestStatus(int requestId) async {
  try {
    // Fetch the ride status from the ridestatus table
    final response = await _client
        .from('ridestatus')
        .select('ride_accepted, ride_cancelled, req_status')
        .eq('requestid', requestId)
        .single();

    // Check if the ride has been accepted
    if (response['ride_accepted'] == true) {
      return response;
    }
    return null;
  } catch (e) {
    print('Error checking ride request status: $e');
    return null;
  }
}

// Fetch driver details and OTP for an accepted ride request
Future<Map<String, dynamic>?> fetchDriverDetails(int requestId) async {
  try {
    final response = await _client
        .from('ridestatus')
        .select('driverid, otp')
        .eq('requestid', requestId)
        .single();

    if (response != null) {
      final driverDetails = await _client
          .from('drivers')
          .select('name, phone_number, current_lat, current_lng')
          .eq('id', response['driverid'])
          .single();

      return {
        ...driverDetails,
        'otp': response['otp'],
      };
    }
    return null;
  } catch (e) {
    print('Error fetching driver details: $e');
    return null;
  }
}
  Future<Map<String, dynamic>> fetchRideRequestById(int requestId) async {
  try {
    final response = await _client
        .from('ride_request')
        .select()
        .eq('id', requestId)
        .single();
    return response;
  } catch (e) {
    print('Error fetching ride request: $e');
    rethrow;
  }
}

  // Fetch all ride requests that are not accepted, cancelled, or completed
  Future<List<Map<String, dynamic>>> fetchRideRequests() async {
    try {
      // Fetch all ride requests
      final rideRequests = await _client.from('ride_request').select();

      // Fetch all ride statuses
      final rideStatuses = await _client.from('ridestatus').select();

      // Filter out ride requests that have been accepted, cancelled, or completed
      final validRequests = rideRequests.where((request) {
        final status = rideStatuses.firstWhere(
          (status) => status['requestid'] == request['id'],
          orElse: () => {},
        );

        // Include the request only if it hasn't been accepted, cancelled, or completed
        return status.isEmpty || 
               (status['ride_accepted'] != true && 
                status['ride_cancelled'] != true && 
                status['req_status'] != true);
      }).toList();

      return List<Map<String, dynamic>>.from(validRequests);
    } catch (e) {
      print('Error fetching ride requests: $e');
      rethrow;
    }
  }

  // Delete a ride request by ID
  Future<void> deleteRideRequest(int id) async {
    try {
      await _client.from('ride_request').delete().eq('id', id);
    } catch (e) {
      print('Error deleting ride request: $e');
      rethrow;
    }
  }

  // Update ride status (accept, cancel, or complete)
  Future<void> updateRideStatus({
    required int requestId,
    bool rideAccepted = false,
    bool rideCancelled = false,
    bool reqStatus = false,
  }) async {
    try {
      await _client.from('ridestatus').upsert({
        'requestid': requestId,
        'ride_accepted': rideAccepted,
        'ride_cancelled': rideCancelled,
        'req_status': reqStatus,
      }).eq('requestid', requestId);
    } catch (e) {
      print('Error updating ride status: $e');
      rethrow;
    }
  }
  Future<void> updateDriverPoints(int points) async {
  try {
    // Hardcode driverId to 3
    final driverId = 3;

    // Fetch current points for driverId 3
    final response = await _client
        .from('drivers')
        .select('points')
        .eq('id', driverId)
        .single();

    final currentPoints = response['points'] ?? 0;

    // Update points for driverId 3
    await _client
        .from('drivers')
        .update({'points': currentPoints + points})
        .eq('id', driverId);
  } catch (e) {
    print('Error updating driver points: $e');
    rethrow;
  }
}
  // Insert ride details into ridestatus table
  Future<void> insertRideStatus({
    required int driverId,
    required int requestId,
    bool rideAccepted = false,
    bool rideCancelled = false,
    bool reqStatus = false,
  }) async {
    try {
      await _client.from('ridestatus').insert({
        'driverid': 1,
        'requestid': requestId,
        'ride_accepted': rideAccepted,
        'ride_cancelled': rideCancelled,
        'req_status': reqStatus,
      });
    } catch (e) {
      print('Error inserting ride status: $e');
      rethrow;
    }
  }
}
