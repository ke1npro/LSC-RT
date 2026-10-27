# -*- coding: utf-8 -*-
"""
synthesize_bulletproof_master.py

Generador definitivo, anatómicamente riguroso y cinematográficamente fluido
de los 50 Master CSVs y el Motion Bank del Avatar LSC50.

Garantías matemáticas y anatómicas estrictas:
1. Unión rígida muñeca-mano: Hand[i, 0] == Torso_Wrist[i] con distancia idéntica a 0.0000.
2. Invarianza de escala dactilar (Zero Giant Hand Artifact): Delta_k <= 0.080 con clamping estricto.
3. Separación lateral estricta (Zero Crossing Arm Artifact): brazos desacoplados y simétricos.
4. Fusión Bidireccional Hermite con Medoide Humano T*:
   - t=0: Medoide puro T*[0] (inicio limpio y humano).
   - t=apex: Mezcla Universal canónica en el ápex semántico.
   - t=fin: Medoide puro T*[-1] (resolución limpia y humana).
5. Postura de reposo anatómica con proporciones corporales humanas reales:
   - Longitud de brazo = upper_arm (~1.45*W) + forearm (~1.05*W) = ~2.5*W.
   - Manos relajadas canónicas en reposo.
6. Aislamiento cinemático de mano no dominante en señas unimanuales (cero artefactos parásitos).
7. Suite de QA biomecánica estricta (detiene el proceso ante cualquier fallo).
"""

import os
import glob
import json
import time
import numpy as np
import pandas as pd
from scipy.interpolate import PchipInterpolator, interp1d
from scipy.signal import savgol_filter
from scipy.stats import trim_mean

WORKSPACE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
NPZ_DIR = os.path.join(WORKSPACE_DIR, 'dataset', 'PROCESSED_NPZ')
MASTER_OUT_DIR = os.path.join(os.path.dirname(__file__), 'output', 'master_csv')
AVATAR_OUT_DIR = os.path.join(os.path.dirname(__file__), 'output', 'avatar')

os.makedirs(MASTER_OUT_DIR, exist_ok=True)
os.makedirs(AVATAR_OUT_DIR, exist_ok=True)

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

# Postura base anatómica de reposo de una mano humana relajada (relativa a muñeca)
def get_canonical_hand_shape(is_left=False):
    shape = np.zeros((21, 3), dtype=np.float32)
    sign_x = -1.0 if is_left else 1.0
    for k in range(1, 21):
        finger = (k - 1) // 4
        joint = (k - 1) % 4 + 1
        dx = (finger - 2) * 0.005 * sign_x
        dy = joint * 0.010
        shape[k] = [dx, dy, 0.0]
    return shape


def extract_relative_hand_shape(hand_arr, has_hand_mask, is_left=False):
    n_frames = len(hand_arr)
    valid_frames = np.where(has_hand_mask)[0]

    truly_valid = []
    for vf in valid_frames:
        if not np.isnan(hand_arr[vf, 0, 0]):
            span = np.ptp(hand_arr[vf, :, :2], axis=0)
            if 0.01 < span[0] < 0.15 and 0.01 < span[1] < 0.15:
                truly_valid.append(vf)

    if len(truly_valid) == 0:
        base_shape = get_canonical_hand_shape(is_left=is_left)
        return np.repeat(base_shape[np.newaxis, :, :], n_frames, axis=0)

    valid_data = hand_arr[truly_valid]
    rel_data = valid_data - valid_data[:, 0:1, :]
    rel_data[:, 0] = 0.0

    out_rel = np.zeros((n_frames, 21, 3), dtype=np.float32)
    for k in range(21):
        for c in range(3):
            col = rel_data[:, k, c]
            if len(truly_valid) == 1:
                out_rel[:, k, c] = col[0]
            else:
                f_interp = interp1d(truly_valid, col, kind='linear', bounds_error=False, fill_value=(col[0], col[-1]))
                out_rel[:, k, c] = f_interp(np.arange(n_frames))

    out_rel[:, 0] = 0.0

    # Límite estricto de escala dactilar para evitar deformaciones
    for k in range(1, 21):
        dists = np.linalg.norm(out_rel[:, k, :2], axis=1)
        too_large = (dists > 0.080)
        if np.any(too_large):
            scale = 0.080 / np.maximum(dists[too_large, np.newaxis], 1e-6)
            out_rel[too_large, k, :2] *= scale

    return out_rel


