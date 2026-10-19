class Address {
  final String? line1;
  final String? line2;
  final String? city;
  final String? state;
  final String? zip;
  final String? phone;

  Address({
    this.line1,
    this.line2,
    this.city,
    this.state,
    this.zip,
    this.phone,
  });

  factory Address.fromJson(Map<String, dynamic> json) => Address(
        line1: json['line1'],
        line2: json['line2'],
        city: json['city'],
        state: json['state'],
        zip: json['zip'],
        phone: json['phone'],
      );

  Map<String, dynamic> toJson() => {
        'line1': line1,
        'line2': line2,
        'city': city,
        'state': state,
        'zip': zip,
        'phone': phone,
      };
}

class Patient {
  final int id;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String dob;
  final String relationship;
  final String? profileImageUrl;
  final Address? address;
  final int? linkId;
  final String linkStatus;
  final String? gender;
  final String? maNumber;
  final List<dynamic>? allergies;
  final Map<String, dynamic>? vitalConditions;
  // In-Home personalization fields
  final String? likes;
  final String? dislikes;
  final String? habits;
  final String? phobias;
  final String? preferredCommunicationMethod;
  final bool patientVideoCallsEnabled;

  Patient({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.dob,
    required this.relationship,
    this.profileImageUrl,
    this.address,
    this.linkId,
    this.linkStatus = 'ACTIVE',
    this.gender,
    this.maNumber,
    this.allergies,
    this.vitalConditions,
    this.likes,
    this.dislikes,
    this.habits,
    this.phobias,
    this.preferredCommunicationMethod,
    this.patientVideoCallsEnabled = true,
  });

  factory Patient.fromJson(Map<String, dynamic> json) {
    // Check if this is a nested structure from the API
    Map<String, dynamic> patientData = json;
    if (json.containsKey('patient') &&
        json['patient'] is Map<String, dynamic>) {
      print('🔍 Detected nested patient structure');
      patientData = json['patient'] as Map<String, dynamic>;
    }

    // Ensure we can handle various ways the id might be provided
    int id;
    if (patientData['id'] is int) {
      id = patientData['id'];
    } else if (patientData['id'] is String) {
      id = int.tryParse(patientData['id']) ?? 0;
    } else if (patientData['patientId'] is int) {
      id = patientData['patientId'];
    } else if (patientData['patientId'] is String) {
      id = int.tryParse(patientData['patientId']) ?? 0;
    } else {
      id = 0;
    }

    // Extract link ID and status if available
    int? linkId;
    String linkStatus = 'ACTIVE';
    bool patientVideoCallsEnabled = true;

    // First check if linkId and status are directly provided
    if (json.containsKey('linkId')) {
      if (json['linkId'] is int) {
        linkId = json['linkId'];
      } else if (json['linkId'] is String) {
        linkId = int.tryParse(json['linkId'].toString());
      }
    }

    if (json.containsKey('linkStatus')) {
      linkStatus = json['linkStatus']?.toString() ?? 'ACTIVE';
    }
    if (json.containsKey('patientVideoCallsEnabled')) {
      final raw = json['patientVideoCallsEnabled'];
      patientVideoCallsEnabled =
          raw is bool ? raw : raw?.toString().toLowerCase() != 'false';
    }

    // If linkId is still null, try to extract from link object
    if (json.containsKey('link') && json['link'] is Map<String, dynamic>) {
      final linkData = json['link'] as Map<String, dynamic>;
      print('🔍 Found link data: ${linkData.keys.toList()}');

      // Extract link ID
      if (linkData.containsKey('id')) {
        if (linkData['id'] is int) {
          linkId = linkData['id'];
          print('🔍 Using link.id for linkId: $linkId');
        } else if (linkData['id'] is String) {
          linkId = int.tryParse(linkData['id'].toString());
          print('🔍 Parsed link.id string to linkId: $linkId');
        }
      }
      if (linkData.containsKey('patientVideoCallsEnabled')) {
        final raw = linkData['patientVideoCallsEnabled'];
        patientVideoCallsEnabled =
            raw is bool ? raw : raw?.toString().toLowerCase() != 'false';
      }

      // Extract status if available
      if (linkData.containsKey('status')) {
        linkStatus = linkData['status']?.toString() ?? 'ACTIVE';
        print('🔍 Using link.status for linkStatus: $linkStatus');
      }
    }

    return Patient(
      id: id,
      firstName: patientData['firstName']?.toString() ?? '',
      lastName: patientData['lastName']?.toString() ?? '',
      email: patientData['email']?.toString() ?? '',
      phone: patientData['phone']?.toString() ?? '',
      dob: patientData['dob']?.toString() ?? '',
      relationship: patientData['relationship']?.toString() ??
          (json.containsKey('link') && json['link'] is Map<String, dynamic>
              ? json['link']['linkType']?.toString()
              : '') ??
          '',
      profileImageUrl: patientData['profileImageUrl']?.toString() ??
          (patientData.containsKey('user') &&
                  patientData['user'] is Map<String, dynamic>
              ? patientData['user']['profileImageUrl']?.toString()
              : ''),
      address: patientData['address'] != null
          ? Address.fromJson(Map<String, dynamic>.from(patientData['address']))
          : null,
      linkId: linkId,
      linkStatus: linkStatus,
      gender: patientData['gender']?.toString(),
      maNumber: patientData['maNumber']?.toString(),
      allergies: patientData['allergies'] ?? [],
      vitalConditions: patientData['latestVitals'] ?? {},
      likes: (patientData['likes'] ?? patientData['personalizationLikes'])
          ?.toString(),
      dislikes:
          (patientData['dislikes'] ?? patientData['personalizationDislikes'])
              ?.toString(),
      habits: (patientData['habits'] ?? patientData['personalizationHabits'])
          ?.toString(),
      phobias: (patientData['phobias'] ?? patientData['personalizationPhobias'])
          ?.toString(),
      preferredCommunicationMethod:
          (patientData['preferredCommunicationMethod'] ??
                  patientData['preferred_communication_method'])
              ?.toString(),
      patientVideoCallsEnabled: patientVideoCallsEnabled,
    );
  }

