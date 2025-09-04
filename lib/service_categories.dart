
// lib/service_categories.dart
// Massive category list, split by mode. Keep ids stable.

class ServiceCategory {
  final String id;
  final String label;
  /// 'online' | 'physical' | 'both'
  final String mode;
  const ServiceCategory({required this.id, required this.label, required this.mode});
}

const List<ServiceCategory> kOnlineCategories = [
  ServiceCategory(id: 'online_tutoring_math', label: 'Online Tutoring – Mathematics', mode: 'online'),
  ServiceCategory(id: 'online_tutoring_english', label: 'Online Tutoring – English', mode: 'online'),
  ServiceCategory(id: 'online_tutoring_science', label: 'Online Tutoring – Science', mode: 'online'),
  ServiceCategory(id: 'online_graphic_design', label: 'Graphic Design', mode: 'online'),
  ServiceCategory(id: 'online_logo_branding', label: 'Logo & Branding', mode: 'online'),
  ServiceCategory(id: 'online_uiux', label: 'UI/UX Design', mode: 'online'),
  ServiceCategory(id: 'online_web_dev', label: 'Web Development', mode: 'online'),
  ServiceCategory(id: 'online_mobile_app', label: 'Mobile App (Remote)', mode: 'online'),
  ServiceCategory(id: 'online_copywriting', label: 'Copywriting', mode: 'online'),
  ServiceCategory(id: 'online_translation', label: 'Translation', mode: 'online'),
  ServiceCategory(id: 'online_video_editing', label: 'Video Editing', mode: 'online'),
  ServiceCategory(id: 'online_music_editing', label: 'Audio/Music Editing', mode: 'online'),
  ServiceCategory(id: 'online_social_media', label: 'Social Media Management', mode: 'online'),
  ServiceCategory(id: 'online_seo', label: 'SEO', mode: 'online'),
  ServiceCategory(id: 'online_data_entry', label: 'Data Entry', mode: 'online'),
  ServiceCategory(id: 'online_virtual_assistant', label: 'Virtual Assistant', mode: 'online'),
  ServiceCategory(id: 'online_accounting', label: 'Accounting (Remote)', mode: 'online'),
  ServiceCategory(id: 'online_legal_docs', label: 'Legal Document Prep (Remote)', mode: 'online'),
  ServiceCategory(id: 'online_marketing', label: 'Digital Marketing', mode: 'online'),
  ServiceCategory(id: 'online_illustration', label: 'Illustration', mode: 'online'),
  ServiceCategory(id: 'online_3d', label: '3D Modeling/Rendering', mode: 'online'),
  ServiceCategory(id: 'online_cad', label: 'CAD Drafting', mode: 'online'),
  ServiceCategory(id: 'online_cv_resume', label: 'CV/Resume Writing', mode: 'online'),
  ServiceCategory(id: 'online_research', label: 'Research Assistance', mode: 'online'),
  ServiceCategory(id: 'online_excel', label: 'Excel/Sheets Expert', mode: 'online'),
  ServiceCategory(id: 'online_ppt', label: 'Presentation Design', mode: 'online'),
  ServiceCategory(id: 'online_ai_prompting', label: 'AI Prompt Engineering', mode: 'online'),
  ServiceCategory(id: 'online_ai_chatops', label: 'AI Chat Ops', mode: 'online'),
  ServiceCategory(id: 'online_coding_help', label: 'Coding Help (Remote)', mode: 'online'),
  ServiceCategory(id: 'online_math_solver', label: 'Math Problem Solving', mode: 'online'),
  ServiceCategory(id: 'online_language_lessons', label: 'Language Lessons', mode: 'online'),
  ServiceCategory(id: 'online_exam_prep', label: 'Exam Prep/Coaching', mode: 'online'),
];

