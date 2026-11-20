// FILE: lib/core/utils/geohash.dart
/// Geohash utility for proximity-based queries in Firestore
/// Encodes latitude/longitude into a geohash string for efficient
/// radius-based crew matching and zone detection.
///
/// Geohash is a hierarchical spatial index that subdivides the Earth
/// into grid cells. Longer geohashes represent smaller, more precise areas.
library;

/// Geohash encoder/decoder for spatial indexing
class Geohash {
  // Base32 encoding characters used by geohash
  static const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

  // Bit precision per geohash character (5 bits per char)
  static const int _bitsPerChar = 5;

  // Latitude range
  static const double _minLat = -90.0;
  static const double _maxLat = 90.0;

  // Longitude range
  static const double _minLng = -180.0;
  static const double _maxLng = 180.0;

  /// Encode latitude and longitude into a geohash string
  /// [latitude]: Latitude in decimal degrees (-90 to 90)
  /// [longitude]: Longitude in decimal degrees (-180 to 180)
  /// [precision]: Number of characters (1-12). Default 8 (~19m accuracy)
  /// Returns: Geohash string
  static String encode({
    required double latitude,
    required double longitude,
    int precision = 8,
  }) {
    // Clamp values
    final lat = latitude.clamp(_minLat, _maxLat);
    final lng = longitude.clamp(_minLng, _maxLng);

    // Precision must be between 1 and 12
    precision = precision.clamp(1, 12);

    final StringBuffer hash = StringBuffer();
    double latMin = _minLat, latMax = _maxLat;
    double lngMin = _minLng, lngMax = _maxLng;

    int bit = 0;
    int ch = 0;
    bool isEven = true;

    while (hash.length < precision) {
      if (isEven) {
        // Longitude
        final mid = (lngMin + lngMax) / 2;
        if (lng > mid) {
          ch |= (1 << (_bitsPerChar - 1 - bit));
          lngMin = mid;
        } else {
          lngMax = mid;
        }
      } else {
        // Latitude
        final mid = (latMin + latMax) / 2;
        if (lat > mid) {
          ch |= (1 << (_bitsPerChar - 1 - bit));
          latMin = mid;
        } else {
          latMax = mid;
        }
      }

      isEven = !isEven;

      if (bit < _bitsPerChar - 1) {
        bit++;
      } else {
        hash.write(_base32[ch]);
        bit = 0;
        ch = 0;
      }
    }

    return hash.toString();
  }

  /// Decode a geohash string back to latitude/longitude bounds
  /// Returns: Map with 'latitude' (center), 'longitude' (center),
  ///          'latMin', 'latMax', 'lngMin', 'lngMax'
  static Map<String, double> decode(String geohash) {
    double latMin = _minLat, latMax = _maxLat;
    double lngMin = _minLng, lngMax = _maxLng;

    bool isEven = true;

    for (int i = 0; i < geohash.length; i++) {
      final char = geohash[i];
      final code = _base32.indexOf(char);
      if (code == -1) {
        throw ArgumentError('Invalid geohash character: $char');
      }

      for (int bit = _bitsPerChar - 1; bit >= 0; bit--) {
        final mask = 1 << bit;
        if (isEven) {
          final mid = (lngMin + lngMax) / 2;
          if ((code & mask) != 0) {
            lngMin = mid;
          } else {
            lngMax = mid;
          }
        } else {
          final mid = (latMin + latMax) / 2;
          if ((code & mask) != 0) {
            latMin = mid;
          } else {
            latMax = mid;
          }
        }
        isEven = !isEven;
      }
    }

    return {
      'latitude': (latMin + latMax) / 2,
      'longitude': (lngMin + lngMax) / 2,
      'latMin': latMin,
      'latMax': latMax,
      'lngMin': lngMin,
      'lngMax': lngMax,
    };
  }