  Patient copyWith({
    int? id,
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
    String? dob,
    String? relationship,
    String? profileImageUrl,
    Address? address,
    int? linkId,
    String? linkStatus,
    String? gender,
    String? maNumber,
    List<dynamic>? allergies,
    Map<String, dynamic>? vitalConditions,
    String? likes,
    String? dislikes,
    String? habits,
    String? phobias,
    String? preferredCommunicationMethod,
    bool? patientVideoCallsEnabled,
  }) {
    return Patient(
      id: id ?? this.id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      dob: dob ?? this.dob,
      relationship: relationship ?? this.relationship,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      address: address ?? this.address,
      linkId: linkId ?? this.linkId,
      linkStatus: linkStatus ?? this.linkStatus,
      gender: gender ?? this.gender,
      maNumber: maNumber ?? this.maNumber,
      allergies: allergies ?? this.allergies,
      vitalConditions: vitalConditions ?? this.vitalConditions,
      likes: likes ?? this.likes,
      dislikes: dislikes ?? this.dislikes,
      habits: habits ?? this.habits,
      phobias: phobias ?? this.phobias,
      preferredCommunicationMethod:
          preferredCommunicationMethod ?? this.preferredCommunicationMethod,
      patientVideoCallsEnabled:
          patientVideoCallsEnabled ?? this.patientVideoCallsEnabled,
    );
  }

  // factory Patient.fromJson(Map<String, dynamic> json) {
  //   // Check if this is a nested structure from the API
  //   Map<String, dynamic> patientData = json;
  //   if (json.containsKey('patient') &&
  //       json['patient'] is Map<String, dynamic>) {
  //     print('🔍 Detected nested patient structure');
  //     patientData = json['patient'] as Map<String, dynamic>;
  //   }

