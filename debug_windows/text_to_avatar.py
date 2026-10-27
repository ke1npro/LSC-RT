# -*- coding: utf-8 -*-
"""
text_to_avatar.py

Motor de Síntesis de Texto a Avatar Cinemático para Lengua de Señas Colombiana (LSC).

Funcionalidades:
1. Normalización y análisis sintáctico de texto/transcripción de voz.
2. Mapeo a clips de señas canónicas desde 'lsc_motion_bank.json'.
3. Encadenamiento y mezcla cinemática suave (Cubic Hermite Blending) entre señas consecutivas.
4. Renderizador visual de Avatar pedagógico (exporta video MP4 de alta definición):
   - Esqueleto articulado estilizado (cabeza, torso, brazos, 21 puntos por mano).
   - Estela de trayectoria luminosa (motion trail) para visualización didáctica.
   - HUD pedagógico con fase del gesto (Inicio, Ápex, Culminación) e instrucciones.
"""

import os
import sys
import re
import json
import unicodedata
import cv2
import numpy as np

WORKSPACE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
MOTION_BANK_PATH = os.path.join(os.path.dirname(__file__), 'output', 'avatar', 'lsc_motion_bank.json')
AVATAR_OUT_DIR = os.path.join(os.path.dirname(__file__), 'output', 'avatar')
os.makedirs(AVATAR_OUT_DIR, exist_ok=True)

# Conexiones estándar de MediaPipe Hand (21 puntos)
HAND_CONNECTIONS = [
    (0, 1), (1, 2), (2, 3), (3, 4),        # Pulgar
    (0, 5), (5, 6), (6, 7), (7, 8),        # Índice
    (9, 10), (10, 11), (11, 12),           # Medio
    (13, 14), (14, 15), (15, 16),          # Anular
    (0, 17), (17, 18), (18, 19), (19, 20), # Meñique
    (5, 9), (9, 13), (13, 17)              # Palma
]

# Mapa de expresiones y sinónimos para el parser de texto
TEXT_SYNONYMS = [
    (r'\b(muchas\s+)?gracias\b', 'gracias'),
    (r'\bbuen(os)?\s*d[ií]as?\b', 'buenos_dias'),
    (r'\bbuen(as)?\s*tardes?\b', 'buenas_tardes'),
    (r'\bbuen(as)?\s*noches?\b', 'buenas_noches'),
]

# Postura neutral de reposo (brazos relajados a los costados)
NEUTRAL_REST_TORSO = {
    'nose': [0.50, 0.22, 0.0],
    'left_shoulder': [0.38, 0.38, 0.0],
    'right_shoulder': [0.62, 0.38, 0.0],
    'left_elbow': [0.34, 0.58, 0.0],
    'right_elbow': [0.66, 0.58, 0.0],
    'left_wrist': [0.35, 0.78, 0.0],
    'right_wrist': [0.65, 0.78, 0.0]
}


def normalize_text(text):
    """Limpia y normaliza el texto eliminando acentos y caracteres especiales."""
    nfkd = unicodedata.normalize('NFKD', text)
    cleaned = ''.join([c for c in nfkd if not unicodedata.combining(c)]).lower()
    return cleaned.strip()


def parse_text_to_sign_sequence(input_text, motion_bank):
    """
    Analiza una frase en texto y retorna la secuencia ordenada de claves de señas.
    Ejemplo: 'hola buenos días y muchas gracias' -> ['buenos_dias', 'gracias']
    """
    norm = normalize_text(input_text)
    matched_signs = []

    # Buscar coincidencias con regex ordenadas por posición en el texto
    matches = []
    for pattern, sign_key in TEXT_SYNONYMS:
        for m in re.finditer(pattern, norm):
            matches.append((m.start(), sign_key))

    matches.sort(key=lambda x: x[0])
    for _, sign_key in matches:
        if sign_key in motion_bank and sign_key not in matched_signs:
            matched_signs.append(sign_key)

    # Si no hubo match por regex, buscar palabras clave directas
    if not matched_signs:
        for word in norm.split():
            if word in motion_bank:
                matched_signs.append(word)

    # Fallback predeterminado a 'gracias' si no hay coincidencia
    if not matched_signs:
        matched_signs = ['gracias']

    return matched_signs


