import 'agent_tool.dart';

class ClockTool implements AgentTool {
  @override
  String get name => 'get_current_time';

  @override
  String get description => 'Get the current date and time. No arguments required.';

  @override
  String get usage => 'None';

  @override
  Future<String> execute(String args) async {
    final now = DateTime.now();
    return now.toString();
  }
}
