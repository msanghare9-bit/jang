import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/auth_service.dart';
import '../../services/match_service.dart';
import '../../theme.dart';
import '../../widgets/jang_ui.dart';
import 'match_screens.dart';

class XaritUser {
  final String uid;
  final String name;
  final String username;
  const XaritUser({required this.uid, required this.name, required this.username});
}

class XaritFriend {
  final String uid;
  final String name;
  final String requestId;
  const XaritFriend(this.uid, this.name, this.requestId);
}

class MatchInvitation {
  final String id, fromUid, fromName, matchId, code;
  const MatchInvitation(this.id, this.fromUid, this.fromName, this.matchId, this.code);
  factory MatchInvitation.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return MatchInvitation(doc.id, '${d['fromUid'] ?? ''}', '${d['fromName'] ?? 'Ami'}',
        '${d['matchId'] ?? ''}', '${d['code'] ?? ''}');
  }
}

/// Demandes Xarit, liste d'amis et invitations à rejoindre un match.
class XaritService {
  XaritService._();
  static final instance = XaritService._();
  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _requests => _db.collection('friendRequests');
  CollectionReference<Map<String, dynamic>> get _invites => _db.collection('matchInvitations');

  Future<XaritUser?> find(String rawUsername) async {
    final username = AuthService.normalizeUsername(rawUsername);
    if (username.isEmpty) return null;
    final doc = await _db.collection('usernames').doc(username).get();
    final d = doc.data();
    if (d == null) return null;
    return XaritUser(uid: '${d['uid'] ?? ''}', name: '${d['name'] ?? 'Élève'}', username: username);
  }