def interpolate_frames(frame_a, frame_b, alpha):
    """Interpola linealmente entre dos fotogramas de movimiento con easing."""
    # Easing cúbico (smoothstep)
    t = alpha * alpha * (3.0 - 2.0 * alpha)

    res = {
        'torso': {},
        'left_hand': [],
        'right_hand': []
    }

    # Interpolar torso
    for k in frame_a['torso'].keys():
        pa = np.array(frame_a['torso'][k])
        pb = np.array(frame_b['torso'][k])
        p_interp = (1.0 - t) * pa + t * pb
        res['torso'][k] = [round(float(c), 4) for c in p_interp]

    # Interpolar manos si existen en ambos
    if len(frame_a['right_hand']) == 21 and len(frame_b['right_hand']) == 21:
        ra = np.array(frame_a['right_hand'])
        rb = np.array(frame_b['right_hand'])
        r_interp = (1.0 - t) * ra + t * rb
        res['right_hand'] = [[round(float(c), 4) for c in pt] for pt in r_interp]
    elif len(frame_b['right_hand']) == 21:
        res['right_hand'] = frame_b['right_hand']
    else:
        res['right_hand'] = frame_a['right_hand']

    if len(frame_a['left_hand']) == 21 and len(frame_b['left_hand']) == 21:
        la = np.array(frame_a['left_hand'])
        lb = np.array(frame_b['left_hand'])
        l_interp = (1.0 - t) * la + t * lb
        res['left_hand'] = [[round(float(c), 4) for c in pt] for pt in l_interp]
    elif len(frame_b['left_hand']) == 21:
        res['left_hand'] = frame_b['left_hand']
    else:
        res['left_hand'] = frame_a['left_hand']

    return res


def synthesize_motion_sequence(sign_keys, motion_bank, transition_frames=10):
    """
    Ensambla la secuencia temporal completa uniendo los clips seleccionados
    con interpolación cinematográfica suave en las transiciones.
    """
    all_frames = []
    annotations = []

    # Fotograma neutral base
    rest_frame = {
        'torso': NEUTRAL_REST_TORSO,
        'left_hand': [],
        'right_hand': []
    }

    current_frame = rest_frame

    for s_idx, sign_key in enumerate(sign_keys):
        sign_data = motion_bank[sign_key]
        sign_frames = sign_data['frames']
        n_frames = len(sign_frames)
        apex_f = sign_data['apex_frame']
        display_name = sign_data['display_name']
        instructions = sign_data['pedagogical_metadata']['instructions']

        # 1. Transición suave hacia el inicio de la seña (ease-in)
        first_frame = sign_frames[0]
        for step in range(transition_frames):
            alpha = (step + 1) / float(transition_frames)
            blended = interpolate_frames(current_frame, first_frame, alpha)
            all_frames.append(blended)
            annotations.append({
                'sign': display_name,
                'phase': 'Preparación',
                'hint': 'Posicionando manos hacia el punto de inicio...',
                'is_apex': False
            })

        # 2. Reproducir la seña canónica completa
        for f_i, frm in enumerate(sign_frames):
            all_frames.append(frm)
            is_apex = (abs(f_i - apex_f) <= 2)
            if f_i < apex_f:
                phase = 'Ascenso / Ejecución'
                hint = instructions
            elif is_apex:
                phase = 'ÁPEX CLAVE'
                hint = sign_data['pedagogical_metadata']['apex_description']
            else:
                phase = 'Culminación / Liberación'
                hint = 'Completando trayectoria del gesto...'

            annotations.append({
                'sign': display_name,
                'phase': phase,
                'hint': hint,
                'is_apex': is_apex
            })

        current_frame = sign_frames[-1]

    # 3. Transición final de regreso al reposo neutral (ease-out)
    for step in range(transition_frames):
        alpha = (step + 1) / float(transition_frames)
        blended = interpolate_frames(current_frame, rest_frame, alpha)
        all_frames.append(blended)
        annotations.append({
            'sign': sign_keys[-1].upper(),
            'phase': 'Reposo',
            'hint': 'Regresando a postura neutral de descanso.',
            'is_apex': False
        })

    return all_frames, annotations


# =========================================================================
# RENDERIZADOR VISUAL DE AVATAR (ESTILO DIDÁCTICO DARK THEME)
# =========================================================================

