# -*- coding: utf-8 -*-
"""
fix_natural_onset_synthesis.py

Implementa la solución propuesta por el usuario:
'A la mezcla universal se le busca el más cercano y se adapta a ese inicio'.

Arquitectura del Inicio Natural Anclado al Medoide:
1. Para cada seña, calcula la 'mezcla universal' multiseñante M_bar.
2. Identifica la toma real más cercana T* (medoide con menor distancia L2/DTW a M_bar).
3. Adapta el inicio de la seña (t=0..t_onset) anclándolo a la postura anatómica real de T*,
   transicionando suavemente hacia la mezcla universal en el ápex semántico.
4. Anclaje estricto de muñeca:
   Hand[0] == Torso_Wrist en el 100% de los fotogramas (garantiza cero desprendimiento de manos).
5. Postura de reposo neutral natural basada en la anatomía de T* (no en mallas sintéticas artificiales).
"""

import os
import sys
import glob
import json
import time
import cv2
import numpy as np
import pandas as pd
from scipy.interpolate import PchipInterpolator, interp1d
from scipy.signal import savgol_filter
from scipy.stats import trim_mean

WORKSPACE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
NPZ_DIR = os.path.join(WORKSPACE_DIR, 'dataset', 'PROCESSED_NPZ')
MASTER_OUT_DIR = os.path.join(os.path.dirname(__file__), 'output', 'master_csv')
AVATAR_OUT_DIR = os.path.join(os.path.dirname(__file__), 'output', 'avatar')

POSE_INDICES_MAP = [0, 5, 6, 7, 8, 9, 10]
POSE_NAMES = ['nose', 'left_shoulder', 'right_shoulder', 'left_elbow', 'right_elbow', 'left_wrist', 'right_wrist']

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

CATEGORIES = {
    "GRACIAS": "Cortesía", "BUENOS DÍAS": "Saludos", "BUENAS TARDES": "Saludos", "BUENAS NOCHES": "Saludos",
    "SEÑA": "Vocabulario", "NOMBRE": "Identidad", "TRABAJAR": "Acciones", "COMER": "Acciones", "VIVIR": "Acciones",
    "POCO": "Cuantificadores", "FAMILIA": "Familia", "PERSONAS": "Personas", "MUJER": "Personas", "HOMBRE": "Personas",
    "NIÑO": "Familia", "NIÑA": "Familia", "ABUELO": "Familia", "TÍO": "Familia", "HERMANO": "Familia",
    "HAMBRE": "Estados", "FELIZ": "Emociones", "CONTENTO": "Emociones", "TRISTE": "Emociones", "ABURRIDO": "Emociones",
    "BIEN": "Estados", "MAL": "Estados", "¿CÓMO ESTÁS?": "Preguntas", "MÁS O MENOS": "Estados", "SENTIR": "Emociones",
    "JUICIOSO": "Estados", "HOLA": "Saludos", "ADIÓS": "Saludos", "POR FAVOR": "Cortesía", "CON GUSTO": "Cortesía",
    "BIENVENIDO": "Saludos", "PERDÓN": "Cortesía", "PERMISO": "Cortesía", "NUNCA": "Modales", "YO": "Pronombres",
    "TÚ": "Pronombres", "USTEDES": "Pronombres", "¿QUÉ?": "Preguntas", "¿CUÁNDO?": "Preguntas", "¿DÓNDE?": "Preguntas",
    "¿CÓMO?": "Preguntas", "¿POR QUÉ?": "Preguntas", "¿QUIÉN?": "Preguntas", "DIFERENTE": "Modales", "TODOS": "Pronombres",
    "MUCHO": "Cuantificadores"
}


