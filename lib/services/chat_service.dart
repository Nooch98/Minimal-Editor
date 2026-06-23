class ChatService {
  static final List<Map<String, String>> messages = [];
  
  static void addMessage(String role, String content) {
    messages.add({"role": role, "content": content});
  }
}
