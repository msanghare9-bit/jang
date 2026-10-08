import 'dart:math';

/// Messages bienveillants : on félicite les réussites et on encourage après une erreur.
/// Jamais de mots comme « nul », « mauvais » ou « échec ».
class Cheer {
  Cheer._();
  static final _rand = Random();

  static String _pick(List<String> list) => list[_rand.nextInt(list.length)];

  /// Après une bonne réponse.
  static String right() => _pick(const [
        'Bravo !',
        'Excellent, tu as compris !',
        'Super, continue comme ça !',
        'Bien joué !',
        'Parfait !',
        'Oui, c\'est ça !',
      ]);

  /// Après une réponse à revoir.
  static String wrong() => _pick(const [
        'Pas encore, mais tu progresses. Regarde l\'explication.',
        'Ce n\'est pas grave, c\'est en se trompant qu\'on apprend.',
        'Presque ! Lis l\'explication, tu vas comprendre.',
        'Pas tout à fait. Courage, la prochaine sera la bonne.',
      ]);

  /// Après plusieurs erreurs de suite.
  static String streakWrong() => _pick(const [
        'Prends ton temps. Relis la leçon, tu vas y arriver.',
        'Une pause, une relecture, et tu repartiras plus fort.',
        'Chaque erreur t’apprend quelque chose. On continue doucement.',
        'Respire, relis la consigne, puis essaie encore.',
      ]);

  /// Paroles propres à chaque personnage, choisies au hasard pour éviter les répétitions.
  static String fromCharacter(String character, bool correct) {
    final lines = switch ((character, correct)) {
      ('gainde', true) => const ['Miaou… euh, bravo ! Tu as trouvé !', 'Ma crinière frétille : bonne réponse !', 'Waaw, tu as été plus rapide que moi !'],
      ('gainde', false) => const ['Oups, je me suis trompé aussi. On regarde la bonne réponse ?', 'Même un lionceau apprend en essayant !', 'Pas grave, on rugit et on retente !'],
      ('modou', true) => const ['Bien joué, ta réponse est juste.', 'Tu avances bien, continue comme ça.', 'Yes, tu as trouvé la bonne réponse !'],
      ('modou', false) => const ['On reprend tranquillement, tu vas comprendre.', 'Pas cette fois, mais tu progresses.', 'Regarde l’indice et essaie encore.'],
      ('awa', true) => const ['Excellent ! Tu as bien réfléchi.', 'Bravo, ta persévérance paie !', 'Tu as trouvé, je suis fière de toi !'],
      ('awa', false) => const ['Tu peux y arriver, relis bien la question.', 'Une erreur ne t’empêche pas de réussir.', 'Courage, on apprend pas à pas.'],
      ('kocc', true) => const ['Belle démonstration ! Explique-moi ton raisonnement.', 'Tu as trouvé : quelle bonne stratégie !', 'Excellent travail, jeune savant.'],
      ('kocc', false) => const ['Quel indice pourrait t’aider à trouver ?', 'Reprenons la question étape par étape.', 'Ta démarche compte ; essayons une autre piste.'],
      _ => correct ? const ['Bravo !'] : const ['Continue, tu progresses.'],
    };
    return _pick(lines);
  }

  /// Message de fin de QCM selon la note. [improved] : meilleure note que la fois précédente.
  static String quizEnd(int score, int total, {bool improved = false}) {
    final ratio = total == 0 ? 0.0 : score / total;
    final String base;
    if (ratio >= 1) {
      base = _pick(const [
        'Tout juste ! Félicitations, tu maîtrises cette leçon.',
        'Sans faute ! Tu peux être fier de toi.',
      ]);
    } else if (ratio >= 0.8) {
      base = _pick(const [
        'Très beau résultat, bravo !',
        'Excellent travail, tu y es presque !',
      ]);
    } else if (ratio >= 0.5) {
      base = _pick(const [
        'Beau travail, encore un petit effort !',
        'Tu es sur la bonne voie. Lis les explications et réessaie.',
      ]);
    } else {
      base = _pick(const [
        'Chaque essai te fait progresser. Revois la leçon et réessaie, tu feras mieux.',
        'Ne te décourage pas : relis la leçon, regarde les vidéos, puis recommence. Tu vas y arriver.',
      ]);
    }
    return improved ? 'Tu as fait mieux que la dernière fois ! $base' : base;
  }

  /// Fin d'une séance de flashcards.
  static String flashcardsEnd(int knew, int total) {
    if (total == 0) return 'Bravo pour ta séance !';
    if (knew == total) return 'Tu savais tout, bravo ! Ta mémoire est en forme.';
    if (knew * 2 >= total) {
      return 'Tu savais $knew carte${knew > 1 ? 's' : ''} sur $total, bravo ! Les autres reviendront bientôt.';
    }
    return 'Tu savais $knew carte${knew > 1 ? 's' : ''} sur $total. '
        'C\'est normal au début : à force de les revoir, tu les retiendras.';
  }

  /// Message d'accueil.
  static String welcome(String firstName, int streak) {
    final name = firstName.isEmpty ? '' : ', $firstName';
    if (streak >= 7) return '$streak jours de suite$name, bravo pour ta régularité !';
    if (streak >= 2) return '$streak jours de suite$name, continue comme ça !';
    return _pick([
      'Content de te revoir$name !',
      'Prêt à apprendre$name ?',
      'Un peu chaque jour, et tu vas loin$name !',
    ]);
  }
}
