import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

/// Espace personnel de l'élève : les leçons qu'il choisit de garder pour les
/// relire plus tard, de n'importe quel niveau. Gardé sur le téléphone, comme
/// les favoris — pas besoin de règles Firestore pour cette fonctionnalité.
class SavedLessonsService {
  SavedLessonsService._();
  static final instance = SavedLessonsService._();

  /// Change à chaque ajout/retrait, pour que les écrans ouverts se mettent à jour.
  final ValueNotifier<int> revision = ValueNotifier(0);

  String get _key => 'saved_lessons_${AuthService.instance.profile.value?.uid ?? ''}';

  Future<List<String>> ids() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return [];
    }
  }

  Future<bool> isSaved(String lessonId) async => (await ids()).contains(lessonId);

  /// Ajoute ou retire la leçon de l'espace personnel ; renvoie le nouvel état
  /// (true = maintenant enregistrée).
  Future<bool> toggle(String lessonId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await ids();
    final wasSaved = list.remove(lessonId);
    if (!wasSaved) list.insert(0, lessonId); // la plus récente en premier
    await prefs.setString(_key, jsonEncode(list));
    revision.value++;
    return !wasSaved;
  }

  Future<void> remove(String lessonId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await ids();
    list.remove(lessonId);
    await prefs.setString(_key, jsonEncode(list));
    revision.value++;
  }
}
