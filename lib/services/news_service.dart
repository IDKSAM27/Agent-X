import '../models/news_model.dart';

class NewsService {
  static Future<List<NewsArticle>> fetchNewsForProfession(String profession) async {
    await Future.delayed(const Duration(seconds: 1)); // simulate loading

    return switch (profession.toLowerCase()) {
      'student' => [
        NewsArticle(title: "Exam Tips", description: "Best tips to prepare for exams."),
        NewsArticle(title: "College Events", description: "Latest happenings in your college."),
      ],
      'teacher' => [
        NewsArticle(title: "Teaching Tools", description: "Top 5 tools for modern classrooms."),
        NewsArticle(title: "Online Teaching", description: "How to manage hybrid classes."),
      ],
      _ => [
        NewsArticle(title: "World News", description: "Stay updated with daily headlines."),
        NewsArticle(title: "Tech Buzz", description: "Trending tech stories of the day."),
      ]
    };
  }
}
