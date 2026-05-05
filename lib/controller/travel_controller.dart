import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';

class TravelController extends GetxController {

  /// 🔹 HOME LOCATION
  TextEditingController homeController = TextEditingController();
  FocusNode homeFocus = FocusNode();

  var homeLat = 0.0.obs;
  var homeLng = 0.0.obs;

  /// 🔹 DESTINATION (AIRPORT)
  TextEditingController destController = TextEditingController();
  FocusNode destFocus = FocusNode();

  var destLat = 0.0.obs;
  var destLng = 0.0.obs;

   ///Step 1
  var distance = ''.obs;
  var duration = ''.obs;
  var traficDuration = ''.obs;


  ///Step 2
  var flightStatus = ''.obs;
  var departureTime = ''.obs;
  var isLoading = false.obs;

  Future<void> getPlaceLatLng(String placeId, {required bool isHome}) async {
    try {
      final url = Uri.parse(
        "https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=${ApiService.apiKey}",
        // "https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=AIzaSyCDGe4wXXZ1gwVU2W1Qz66g5Rf0t-df9NQ",
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final location = data['result']['geometry']['location'];

        double lat = location['lat'];
        double lng = location['lng'];

        if (isHome) {
          homeLat.value = lat;
          homeLng.value = lng;
        } else {
          destLat.value = lat;
          destLng.value = lng;
        }
      }
    } catch (e) {
      print("Error: $e");
    }
  }

  Future<void> getDistance() async {
    if (homeLat.value == 0.0 || destLat.value == 0.0) {
      Get.snackbar("Error", "Please select both locations");
      return;
    }

    var result = await ApiService.getDistanceMatrix(
      homeLat.value,
      homeLng.value,
      destLat.value,
      destLng.value,
    );

    distance.value = result['distance'] ?? '';
    duration.value = result['duration'] ?? '';
    traficDuration.value = result['traffic_duration'] ?? '';
  }

  ///Weather
  /// 🔹 WEATHER
  var flightRisk = ''.obs;
  var weatherDesc = ''.obs;

  Future<void> analyzeWeather() async {
    var result = await ApiService.getWeather(destLat.value, destLng.value);

    weatherDesc.value = result['description'];

    double wind = result['wind'] * 3.6; // convert to km/h
    int visibility = result['visibility'];
    String condition = result['condition'];

    /// 🔥 FLIGHT RISK LOGIC
    if (condition.contains("Thunderstorm")) {
      flightRisk.value = "❌ High Delay (Storm)";
    } else if (condition.contains("Rain")) {
      flightRisk.value = "⚠️ Possible Delay (Rain)";
    } else if (visibility < 2000) {
      flightRisk.value = "⚠️ Low Visibility";
    } else if (wind > 30) {
      flightRisk.value = "⚠️ Strong Winds";
    } else {
      flightRisk.value = "✅ Good Weather (On Time)";
    }
  }

  //--------------------weather End


  ///Step 2 (Same)
  Future<void> getFlightStatus(String flightNo) async {
    try {
      isLoading.value = true;

      var result = await ApiService.getFlightData(flightNo);
      log(result.toString());

      flightStatus.value = result['status'] ?? '';
      departureTime.value = result['departure'] ?? '';

    } catch (e) {
      Get.snackbar("Error", "Flight not found");
    } finally {
      isLoading.value = false;
    }
  }
}