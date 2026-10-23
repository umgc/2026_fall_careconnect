import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import 'api_service.dart';
import '../config/env_constant.dart';

/// AI Configuration Data Transfer Object
class PatientAIConfigDTO {
  final int? id;
  final int patientId;
  final String aiProvider;
  final Map<String, dynamic> preferences;
  final List<String> enabledFeatures;
  final int maxTokensPerSession;
  final double temperature;
  final String personalityStyle;
  final bool contextMemoryEnabled;
  final bool medicalContextEnabled;
  final String language;
  final bool emergencyAlertsEnabled;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isActive;

  PatientAIConfigDTO({
    this.id,
    required this.patientId,
    required this.aiProvider,
    required this.preferences,
    required this.enabledFeatures,
    required this.maxTokensPerSession,
    required this.temperature,
    required this.personalityStyle,
    required this.contextMemoryEnabled,
    required this.medicalContextEnabled,
    required this.language,
    required this.emergencyAlertsEnabled,
    this.createdAt,
    this.updatedAt,
    this.isActive = true,
  });

  factory PatientAIConfigDTO.fromJson(Map<String, dynamic> json) {
    return PatientAIConfigDTO(
      id: json['id'],
      patientId: json['patientId'],
      aiProvider: json['aiProvider'] ?? 'DEFAULT',
      preferences: Map<String, dynamic>.from(json['preferences'] ?? {}),
      enabledFeatures: List<String>.from(json['enabledFeatures'] ?? []),
      maxTokensPerSession: json['maxTokensPerSession'] ?? 1000,
      temperature: (json['temperature'] ?? 0.7).toDouble(),
      personalityStyle: json['personalityStyle'] ?? 'PROFESSIONAL',
      contextMemoryEnabled: json['contextMemoryEnabled'] ?? true,
      medicalContextEnabled: json['medicalContextEnabled'] ?? true,
      language: json['language'] ?? 'en',
      emergencyAlertsEnabled: json['emergencyAlertsEnabled'] ?? true,
      createdAt:
          json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
      updatedAt:
          json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
      isActive: json['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'patientId': patientId,
      'aiProvider': aiProvider,
      'preferences': preferences,
      'enabledFeatures': enabledFeatures,
      'maxTokensPerSession': maxTokensPerSession,
      'temperature': temperature,
      'personalityStyle': personalityStyle,
      'contextMemoryEnabled': contextMemoryEnabled,
      'medicalContextEnabled': medicalContextEnabled,
      'language': language,
      'emergencyAlertsEnabled': emergencyAlertsEnabled,
      'isActive': isActive,
    };
  }

  PatientAIConfigDTO copyWith({
    int? id,
    int? patientId,
    String? aiProvider,
    Map<String, dynamic>? preferences,
    List<String>? enabledFeatures,
    int? maxTokensPerSession,
    double? temperature,
    String? personalityStyle,
    bool? contextMemoryEnabled,
    bool? medicalContextEnabled,
    String? language,
    bool? emergencyAlertsEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
  }) {
    return PatientAIConfigDTO(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      aiProvider: aiProvider ?? this.aiProvider,
      preferences: preferences ?? this.preferences,
      enabledFeatures: enabledFeatures ?? this.enabledFeatures,
      maxTokensPerSession: maxTokensPerSession ?? this.maxTokensPerSession,
      temperature: temperature ?? this.temperature,
      personalityStyle: personalityStyle ?? this.personalityStyle,
      contextMemoryEnabled: contextMemoryEnabled ?? this.contextMemoryEnabled,
      medicalContextEnabled:
          medicalContextEnabled ?? this.medicalContextEnabled,
      language: language ?? this.language,
      emergencyAlertsEnabled:
          emergencyAlertsEnabled ?? this.emergencyAlertsEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
    );
  }
}

/// Service to manage AI configuration settings for patients
class AIConfigService {
  static String get baseUrl => '${getBackendBaseUrl()}/v1/api/ai-chat';

