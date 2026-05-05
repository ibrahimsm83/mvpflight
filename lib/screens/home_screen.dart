// screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';

// import 'package:google_places_autocomplete_text_field/google_places_autocomplete_text_field.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import '../controller/travel_controller.dart';
import '../services/api_service.dart';

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
      appBar: AppBar(title: Text("Travel Planner"), centerTitle: true),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              /// 🔹 HOME LOCATION
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: GooglePlaceAutoCompleteTextField(
                    textEditingController: controller.homeController,
                    googleAPIKey: ApiService.apiKey,
                    focusNode: controller.homeFocus,
                    // countries: ["pk"],
                    isLatLngRequired: false,
                    inputDecoration: InputDecoration(
                      hintText: "Enter Home Location",
                      border: InputBorder.none,
                      prefixIcon: Icon(Icons.home),
                    ),
                    itemClick: (prediction) {
                      controller.homeController.text =
                          prediction.description ?? "";

                      if (prediction.placeId != null) {
                        controller.getPlaceLatLng(
                          prediction.placeId!,
                          isHome: true,
                        );

                      }
                    },
                  ),
                ),
              ),

              SizedBox(height: 12),

              /// 🔹 DESTINATION
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: GooglePlaceAutoCompleteTextField(
                    textEditingController: controller.destController,
                    googleAPIKey: ApiService.apiKey,
                    focusNode: controller.destFocus,
                    // countries: ["pk"],
                    isLatLngRequired: false,
                    inputDecoration: InputDecoration(
                      hintText: "Enter Airport / Destination",
                      border: InputBorder.none,
                      prefixIcon: Icon(Icons.location_on),
                    ),
                    itemClick: (prediction) {
                      controller.destController.text =
                          prediction.description ?? "";
                      FocusScope.of(context).unfocus();

                      if (prediction.placeId != null) {
                        // controller.getPlaceLatLng(
                        //   prediction.placeId!,
                        //   isHome: false,
                        // );
                        controller.getPlaceLatLng(
                          prediction.placeId!,
                          isHome: false,
                        ).then((_) {
                       controller.analyzeWeather(); // 🔥(); // 🔥 important
                        });
                      }
                    },
                  ),
                ),
              ),

              SizedBox(height: 20),

              /// 🔹 BUTTON
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: controller.getDistance,
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text("Calculate Route"),
                ),
              ),

              SizedBox(height: 20),

              /// 🔹 RESULT CARD
              Obx(
                () => Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("Distance"),
                            Text(controller.distance.value),
                          ],
                        ),
                        Divider(),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("Without Traffic"),
                            Text(controller.duration.value),
                          ],
                        ),
                        Divider(),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("With Traffic"),
                            Text(controller.traficDuration.value),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              Obx(() => controller.flightRisk.value.isEmpty
                  ? SizedBox()
                  : Card(
                color: Colors.black87,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        "Airport Weather Status",
                        style: TextStyle(color: Colors.white70),
                      ),
                      SizedBox(height: 10),

                      Text(
                        controller.flightRisk.value,
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      SizedBox(height: 8),

                      Text(
                        controller.weatherDesc.value,
                        style: TextStyle(color: Colors.white60),
                      ),
                    ],
                  ),
                ),
              )),

              ///Step 2
              ///Sizedb
              SizedBox(height: 20.0),
              // home_screen.dart me add karo
              Text("Enter Flight Number"),
              SizedBox(height: 20.0),

              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 21.0),
                  child: TextField(
                    controller: TextEditingController(),
                    onSubmitted: (value) {
                      controller.getFlightStatus(value);
                    },
                    decoration: InputDecoration(
                      hintText: "Enter Flight Number (e.g. PK303)",
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),

              SizedBox(height: 20),

              Obx(
                () => controller.isLoading.value
                    ? CircularProgressIndicator()
                    : Column(
                        children: [
                          Text("Status: ${controller.flightStatus.value}"),
                          Text("Departure: ${controller.departureTime.value}"),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
