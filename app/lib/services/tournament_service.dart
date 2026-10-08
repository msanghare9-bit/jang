import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models.dart';
import 'match_service.dart';
import 'quiz_bank.dart';

class Tournament {
  final String id, title, hostUid, hostName, status, championUid;
  final int round, capacity;
  final List<BankQuestion> questions;
  const Tournament({
    required this.id, required this.title, required this.hostUid, required this.hostName,
    required this.status, required this.round, required this.capacity, required this.questions,
    this.championUid = '',
  });
  factory Tournament.fromDoc(DocumentSnapshot<Map<String,dynamic>> doc) {
    final d=doc.data()??{};
    return Tournament(
      id:doc.id,title:'${d['title']??'Tournoi'}',hostUid:'${d['hostUid']??''}',
      hostName:'${d['hostName']??'Organisateur'}',status:'${d['status']??'waiting'}',
      round:d['round'] is num?(d['round'] as num).toInt():0,
      capacity:d['capacity'] is num?(d['capacity'] as num).toInt():16,
      championUid:'${d['championUid']??''}',
      questions:[for(final q in (d['questions'] as List? ?? const [])) if(q is Map) BankQuestion.fromMap(q)],
    );
  }
}

class TournamentParticipant {
  final String uid, name;
  const TournamentParticipant(this.uid,this.name);
  factory TournamentParticipant.fromDoc(DocumentSnapshot<Map<String,dynamic>> doc) {
    final d=doc.data()??{};
    return TournamentParticipant(doc.id,'${d['name']??'Joueur'}');
  }
}

class TournamentGame {
  final String id, player1Uid, player1Name, player2Uid, player2Name, matchId, code, status, winnerUid, winnerName;
  final int order;
  const TournamentGame({
    required this.id,required this.player1Uid,required this.player1Name,required this.player2Uid,
    required this.player2Name,required this.matchId,required this.code,required this.status,
    required this.order,required this.winnerUid,required this.winnerName,
  });
  factory TournamentGame.fromDoc(DocumentSnapshot<Map<String,dynamic>> doc) {
    final d=doc.data()??{};
    return TournamentGame(
      id:doc.id,player1Uid:'${d['player1Uid']??''}',player1Name:'${d['player1Name']??''}',
      player2Uid:'${d['player2Uid']??''}',player2Name:'${d['player2Name']??''}',
      matchId:'${d['matchId']??''}',code:'${d['code']??''}',status:'${d['status']??'waiting'}',
      order:d['order'] is num?(d['order'] as num).toInt():0,
      winnerUid:'${d['winnerUid']??''}',winnerName:'${d['winnerName']??''}',
    );
  }
}

class TournamentService {
  TournamentService._();
  static final instance=TournamentService._();
  final _db=FirebaseFirestore.instance;
  CollectionReference<Map<String,dynamic>> get _col=>_db.collection('tournaments');

  Stream<QuerySnapshot<Map<String,dynamic>>> openTournaments()=>_col
      .where('status',whereIn:['waiting','running']).snapshots();

  Future<Tournament?> byId(String id) async {
    final d=await _col.doc(id).get();
    return d.exists?Tournament.fromDoc(d):null;
  }

  Stream<DocumentSnapshot<Map<String,dynamic>>> watch(String id)=>_col.doc(id).snapshots();

  Future<Tournament> create({
    required UserProfile host,
    required String title,
    required List<BankQuestion> questions,
    int capacity=16,
  }) async {
    final ref=_col.doc();
    await ref.set({
      'title':title.trim().isEmpty?'Tournoi de ${host.firstName}':title.trim(),
      'hostUid':host.uid,'hostName':host.publicName,'status':'waiting',
      'round':0,'capacity':capacity,'questions':[for(final q in questions) q.toMap()],
      'createdAt':FieldValue.serverTimestamp(),
    });
    await ref.collection('participants').doc(host.uid).set({
      'name':host.publicName,'joinedAt':FieldValue.serverTimestamp(),
    });
    return Tournament.fromDoc(await ref.get());
  }

  Stream<QuerySnapshot<Map<String,dynamic>>> participantStream(String id)=>_col.doc(id)
      .collection('participants').orderBy('joinedAt').snapshots();

  Future<List<TournamentParticipant>> participants(String id) async {
    final q=await _col.doc(id).collection('participants').orderBy('joinedAt').get();
    return q.docs.map(TournamentParticipant.fromDoc).toList();
  }

