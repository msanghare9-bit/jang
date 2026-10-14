import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models.dart';
import '../../services/auth_service.dart';
import '../../services/match_service.dart';
import '../../services/quiz_bank.dart';
import '../../services/tournament_service.dart';
import '../../theme.dart';
import '../../widgets/jang_ui.dart';
import 'match_screens.dart';

class TournamentHomeScreen extends StatelessWidget {
  const TournamentHomeScreen({super.key});

  Future<void> _create(BuildContext context) async {
    final form=await showDialog<_TournamentForm>(context:context,builder:(_)=>const _TournamentSetupDialog());
    if(form==null||!context.mounted)return;
    final host=AuthService.instance.profile.value;
    if(host==null)return;
    try{
      final qs=await QuizBank.instance.drawDomains(form.domains,form.level,form.count);
      if(!context.mounted)return;
      if(qs.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Aucune question disponible pour ces choix.')));return;}
      final t=await TournamentService.instance.create(host:host,title:form.title,questions:qs,level:form.level,domains:form.domains);
      if(context.mounted)await Navigator.push(context,MaterialPageRoute(builder:(_)=>TournamentDetailScreen(tournamentId:t.id)));
    }catch(_){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Impossible de créer le tournoi.')));}
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Tournois')),
    floatingActionButton:FloatingActionButton.extended(
      onPressed:()=>_create(context),backgroundColor:JangColors.snGreen,foregroundColor:Colors.white,
      icon:const Icon(Icons.add),label:const Text('Créer un tournoi')),
    body:StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
      stream:TournamentService.instance.openTournaments(),
      builder:(context,snap){
        if(snap.hasError)return const Center(child:Text('Impossible de charger les tournois.'));
        if(!snap.hasData)return const Center(child:CircularProgressIndicator());
        // Les tournois de classe se trouvent dans l'espace de la classe.
        final docs=snap.data!.docs.where((d)=>'${d.data()['classId']??''}'.isEmpty).toList();
        if(docs.isEmpty)return const Center(child:Padding(padding:EdgeInsets.all(28),child:Text('Aucun tournoi en cours. Crée le premier !',textAlign:TextAlign.center)));
        return ListView(padding:const EdgeInsets.fromLTRB(16,12,16,96),children:[
          const Text('Rejoins un tableau à élimination ou ouvre un match comme spectateur.'),
          const SizedBox(height:12),
          for(final doc in docs)Builder(builder:(context){
            final t=Tournament.fromDoc(doc);
            return Card(child:ListTile(
              leading:CircleAvatar(backgroundColor:JangColors.snGreen,child:Icon(t.status=='finished'?Icons.emoji_events:Icons.account_tree_outlined,color:Colors.white)),
              title:Text(t.title),
              subtitle:Text(t.status=='waiting'?'Inscriptions ouvertes · ${t.hostName}':t.status=='finished'?'Champion : ${t.championName}':'Manche ${t.round} · ${t.hostName}'),
              trailing:const Icon(Icons.chevron_right),
              onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>TournamentDetailScreen(tournamentId:t.id))),
            ));
          }),
        ]);
      },
    ),
  );
}

class _TournamentForm{final String title,level;final List<String> domains;final int count;const _TournamentForm(this.title,this.level,this.domains,this.count);}
class _TournamentSetupDialog extends StatefulWidget{final String? className;const _TournamentSetupDialog({this.className});@override State<_TournamentSetupDialog> createState()=>_TournamentSetupDialogState();}
class _TournamentSetupDialogState extends State<_TournamentSetupDialog>{
  final _title=TextEditingController();final _domains=<String>{'vocabulaire'};String _level='debutant';int _count=10;
  @override void dispose(){_title.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>AlertDialog(
    title:Text(widget.className==null?'Créer un tournoi':'Tournoi pour ${widget.className}'),
    content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      TextField(controller:_title,textCapitalization:TextCapitalization.sentences,decoration:const InputDecoration(labelText:'Nom du tournoi')),
      const SizedBox(height:12),const Text('Domaines'),
      Wrap(spacing:6,children:[for(final d in QuizBank.domains)FilterChip(
        label:Text(QuizBank.domainLabel(d)),selected:_domains.contains(d),
        onSelected:(v)=>setState(()=>v?_domains.add(d):_domains.remove(d)))]),
      const SizedBox(height:10),const Text('Niveau'),
      SegmentedButton<String>(showSelectedIcon:false,
        segments:[for(final l in QuizBank.levels)ButtonSegment(value:l,label:Text(QuizBank.levelLabel(l)))],
        selected:{_level},onSelectionChanged:(s)=>setState(()=>_level=s.first)),
      const SizedBox(height:10),const Text('Questions par match'),
      SegmentedButton<int>(showSelectedIcon:false,
        segments:const[ButtonSegment(value:5,label:Text('5')),ButtonSegment(value:10,label:Text('10')),ButtonSegment(value:15,label:Text('15'))],
        selected:{_count},onSelectionChanged:(s)=>setState(()=>_count=s.first)),
      const SizedBox(height:8),Text(widget.className==null?'Jusqu’à 16 joueurs; $_count questions par match.':'Seuls les élèves de la classe peuvent s’inscrire; $_count questions par match.',style:const TextStyle(fontSize:12)),
    ])),
    actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Annuler')),
      FilledButton(onPressed:_domains.isEmpty?null:()=>Navigator.pop(context,_TournamentForm(_title.text.trim(),_level,_domains.toList(),_count)),child:const Text('Créer'))],
  );
}

