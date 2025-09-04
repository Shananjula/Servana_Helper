import 'package:cloud_firestore/cloud_firestore.dart';

enum VerificationTier { none, bronze, silver, gold }

class HelpifyUser {
  final String id;
  final String? displayName;
  final String? email;
  final String? photoURL;

  /// Canonical number in profile
  final String? phone;

  final String? bio;
  final bool? isHelper;
  final bool isLive;

  final String? qualifications;
  final String? experience;
  final List<String> skills;
  final List<String> badges;
  final double? hourlyRate;
  final int trustScore;

  final List<String> portfolioImageUrls;
  final String? videoIntroUrl;

  final GeoPoint? workLocation;
  final String? workLocationAddress;

  final int ratingCount;
  final double averageRating;
  final int cancellationCount;
  final int commissionFreeTasksPosted;
  final int commissionFreeTasksCompleted;
  final int bonusTasksAvailable;

  final bool isProMember;
  final Timestamp? proMembershipExpiry;

  final double servCoinBalance;
  final double creditCoinBalance;
  final bool initialCreditGranted;

  final String verificationStatus;
  final VerificationTier verificationTier;

  final String? interviewStatus;
  final int? interviewScore;

  final int onboardingStep;
  final String? nicFrontUrl;
  final String? nicBackUrl;
  final String? policeClearanceUrl;
  final String? proofOfAddressUrl;

  final double profileCompletion;

  HelpifyUser({
    required this.id,
    this.displayName,
    this.email,
    this.photoURL,
    this.phone,
    this.bio,
    this.isHelper,
    this.isLive = false,
    this.qualifications,
    this.experience,
    this.skills = const [],
    this.badges = const [],
    this.hourlyRate,
    this.trustScore = 10,
    this.cancellationCount = 0,
    this.workLocation,
    this.workLocationAddress,
    this.ratingCount = 0,
    this.averageRating = 0.0,
    this.isProMember = false,
    this.proMembershipExpiry,
    this.commissionFreeTasksPosted = 0,
    this.commissionFreeTasksCompleted = 0,
    this.bonusTasksAvailable = 0,
    this.servCoinBalance = 0.0,
    this.creditCoinBalance = 0.0,
    this.initialCreditGranted = false,
    this.verificationStatus = 'not_verified',
    this.verificationTier = VerificationTier.none,
    this.onboardingStep = 0,
    this.nicFrontUrl,
    this.nicBackUrl,
    this.policeClearanceUrl,
    this.proofOfAddressUrl,
    this.portfolioImageUrls = const [],
    this.videoIntroUrl,
    this.interviewStatus,
    this.interviewScore,
  }) : profileCompletion = _calculateProfileCompletion(
    displayName: displayName,
    photoURL: photoURL,
    phone: phone,
    bio: bio,
    isHelper: isHelper,
    qualifications: qualifications,
    experience: experience,
    skills: skills,
    portfolioImageUrls: portfolioImageUrls,
  );

  /// UPDATED: prefer 'phone' but fall back to legacy 'phoneNumber'
  factory HelpifyUser.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data == null) {
      throw StateError('Missing data for userId: ${snapshot.id}');
    }
    return HelpifyUser(
      id: snapshot.id,
      displayName: data['displayName'] as String?,
      email: data['email'] as String?,
      photoURL: data['photoURL'] as String?,
      phone: (data['phone'] as String?) ?? (data['phoneNumber'] as String?), // <—
      bio: data['bio'] as String?,
      isHelper: data['isHelper'] as bool?,
      isLive: data['isLive'] as bool? ?? false,
      qualifications: data['qualifications'] as String?,
      experience: data['experience'] as String?,
      skills: List<String>.from(data['skills'] ?? []),
      badges: List<String>.from(data['badges'] ?? []),
      hourlyRate: (data['hourlyRate'] as num?)?.toDouble(),
      trustScore: (data['trustScore'] as num?)?.toInt() ?? 10,
      cancellationCount: data['cancellationCount'] as int? ?? 0,
      workLocation: data['workLocation'] as GeoPoint?,
      workLocationAddress: data['workLocationAddress'] as String?,
      ratingCount: (data['ratingCount'] as num?)?.toInt() ?? 0,
      averageRating: (data['averageRating'] as num?)?.toDouble() ?? 0.0,
      isProMember: data['isProMember'] as bool? ?? false,
      proMembershipExpiry: data['proMembershipExpiry'] as Timestamp?,
      commissionFreeTasksPosted: (data['commissionFreeTasksPosted'] as num?)?.toInt() ?? 0,
      commissionFreeTasksCompleted: (data['commissionFreeTasksCompleted'] as num?)?.toInt() ?? 0,
      bonusTasksAvailable: (data['bonusTasksAvailable'] as num?)?.toInt() ?? 0,
      servCoinBalance: (data['servCoinBalance'] as num?)?.toDouble() ?? 0.0,
      creditCoinBalance: (data['creditCoinBalance'] as num?)?.toDouble() ?? 0.0,
      initialCreditGranted: data['initialCreditGranted'] as bool? ?? false,
      verificationStatus: data['verificationStatus'] as String? ?? 'not_verified',
      verificationTier: VerificationTier.values.firstWhere(
            (e) => e.name == data['verificationTier'],
        orElse: () => VerificationTier.none,
      ),
      onboardingStep: data['onboardingStep'] as int? ?? 0,
      nicFrontUrl: data['nicFrontUrl'] as String?,
      nicBackUrl: data['nicBackUrl'] as String?,
      policeClearanceUrl: data['policeClearanceUrl'] as String?,
      proofOfAddressUrl: data['proofOfAddressUrl'] as String?,
      portfolioImageUrls: List<String>.from(data['portfolioImageUrls'] ?? []),
      videoIntroUrl: data['videoIntroUrl'] as String?,
      interviewStatus: data['interviewStatus'] as String?,
      interviewScore: data['interviewScore'] as int?,
    );
  }

  static double _calculateProfileCompletion({
    String? displayName,
    String? photoURL,
    String? phone,
    String? bio,
    bool? isHelper,
    String? qualifications,
    String? experience,
    List<String>? skills,
    List<String>? portfolioImageUrls,
  }) {
    int score = 0;
    int maxScore = 4;
    if (displayName != null && displayName.isNotEmpty) score++;
    if (photoURL != null && photoURL.isNotEmpty) score++;
    if (phone != null && phone.isNotEmpty) score++;
    if (bio != null && bio.isNotEmpty) score++;
    if (isHelper == true) {
      maxScore = 8;
      if (qualifications != null && qualifications.isNotEmpty) score++;
      if (experience != null && experience.isNotEmpty) score++;
      if (skills != null && skills.isNotEmpty) score++;
      if (portfolioImageUrls != null && portfolioImageUrls.isNotEmpty) score++;
    }
    if (maxScore == 0) return 0.0;
    return score / maxScore;
  }
}
