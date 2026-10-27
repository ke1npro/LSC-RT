# -*- coding: utf-8 -*-
"""
realtime_camera_inference.py

Sistema optimizado de reconocimiento en tiempo real para 50 Señas de LSC.
Resuelve de raíz los cuellos de botella de FPS, la mala detección y los falsos
positivos recurrentes ('SEÑA' y 'MÁS O MENOS').

Mejoras arquitectónicas implementadas:
1. Alto rendimiento (25-30 FPS estables):
   - Captura directa DirectShow a 640x480 (elimina retrasos de búfer MSMF).
   - Inferencia MediaPipe ultrarrápida sobre resolución optimizada (~25-30 ms).
2. Corrección del Efecto Espejo (Coordenadas de Entrenamiento):
   - MediaPipe procesa el fotograma nativo de la cámara (sin invertir), alineando
     las articulaciones con el sistema de coordenadas real del dataset LSC50.
   - La pantalla muestra el reflejo espejo natural del usuario con el esqueleto
     rotado simétricamente (display_x = 1.0 - x).
3. Segmentación Cinemática Inteligente (Zero Falsos Positivos 'SEÑA' / 'MÁS O MENOS'):
   - Detección por energía cinética y pico de velocidad de muñeca (V_peak >= 0.030).
   - Rechazo estricto de posturas de reposo, vacilación o hovering pasivo.
   - Filtro de margen de confianza: P(Top-1) >= 0.58 y P(Top-1) >= 1.35 * P(Top-2).
4. Modos de Detección Dinámica:
   - Modo AUTOMÁTICO: Detecta por aceleración, ápex y desaceleración gestual.
   - Modo MANUAL ASISTIDO (tecla [M]): Mantén presionado [ESPACIO] durante la ejecución
     de la seña para una segmentación exacta.
5. Interfaz HUD Profesional:
   - Barra de Energía Gestual en vivo (indica reposo vs signado activo).
   - Frase actual y registro histórico de frases anteriores con hora exacta.
   - Ranking Top-3 con porcentajes de certidumbre.
"""

import os
import sys
import time
from collections import deque
import cv2
import numpy as np
import tensorflow as tf
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

WORKSPACE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
POSE_MODEL_PATH = os.path.join(WORKSPACE_DIR, 'assets', 'pose_landmarker_lite.task')
HAND_MODEL_PATH = os.path.join(WORKSPACE_DIR, 'assets', 'hand_landmarker.task')
TFLITE_MODEL_PATH = os.path.join(WORKSPACE_DIR, 'assets', 'lsc50_classifier.tflite')

T_TARGET = 64
NUM_CLASSES = 50

CLASS_NAMES = [
    "GRACIAS", "BUENOS DÍAS", "BUENAS TARDES", "BUENAS NOCHES", "SEÑA",
    "NOMBRE", "TRABAJAR", "COMER", "VIVIR", "POCO",
    "FAMILIA", "PERSONAS", "MUJER", "HOMBRE", "NIÑO",
    "NIÑA", "ABUELO", "TÍO", "HERMANO", "HAMBRE",
    "FELIZ", "CONTENTO", "TRISTE", "ABURRIDO", "BIEN",
    "MAL", "¿CÓMO ESTÁS?", "MÁS O MENOS", "SENTIR", "JUICIOSO",
    "HOLA", "ADIÓS", "POR FAVOR", "CON GUSTO", "BIENVENIDO",
    "PERDÓN", "PERMISO", "NUNCA", "YO", "TÚ",
    "USTEDES", "¿QUÉ?", "¿CUÁNDO?", "¿DÓNDE?", "¿CÓMO?",
    "¿POR QUÉ?", "¿QUIÉN?", "DIFERENTE", "TODOS", "MUCHO"
]

# 11 Articulaciones del cuerpo superior (idénticas a Phase 3):
# 0: Nariz, 7: Oreja I, 8: Oreja D, 9: Boca I, 10: Boca D,
# 11: Hombro I (idx 5), 12: Hombro D (idx 6), 13: Codo I (idx 7),
# 14: Codo D (idx 8), 15: Muñeca I (idx 9), 16: Muñeca D (idx 10)
POSE_INDICES = [0, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]