class _TournamentData{final Tournament tournament;final List<TournamentParticipant> people;final List<TournamentGame> games;const _TournamentData(this.tournament,this.people,this.games);}
class TournamentDetailScreen extends StatefulWidget{final String tournamentId;const TournamentDetailScreen({super.key,required this.tournamentId});@override State<TournamentDetailScreen> createState()=>_TournamentDetailScreenState();}
class _TournamentDetailScreenState extends State<TournamentDetailScreen>{
  late Future<_TournamentData?> _future=_load();bool _busy=false;
  Future<_TournamentData?> _load()async{
    final s=TournamentService.instance;final t=await s.byId(widget.tournamentId);if(t==null)return null;
    final people=await s.participants(t.id);
    final games=t.round==0?const <TournamentGame>[]:(await s.currentGames(t.id,t.round).first).docs.map(TournamentGame.fromDoc).toList();
    return _TournamentData(t,people,games);
  }
  void _reload(){if(mounted)setState(()=>_future=_load());}
  void _msg(String m){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(m)));}
  Future<void> _join(Tournament t)async{
    final p=AuthService.instance.profile.value;if(p==null)return;setState(()=>_busy=true);
    try{final(ok,msg)=await TournamentService.instance.join(t.id,p);if(!ok){_msg(msg);return;}_msg('Inscription confirmée.');_reload();}
    catch(_){_msg('Impossible de rejoindre le tournoi.');}finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _advance(Tournament t)async{
    final p=AuthService.instance.profile.value;if(p==null)return;setState(()=>_busy=true);
    try{await TournamentService.instance.startOrAdvance(t.id,p);_msg(t.status=='waiting'?'Le tableau est lancé !':'Le tableau est mis à jour.');_reload();}
    catch(e){_msg(e.toString().replaceFirst('Exception: ',''));}finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _openGame(Tournament t,TournamentGame g)async{
    final p=AuthService.instance.profile.value;if(p==null)return;setState(()=>_busy=true);
    try{
      final isPlayer=p.uid==g.player1Uid||p.uid==g.player2Uid;
      if(isPlayer){
        final (match,error)=await MatchService.instance.joinByCode(g.code,p);if(match==null){_msg(error);return;}
        if(!mounted)return;await Navigator.push(context,MaterialPageRoute(builder:(_)=>MatchRoomScreen(matchId:match.id)));
      }else if(p.uid==t.hostUid){
        if(!mounted)return;await Navigator.push(context,MaterialPageRoute(builder:(_)=>MatchRoomScreen(matchId:g.matchId)));
      }else{
        await MatchService.instance.requestTournamentObservation(g.matchId,p);
        if(!mounted)return;await Navigator.push(context,MaterialPageRoute(builder:(_)=>MatchRoomScreen(matchId:g.matchId,spectator:true,tournamentFree:true)));
      }
      _reload();
    }catch(e){_msg(e.toString().replaceFirst('Exception: ',''));}finally{if(mounted)setState(()=>_busy=false);}
  }
  @override Widget build(BuildContext context){
    final uid=AuthService.instance.profile.value?.uid??'';
    return Scaffold(appBar:AppBar(title:const Text('Tableau du tournoi')),body:FutureBuilder<_TournamentData?>(
      future:_future,builder:(context,snap){
        if(snap.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
        if(snap.hasError)return Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
          const Text('Impossible de charger ce tournoi.'),const SizedBox(height:10),
          FilledButton(onPressed:_reload,child:const Text('Réessayer'))]));
        final data=snap.data;if(data==null)return const Center(child:Text('Tournoi introuvable.'));
        final t=data.tournament;final host=t.hostUid==uid;final joined=data.people.any((p)=>p.uid==uid);
        return RefreshIndicator(onRefresh:()async=>_reload(),child:ListView(padding:const EdgeInsets.fromLTRB(16,12,16,30),children:[
          Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:JangColors.snGreen,borderRadius:BorderRadius.circular(18)),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(t.title,style:titleStyle(23,color:Colors.white,weight:800)),
              const SizedBox(height:5),
              Text(t.status=='waiting'?'Inscriptions ouvertes':'Manche ${t.round}',style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w700)),
              if(t.status=='finished')Text('Champion : ${data.people.where((p)=>p.uid==t.championUid).firstOrNull?.name??'Félicitations !'}',style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w800)),
              Text(t.isClass?'Organisé par ${t.hostName} · classe ${t.className}':'Organisé par ${t.hostName} · jusqu’à ${t.capacity} joueurs',style:const TextStyle(color:Colors.white)),
              Text('${t.questions.length} questions par match · pas de Ndimbal en tournoi',style:const TextStyle(color:Colors.white,fontSize:12)),
            ])),
          const SizedBox(height:14),
          Row(children:[Expanded(child:Text(t.isClass?'Joueurs (${data.people.length})':'Joueurs (${data.people.length}/${t.capacity})',style:titleStyle(19,weight:800))),
            if(t.status=='waiting'&&!joined&&!(t.isClass&&host)&&data.people.length<t.capacity)FilledButton(onPressed:_busy?null:()=>_join(t),child:const Text('Rejoindre'))]),
          const SizedBox(height:6),
          for(final p in data.people)ListTile(dense:true,leading:const Icon(Icons.person_outline,color:JangColors.snGreen),title:Text(p.name),
            trailing:p.uid==t.championUid?const Icon(Icons.emoji_events,color:JangColors.ocre):null),
          if(host&&t.status=='waiting')...[
            const SizedBox(height:8),
            ChunkyButton(label:_busy?'Préparation…':'Lancer le tournoi',icon:Icons.account_tree_outlined,color:JangColors.primary,
              onPressed:_busy||data.people.length<2?null:()=>_advance(t)),
          ],
          if(t.status=='running'||t.status=='finished')...[
            const SizedBox(height:14),Text('Manche ${t.round}',style:titleStyle(19,weight:800)),
            for(final g in data.games)_gameCard(t,g,host),
            if(host&&t.status=='running')Padding(padding:const EdgeInsets.only(top:10),child:ChunkyButton(
              label:_busy?'Calcul…':'Calculer les vainqueurs / lancer la suite',icon:Icons.skip_next,color:JangColors.primary,
              onPressed:_busy?null:()=>_advance(t))),
            const SizedBox(height:6),const Text('Les matchs en direct du tournoi sont observables sans autorisation.',style:TextStyle(fontSize:12,color:JangColors.textSecondary)),
          ],
        ]));
      },
    ));
  }
  Widget _gameCard(Tournament t,TournamentGame g,bool host){
    final p=AuthService.instance.profile.value;final player=p!=null&&(p.uid==g.player1Uid||p.uid==g.player2Uid);
    final done=g.status=='done'||g.status=='bye'||t.status=='finished';
    final label=g.status=='bye'?'Passe au tour suivant':g.status=='done'?'Vainqueur : ${g.winnerName}':'Partie ${g.order~/2+1}';
    return Card(margin:const EdgeInsets.only(bottom:8),child:ListTile(
      leading:CircleAvatar(backgroundColor:JangColors.snGreen,child:Text('${g.order~/2+1}',style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w800))),
      title:Text('${g.player1Name}${g.player2Name.isEmpty?'':'  ·  ${g.player2Name}'}'),
      subtitle:Text(label),
      trailing:g.matchId.isEmpty?null:Wrap(spacing:2,children:[
        if(player||host)IconButton(tooltip:host?'Gérer le match':'Jouer',onPressed:_busy||done?null:()=>_openGame(t,g),icon:Icon(host?Icons.settings_outlined:Icons.play_circle_outline,color:JangColors.snGreen)),
        if(!player&&!host)IconButton(tooltip:'Observer librement',onPressed:_busy||done?null:()=>_openGame(t,g),icon:const Icon(Icons.visibility_outlined,color:JangColors.snGreen)),
      ]),
    ));
  }
}

