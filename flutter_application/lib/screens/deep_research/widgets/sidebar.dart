import 'package:flutter/material.dart';
import '../../settings/settings_screen.dart';

class DeepResearchSidebar extends StatelessWidget {
  const DeepResearchSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: 260,
      color: colorScheme.surfaceContainerHigh,
      child: Column(
        children: [
          // 1. Logo / Header
          Container(
            padding: const EdgeInsets.all(20),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Icon(Icons.science, color: colorScheme.primary, size: 28),
                const SizedBox(width: 12),
                Text(
                  "Deep Research",
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          
          Divider(color: theme.dividerColor.withOpacity(0.12)),

          // 2. New Project Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: ElevatedButton.icon(
              onPressed: () {
                // TODO: Create new session
              },
              icon: const Icon(Icons.add),
              label: const Text("New Project"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 45),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),

          // 3. Project History List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Text(
                    "Recent Projects",
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                _buildHistoryItem(context, "Market Analysis: AI 2025", isActive: true),
                _buildHistoryItem(context, "Biotech Research: Enzyme X"),
                _buildHistoryItem(context, "Physics: Quantum Entanglement"),
              ],
            ),
          ),
          
          // 4. User/Settings Area (Minimal)
          Container(
            padding: const EdgeInsets.all(16),
            color: colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Colors.grey,
                  radius: 16,
                  child: Icon(Icons.person, size: 20, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "User",
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.settings, size: 20),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SettingsScreen(
                          initialIndex: 4,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(
    BuildContext context,
    String title, {
    bool isActive = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isActive ? colorScheme.primary.withOpacity(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isActive
            ? Border.all(color: colorScheme.primary.withOpacity(0.35))
            : null,
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          Icons.history, 
          color: isActive ? colorScheme.primary : colorScheme.onSurfaceVariant, 
          size: 18
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isActive ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: isActive 
            ? Icon(Icons.arrow_forward_ios, color: colorScheme.primary, size: 12)
            : null,
        onTap: () {
          // TODO: Load history item
        },
      ),
    );
  }
}