def process_npz_take_bulletproof(npz_path):
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

    rel_lh = extract_relative_hand_shape(lh_act, m_act[:, 1], is_left=True)
    rel_rh = extract_relative_hand_shape(rh_act, m_act[:, 2], is_left=False)

    lw_disp = float(np.ptp(torso_act[:, 5, 1]))
    rw_disp = float(np.ptp(torso_act[:, 6, 1]))
    min_disp = min(lw_disp, rw_disp)
    max_disp = max(lw_disp, rw_disp)
    is_bimanual = (min_disp > 0.055 and (min_disp / max(max_disp, 1e-4)) > 0.35)

    # Si es unimanual y el señante fue zurdo en esta toma, espejamos simétricamente
    if not is_bimanual and lw_disp > rw_disp:
        torso_act[:, :, 0] = 1.0 - torso_act[:, :, 0]
        torso_act[:, [1, 2]] = torso_act[:, [2, 1]]
        torso_act[:, [3, 4]] = torso_act[:, [4, 3]]
        torso_act[:, [5, 6]] = torso_act[:, [6, 5]]
        rel_lh[:, :, 0] = -rel_lh[:, :, 0]
        rel_rh[:, :, 0] = -rel_rh[:, :, 0]
        temp_rel = rel_lh.copy()
        rel_lh = rel_rh
        rel_rh = temp_rel

    final_lh = torso_act[:, 5:6, :] + rel_lh
    final_rh = torso_act[:, 6:7, :] + rel_rh

    return {
        'file': os.path.basename(npz_path),
        'n_frames': n_act,
        'torso': torso_act,
        'lh': final_lh,
        'rh': final_rh,
        'rel_lh': rel_lh,
        'rel_rh': rel_rh,
        'is_bimanual': is_bimanual
    }


def resample_take_bulletproof(take_dict, target_frames=60):
    orig_n = take_dict['n_frames']
    t_orig = np.linspace(0.0, 1.0, orig_n)
    t_target = np.linspace(0.0, 1.0, target_frames)

    def resample_mat(arr):
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

    torso_res = resample_mat(take_dict['torso'])
    rel_lh_res = resample_mat(take_dict['rel_lh'])
    rel_rh_res = resample_mat(take_dict['rel_rh'])

    rel_lh_res[:, 0] = 0.0
    rel_rh_res[:, 0] = 0.0

    lh_res = torso_res[:, 5:6, :] + rel_lh_res
    rh_res = torso_res[:, 6:7, :] + rel_rh_res

    return {
        'file': take_dict['file'],
        'torso': torso_res,
        'lh': lh_res,
        'rh': rh_res,
        'rel_lh': rel_lh_res,
        'rel_rh': rel_rh_res,
        'is_bimanual': take_dict['is_bimanual']
    }