  //   // Ensure we can handle various ways the id might be provided
  //   int id;
  //   if (patientData['id'] is int) {
  //     id = patientData['id'];
  //   } else if (patientData['id'] is String) {
  //     id = int.tryParse(patientData['id']) ?? 0;
  //   } else if (patientData['patientId'] is int) {
  //     // Try to use patientId if id is not available
  //     id = patientData['patientId'];
  //   } else if (patientData['patientId'] is String) {
  //     id = int.tryParse(patientData['patientId']) ?? 0;
  //   } else if (patientData.containsKey('user') &&
  //       patientData['user'] is Map<String, dynamic> &&
  //       patientData['user']['id'] is int) {
  //     // Try to use user.id if available
  //     id = patientData['user']['id'];
  //     print('🔧 Using user.id as fallback for patient ID: $id');
  //   } else {
  //     // Default value with debug log
  //     print(
  //       '⚠️ Warning: Patient object missing id and patientId fields: ${patientData.keys.toList()}',
  //     );
  //     id = 0;
  //   }

  //   // Extract link ID and status if available
  //   int? linkId;
  //   String linkStatus = 'ACTIVE';

  //   // First check if linkId and status are directly provided
  //   if (json.containsKey('linkId')) {
  //     if (json['linkId'] is int) {
  //       linkId = json['linkId'];
  //     } else if (json['linkId'] is String) {
  //       linkId = int.tryParse(json['linkId'].toString());
  //     }
  //   }

  //   if (json.containsKey('linkStatus')) {
  //     linkStatus = json['linkStatus']?.toString() ?? 'ACTIVE';
  //   }

  //   // If linkId is still null, try to extract from link object
  //   if (json.containsKey('link') && json['link'] is Map<String, dynamic>) {
  //     final linkData = json['link'] as Map<String, dynamic>;
  //     print('🔍 Found link data: ${linkData.keys.toList()}');

  //     // Extract link ID
  //     if (linkData.containsKey('id')) {
  //       if (linkData['id'] is int) {
  //         linkId = linkData['id'];
  //         print('🔍 Using link.id for linkId: $linkId');
  //       } else if (linkData['id'] is String) {
  //         linkId = int.tryParse(linkData['id'].toString());
  //         print('🔍 Parsed link.id string to linkId: $linkId');
  //       }
  //     }

  //     // Extract status if available
  //     if (linkData.containsKey('status')) {
  //       linkStatus = linkData['status']?.toString() ?? 'ACTIVE';
  //       print('🔍 Using link.status for linkStatus: $linkStatus');
  //     }
  //   }

  //   return Patient(
  //     id: id,
  //     firstName: patientData['firstName']?.toString() ?? '',
  //     lastName: patientData['lastName']?.toString() ?? '',
  //     email: patientData['email']?.toString() ?? '',
  //     phone: patientData['phone']?.toString() ?? '',
  //     dob: patientData['dob']?.toString() ?? '',
  //     relationship:
  //         patientData['relationship']?.toString() ??
  //         (json.containsKey('link') && json['link'] is Map<String, dynamic>
  //             ? json['link']['linkType']?.toString()
  //             : '') ??
  //         '',
  //     profileImageUrl:
  //         patientData['profileImageUrl']?.toString() ??
  //         (patientData.containsKey('user') &&
  //                 patientData['user'] is Map<String, dynamic>
  //             ? patientData['user']['profileImageUrl']?.toString()
  //             : ''),
  //     address: patientData['address'] != null
  //         ? Address.fromJson(Map<String, dynamic>.from(patientData['address']))
  //         : null,
  //     linkId: linkId,
  //     linkStatus: linkStatus,
  //     gender: patientData['gender']?.toString(),
  //     allergies: patientData['allergies'] ?? [],
  //     vitalConditions: patientData['latestVitals'] ?? {},
  //   );
  // }

  @override
  String toString() {
    return 'Patient{id: $id, firstName: $firstName, lastName: $lastName, email: $email, phone: $phone, dob: $dob, relationship: $relationship, maNumber: $maNumber, linkId: $linkId, linkStatus: $linkStatus, gender: $gender, allergies: $allergies, vitalConditions: $vitalConditions, patientVideoCallsEnabled: $patientVideoCallsEnabled}';
  }
}
