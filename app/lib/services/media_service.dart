import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme.dart';

/// Photos des leçons, des QCM et des cartes de révision.
///
/// Chaque photo est réduite (1024 px, JPEG) puis enregistrée dans Firestore (media/{id}).
/// Elle n'est téléchargée que quand un élève l'affiche, puis reste sur le téléphone.
class MediaService {
  MediaService._();
  static final instance = MediaService._();

  final _db = FirebaseFirestore.instance;
  final _memory = <String, Uint8List>{};
  final _picker = ImagePicker();

  /// Demande « Galerie » ou « Appareil photo », réduit la photo et l'enregistre.
  /// Renvoie l'identifiant de la photo, ou null si annulé.
  Future<String?> pickAndUpload(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text('Ajouter une photo', style: titleStyle(20)),
          ),
          ListTile(
            minVerticalPadding: 14,
            leading: const Icon(Icons.photo_library_outlined, color: JangColors.primary),
            title: const Text('Choisir dans la galerie'),
            onTap: () => Navigator.pop(c, ImageSource.gallery),
          ),
          ListTile(
            minVerticalPadding: 14,
            leading: const Icon(Icons.photo_camera_outlined, color: JangColors.primary),
            title: const Text('Prendre une photo'),
            onTap: () => Navigator.pop(c, ImageSource.camera),
          ),
          const SizedBox(height: 10),
        ]),
      ),
    );
    if (source == null) return null;
    XFile? file;
    try {
      file = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 70,
      );
    } catch (e) {
      debugPrint('Photo impossible : $e');
      return null;
    }
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (bytes.length > 900000) return null; // trop lourde pour être enregistrée
    final id = _db.collection('media').doc().id;
    _memory[id] = bytes;
    await _db.collection('media').doc(id).set({
      'data': base64Encode(bytes),
      'size': bytes.length,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return id;
  }

  /// Photo [id] : d'abord la mémoire, puis le téléphone, puis internet.
  Future<Uint8List?> load(String id) async {
    final m = _memory[id];
    if (m != null) return m;
    final ref = _db.collection('media').doc(id);
    DocumentSnapshot<Map<String, dynamic>>? d;
    try {
      d = await ref.get(const GetOptions(source: Source.cache));
    } catch (_) {}
    if (d == null || !d.exists) {
      try {
        d = await ref.get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 25));
      } catch (_) {
        return null;
      }
    }
    final data = d?.data()?['data'];
    if (data is! String) return null;
    try {
      final bytes = base64Decode(data);
      _memory[id] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }
}

/// Affiche la photo [id] (avec un emplacement gris pendant le chargement).
class MediaImage extends StatefulWidget {
  final String id;
  final double? height;
  final BoxFit fit;
  final double radius;
  const MediaImage(this.id, {super.key, this.height, this.fit = BoxFit.cover, this.radius = 16});

  @override
  State<MediaImage> createState() => _MediaImageState();
}

class _MediaImageState extends State<MediaImage> {
  late Future<Uint8List?> _future = MediaService.instance.load(widget.id);

  @override
  void didUpdateWidget(MediaImage old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) _future = MediaService.instance.load(widget.id);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: FutureBuilder<Uint8List?>(
        future: _future,
        builder: (context, snap) {
          final bytes = snap.data;
          if (bytes != null) {
            return Image.memory(bytes,
                height: widget.height, width: double.infinity, fit: widget.fit, gaplessPlayback: true);
          }
          final waiting = snap.connectionState != ConnectionState.done;
          return Container(
            height: widget.height ?? 160,
            width: double.infinity,
            color: const Color(0xFFF7F7F7),
            alignment: Alignment.center,
            child: waiting
                ? const SizedBox(
                    width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.wifi_off_rounded, color: JangColors.textSecondary),
                    const SizedBox(height: 4),
                    Text('Photo visible avec internet',
                        style: Theme.of(context).textTheme.bodySmall),
                    TextButton(
                      onPressed: () =>
                          setState(() => _future = MediaService.instance.load(widget.id)),
                      child: const Text('Réessayer'),
                    ),
                  ]),
          );
        },
      ),
    );
  }
}