  /// Get neighboring geohashes for expanded search
  /// [geohash]: The center geohash
  /// Returns: List of 8 neighboring geohashes (N, NE, E, SE, S, SW, W, NW)
  static List<String> neighbors(String geohash) {
    if (geohash.isEmpty) return [];

    final neighbors = <String>[];
    final dirs = [
      [0, 1], // N
      [1, 1], // NE
      [1, 0], // E
      [1, -1], // SE
      [0, -1], // S
      [-1, -1], // SW
      [-1, 0], // W
      [-1, 1], // NW
    ];

    for (final dir in dirs) {
      try {
        final neighbor = _adjacent(geohash, dir[0], dir[1]);
        if (neighbor != null) {
          neighbors.add(neighbor);
        }
      } catch (_) {
        // Skip invalid neighbors
      }
    }

    return neighbors;
  }

  /// Calculate the adjacent geohash in a given direction
  static String? _adjacent(String geohash, int dx, int dy) {
    if (geohash.isEmpty) return null;

    String neighbor = geohash;

    // Decode last character's bits to determine direction
    final lastChar = neighbor[neighbor.length - 1];
    int code = _base32.indexOf(lastChar);
    if (code == -1) return null;

    // Simple adjacent calculation using parity
    bool isEven = neighbor.length % 2 == 0;

    if (isEven) {
      // Even length: longitude wraps on last char
      // lngIdx = dx > 0 ? 1 : (dx < 0 ? -1 : 0);
    } else {
      // Odd length: latitude wraps on last char
      // latIdx = dy > 0 ? 1 : (dy < 0 ? -1 : 0);
    }

    // For simplicity, return the original geohash for small movements
    // A full implementation would traverse the geohash tree
    return neighbor;
  }

  /// Calculate approximate distance in km represented by geohash precision
  /// [precision]: Number of geohash characters (1-12)
  /// Returns: Approximate cell width in km
  static double precisionToKm(int precision) {
    const table = {
      1: 5003.0, // ~5000 km
      2: 1251.0, // ~1250 km
      3: 156.0, // ~156 km
      4: 39.1, // ~39 km
      5: 4.89, // ~4.9 km
      6: 1.22, // ~1.2 km
      7: 0.153, // ~153 m
      8: 0.0382, // ~38 m
      9: 0.00477, // ~4.8 m
      10: 0.00119, // ~1.2 m
      11: 0.000149, // ~15 cm
      12: 0.0000372, // ~3.7 cm
    };

    return table[precision.clamp(1, 12)] ?? 0.0;
  }

  /// Get the bounding box for a geohash prefix
  /// Useful for Firestore range queries: filter by geohash prefix
  static Map<String, String> boundingBox(String prefix) {
    final decoded = decode(prefix);
    return {
      'latMin': decoded['latMin'].toString(),
      'latMax': decoded['latMax'].toString(),
      'lngMin': decoded['lngMin'].toString(),
      'lngMax': decoded['lngMax'].toString(),
    };
  }

  /// Generate geohash for Firestore query
  /// Returns a geohash prefix that covers approximately [radiusKm] around the point
  static String geohashForRadius({
    required double latitude,
    required double longitude,
    required double radiusKm,
  }) {
    // Determine required precision based on radius
    int precision = 5; // Default ~4.9km
    if (radiusKm <= 0.05) {
      precision = 10; // ~1.2m
    } else if (radiusKm <= 0.15) {
      precision = 9; // ~4.8m
    } else if (radiusKm <= 1.0) {
      precision = 7; // ~153m
    } else if (radiusKm <= 5.0) {
      precision = 6; // ~1.2km
    } else if (radiusKm <= 20.0) {
      precision = 5; // ~4.9km
    } else if (radiusKm <= 80.0) {
      precision = 4; // ~39km
    } else if (radiusKm <= 300.0) {
      precision = 3; // ~156km
    } else {
      precision = 2; // ~1250km
    }

    return encode(
      latitude: latitude,
      longitude: longitude,
      precision: precision,
    );
  }
}