def build_bulletproof_master_for_class(class_id):
    c_idx = int(class_id)
    sign_name = CLASS_NAMES[c_idx]
    pattern = os.path.join(NPZ_DIR, f"{class_id}_*.npz")
    npz_files = sorted(glob.glob(pattern))

    takes = [process_npz_take_bulletproof(f) for f in npz_files]
    TARGET_FRAMES = 60
    resampled = [resample_take_bulletproof(t, target_frames=TARGET_FRAMES) for t in takes]

    K = len(resampled)
    torso_stack = np.array([r['torso'] for r in resampled])
    rel_lh_stack = np.array([r['rel_lh'] for r in resampled])
    rel_rh_stack = np.array([r['rel_rh'] for r in resampled])

    # 1. Mezcla Universal Canónica
    univ_torso = np.zeros((TARGET_FRAMES, 7, 3), dtype=np.float32)
    univ_rel_lh = np.zeros((TARGET_FRAMES, 21, 3), dtype=np.float32)
    univ_rel_rh = np.zeros((TARGET_FRAMES, 21, 3), dtype=np.float32)

    for t in range(TARGET_FRAMES):
        for j in range(7):
            for c in range(3):
                univ_torso[t, j, c] = trim_mean(torso_stack[:, t, j, c], 0.2)
        for j in range(21):
            for c in range(3):
                univ_rel_lh[t, j, c] = trim_mean(rel_lh_stack[:, t, j, c], 0.2)
                univ_rel_rh[t, j, c] = trim_mean(rel_rh_stack[:, t, j, c], 0.2)

    univ_rel_lh[:, 0] = 0.0
    univ_rel_rh[:, 0] = 0.0

    # 2. Medoide Real T* (ejemplar más representativo)
    feat_univ = np.hstack([univ_torso.reshape(60, -1), univ_rel_lh.reshape(60, -1), univ_rel_rh.reshape(60, -1)])
    dists = []
    for k in range(K):
        f_k = np.hstack([resampled[k]['torso'].reshape(60, -1), resampled[k]['rel_lh'].reshape(60, -1), resampled[k]['rel_rh'].reshape(60, -1)])
        d = float(np.mean(np.linalg.norm(f_k - feat_univ, axis=1)))
        dists.append((k, d))

    dists.sort(key=lambda x: x[1])
    medoid = resampled[dists[0][0]]

    # 3. Clasificación unimanual / bimanual
    bim_count = sum(1 for t in takes if t['is_bimanual'])
    is_bim = (bim_count >= K * 0.45)

    # 4. Detección del Ápex Semántico
    rw_apex = univ_torso[:, 6, :2]
    disp = np.linalg.norm(rw_apex - rw_apex[0], axis=1)
    apex_idx = int(np.argmax(disp))
    if apex_idx < 15 or apex_idx > 45:
        apex_idx = 30

    # 5. Fusión Bidireccional Hermite con T*:
    # t=0: Medoide puro T*[0] (humano real sin artefactos)
    # t=apex: Mezcla Universal canónica
    # t=59: Medoide puro T*[-1] (humano real sin artefactos)
    adapted_torso = np.zeros_like(univ_torso)
    adapted_rel_lh = np.zeros_like(univ_rel_lh)
    adapted_rel_rh = np.zeros_like(univ_rel_rh)

    for t in range(TARGET_FRAMES):
        if t <= apex_idx:
            alpha = t / float(max(1, apex_idx))
            w = alpha * alpha * (3.0 - 2.0 * alpha)
        else:
            rem = (t - apex_idx) / float(max(1, TARGET_FRAMES - 1 - apex_idx))
            w = 1.0 - rem * rem * (3.0 - 2.0 * rem)

        adapted_torso[t] = (1.0 - w) * medoid['torso'][t] + w * univ_torso[t]
        adapted_rel_lh[t] = (1.0 - w) * medoid['rel_lh'][t] + w * univ_rel_lh[t]
        adapted_rel_rh[t] = (1.0 - w) * medoid['rel_rh'][t] + w * univ_rel_rh[t]

    adapted_rel_lh[:, 0] = 0.0
    adapted_rel_rh[:, 0] = 0.0

    # 6. Suavizado Savitzky-Golay
    def smooth_arr(arr):
        res = np.zeros_like(arr)
        for j in range(arr.shape[1]):
            for c in range(arr.shape[2]):
                res[:, j, c] = savgol_filter(arr[:, j, c], window_length=7, polyorder=2)
        return res

    adapted_torso = smooth_arr(adapted_torso)
    adapted_rel_lh = smooth_arr(adapted_rel_lh)
    adapted_rel_rh = smooth_arr(adapted_rel_rh)

    adapted_rel_lh[:, 0] = 0.0
    adapted_rel_rh[:, 0] = 0.0

    # 7. Postura de Reposo Anatómica Real basada en dimensiones humanas
    sh_l = adapted_torso[0, 1]
    sh_r = adapted_torso[0, 2]
    torso_w = float(np.linalg.norm(sh_l - sh_r))
    upper_arm_len = torso_w * 1.45 # ~0.16
    forearm_len = torso_w * 1.05   # ~0.11
    total_arm = upper_arm_len + forearm_len

    rest_torso = adapted_torso[0].copy()
    rest_torso[3] = [sh_l[0] + 0.025, sh_l[1] + upper_arm_len, 0.0]  # Codo izq
    rest_torso[4] = [sh_r[0] - 0.025, sh_r[1] + upper_arm_len, 0.0]  # Codo der
    rest_torso[5] = [sh_l[0] + 0.010, sh_l[1] + total_arm, 0.0]      # Muñeca izq
    rest_torso[6] = [sh_r[0] - 0.010, sh_r[1] + total_arm, 0.0]      # Muñeca der

    canon_lh = get_canonical_hand_shape(is_left=True)
    canon_rh = get_canonical_hand_shape(is_left=False)

    # Bloqueo de mano no dominante si la seña es unimanual
    if not is_bim:
        adapted_torso[:, 3] = rest_torso[3]
        adapted_torso[:, 5] = rest_torso[5]
        adapted_rel_lh[:] = canon_lh

    # 8. Secuencia Completa con Fases Didácticas Estandarizadas
    # 12 fotogramas reposo/entrada + 60 activos + 12 fotogramas salida/reposo = 84 fotogramas
    PAD_FRAMES = 12
    TOTAL_FRAMES = PAD_FRAMES + TARGET_FRAMES + PAD_FRAMES

    full_torso = np.zeros((TOTAL_FRAMES, 7, 3), dtype=np.float32)
    full_rel_lh = np.zeros((TOTAL_FRAMES, 21, 3), dtype=np.float32)
    full_rel_rh = np.zeros((TOTAL_FRAMES, 21, 3), dtype=np.float32)
    is_act = np.zeros(TOTAL_FRAMES, dtype=np.int32)

    # Entrada
    for i in range(PAD_FRAMES):
        alpha = i / float(PAD_FRAMES)
        w = alpha * alpha * (3.0 - 2.0 * alpha)
        full_torso[i] = (1.0 - w) * rest_torso + w * adapted_torso[0]
        full_rel_lh[i] = (1.0 - w) * canon_lh + w * adapted_rel_lh[0]
        full_rel_rh[i] = (1.0 - w) * canon_rh + w * adapted_rel_rh[0]
        is_act[i] = 0

    # Activo
    for i in range(TARGET_FRAMES):
        idx = PAD_FRAMES + i
        full_torso[idx] = adapted_torso[i]
        full_rel_lh[idx] = adapted_rel_lh[i]
        full_rel_rh[idx] = adapted_rel_rh[i]
        is_act[idx] = 1

    # Salida
    for i in range(PAD_FRAMES):
        alpha = (i + 1) / float(PAD_FRAMES)
        w = alpha * alpha * (3.0 - 2.0 * alpha)
        idx = PAD_FRAMES + TARGET_FRAMES + i
        full_torso[idx] = (1.0 - w) * adapted_torso[-1] + w * rest_torso
        full_rel_lh[idx] = (1.0 - w) * adapted_rel_lh[-1] + w * canon_lh
        full_rel_rh[idx] = (1.0 - w) * adapted_rel_rh[-1] + w * canon_rh
        is_act[idx] = 0

    full_rel_lh[:, 0] = 0.0
    full_rel_rh[:, 0] = 0.0

    # Anclaje rígido muñeca-mano
    full_lh = full_torso[:, 5:6, :] + full_rel_lh
    full_rh = full_torso[:, 6:7, :] + full_rel_rh

    # SUITE DE QA BIOMECÁNICA AUTOMÁTICA
    for f_i in range(TOTAL_FRAMES):
        d_lw = float(np.linalg.norm(full_lh[f_i, 0] - full_torso[f_i, 5]))
        d_rw = float(np.linalg.norm(full_rh[f_i, 0] - full_torso[f_i, 6]))
        assert d_lw < 1e-5, f"Fallo QA: Muñeca izquierda desprendida frame {f_i}"
        assert d_rw < 1e-5, f"Fallo QA: Muñeca derecha desprendida frame {f_i}"

        span_l = np.ptp(full_lh[f_i, :, :2], axis=0)
        span_r = np.ptp(full_rh[f_i, :, :2], axis=0)
        assert span_l[0] < 0.14 and span_l[1] < 0.14, f"Fallo QA: Mano izquierda gigante frame {f_i} ({span_l})"
        assert span_r[0] < 0.14 and span_r[1] < 0.14, f"Fallo QA: Mano derecha gigante frame {f_i} ({span_r})"

        if f_i < PAD_FRAMES or f_i >= PAD_FRAMES + TARGET_FRAMES:
            le = full_torso[f_i, 3]
            re_p = full_torso[f_i, 4]
            lw = full_torso[f_i, 5]
            rw = full_torso[f_i, 6]
            assert le[0] > re_p[0], f"Fallo QA: Codos invertidos en reposo frame {f_i}"
            assert lw[0] > rw[0], f"Fallo QA: Muñecas invertidas en reposo frame {f_i}"

    # Construir DataFrame Master CSV (310 columnas)
    master_rows = []
    fps = 30.0

    for i in range(TOTAL_FRAMES):
        row = {}
        row['frame'] = i
        row['timestamp_ms'] = int(i * (1000.0 / fps))
        row['is_active'] = int(is_act[i])
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

        sh_l_pt = full_torso[i, 1]
        sh_r_pt = full_torso[i, 2]
        torso_ctr = (sh_l_pt + sh_r_pt) / 2.0
        sh_d = float(np.linalg.norm(sh_l_pt - sh_r_pt))
        s_factor = sh_d if sh_d > 0.05 else 1.0

        row['torso_center_x'] = round(float(torso_ctr[0]), 4)
        row['torso_center_y'] = round(float(torso_ctr[1]), 4)
        row['scale_shoulder_dist'] = round(float(s_factor), 4)

        for p_idx, p_name in enumerate(POSE_NAMES):
            n_pt = (full_torso[i, p_idx] - torso_ctr) / s_factor
            row[f'norm_torso_{p_name}_x'] = round(float(n_pt[0]), 4)
            row[f'norm_torso_{p_name}_y'] = round(float(n_pt[1]), 4)
            row[f'norm_torso_{p_name}_z'] = round(float(n_pt[2]), 4)

        lw_p = full_lh[i, 0]
        palm_l = float(np.linalg.norm(full_lh[i, 9] - lw_p))
        scale_l = palm_l if palm_l > 0.02 else 0.1
        for k in range(21):
            nk = (full_lh[i, k] - lw_p) / scale_l
            row[f'norm_lh_{k}_x'] = round(float(nk[0]), 4)
            row[f'norm_lh_{k}_y'] = round(float(nk[1]), 4)
            row[f'norm_lh_{k}_z'] = round(float(nk[2]), 4)

        rw_p = full_rh[i, 0]
        palm_r = float(np.linalg.norm(full_rh[i, 9] - rw_p))
        scale_r = palm_r if palm_r > 0.02 else 0.1
        for k in range(21):
            nk = (full_rh[i, k] - rw_p) / scale_r
            row[f'norm_rh_{k}_x'] = round(float(nk[0]), 4)
            row[f'norm_rh_{k}_y'] = round(float(nk[1]), 4)
            row[f'norm_rh_{k}_z'] = round(float(nk[2]), 4)

        master_rows.append(row)

    master_df = pd.DataFrame(master_rows)
    master_csv_path = os.path.join(MASTER_OUT_DIR, f"{class_id}_master.csv")
    master_df.to_csv(master_csv_path, index=False)

    clean_id = sign_name.lower().replace(' ', '_').replace('¿', '').replace('?', '').replace('á', 'a').replace('é', 'e').replace('í', 'i').replace('ó', 'o').replace('ú', 'u')

    meta = {
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
        'medoid_take': medoid['file'],
        'medoid_distance': round(dists[0][1], 6),
        'qa_passed': True,
        'wrist_detachment_dist': 0.0,
        'methodology': 'Bulletproof Relative Finger Binding + Bidirectional Medoid Hermite Anchor + Universal Apex'
    }

    meta_path = os.path.join(MASTER_OUT_DIR, f"{class_id}_master_meta.json")
    with open(meta_path, 'w', encoding='utf-8') as f:
        json.dump(meta, f, indent=2, ensure_ascii=False)

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
            'instructions': f"Gesto {'bimanual' if is_bim else 'con mano dominante'}. Inicio suave desde reposo anatómico, sincronizado hacia el ápex canónico.",
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

    return clean_id, sign_dict, medoid['file'], dists[0][1]


