import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  // Insert a new ride request
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
      });
    } catch (e) {
      print('Error inserting ride request: $e');
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