  /// Create or update AI configuration for a user
  /// Returns the saved PatientAIConfigDTO or null on failure
  static Future<PatientAIConfigDTO?> saveUserAIConfig(
    PatientAIConfigDTO config, {
    required int userId,
  }) async {
    try {
      final authHeaders = await ApiService.getAuthHeaders();
      authHeaders['Content-Type'] = 'application/json';
      authHeaders['Accept'] = '*/*';

      // Compose request body to match backend UserAIConfigDTO structure
      final requestBody = {
        'userId': userId,
        'patientId': config.patientId,
        'preferredAiProvider': config.aiProvider,
        'openaiModel': config.preferences['openaiModel'] ?? 'gpt-4',
        'deepseekModel': config.preferences['deepseekModel'] ?? 'deepseek-chat',
        'maxTokens': config.maxTokensPerSession,
        'temperature': config.temperature,
        'conversationHistoryLimit':
            config.preferences['conversationHistoryLimit'] ?? 20,
        'includeVitalsByDefault':
            config.preferences['includeVitalsByDefault'] ?? true,
        'includeMedicationsByDefault':
            config.preferences['includeMedicationsByDefault'] ?? true,
        'includeNotesByDefault':
            config.preferences['includeNotesByDefault'] ?? true,
        'includeMoodPainByDefault':
            config.preferences['includeMoodPainLogsByDefault'] ?? true,
        'includeAllergiesByDefault':
            config.preferences['includeAllergiesByDefault'] ?? true,
        'isActive': config.isActive,
        'systemPrompt': config.preferences['systemPrompt'] ??
            'You are a helpful AI assistant that helps patients access their health information.',
      };

      final response = await http.post(
        Uri.parse('$baseUrl/config'),
        headers: authHeaders,
        body: jsonEncode(requestBody),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return PatientAIConfigDTO.fromJson(data);
      } else {
        print('❌ Failed to save/update AI config: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Error saving/updating AI config: $e');
      return null;
    }
  }

  /// Get AI configuration for the logged-in user
  /// Usage: AIConfigService.getUserAIConfig(context)
  static Future<PatientAIConfigDTO?> getUserAIConfig(context) async {
    try {
      final authHeaders = await ApiService.getAuthHeaders();
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final userId = userProvider.user?.id;
      if (userId == null) {
        print('❌ No logged-in user found for AI config fetch.');
        return null;
      }
      final uri = Uri.parse(
        '$baseUrl/config',
      ).replace(queryParameters: {'userId': userId.toString()});
      print('🤖 Getting AI config for userId $userId from: $uri');
      final response = await http.get(uri, headers: authHeaders);
      print('🤖 AI config response status: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return PatientAIConfigDTO.fromJson(data);
      } else if (response.statusCode == 404) {
        print('🤖 No AI config found for userId $userId, using default');
        return _getDefaultConfig(userId);
      } else {
        print('❌ Failed to get AI config: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Error getting AI config: $e');
      return null;
    }
  }

  // ...keep only DTO and single config logic if needed...

  /// Get default AI configuration for a patient
  static PatientAIConfigDTO _getDefaultConfig(int patientId) {
    return PatientAIConfigDTO(
      patientId: patientId,
      aiProvider: 'DEFAULT',
      preferences: {
        'responseLength': 'medium',
        'technicalLevel': 'basic',
        'empathyLevel': 'high',
      },
      enabledFeatures: [
        'general_chat',
        'medical_questions',
        'appointment_reminders',
        'medication_reminders',
      ],
      maxTokensPerSession: 1000,
      temperature: 0.7,
      personalityStyle: 'PROFESSIONAL',
      contextMemoryEnabled: true,
      medicalContextEnabled: true,
      language: 'en',
      emergencyAlertsEnabled: true,
    );
  }

  /// Get available AI providers
  static List<Map<String, String>> getAvailableProviders() {
    return [
      {'value': 'DEFAULT', 'label': 'Default AI Assistant'},
      {'value': 'DEEPSEEK', 'label': 'DeepSeek (Advanced)'},
      {'value': 'OPENAI', 'label': 'OpenAI GPT (Premium)'},
      {'value': 'MEDICAL_SPECIALIST', 'label': 'Medical Specialist AI'},
    ];
  }

  /// Get available personality styles
  static List<Map<String, String>> getPersonalityStyles() {
    return [
      {'value': 'PROFESSIONAL', 'label': 'Professional & Clinical'},
      {'value': 'FRIENDLY', 'label': 'Friendly & Supportive'},
      {'value': 'EMPATHETIC', 'label': 'Empathetic & Caring'},
      {'value': 'DIRECT', 'label': 'Direct & Concise'},
      {'value': 'EDUCATIONAL', 'label': 'Educational & Informative'},
    ];
  }

  /// Get available AI features
  static List<Map<String, dynamic>> getAvailableFeatures() {
    return [
      {
        'value': 'general_chat',
        'label': 'General Conversation',
        'description': 'Basic chat and conversation capabilities',
        'icon': 'chat',
      },
      {
        'value': 'medical_questions',
        'label': 'Medical Questions',
        'description': 'Answer health and medical related questions',
        'icon': 'medical_services',
      },
      {
        'value': 'symptom_analysis',
        'label': 'Symptom Analysis',
        'description': 'Help analyze and understand symptoms',
        'icon': 'analytics',
      },
      {
        'value': 'appointment_reminders',
        'label': 'Appointment Reminders',
        'description': 'Reminders for upcoming appointments',
        'icon': 'schedule',
      },
      {
        'value': 'medication_reminders',
        'label': 'Medication Reminders',
        'description': 'Reminders for medication schedules',
        'icon': 'medication',
      },
      {
        'value': 'emergency_assistance',
        'label': 'Emergency Assistance',
        'description': 'Help during emergency situations',
        'icon': 'emergency',
      },
      {
        'value': 'mental_health_support',
        'label': 'Mental Health Support',
        'description': 'Basic mental health and wellness support',
        'icon': 'psychology',
      },
      {
        'value': 'nutrition_advice',
        'label': 'Nutrition Advice',
        'description': 'Dietary and nutrition recommendations',
        'icon': 'restaurant',
      },
      {
        'value': 'exercise_guidance',
        'label': 'Exercise Guidance',
        'description': 'Physical activity and exercise recommendations',
        'icon': 'fitness_center',
      },
    ];
  }

  /// Get available languages
  static List<Map<String, String>> getAvailableLanguages() {
    return [
      {'value': 'en', 'label': 'English'},
      {'value': 'es', 'label': 'Spanish'},
      {'value': 'fr', 'label': 'French'},
      {'value': 'de', 'label': 'German'},
      {'value': 'it', 'label': 'Italian'},
      {'value': 'pt', 'label': 'Portuguese'},
      {'value': 'zh', 'label': 'Chinese'},
      {'value': 'ja', 'label': 'Japanese'},
      {'value': 'ko', 'label': 'Korean'},
      {'value': 'ar', 'label': 'Arabic'},
    ];
  }
}
