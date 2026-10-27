# -*- coding: utf-8 -*-
"""
extract_bimanual_csv.py

Extractor de landmarks bimanuales y torso usando MediaPipe Tasks API.
Diseñado para el dataset LSC (Lengua de Señas Colombiana).

Características principales:
1. Extracción de torso (nariz, hombros, codos, muñecas).
2. Extracción de ambas manos (21 puntos cada una).
3. Desambiguación izquierda/derecha robusta basada en proximidad a muñecas de pose.
4. Doble representación en CSV:
   - Coordenadas de pantalla [0, 1] para renderizar overlays exactos.
   - Coordenadas normalizadas centradas en esternón y muñecas (invariantes a escala/posición para ML/DTW).
5. Detección cinemática del segmento activo (inicio y fin del gesto).
"""

import os
import sys
import json
import time
import cv2
import numpy as np
import pandas as pd
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

# Rutas de modelos preentrenados de MediaPipe Tasks
WORKSPACE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
POSE_MODEL_PATH = os.path.join(WORKSPACE_DIR, 'assets', 'pose_landmarker_lite.task')
HAND_MODEL_PATH = os.path.join(WORKSPACE_DIR, 'assets', 'hand_landmarker.task')

# Índices de pose utilizados para torso y brazos:
# 0: Nariz
# 11: Hombro Izquierdo, 12: Hombro Derecho
# 13: Codo Izquierdo,   14: Codo Derecho
# 15: Muñeca Izquierda, 16: Muñeca Derecha
POSE_NAMES = [
    'nose',
    'left_shoulder', 'right_shoulder',
    'left_elbow', 'right_elbow',
    'left_wrist', 'right_wrist'
]
POSE_RAW_INDICES = [0, 11, 12, 13, 14, 15, 16]


def create_landmarker_detectors(pose_model=POSE_MODEL_PATH, hand_model=HAND_MODEL_PATH):
    """Inicializa detectores de Pose y Manos en modo Video."""
    if not os.path.exists(pose_model):
        raise FileNotFoundError(f"No se encontró el modelo de pose en: {pose_model}")
    if not os.path.exists(hand_model):
        raise FileNotFoundError(f"No se encontró el modelo de manos en: {hand_model}")

    pose_opts = vision.PoseLandmarkerOptions(
        base_options=python.BaseOptions(model_asset_path=pose_model),
        running_mode=vision.RunningMode.VIDEO,
        num_poses=1,
        min_pose_detection_confidence=0.5,
        min_tracking_confidence=0.5
    )
    hand_opts = vision.HandLandmarkerOptions(
        base_options=python.BaseOptions(model_asset_path=hand_model),
        running_mode=vision.RunningMode.VIDEO,
        num_hands=2,
        min_hand_detection_confidence=0.35,
        min_tracking_confidence=0.35
    )
    p_detector = vision.PoseLandmarker.create_from_options(pose_opts)
    h_detector = vision.HandLandmarker.create_from_options(hand_opts)
    return p_detector, h_detector


def compute_active_segment(pose_data, lh_data, rh_data, mask_data):
    """
    Determina el segmento activo del gesto analizando la cinemática de las muñecas
    y la presencia de las manos respecto al torso.
    """
    n_frames = len(pose_data)
    if n_frames < 4:
        return 0, max(0, n_frames - 1)

    # Elevación de muñecas respecto a la altura media de hombros
    # En pose_data: [nose, l_sh(1), r_sh(2), l_el(3), r_el(4), l_wr(5), r_wr(6)]
    sh_y = np.nanmean([pose_data[:, 1, 1], pose_data[:, 2, 1]], axis=0)
    wl_y = pose_data[:, 5, 1]
    wr_y = pose_data[:, 6, 1]

    # Altura relativa mínima (eje Y invertido: menor valor = más arriba hacia la cabeza/pecho)
    min_wrist_y = np.nanmin([wl_y, wr_y], axis=0)
    rel_elevation = min_wrist_y - sh_y  # Valores < 0.25 indican manos elevadas fuera de reposo

    # Velocidad lineal en 2D de muñecas de pose
    vel_l = np.r_[0, np.sqrt(np.diff(np.nan_to_num(pose_data[:, 5, 0]))**2 + np.diff(np.nan_to_num(pose_data[:, 5, 1]))**2)]
    vel_r = np.r_[0, np.sqrt(np.diff(np.nan_to_num(pose_data[:, 6, 0]))**2 + np.diff(np.nan_to_num(pose_data[:, 6, 1]))**2)]
    max_vel = np.maximum(vel_l, vel_r)

    # Presencia detectada de al menos una mano
    hands_present = mask_data[:, 1] | mask_data[:, 2]

    # Criterio activo: manos elevadas Y detectadas, O movimiento cinemático rápido
    is_active_raw = ((rel_elevation < 0.28) & hands_present) | (max_vel > 0.018)

    # Suavizado temporal con ventana móvil de 3 frames
    kernel = np.ones(3) / 3.0
    active_smoothed = np.convolve(is_active_raw.astype(float), kernel, mode='same') >= 0.5

    active_indices = np.where(active_smoothed)[0]
    if len(active_indices) >= 3:
        start_frame = int(max(0, active_indices[0] - 1))
        end_frame = int(min(n_frames - 1, active_indices[-1] + 1))
    else:
        # Respaldo: tercio central del video si la detección de reposo es ambigua
        start_frame = int(n_frames * 0.15)
        end_frame = int(n_frames * 0.85)

    return start_frame, end_frame


