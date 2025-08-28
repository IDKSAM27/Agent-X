import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ChatService {
  static final String apiKey = dotenv.env['OPENROUTER_API_KEY'] ?? '';
  static const String endpoint = 'https://openrouter.ai/api/v1/chat/completions';

  static Future<String> getChatResponse(String message) async {
    try {
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'HTTP-Referer': 'https://yourapp.com', // Optional
          'X-Title': 'AgentXAssistant',
        },
        body: jsonEncode({
          "model": "google/gemma-3n-e4b-it:free",
          "messages": [
            {"role": "user", "content": message}
          ]
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'].toString().trim();
      } else {
        print('API Error: ${response.body}');
        return "Sorry, I couldn't generate a response.";
      }
    } catch (e) {
      print('Exception: $e');
      return "Error: Failed to get response.";
    }
  }
}
