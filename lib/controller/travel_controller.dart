// controllers/travel_controller.dart

import 'dart:developer';

import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';

class TravelController extends GetxController {
  ///Step 1
  var distance = ''.obs;
  var duration = ''.obs;
  var traficDuration = ''.obs;

  ///Step 2
  var flightStatus = ''.obs;
  var departureTime = ''.obs;
  var isLoading = false.obs;

  ///Step1
  Future<void> getDistance() async {
    Position position = await Geolocator.getCurrentPosition();

    // Karachi Airport (MVP)
    double airportLat = 24.9065;
    double airportLng = 67.1608;

    var result = await ApiService.getDistanceMatrix(
      position.latitude,
      position.longitude,
      airportLat,
      airportLng,
    );
    print("result is $result");
    distance.value = result['distance']!;
    duration.value = result['duration']!;
    traficDuration.value = result['traffic_duration']!;
  }

  ///Step2
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

//24.834243, 67.055395