/// Tournois d'une classe : le prof les crée, les élèves de la classe s'y inscrivent.
class ClassTournamentsScreen extends StatefulWidget{
  final ClassRoom classRoom;
  const ClassTournamentsScreen({super.key,required this.classRoom});
  @override State<ClassTournamentsScreen> createState()=>_ClassTournamentsScreenState();
}
class _ClassTournamentsScreenState extends State<ClassTournamentsScreen>{
  late Future<List<Tournament>> _future=TournamentService.instance.ofClass(widget.classRoom.id);
  bool _busy=false;
  void _reload(){if(mounted)setState(()=>_future=TournamentService.instance.ofClass(widget.classRoom.id));}
  bool get _organizer{
    final p=AuthService.instance.profile.value;
    return p!=null&&(p.uid==widget.classRoom.profUid||p.isAdmin);
  }
  Future<void> _create()async{
    final c=widget.classRoom;
    final form=await showDialog<_TournamentForm>(context:context,builder:(_)=>_TournamentSetupDialog(className:c.name));
    if(form==null||!mounted)return;
    final host=AuthService.instance.profile.value;if(host==null)return;
    setState(()=>_busy=true);
    try{
      final qs=await QuizBank.instance.drawDomains(form.domains,form.level,form.count);
      if(!mounted)return;
      if(qs.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Aucune question disponible pour ces choix.')));return;}
      final t=await TournamentService.instance.create(host:host,title:form.title,questions:qs,capacity:64,
        classRoom:c,level:form.level,domains:form.domains);
      if(!mounted)return;
      await Navigator.push(context,MaterialPageRoute(builder:(_)=>TournamentDetailScreen(tournamentId:t.id)));
      _reload();
    }catch(_){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Impossible de créer le tournoi. Vérifie ta connexion internet.')));
    }finally{if(mounted)setState(()=>_busy=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text('Tournois · ${widget.classRoom.name}')),
    floatingActionButton:_organizer?FloatingActionButton.extended(
      onPressed:_busy?null:_create,backgroundColor:JangColors.snGreen,foregroundColor:Colors.white,
      icon:const Icon(Icons.add),label:Text(_busy?'Préparation…':'Créer un tournoi')):null,
    body:FutureBuilder<List<Tournament>>(
      future:_future,
      builder:(context,snap){
        if(snap.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
        final list=snap.data;
        if(snap.hasError||list==null)return Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
          const Text('Impossible de charger les tournois.'),const SizedBox(height:10),
          FilledButton(onPressed:_reload,child:const Text('Réessayer'))]));
        return RefreshIndicator(onRefresh:()async=>_reload(),child:ListView(padding:const EdgeInsets.fromLTRB(16,12,16,96),children:[
          Text(_organizer
            ?'Crée un tournoi pour ta classe : tes élèves s’inscrivent, puis tu lances le tableau et les matchs.'
            :'Les tournois de ta classe : inscris-toi et affronte tes camarades !'),
          const SizedBox(height:12),
          if(list.isEmpty)Padding(padding:const EdgeInsets.all(24),child:Text(
            _organizer?'Pas encore de tournoi. Crée le premier !':'Ton prof n’a pas encore créé de tournoi.',textAlign:TextAlign.center)),
          for(final t in list)Card(child:ListTile(
            leading:CircleAvatar(backgroundColor:JangColors.snGreen,child:Icon(t.status=='finished'?Icons.emoji_events:Icons.account_tree_outlined,color:Colors.white)),
            title:Text(t.title),
            subtitle:Text(t.status=='waiting'?'Inscriptions ouvertes':t.status=='finished'?'Champion : ${t.championName}':'Manche ${t.round} en cours'),
            trailing:const Icon(Icons.chevron_right),
            onTap:()async{
              await Navigator.push(context,MaterialPageRoute(builder:(_)=>TournamentDetailScreen(tournamentId:t.id)));
              _reload();
            },
          )),
        ]));
      },
    ),
  );
}
