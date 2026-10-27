# -*- coding: utf-8 -*-
"""
synthesize_all_50_master.py

Generador integral de los 50 Master CSVs canónicos del dataset LSC50
a partir de las 1,000 secuencias preprocesadas en dataset/PROCESSED_NPZ.

Metodología de 6 fases:
1. Infilling cinemático de manos guiado por muñecas de Pose.
2. Detección automática bimanual vs unimanual y canonicalización de lateralidad (espejado a diestro tutor).
3. Remuestreo PCHIP a grilla de 60 fotogramas canónicos.
4. Fusión multiseñante con Trimmed Mean al 20% (aislamiento del invariante fonológico).
5. Regularización cinemática Savitzky-Golay (C1 continuidad).
6. Fases de reposo anatómico neutral (12 cuadros inicio, 60 activos, 12 cuadros retorno = 84 cuadros totales).
7. Exportación a CSVs de 310 columnas y generación del Motion Bank de 50 señas.
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

POSE_INDICES_MAP = [0, 5, 6, 7, 8, 9, 10]
POSE_NAMES = ['nose', 'left_shoulder', 'right_shoulder', 'left_elbow', 'right_elbow', 'left_wrist', 'right_wrist']


def get_neutral_pose():
    torso = {
        'nose': [0.50, 0.22, 0.0],
        'left_shoulder': [0.60, 0.36, 0.0],
        'right_shoulder': [0.40, 0.36, 0.0],
        'left_elbow': [0.64, 0.58, 0.0],
        'right_elbow': [0.36, 0.58, 0.0],
        'left_wrist': [0.62, 0.78, 0.0],
        'right_wrist': [0.38, 0.78, 0.0]
    }
    lh_hand = []
    rh_hand = []
    base_l = np.array([0.62, 0.78, 0.0])
    base_r = np.array([0.38, 0.78, 0.0])
    for k in range(21):
        offset_y = 0.01 * (k // 4)
        offset_x = 0.005 * (k % 4 - 2)
        lh_hand.append([round(float(base_l[0] + offset_x), 4), round(float(base_l[1] + offset_y), 4), 0.0])
        rh_hand.append([round(float(base_r[0] - offset_x), 4), round(float(base_r[1] + offset_y), 4), 0.0])
    return torso, lh_hand, rh_hand


def infill_hand(hand_arr, has_hand_mask, pose_wrist):
    n_frames = len(hand_arr)
    valid_frames = np.where(has_hand_mask)[0]

    for c in range(3):
        col = pose_wrist[:, c]
        nans = np.isnan(col)
        if np.any(nans):
            x = np.arange(n_frames)
            col[nans] = np.interp(x[nans], x[~nans], col[~nans])
            pose_wrist[:, c] = col

    if len(valid_frames) == 0:
        hand_infilled = np.zeros((n_frames, 21, 3), dtype=np.float32)
        for i in range(n_frames):
            w = pose_wrist[i]
            for k in range(21):
                hand_infilled[i, k] = [w[0], w[1] + 0.01 * (k // 4), w[2]]
        return hand_infilled

    valid_hands = hand_arr[valid_frames]
    valid_wrist = valid_hands[:, 0:1, :]
    rel_shapes = valid_hands - valid_wrist

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
        if has_hand_mask[i] and not np.isnan(hand_arr[i, 0, 0]):
            out_hand[i] = hand_arr[i]
        else:
            out_hand[i] = pose_wrist[i] + infilled_shapes[i]
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
    lh_inf = infill_hand(lh_act, m_act[:, 1], lw_pose)
    rh_inf = infill_hand(rh_act, m_act[:, 2], rw_pose)

    lh_disp = float(np.ptp(lh_inf[:, 0, 1]))
    rh_disp = float(np.ptp(rh_inf[:, 0, 1]))
    is_bimanual = (lh_disp > 0.08 and rh_disp > 0.08)

    if not is_bimanual:
        if lh_disp > rh_disp:
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

    return {
        'n_frames': n_act,
        'torso': torso_act,
        'lh': final_lh,
        'rh': final_rh,
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
        'torso': resample_arr(take_dict['torso']),
        'lh': resample_arr(take_dict['lh']),
        'rh': resample_arr(take_dict['rh']),
        'is_bimanual': take_dict['is_bimanual']
    }


def build_master_for_class(class_id):
    c_idx = int(class_id)
    sign_name = CLASS_NAMES[c_idx]
    pattern = os.path.join(NPZ_DIR, f"{class_id}_*.npz")
    npz_files = sorted(glob.glob(pattern))

    if not npz_files:
        raise ValueError(f"No se encontraron archivos .npz para la clase {class_id}")

    takes = [process_npz_take(f) for f in npz_files]
    TARGET_FRAMES = 60
    resampled = [resample_take(t, target_frames=TARGET_FRAMES) for t in takes]

    K = len(resampled)
    torso_stack = np.array([r['torso'] for r in resampled])
    lh_stack = np.array([r['lh'] for r in resampled])
    rh_stack = np.array([r['rh'] for r in resampled])

    master_torso = np.zeros((TARGET_FRAMES, 7, 3), dtype=np.float32)
    master_lh = np.zeros((TARGET_FRAMES, 21, 3), dtype=np.float32)
    master_rh = np.zeros((TARGET_FRAMES, 21, 3), dtype=np.float32)

    for t in range(TARGET_FRAMES):
        for j in range(7):
            for c in range(3):
                master_torso[t, j, c] = trim_mean(torso_stack[:, t, j, c], 0.2)
        for j in range(21):
            for c in range(3):
                master_lh[t, j, c] = trim_mean(lh_stack[:, t, j, c], 0.2)
                master_rh[t, j, c] = trim_mean(rh_stack[:, t, j, c], 0.2)

    rh_var = float(np.mean(np.var(rh_stack, axis=0)))

    # Suavizado Savitzky-Golay
    def apply_savgol(arr):
        res = np.zeros_like(arr)
        for j in range(arr.shape[1]):
            for c in range(arr.shape[2]):
                res[:, j, c] = savgol_filter(arr[:, j, c], window_length=7, polyorder=2)
        return res

    master_torso = apply_savgol(master_torso)
    master_lh = apply_savgol(master_lh)
    master_rh = apply_savgol(master_rh)

    # Detección de Ápex
    disp = np.linalg.norm(master_rh[:, 0, :2] - master_rh[0, 0, :2], axis=1)
    apex_idx = int(np.argmax(disp))

    PAD_FRAMES = 12
    TOTAL_FRAMES = PAD_FRAMES + TARGET_FRAMES + PAD_FRAMES
    neutral_torso, neutral_lh, neutral_rh = get_neutral_pose()

    full_torso = np.zeros((TOTAL_FRAMES, 7, 3), dtype=np.float32)
    full_lh = np.zeros((TOTAL_FRAMES, 21, 3), dtype=np.float32)
    full_rh = np.zeros((TOTAL_FRAMES, 21, 3), dtype=np.float32)
    is_active_flags = np.zeros(TOTAL_FRAMES, dtype=np.int32)

    n_torso_arr = np.array([neutral_torso[p] for p in POSE_NAMES], dtype=np.float32)
    n_lh_arr = np.array(neutral_lh, dtype=np.float32)
    n_rh_arr = np.array(neutral_rh, dtype=np.float32)

    # Transición entrada
    for i in range(PAD_FRAMES):
        alpha = i / float(PAD_FRAMES)
        w = alpha * alpha * (3.0 - 2.0 * alpha)
        full_torso[i] = (1.0 - w) * n_torso_arr + w * master_torso[0]
        full_lh[i] = (1.0 - w) * n_lh_arr + w * master_lh[0]
        full_rh[i] = (1.0 - w) * n_rh_arr + w * master_rh[0]
        is_active_flags[i] = 0

    # Activo
    for i in range(TARGET_FRAMES):
        idx = PAD_FRAMES + i
        full_torso[idx] = master_torso[i]
        full_lh[idx] = master_lh[i]
        full_rh[idx] = master_rh[i]
        is_active_flags[idx] = 1

    # Transición salida
    for i in range(PAD_FRAMES):
        alpha = (i + 1) / float(PAD_FRAMES)
        w = alpha * alpha * (3.0 - 2.0 * alpha)
        idx = PAD_FRAMES + TARGET_FRAMES + i
        full_torso[idx] = (1.0 - w) * master_torso[-1] + w * n_torso_arr
        full_lh[idx] = (1.0 - w) * master_lh[-1] + w * n_lh_arr
        full_rh[idx] = (1.0 - w) * master_rh[-1] + w * n_rh_arr
        is_active_flags[idx] = 0

    # Generar DataFrame de 310 columnas
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
        'hand_presence_ratio': 1.0,
        'rh_variance_residual': round(rh_var, 6),
        'methodology': 'Pose-Wrist Infilled + PCHIP Resampling + Trimmed Mean 20% + Savitzky-Golay'
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
            'instructions': f"Gesto {'bimanual' if is_bim else 'con mano dominante'}. Sigue el movimiento fluido indicado por la estela hasta el ápex.",
            'apex_description': 'Punto de máxima configuración o contacto del gesto',
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

    return clean_id, sign_dict, rh_var


def run_all_50_synthesis():
    print("=" * 75)
    print(" SÍNTESIS INTEGRAL DE MASTER CSVS PARA LAS 50 SEÑAS DEL DATASET LSC")
    print("=" * 75)
    t0 = time.time()
    motion_bank = {}
    summary_report = []

    for c_idx in range(50):
        class_id = f"{c_idx:04d}"
        t_start = time.time()
        clean_id, sign_dict, rh_var = build_master_for_class(class_id)
        motion_bank[clean_id] = sign_dict
        el = time.time() - t_start
        print(f"[{class_id}] {sign_dict['display_name']:<20} | Tipo: {sign_dict['type']:<10} | Var: {rh_var:.6f} | Tiempo: {el:.2f}s")
        summary_report.append({
            'class_id': class_id,
            'sign_name': sign_dict['display_name'],
            'clean_id': clean_id,
            'category': sign_dict['category'],
            'type': sign_dict['type'],
            'variance_residual': round(rh_var, 6),
            'frames': sign_dict['total_frames']
        })

    # Guardar Motion Bank de las 50 señas
    bank_path = os.path.join(AVATAR_OUT_DIR, 'lsc_motion_bank.json')
    with open(bank_path, 'w', encoding='utf-8') as f:
        json.dump(motion_bank, f, indent=2, ensure_ascii=False)

    # Guardar reporte de síntesis
    rep_path = os.path.join(MASTER_OUT_DIR, 'lsc50_master_summary.json')
    with open(rep_path, 'w', encoding='utf-8') as f:
        json.dump(summary_report, f, indent=2, ensure_ascii=False)

    total_time = time.time() - t0
    print("\n" + "=" * 75)
    print(f" PROCESO COMPLETADO EXITOSAMENTE:")
    print(f" - Señas procesadas: {len(motion_bank)} / 50")
    print(f" - Total Master CSVs generados: 50 en {MASTER_OUT_DIR}")
    print(f" - Banco de Movimiento de 50 señas: {bank_path}")
    print(f" - Tiempo total de cómputo: {total_time:.2f} s ({total_time/50:.2f} s/seña)")
    print("=" * 75)


if __name__ == '__main__':
    run_all_50_synthesis()