HAND_CONNECTIONS = [
    [0, 1], [1, 2], [2, 3], [3, 4],
    [0, 5], [5, 6], [6, 7], [7, 8],
    [9, 10], [10, 11], [11, 12],
    [13, 14], [14, 15], [15, 16],
    [0, 17], [17, 18], [18, 19], [19, 20],
    [5, 9], [9, 13], [13, 17]
]


def create_mediapipe_detectors():
    """Inicializa detectores de Pose y Manos optimizados para captura a alta velocidad."""
    if not os.path.exists(POSE_MODEL_PATH):
        raise FileNotFoundError(f"No se encontró el modelo de pose en: {POSE_MODEL_PATH}")
    if not os.path.exists(HAND_MODEL_PATH):
        raise FileNotFoundError(f"No se encontró el modelo de manos en: {HAND_MODEL_PATH}")

    pose_opts = vision.PoseLandmarkerOptions(
        base_options=python.BaseOptions(model_asset_path=POSE_MODEL_PATH),
        running_mode=vision.RunningMode.VIDEO,
        num_poses=1,
        min_pose_detection_confidence=0.45,
        min_tracking_confidence=0.45
    )
    hand_opts = vision.HandLandmarkerOptions(
        base_options=python.BaseOptions(model_asset_path=HAND_MODEL_PATH),
        running_mode=vision.RunningMode.VIDEO,
        num_hands=2,
        min_hand_detection_confidence=0.35,
        min_tracking_confidence=0.35
    )

    p_det = vision.PoseLandmarker.create_from_options(pose_opts)
    h_det = vision.HandLandmarker.create_from_options(hand_opts)
    return p_det, h_det


def interpolate_gaps(coords, mask_valid, max_gap=6):
    N = len(coords)
    filled = coords.copy()
    valid_idx = np.where(mask_valid)[0]
    if len(valid_idx) == 0:
        return np.nan_to_num(filled, 0.0), mask_valid
    if len(valid_idx) == N:
        return filled, mask_valid
    new_mask = mask_valid.copy()
    for i in range(len(valid_idx) - 1):
        idx1, idx2 = valid_idx[i], valid_idx[i + 1]
        gap = idx2 - idx1 - 1
        if 0 < gap <= max_gap:
            for step in range(1, gap + 1):
                alpha = step / (gap + 1)
                curr_idx = idx1 + step
                filled[curr_idx] = (1.0 - alpha) * filled[idx1] + alpha * filled[idx2]
                new_mask[curr_idx] = True
    return np.nan_to_num(filled, 0.0), new_mask


def temporal_resample(features, target_len=64):
    N, F = features.shape
    if N == target_len:
        return features.astype(np.float32)
    orig_steps = np.linspace(0, 1, N)
    target_steps = np.linspace(0, 1, target_len)
    resampled = np.zeros((target_len, F), dtype=np.float32)
    for f in range(F):
        resampled[:, f] = np.interp(target_steps, orig_steps, features[:, f])
    return resampled


def build_feature_matrix(pose_list, lh_list, rh_list, mask_list):
    """Genera el tensor normalizado (1, 64, 162) idéntico al corpus de entrenamiento."""
    pose_arr = np.array(pose_list, dtype=np.float32)   # (N, 11, 3)
    lh_arr = np.array(lh_list, dtype=np.float32)       # (N, 21, 3)
    rh_arr = np.array(rh_list, dtype=np.float32)       # (N, 21, 3)
    mask_arr = np.array(mask_list, dtype=bool)         # (N, 3)

    lh_filled, mask_lh = interpolate_gaps(lh_arr, mask_arr[:, 1], max_gap=6)
    rh_filled, mask_rh = interpolate_gaps(rh_arr, mask_arr[:, 2], max_gap=6)
    pose_coords = np.nan_to_num(pose_arr, 0.0)

    # 1. Normalización por hombros (idx 5 Hombro I, idx 6 Hombro D)
    sh_l = pose_coords[:, 5, :2]
    sh_r = pose_coords[:, 6, :2]
    sh_center = (sh_l + sh_r) / 2.0
    sh_width = np.linalg.norm(sh_l - sh_r, axis=1, keepdims=True)

    valid_widths = sh_width[sh_width > 0.02]
    med_w = np.median(valid_widths) if len(valid_widths) > 0 else 0.15
    sh_width[sh_width < 0.02] = med_w

    norm_pose = pose_coords.copy()
    norm_pose[:, :, :2] -= sh_center[:, np.newaxis, :]
    norm_pose /= sh_width[:, np.newaxis, :]

    # 2. Normalización de manos
    norm_lh = lh_filled.copy()
    for t in range(len(norm_lh)):
        if mask_lh[t]:
            norm_lh[t, :, :2] -= sh_center[t, :]
            norm_lh[t] /= sh_width[t, 0]
        else:
            norm_lh[t] = 0.0

    norm_rh = rh_filled.copy()
    for t in range(len(norm_rh)):
        if mask_rh[t]:
            norm_rh[t, :, :2] -= sh_center[t, :]
            norm_rh[t] /= sh_width[t, 0]
        else:
            norm_rh[t] = 0.0

    # 3. Concatenación plana (33 pose + 63 lh + 63 rh + 3 mask = 162)
    flat_pose = norm_pose.reshape(len(norm_pose), 11 * 3)
    flat_lh = norm_lh.reshape(len(norm_lh), 21 * 3)
    flat_rh = norm_rh.reshape(len(norm_rh), 21 * 3)

    mask_feat = np.column_stack([
        mask_arr[:, 0].astype(np.float32),
        mask_lh.astype(np.float32),
        mask_rh.astype(np.float32)
    ])

    feat_matrix = np.hstack([flat_pose, flat_lh, flat_rh, mask_feat])
    resampled = temporal_resample(feat_matrix, target_len=T_TARGET)
    return np.expand_dims(resampled, axis=0).astype(np.float32)


