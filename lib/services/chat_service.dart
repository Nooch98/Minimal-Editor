class ChatService {
  static final List<Map<String, String>> messages = [];

  static void addMessage(String role, String content) {
    messages.add({"role": role, "content": content});
  }

  static void clearChatHistory() {
    messages.clear();
  }

  static void setMessages(List<Map<String, String>> newMessages) {
    messages.clear();
    messages.addAll(newMessages);
  }
}