def infill_hand_anatomical(hand_arr, has_hand_mask, pose_wrist):
    """
    Rellena manos ocluidas preservando la anatomía de los 21 puntos
    y anclando Landmark 0 estrictamente a la muñeca de pose.
    """
    n_frames = len(hand_arr)
    valid_frames = np.where(has_hand_mask)[0]

    # Interpolar huecos en muñeca de pose si existiesen
    for c in range(3):
        col = pose_wrist[:, c]
        nans = np.isnan(col)
        if np.any(nans):
            x = np.arange(n_frames)
            col[nans] = np.interp(x[nans], x[~nans], col[~nans])
            pose_wrist[:, c] = col

    # Postura anatómica de respaldo si nunca se detectó la mano
    if len(valid_frames) == 0:
        out_hand = np.zeros((n_frames, 21, 3), dtype=np.float32)
        for i in range(n_frames):
            w = pose_wrist[i]
            out_hand[i, 0] = w
            for k in range(1, 21):
                # Desplazamiento anatómico natural hacia abajo y afuera
                finger_idx = (k - 1) // 4
                joint_idx = (k - 1) % 4
                dx = 0.01 * (finger_idx - 2)
                dy = 0.015 * (joint_idx + 1)
                out_hand[i, k] = [w[0] + dx, w[1] + dy, w[2]]
        return out_hand

    # Extraer forma dactilar relativa a la muñeca
    valid_hands = hand_arr[valid_frames]
    valid_wrist = valid_hands[:, 0:1, :]
    rel_shapes = valid_hands - valid_wrist  # (V, 21, 3)

    infilled_shapes = np.zeros((n_frames, 21, 3), dtype=np.float32)
    for k in range(21):
        for c in range(3):
            val_col = rel_shapes[:, k, c]
            if len(valid_frames) == 1:
                infilled_shapes[:, k, c] = val_col[0]
            else:
                f_interp = interp1d(valid_frames, val_col, kind='linear', fill_value='extrapolate')
                infilled_shapes[:, k, c] = f_interp(np.arange(n_frames))

    out_hand = np.zeros((n_frames, 21, 3), dtype=np.float32)
    for i in range(n_frames):
        # Bloquear muñeca de mano estrictamente a la muñeca de pose
        w_pose = pose_wrist[i]
        out_hand[i, 0] = w_pose
        for k in range(1, 21):
            out_hand[i, k] = w_pose + infilled_shapes[i, k]

    return out_hand


def process_npz_take(npz_path):
    d = np.load(npz_path)
    pose_raw = d['pose']
    lh_raw = d['mano_izquierda']
    rh_raw = d['mano_derecha']
    mask = d['mask']
    act = d['active_segment']

    n_frames = len(pose_raw)
    start_act = int(act[0])
    end_act = int(act[1])
    if end_act <= start_act + 5 or end_act >= n_frames:
        start_act = int(n_frames * 0.15)
        end_act = int(n_frames * 0.85)

    p_act = pose_raw[start_act:end_act + 1]
    lh_act = lh_raw[start_act:end_act + 1]
    rh_act = rh_raw[start_act:end_act + 1]
    m_act = mask[start_act:end_act + 1]
    n_act = len(p_act)

    torso_act = np.zeros((n_act, 7, 3), dtype=np.float32)
    for i_out, i_src in enumerate(POSE_INDICES_MAP):
        for c in range(3):
            col = p_act[:, i_src, c]
            nans = np.isnan(col)
            if np.any(nans):
                x = np.arange(n_act)
                col[nans] = np.interp(x[nans], x[~nans], col[~nans])
            torso_act[:, i_out, c] = col

    lw_pose = torso_act[:, 5]
    rw_pose = torso_act[:, 6]
    lh_inf = infill_hand_anatomical(lh_act, m_act[:, 1], lw_pose)
    rh_inf = infill_hand_anatomical(rh_act, m_act[:, 2], rw_pose)

    lh_disp = float(np.ptp(lh_inf[:, 0, 1]))
    rh_disp = float(np.ptp(rh_inf[:, 0, 1]))
    is_bimanual = (lh_disp > 0.08 and rh_disp > 0.08)

    if not is_bimanual:
        if lh_disp > rh_disp:
            # Espejar a diestro
            torso_act[:, :, 0] = 1.0 - torso_act[:, :, 0]
            torso_act[:, [1, 2]] = torso_act[:, [2, 1]]
            torso_act[:, [3, 4]] = torso_act[:, [4, 3]]
            torso_act[:, [5, 6]] = torso_act[:, [6, 5]]
            lh_inf[:, :, 0] = 1.0 - lh_inf[:, :, 0]
            rh_inf[:, :, 0] = 1.0 - rh_inf[:, :, 0]
            final_lh = rh_inf
            final_rh = lh_inf
        else:
            final_lh = lh_inf
            final_rh = rh_inf
    else:
        final_lh = lh_inf
        final_rh = rh_inf

    # Postura de reposo previa real del señante (si existe)
    rest_torso = torso_act[0].copy()
    rest_lh = final_lh[0].copy()
    rest_rh = final_rh[0].copy()

    if start_act > 2:
        p_pre = pose_raw[:start_act]
        t_pre = np.zeros((len(p_pre), 7, 3), dtype=np.float32)
        for i_out, i_src in enumerate(POSE_INDICES_MAP):
            for c in range(3):
                col = p_pre[:, i_src, c]
                t_pre[:, i_out, c] = np.nan_to_num(col, rest_torso[i_out, c])
        rest_torso = t_pre[0]

    return {
        'file': os.path.basename(npz_path),
        'n_frames': n_act,
        'torso': torso_act,
        'lh': final_lh,
        'rh': final_rh,
        'rest_torso': rest_torso,
        'rest_lh': rest_lh,
        'rest_rh': rest_rh,
        'is_bimanual': is_bimanual
    }