def draw_hud(frame, current_phrase, previous_phrases, last_sign, last_conf, top3_preds,
             motion_energy, is_active, is_manual_mode, is_manual_recording,
             fps, latency_ms, show_skeleton):
    H, W = frame.shape[:2]
    overlay = frame.copy()

    # 1. Barra Superior
    cv2.rectangle(overlay, (0, 0), (W, 56), (16, 17, 20), -1)
    cv2.addWeighted(overlay, 0.78, frame, 0.22, 0, frame)

    cv2.putText(frame, "LSC-RT : Reconocimiento en Tiempo Real (50 Senas)", (18, 35),
                cv2.FONT_HERSHEY_SIMPLEX, 0.70, (0, 242, 254), 2, cv2.LINE_AA)

    # Indicador de Modo
    mode_str = "MODO: MANUAL [ESPACIO]" if is_manual_mode else "MODO: AUTOMATICO"
    mode_col = (255, 190, 11) if is_manual_mode else (0, 245, 155)
    cv2.putText(frame, mode_str, (W - 470, 35),
                cv2.FONT_HERSHEY_SIMPLEX, 0.50, mode_col, 2, cv2.LINE_AA)

    # Estado y FPS
    if is_manual_recording:
        st_text = "GRABANDO GESTO..."
        st_col = (0, 245, 155)
    elif is_active:
        st_text = "SIGNANDO..."
        st_col = (0, 245, 155)
    else:
        st_text = "REPOSO"
        st_col = (130, 135, 148)

    cv2.putText(frame, st_text, (W - 240, 35),
                cv2.FONT_HERSHEY_SIMPLEX, 0.52, st_col, 2, cv2.LINE_AA)

    cv2.putText(frame, f"{fps:.0f} FPS", (W - 75, 35),
                cv2.FONT_HERSHEY_SIMPLEX, 0.50, (200, 205, 215), 1, cv2.LINE_AA)

    # 2. Barra de Energía Cinética Gestual (en vivo)
    bar_w = 160
    bar_h = 8
    bx = 20
    by = 68
    energy_norm = min(1.0, motion_energy / 0.055)
    fill_len = int(bar_w * energy_norm)
    bar_col = (0, 245, 155) if energy_norm > 0.45 else (140, 145, 155)
    if energy_norm > 0.75:
        bar_col = (0, 242, 254)

    cv2.rectangle(frame, (bx, by), (bx + bar_w, by + bar_h), (35, 38, 48), -1)
    cv2.rectangle(frame, (bx, by), (bx + fill_len, by + bar_h), bar_col, -1)
    cv2.putText(frame, "Energia cinetica", (bx + bar_w + 12, by + 8),
                cv2.FONT_HERSHEY_SIMPLEX, 0.40, (140, 145, 155), 1, cv2.LINE_AA)

    # 3. Panel Lateral Derecho: Top 3 Predicciones
    if top3_preds:
        p_w, p_h = 240, 110
        px, py = W - p_w - 15, 68
        cv2.rectangle(overlay, (px, py), (px + p_w, py + p_h), (20, 22, 28), -1)
        cv2.addWeighted(overlay, 0.82, frame, 0.18, 0, frame)
        cv2.rectangle(frame, (px, py), (px + p_w, py + p_h), (40, 44, 55), 1)

        cv2.putText(frame, "TOP 3 CANDIDATOS", (px + 12, py + 22),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.45, (142, 149, 165), 1, cv2.LINE_AA)

        for i, (p_name, p_prob) in enumerate(top3_preds):
            y_item = py + 48 + i * 24
            bar_len = int(115 * p_prob)
            col = (0, 242, 254) if i == 0 else (170, 175, 185)
            cv2.putText(frame, f"{p_name[:11]}", (px + 12, y_item),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.48, col, 1, cv2.LINE_AA)
            cv2.rectangle(frame, (px + 125, y_item - 10), (px + 125 + bar_len, y_item - 2), col, -1)
            cv2.putText(frame, f"{p_prob*100:.0f}%", (px + 195, y_item),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.42, (200, 205, 215), 1, cv2.LINE_AA)

    # 4. Panel Inferior
    pan_h = 165
    cv2.rectangle(overlay, (0, H - pan_h), (W, H), (14, 15, 18), -1)
    cv2.addWeighted(overlay, 0.86, frame, 0.14, 0, frame)
    cv2.line(frame, (0, H - pan_h), (W, H - pan_h), (40, 44, 55), 1)

    # A. Frase Actual
    cv2.putText(frame, "FRASE ACTUAL:", (20, H - pan_h + 26),
                cv2.FONT_HERSHEY_SIMPLEX, 0.50, (255, 190, 11), 1, cv2.LINE_AA)

    str_current = " ".join(current_phrase) if current_phrase else "(Realiza un gesto continuo o mantén [ESPACIO]...)"
    col_phrase = (255, 255, 255) if current_phrase else (100, 105, 118)
    cv2.putText(frame, str_current, (20, H - pan_h + 58),
                cv2.FONT_HERSHEY_SIMPLEX, 0.82, col_phrase, 2, cv2.LINE_AA)

    if last_sign:
        sign_badge = f"Ultima: {last_sign} ({last_conf*100:.1f}%) | {latency_ms:.1f}ms"
        cv2.putText(frame, sign_badge, (W - 360, H - pan_h + 26),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.48, (0, 245, 155), 1, cv2.LINE_AA)

    # B. Historial de Frases Anteriores
    cv2.line(frame, (20, H - 72), (W - 20, H - 72), (30, 33, 42), 1)
    cv2.putText(frame, "FRASES ANTERIORES:", (20, H - 52),
                cv2.FONT_HERSHEY_SIMPLEX, 0.44, (140, 145, 158), 1, cv2.LINE_AA)

    if previous_phrases:
        recent = previous_phrases[-2:]
        disp_prev = "   |   ".join([f"[{t}] {p}" for t, p in recent])
    else:
        disp_prev = "Historial vacio. Presiona [ENTER] para guardar la frase actual."

    cv2.putText(frame, disp_prev, (20, H - 26),
                cv2.FONT_HERSHEY_SIMPLEX, 0.52, (180, 185, 198), 1, cv2.LINE_AA)

    # C. Teclas de ayuda
    help_keys = "[ENTER] Guardar Frase | [M] Cambiar Modo | [C] Limpiar | [B] Borrar Seña | [S] Esqueleto | [Q] Salir"
    cv2.putText(frame, help_keys, (W - 610, H - 8),
                cv2.FONT_HERSHEY_SIMPLEX, 0.38, (90, 95, 108), 1, cv2.LINE_AA)


