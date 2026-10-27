# -*- coding: utf-8 -*-
"""
realtime_camera_inference.py

Reconocimiento en tiempo real de Lengua de Señas Colombiana (50 Señas LSC)
utilizando la cámara web, MediaPipe Tasks (Pose + Manos) y el modelo neuronal
ultraligero TensorFlow Lite (assets/lsc50_classifier.tflite).

Mapeo de Articulaciones:
- Pose: 11 articulaciones corporales [Nariz, Orejas, Boca, Hombros, Codos, Muñecas] (33 floats)
- Mano Izquierda: 21 puntos articulados (63 floats)
- Mano Derecha: 21 puntos articulados (63 floats)
- Máscaras de presencia: [has_pose, has_lh, has_rh] (3 floats)
- Total: 162 dimensiones por fotograma normalizadas y remuestreadas a T=64.

Funcionalidades en pantalla:
- Muestra en vivo la frase actual detectada ('FRASE ACTUAL').
- Muestra el historial cronológico de frases anteriores ('FRASES ANTERIORES').
- Indicador visual de estado ('ESPERANDO GESTO', 'DETECTANDO GESTO...').
- Ranking Top-3 en tiempo real con barras de confianza.
- Esqueleto dinámico de brazos y manos sobre la imagen de la cámara.
- Controles de teclado:
  [ESPACIO] / [ENTER]: Finalizar frase actual y guardarla en el historial.
  [C]: Limpiar frase actual.
  [B] / [BACKSPACE]: Borrar última seña agregada.
  [S]: Alternar visualización del esqueleto.
  [R]: Reiniciar todo el historial.
  [Q] / [ESC]: Salir.
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

# 11 Articulaciones del cuerpo superior (coincide exactamente con el entrenamiento de Fase 3):
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
    """Inicializa los detectores de Pose y Manos de MediaPipe en modo VIDEO."""
    if not os.path.exists(POSE_MODEL_PATH):
        raise FileNotFoundError(f"No se encontró el modelo de pose en: {POSE_MODEL_PATH}")
    if not os.path.exists(HAND_MODEL_PATH):
        raise FileNotFoundError(f"No se encontró el modelo de manos en: {HAND_MODEL_PATH}")

    pose_opts = vision.PoseLandmarkerOptions(
        base_options=python.BaseOptions(model_asset_path=POSE_MODEL_PATH),
        running_mode=vision.RunningMode.VIDEO,
        num_poses=1,
        min_pose_detection_confidence=0.5,
        min_tracking_confidence=0.5
    )
    hand_opts = vision.HandLandmarkerOptions(
        base_options=python.BaseOptions(model_asset_path=HAND_MODEL_PATH),
        running_mode=vision.RunningMode.VIDEO,
        num_hands=2,
        min_hand_detection_confidence=0.4,
        min_tracking_confidence=0.4
    )

    p_det = vision.PoseLandmarker.create_from_options(pose_opts)
    h_det = vision.HandLandmarker.create_from_options(hand_opts)
    return p_det, h_det


def interpolate_gaps(coords, mask_valid, max_gap=6):
    """Interpola huecos temporales breves donde no se detectó una articulación."""
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
    """Remuestrea uniformemente la secuencia temporal a 64 frames."""
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
    """
    Normaliza y concatena las articulaciones para generar el tensor (1, 64, 162)
    esperado por el clasificador neuronal LSC50.
    """
    pose_arr = np.array(pose_list, dtype=np.float32)   # (N, 11, 3)
    lh_arr = np.array(lh_list, dtype=np.float32)       # (N, 21, 3)
    rh_arr = np.array(rh_list, dtype=np.float32)       # (N, 21, 3)
    mask_arr = np.array(mask_list, dtype=bool)         # (N, 3)

    lh_filled, mask_lh = interpolate_gaps(lh_arr, mask_arr[:, 1], max_gap=6)
    rh_filled, mask_rh = interpolate_gaps(rh_arr, mask_arr[:, 2], max_gap=6)
    pose_coords = np.nan_to_num(pose_arr, 0.0)

    # 1. Normalización por hombros (Hombro Izq: idx 5, Hombro Der: idx 6 en los 11 puntos)
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

    # 2. Normalización de manos respecto al centro del pecho y escala de hombros
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

    # 3. Concatenación plana (33 pose + 63 mano_izq + 63 mano_der + 3 máscaras = 162)
    flat_pose = norm_pose.reshape(len(norm_pose), 11 * 3) # 33
    flat_lh = norm_lh.reshape(len(norm_lh), 21 * 3)       # 63
    flat_rh = norm_rh.reshape(len(norm_rh), 21 * 3)       # 63

    mask_feat = np.column_stack([
        mask_arr[:, 0].astype(np.float32),
        mask_lh.astype(np.float32),
        mask_rh.astype(np.float32)
    ])

    feat_matrix = np.hstack([flat_pose, flat_lh, flat_rh, mask_feat])
    resampled = temporal_resample(feat_matrix, target_len=T_TARGET)
    return np.expand_dims(resampled, axis=0).astype(np.float32)


def draw_hud(frame, current_phrase, previous_phrases, last_sign, last_conf, top3_preds, is_active, fps, latency_ms, show_skeleton):
    """Renderiza una interfaz gráfica HUD elegante directamente sobre el frame."""
    H, W = frame.shape[:2]
    overlay = frame.copy()

    # 1. Barra Superior Translúcida (Título, Estado, FPS y Latencia)
    cv2.rectangle(overlay, (0, 0), (W, 54), (18, 16, 14), -1)
    cv2.addWeighted(overlay, 0.78, frame, 0.22, 0, frame)

    cv2.putText(frame, "LSC-RT : Reconocimiento en Tiempo Real (50 Senas)", (18, 34),
                cv2.FONT_HERSHEY_SIMPLEX, 0.72, (0, 242, 254), 2, cv2.LINE_AA)

    status_text = "DETECTANDO GESTO..." if is_active else "ESPERANDO GESTO"
    status_color = (0, 245, 155) if is_active else (142, 149, 165)
    cv2.circle(frame, (W - 325, 27), 7, status_color, -1)
    cv2.putText(frame, status_text, (W - 310, 34),
                cv2.FONT_HERSHEY_SIMPLEX, 0.52, status_color, 2, cv2.LINE_AA)

    diag_text = f"{fps:.1f} FPS | {latency_ms:.1f} ms"
    cv2.putText(frame, diag_text, (W - 145, 34),
                cv2.FONT_HERSHEY_SIMPLEX, 0.50, (200, 205, 215), 1, cv2.LINE_AA)

    # 2. Panel Lateral Derecho: Top 3 Predicciones
    if top3_preds:
        p_w, p_h = 240, 110
        px, py = W - p_w - 15, 65
        cv2.rectangle(overlay, (px, py), (px + p_w, py + p_h), (22, 24, 30), -1)
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

    # 3. Panel Inferior de Subtítulos y Frases
    pan_h = 170
    cv2.rectangle(overlay, (0, H - pan_h), (W, H), (14, 15, 18), -1)
    cv2.addWeighted(overlay, 0.86, frame, 0.14, 0, frame)
    cv2.line(frame, (0, H - pan_h), (W, H - pan_h), (40, 44, 55), 1)

    # A. Frase Actual en Construcción
    cv2.putText(frame, "FRASE ACTUAL:", (20, H - pan_h + 28),
                cv2.FONT_HERSHEY_SIMPLEX, 0.52, (255, 190, 11), 1, cv2.LINE_AA)

    str_current = " ".join(current_phrase) if current_phrase else "(Realiza una seña frente a la cámara...)"
    col_phrase = (255, 255, 255) if current_phrase else (110, 115, 128)
    cv2.putText(frame, str_current, (20, H - pan_h + 62),
                cv2.FONT_HERSHEY_SIMPLEX, 0.85, col_phrase, 2, cv2.LINE_AA)

    if last_sign:
        sign_badge = f"Última seña: {last_sign} ({last_conf*100:.1f}%)"
        cv2.putText(frame, sign_badge, (W - 380, H - pan_h + 28),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.50, (0, 245, 155), 1, cv2.LINE_AA)

    # B. Historial de Frases Anteriores
    cv2.line(frame, (20, H - 75), (W - 20, H - 75), (30, 33, 42), 1)
    cv2.putText(frame, "FRASES ANTERIORES:", (20, H - 55),
                cv2.FONT_HERSHEY_SIMPLEX, 0.45, (142, 149, 165), 1, cv2.LINE_AA)

    if previous_phrases:
        recent = previous_phrases[-2:]
        disp_prev = "  |  ".join([f"[{t}] {p}" for t, p in recent])
    else:
        disp_prev = "Ninguna frase finalizada aún. Presiona [ESPACIO] para finalizar una frase."

    cv2.putText(frame, disp_prev, (20, H - 28),
                cv2.FONT_HERSHEY_SIMPLEX, 0.52, (180, 185, 198), 1, cv2.LINE_AA)

    # C. Teclas de ayuda en la esquina inferior derecha
    help_keys = "[ESPACIO] Fin Frase | [C] Limpiar | [B] Borrar | [S] Esqueleto | [Q] Salir"
    cv2.putText(frame, help_keys, (W - 550, H - 10),
                cv2.FONT_HERSHEY_SIMPLEX, 0.40, (90, 95, 108), 1, cv2.LINE_AA)


def draw_skeleton(frame, pose_landmarks, lh_landmarks, rh_landmarks):
    """Dibuja los brazos y las manos articuladas sobre la imagen de la cámara."""
    H, W = frame.shape[:2]

    # Manos Articuladas
    # Mano izquierda (dorado)
    if lh_landmarks is not None and not np.isnan(lh_landmarks).all():
        px_pts = [(int(p[0] * W), int(p[1] * H)) for p in lh_landmarks]
        for i1, i2 in HAND_CONNECTIONS:
            cv2.line(frame, px_pts[i1], px_pts[i2], (102, 209, 255), 2, cv2.LINE_AA)
        for pt in px_pts:
            cv2.circle(frame, pt, 3, (154, 226, 255), -1, cv2.LINE_AA)

    # Mano derecha (esmeralda)
    if rh_landmarks is not None and not np.isnan(rh_landmarks).all():
        px_pts = [(int(p[0] * W), int(p[1] * H)) for p in rh_landmarks]
        for i1, i2 in HAND_CONNECTIONS:
            cv2.line(frame, px_pts[i1], px_pts[i2], (155, 245, 0), 2, cv2.LINE_AA)
        for pt in px_pts:
            cv2.circle(frame, pt, 3, (204, 255, 112), -1, cv2.LINE_AA)

    # Brazos (Hombro -> Codo -> Muñeca)
    # En pose_11: 5: hombro izq, 6: hombro der, 7: codo izq, 8: codo der, 9: muñeca izq, 10: muñeca der
    if pose_landmarks is not None and not np.isnan(pose_landmarks).all():
        ls = (int(pose_landmarks[5][0] * W), int(pose_landmarks[5][1] * H))
        rs = (int(pose_landmarks[6][0] * W), int(pose_landmarks[6][1] * H))
        le = (int(pose_landmarks[7][0] * W), int(pose_landmarks[7][1] * H))
        re = (int(pose_landmarks[8][0] * W), int(pose_landmarks[8][1] * H))
        lw = (int(pose_landmarks[9][0] * W), int(pose_landmarks[9][1] * H))
        rw = (int(pose_landmarks[10][0] * W), int(pose_landmarks[10][1] * H))

        cv2.line(frame, ls, rs, (254, 242, 0), 3, cv2.LINE_AA)
        cv2.line(frame, ls, le, (255, 198, 0), 2, cv2.LINE_AA)
        cv2.line(frame, le, lw, (255, 198, 0), 2, cv2.LINE_AA)
        cv2.line(frame, rs, re, (255, 198, 0), 2, cv2.LINE_AA)
        cv2.line(frame, re, rw, (255, 198, 0), 2, cv2.LINE_AA)

        for pt in [ls, rs, le, re, lw, rw]:
            cv2.circle(frame, pt, 5, (254, 172, 79), -1, cv2.LINE_AA)


def run_realtime_recognition(camera_id=0):
    print("=" * 80)
    print(" INICIANDO SISTEMA LSC-RT EN TIEMPO REAL CON CÁMARA")
    print(" (50 Señas Canónicas LSC | TensorFlow Lite | MediaPipe Tasks)")
    print("=" * 80)

    # 1. Cargar intérprete TFLite
    if not os.path.exists(TFLITE_MODEL_PATH):
        raise FileNotFoundError(f"No se encontró el modelo TFLite en: {TFLITE_MODEL_PATH}")

    interp = tf.lite.Interpreter(model_path=TFLITE_MODEL_PATH)
    interp.allocate_tensors()
    in_idx = interp.get_input_details()[0]['index']
    out_idx = interp.get_output_details()[0]['index']
    print("Modelo TensorFlow Lite cargado exitosamente.")

    # 2. Inicializar detectores MediaPipe
    print("Inicializando detectores de Pose y Manos...")
    p_det, h_det = create_mediapipe_detectors()
    print("MediaPipe Tasks listo.")

    # 3. Inicializar Cámara OpenCV
    print(f"Abriendo cámara {camera_id}...")
    cap = cv2.VideoCapture(camera_id, cv2.CAP_DSHOW if sys.platform.startswith('win') else cv2.CAP_ANY)
    if not cap.isOpened():
        print(f"Error: No se pudo abrir la cámara {camera_id}. Intentando cámara 1...")
        cap = cv2.VideoCapture(1)
        if not cap.isOpened():
            raise RuntimeError("No se encontró ninguna cámara disponible en el sistema.")

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
    print("Cámara abierta. Presiona [Q] para salir.\n")

    # Estados de la aplicación
    current_phrase = []
    previous_phrases = []
    last_detected_sign = ""
    last_confidence = 0.0
    top3_predictions = []
    show_skeleton = True

    # Búferes temporales
    MAX_BUFFER = 75
    MIN_SIGN_FRAMES = 14
    pose_buffer = deque(maxlen=MAX_BUFFER)
    lh_buffer = deque(maxlen=MAX_BUFFER)
    rh_buffer = deque(maxlen=MAX_BUFFER)
    mask_buffer = deque(maxlen=MAX_BUFFER)

    is_signing = False
    inactive_counter = 0
    cooldown_counter = 0
    last_sign_time = time.time()
    last_inf_latency = 0.0

    fps_history = deque(maxlen=20)
    prev_time = time.time()
    t_start = time.time()

    cv2.namedWindow("LSC-RT : Reconocimiento en Tiempo Real", cv2.WINDOW_NORMAL)
    cv2.resizeWindow("LSC-RT : Reconocimiento en Tiempo Real", 1280, 720)

    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                print("Error de lectura de fotograma de cámara.")
                break

            # Espejar horizontalmente para experiencia natural de espejo
            frame = cv2.flip(frame, 1)

            cur_time = time.time()
            fps_history.append(1.0 / max(1e-4, cur_time - prev_time))
            prev_time = cur_time
            current_fps = float(np.mean(fps_history))

            t_ms = int((cur_time - t_start) * 1000)
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            mp_img = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)

            # Inferencia MediaPipe en vivo
            p_res = p_det.detect_for_video(mp_img, t_ms)
            h_res = h_det.detect_for_video(mp_img, t_ms)

            # 1. Extraer Pose (11 puntos exactos)
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

                # Muñeca Izquierda (idx 15) y Derecha (idx 16)
                lw_pt = np.array([lm[15].x, lm[15].y])
                rw_pt = np.array([lm[16].x, lm[16].y])

            # 2. Extraer Manos y Asignar por Proximidad a Muñecas
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

            # 3. Detección Cinemática de Actividad Gestual
            frame_is_active = False
            if has_pose and (has_lh or has_rh):
                # Hombros: idx 5 y idx 6
                sh_y = (pose_11[5, 1] + pose_11[6, 1]) / 2.0
                min_w_y = 1.0
                if has_lh:
                    min_w_y = min(min_w_y, pose_11[9, 1])
                if has_rh:
                    min_w_y = min(min_w_y, pose_11[10, 1])

                rel_elev = min_w_y - sh_y
                # Manos elevadas hacia el pecho/cara (rel_elev < 0.24)
                if rel_elev < 0.24:
                    frame_is_active = True

            # Máquina de Estados de Gesto
            if cooldown_counter > 0:
                cooldown_counter -= 1

            if frame_is_active:
                is_signing = True
                inactive_counter = 0
                pose_buffer.append(pose_11)
                lh_buffer.append(lh_21)
                rh_buffer.append(rh_21)
                mask_buffer.append([has_pose, has_lh, has_rh])
            else:
                if is_signing:
                    inactive_counter += 1
                    # Añadir fotogramas de desaceleración
                    pose_buffer.append(pose_11)
                    lh_buffer.append(lh_21)
                    rh_buffer.append(rh_21)
                    mask_buffer.append([has_pose, has_lh, has_rh])

                    # Cuando el usuario baja las manos durante 7 fotogramas (~230 ms):
                    if inactive_counter >= 7:
                        if len(pose_buffer) >= MIN_SIGN_FRAMES and cooldown_counter == 0:
                            # INFERENCIA NEURONAL TFLITE
                            t_inf0 = time.perf_counter()
                            inp_tensor = build_feature_matrix(pose_buffer, lh_buffer, rh_buffer, mask_buffer)
                            interp.set_tensor(in_idx, inp_tensor)
                            interp.invoke()
                            probs = interp.get_tensor(out_idx)[0]
                            last_inf_latency = (time.perf_counter() - t_inf0) * 1000.0

                            top_c = int(np.argmax(probs))
                            top_prob = float(probs[top_c])

                            # Top 3
                            top3_idx = np.argsort(probs)[-3:][::-1]
                            top3_predictions = [(CLASS_NAMES[idx], float(probs[idx])) for idx in top3_idx]

                            # Umbral de confianza
                            if top_prob >= 0.50:
                                sign_name = CLASS_NAMES[top_c]
                                last_detected_sign = sign_name
                                last_confidence = top_prob
                                last_sign_time = cur_time

                                # Evitar duplicados inmediatos
                                if not current_phrase or current_phrase[-1] != sign_name:
                                    current_phrase.append(sign_name)
                                    print(f"[{time.strftime('%H:%M:%S')}] Seña detectada: {sign_name:<16} | Confianza: {top_prob*100:.1f}% | Latencia: {last_inf_latency:.1f}ms")

                                cooldown_counter = 18

                        # Limpiar búfer para la siguiente seña
                        pose_buffer.clear()
                        lh_buffer.clear()
                        rh_buffer.clear()
                        mask_buffer.clear()
                        is_signing = False
                        inactive_counter = 0

            # 4. Auto-cierre de frase por inactividad (> 4.5 segundos)
            if current_phrase and (cur_time - last_sign_time > 4.5):
                t_stamp = time.strftime('%H:%M:%S', time.localtime(last_sign_time))
                previous_phrases.append((t_stamp, " ".join(current_phrase)))
                print(f">> Frase finalizada (auto): {' '.join(current_phrase)}")
                current_phrase = []

            # 5. Renderizado Visual
            if show_skeleton:
                draw_skeleton(frame, pose_11 if has_pose else None,
                              lh_21 if has_lh else None,
                              rh_21 if has_rh else None)

            draw_hud(frame, current_phrase, previous_phrases,
                     last_detected_sign, last_confidence, top3_predictions,
                     is_signing, current_fps, last_inf_latency, show_skeleton)

            cv2.imshow("LSC-RT : Reconocimiento en Tiempo Real", frame)

            # 6. Manejo de Teclado Interactivo
            key = cv2.waitKey(1) & 0xFF
            if key == ord('q') or key == 27: # Q o ESC
                print("\nCerrando sistema por usuario.")
                break
            elif key == 32 or key == 13: # Espacio o Enter -> Finalizar frase
                if current_phrase:
                    t_stamp = time.strftime('%H:%M:%S')
                    previous_phrases.append((t_stamp, " ".join(current_phrase)))
                    print(f">> Frase guardada manualmente: {' '.join(current_phrase)}")
                    current_phrase = []
            elif key == ord('c') or key == ord('C'): # Limpiar frase actual
                current_phrase = []
                print("Frase actual borrada.")
            elif key == ord('b') or key == 8: # Backspace -> Borrar última seña
                if current_phrase:
                    removed = current_phrase.pop()
                    print(f"Seña eliminada: {removed}")
            elif key == ord('s') or key == ord('S'): # Alternar esqueleto
                show_skeleton = not show_skeleton
                print(f"Esqueleto visible: {show_skeleton}")
            elif key == ord('r') or key == ord('R'): # Reiniciar historial
                previous_phrases = []
                current_phrase = []
                last_detected_sign = ""
                top3_predictions = []
                print("Historial reiniciado por completo.")

    finally:
        cap.release()
        cv2.destroyAllWindows()
        p_det.close()
        h_det.close()
        print("Recursos de cámara y MediaPipe liberados correctamente.")


if __name__ == '__main__':
    cam_id = 0
    if len(sys.argv) > 1:
        try:
            cam_id = int(sys.argv[1])
        except ValueError:
            pass
    run_realtime_recognition(camera_id=cam_id)