  Future<void> requestFriend(UserProfile me, XaritUser other) async {
    if (me.uid == other.uid) throw Exception('Tu ne peux pas t’ajouter toi-même.');
    final outId = '${me.uid}__${other.uid}';
    final prior = await Future.wait([
      _requests.where('fromUid', isEqualTo: me.uid).where('toUid', isEqualTo: other.uid).get(),
      _requests.where('fromUid', isEqualTo: other.uid).where('toUid', isEqualTo: me.uid).get(),
    ]);
    final rows = prior.expand((s) => s.docs).toList();
    if (rows.any((d) => d.data()['status'] == 'accepted')) {
      throw Exception('Cette personne est déjà dans tes Xarit.');
    }
    if (rows.any((d) => d.data()['status'] == 'pending')) {
      throw Exception('Une demande est déjà en attente.');
    }
    for (final doc in prior[0].docs) {
      await doc.reference.delete();
    }
    await _requests.doc(outId).set({
      'fromUid': me.uid, 'toUid': other.uid, 'fromName': me.publicName, 'toName': other.name,
      'status': 'pending', 'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> incoming(String uid) => _requests
      .where('toUid', isEqualTo: uid).where('status', isEqualTo: 'pending').snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> outgoing(String uid) => _requests
      .where('fromUid', isEqualTo: uid).where('status', isEqualTo: 'pending').snapshots();

  Future<List<XaritFriend>> friends(String uid) async {
    final rows = await Future.wait([
      _requests.where('fromUid', isEqualTo: uid).where('status', isEqualTo: 'accepted').get(),
      _requests.where('toUid', isEqualTo: uid).where('status', isEqualTo: 'accepted').get(),
    ]);
    final friends = <XaritFriend>[];
    for (final row in rows) {
      for (final doc in row.docs) {
        final d = doc.data();
        final otherUid = d['fromUid'] == uid ? '${d['toUid'] ?? ''}' : '${d['fromUid'] ?? ''}';
        final otherName = d['fromUid'] == uid ? '${d['toName'] ?? 'Ami'}' : '${d['fromName'] ?? 'Ami'}';
        friends.add(XaritFriend(otherUid, otherName, doc.id));
      }
    }
    friends.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return friends;
  }

  Future<void> decide(String id, {required bool accept}) =>
      _requests.doc(id).update({'status': accept ? 'accepted' : 'rejected'});

  Future<void> inviteToMatch(UserProfile from, String friendUid, LiveMatch match) async {
    final ref = _invites.doc();
    await ref.set({
      'fromUid': from.uid, 'toUid': friendUid, 'fromName': from.publicName,
      'matchId': match.id, 'code': match.code, 'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> invitations(String uid) => _invites
      .where('toUid', isEqualTo: uid).where('status', isEqualTo: 'pending').snapshots();

  Future<void> markInvitation(String id, {required bool accept}) =>
      _invites.doc(id).update({'status': accept ? 'accepted' : 'declined'});
}

class XaritScreen extends StatefulWidget {
  const XaritScreen({super.key});
  @override
  State<XaritScreen> createState() => _XaritScreenState();
}

class _XaritScreenState extends State<XaritScreen> {
  final _username = TextEditingController();
  XaritUser? _found;
  bool _searching = false;
  bool _busy = false;
  late Future<List<XaritFriend>> _friends;

  @override
  void initState() {
    super.initState();
    _friends = _loadFriends();
  }
  @override
  void dispose() { _username.dispose(); super.dispose(); }
  Future<List<XaritFriend>> _loadFriends() =>
      XaritService.instance.friends(AuthService.instance.profile.value?.uid ?? '');

  void _message(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _search() async {
    setState(() { _searching = true; _found = null; });
    try {
      final result = await XaritService.instance.find(_username.text);
      if (mounted) setState(() => _found = result);
    } catch (_) { _message('La recherche a échoué. Vérifie ta connexion.'); }
    finally { if (mounted) setState(() => _searching = false); }
  }

  Future<void> _request(XaritUser other) async {
    final me = AuthService.instance.profile.value;
    if (me == null) return;
    try {
      await XaritService.instance.requestFriend(me, other);
      _message('Demande envoyée à ${other.name}.');
    } catch (e) { _message(e.toString().replaceFirst('Exception: ', '')); }
  }

  Future<void> _challenge(XaritFriend friend) async {
    final me = AuthService.instance.profile.value;
    if (me == null) return;
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => MatchSetupScreen(friendUid: friend.uid, friendName: friend.name)));
    if (mounted) setState(() => _friends = _loadFriends());
  }

  Future<void> _joinInvitation(MatchInvitation invite) async {
    final p = AuthService.instance.profile.value;
    if (p == null) return;
    setState(() => _busy = true);
    try {
      final (match, error) = await MatchService.instance.joinByCode(invite.code, p);
      if (match == null) { _message(error); return; }
      await XaritService.instance.markInvitation(invite.id, accept: true);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => MatchRoomScreen(matchId: match.id)));
    } catch (_) { _message('Impossible de rejoindre ce match. Vérifie ta connexion.'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final me = AuthService.instance.profile.value;
    if (me == null) return const Scaffold(body: Center(child: Text('Connecte-toi pour voir tes Xarit.')));
    return Scaffold(
      appBar: AppBar(title: const Text('Mes Xarit')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Trouver un ami', style: titleStyle(20, weight: 800)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: _username, textInputAction: TextInputAction.search,
            decoration: const InputDecoration(labelText: 'Identifiant Jàng', prefixIcon: Icon(Icons.search)),
            onSubmitted: (_) => _search())),
          const SizedBox(width: 8),
          FilledButton(onPressed: _searching ? null : _search,
            child: _searching ? const SizedBox(width: 18,height:18,child:CircularProgressIndicator(strokeWidth:2)) : const Text('Chercher')),
        ]),
        if (_found != null) Card(child: ListTile(
          leading: const CircleAvatar(backgroundColor: JangColors.snGreen, child: Icon(Icons.person,color:Colors.white)),
          title: Text(_found!.name), subtitle: Text('@${_found!.username}'),
          trailing: IconButton(tooltip:'Ajouter', icon:const Icon(Icons.person_add_alt_1), onPressed:()=>_request(_found!)),
        )),
        const SizedBox(height: 18),
        Text('Demandes reçues', style: titleStyle(18, weight: 800)),
        StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
          stream:XaritService.instance.incoming(me.uid),
          builder:(context,snap){
            final docs=snap.data?.docs??[];
            if(docs.isEmpty) return const ListTile(title:Text('Aucune demande pour le moment.'));
            return Column(children:[for(final doc in docs) Card(child:ListTile(
              title:Text('${doc.data()['fromName']??'Un élève'}'),
              subtitle:const Text('Veut devenir ton Xarit'),
              trailing:Wrap(spacing:4,children:[
                IconButton(tooltip:'Refuser',onPressed:()=>XaritService.instance.decide(doc.id,accept:false),icon:const Icon(Icons.close)),
                IconButton(tooltip:'Accepter',onPressed:()async{await XaritService.instance.decide(doc.id,accept:true);if(mounted)setState(()=>_friends=_loadFriends());},icon:const Icon(Icons.check,color:JangColors.snGreen)),
              ]),
            ))]);
          }),
        const SizedBox(height: 12),
        Text('Invitations de match', style: titleStyle(18, weight: 800)),
        StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
          stream:XaritService.instance.invitations(me.uid),
          builder:(context,snap){
            final docs=snap.data?.docs??[];
            if(docs.isEmpty)return const ListTile(title:Text('Aucune invitation en attente.'));
            return Column(children:[for(final doc in docs) Builder(builder:(context){
              final invite=MatchInvitation.fromDoc(doc);
              return Card(child:ListTile(
                title:Text('${invite.fromName} te défie !'),
                subtitle:Text('Code du match : ${invite.code}'),
                trailing:FilledButton(onPressed:_busy?null:()=>_joinInvitation(invite),child:const Text('Rejoindre')),
              ));
            })]);
          }),
        const SizedBox(height: 12),
        Row(children:[
          Expanded(child:Text('Tes Xarit',style:titleStyle(18,weight:800))),
          IconButton(tooltip:'Actualiser',onPressed:()=>setState(()=>_friends=_loadFriends()),icon:const Icon(Icons.refresh)),
        ]),
        FutureBuilder<List<XaritFriend>>(future:_friends,builder:(context,snap){
          if(snap.hasError)return const ListTile(title:Text('Impossible de charger les Xarit.'));
          if(!snap.hasData)return const Padding(padding:EdgeInsets.all(16),child:Center(child:CircularProgressIndicator()));
          if(snap.data!.isEmpty)return const ListTile(title:Text('Tes amis apparaîtront ici après acceptation.'));
          return Column(children:[for(final friend in snap.data!) Card(child:ListTile(
            leading:const CircleAvatar(backgroundColor:JangColors.snGreen,child:Icon(Icons.people,color:Colors.white)),
            title:Text(friend.name),
            trailing:FilledButton.tonalIcon(onPressed:()=>_challenge(friend),icon:const Icon(Icons.sports_esports),label:const Text('Défier')),
          ))]);
        }),
        StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
          stream:XaritService.instance.outgoing(me.uid),
          builder:(context,snap){
            final docs=snap.data?.docs??[];
            if(docs.isEmpty)return const SizedBox.shrink();
            return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              const SizedBox(height:14),Text('Demandes envoyées',style:titleStyle(18,weight:800)),
              for(final doc in docs)ListTile(title:Text('${doc.data()['toName']??'Xarit'}'),subtitle:const Text('En attente de réponse')),
            ]);
          }),
      ]),
    );
  }
}