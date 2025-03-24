import 'package:flutter/material.dart';
import '../widgets/menu_item.dart';
import '../widgets/profile_header.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final menuItems = [
      MenuItemData(icon: Icons.home, label: 'Home', color: Colors.blue),
      MenuItemData(icon: Icons.wallet, label: 'My Wallet', color: Colors.blue),
      MenuItemData(icon: Icons.history, label: 'History', color: Colors.blue),
      MenuItemData(icon: Icons.notifications, label: 'Notifications', color: Colors.blue),
      MenuItemData(icon: Icons.people, label: 'Invite Friends', color: Colors.blue),
      MenuItemData(icon: Icons.settings, label: 'Settings', color: Colors.blue),
      MenuItemData(icon: Icons.logout, label: 'Logout', color: Colors.blue),
    ];

    return Scaffold(
      body: Container(
        color: Colors.black,
        child: Stack(
          children: [
            // Background Image with Overlay
            Container(
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/images/vijay.png'),
                  fit: BoxFit.cover,
                ),
              ),
              child: Container(
                color: Colors.black.withOpacity(0.6),
              ),
            ),
            
            // Content
            SafeArea(
              child: Column(
                children: [
                  const ProfileHeader(),
                  const SizedBox(height: 40),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      child: ListView.separated(
                        itemCount: menuItems.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 40),
                        itemBuilder: (context, index) => MenuItem(
                          icon: menuItems[index].icon,
                          label: menuItems[index].label,
                          color: menuItems[index].color,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}