// services/api_service.dart

import 'dart:convert';
import 'dart:developer';
import 'package:http/http.dart' as http;

class ApiService {
  // static const String apiKey = "AIzaSyBZ__aYmZxnIQdm1GZALUgTxWK4s1LpHCk"; //FastLane
  // static const String apiKey = "AIzaSyAME9RZ8rbjiDsNUJJrUlqe0QNrqjgCAxQ"; //Amarsidy
  // static const String apiKey = "AIzaSyCDGe4wXXZ1gwVU2W1Qz66g5Rf0t-df9NQ"; //Amarsidy
  static const String apiKey = "AIzaSyCDGe4wXXZ1gwVU2W1Qz66g5Rf0t-df9NQ"; //Amarsidy


  static Future<Map<String, String>> getDistanceMatrix(
      double originLat,
      double originLng,
      double destLat,
      double destLng,
      ) async {
    final url = Uri.parse(
      "https://routes.googleapis.com/directions/v2:computeRoutes",
    );

    final response = await http.post(
      url,
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask":
        "routes.distanceMeters,routes.duration,routes.staticDuration",
      },
      body: jsonEncode({
        "origin": {
          "location": {
            "latLng": {
              "latitude": originLat,
              "longitude": originLng
            }
          }
        },
        "destination": {
          "location": {
            "latLng": {
              "latitude": destLat,
              "longitude": destLng
            }
          }
        },
        "travelMode": "DRIVE",
        "routingPreference": "TRAFFIC_AWARE"
      }),
    );

    if (response.statusCode != 200) {
      throw Exception("HTTP error: ${response.statusCode}");
    }

    final data = jsonDecode(response.body);

    print("NEW API RESPONSE: $data");

    if (data['routes'] == null || data['routes'].isEmpty) {
      throw Exception("No routes found");
    }

    final route = data['routes'][0];

    /// 🔹 Convert values
    double distanceKm = route['distanceMeters'] / 1000;

    Duration duration = parseDuration(route['duration']); // with traffic
    Duration staticDuration =
    parseDuration(route['staticDuration']); // without traffic

    return {
      "distance": "${distanceKm.toStringAsFixed(2)} km",
      "duration": formatDuration(staticDuration),
      "traffic_duration": formatDuration(duration),
    };
  }


  static Duration parseDuration(String duration) {
    final seconds = int.parse(duration.replaceAll("s", ""));
    return Duration(seconds: seconds);
  }

 static String formatDuration(Duration d) {
    int hours = d.inHours;
    int minutes = d.inMinutes % 60;

    if (hours > 0) {
      return "$hours h $minutes min";
    } else {
      return "$minutes min";
    }
  }
  ///Weather

  /// “Flight delay ho sakti hai ya nahi?”
  //
  // Toh humein sirf temp nahi, yeh cheezein chahiye:
  //
  // ✈️ Important Weather Factors for Flights
  //
  // Ye 5 cheezein decide karti hain delay:
  //
  // 1. 🌧️ Rain / Thunderstorm
  // Heavy rain = ❌ delay chances high
  // Thunderstorm = ❌❌ HIGH delay
  // 2. 🌫️ Visibility (Fog / Smog)
  // Low visibility = ❌ flights delay / divert
  // 3. 💨 Wind Speed
  // High wind (>25 km/h) = ❌ landing issue
  // 4. 🌡️ Extreme Temperature
  // Usually ok, but heatwaves affect performance
  // 5. ☁️ Clouds
  // Low clouds = risky for landing
  static Future<Map<String, dynamic>> getWeather(
      double lat,
      double lng,
      ) async {
    final url = Uri.parse(
      "https://api.openweathermap.org/data/2.5/weather?"
          // "lat=${52.746}&lon=${-87.749}&appid=d93ae92db1225dd97aae37e416568e8b&units=metric",
          "lat=$lat&lon=$lng&appid=d93ae92db1225dd97aae37e416568e8b&units=metric",
    );

    final response = await http.get(url);
    final data = jsonDecode(response.body);
    /// 🔥 RAW JSON print (string)
    print("RAW RESPONSE:");
    print(response.body);

    return {
      "temp": data['main']['temp'],
      "condition": data['weather'][0]['main'],
      "description": data['weather'][0]['description'],
      "wind": data['wind']['speed'], // m/s
      "visibility": data['visibility'], // meters
      "humidity": data['main']['humidity'],
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