const List<ServiceCategory> kPhysicalCategories = [
  ServiceCategory(id: 'physical_plumbing', label: 'Plumbing', mode: 'physical'),
  ServiceCategory(id: 'physical_electrical', label: 'Electrical Repair', mode: 'physical'),
  ServiceCategory(id: 'physical_carpentry', label: 'Carpentry', mode: 'physical'),
  ServiceCategory(id: 'physical_masonry', label: 'Masonry', mode: 'physical'),
  ServiceCategory(id: 'physical_painting', label: 'Painting', mode: 'physical'),
  ServiceCategory(id: 'physical_cleaning', label: 'House Cleaning', mode: 'physical'),
  ServiceCategory(id: 'physical_deep_clean', label: 'Deep Cleaning', mode: 'physical'),
  ServiceCategory(id: 'physical_lawn', label: 'Gardening/Lawn Care', mode: 'physical'),
  ServiceCategory(id: 'physical_ac_service', label: 'AC Service/Repair', mode: 'physical'),
  ServiceCategory(id: 'physical_refrigeration', label: 'Refrigeration Repair', mode: 'physical'),
  ServiceCategory(id: 'physical_tv_install', label: 'TV/Appliance Installation', mode: 'physical'),
  ServiceCategory(id: 'physical_locksmith', label: 'Locksmith', mode: 'physical'),
  ServiceCategory(id: 'physical_pest_control', label: 'Pest Control', mode: 'physical'),
  ServiceCategory(id: 'physical_handyman', label: 'Handyman', mode: 'physical'),
  ServiceCategory(id: 'physical_moving', label: 'Moving & Packing', mode: 'physical'),
  ServiceCategory(id: 'physical_driver', label: 'Driver/Chauffeur', mode: 'physical'),
  ServiceCategory(id: 'physical_cook', label: 'Home Cooking', mode: 'physical'),
  ServiceCategory(id: 'physical_babysitting', label: 'Babysitting', mode: 'physical'),
  ServiceCategory(id: 'physical_elder_care', label: 'Elder Care', mode: 'physical'),
  ServiceCategory(id: 'physical_pet_care', label: 'Pet Care', mode: 'physical'),
  ServiceCategory(id: 'physical_beauty', label: 'Beauty & Makeup', mode: 'physical'),
  ServiceCategory(id: 'physical_tailor', label: 'Tailoring/Alterations', mode: 'physical'),
  ServiceCategory(id: 'physical_event_setup', label: 'Event Setup', mode: 'physical'),
  ServiceCategory(id: 'physical_photography', label: 'Photography (On-site)', mode: 'physical'),
  ServiceCategory(id: 'physical_videography', label: 'Videography (On-site)', mode: 'physical'),
  ServiceCategory(id: 'physical_tutor_home', label: 'Home Tutoring', mode: 'physical'),
  ServiceCategory(id: 'physical_personal_trainer', label: 'Personal Trainer', mode: 'physical'),
  ServiceCategory(id: 'physical_mechanic', label: 'Auto Mechanic', mode: 'physical'),
  ServiceCategory(id: 'physical_bike_repair', label: 'Bike Repair', mode: 'physical'),
  ServiceCategory(id: 'physical_it_setup', label: 'Home IT Setup', mode: 'physical'),
  ServiceCategory(id: 'physical_inverter', label: 'Inverter/Solar Install', mode: 'physical'),
  ServiceCategory(id: 'physical_security', label: 'Security/Guard', mode: 'physical'),
  ServiceCategory(id: 'physical_plastering', label: 'Plastering', mode: 'physical'),
  ServiceCategory(id: 'physical_tiling', label: 'Tiling', mode: 'physical'),
  ServiceCategory(id: 'physical_roofing', label: 'Roofing', mode: 'physical'),
  ServiceCategory(id: 'physical_waterproofing', label: 'Waterproofing', mode: 'physical'),
  ServiceCategory(id: 'physical_curtain_blinds', label: 'Curtains/Blinds', mode: 'physical'),
  ServiceCategory(id: 'physical_glass', label: 'Glass/Aluminium Works', mode: 'physical'),
  ServiceCategory(id: 'physical_welding', label: 'Welding', mode: 'physical'),
  ServiceCategory(id: 'physical_pool', label: 'Pool Cleaning', mode: 'physical'),
  ServiceCategory(id: 'physical_cctv', label: 'CCTV Install', mode: 'physical'),
  ServiceCategory(id: 'physical_sanitization', label: 'Sanitization', mode: 'physical'),
];

List<ServiceCategory> allCategoriesForMode(String mode) {
  if (mode == 'online') return kOnlineCategories;
  if (mode == 'physical') return kPhysicalCategories;
  return [...kOnlineCategories, ...kPhysicalCategories];
}
