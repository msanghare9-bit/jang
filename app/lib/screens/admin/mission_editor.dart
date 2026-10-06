import 'package:flutter/material.dart';

/// Éditeur d'une mission (format de contenus/missions.json).
/// Sert pour les missions officielles (admin) et les missions des profs.
class MissionEditorScreen extends StatefulWidget {
  /// La mission à modifier (une copie est modifiée ; l'original ne change pas).
  final Map<String, dynamic> initial;

  /// Titre de l'écran.
  final String title;

  /// Appelé avec la mission modifiée quand on appuie sur « Enregistrer ».
  final Future<void> Function(Map<String, dynamic> mission) onSave;
  const MissionEditorScreen({super.key, required this.initial, required this.onSave, this.title = 'Modifier la mission'});

  /// Une mission vide, prête à remplir.
  static Map<String, dynamic> blank(String id) => {
        'id': id,
        'titre': '',
        'jesais': '',
        'expressions': <String>[],
        'mots': {'consigne': 'Quels mots vont avec l\'image ?', 'fond': 'classe', 'objets': <String>[], 'liste': <Map>[]},
        'scene': {'fond': 'classe', 'persos': ['awa', 'modou', 'gainde'], 'repliques': <Map>[], 'gainde': ''},
        'questions': <Map>[],
        'marches': <Map>[],
        'pourdevrai': <Map>[],
        'carnet': <String>[],
      };

  @override
  State<MissionEditorScreen> createState() => _MissionEditorScreenState();
}

class _MissionEditorScreenState extends State<MissionEditorScreen> {
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(widget.title)));
}
