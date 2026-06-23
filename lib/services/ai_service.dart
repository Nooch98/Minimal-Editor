import 'dart:convert';
import 'package:http/http.dart' as http;

class AIService {
  static Future<String> sendMessage({
    required String baseUrl,
    required String model,
    required String message,
  }) async {
    final url = Uri.parse('${baseUrl.replaceAll(RegExp(r'\/$'), '')}/v1/chat/completions');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "model": model,
        "messages": [
          {"role": "user", "content": message}
        ],
        "temperature": 0.7,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['choices'][0]['message']['content'];
    } else {
      throw Exception('Failed to connect: ${response.statusCode} - ${response.body}');
    }
  }
}
