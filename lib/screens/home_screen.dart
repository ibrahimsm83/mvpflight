
// screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import '../controller/travel_controller.dart';

class HomeScreen extends StatelessWidget {
  final controller = Get.put(TravelController());

  Future<void> checkPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      // Handle permanently denied case
    }

  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Travel App MVP")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
SizedBox(height: 100,),
            ElevatedButton(
              onPressed: () {
                checkPermission();
                controller.getDistance();
              },
              child: Text("Calculate Distance"),
            ),

            Obx(() => Text("Distance: ${controller.distance.value}")),
            Obx(() => Text("Time: ${controller.duration.value}")),
            Obx(() => Text("Traffic Duration Time: ${controller.traficDuration.value}")),


            ///Step 2
            // home_screen.dart me add karo

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 21.0),
              child: TextField(
                controller: TextEditingController(),
                onSubmitted: (value) {
                  controller.getFlightStatus(value);
                },
                decoration: InputDecoration(
                  hintText: "Enter Flight Number (e.g. PK303)",
                ),
              ),
            ),

            SizedBox(height: 20),

            Obx(() => controller.isLoading.value
                ? CircularProgressIndicator()
                : Column(
              children: [
                Text("Status: ${controller.flightStatus.value}"),
                Text("Departure: ${controller.departureTime.value}"),
              ],
            )),

          ],
        ),
      ),
    );
  }
}