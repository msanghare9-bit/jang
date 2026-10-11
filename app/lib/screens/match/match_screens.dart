<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Aperçu Ludo Jàng</title>
<style>
  :root{
    --red:#E31B23; --green:#00853F; --yellow:#F4D000; --blue:#159FE8;
    --bg:#F6F8F6; --ink:#1c2420; --line:#33413A;
  }
  *{box-sizing:border-box;}
  body{
    margin:0; padding:20px; background:#eef1ee;
    font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
    display:flex; justify-content:center;
  }
  .phone{
    width:360px; background:#fff; border-radius:22px; overflow:hidden;
    box-shadow:0 10px 30px rgba(0,0,0,.18);
  }
  .appbar{
    background:var(--green); color:#fff; padding:14px 16px;
    font-weight:800; font-size:17px;
  }
  .content{ padding:10px 12px 16px; }
  .players{ display:flex; gap:6px; overflow-x:auto; padding:4px 0 10px; }
  .card{
    display:flex; align-items:center; gap:6px;
    border:1.5px solid #d8ded8; border-radius:999px;
    padding:4px 8px; font-size:12px; font-weight:700; color:var(--ink);
    white-space:nowrap; flex:none;
  }
  .card.active{ border-color: var(--accent); background:#fafff9; }
  .dot{ width:16px; height:16px; border-radius:50%; flex:none; }
  .ok{ color:var(--green); } .bad{ color:var(--red); }
  .chat-ic{ font-size:13px; opacity:.75; }
  .die{
    width:24px; height:24px; border-radius:7px; background:#fff;
    border:2px solid var(--accent); display:flex; align-items:center;
    justify-content:center; font-size:12px; font-weight:800; color:var(--accent);
    margin-left:2px;
  }
  .board-wrap{ position:relative; }
  .board{
    width:100%; aspect-ratio:1/1; border-radius:12px; border:1.5px solid var(--line);
    display:grid; grid-template-columns:repeat(15,1fr); grid-template-rows:repeat(15,1fr);
    overflow:hidden; background:var(--bg); position:relative;
  }
  .cell{ border:.5px solid #e2e7e2; }
  .house{ display:flex; align-items:center; justify-content:center; }
  .house .yard{
    width:66%; height:66%; background:#fff; border-radius:8px;
    display:grid; grid-template-columns:1fr 1fr; grid-template-rows:1fr 1fr;
    gap:6%; padding:6%;
  }
  .pawn{
    border-radius:50%; width:100%; height:100%; max-width:16px; max-height:16px;
    margin:auto; border:2px solid #fff; box-shadow:0 1px 2px rgba(0,0,0,.35);
  }
  .star{ font-size:9px; color:var(--yellow); text-shadow:0 0 1px #0003; display:flex; align-items:center; justify-content:center; }
  .path-red{ background:var(--red); } .path-green{ background:var(--green); }
  .path-yellow{ background:var(--yellow); } .path-blue{ background:var(--blue); }
  .center{
    display:flex; align-items:center; justify-content:center; position:relative; overflow:hidden;
  }
  .bubble{
    position:absolute; top:6%; left:6%; max-width:40%;
    background:#fff; border:2px solid var(--red); border-radius:12px;
    padding:5px 8px; font-size:11px; font-weight:700; color:var(--ink);
    box-shadow:0 2px 6px rgba(0,0,0,.25);
  }
  .qpanel{
    position:absolute; right:5%; bottom:5%; width:46%; height:46%;
    background:#fff; border-radius:12px; box-shadow:0 4px 14px rgba(0,0,0,.3);
    padding:8px; display:flex; flex-direction:column; gap:5px; font-size:10px;
  }
  .qpanel .qtitle{ display:flex; justify-content:space-between; font-weight:800; }
  .qpanel .bar{ height:3px; background:#eee; border-radius:2px; overflow:hidden; }
  .qpanel .bar i{ display:block; height:100%; width:55%; background:var(--green); }
  .qpanel .qtext{ flex:1; display:flex; align-items:center; justify-content:center; text-align:center; font-weight:700; font-size:11px; }
  .qpanel .opts{ display:grid; grid-template-columns:1fr 1fr; gap:4px; }
  .qpanel .opts div{ border:1px solid #ccc; border-radius:6px; text-align:center; padding:3px 0; font-size:9px; }
  .note{ font-size:11.5px; color:#51615a; margin-top:10px; line-height:1.4; }
  .legend{ display:flex; gap:10px; flex-wrap:wrap; margin-top:8px; font-size:10.5px; color:#51615a; }
  .legend span{ display:inline-flex; align-items:center; gap:4px; }
  .legend i{ width:10px; height:10px; border-radius:3px; display:inline-block; }
</style>
</head>
<body>
  <div class="phone">
    <div class="appbar">Ludo Jàng</div>
    <div class="content">
      <div class="players">
        <div class="card active" style="--accent:var(--red)">
          <span class="dot" style="background:var(--red)"></span>
          Awa <span class="ok">✓3</span> <span class="bad">✗1</span>
          <span class="chat-ic">💬</span>
          <span class="die">4</span>
        </div>
        <div class="card" style="--accent:var(--yellow)">
          <span class="dot" style="background:var(--yellow)"></span>
          Modou <span class="ok">✓2</span> <span class="bad">✗2</span>
          <span class="chat-ic">💬</span>
        </div>
      </div>

      <div class="board-wrap">
        <div class="board" id="board"></div>
        <div class="bubble">👏 Bravo !</div>
        <div class="qpanel">
          <div class="qtitle"><span>Question · Débutant</span><span style="color:var(--red)">7 s</span></div>
          <div class="bar"><i></i></div>
          <div class="qtext">Quel est un synonyme de "bicycle" ?</div>
          <div class="opts"><div>bus</div><div>boat</div><div>train</div><div>bike</div></div>
        </div>
      </div>

      <div class="legend">
        <span><i style="background:var(--red)"></i>Awa</span>
        <span><i style="background:var(--green)"></i>(libre)</span>
        <span><i style="background:var(--yellow)"></i>Modou</span>
        <span><i style="background:var(--blue)"></i>(libre)</span>
      </div>

      <div class="note">
        Aperçu approximatif de l'écran actuel : le dé et la bulle de message sont à côté du nom du joueur actif (plus sur le plateau), les questions apparaissent dans le coin du joueur, et les thèmes ne sont plus pré-cochés au départ. Ce n'est pas une vraie capture d'écran — juste pour visualiser la disposition.
      </div>
    </div>
  </div>

<script>
  const board = document.getElementById('board');
  const houses = [
    {r0:0,c0:0,color:'red'}, {r0:0,c0:9,color:'green'},
    {r0:9,c0:9,color:'yellow'}, {r0:9,c0:0,color:'blue'},
  ];
  const colorVar = {red:'var(--red)',green:'var(--green)',yellow:'var(--yellow)',blue:'var(--blue)'};
  const grid = [];
  for(let r=0;r<15;r++){ grid.push(new Array(15).fill(null)); }

  // mark houses
  houses.forEach(h=>{
    for(let r=h.r0;r<h.r0+6;r++) for(let c=h.c0;c<h.c0+6;c++) grid[r][c]={type:'house',color:h.color};
  });

  // cross path (col 6-8 vertical, row 6-8 horizontal)
  for(let r=0;r<15;r++) for(let c=6;c<=8;c++) if(!grid[r][c]) grid[r][c]={type:'path'};
  for(let c=0;c<15;c++) for(let r=6;r<=8;r++) if(!grid[r][c]) grid[r][c]={type:'path'};

  // colored entry lanes (simplified)
  for(let c=1;c<=5;c++) grid[7][c]={type:'lane',color:'blue'};
  for(let r=1;r<=5;r++) grid[r][7]={type:'lane',color:'red'};
  for(let c=9;c<=13;c++) grid[7][c]={type:'lane',color:'yellow'};
  for(let r=9;r<=13;r++) grid[r][7]={type:'lane',color:'green'};

  // safe stars (approx positions)
  const stars = [[6,1],[1,8],[8,13],[13,6],[2,6],[6,12],[12,8],[8,2]];
  stars.forEach(([r,c])=>{ if(grid[r][c] && grid[r][c].type==='path') grid[r][c].star=true; });

  // center triangle cell
  grid[7][7]={type:'center'};

  for(let r=0;r<15;r++){
    for(let c=0;c<15;c++){
      const cell = grid[r][c];
      const div = document.createElement('div');
      div.className='cell';
      if(!cell){ div.style.background='var(--bg)'; }
      else if(cell.type==='house'){ div.style.background=colorVar[cell.color]; }
      else if(cell.type==='lane'){ div.classList.add('path-'+cell.color); }
      else if(cell.type==='center'){
        div.style.background='conic-gradient(var(--red) 0deg 90deg, var(--blue) 90deg 180deg, var(--green) 180deg 270deg, var(--yellow) 270deg 360deg)';
      } else if(cell.type==='path'){
        div.style.background='#fff';
        if(cell.star){ div.classList.add('star'); div.textContent='★'; }
      }
      board.appendChild(div);
    }
  }

  // Yards drawn as overlays on top of each house (simpler than spanning grid cells).
  const yardPos = {
    red:{top:'8%',left:'8%'}, green:{top:'8%',right:'8%'},
    yellow:{bottom:'8%',right:'8%'}, blue:{bottom:'8%',left:'8%'},
  };
  const pawnCount = {red:4, green:0, yellow:4, blue:0};
  houses.forEach(h=>{
    const yard=document.createElement('div');
    yard.className='yard';
    Object.assign(yard.style, {position:'absolute', width:'24%', height:'24%', ...yardPos[h.color]});
    for(let i=0;i<4;i++){
      const p=document.createElement('div');
      if(i<pawnCount[h.color]){ p.className='pawn'; p.style.background=colorVar[h.color]; }
      yard.appendChild(p);
    }
    board.appendChild(yard);
  });
</script>
</body>
</html>
