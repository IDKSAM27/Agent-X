class ApiConfig {
  // Development configuration
  static const String baseUrl = "http://192.168.1.10:8000"; // Local machine's IP btw.. you dumb fuq

  // API endpoints
  static const String agentsEndpoint = "/api/agents";
  static const String healthEndpoint = "/api/health";

  // For production deployment
  // static const String baseUrl = "https://your-deployed-api.com";

  // Timeouts
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);

  static const Map<String, String> defaultHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };
}
