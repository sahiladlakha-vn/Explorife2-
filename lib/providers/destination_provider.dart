import 'package:flutter/foundation.dart';
import '../models/destination.dart';

class DestinationProvider extends ChangeNotifier {
  String _selectedCategory = 'All';
  String _searchQuery = '';

  String get selectedCategory => _selectedCategory;
  String get searchQuery => _searchQuery;

  final List<Destination> _all = [
    Destination(
      id: '1', name: 'Santorini', country: 'Greece',
      description: 'Iconic white-washed buildings, volcanic beaches, and stunning sunsets over the caldera make Santorini one of the world\'s most romantic destinations.',
      imageUrl: 'https://picsum.photos/seed/santorini/800/600',
      latitude: 36.3932, longitude: 25.4615,
      rating: 4.9, reviewCount: 2341, category: 'Beach',
      tags: ['Romantic', 'Scenic', 'Island', 'Sunset'],
      pricePerNight: 180,
    ),
    Destination(
      id: '2', name: 'Machu Picchu', country: 'Peru',
      description: 'An ancient Incan citadel set high in the Andes Mountains. A UNESCO World Heritage site shrouded in mist and mystery.',
      imageUrl: 'https://picsum.photos/seed/machupicchu/800/600',
      latitude: -13.1631, longitude: -72.5450,
      rating: 4.8, reviewCount: 1875, category: 'Mountains',
      tags: ['Historical', 'Hiking', 'Ancient', 'UNESCO'],
      pricePerNight: 120,
    ),
    Destination(
      id: '3', name: 'Tokyo', country: 'Japan',
      description: 'A dazzling blend of ultramodern and traditional, from neon-lit skyscrapers to historic temples, Tokyo is unlike any city on Earth.',
      imageUrl: 'https://picsum.photos/seed/tokyo/800/600',
      latitude: 35.6762, longitude: 139.6503,
      rating: 4.7, reviewCount: 3102, category: 'City',
      tags: ['Food', 'Technology', 'Culture', 'Nightlife'],
      pricePerNight: 150,
    ),
    Destination(
      id: '4', name: 'Bali', country: 'Indonesia',
      description: 'A lush paradise of terraced rice fields, ancient temples, vibrant arts scene, and world-class surf breaks.',
      imageUrl: 'https://picsum.photos/seed/bali/800/600',
      latitude: -8.3405, longitude: 115.0920,
      rating: 4.8, reviewCount: 2780, category: 'Beach',
      tags: ['Spiritual', 'Surfing', 'Rice Fields', 'Temples'],
      pricePerNight: 85,
    ),
    Destination(
      id: '5', name: 'Sahara Desert', country: 'Morocco',
      description: 'Experience the endless golden dunes, camel treks at sunrise, and star-filled skies in the world\'s largest hot desert.',
      imageUrl: 'https://picsum.photos/seed/sahara/800/600',
      latitude: 23.4162, longitude: -8.1389,
      rating: 4.6, reviewCount: 943, category: 'Desert',
      tags: ['Adventure', 'Camping', 'Camel Trek', 'Stars'],
      pricePerNight: 95,
    ),
    Destination(
      id: '6', name: 'Amazon Rainforest', country: 'Brazil',
      description: 'Dive into the planet\'s most biodiverse ecosystem — piranha fishing, jungle hikes, and pink river dolphins await.',
      imageUrl: 'https://picsum.photos/seed/amazon/800/600',
      latitude: -3.4653, longitude: -62.2159,
      rating: 4.7, reviewCount: 654, category: 'Jungle',
      tags: ['Wildlife', 'Eco-tourism', 'Adventure', 'Nature'],
      pricePerNight: 110,
    ),
    Destination(
      id: '7', name: 'Rome', country: 'Italy',
      description: 'The Eternal City brims with awe-inspiring art, ancient ruins, and world-renowned cuisine at every cobblestone turn.',
      imageUrl: 'https://picsum.photos/seed/rome/800/600',
      latitude: 41.9028, longitude: 12.4964,
      rating: 4.8, reviewCount: 4210, category: 'Cultural',
      tags: ['History', 'Art', 'Food', 'Architecture'],
      pricePerNight: 160,
    ),
    Destination(
      id: '8', name: 'Patagonia', country: 'Argentina',
      description: 'At the tip of South America, dramatic glaciers, jagged peaks, and windswept steppes offer the ultimate adventure.',
      imageUrl: 'https://picsum.photos/seed/patagonia/800/600',
      latitude: -51.6230, longitude: -69.2168,
      rating: 4.9, reviewCount: 712, category: 'Adventure',
      tags: ['Hiking', 'Glaciers', 'Wilderness', 'Trekking'],
      pricePerNight: 130,
    ),
  ];

  List<Destination> get destinations {
    return _all.where((d) {
      final matchesCategory = _selectedCategory == 'All' || d.category == _selectedCategory;
      final matchesSearch = _searchQuery.isEmpty ||
          d.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          d.country.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          d.tags.any((t) => t.toLowerCase().contains(_searchQuery.toLowerCase()));
      return matchesCategory && matchesSearch;
    }).toList();
  }

  List<Destination> get featured => _all.where((d) => d.rating >= 4.8).toList();
  List<Destination> get saved => _all.where((d) => d.isSaved).toList();

  Destination? findById(String id) {
    try {
      return _all.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  void selectCategory(String category) {
    _selectedCategory = category;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void toggleSave(String id) {
    final dest = findById(id);
    if (dest != null) {
      dest.isSaved = !dest.isSaved;
      notifyListeners();
    }
  }
}
