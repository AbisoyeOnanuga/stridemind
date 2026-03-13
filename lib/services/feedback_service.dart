import 'package:google_generative_ai/google_generative_ai.dart';

class FeedbackService {
  final GenerativeModel _model;
  static const String _geminiApiKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

  FeedbackService()
      : _model = GenerativeModel(
          model: 'gemini-2.5-flash',
          apiKey: _geminiApiKey,
        );

  Future<String> getFeedback(String prompt) async {
    if (_geminiApiKey.isEmpty) {
      return "AI coach is not configured for this build. Set GEMINI_API_KEY with --dart-define.";
    }
    try {
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      return response.text ?? "Sorry, I couldn't generate feedback right now.";
    } catch (e) {
      // Handle API errors
      return "Error generating feedback: ${e.toString()}";
    }
  }

  Stream<String> streamFeedback(String prompt) async* {
    if (_geminiApiKey.isEmpty) {
      yield "AI coach is not configured for this build. Set GEMINI_API_KEY with --dart-define.";
      return;
    }
    try {
      final content = [Content.text(prompt)];
      await for (final response in _model.generateContentStream(content)) {
        final chunk = response.text;
        if (chunk != null && chunk.isNotEmpty) {
          yield chunk;
        }
      }
    } catch (e) {
      yield "Error generating feedback: ${e.toString()}";
    }
  }
}