def resample_take(take_dict, target_frames=60):
    orig_n = take_dict['n_frames']
    t_orig = np.linspace(0.0, 1.0, orig_n)
    t_target = np.linspace(0.0, 1.0, target_frames)

    def resample_arr(arr):
        j_count = arr.shape[1]
        out = np.zeros((target_frames, j_count, 3), dtype=np.float32)
        for j in range(j_count):
            for c in range(3):
                col = arr[:, j, c]
                if orig_n < 4:
                    f = interp1d(t_orig, col, kind='linear')
                else:
                    f = PchipInterpolator(t_orig, col)
                out[:, j, c] = f(t_target)
        return out

    return {
        'file': take_dict['file'],
        'torso': resample_arr(take_dict['torso']),
        'lh': resample_arr(take_dict['lh']),
        'rh': resample_arr(take_dict['rh']),
        'rest_torso': take_dict['rest_torso'],
        'rest_lh': take_dict['rest_lh'],
        'rest_rh': take_dict['rest_rh'],
        'is_bimanual': take_dict['is_bimanual']
    }


def build_adapted_master(class_id):
    c_idx = int(class_id)
    sign_name = CLASS_NAMES[c_idx]
    pattern = os.path.join(NPZ_DIR, f"{class_id}_*.npz")
    npz_files = sorted(glob.glob(pattern))

    takes = [process_npz_take(f) for f in npz_files]
    TARGET_FRAMES = 60
    resampled = [resample_take(t, target_frames=TARGET_FRAMES) for t in takes]

    K = len(resampled)
    torso_stack = np.array([r['torso'] for r in resampled])
    lh_stack = np.array([r['lh'] for r in resampled])
    rh_stack = np.array([r['rh'] for r in resampled])

    # 1. Calcular la 'Mezcla Universal' (Trimmed Mean 20%)
    universal_torso = np.zeros((TARGET_FRAMES, 7, 3), dtype=np.float32)
    universal_lh = np.zeros((TARGET_FRAMES, 21, 3), dtype=np.float32)
    universal_rh = np.zeros((TARGET_FRAMES, 21, 3), dtype=np.float32)

    for t in range(TARGET_FRAMES):
        for j in range(7):
            for c in range(3):
                universal_torso[t, j, c] = trim_mean(torso_stack[:, t, j, c], 0.2)
        for j in range(21):
            for c in range(3):
                universal_lh[t, j, c] = trim_mean(lh_stack[:, t, j, c], 0.2)
                universal_rh[t, j, c] = trim_mean(rh_stack[:, t, j, c], 0.2)

    # 2. Identificar la toma real más cercana (Medoide T*)
    # Comparar la distancia euclidiana total a la mezcla universal
    feat_universal = np.hstack([universal_torso.reshape(60, -1), universal_lh.reshape(60, -1), universal_rh.reshape(60, -1)])
    dists = []
    for k in range(K):
        f_k = np.hstack([resampled[k]['torso'].reshape(60, -1), resampled[k]['lh'].reshape(60, -1), resampled[k]['rh'].reshape(60, -1)])
        d = float(np.mean(np.linalg.norm(f_k - feat_universal, axis=1)))
        dists.append((k, d))

    dists.sort(key=lambda x: x[1])
    best_k, best_dist = dists[0]
    medoid_take = resampled[best_k]

    # 3. Localizar el Ápex en la mezcla universal
    disp = np.linalg.norm(universal_rh[:, 0, :2] - universal_rh[0, 0, :2], axis=1)
    apex_idx = int(np.argmax(disp))
    if apex_idx < 15:
        apex_idx = 30  # Centro seguro si el desplazamiento es sutil

    # 4. Fusión adaptativa: Inicio de T* -> Transición suave hacia Mezcla Universal en el Ápex
    # Peso w_univ(t) que inicia en 0.0 en t=0 (toma pura real) y llega a 1.0 en el ápex
    adapted_torso = np.zeros_like(universal_torso)
    adapted_lh = np.zeros_like(universal_lh)
    adapted_rh = np.zeros_like(universal_rh)

    for t in range(TARGET_FRAMES):
        if t <= apex_idx:
            # Curva suave ease-in-out hacia el ápex
            alpha = t / float(max(1, apex_idx))
            w = alpha * alpha * (3.0 - 2.0 * alpha)
        else:
            # Desde el ápex hasta el final, mantener la mezcla universal consolidada
            w = 1.0

        adapted_torso[t] = (1.0 - w) * medoid_take['torso'][t] + w * universal_torso[t]
        adapted_lh[t] = (1.0 - w) * medoid_take['lh'][t] + w * universal_lh[t]
        adapted_rh[t] = (1.0 - w) * medoid_take['rh'][t] + w * universal_rh[t]

        # Bloqueo estricto: Muñeca de mano 0 == Muñeca de torso
        adapted_lh[t, 0] = adapted_torso[t, 5]
        adapted_rh[t, 0] = adapted_torso[t, 6]

    # Suavizado cinemático Savitzky-Golay
    def apply_savgol(arr):
        res = np.zeros_like(arr)
        for j in range(arr.shape[1]):
            for c in range(arr.shape[2]):
                res[:, j, c] = savgol_filter(arr[:, j, c], window_length=7, polyorder=2)
        return res

    adapted_torso = apply_savgol(adapted_torso)
    adapted_lh = apply_savgol(adapted_lh)
    adapted_rh = apply_savgol(adapted_rh)

    # Re-asegurar coincidencia de muñecas tras el filtro
    for t in range(TARGET_FRAMES):
        adapted_lh[t, 0] = adapted_torso[t, 5]
        adapted_rh[t, 0] = adapted_torso[t, 6]

    # 5. Fases de Reposo Neutral Natural (Ancladas a la postura real de reposo de T*)
    PAD_FRAMES = 12
    TOTAL_FRAMES = PAD_FRAMES + TARGET_FRAMES + PAD_FRAMES

    # La postura de reposo neutral proviene de la anatomía real de T*
    real_rest_torso = medoid_take['rest_torso']
    # Los brazos en reposo descienden suavemente desde los hombros
    natural_rest_torso = real_rest_torso.copy()
    natural_rest_torso[5] = [natural_rest_torso[1, 0] + 0.02, natural_rest_torso[1, 1] + 0.35, 0.0]  # Muñeca izq
    natural_rest_torso[6] = [natural_rest_torso[2, 0] - 0.02, natural_rest_torso[2, 1] + 0.35, 0.0]  # Muñeca der
    natural_rest_torso[3] = [natural_rest_torso[1, 0] + 0.04, natural_rest_torso[1, 1] + 0.18, 0.0]  # Codo izq
    natural_rest_torso[4] = [natural_rest_torso[2, 0] - 0.04, natural_rest_torso[2, 1] + 0.18, 0.0]  # Codo der

    # Manos de reposo ancladas a las muñecas con la forma dactilar de inicio de T*
    shape_lh_start = medoid_take['lh'][0] - medoid_take['lh'][0, 0:1]
    shape_rh_start = medoid_take['rh'][0] - medoid_take['rh'][0, 0:1]

    natural_rest_lh = natural_rest_torso[5] + shape_lh_start
    natural_rest_rh = natural_rest_torso[6] + shape_rh_start

    full_torso = np.zeros((TOTAL_FRAMES, 7, 3), dtype=np.float32)
    full_lh = np.zeros((TOTAL_FRAMES, 21, 3), dtype=np.float32)
    full_rh = np.zeros((TOTAL_FRAMES, 21, 3), dtype=np.float32)
    is_active_flags = np.zeros(TOTAL_FRAMES, dtype=np.int32)

    # Transición de entrada (Hermite suave desde reposo natural hacia el inicio real de T*)
    for i in range(PAD_FRAMES):
        alpha = i / float(PAD_FRAMES)
        w = alpha * alpha * (3.0 - 2.0 * alpha)
        full_torso[i] = (1.0 - w) * natural_rest_torso + w * adapted_torso[0]
        full_lh[i] = (1.0 - w) * natural_rest_lh + w * adapted_lh[0]
        full_rh[i] = (1.0 - w) * natural_rest_rh + w * adapted_rh[0]
        # Asegurar muñecas
        full_lh[i, 0] = full_torso[i, 5]
        full_rh[i, 0] = full_torso[i, 6]
        is_active_flags[i] = 0

    # Segmento Activo Adaptado
    for i in range(TARGET_FRAMES):
        idx = PAD_FRAMES + i
        full_torso[idx] = adapted_torso[i]
        full_lh[idx] = adapted_lh[i]
        full_rh[idx] = adapted_rh[i]
        is_active_flags[idx] = 1

    # Transición de salida (Retorno suave a reposo natural)
    for i in range(PAD_FRAMES):
        alpha = (i + 1) / float(PAD_FRAMES)
        w = alpha * alpha * (3.0 - 2.0 * alpha)
        idx = PAD_FRAMES + TARGET_FRAMES + i
        full_torso[idx] = (1.0 - w) * adapted_torso[-1] + w * natural_rest_torso
        full_lh[idx] = (1.0 - w) * adapted_lh[-1] + w * natural_rest_lh
        full_rh[idx] = (1.0 - w) * adapted_rh[-1] + w * natural_rest_rh
        full_lh[idx, 0] = full_torso[idx, 5]
        full_rh[idx, 0] = full_torso[idx, 6]
        is_active_flags[idx] = 0

    # Construir DataFrame de 310 columnas
    master_rows = []
    fps = 30.0

    for i in range(TOTAL_FRAMES):
        row = {}
        row['frame'] = i
        row['timestamp_ms'] = int(i * (1000.0 / fps))
        row['is_active'] = int(is_active_flags[i])
        row['has_pose'] = 1
        row['has_lh'] = 1
        row['has_rh'] = 1

        for p_idx, p_name in enumerate(POSE_NAMES):
            row[f'torso_{p_name}_x'] = round(float(full_torso[i, p_idx, 0]), 4)
            row[f'torso_{p_name}_y'] = round(float(full_torso[i, p_idx, 1]), 4)
            row[f'torso_{p_name}_z'] = round(float(full_torso[i, p_idx, 2]), 4)
            row[f'torso_{p_name}_vis'] = 1.0

        for k in range(21):
            row[f'lh_{k}_x'] = round(float(full_lh[i, k, 0]), 4)
            row[f'lh_{k}_y'] = round(float(full_lh[i, k, 1]), 4)
            row[f'lh_{k}_z'] = round(float(full_lh[i, k, 2]), 4)

        for k in range(21):
            row[f'rh_{k}_x'] = round(float(full_rh[i, k, 0]), 4)
            row[f'rh_{k}_y'] = round(float(full_rh[i, k, 1]), 4)
            row[f'rh_{k}_z'] = round(float(full_rh[i, k, 2]), 4)

        sh_l = full_torso[i, 1]
        sh_r = full_torso[i, 2]
        torso_center = (sh_l + sh_r) / 2.0
        sh_dist = float(np.linalg.norm(sh_l - sh_r))
        scale_factor = sh_dist if sh_dist > 0.05 else 1.0

        row['torso_center_x'] = round(float(torso_center[0]), 4)
        row['torso_center_y'] = round(float(torso_center[1]), 4)
        row['scale_shoulder_dist'] = round(float(scale_factor), 4)

        for p_idx, p_name in enumerate(POSE_NAMES):
            norm_pt = (full_torso[i, p_idx] - torso_center) / scale_factor
            row[f'norm_torso_{p_name}_x'] = round(float(norm_pt[0]), 4)
            row[f'norm_torso_{p_name}_y'] = round(float(norm_pt[1]), 4)
            row[f'norm_torso_{p_name}_z'] = round(float(norm_pt[2]), 4)

        lw_pt = full_lh[i, 0]
        palm_l = float(np.linalg.norm(full_lh[i, 9] - lw_pt))
        palm_scale_l = palm_l if palm_l > 0.02 else 0.1
        for k in range(21):
            norm_k = (full_lh[i, k] - lw_pt) / palm_scale_l
            row[f'norm_lh_{k}_x'] = round(float(norm_k[0]), 4)
            row[f'norm_lh_{k}_y'] = round(float(norm_k[1]), 4)
            row[f'norm_lh_{k}_z'] = round(float(norm_k[2]), 4)

        rw_pt = full_rh[i, 0]
        palm_r = float(np.linalg.norm(full_rh[i, 9] - rw_pt))
        palm_scale_r = palm_r if palm_r > 0.02 else 0.1
        for k in range(21):
            norm_k = (full_rh[i, k] - rw_pt) / palm_scale_r
            row[f'norm_rh_{k}_x'] = round(float(norm_k[0]), 4)
            row[f'norm_rh_{k}_y'] = round(float(norm_k[1]), 4)
            row[f'norm_rh_{k}_z'] = round(float(norm_k[2]), 4)

        master_rows.append(row)

    master_df = pd.DataFrame(master_rows)
    master_csv_path = os.path.join(MASTER_OUT_DIR, f"{class_id}_master.csv")
    master_df.to_csv(master_csv_path, index=False)

    clean_id = sign_name.lower().replace(' ', '_').replace('¿', '').replace('?', '').replace('á', 'a').replace('é', 'e').replace('í', 'i').replace('ó', 'o').replace('ú', 'u')
    is_bim = bool(takes[0]['is_bimanual'])

    master_meta = {
        'class_id': class_id,
        'sign_name': sign_name,
        'sign_id': clean_id,
        'category': CATEGORIES.get(sign_name, 'General'),
        'type': 'bimanual' if is_bim else 'unimanual',
        'takes_fused': K,
        'canonical_frames': TOTAL_FRAMES,
        'active_segment': [PAD_FRAMES, PAD_FRAMES + TARGET_FRAMES - 1],
        'apex_frame': PAD_FRAMES + apex_idx,
        'fps': fps,
        'closest_real_take': medoid_take['file'],
        'medoid_distance_to_universal': round(best_dist, 6),
        'hand_presence_ratio': 1.0,
        'wrist_hand_detachment_max_dist': 0.0,
        'methodology': 'Medoid-Guided Natural Onset + Universal Apex Consensus + Strict Wrist Locking'
    }

    meta_path = os.path.join(MASTER_OUT_DIR, f"{class_id}_master_meta.json")
    with open(meta_path, 'w', encoding='utf-8') as f:
        json.dump(master_meta, f, indent=2, ensure_ascii=False)

    frames_avatar = []
    for i in range(TOTAL_FRAMES):
        f_data = {
            'frame_idx': i,
            'torso': {p_name: [round(float(full_torso[i, p_idx, c]), 4) for c in range(3)] for p_idx, p_name in enumerate(POSE_NAMES)},
            'left_hand': [[round(float(full_lh[i, k, c]), 4) for c in range(3)] for k in range(21)],
            'right_hand': [[round(float(full_rh[i, k, c]), 4) for c in range(3)] for k in range(21)]
        }
        frames_avatar.append(f_data)

    sign_dict = {
        'id': clean_id,
        'sign_id': clean_id,
        'display_name': sign_name,
        'class_code': class_id,
        'category': CATEGORIES.get(sign_name, 'General'),
        'type': 'bimanual' if is_bim else 'unimanual',
        'total_frames': TOTAL_FRAMES,
        'total_active_frames': TARGET_FRAMES,
        'fps': fps,
        'duration_seconds': round(TOTAL_FRAMES / fps, 2),
        'apex_frame': PAD_FRAMES + apex_idx,
        'pedagogical_metadata': {
            'instructions': f"Gesto {'bimanual' if is_bim else 'con mano dominante'}. Inicio natural anclado al ejemplar más representativo ({medoid_take['file']}) y sincronizado al ápex.",
            'apex_description': 'Punto crucial de máxima expresión del signo en LSC',
            'key_hand': 'both' if is_bim else 'right',
            'milestones': {
                'start_frame': PAD_FRAMES,
                'apex_frame': PAD_FRAMES + apex_idx,
                'end_frame': PAD_FRAMES + TARGET_FRAMES - 1
            }
        },
        'phases': {
            'neutral_prep': [0, PAD_FRAMES - 1],
            'active_sign': [PAD_FRAMES, PAD_FRAMES + TARGET_FRAMES - 1],
            'apex_frame': PAD_FRAMES + apex_idx,
            'neutral_recovery': [PAD_FRAMES + TARGET_FRAMES, TOTAL_FRAMES - 1]
        },
        'frames': frames_avatar
    }

    return clean_id, sign_dict, medoid_take['file'], best_dist


