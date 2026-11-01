import 'dart:async';
import '../../widgets/expressive_face.dart';

/// A lightweight in-memory bus to hold latest inferred ExpressionData
/// and expose a stream for interested parties (UI, BrainService, etc.).
class ExpressionStateBus {
  ExpressionStateBus._internal();
  static final ExpressionStateBus _instance = ExpressionStateBus._internal();
  factory ExpressionStateBus() => _instance;

  final _controller = StreamController<ExpressionData>.broadcast();
  ExpressionData _latest = ExpressionData.neutral();

  Stream<ExpressionData> get stream => _controller.stream;
  ExpressionData get latest => _latest;

  void set(ExpressionData data) {
    _latest = data;
    _controller.add(data);
  }

  void dispose() {
    _controller.close();
  }
}