def extract_video_landmarks(video_path, p_detector, h_detector):
    """
    Procesa un archivo de video y extrae landmarks de pose y manos en cada fotograma.
    """
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise IOError(f"No se pudo abrir el archivo de video: {video_path}")

    fps = cap.get(cv2.CAP_PROP_FPS)
    if fps <= 0:
        fps = 24.0

    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    pose_list = []      # (N, 7, 4) -> x, y, z, vis
    lh_list = []        # (N, 21, 3) -> x, y, z
    rh_list = []        # (N, 21, 3) -> x, y, z
    mask_list = []      # (N, 3) -> [has_pose, has_lh, has_rh]
    timestamps = []

    fidx = 0
    while True:
        ret, frame = cap.read()
        if not ret:
            break

        t_ms = int(fidx * (1000.0 / fps))
        timestamps.append(t_ms)

        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_img = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)

        p_res = p_detector.detect_for_video(mp_img, t_ms)
        h_res = h_detector.detect_for_video(mp_img, t_ms)

        # 1. Pose
        has_pose = False
        pose_row = np.full((7, 4), np.nan, dtype=np.float32)
        p15_wrist = None
        p16_wrist = None

        if p_res.pose_landmarks and len(p_res.pose_landmarks) > 0:
            has_pose = True
            all_pose = p_res.pose_landmarks[0]
            for out_i, raw_i in enumerate(POSE_RAW_INDICES):
                lm = all_pose[raw_i]
                vis = getattr(lm, 'visibility', 1.0)
                if vis is None:
                    vis = 1.0
                pose_row[out_i] = [lm.x, lm.y, lm.z, vis]

            p15_wrist = np.array([all_pose[15].x, all_pose[15].y])
            p16_wrist = np.array([all_pose[16].x, all_pose[16].y])

        # 2. Manos & Desambiguación L/R
        has_lh = False
        has_rh = False
        lh_row = np.full((21, 3), np.nan, dtype=np.float32)
        rh_row = np.full((21, 3), np.nan, dtype=np.float32)

        det_hands = h_res.hand_landmarks if h_res.hand_landmarks else []

        if len(det_hands) == 2 and p15_wrist is not None and p16_wrist is not None:
            hw0 = np.array([det_hands[0][0].x, det_hands[0][0].y])
            hw1 = np.array([det_hands[1][0].x, det_hands[1][0].y])
            # Costo asignación A (H0->Izq, H1->Der) vs B (H0->Der, H1->Izq)
            cost_A = np.linalg.norm(hw0 - p15_wrist) + np.linalg.norm(hw1 - p16_wrist)
            cost_B = np.linalg.norm(hw0 - p16_wrist) + np.linalg.norm(hw1 - p15_wrist)

            if cost_A <= cost_B:
                lh_hand, rh_hand = det_hands[0], det_hands[1]
            else:
                lh_hand, rh_hand = det_hands[1], det_hands[0]

            has_lh = True
            has_rh = True
            lh_row = np.array([[lm.x, lm.y, lm.z] for lm in lh_hand], dtype=np.float32)
            rh_row = np.array([[lm.x, lm.y, lm.z] for lm in rh_hand], dtype=np.float32)

        elif len(det_hands) == 1 and p15_wrist is not None and p16_wrist is not None:
            hw0 = np.array([det_hands[0][0].x, det_hands[0][0].y])
            d15 = float(np.linalg.norm(hw0 - p15_wrist))
            d16 = float(np.linalg.norm(hw0 - p16_wrist))

            if d15 < d16 and d15 < 0.28:
                has_lh = True
                lh_row = np.array([[lm.x, lm.y, lm.z] for lm in det_hands[0]], dtype=np.float32)
            elif d16 <= d15 and d16 < 0.28:
                has_rh = True
                rh_row = np.array([[lm.x, lm.y, lm.z] for lm in det_hands[0]], dtype=np.float32)

        elif len(det_hands) > 0 and (p15_wrist is None or p16_wrist is None):
            for idx_h, hand in enumerate(det_hands):
                handedness = h_res.handedness[idx_h][0].category_name
                pts = np.array([[lm.x, lm.y, lm.z] for lm in hand], dtype=np.float32)
                if handedness == 'Left' and not has_lh:
                    has_lh = True
                    lh_row = pts
                elif handedness == 'Right' and not has_rh:
                    has_rh = True
                    rh_row = pts

        pose_list.append(pose_row)
        lh_list.append(lh_row)
        rh_list.append(rh_row)
        mask_list.append([has_pose, has_lh, has_rh])

        fidx += 1

    cap.release()

    pose_arr = np.array(pose_list, dtype=np.float32)
    lh_arr = np.array(lh_list, dtype=np.float32)
    rh_arr = np.array(rh_list, dtype=np.float32)
    mask_arr = np.array(mask_list, dtype=bool)

    start_act, end_act = compute_active_segment(pose_arr, lh_arr, rh_arr, mask_arr)

    return {
        'pose': pose_arr,
        'lh': lh_arr,
        'rh': rh_arr,
        'mask': mask_arr,
        'timestamps': timestamps,
        'fps': fps,
        'active_segment': (start_act, end_act),
        'total_frames': fidx
    }


