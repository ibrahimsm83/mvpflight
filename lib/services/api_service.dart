// services/api_service.dart

import 'dart:convert';
import 'dart:developer';
import 'package:http/http.dart' as http;

class ApiService {
  static const String apiKey = "AIzaSyBZ__aYmZxnIQdm1GZALUgTxWK4s1LpHCk"; //capcup


  static Future<Map<String, String>> getDistanceMatrix(
      double originLat,
      double originLng,
      double destLat,
      double destLng,
      ) async {
    final url =
        "https://maps.googleapis.com/maps/api/distancematrix/json?"
        "origins=$originLat,$originLng"
        "&destinations=$destLat,$destLng"
        "&departure_time=now"
        "&traffic_model=best_guess"
        "&mode=driving"
        "&key=$apiKey";

    final response = await http.get(Uri.parse(url));

    if (response.statusCode != 200) {
      throw Exception("HTTP error: ${response.statusCode}");
    }

    final data = json.decode(response.body);

    // 🔍 Debug (keep this while testing)
    print("API RESPONSE: $data");

    if (data['rows'] == null || data['rows'].isEmpty) {
      throw Exception("No rows returned from API");
    }

    final elements = data['rows'][0]['elements'];

    if (elements == null || elements.isEmpty) {
      throw Exception("No elements returned from API");
    }

    final element = elements[0];

    if (element['status'] != 'OK') {
      throw Exception("Distance Matrix error: ${element['status']}");
    }

    return {
      "distance": element['distance']['text'],
      "duration": element['duration']['text'],
      "traffic_duration": element['duration_in_traffic']['text'],
    };
  }


  // services/api_service.dart
///step2
  static Future<Map<String, String>> getFlightData(String flightNo) async {
    const apiKey = "9cab6e82-5e89-42a5-9b4b-7e278c4a874c";

    final url =
        "https://airlabs.co/api/v9/flight?flight_iata=$flightNo&api_key=$apiKey";

    final response = await http.get(Uri.parse(url));
    log(response.toString());
    final data = json.decode(response.body);
    log(data.toString());
    if (data['response'] == null) {
      throw Exception("Flight not found");
    }

    var flight = data['response'];

    return {
      "status": flight['status'] ?? "Unknown",
      "departure": flight['dep_time'] ?? "N/A",
    };
  }

}