def render_avatar_video(frames_seq, annotations, out_mp4_path, fps=24.0, width=960, height=720):
    """
    Renderiza la animación del avatar en video MP4 con estética didáctica:
    - Silueta del avatar con articulaciones estilizadas.
    - Estela de movimiento (motion trail ribbon).
    - HUD informativo inferior y superior.
    """
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    writer = cv2.VideoWriter(out_mp4_path, fourcc, fps, (width, height))

    # Búfer para estela de trayectoria de la mano dominante (últimos 14 frames)
    trail_points = []
    max_trail_len = 16

    for f_idx, (frame_data, annot) in enumerate(zip(frames_seq, annotations)):
        canvas = np.zeros((height, width, 3), dtype=np.uint8)

        # Fondo con gradiente sutil grafito -> carbón
        for y in range(height):
            c_val = int(18 + (y / height) * 14)
            canvas[y, :] = (c_val, c_val, c_val + 4)

        # 1. Cabina y cuadrícula de perspectiva de fondo
        cv2.line(canvas, (0, int(height * 0.85)), (width, int(height * 0.85)), (40, 40, 50), 1)

        # 2. Dibujar Torso y Cabeza del Avatar
        torso = frame_data['torso']
        torso_pts = {}
        for k, v in torso.items():
            px = int(np.clip(v[0] * width, 0, width - 1))
            py = int(np.clip(v[1] * height, 0, height - 1))
            torso_pts[k] = (px, py)

        # Cabeza estilizada
        if 'nose' in torso_pts:
            nose_p = torso_pts['nose']
            head_center = (nose_p[0], nose_p[1] - 30)
            cv2.ellipse(canvas, head_center, (38, 50), 0, 0, 360, (50, 50, 65), -1, cv2.LINE_AA)
            cv2.ellipse(canvas, head_center, (38, 50), 0, 0, 360, (100, 100, 130), 2, cv2.LINE_AA)
            # Ojos de guía
            cv2.circle(canvas, (head_center[0] - 12, head_center[1] - 8), 3, (180, 200, 255), -1, cv2.LINE_AA)
            cv2.circle(canvas, (head_center[0] + 12, head_center[1] - 8), 3, (180, 200, 255), -1, cv2.LINE_AA)

        # Clavícula y Hombros
        if 'left_shoulder' in torso_pts and 'right_shoulder' in torso_pts:
            ls = torso_pts['left_shoulder']
            rs = torso_pts['right_shoulder']
            neck_center = (int((ls[0] + rs[0]) / 2), int((ls[1] + rs[1]) / 2))

            # Conexión cuello a cabeza
            if 'nose' in torso_pts:
                cv2.line(canvas, neck_center, torso_pts['nose'], (70, 70, 90), 3, cv2.LINE_AA)

            # Pecho y Clavículas
            cv2.line(canvas, ls, rs, (0, 180, 255), 4, cv2.LINE_AA)

            # Brazos (Hombro -> Codo -> Muñeca)
            if 'left_elbow' in torso_pts and 'left_wrist' in torso_pts:
                le = torso_pts['left_elbow']
                lw = torso_pts['left_wrist']
                cv2.line(canvas, ls, le, (0, 170, 240), 3, cv2.LINE_AA)
                cv2.line(canvas, le, lw, (0, 170, 240), 3, cv2.LINE_AA)
                cv2.circle(canvas, le, 6, (0, 210, 255), -1, cv2.LINE_AA)

            if 'right_elbow' in torso_pts and 'right_wrist' in torso_pts:
                re_p = torso_pts['right_elbow']
                rw = torso_pts['right_wrist']
                cv2.line(canvas, rs, re_p, (0, 170, 240), 3, cv2.LINE_AA)
                cv2.line(canvas, re_p, rw, (0, 170, 240), 3, cv2.LINE_AA)
                cv2.circle(canvas, re_p, 6, (0, 210, 255), -1, cv2.LINE_AA)

            # Articulaciones de hombro
            cv2.circle(canvas, ls, 8, (0, 220, 255), -1, cv2.LINE_AA)
            cv2.circle(canvas, rs, 8, (0, 220, 255), -1, cv2.LINE_AA)

        # 3. Estela de Trayectoria (Motion Trail Ribbon)
        rh_pts = frame_data['right_hand']
        if len(rh_pts) == 21:
            wrist_px = (int(rh_pts[0][0] * width), int(rh_pts[0][1] * height))
            trail_points.append(wrist_px)
            if len(trail_points) > max_trail_len:
                trail_points.pop(0)

            # Dibujar la estela con desvanecimiento alfa
            for t_i in range(1, len(trail_points)):
                intensity = t_i / float(len(trail_points))
                t_col = (int(0 * intensity), int(255 * intensity), int(200 * intensity))
                cv2.line(canvas, trail_points[t_i - 1], trail_points[t_i], t_col, max(1, int(4 * intensity)), cv2.LINE_AA)

        # 4. Dibujar Manos Articuladas
        for hand_key, hand_pts_raw, color_bone, color_joint in [
            ('right', frame_data['right_hand'], (0, 255, 120), (100, 255, 180)),
            ('left', frame_data['left_hand'], (255, 220, 0), (255, 240, 120))
        ]:
            if len(hand_pts_raw) == 21:
                pts_px = [(int(p[0] * width), int(p[1] * height)) for p in hand_pts_raw]

                # Huesos
                for p1, p2 in HAND_CONNECTIONS:
                    cv2.line(canvas, pts_px[p1], pts_px[p2], (0, 0, 0), 4, cv2.LINE_AA)
                    cv2.line(canvas, pts_px[p1], pts_px[p2], color_bone, 2, cv2.LINE_AA)

                # Articulaciones
                for idx_pt, pt in enumerate(pts_px):
                    radius = 5 if idx_pt in [4, 8, 12, 16, 20] else 3
                    cv2.circle(canvas, pt, radius + 1, (0, 0, 0), -1, cv2.LINE_AA)
                    cv2.circle(canvas, pt, radius, color_joint, -1, cv2.LINE_AA)

        # Efecto de Pulso en Ápex Clave
        if annot['is_apex'] and len(rh_pts) == 21:
            wrist_px = (int(rh_pts[0][0] * width), int(rh_pts[0][1] * height))
            cv2.circle(canvas, wrist_px, 22, (0, 255, 255), 2, cv2.LINE_AA)
            cv2.circle(canvas, wrist_px, 14, (0, 255, 255), 1, cv2.LINE_AA)

        # 5. HUD Superior (Título y Seña Activa)
        cv2.rectangle(canvas, (0, 0), (width, 54), (18, 18, 22), -1)
        cv2.putText(canvas, "AVATAR LSC - MÓDULO DE APRENDIZAJE", (25, 35), cv2.FONT_HERSHEY_DUPLEX, 0.7, (180, 180, 200), 1, cv2.LINE_AA)

        # Pill con el nombre de la seña
        sign_pill_text = annot['sign']
        cv2.rectangle(canvas, (width - 260, 10), (width - 25, 44), (40, 140, 255), -1)
        cv2.putText(canvas, sign_pill_text, (width - 245, 34), cv2.FONT_HERSHEY_DUPLEX, 0.65, (255, 255, 255), 2, cv2.LINE_AA)

        # 6. HUD Inferior Glassmorphism (Fase e Instrucción Didáctica)
        hud_bot_y = height - 90
        cv2.rectangle(canvas, (0, hud_bot_y), (width, height), (15, 15, 20), -1)
        cv2.line(canvas, (0, hud_bot_y), (width, hud_bot_y), (50, 50, 60), 1)

        # Indicador de fase
        phase_col = (0, 255, 255) if annot['is_apex'] else (0, 220, 180)
        cv2.putText(canvas, f"FASE: {annot['phase']}", (25, hud_bot_y + 30), cv2.FONT_HERSHEY_DUPLEX, 0.65, phase_col, 2, cv2.LINE_AA)

        # Instrucción pedagógica
        cv2.putText(canvas, annot['hint'], (25, hud_bot_y + 62), cv2.FONT_HERSHEY_DUPLEX, 0.52, (200, 200, 210), 1, cv2.LINE_AA)

        # Barra de progreso
        prog_w = int((f_idx / float(len(frames_seq))) * width)
        cv2.line(canvas, (0, height - 3), (prog_w, height - 3), (0, 200, 255), 3)

        writer.write(canvas)

    writer.release()
    return out_mp4_path