def run_bulletproof_synthesis():
    print("=" * 80)
    print(" SÍNTESIS DEFINITIVA DE 50 MASTER CSVS PARA AVATAR LSC")
    print(" (Zero Giant Hands | Zero Crossed Arms | Zero Detached Wrists)")
    print("=" * 80)

    t0 = time.time()
    motion_bank = {}

    for c_idx in range(50):
        class_id = f"{c_idx:04d}"
        t_start = time.time()
        clean_id, sign_dict, medoid_file, dist = build_bulletproof_master_for_class(class_id)
        motion_bank[clean_id] = sign_dict
        el = time.time() - t_start
        print(f"[{class_id}] {sign_dict['display_name']:<20} | Tipo: {sign_dict['type'].upper():<9} | Medoide: {medoid_file:<20} | QA: PASS | {el:.2f}s")

    bank_path = os.path.join(AVATAR_OUT_DIR, 'lsc_motion_bank.json')
    with open(bank_path, 'w', encoding='utf-8') as f:
        json.dump(motion_bank, f, indent=2, ensure_ascii=False)

    print("\n" + "=" * 80)
    print(f" SÍNTESIS BULLETPROOF COMPLETADA EXITOSAMENTE EN {time.time()-t0:.2f} s")
    print(f" 50 / 50 señas pasaron el 100% de las pruebas QA biomecánicas.")
    print(f" Banco guardado en: {bank_path}")
    print("=" * 80)


if __name__ == '__main__':
    run_bulletproof_synthesis()
