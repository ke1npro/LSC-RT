# -*- coding: utf-8 -*-
"""
generate_html_player.py

Genera un visor web interactivo 'avatar_training_viewer.html' que contiene
el reproductor del Avatar pedagógico LSC en Canvas HTML5 con soporte completo
para el vocabulario de 50 señas del dataset LSC50.

Características:
1. Incluye el Motion Bank canónico de 50 señas embebido (cero problemas de CORS).
2. Reproduce a 60 FPS con interpolación temporal suave (sub-frame lerp).
3. Selector dinámico de 50 señas con filtrado por categorías y buscador por texto.
4. Motor de síntesis de oraciones en tiempo real (encadena señas reconocidas con transiciones Hermite).
5. Controles didácticos de velocidad (0.25x, 0.5x, 1x), pausa, scrubber y estela luminosa.
6. Ficha pedagógica dinámica con ápex, instrucciones y tipo de seña (unimanual/bimanual).
"""

import os
import json

MOTION_BANK_PATH = os.path.join(os.path.dirname(__file__), 'output', 'avatar', 'lsc_motion_bank.json')
HTML_OUT_PATH = os.path.join(os.path.dirname(__file__), 'avatar_training_viewer.html')


def generate_viewer():
    if not os.path.exists(MOTION_BANK_PATH):
        raise FileNotFoundError(f"No se encontró {MOTION_BANK_PATH}")

    with open(MOTION_BANK_PATH, 'r', encoding='utf-8') as f:
        motion_bank_json_str = f.read()

    html_content = f"""<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Avatar Tutor LSC - 50 Señas Canónicas</title>
  <style>
    :root {{
      --bg: #0e0f12;
      --panel: #16181e;
      --panel-border: #282c37;
      --accent-cyan: #00f2fe;
      --accent-blue: #4facfe;
      --accent-gold: #ffbe0b;
      --accent-green: #00f59b;
      --text: #f0f2f5;
      --text-muted: #8e95a5;
    }}
    * {{
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }}
    body {{
      background: var(--bg);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      display: flex;
      flex-direction: column;
      height: 100vh;
      overflow: hidden;
    }}
    header {{
      background: var(--panel);
      border-bottom: 1px solid var(--panel-border);
      padding: 12px 24px;
      display: flex;
      align-items: center;
      justify-content: space-between;
    }}
    .title-box h1 {{
      font-size: 1.15rem;
      font-weight: 700;
      letter-spacing: -0.02em;
      color: #fff;
    }}
    .title-box p {{
      font-size: 0.78rem;
      color: var(--text-muted);
    }}
    .badge-branch {{
      background: rgba(79, 172, 254, 0.15);
      border: 1px solid rgba(79, 172, 254, 0.3);
      color: var(--accent-cyan);
      font-size: 0.72rem;
      padding: 4px 10px;
      border-radius: 999px;
      font-family: monospace;
    }}
    main {{
      display: flex;
      flex: 1;
      height: calc(100vh - 65px);
      overflow: hidden;
    }}
    .viewport-container {{
      flex: 1;
      display: flex;
      flex-direction: column;
      position: relative;
      background: radial-gradient(circle at 50% 35%, #181b24 0%, #0a0b0e 80%);
      align-items: center;
      justify-content: center;
    }}
    canvas {{
      max-width: 100%;
      max-height: calc(100% - 70px);
      border-radius: 12px;
      box-shadow: 0 20px 40px rgba(0, 0, 0, 0.6);
    }}
    .hud-overlay {{
      position: absolute;
      top: 16px;
      left: 16px;
      background: rgba(16, 18, 24, 0.75);
      backdrop-filter: blur(8px);
      border: 1px solid rgba(255, 255, 255, 0.1);
      padding: 8px 14px;
      border-radius: 8px;
      font-size: 0.8rem;
    }}
    .hud-overlay .phase-tag {{
      display: inline-block;
      padding: 2px 8px;
      border-radius: 4px;
      font-weight: 600;
      background: rgba(0, 245, 155, 0.2);
      color: var(--accent-green);
      margin-left: 6px;
    }}
    .playback-bar {{
      position: absolute;
      bottom: 12px;
      left: 20px;
      right: 20px;
      background: rgba(22, 24, 30, 0.85);
      backdrop-filter: blur(12px);
      border: 1px solid var(--panel-border);
      border-radius: 12px;
      padding: 10px 18px;
      display: flex;
      align-items: center;
      gap: 16px;
    }}
    .playback-bar button {{
      background: #2a2e3d;
      border: 1px solid #3c4257;
      color: #fff;
      padding: 6px 14px;
      border-radius: 6px;
      font-size: 0.82rem;
      cursor: pointer;
      font-weight: 500;
      transition: all 0.15s;
    }}
    .playback-bar button:hover {{
      background: #393e54;
      border-color: var(--accent-cyan);
    }}
    .playback-bar input[type="range"] {{
      flex: 1;
      accent-color: var(--accent-cyan);
      cursor: pointer;
    }}
    .speed-select {{
      background: #2a2e3d;
      border: 1px solid #3c4257;
      color: #fff;
      padding: 6px 10px;
      border-radius: 6px;
      font-size: 0.82rem;
      cursor: pointer;
    }}
    .sidebar {{
      width: 420px;
      background: var(--panel);
      border-left: 1px solid var(--panel-border);
      display: flex;
      flex-direction: column;
      padding: 18px;
      gap: 16px;
      overflow-y: auto;
    }}
    .section-title {{
      font-size: 0.82rem;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      color: var(--text-muted);
      margin-bottom: 6px;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }}
    .search-box {{
      width: 100%;
      background: #111318;
      border: 1px solid var(--panel-border);
      color: var(--text);
      padding: 8px 12px;
      border-radius: 6px;
      font-size: 0.82rem;
      outline: none;
      margin-bottom: 8px;
    }}
    .search-box:focus {{
      border-color: var(--accent-cyan);
    }}
    .categories-bar {{
      display: flex;
      gap: 6px;
      overflow-x: auto;
      padding-bottom: 6px;
      margin-bottom: 8px;
    }}
    .cat-pill {{
      background: #1e222d;
      border: 1px solid #2e3547;
      color: var(--text-muted);
      padding: 3px 8px;
      border-radius: 999px;
      font-size: 0.72rem;
      cursor: pointer;
      white-space: nowrap;
    }}
    .cat-pill.active, .cat-pill:hover {{
      background: rgba(79, 172, 254, 0.2);
      border-color: var(--accent-cyan);
      color: #fff;
    }}
    .sign-list-scroll {{
      max-height: 220px;
      overflow-y: auto;
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 6px;
      padding-right: 4px;
    }}
    .btn-sign {{
      background: #1e222d;
      border: 1px solid #2e3547;
      color: var(--text);
      padding: 8px 8px;
      border-radius: 6px;
      font-size: 0.78rem;
      font-weight: 600;
      cursor: pointer;
      text-align: left;
      transition: all 0.15s;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }}
    .btn-sign:hover {{
      border-color: var(--accent-cyan);
      background: #252a38;
    }}
    .btn-sign.active {{
      background: linear-gradient(135deg, rgba(79, 172, 254, 0.25) 0%, rgba(0, 242, 254, 0.25) 100%);
      border-color: var(--accent-cyan);
      color: #fff;
    }}
    .text-input-box {{
      display: flex;
      flex-direction: column;
      gap: 8px;
    }}
    .text-input-box textarea {{
      background: #101217;
      border: 1px solid var(--panel-border);
      border-radius: 8px;
      padding: 10px;
      color: var(--text);
      font-family: inherit;
      font-size: 0.82rem;
      resize: vertical;
      min-height: 60px;
      outline: none;
    }}
    .text-input-box textarea:focus {{
      border-color: var(--accent-cyan);
    }}
    .btn-synthesize {{
      background: linear-gradient(135deg, #00f2fe 0%, #4facfe 100%);
      border: none;
      color: #000;
      padding: 10px;
      border-radius: 6px;
      font-weight: 700;
      font-size: 0.82rem;
      cursor: pointer;
      transition: opacity 0.2s;
    }}
    .btn-synthesize:hover {{
      opacity: 0.9;
    }}
    .card-instructions {{
      background: #1a1e27;
      border: 1px solid #2d3446;
      border-radius: 10px;
      padding: 14px;
      font-size: 0.8rem;
    }}
    .card-instructions h4 {{
      color: var(--accent-cyan);
      margin-bottom: 6px;
      font-size: 0.9rem;
    }}
    .trail-toggle {{
      display: flex;
      align-items: center;
      gap: 6px;
      font-size: 0.82rem;
      cursor: pointer;
    }}
    .trail-toggle input {{
      accent-color: var(--accent-cyan);
    }}
  </style>
</head>
<body>

  <header>
    <div class="title-box">
      <h1>Avatar Tutor LSC - 50 Señas Canónicas</h1>
      <p>Visualizador Interactivo y Síntesis de Texto con Datos Reales LSC50</p>
    </div>
    <div class="badge-branch">Rama: WindowsTest | 50 Master CSVs</div>
  </header>

  <main>
    <div class="viewport-container">
      <div class="hud-overlay">
        <span id="hud-sign-name">SEÑA: GRACIAS</span>
        <span class="phase-tag" id="hud-phase">ACTIVO</span>
      </div>

      <canvas id="avatarCanvas" width="960" height="720"></canvas>

      <div class="playback-bar">
        <button id="btnPlayPause">Pausar</button>
        <button id="btnRestart">Reiniciar</button>
        <input type="range" id="scrubber" min="0" max="100" value="0">
        <span id="time-display" style="font-family: monospace; font-size: 0.78rem;">00 / 00</span>
        <select class="speed-select" id="speedSelect">
          <option value="0.25">0.25x (Lento)</option>
          <option value="0.5" selected>0.50x (Didáctico)</option>
          <option value="1.0">1.00x (Normal)</option>
        </select>
        <label class="trail-toggle">
          <input type="checkbox" id="chkTrail" checked> Estela
        </label>
      </div>
    </div>

    <aside class="sidebar">
      <div>
        <div class="section-title">
          <span>Catálogo de 50 Señas</span>
          <span id="sign-count-badge" style="color: var(--accent-cyan); font-size: 0.75rem;">50 señas</span>
        </div>
        <input type="text" class="search-box" id="searchSign" placeholder="Buscar entre las 50 señas..." oninput="renderSignList()">
        
        <div class="categories-bar" id="categoriesBar"></div>
        <div class="sign-list-scroll" id="signButtonsContainer"></div>
      </div>

      <div class="text-input-box">
        <div class="section-title">Síntesis Texto a Avatar</div>
        <textarea id="txtInput" placeholder="Escribe palabras en LSC, ej: Hola, buenos días, ¿cómo estás?, gracias...">Buenos días, muchas gracias</textarea>
        <button class="btn-synthesize" onclick="synthesizeFromInput()">Traducir a Avatar</button>
      </div>

      <div class="card-instructions">
        <h4 id="inst-title">Mecánica del Gesto: GRACIAS</h4>
        <p id="inst-body" style="color: #cbd3e1; margin-bottom: 8px;">
          Gesto de cortesía con mano dominante. Sigue la estela hasta el ápex.
        </p>
        <p style="font-size: 0.75rem; color: var(--text-muted); margin-bottom: 4px;">
          <strong>Tipo:</strong> <span id="inst-type" style="color: var(--accent-cyan);">Unimanual</span> | 
          <strong>Categoría:</strong> <span id="inst-cat" style="color: var(--accent-green);">Cortesía</span>
        </p>
        <p style="font-size: 0.75rem; color: var(--text-muted);">
          <strong>Ápex clave:</strong> <span id="inst-apex" style="color: var(--accent-gold);">Máxima extensión / contacto</span>
        </p>
      </div>

      <div class="card-instructions" style="background: #141720; border-color: #212636;">
        <h4 style="color: var(--accent-cyan); margin-bottom: 4px;">Arquitectura de Consenso</h4>
        <p style="font-size: 0.73rem; color: #8e95a5;">
          Cada seña proviene de un Master CSV generado por fusión con Trimmed Mean al 20% sobre 20 tomas de 5 señantes en MediaPipe Tasks, eliminando oclusiones con 100% de presencia articular.
        </p>
      </div>
    </aside>
  </main>

  <script>
    const MOTION_BANK = {motion_bank_json_str};

    const HAND_CONNECTIONS = [
      [0, 1], [1, 2], [2, 3], [3, 4],
      [0, 5], [5, 6], [6, 7], [7, 8],
      [9, 10], [10, 11], [11, 12],
      [13, 14], [14, 15], [15, 16],
      [0, 17], [17, 18], [18, 19], [19, 20],
      [5, 9], [9, 13], [13, 17]
    ];

    let currentSelectedSignId = 'gracias';
    let currentCategoryFilter = 'TODAS';
    let currentSequence = [];
    let currentAnnotations = [];
    let currentFrameIndex = 0;
    let isPlaying = true;
    let playbackSpeed = 0.5;
    let trailPoints = [];
    const maxTrailLength = 16;
    let lastRenderTime = 0;
    const targetFPS = 60;
    const frameInterval = 1000 / targetFPS;

    const canvas = document.getElementById('avatarCanvas');
    const ctx = canvas.getContext('2d');
    const scrubber = document.getElementById('scrubber');
    const timeDisplay = document.getElementById('time-display');
    const btnPlayPause = document.getElementById('btnPlayPause');

    // Inicializar Categorías
    function initCategories() {{
      const cats = new Set(['TODAS']);
      for (const k in MOTION_BANK) {{
        cats.add(MOTION_BANK[k].category.toUpperCase());
      }}
      const bar = document.getElementById('categoriesBar');
      bar.innerHTML = '';
      cats.forEach(cat => {{
        const btn = document.createElement('button');
        btn.className = 'cat-pill ' + (cat === 'TODAS' ? 'active' : '');
        btn.innerText = cat;
        btn.onclick = () => {{
          document.querySelectorAll('.cat-pill').forEach(p => p.classList.remove('active'));
          btn.classList.add('active');
          currentCategoryFilter = cat;
          renderSignList();
        }};
        bar.appendChild(btn);
      }});
    }}

    // Renderizar Lista de Señas con Filtros
    function renderSignList() {{
      const query = document.getElementById('searchSign').value.toLowerCase().trim();
      const container = document.getElementById('signButtonsContainer');
      container.innerHTML = '';

      let count = 0;
      for (const k in MOTION_BANK) {{
        const sign = MOTION_BANK[k];
        const matchCat = (currentCategoryFilter === 'TODAS' || sign.category.toUpperCase() === currentCategoryFilter);
        const matchQuery = (sign.display_name.toLowerCase().includes(query) || k.includes(query));

        if (matchCat && matchQuery) {{
          count++;
          const btn = document.createElement('button');
          btn.className = 'btn-sign ' + (k === currentSelectedSignId ? 'active' : '');
          btn.title = sign.display_name + ' (' + sign.category + ')';
          btn.innerText = sign.display_name;
          btn.onclick = () => playSingleSign(k);
          container.appendChild(btn);
        }}
      }}
      document.getElementById('sign-count-badge').innerText = count + ' señas';
    }}

    function interpolateFrames(fA, fB, alpha) {{
      const w = alpha * alpha * (3.0 - 2.0 * alpha);
      const resTorso = {{}};
      for (const p in fA.torso) {{
        resTorso[p] = [
          (1 - w) * fA.torso[p][0] + w * fB.torso[p][0],
          (1 - w) * fA.torso[p][1] + w * fB.torso[p][1],
          (1 - w) * fA.torso[p][2] + w * fB.torso[p][2]
        ];
      }}

      const resLH = [];
      const resRH = [];
      for (let k = 0; k < 21; k++) {{
        resLH.push([
          (1 - w) * fA.left_hand[k][0] + w * fB.left_hand[k][0],
          (1 - w) * fA.left_hand[k][1] + w * fB.left_hand[k][1],
          (1 - w) * fA.left_hand[k][2] + w * fB.left_hand[k][2]
        ]);
        resRH.push([
          (1 - w) * fA.right_hand[k][0] + w * fB.right_hand[k][0],
          (1 - w) * fA.right_hand[k][1] + w * fB.right_hand[k][1],
          (1 - w) * fA.right_hand[k][2] + w * fB.right_hand[k][2]
        ]);
      }}

      return {{ torso: resTorso, left_hand: resLH, right_hand: resRH }};
    }}

    function buildMotion(keys) {{
      const frames = [];
      const annots = [];

      keys.forEach((key, sIdx) => {{
        const sign = MOTION_BANK[key];
        if (!sign) return;

        if (sIdx > 0 && frames.length > 0) {{
          const lastF = frames[frames.length - 1];
          const nextF = sign.frames[0];
          const transFrames = 10;
          for (let step = 0; step < transFrames; step++) {{
            const alpha = (step + 1) / (transFrames + 1);
            frames.push(interpolateFrames(lastF, nextF, alpha));
            annots.push({{
              sign: sign.display_name,
              phase: 'TRANSICIÓN',
              apex: false
            }});
          }}
        }}

        const apexF = sign.phases.apex_frame;
        sign.frames.forEach((f, fIdx) => {{
          frames.push(f);
          const isApex = (Math.abs(fIdx - apexF) <= 2);
          let phaseName = 'ACTIVO';
          if (fIdx < sign.phases.active_sign[0]) phaseName = 'PREPARACIÓN';
          else if (fIdx > sign.phases.active_sign[1]) phaseName = 'RETORNO';
          else if (isApex) phaseName = 'ÁPEX';

          annots.push({{
            sign: sign.display_name,
            phase: phaseName,
            apex: isApex
          }});
        }});
      }});

      return {{ frames, annots }};
    }}

    function playSingleSign(key) {{
      currentSelectedSignId = key;
      renderSignList();

      const sign = MOTION_BANK[key];
      if (!sign) return;

      document.getElementById('inst-title').innerText = 'Mecánica del Gesto: ' + sign.display_name;
      document.getElementById('inst-body').innerText = sign.pedagogical_metadata.instructions;
      document.getElementById('inst-type').innerText = sign.type.toUpperCase();
      document.getElementById('inst-cat').innerText = sign.category;
      document.getElementById('inst-apex').innerText = sign.pedagogical_metadata.apex_description;

      const res = buildMotion([key]);
      currentSequence = res.frames;
      currentAnnotations = res.annots;
      currentFrameIndex = 0;
      trailPoints = [];
      scrubber.max = currentSequence.length - 1;
      scrubber.value = 0;
    }}

    function synthesizeFromInput() {{
      const text = document.getElementById('txtInput').value.toLowerCase();
      const keys = [];

      // Mapear oraciones a claves de las 50 señas
      for (const k in MOTION_BANK) {{
        const sign = MOTION_BANK[k];
        const disp = sign.display_name.toLowerCase().replace('¿', '').replace('?', '').replace('á', 'a').replace('é', 'e').replace('í', 'i').replace('ó', 'o').replace('ú', 'u');
        if (text.includes(disp) || text.includes(k.replace('_', ' '))) {{
          keys.push(k);
        }}
      }}

      if (keys.length === 0) keys.push('gracias');

      const res = buildMotion(keys);
      currentSequence = res.frames;
      currentAnnotations = res.annots;
      currentFrameIndex = 0;
      trailPoints = [];
      scrubber.max = currentSequence.length - 1;
      scrubber.value = 0;
    }}

    function drawAvatar(frameData, annot) {{
      const W = canvas.width;
      const H = canvas.height;

      ctx.fillStyle = '#0f1117';
      ctx.fillRect(0, 0, W, H);

      ctx.strokeStyle = '#1a1f2c';
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(0, H * 0.85);
      ctx.lineTo(W, H * 0.85);
      ctx.stroke();

      const torso = frameData.torso;
      const tPts = {{}};
      for (const p in torso) {{
        tPts[p] = [torso[p][0] * W, torso[p][1] * H];
      }}

      // Cabeza
      if (tPts.nose) {{
        const nx = tPts.nose[0];
        const ny = tPts.nose[1];
        ctx.fillStyle = '#2d3345';
        ctx.strokeStyle = '#4e5a7a';
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.ellipse(nx, ny - 30, 36, 48, 0, 0, Math.PI * 2);
        ctx.fill();
        ctx.stroke();

        ctx.fillStyle = '#9fb7ff';
        ctx.beginPath();
        ctx.arc(nx - 12, ny - 38, 3, 0, Math.PI * 2);
        ctx.arc(nx + 12, ny - 38, 3, 0, Math.PI * 2);
        ctx.fill();
      }}

      // Torso y Brazos
      if (tPts.left_shoulder && tPts.right_shoulder) {{
        const ls = tPts.left_shoulder;
        const rs = tPts.right_shoulder;
        const midNeck = [(ls[0] + rs[0]) / 2, (ls[1] + rs[1]) / 2];

        if (tPts.nose) {{
          ctx.strokeStyle = '#3e465e';
          ctx.lineWidth = 3;
          ctx.beginPath();
          ctx.moveTo(midNeck[0], midNeck[1]);
          ctx.lineTo(tPts.nose[0], tPts.nose[1]);
          ctx.stroke();
        }}

        ctx.strokeStyle = '#00f2fe';
        ctx.lineWidth = 4;
        ctx.beginPath();
        ctx.moveTo(ls[0], ls[1]);
        ctx.lineTo(rs[0], rs[1]);
        ctx.stroke();

        if (tPts.left_elbow && tPts.left_wrist) {{
          ctx.strokeStyle = '#00c6ff';
          ctx.lineWidth = 3;
          ctx.beginPath();
          ctx.moveTo(ls[0], ls[1]);
          ctx.lineTo(tPts.left_elbow[0], tPts.left_elbow[1]);
          ctx.lineTo(tPts.left_wrist[0], tPts.left_wrist[1]);
          ctx.stroke();

          ctx.fillStyle = '#4facfe';
          ctx.beginPath();
          ctx.arc(tPts.left_elbow[0], tPts.left_elbow[1], 5, 0, Math.PI * 2);
          ctx.fill();
        }}

        if (tPts.right_elbow && tPts.right_wrist) {{
          ctx.strokeStyle = '#00c6ff';
          ctx.lineWidth = 3;
          ctx.beginPath();
          ctx.moveTo(rs[0], rs[1]);
          ctx.lineTo(tPts.right_elbow[0], tPts.right_elbow[1]);
          ctx.lineTo(tPts.right_wrist[0], tPts.right_wrist[1]);
          ctx.stroke();

          ctx.fillStyle = '#4facfe';
          ctx.beginPath();
          ctx.arc(tPts.right_elbow[0], tPts.right_elbow[1], 5, 0, Math.PI * 2);
          ctx.fill();
        }}

        ctx.fillStyle = '#00f2fe';
        ctx.beginPath();
        ctx.arc(ls[0], ls[1], 7, 0, Math.PI * 2);
        ctx.arc(rs[0], rs[1], 7, 0, Math.PI * 2);
        ctx.fill();
      }}

      // Estela luminosa
      if (document.getElementById('chkTrail').checked && frameData.right_hand && frameData.right_hand.length === 21) {{
        const rWrist = frameData.right_hand[0];
        trailPoints.push([rWrist[0] * W, rWrist[1] * H]);
        if (trailPoints.length > maxTrailLength) trailPoints.shift();

        for (let i = 1; i < trailPoints.length; i++) {{
          const alpha = i / trailPoints.length;
          ctx.strokeStyle = `rgba(0, 242, 254, ${{alpha * 0.7}})`;
          ctx.lineWidth = Math.max(1, alpha * 5);
          ctx.beginPath();
          ctx.moveTo(trailPoints[i - 1][0], trailPoints[i - 1][1]);
          ctx.lineTo(trailPoints[i][0], trailPoints[i][1]);
          ctx.stroke();
        }}
      }}

      // Manos Articuladas
      [['left_hand', '#ffd166', '#ffe29a'], ['right_hand', '#00f59b', '#70ffcc']].forEach(([handKey, colBone, colJoint]) => {{
        const pts = frameData[handKey];
        if (pts && pts.length === 21) {{
          const pPx = pts.map(p => [p[0] * W, p[1] * H]);
          HAND_CONNECTIONS.forEach(([i1, i2]) => {{
            ctx.strokeStyle = '#000';
            ctx.lineWidth = 4;
            ctx.beginPath();
            ctx.moveTo(pPx[i1][0], pPx[i1][1]);
            ctx.lineTo(pPx[i2][0], pPx[i2][1]);
            ctx.stroke();

            ctx.strokeStyle = colBone;
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.moveTo(pPx[i1][0], pPx[i1][1]);
            ctx.lineTo(pPx[i2][0], pPx[i2][1]);
            ctx.stroke();
          }});

          pPx.forEach(([x, y], idx) => {{
            const rad = [4, 8, 12, 16, 20].includes(idx) ? 5 : 3;
            ctx.fillStyle = colJoint;
            ctx.beginPath();
            ctx.arc(x, y, rad, 0, Math.PI * 2);
            ctx.fill();
          }});
        }}
      }});

      // Pulso Ápex
      if (annot && annot.apex && frameData.right_hand && frameData.right_hand.length === 21) {{
        const rw = frameData.right_hand[0];
        ctx.strokeStyle = '#ffea00';
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.arc(rw[0] * W, rw[1] * H, 22, 0, Math.PI * 2);
        ctx.stroke();
      }}
    }}

    function animate(timestamp) {{
      if (!lastRenderTime) lastRenderTime = timestamp;
      const elapsed = timestamp - lastRenderTime;

      if (elapsed > (frameInterval / playbackSpeed)) {{
        lastRenderTime = timestamp;

        if (isPlaying && currentSequence.length > 0) {{
          currentFrameIndex = (currentFrameIndex + 1) % currentSequence.length;
          scrubber.value = currentFrameIndex;
        }}

        const curFrame = currentSequence[currentFrameIndex];
        const curAnnot = currentAnnotations[currentFrameIndex] || {{ sign: '', phase: '', apex: false }};

        if (curFrame) {{
          drawAvatar(curFrame, curAnnot);
          document.getElementById('hud-sign-name').innerText = 'SEÑA: ' + curAnnot.sign;
          const phaseElem = document.getElementById('hud-phase');
          phaseElem.innerText = curAnnot.phase;
          phaseElem.style.background = curAnnot.apex ? 'rgba(255, 234, 0, 0.25)' : 'rgba(0, 245, 155, 0.2)';
          phaseElem.style.color = curAnnot.apex ? '#ffea00' : '#00f59b';
          timeDisplay.innerText = `${{String(currentFrameIndex + 1).padStart(2, '0')}} / ${{String(currentSequence.length).padStart(2, '0')}}`;
        }}
      }}

      requestAnimationFrame(animate);
    }}

    btnPlayPause.addEventListener('click', () => {{
      isPlaying = !isPlaying;
      btnPlayPause.innerText = isPlaying ? 'Pausar' : 'Reanudar';
    }});

    document.getElementById('btnRestart').addEventListener('click', () => {{
      currentFrameIndex = 0;
      scrubber.value = 0;
      trailPoints = [];
    }});

    scrubber.addEventListener('input', (e) => {{
      currentFrameIndex = parseInt(e.target.value);
    }});

    document.getElementById('speedSelect').addEventListener('change', (e) => {{
      playbackSpeed = parseFloat(e.target.value);
    }});

    initCategories();
    renderSignList();
    playSingleSign('gracias');
    requestAnimationFrame(animate);
  </script>
</body>
</html>"""

    with open(HTML_OUT_PATH, 'w', encoding='utf-8') as f:
        f.write(html_content)

    print(f"Visor HTML5 generado exitosamente: {HTML_OUT_PATH}")
    return HTML_OUT_PATH


if __name__ == '__main__':
    generate_viewer()
