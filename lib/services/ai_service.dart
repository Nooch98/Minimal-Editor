import 'dart:convert';
import 'package:http/http.dart' as http;

class AIService {
  static Future<String> sendMessage({
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
    String? apiKey,
  }) async {
    final url = Uri.parse('${baseUrl.replaceAll(RegExp(r'\/$'), '')}/v1/chat/completions');
    
    final headers = {'Content-Type': 'application/json'};
    if (apiKey != null && apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }

    final response = await http.post(
      url,
      headers: headers,
      body: jsonEncode({
        "model": model,
        "messages": messages,
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

  static Future<String?> getInlineCompletion({
    required String baseUrl,
    required String model,
    required String codeBefore,
    required String codeAfter,
    String? apiKey,
  }) async {
    final url = Uri.parse('${baseUrl.replaceAll(RegExp(r'\/$'), '')}/v1/chat/completions');

    final headers = {'Content-Type': 'application/json'};
    if (apiKey != null && apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }

    final prompt = """
        You are a code autocompletion engine. 
        Complete the code. Output ONLY the raw code continuation.
        Do not include explanations, markdown, reasoning tags, or introductory text.
        
        Code before cursor:
        $codeBefore

        Code after cursor:
        $codeAfter
        """;

    try {
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode({
          "model": model,
          "messages": [{"role": "user", "content": prompt}],
          "temperature": 0.1,
          "max_tokens": 512,
          "reasoning_effort": "none" 
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final choices = data['choices'] as List?;
        if (choices == null || choices.isEmpty) return null;

        final message = choices[0]['message'] as Map<String, dynamic>?;
        if (message == null) return null;

        String suggestedCode = (message['content']?.toString() ?? "").trim();
        suggestedCode = suggestedCode.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true, caseSensitive: false), '');
        
        suggestedCode = suggestedCode
            .replaceAll(RegExp(r'^```[a-zA-Z]*\n', caseSensitive: false), '')
            .replaceAll(RegExp(r'\n```$', caseSensitive: false), '')
            .replaceAll(RegExp(r'```', caseSensitive: false), '')
            .trim();

        if (suggestedCode.isEmpty) {
          suggestedCode = (message['reasoning_content']?.toString() ?? "").trim();
        }

        return suggestedCode.isEmpty ? null : suggestedCode;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