  Future<(bool,String)> join(String id,UserProfile p) async {
    final ref=_col.doc(id);
    final doc=await ref.get();
    if(!doc.exists)return(false,'Ce tournoi n’existe plus.');
    final t=Tournament.fromDoc(doc);
    if(t.status!='waiting')return(false,'Les inscriptions sont terminées.');
    final people=await participants(id);
    if(people.any((x)=>x.uid==p.uid))return(true,'');
    if(people.length>=t.capacity)return(false,'Le tournoi est complet.');
    await ref.collection('participants').doc(p.uid).set({
      'name':p.publicName,'joinedAt':FieldValue.serverTimestamp(),
    });
    return(true,'');
  }

  Stream<QuerySnapshot<Map<String,dynamic>>> currentGames(String id,int round)=>_col.doc(id)
      .collection('rounds').doc('$round').collection('games').orderBy('order').snapshots();

  Future<void> startOrAdvance(String id,UserProfile organizer) async {
    final ref=_col.doc(id);
    final doc=await ref.get();
    if(!doc.exists)throw Exception('Ce tournoi n’existe plus.');
    final t=Tournament.fromDoc(doc);
    if(t.hostUid!=organizer.uid)throw Exception('Seul l’organisateur peut faire avancer le tournoi.');
    if(t.status=='waiting') {
      final people=await participants(id);
      if(people.length<2)throw Exception('Il faut au moins deux joueurs inscrits.');
      people.shuffle(Random.secure());
      await _makeRound(t,organizer,1,people);
      await ref.update({'status':'running','round':1});
      return;
    }
    if(t.status!='running')throw Exception('Ce tournoi est déjà terminé.');
    final gamesRef=ref.collection('rounds').doc('${t.round}').collection('games');
    final snap=await gamesRef.orderBy('order').get();
    final winners=<TournamentParticipant>[];
    for(final gameDoc in snap.docs) {
      final game=TournamentGame.fromDoc(gameDoc);
      if(game.status=='bye') {
        winners.add(TournamentParticipant(game.winnerUid,game.winnerName));
        continue;
      }
      if(game.status=='done') {
        winners.add(TournamentParticipant(game.winnerUid,game.winnerName));
        continue;
      }
      final match=await MatchService.instance.getOnce(game.matchId);
      if(match==null || match.state!=LiveMatch.over) {
        throw Exception('Toutes les parties de cette manche doivent être terminées.');
      }
      final players=await MatchService.instance.playersOnce(game.matchId);
      if(players.isEmpty)throw Exception('Une partie ne contient aucun résultat.');
      final winner=players.first;
      await gameDoc.reference.update({'status':'done','winnerUid':winner.uid,'winnerName':winner.name});
      winners.add(TournamentParticipant(winner.uid,winner.name));
    }
    if(winners.length==1) {
      await ref.update({'status':'finished','championUid':winners.first.uid,'championName':winners.first.name});
      return;
    }
    if(winners.length<2)throw Exception('Impossible de déterminer les finalistes.');
    await _makeRound(t,organizer,t.round+1,winners);
    await ref.update({'round':t.round+1});
  }

  Future<void> _makeRound(Tournament t,UserProfile organizer,int round,List<TournamentParticipant> people) async {
    final roundRef=_col.doc(t.id).collection('rounds').doc('$round');
    await roundRef.set({'number':round,'createdAt':FieldValue.serverTimestamp()});
    final games=roundRef.collection('games');
    for(var i=0;i<people.length;i+=2) {
      final p1=people[i];
      if(i+1>=people.length) {
        await games.doc('game_${i.toString().padLeft(2,'0')}').set({
          'order':i,'player1Uid':p1.uid,'player1Name':p1.name,'player2Uid':'','player2Name':'',
          'matchId':'','code':'','status':'bye','winnerUid':p1.uid,'winnerName':p1.name,
        });
        continue;
      }
      final p2=people[i+1];
      final match=await MatchService.instance.create(
        host:organizer,questions:t.questions,hostPlays:false,seconds:20,
        domain:'tournoi',level:'',title:'Tournoi · Manche $round',tournamentId:t.id,
      );
      await games.doc('game_${i.toString().padLeft(2,'0')}').set({
        'order':i,'player1Uid':p1.uid,'player1Name':p1.name,'player2Uid':p2.uid,'player2Name':p2.name,
        'matchId':match.id,'code':match.code,'status':'waiting','winnerUid':'','winnerName':'',
      });
    }
  }
}
