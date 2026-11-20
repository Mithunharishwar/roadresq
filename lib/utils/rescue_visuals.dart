import 'package:flutter/material.dart';

class RescueVisuals {
  static String vehicleAsset(String vehicle) {
    switch (vehicle.toLowerCase()) {
      case 'bike':
        return 'assets/vehicles/bike.png';
      case 'scooter':
        return 'assets/vehicles/scooter.png';
      case 'car':
        return 'assets/vehicles/car.png';
      case 'suv':
        return 'assets/vehicles/suv.png';
      case 'van':
        return 'assets/vehicles/van.png';
      case 'truck':
        return 'assets/vehicles/truck.png';
      default:
        return 'assets/vehicles/car.png';
    }
  }

  static String issueAsset(String issue) {
    switch (issue.toLowerCase()) {
      case 'flat tyre':
        return 'assets/issues/flat_tyre.png';
      case 'battery problem':
        return 'assets/issues/battery_problem.png';
      case 'fuel delivery':
        return 'assets/issues/fuel_delivery.png';
      case 'engine trouble':
        return 'assets/issues/engine_trouble.png';
      case 'towing':
        return 'assets/issues/towing.png';
      case 'general service':
        return 'assets/issues/general_service.png';
      default:
        return 'assets/issues/general_service.png';
    }
  }

  static Widget imageOrFallback({
    required String assetPath,
    required IconData fallbackIcon,
    double size = 36,
    Color fallbackColor = Colors.red,
  }) {
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) {
        return Icon(fallbackIcon, size: size, color: fallbackColor);
      },
    );
  }
}