def build_hybrid_csv(extraction_result, output_csv_path):
    """
    Genera un DataFrame y archivo CSV con la representación híbrida completa:
    1. Coordenadas de pantalla [0, 1].
    2. Coordenadas normalizadas invariantes (esternón y muñecas).
    3. Metadatos de actividad y presencia.
    """
    pose = extraction_result['pose']
    lh = extraction_result['lh']
    rh = extraction_result['rh']
    mask = extraction_result['mask']
    timestamps = extraction_result['timestamps']
    start_act, end_act = extraction_result['active_segment']
    n_frames = extraction_result['total_frames']

    rows = []

    for i in range(n_frames):
        row = {}
        row['frame'] = i
        row['timestamp_ms'] = timestamps[i]
        row['is_active'] = 1 if (start_act <= i <= end_act) else 0
        row['has_pose'] = 1 if mask[i, 0] else 0
        row['has_lh'] = 1 if mask[i, 1] else 0
        row['has_rh'] = 1 if mask[i, 2] else 0

        # 1. Coordenadas de pantalla crudas [0, 1]
        for p_idx, p_name in enumerate(POSE_NAMES):
            row[f'torso_{p_name}_x'] = pose[i, p_idx, 0]
            row[f'torso_{p_name}_y'] = pose[i, p_idx, 1]
            row[f'torso_{p_name}_z'] = pose[i, p_idx, 2]
            row[f'torso_{p_name}_vis'] = pose[i, p_idx, 3]

        for k in range(21):
            row[f'lh_{k}_x'] = lh[i, k, 0]
            row[f'lh_{k}_y'] = lh[i, k, 1]
            row[f'lh_{k}_z'] = lh[i, k, 2]

        for k in range(21):
            row[f'rh_{k}_x'] = rh[i, k, 0]
            row[f'rh_{k}_y'] = rh[i, k, 1]
            row[f'rh_{k}_z'] = rh[i, k, 2]

        # 2. Coordenadas normalizadas e invariantes
        # Ancla de torso: punto medio de hombros (11=left_shoulder idx 1, 12=right_shoulder idx 2)
        sh_l = pose[i, 1, :3]
        sh_r = pose[i, 2, :3]

        if not np.isnan(sh_l[0]) and not np.isnan(sh_r[0]):
            torso_center = (sh_l + sh_r) / 2.0
            sh_dist = float(np.linalg.norm(sh_l - sh_r))
            scale_factor = sh_dist if sh_dist > 0.05 else 1.0
        else:
            torso_center = np.array([0.5, 0.5, 0.0], dtype=np.float32)
            scale_factor = 1.0

        row['torso_center_x'] = float(torso_center[0])
        row['torso_center_y'] = float(torso_center[1])
        row['scale_shoulder_dist'] = float(scale_factor)

        # Torso normalizado respecto al esternón
        for p_idx, p_name in enumerate(POSE_NAMES):
            pt = pose[i, p_idx, :3]
            if not np.isnan(pt[0]):
                norm_pt = (pt - torso_center) / scale_factor
                row[f'norm_torso_{p_name}_x'] = float(norm_pt[0])
                row[f'norm_torso_{p_name}_y'] = float(norm_pt[1])
                row[f'norm_torso_{p_name}_z'] = float(norm_pt[2])
            else:
                row[f'norm_torso_{p_name}_x'] = np.nan
                row[f'norm_torso_{p_name}_y'] = np.nan
                row[f'norm_torso_{p_name}_z'] = np.nan

        # Mano izquierda normalizada respecto a su muñeca (landmark 0) y escala de palma
        if mask[i, 1] and not np.isnan(lh[i, 0, 0]):
            lw_pt = lh[i, 0, :3]
            palm_l = float(np.linalg.norm(lh[i, 9, :3] - lw_pt))
            palm_scale_l = palm_l if palm_l > 0.02 else 0.1
            for k in range(21):
                pt = lh[i, k, :3]
                norm_k = (pt - lw_pt) / palm_scale_l
                row[f'norm_lh_{k}_x'] = float(norm_k[0])
                row[f'norm_lh_{k}_y'] = float(norm_k[1])
                row[f'norm_lh_{k}_z'] = float(norm_k[2])
        else:
            for k in range(21):
                row[f'norm_lh_{k}_x'] = np.nan
                row[f'norm_lh_{k}_y'] = np.nan
                row[f'norm_lh_{k}_z'] = np.nan

        # Mano derecha normalizada respecto a su muñeca (landmark 0) y escala de palma
        if mask[i, 2] and not np.isnan(rh[i, 0, 0]):
            rw_pt = rh[i, 0, :3]
            palm_r = float(np.linalg.norm(rh[i, 9, :3] - rw_pt))
            palm_scale_r = palm_r if palm_r > 0.02 else 0.1
            for k in range(21):
                pt = rh[i, k, :3]
                norm_k = (pt - rw_pt) / palm_scale_r
                row[f'norm_rh_{k}_x'] = float(norm_k[0])
                row[f'norm_rh_{k}_y'] = float(norm_k[1])
                row[f'norm_rh_{k}_z'] = float(norm_k[2])
        else:
            for k in range(21):
                row[f'norm_rh_{k}_x'] = np.nan
                row[f'norm_rh_{k}_y'] = np.nan
                row[f'norm_rh_{k}_z'] = np.nan

        rows.append(row)

    df = pd.DataFrame(rows)
    os.makedirs(os.path.dirname(output_csv_path), exist_ok=True)
    df.to_csv(output_csv_path, index=False)
    return df