def synthesize_text_to_avatar(input_text, out_filename=None):
    """
    Función principal de texto a avatar:
    Recibe texto, busca en el motion bank, encadena clips y renderiza el video MP4.
    """
    if not os.path.exists(MOTION_BANK_PATH):
        raise FileNotFoundError(f"Motion bank no encontrado en {MOTION_BANK_PATH}. Ejecuta build_motion_bank.py primero.")

    with open(MOTION_BANK_PATH, 'r', encoding='utf-8') as f:
        motion_bank = json.load(f)

    print(f"\nProcesando texto de entrada: \"{input_text}\"")
    sign_keys = parse_text_to_sign_sequence(input_text, motion_bank)
    print(f" -> Señas detectadas en orden: {sign_keys}")

    frames_seq, annotations = synthesize_motion_sequence(sign_keys, motion_bank, transition_frames=10)
    print(f" -> Secuencia sintética generada: {len(frames_seq)} frames ({len(frames_seq)/24.0:.2f} s)")

    if out_filename is None:
        slug = re.sub(r'[^a-z0-9]+', '_', normalize_text(input_text))[:30]
        out_filename = f"avatar_{slug}.mp4"

    out_mp4 = os.path.join(AVATAR_OUT_DIR, out_filename)
    print(f" -> Renderizando video de avatar en: {out_mp4}...")
    render_avatar_video(frames_seq, annotations, out_mp4, fps=24.0)
    print(f" -> Video generado con éxito: {out_mp4}")

    return {
        'input_text': input_text,
        'sign_keys': sign_keys,
        'total_frames': len(frames_seq),
        'duration_sec': round(len(frames_seq) / 24.0, 2),
        'video_path': out_mp4
    }


if __name__ == '__main__':
    text = sys.argv[1] if len(sys.argv) > 1 else "Buenos días, muchas gracias"
    res = synthesize_text_to_avatar(text)
    print(json.dumps(res, indent=2))
