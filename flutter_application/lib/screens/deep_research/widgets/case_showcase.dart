import 'package:flutter/material.dart';

class CaseShowcase extends StatelessWidget {
  const CaseShowcase({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "User Case Showcase",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildCaseCard(
                  "Market Research Report",
                  "Analyzing global trends in AI...",
                  Colors.blue,
                ),
                _buildCaseCard(
                  "Annual PPT Generation",
                  "Generating slide deck from Q4 data...",
                  Colors.orange,
                ),
                _buildCaseCard(
                  "Stock Data Analysis",
                  "Processing CSV and creating charts...",
                  Colors.green,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaseCard(String title, String desc, Color color) {
    return Container(
      width: 240,
      margin: const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A35),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            desc,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          Align(
            alignment: Alignment.bottomRight,
            child: Icon(Icons.arrow_forward, color: color, size: 20),
          ),
        ],
      ),
    );
  }
}