def run_all():
    print("=" * 80)
    print(" RE-SÍNTESIS CON INICIO NATURAL ANCLADO AL MEDOIDE (50 SEÑAS LSC)")
    print(" Adaptando el inicio de la mezcla universal al ejemplar real más cercano")
    print("=" * 80)
    t0 = time.time()
    motion_bank = {}

    for c_idx in range(50):
        class_id = f"{c_idx:04d}"
        t_start = time.time()
        clean_id, sign_dict, medoid_file, dist = build_adapted_master(class_id)
        motion_bank[clean_id] = sign_dict
        el = time.time() - t_start
        print(f"[{class_id}] {sign_dict['display_name']:<20} | Medoide: {medoid_file:<20} | Dist: {dist:.4f} | {el:.2f}s")

    # Guardar Motion Bank
    bank_path = os.path.join(AVATAR_OUT_DIR, 'lsc_motion_bank.json')
    with open(bank_path, 'w', encoding='utf-8') as f:
        json.dump(motion_bank, f, indent=2, ensure_ascii=False)

    print("\n" + "=" * 80)
    print(f" RE-SÍNTESIS COMPLETADA EXITOSAMENTE EN {time.time()-t0:.2f} s")
    print(f" Banco guardado en: {bank_path}")
    print("=" * 80)


if __name__ == '__main__':
    run_all()
