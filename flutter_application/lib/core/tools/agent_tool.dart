abstract class AgentTool {
  String get name;
  String get description;
  // A simple description of arguments, e.g. "query: string"
  String get usage;

  Future<String> execute(String args);
}