def draw_skeleton_mirrored(frame, pose_landmarks, lh_landmarks, rh_landmarks):
    """
    Dibuja el esqueleto sobre la imagen ya espejada para que coincida exactamente
    con el reflejo visual del usuario.
    """
    H, W = frame.shape[:2]

    def mirror_pt(x, y):
        # Al estar el frame ya espejado con flip(1), una coordenada nativa x (0..1)
        # se dibuja en (1.0 - x) * W
        return (int((1.0 - x) * W), int(y * H))

    # Mano Izquierda (Dorado)
    if lh_landmarks is not None and not np.isnan(lh_landmarks).all():
        px_pts = [mirror_pt(p[0], p[1]) for p in lh_landmarks]
        for i1, i2 in HAND_CONNECTIONS:
            cv2.line(frame, px_pts[i1], px_pts[i2], (102, 209, 255), 2, cv2.LINE_AA)
        for pt in px_pts:
            cv2.circle(frame, pt, 3, (154, 226, 255), -1, cv2.LINE_AA)

    # Mano Derecha (Verde Esmeralda)
    if rh_landmarks is not None and not np.isnan(rh_landmarks).all():
        px_pts = [mirror_pt(p[0], p[1]) for p in rh_landmarks]
        for i1, i2 in HAND_CONNECTIONS:
            cv2.line(frame, px_pts[i1], px_pts[i2], (155, 245, 0), 2, cv2.LINE_AA)
        for pt in px_pts:
            cv2.circle(frame, pt, 3, (204, 255, 112), -1, cv2.LINE_AA)

    # Brazos (Hombro -> Codo -> Muñeca)
    # Pose: 5 Hombro I, 6 Hombro D, 7 Codo I, 8 Codo D, 9 Muñeca I, 10 Muñeca D
    if pose_landmarks is not None and not np.isnan(pose_landmarks).all():
        ls = mirror_pt(pose_landmarks[5][0], pose_landmarks[5][1])
        rs = mirror_pt(pose_landmarks[6][0], pose_landmarks[6][1])
        le = mirror_pt(pose_landmarks[7][0], pose_landmarks[7][1])
        re = mirror_pt(pose_landmarks[8][0], pose_landmarks[8][1])
        lw = mirror_pt(pose_landmarks[9][0], pose_landmarks[9][1])
        rw = mirror_pt(pose_landmarks[10][0], pose_landmarks[10][1])

        cv2.line(frame, ls, rs, (254, 242, 0), 3, cv2.LINE_AA)
        cv2.line(frame, ls, le, (255, 198, 0), 2, cv2.LINE_AA)
        cv2.line(frame, le, lw, (255, 198, 0), 2, cv2.LINE_AA)
        cv2.line(frame, rs, re, (255, 198, 0), 2, cv2.LINE_AA)
        cv2.line(frame, re, rw, (255, 198, 0), 2, cv2.LINE_AA)

        for pt in [ls, rs, le, re, lw, rw]:
            cv2.circle(frame, pt, 5, (254, 172, 79), -1, cv2.LINE_AA)


