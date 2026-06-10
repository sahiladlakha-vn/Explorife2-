import 'package:flutter/foundation.dart';
import '../models/user.dart';

class UserProvider extends ChangeNotifier {
  AppUser _user = const AppUser(
    id: 'u1',
    name: 'Alex Rivera',
    email: 'alex.rivera@explorife.app',
    avatarUrl: 'https://picsum.photos/seed/user1/200/200',
    bio: 'Adventure seeker | 30+ countries visited 🌍',
    tripsCount: 31,
    savedCount: 14,
    visitedDestinationIds: ['1', '3', '7'],
    savedDestinationIds: ['2', '4', '8'],
  );

  AppUser get user => _user;

  void updateBio(String bio) {
    _user = AppUser(
      id: _user.id, name: _user.name, email: _user.email,
      avatarUrl: _user.avatarUrl, bio: bio,
      tripsCount: _user.tripsCount, savedCount: _user.savedCount,
      visitedDestinationIds: _user.visitedDestinationIds,
      savedDestinationIds: _user.savedDestinationIds,
    );
    notifyListeners();
  }
}
