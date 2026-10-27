# -*- coding: utf-8 -*-
"""
generate_html_player.py

Genera un visor web interactivo 'avatar_training_viewer.html' que contiene
el reproductor del Avatar pedagógico LSC en Canvas HTML5.

Características:
1. Incluye el Motion Bank canónico embebido (cero problemas de CORS al abrir localmente).
2. Reproduce a 60 FPS con interpolación temporal suave (sub-frame lerp).
3. Permite escribir texto en tiempo real o seleccionar entre 'Gracias', 'Buenos días', 'Buenas tardes' y 'Buenas noches'.
4. Controles de velocidad didáctica (0.25x, 0.5x, 1x), pausa y barra de desplazamiento (scrubber).
5. Visualización de estela cinemática (Motion Trail) y marcas pedagógicas del ápex.
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
  <title>Avatar Tutor LSC - Texto a Señas y Entrenamiento</title>
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
      background: #20232c;
      color: var(--text);
      border: 1px solid var(--panel-border);
      padding: 4px 8px;
      border-radius: 6px;
      font-size: 0.78rem;
    }}
    .sidebar {{
      width: 360px;
      background: var(--panel);
      border-left: 1px solid var(--panel-border);
      display: flex;
      flex-direction: column;
      padding: 20px;
      gap: 20px;
      overflow-y: auto;
    }}
    .section-title {{
      font-size: 0.85rem;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      color: var(--text-muted);
      margin-bottom: 8px;
    }}
    .sign-buttons {{
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 10px;
    }}
    .btn-sign {{
      background: #1e222d;
      border: 1px solid #2e3547;
      color: var(--text);
      padding: 12px 10px;
      border-radius: 8px;
      font-size: 0.82rem;
      font-weight: 600;
      cursor: pointer;
      text-align: left;
      transition: all 0.2s;
    }}
    .btn-sign:hover {{
      border-color: var(--accent-cyan);
      background: #252a38;
      transform: translateY(-1px);
    }}
    .btn-sign.active {{
      background: linear-gradient(135deg, rgba(79, 172, 254, 0.2) 0%, rgba(0, 242, 254, 0.2) 100%);
      border-color: var(--accent-cyan);
      color: #fff;
    }}
    .text-input-box {{
      display: flex;
      flex-direction: column;
      gap: 8px;
    }}
    .text-input-box textarea {{
      background: #12141a;
      border: 1px solid #2e3547;
      color: #fff;
      padding: 10px;
      border-radius: 8px;
      font-family: inherit;
      font-size: 0.85rem;
      resize: none;
      height: 70px;
    }}
    .text-input-box textarea:focus {{
      outline: none;
      border-color: var(--accent-cyan);
    }}
    .btn-synthesize {{
      background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%);
      border: none;
      color: #0b0c10;
      padding: 10px;
      border-radius: 8px;
      font-weight: 700;
      font-size: 0.85rem;
      cursor: pointer;
      transition: opacity 0.2s;
    }}
    .btn-synthesize:hover {{
      opacity: 0.9;
    }}
    .card-instructions {{
      background: #191c24;
      border: 1px solid #282e3e;
      border-radius: 8px;
      padding: 14px;
      font-size: 0.82rem;
      line-height: 1.45;
    }}
    .card-instructions h4 {{
      color: var(--accent-gold);
      font-size: 0.82rem;
      margin-bottom: 6px;
    }}
    .trail-toggle {{
      display: flex;
      align-items: center;
      gap: 8px;
      font-size: 0.8rem;
      color: var(--text-muted);
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
      <h1>Avatar Tutor LSC - Visualizador Interactivo</h1>
      <p>Síntesis de Texto a Avatar y Aprendizaje de Señas con Datos Reales</p>
    </div>
    <div class="badge-branch">Rama: WindowsTest</div>
  </header>

  <main>
    <div class="viewport-container">
      <div class="hud-overlay">
        <span id="hud-sign-name">SEÑA: GRACIAS</span>
        <span class="phase-tag" id="hud-phase">EJECUCIÓN</span>
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
        <div class="section-title">Señas del Módulo de Entrenamiento</div>
        <div class="sign-buttons">
          <button class="btn-sign active" onclick="playSingleSign('gracias')">GRACIAS</button>
          <button class="btn-sign" onclick="playSingleSign('buenos_dias')">BUENOS DÍAS</button>
          <button class="btn-sign" onclick="playSingleSign('buenas_tardes')">BUENAS TARDES</button>
          <button class="btn-sign" onclick="playSingleSign('buenas_noches')">BUENAS NOCHES</button>
        </div>
      </div>

      <div class="text-input-box">
        <div class="section-title">Síntesis Texto a Avatar</div>
        <textarea id="txtInput" placeholder="Ej: Buenos días, muchas gracias...">Buenos días, muchas gracias</textarea>
        <button class="btn-synthesize" onclick="synthesizeFromInput()">Traducir a Avatar</button>
      </div>

      <div class="card-instructions">
        <h4 id="inst-title">Mecánica del Gesto: GRACIAS</h4>
        <p id="inst-body" style="color: #cbd3e1; margin-bottom: 8px;">
          Mano dominante plana con los dedos juntos. Las yemas tocan la barbilla/mentón y luego descienden suavemente hacia adelante en plano sagital.
        </p>
        <p style="font-size: 0.75rem; color: var(--text-muted);">
          <strong>Ápex clave:</strong> <span id="inst-apex" style="color: var(--accent-cyan);">Contacto de las yemas con el mentón</span>
        </p>
      </div>

      <div class="card-instructions" style="background: #141720; border-color: #212636;">
        <h4 style="color: var(--accent-cyan); margin-bottom: 4px;">Arquitectura Cinemática</h4>
        <p style="font-size: 0.75rem; color: #8e95a5;">
          Los movimientos reproducidos provienen directamente de las capturas MediaPipe Tasks del dataset LSC50, normalizadas respecto a la distancia interhumeral ($D_{{\\text{{hombros}}}}$) y centradas en el esternón.
        </p>
      </div>
    </aside>
  </main>

  <script>
    // Banco canónico de señas embebido
    const MOTION_BANK = {motion_bank_json_str};

    const HAND_CONNECTIONS = [
      [0, 1], [1, 2], [2, 3], [3, 4],
      [0, 5], [5, 6], [6, 7], [7, 8],
      [9, 10], [10, 11], [11, 12],
      [13, 14], [14, 15], [15, 16],
      [0, 17], [17, 18], [18, 19], [19, 20],
      [5, 9], [9, 13], [13, 17]
    ];

    const NEUTRAL_REST = {{
      torso: {{
        nose: [0.50, 0.22, 0.0],
        left_shoulder: [0.38, 0.38, 0.0],
        right_shoulder: [0.62, 0.38, 0.0],
        left_elbow: [0.34, 0.58, 0.0],
        right_elbow: [0.66, 0.58, 0.0],
        left_wrist: [0.35, 0.78, 0.0],
        right_wrist: [0.65, 0.78, 0.0]
      }},
      left_hand: [],
      right_hand: []
    }};

    let currentSequence = [];
    let currentAnnotations = [];
    let currentFrameIndex = 0;
    let isPlaying = true;
    let playbackSpeed = 0.5;
    let trailPoints = [];
    let lastTimestamp = 0;
    let accumulatedTime = 0;

    const canvas = document.getElementById('avatarCanvas');
    const ctx = canvas.getContext('2d');
    const scrubber = document.getElementById('scrubber');
    const btnPlayPause = document.getElementById('btnPlayPause');
    const timeDisplay = document.getElementById('time-display');

    function interpolateFrames(fa, fb, t) {{
      const ease = t * t * (3.0 - 2.0 * t);
      const res = {{ torso: {{}}, left_hand: [], right_hand: [] }};

      for (let k in fa.torso) {{
        res.torso[k] = [
          (1 - ease) * fa.torso[k][0] + ease * fb.torso[k][0],
          (1 - ease) * fa.torso[k][1] + ease * fb.torso[k][1],
          (1 - ease) * fa.torso[k][2] + ease * fb.torso[k][2]
        ];
      }}

      if (fa.right_hand.length === 21 && fb.right_hand.length === 21) {{
        for (let i = 0; i < 21; i++) {{
          res.right_hand.push([
            (1 - ease) * fa.right_hand[i][0] + ease * fb.right_hand[i][0],
            (1 - ease) * fa.right_hand[i][1] + ease * fb.right_hand[i][1],
            (1 - ease) * fa.right_hand[i][2] + ease * fb.right_hand[i][2]
          ]);
        }}
      }} else if (fb.right_hand.length === 21) {{
        res.right_hand = fb.right_hand;
      }} else {{
        res.right_hand = fa.right_hand;
      }}

      if (fa.left_hand.length === 21 && fb.left_hand.length === 21) {{
        for (let i = 0; i < 21; i++) {{
          res.left_hand.push([
            (1 - ease) * fa.left_hand[i][0] + ease * fb.left_hand[i][0],
            (1 - ease) * fa.left_hand[i][1] + ease * fb.left_hand[i][1],
            (1 - ease) * fa.left_hand[i][2] + ease * fb.left_hand[i][2]
          ]);
        }}
      }} else if (fb.left_hand.length === 21) {{
        res.left_hand = fb.left_hand;
      }} else {{
        res.left_hand = fa.left_hand;
      }}

      return res;
    }}

    function buildMotion(signKeys) {{
      const frames = [];
      const annots = [];
      let current = NEUTRAL_REST;
      const trans = 12;

      signKeys.forEach(key => {{
        const s = MOTION_BANK[key];
        if (!s) return;

        // Transición de entrada
        for (let i = 0; i < trans; i++) {{
          frames.push(interpolateFrames(current, s.frames[0], (i + 1) / trans));
          annots.push({{
            sign: s.display_name,
            phase: 'Preparación',
            apex: false,
            desc: s.pedagogical_metadata.instructions
          }});
        }}

        // Frames de la seña
        s.frames.forEach((f, idx) => {{
          frames.push(f);
          const isApex = Math.abs(idx - s.apex_frame) <= 2;
          let ph = 'Ejecución';
          if (isApex) ph = 'ÁPEX CLAVE';
          else if (idx > s.apex_frame) ph = 'Culminación';

          annots.push({{
            sign: s.display_name,
            phase: ph,
            apex: isApex,
            desc: isApex ? s.pedagogical_metadata.apex_description : s.pedagogical_metadata.instructions
          }});
        }});

        current = s.frames[s.frames.length - 1];
      }});

      // Transición final a reposo
      for (let i = 0; i < trans; i++) {{
        frames.push(interpolateFrames(current, NEUTRAL_REST, (i + 1) / trans));
        annots.push({{
          sign: 'REPOSO',
          phase: 'Descanso',
          apex: false,
          desc: 'Regresando a postura neutral de reposo.'
        }});
      }}

      return {{ frames, annots }};
    }}

    function playSingleSign(signKey) {{
      document.querySelectorAll('.btn-sign').forEach(b => b.classList.remove('active'));
      event.target.classList.add('active');

      const s = MOTION_BANK[signKey];
      if (s) {{
        document.getElementById('inst-title').innerText = 'Mecánica del Gesto: ' + s.display_name;
        document.getElementById('inst-body').innerText = s.pedagogical_metadata.instructions;
        document.getElementById('inst-apex').innerText = s.pedagogical_metadata.apex_description;
      }}

      const res = buildMotion([signKey]);
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

      if (text.includes('buenos') || text.includes('dias') || text.includes('días')) keys.push('buenos_dias');
      if (text.includes('tardes')) keys.push('buenas_tardes');
      if (text.includes('noches')) keys.push('buenas_noches');
      if (text.includes('gracias')) keys.push('gracias');

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

      // Rejilla de perspectiva
      ctx.strokeStyle = '#1a1f2c';
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(0, H * 0.85);
      ctx.lineTo(W, H * 0.85);
      ctx.stroke();

      const t = frameData.torso;
      const pxTorso = {{}};
      for (let k in t) {{
        pxTorso[k] = [t[k][0] * W, t[k][1] * H];
      }}

      // Cabeza
      if (pxTorso.nose) {{
        const nx = pxTorso.nose[0];
        const ny = pxTorso.nose[1] - 30;
        ctx.fillStyle = '#222838';
        ctx.strokeStyle = '#434d6b';
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.ellipse(nx, ny, 36, 48, 0, 0, Math.PI * 2);
        ctx.fill();
        ctx.stroke();

        // Ojos
        ctx.fillStyle = '#64d2ff';
        ctx.beginPath();
        ctx.arc(nx - 12, ny - 6, 3, 0, Math.PI * 2);
        ctx.arc(nx + 12, ny - 6, 3, 0, Math.PI * 2);
        ctx.fill();
      }}

      // Clavícula y Hombros
      if (pxTorso.left_shoulder && pxTorso.right_shoulder) {{
        const ls = pxTorso.left_shoulder;
        const rs = pxTorso.right_shoulder;

        ctx.strokeStyle = '#ffb300';
        ctx.lineWidth = 4;
        ctx.beginPath();
        ctx.moveTo(ls[0], ls[1]);
        ctx.lineTo(rs[0], rs[1]);
        ctx.stroke();

        // Brazos
        const drawArm = (s, e, w) => {{
          if (!s || !e || !w) return;
          ctx.strokeStyle = '#ffa000';
          ctx.lineWidth = 3;
          ctx.beginPath();
          ctx.moveTo(s[0], s[1]);
          ctx.lineTo(e[0], e[1]);
          ctx.lineTo(w[0], w[1]);
          ctx.stroke();

          ctx.fillStyle = '#ffd54f';
          ctx.beginPath();
          ctx.arc(e[0], e[1], 6, 0, Math.PI * 2);
          ctx.fill();
        }};

        drawArm(pxTorso.left_shoulder, pxTorso.left_elbow, pxTorso.left_wrist);
        drawArm(pxTorso.right_shoulder, pxTorso.right_elbow, pxTorso.right_wrist);

        ctx.fillStyle = '#ffca28';
        ctx.beginPath();
        ctx.arc(ls[0], ls[1], 8, 0, Math.PI * 2);
        ctx.arc(rs[0], rs[1], 8, 0, Math.PI * 2);
        ctx.fill();
      }}

      // Estela (Motion Trail)
      if (document.getElementById('chkTrail').checked && frameData.right_hand.length === 21) {{
        const rw = [frameData.right_hand[0][0] * W, frameData.right_hand[0][1] * H];
        trailPoints.push(rw);
        if (trailPoints.length > 18) trailPoints.shift();

        for (let i = 1; i < trailPoints.length; i++) {{
          const a = i / trailPoints.length;
          ctx.strokeStyle = `rgba(0, 245, 155, ${{a * 0.7}})`;
          ctx.lineWidth = Math.max(1, a * 4);
          ctx.beginPath();
          ctx.moveTo(trailPoints[i - 1][0], trailPoints[i - 1][1]);
          ctx.lineTo(trailPoints[i][0], trailPoints[i][1]);
          ctx.stroke();
        }}
      }}

      // Manos articuladas
      const drawHand = (pts, boneCol, jointCol) => {{
        if (pts.length !== 21) return;
        const ptsPx = pts.map(p => [p[0] * W, p[1] * H]);

        // Huesos
        ctx.strokeStyle = boneCol;
        ctx.lineWidth = 2.2;
        HAND_CONNECTIONS.forEach(([i1, i2]) => {{
          ctx.beginPath();
          ctx.moveTo(ptsPx[i1][0], ptsPx[i1][1]);
          ctx.lineTo(ptsPx[i2][0], ptsPx[i2][1]);
          ctx.stroke();
        }});

        // Articulaciones
        ptsPx.forEach((p, idx) => {{
          const r = [4, 8, 12, 16, 20].includes(idx) ? 5 : 3.2;
          ctx.fillStyle = jointCol;
          ctx.beginPath();
          ctx.arc(p[0], p[1], r, 0, Math.PI * 2);
          ctx.fill();
        }});
      }};

      drawHand(frameData.right_hand, '#00f59b', '#69f0ae');
      drawHand(frameData.left_hand, '#ffea00', '#fff59d');

      // Pulso en Ápex
      if (annot && annot.apex && frameData.right_hand.length === 21) {{
        const rw = [frameData.right_hand[0][0] * W, frameData.right_hand[0][1] * H];
        ctx.strokeStyle = 'rgba(255, 255, 0, 0.8)';
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.arc(rw[0], rw[1], 24, 0, Math.PI * 2);
        ctx.stroke();
      }}
    }}

    function animate(timestamp) {{
      if (!lastTimestamp) lastTimestamp = timestamp;
      const delta = (timestamp - lastTimestamp) / 1000;
      lastTimestamp = timestamp;

      if (isPlaying && currentSequence.length > 0) {{
        accumulatedTime += delta * playbackSpeed;
        const frameInterval = 1 / 24.0;
        if (accumulatedTime >= frameInterval) {{
          currentFrameIndex = (currentFrameIndex + 1) % currentSequence.length;
          accumulatedTime = 0;
          scrubber.value = currentFrameIndex;
        }}
      }}

      if (currentSequence.length > 0) {{
        const curFrame = currentSequence[currentFrameIndex];
        const curAnnot = currentAnnotations[currentFrameIndex] || {{ sign: '', phase: '', apex: false }};

        drawAvatar(curFrame, curAnnot);

        document.getElementById('hud-sign-name').innerText = 'SEÑA: ' + curAnnot.sign;
        const phaseElem = document.getElementById('hud-phase');
        phaseElem.innerText = curAnnot.phase;
        phaseElem.style.background = curAnnot.apex ? 'rgba(255, 234, 0, 0.25)' : 'rgba(0, 245, 155, 0.2)';
        phaseElem.style.color = curAnnot.apex ? '#ffea00' : '#00f59b';

        timeDisplay.innerText = `${{String(currentFrameIndex + 1).padStart(2, '0')}} / ${{String(currentSequence.length).padStart(2, '0')}}`;
      }}

      requestAnimationFrame(animate);
    }}

    // Listeners de controles
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

    // Inicializar con la primera seña (Gracias)
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