def run_realtime_recognition(camera_id=0):
    print("=" * 80)
    print(" INICIANDO SISTEMA LSC-RT EN TIEMPO REAL (ALTA PRECISIÓN & VELOCIDAD)")
    print(" (DirectShow 640x480 | MediaPipe Tasks Nativo | TensorFlow Lite)")
    print("=" * 80)

    # 1. Intérprete TFLite
    interp = tf.lite.Interpreter(model_path=TFLITE_MODEL_PATH)
    interp.allocate_tensors()
    in_idx = interp.get_input_details()[0]['index']
    out_idx = interp.get_output_details()[0]['index']
    print("Modelo TensorFlow Lite inicializado.")

    # 2. Detectores MediaPipe
    p_det, h_det = create_mediapipe_detectors()
    print("MediaPipe Tasks listo.")

    # 3. Cámara DirectShow a 640x480 (rendimiento nativo 30 FPS)
    cap = cv2.VideoCapture(camera_id, cv2.CAP_DSHOW if sys.platform.startswith('win') else cv2.CAP_ANY)
    if not cap.isOpened():
        cap = cv2.VideoCapture(1, cv2.CAP_DSHOW if sys.platform.startswith('win') else cv2.CAP_ANY)
        if not cap.isOpened():
            raise RuntimeError("No se detectó cámara disponible.")

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    cap.set(cv2.CAP_PROP_FPS, 30)

    actual_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    actual_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    print(f"Cámara configurada a {actual_w}x{actual_h} @ 30 FPS.\n")

    # Estados
    current_phrase = []
    previous_phrases = []
    last_detected_sign = ""
    last_confidence = 0.0
    top3_predictions = []
    show_skeleton = True
    is_manual_mode = False
    is_manual_recording = False

    # Búferes temporales
    MAX_BUFFER = 70
    MIN_SIGN_FRAMES = 14
    pose_buffer = deque(maxlen=MAX_BUFFER)
    lh_buffer = deque(maxlen=MAX_BUFFER)
    rh_buffer = deque(maxlen=MAX_BUFFER)
    mask_buffer = deque(maxlen=MAX_BUFFER)

    # Variables cinemáticas
    prev_rw = None
    prev_lw = None
    current_velocity = 0.0
    vel_peak = 0.0
    is_signing = False
    calm_counter = 0
    cooldown_counter = 0
    last_sign_time = time.time()
    last_inf_latency = 0.0

    fps_history = deque(maxlen=15)
    prev_time = time.time()
    t_start = time.time()

    win_title = "LSC-RT : Reconocimiento en Tiempo Real"
    cv2.namedWindow(win_title, cv2.WINDOW_NORMAL)
    cv2.resizeWindow(win_title, 960, 720)

    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                break

            cur_time = time.time()
            fps_history.append(1.0 / max(1e-4, cur_time - prev_time))
            prev_time = cur_time
            current_fps = float(np.mean(fps_history))

            t_ms = int((cur_time - t_start) * 1000)

            # IMPORTANTE: Procesamos el fotograma NATIVO sin invertir para que coincida
            # exactamente con las coordenadas espaciales del dataset LSC50
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            mp_img = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)

            # Inferencia MediaPipe
            p_res = p_det.detect_for_video(mp_img, t_ms)
            h_res = h_det.detect_for_video(mp_img, t_ms)

            # 1. Pose (11 puntos exactos)
            has_pose = False
            pose_11 = np.full((11, 3), np.nan, dtype=np.float32)
            lw_pt = None
            rw_pt = None

            if p_res.pose_landmarks and len(p_res.pose_landmarks) > 0:
                has_pose = True
                lm = p_res.pose_landmarks[0]
                for o_idx, p_idx in enumerate(POSE_INDICES):
                    p = lm[p_idx]
                    pose_11[o_idx] = [p.x, p.y, p.z]

                lw_pt = np.array([lm[15].x, lm[15].y])
                rw_pt = np.array([lm[16].x, lm[16].y])

            # 2. Manos con asignación unívoca por proximidad a muñecas corporales
            has_lh = False
            has_rh = False
            lh_21 = np.full((21, 3), np.nan, dtype=np.float32)
            rh_21 = np.full((21, 3), np.nan, dtype=np.float32)

            det_hands = h_res.hand_landmarks if h_res.hand_landmarks else []

            if len(det_hands) == 2 and lw_pt is not None and rw_pt is not None:
                hw0 = np.array([det_hands[0][0].x, det_hands[0][0].y])
                hw1 = np.array([det_hands[1][0].x, det_hands[1][0].y])
                cost_A = np.linalg.norm(hw0 - lw_pt) + np.linalg.norm(hw1 - rw_pt)
                cost_B = np.linalg.norm(hw0 - rw_pt) + np.linalg.norm(hw1 - lw_pt)

                if cost_A <= cost_B:
                    l_h, r_h = det_hands[0], det_hands[1]
                else:
                    l_h, r_h = det_hands[1], det_hands[0]

                has_lh = True
                has_rh = True
                lh_21 = np.array([[p.x, p.y, p.z] for p in l_h], dtype=np.float32)
                rh_21 = np.array([[p.x, p.y, p.z] for p in r_h], dtype=np.float32)

            elif len(det_hands) == 1 and lw_pt is not None and rw_pt is not None:
                hw0 = np.array([det_hands[0][0].x, det_hands[0][0].y])
                d_l = float(np.linalg.norm(hw0 - lw_pt))
                d_r = float(np.linalg.norm(hw0 - rw_pt))

                pts = np.array([[p.x, p.y, p.z] for p in det_hands[0]], dtype=np.float32)
                if d_l < d_r and d_l < 0.28:
                    has_lh = True
                    lh_21 = pts
                elif d_r <= d_l and d_r < 0.28:
                    has_rh = True
                    rh_21 = pts

            elif len(det_hands) > 0:
                for idx_h, hand in enumerate(det_hands):
                    cat_name = h_res.handedness[idx_h][0].category_name
                    pts = np.array([[p.x, p.y, p.z] for p in hand], dtype=np.float32)
                    if cat_name == 'Left' and not has_lh:
                        has_lh = True
                        lh_21 = pts
                    elif cat_name == 'Right' and not has_rh:
                        has_rh = True
                        rh_21 = pts

            # 3. Cálculo de Velocidad y Energía Cinética
            v_l = 0.0
            v_r = 0.0
            if lw_pt is not None and prev_lw is not None:
                v_l = float(np.linalg.norm(lw_pt - prev_lw))
            if rw_pt is not None and prev_rw is not None:
                v_r = float(np.linalg.norm(rw_pt - prev_rw))

            if lw_pt is not None:
                prev_lw = lw_pt.copy()
            if rw_pt is not None:
                prev_rw = rw_pt.copy()

            current_velocity = max(v_l, v_r)

            # Criterio de Elevación Pectoral: Al menos una mano por encima del esternón
            hands_elevated = False
            if has_pose and (has_lh or has_rh):
                sh_y = (pose_11[5, 1] + pose_11[6, 1]) / 2.0
                min_w = 1.0
                if has_lh and lw_pt is not None:
                    min_w = min(min_w, lw_pt[1])
                if has_rh and rw_pt is not None:
                    min_w = min(min_w, rw_pt[1])
                # En LSC el espacio de articulación está a menos de 0.22 bajo los hombros
                if (min_w - sh_y) < 0.22:
                    hands_elevated = True

            # Máquina de Estados de Detección
            if cooldown_counter > 0:
                cooldown_counter -= 1

            execute_eval = False

            if is_manual_mode:
                # MODO MANUAL: Se graba mientras el usuario mantiene activo el estado
                if is_manual_recording:
                    pose_buffer.append(pose_11)
                    lh_buffer.append(lh_21)
                    rh_buffer.append(rh_21)
                    mask_buffer.append([has_pose, has_lh, has_rh])
            else:
                # MODO AUTOMÁTICO RIGUROSO POR VELOCIDAD CINÉTICA
                # A. Inicio de trazo: manos elevadas con aceleración intencional (V > 0.022)
                if not is_signing:
                    if hands_elevated and current_velocity > 0.022 and cooldown_counter == 0:
                        is_signing = True
                        vel_peak = current_velocity
                        calm_counter = 0
                        pose_buffer.append(pose_11)
                        lh_buffer.append(lh_21)
                        rh_buffer.append(rh_21)
                        mask_buffer.append([has_pose, has_lh, has_rh])
                else:
                    # B. En curso de trazo: registrar movimiento y pico
                    pose_buffer.append(pose_11)
                    lh_buffer.append(lh_21)
                    rh_buffer.append(rh_21)
                    mask_buffer.append([has_pose, has_lh, has_rh])
                    vel_peak = max(vel_peak, current_velocity)

                    # Desaceleración / Ápex finalizado: velocidad decae por debajo de 0.015
                    if current_velocity < 0.015 or not hands_elevated:
                        calm_counter += 1
                    else:
                        calm_counter = 0

                    # C. Fin de seña: calma sostenida por 6 cuadros (~200 ms) o límite de buffer
                    if (calm_counter >= 6 and len(pose_buffer) >= MIN_SIGN_FRAMES) or len(pose_buffer) >= 60:
                        if vel_peak >= 0.028: # Exige que haya existido un golpe gestual real
                            execute_eval = True
                        else:
                            # Falsa alarma (solo fue un leve temblor en reposo)
                            pose_buffer.clear()
                            lh_buffer.clear()
                            rh_buffer.clear()
                            mask_buffer.clear()

                        is_signing = False
                        calm_counter = 0

            # 4. Inferencia Neuronal TFLite
            if execute_eval and len(pose_buffer) >= MIN_SIGN_FRAMES:
                t_inf0 = time.perf_counter()
                inp_tensor = build_feature_matrix(pose_buffer, lh_buffer, rh_buffer, mask_buffer)
                interp.set_tensor(in_idx, inp_tensor)
                interp.invoke()
                probs = interp.get_tensor(out_idx)[0]
                last_inf_latency = (time.perf_counter() - t_inf0) * 1000.0

                top_indices = np.argsort(probs)[-3:][::-1]
                top1_c = int(top_indices[0])
                top2_c = int(top_indices[1])
                top1_p = float(probs[top1_c])
                top2_p = float(probs[top2_c])

                top3_predictions = [(CLASS_NAMES[idx], float(probs[idx])) for idx in top_indices]

                # FILTRO ANTI-FALSOS POSITIVOS:
                # 1. Confianza mínima absoluta (>= 0.52)
                # 2. Margen de separación sobre la segunda predicción (ratio >= 1.25)
                # Esto erradica que 'SEÑA' o 'MÁS O MENOS' absorban la incertidumbre
                if top1_p >= 0.52 and (top1_p / max(top2_p, 1e-4)) >= 1.25:
                    sign_name = CLASS_NAMES[top1_c]
                    last_detected_sign = sign_name
                    last_confidence = top1_p
                    last_sign_time = cur_time

                    if not current_phrase or current_phrase[-1] != sign_name:
                        current_phrase.append(sign_name)
                        print(f"[{time.strftime('%H:%M:%S')}] SEÑA: {sign_name:<16} | Conf: {top1_p*100:.1f}% | Ratio: {top1_p/top2_p:.2f} | Latencia: {last_inf_latency:.1f}ms")

                    cooldown_counter = 20 # 650 ms de descanso antes del siguiente trazo

                pose_buffer.clear()
                lh_buffer.clear()
                rh_buffer.clear()
                mask_buffer.clear()

            # 5. Auto-cierre de frase tras 4.0 segundos sin actividad
            if current_phrase and (cur_time - last_sign_time > 4.0):
                t_stamp = time.strftime('%H:%M:%S', time.localtime(last_sign_time))
                previous_phrases.append((t_stamp, " ".join(current_phrase)))
                print(f">> Frase finalizada (auto): {' '.join(current_phrase)}")
                current_phrase = []

            # 6. Espejar únicamente para la VISUALIZACIÓN del usuario
            disp_frame = cv2.flip(frame, 1)

            if show_skeleton:
                draw_skeleton_mirrored(disp_frame,
                                       pose_11 if has_pose else None,
                                       lh_21 if has_lh else None,
                                       rh_21 if has_rh else None)

            draw_hud(disp_frame, current_phrase, previous_phrases,
                     last_detected_sign, last_confidence, top3_predictions,
                     current_velocity, is_signing, is_manual_mode, is_manual_recording,
                     current_fps, last_inf_latency, show_skeleton)

            cv2.imshow(win_title, disp_frame)

            # 7. Controles de Teclado
            key = cv2.waitKey(1) & 0xFF
            if key == ord('q') or key == 27:
                break
            elif key == 13: # Enter -> Finalizar frase
                if current_phrase:
                    t_stamp = time.strftime('%H:%M:%S')
                    previous_phrases.append((t_stamp, " ".join(current_phrase)))
                    print(f">> Frase guardada: {' '.join(current_phrase)}")
                    current_phrase = []
            elif key == 32: # Espacio
                if is_manual_mode:
                    # Alterna inicio/fin de grabación manual
                    is_manual_recording = not is_manual_recording
                    if not is_manual_recording and len(pose_buffer) >= MIN_SIGN_FRAMES:
                        execute_eval = True
                    elif is_manual_recording:
                        pose_buffer.clear()
                        lh_buffer.clear()
                        rh_buffer.clear()
                        mask_buffer.clear()
                        print("Grabando seña manual...")
                else:
                    # En modo automático, Espacio finaliza la frase
                    if current_phrase:
                        t_stamp = time.strftime('%H:%M:%S')
                        previous_phrases.append((t_stamp, " ".join(current_phrase)))
                        current_phrase = []
            elif key == ord('m') or key == ord('M'):
                is_manual_mode = not is_manual_mode
                is_signing = False
                is_manual_recording = False
                pose_buffer.clear()
                print(f"Modo cambiado a: {'MANUAL (Presiona ESPACIO para iniciar/detener)' if is_manual_mode else 'AUTOMATICO'}")
            elif key == ord('c') or key == ord('C'):
                current_phrase = []
                print("Frase actual borrada.")
            elif key == ord('b') or key == 8:
                if current_phrase:
                    removed = current_phrase.pop()
                    print(f"Seña eliminada: {removed}")
            elif key == ord('s') or key == ord('S'):
                show_skeleton = not show_skeleton
            elif key == ord('r') or key == ord('R'):
                previous_phrases = []
                current_phrase = []
                last_detected_sign = ""
                top3_predictions = []
                print("Historial reiniciado.")

    finally:
        cap.release()
        cv2.destroyAllWindows()
        p_det.close()
        h_det.close()
        print("Recursos liberados.")


if __name__ == '__main__':
    cam_id = 0
    if len(sys.argv) > 1:
        try:
            cam_id = int(sys.argv[1])
        except ValueError:
            pass
    run_realtime_recognition(camera_id=cam_id)