def process_video_to_csv(video_path, output_dir, p_detector=None, h_detector=None):
    """
    Función de conveniencia para procesar un video individual y guardar su CSV y metadatos.
    """
    close_detectors = False
    if p_detector is None or h_detector is None:
        p_detector, h_detector = create_landmarker_detectors()
        close_detectors = True

    base_name = os.path.splitext(os.path.basename(video_path))[0]
    out_csv = os.path.join(output_dir, 'csv', f'{base_name}.csv')
    out_meta = os.path.join(output_dir, 'csv', f'{base_name}_meta.json')

    res = extract_video_landmarks(video_path, p_detector, h_detector)
    df = build_hybrid_csv(res, out_csv)

    meta = {
        'video_file': os.path.abspath(video_path),
        'base_name': base_name,
        'fps': res['fps'],
        'total_frames': res['total_frames'],
        'active_segment': [int(res['active_segment'][0]), int(res['active_segment'][1])],
        'lh_detection_ratio': float(np.mean(res['mask'][:, 1])),
        'rh_detection_ratio': float(np.mean(res['mask'][:, 2])),
        'pose_detection_ratio': float(np.mean(res['mask'][:, 0]))
    }

    with open(out_meta, 'w', encoding='utf-8') as f:
        json.dump(meta, f, indent=2, ensure_ascii=False)

    if close_detectors:
        p_detector.close()
        h_detector.close()

    return out_csv, meta


if __name__ == '__main__':
    if len(sys.argv) > 1:
        test_video = sys.argv[1]
    else:
        test_video = os.path.join(WORKSPACE_DIR, 'dataset', 'VIDEOS', 'COLOR_BODY', '0000_0000_0000.avi')

    out_folder = os.path.join(os.path.dirname(__file__), 'output')
    print(f"Iniciando extraccion de prueba sobre: {test_video}")
    csv_file, metadata = process_video_to_csv(test_video, out_folder)
    print(f"CSV generado exitosamente: {csv_file}")
    print(f"Metadatos: {metadata}")
