import 'package:flutter/material.dart';

class NewsArticle {
  final String id;
  final String title;
  final String description;
  final String summary;
  final String url;
  final String? imageUrl;
  final DateTime publishedAt;
  final String source;
  final NewsCategory category;
  final double relevanceScore;
  final double qualityScore;
  final List<String> tags;
  final List<String> keywords;
  final bool isLocalEvent;
  final bool isUrgent;
  final DateTime? eventDate;
  final String? eventLocation;
  final List<NewsAction> availableActions;

  NewsArticle({
    required this.id,
    required this.title,
    required this.description,
    required this.summary,
    required this.url,
    this.imageUrl,
    required this.publishedAt,
    required this.source,
    required this.category,
    required this.relevanceScore,
    required this.qualityScore,
    required this.tags,
    required this.keywords,
    required this.isLocalEvent,
    required this.isUrgent,
    this.eventDate,
    this.eventLocation,
    required this.availableActions,
  });

  factory NewsArticle.fromJson(Map<String, dynamic> json) {
    return NewsArticle(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      summary: json['summary'],
      url: json['url'],
      imageUrl: json['image_url'],
      publishedAt: DateTime.parse(json['published_at']),
      source: json['source'],
      category: NewsCategory.fromString(json['category']),
      relevanceScore: json['relevance_score']?.toDouble() ?? 0.0,
      qualityScore: json['quality_score']?.toDouble() ?? 0.0,
      tags: List<String>.from(json['tags'] ?? []),
      keywords: List<String>.from(json['keywords'] ?? []),
      isLocalEvent: json['is_local_event'] ?? false,
      isUrgent: json['is_urgent'] ?? false,
      eventDate: json['event_date'] != null ? DateTime.parse(json['event_date']) : null,
      eventLocation: json['event_location'],
      availableActions: (json['available_actions'] as List?)
          ?.map((action) => NewsAction.fromJson(action))
          .toList() ?? [],
    );
  }

  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(publishedAt);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${(difference.inDays / 7).floor()}w ago';
    }
  }

  Color get categoryColor {
    return category.color;
  }

  IconData get categoryIcon {
    return category.icon;
  }
}

enum NewsCategory {
  localEvents('local_events', 'Local Events', Icons.location_on, Colors.orange),
  professionalDev('professional_dev', 'Professional Development', Icons.trending_up, Colors.blue),
  industryTrends('industry_trends', 'Industry Trends', Icons.insights, Colors.purple),
  productivity('productivity', 'Productivity', Icons.speed, Colors.green),
  careerOpportunities('career_opportunities', 'Career Opportunities', Icons.work, Colors.indigo),
  education('education', 'Education', Icons.school, Colors.teal),
  technology('technology', 'Technology', Icons.computer, Colors.cyan);

  const NewsCategory(this.value, this.displayName, this.icon, this.color);

  final String value;
  final String displayName;
  final IconData icon;
  final Color color;

  static NewsCategory fromString(String value) {
    return NewsCategory.values.firstWhere(
          (category) => category.value == value,
      orElse: () => NewsCategory.industryTrends,
    );
  }
}

class NewsAction {
  final String type;
  final String label;
  final String icon;
  final String color;
  final Map<String, dynamic> metadata;

  NewsAction({
    required this.type,
    required this.label,
    required this.icon,
    required this.color,
    required this.metadata,
  });

  factory NewsAction.fromJson(Map<String, dynamic> json) {
    return NewsAction(
      type: json['type'],
      label: json['label'],
      icon: json['icon'],
      color: json['color'],
      metadata: json['metadata'] ?? {},
    );
  }

  IconData get iconData {
    switch (icon) {
      case 'calendar_today':
        return Icons.calendar_today;
      case 'task_alt':
        return Icons.task_alt;
      case 'notifications':
        return Icons.notifications;
      case 'work':
        return Icons.work;
      case 'bookmark':
        return Icons.bookmark;
      default:
        return Icons.info;
    }
  }

  Color get colorValue {
    return Color(int.parse(color.replaceFirst('#', '0xff')));
  }
}

class NewsResponse {
  final List<NewsArticle> articles;
  final Map<String, List<NewsArticle>> categories;
  final NewsMetadata metadata;

  NewsResponse({
    required this.articles,
    required this.categories,
    required this.metadata,
  });

  factory NewsResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;

    return NewsResponse(
      articles: (data['articles'] as List)
          .map((article) => NewsArticle.fromJson(article))
          .toList(),
      categories: (data['categories'] as Map<String, dynamic>? ?? {})
          .map((key, value) => MapEntry(
          key,
          (value as List)
              .map((article) => NewsArticle.fromJson(article))
              .toList())),
      metadata: NewsMetadata.fromJson(data['metadata']),
    );
  }
}

class NewsMetadata {
  final int totalArticles;
  final int rawArticlesFetched;
  final int sourcesUsed;
  final DateTime lastUpdated;
  final Map<String, dynamic> userProfile;

  NewsMetadata({
    required this.totalArticles,
    required this.rawArticlesFetched,
    required this.sourcesUsed,
    required this.lastUpdated,
    required this.userProfile,
  });

  factory NewsMetadata.fromJson(Map<String, dynamic> json) {
    return NewsMetadata(
      totalArticles: json['total_articles'] ?? 0,
      rawArticlesFetched: json['raw_articles_fetched'] ?? 0,
      sourcesUsed: json['sources_used'] ?? 0,
      lastUpdated: DateTime.parse(json['last_updated']),
      userProfile: json['user_profile'] ?? {},
    );
  }
}
