# -*- coding: utf-8 -*-
"""
synthesize_master_csv.py

Metodología de síntesis de "Master CSV" para el Avatar y Modelos de LSC
(Lengua de Señas Colombiana).

Resuelve de raíz los artefactos de oclusión y desaparición momentánea de manos
mediante:
1. Infilling cinemático anclado en muñeca (Pose-guided Kinematic Infilling):
   Garantiza presencia de mano al 100% en cada fotograma utilizando la trayectoria
   continua de muñeca de pose de MediaPipe.
2. Canonicalización morfométrica y de lateralidad:
   Espejado de señantes zurdos a estándar diestro (tutor pedagógico) y alineación
   antropométrica.
3. Remuestreo temporal continuo a grilla canónica unificada (T = 60 fotogramas).
4. Fusión multiseñante por consenso robusto (Trimmed Mean al 20%):
   Elimina ruido, tics individuales o fallos de captura aislando el invariante
   fonológico de la seña.
5. Regularización cinemática biomecánica con filtro Savitzky-Golay (C1 continuidad).
6. Fases de reposo neutral estandarizadas (Preparación -> Gesto Activo -> Retorno).
7. Exportación a CSV canónico de 310 columnas y actualización directa del
   Motion Bank para el avatar.

Diseñado para escalar de las 4 señas iniciales a las 50 señas del dataset LSC.
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
CSV_DIR = os.path.join(os.path.dirname(__file__), 'output', 'csv')
MASTER_OUT_DIR = os.path.join(os.path.dirname(__file__), 'output', 'master_csv')
AVATAR_OUT_DIR = os.path.join(os.path.dirname(__file__), 'output', 'avatar')

os.makedirs(MASTER_OUT_DIR, exist_ok=True)
os.makedirs(AVATAR_OUT_DIR, exist_ok=True)

POSE_NAMES = [
    'nose', 'left_shoulder', 'right_shoulder',
    'left_elbow', 'right_elbow', 'left_wrist', 'right_wrist'
]

SIGN_CATALOG = {
    '0000': {
        'id': 'gracias',
        'display_name': 'GRACIAS',
        'category': 'Cortesía',
        'type': 'unimanual',
        'pedagogical_instructions': 'Mano dominante plana con los dedos juntos. Las yemas tocan la barbilla/mentón y luego descienden suavemente hacia adelante en plano sagital.',
        'apex_description': 'Contacto de las yemas con el mentón',
        'key_hand': 'right'
    },
    '0001': {
        'id': 'buenos_dias',
        'display_name': 'BUENOS DÍAS',
        'category': 'Saludo',
        'type': 'unimanual',
        'pedagogical_instructions': 'Mano dominante abierta a la altura del pecho. Realiza un barrido horizontal fluido hacia afuera y ligeramente hacia arriba.',
        'apex_description': 'Extensión máxima del barrido en el plano pectoral',
        'key_hand': 'right'
    },
    '0002': {
        'id': 'buenas_tardes',
        'display_name': 'BUENAS TARDES',
        'category': 'Saludo',
        'type': 'unimanual',
        'pedagogical_instructions': 'Mano dominante se posiciona en el lateral de la frente/sien y desciende con un movimiento semicircular hacia el plano medio.',
        'apex_description': 'Punto más alto cerca de la sien antes de iniciar el descenso',
        'key_hand': 'right'
    },
    '0003': {
        'id': 'buenas_noches',
        'display_name': 'BUENAS NOCHES',
        'category': 'Saludo',
        'type': 'bimanual',
        'pedagogical_instructions': 'Gesto bimanual: La mano no dominante sirve de base horizontal a la altura del pecho; la mano dominante desciende en un arco suave cubriendo la base.',
        'apex_description': 'Cruce y cobertura en arco de la mano superior sobre la inferior',
        'key_hand': 'both'
    }
}

LEFT_HANDED_SIGNERS = {0, 2, 3, 4}


def get_neutral_pose():
    """Genera postura neutral de reposo anatómico del avatar."""
    torso = {
        'nose': [0.50, 0.22, 0.0],
        'left_shoulder': [0.60, 0.36, 0.0],
        'right_shoulder': [0.40, 0.36, 0.0],
        'left_elbow': [0.64, 0.58, 0.0],
        'right_elbow': [0.36, 0.58, 0.0],
        'left_wrist': [0.62, 0.78, 0.0],
        'right_wrist': [0.38, 0.78, 0.0]
    }
    # Mano relajada estándar en reposo
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


def infill_hand_landmarks(df_slice, hand_prefix, wrist_col_prefix):
    """
    Rellena de forma cinemática cualquier hueco de detección de mano en un segmento:
    - Ancla la posición en la muñeca de Pose (detectada al 100%).
    - Interpola la forma local de la mano (postura dactilar) a lo largo del tiempo.
    - Retorna matriz (N, 21, 3) sin valores nulos ni saltos espaciales.
    """
    n_frames = len(df_slice)
    has_hand_col = f'has_{hand_prefix}'
    has_hand_mask = (df_slice[has_hand_col].values == 1)

    # Coordenadas de muñeca de pose de respaldo
    pose_wrist = df_slice[[f'{wrist_col_prefix}_x', f'{wrist_col_prefix}_y', f'{wrist_col_prefix}_z']].values
    # Reemplazar NaNs en muñeca de pose si hubiera por interpolación lineal
    for c in range(3):
        col = pose_wrist[:, c]
        nans = np.isnan(col)
        if np.any(nans):
            x = np.arange(n_frames)
            col[nans] = np.interp(x[nans], x[~nans], col[~nans])
            pose_wrist[:, c] = col

    # Extraer landmarks de mano
    cols_hand = []
    for k in range(21):
        cols_hand.extend([f'{hand_prefix}_{k}_x', f'{hand_prefix}_{k}_y', f'{hand_prefix}_{k}_z'])
    raw_hand_mat = df_slice[cols_hand].values.reshape(n_frames, 21, 3)

    valid_frames = np.where(has_hand_mask)[0]

    # Si la mano nunca fue detectada en toda la toma, usar postura neutral anclada en muñeca
    if len(valid_frames) == 0:
        hand_infilled = np.zeros((n_frames, 21, 3), dtype=np.float32)
        for i in range(n_frames):
            w = pose_wrist[i]
            for k in range(21):
                hand_infilled[i, k] = [w[0], w[1] + 0.01 * (k // 4), w[2]]
        return hand_infilled

    # Calcular la forma local dactilar respecto a la muñeca de la mano (Landmark 0)
    # shape_offset: (N_valid, 21, 3)
    valid_hands = raw_hand_mat[valid_frames]
    valid_wrist_hand = valid_hands[:, 0:1, :]  # (N_valid, 1, 3)
    relative_shapes = valid_hands - valid_wrist_hand  # (N_valid, 21, 3)

    # Interpolar relative_shapes para todos los fotogramas (0..n_frames-1)
    infilled_shapes = np.zeros((n_frames, 21, 3), dtype=np.float32)
    for k in range(21):
        for c in range(3):
            val_col = relative_shapes[:, k, c]
            if len(valid_frames) == 1:
                infilled_shapes[:, k, c] = val_col[0]
            else:
                f_interp = interp1d(valid_frames, val_col, kind='linear', fill_value='extrapolate')
                infilled_shapes[:, k, c] = f_interp(np.arange(n_frames))

    # Anclar la mano reconstruida sobre la muñeca de pose
    hand_infilled = np.zeros((n_frames, 21, 3), dtype=np.float32)
    for i in range(n_frames):
        if has_hand_mask[i]:
            hand_infilled[i] = raw_hand_mat[i]
        else:
            w_pose = pose_wrist[i]
            hand_infilled[i] = w_pose + infilled_shapes[i]

    return hand_infilled


def process_single_take(csv_file, sign_info):
    """
    Procesa, canonicaliza e infunde una toma individual:
    - Recorta segmento activo.
    - Aplica infilling cinemático a ambas manos.
    - Espeja señantes zurdos a estándar diestro si la seña es unimanual.
    - Retorna dict con arrays completos y limpios de torso y manos.
    """
    meta_file = csv_file.replace('.csv', '_meta.json')
    if not os.path.exists(meta_file):
        return None

    with open(meta_file, 'r', encoding='utf-8') as mf:
        meta = json.load(mf)

    df = pd.read_csv(csv_file)
    start_act, end_act = meta['active_segment']
    if end_act <= start_act + 5:
        start_act = 0
        end_act = len(df) - 1

    df_act = df.iloc[start_act:end_act + 1].copy().reset_index(drop=True)
    n_frames = len(df_act)

    # Torso (7, 3)
    torso_mat = np.zeros((n_frames, 7, 3), dtype=np.float32)
    for p_idx, p_name in enumerate(POSE_NAMES):
        for c_idx, c_name in enumerate(['x', 'y', 'z']):
            col = df_act[f'torso_{p_name}_{c_name}'].values
            nans = np.isnan(col)
            if np.any(nans):
                x = np.arange(n_frames)
                col[nans] = np.interp(x[nans], x[~nans], col[~nans])
            torso_mat[:, p_idx, c_idx] = col

    # Infilling cinemático de manos
    lh_infilled = infill_hand_landmarks(df_act, 'lh', 'torso_left_wrist')
    rh_infilled = infill_hand_landmarks(df_act, 'rh', 'torso_right_wrist')

    # Identificar señante y necesidad de espejado
    parts = os.path.splitext(os.path.basename(csv_file))[0].split('_')
    signer_id = int(parts[1])
    needs_mirror = (signer_id in LEFT_HANDED_SIGNERS and sign_info['type'] == 'unimanual')

    if needs_mirror:
        # Invertir eje horizontal X: x -> 1.0 - x
        torso_mat[:, :, 0] = 1.0 - torso_mat[:, :, 0]
        # Invertir hombros, codos y muñecas correspondientes
        # idx 1: left_sh, idx 2: right_sh
        torso_mat[:, [1, 2]] = torso_mat[:, [2, 1]]
        # idx 3: left_el, idx 4: right_el
        torso_mat[:, [3, 4]] = torso_mat[:, [4, 3]]
        # idx 5: left_wr, idx 6: right_wr
        torso_mat[:, [5, 6]] = torso_mat[:, [6, 5]]

        lh_infilled[:, :, 0] = 1.0 - lh_infilled[:, :, 0]
        rh_infilled[:, :, 0] = 1.0 - rh_infilled[:, :, 0]
        # Intercambiar manos para que la mano activa quede en la derecha
        final_lh = rh_infilled
        final_rh = lh_infilled
    else:
        final_lh = lh_infilled
        final_rh = rh_infilled

    # Si es unimanual, mantener la mano no dominante en posición neutral estable
    if sign_info['type'] == 'unimanual':
        neutral_torso, neutral_lh, _ = get_neutral_pose()
        # Fijar muñeca izquierda cerca de la cadera
        torso_mat[:, 5, 0] = 0.62
        torso_mat[:, 5, 1] = 0.78
        for k in range(21):
            final_lh[:, k, 0] = neutral_lh[k][0]
            final_lh[:, k, 1] = neutral_lh[k][1]
            final_lh[:, k, 2] = 0.0

    return {
        'file': os.path.basename(csv_file),
        'n_frames': n_frames,
        'torso': torso_mat,   # (N, 7, 3)
        'lh': final_lh,       # (N, 21, 3)
        'rh': final_rh,       # (N, 21, 3)
        'meta': meta
    }


def resample_take_to_grid(take_dict, target_frames=60):
    """
    Remuestrea una toma individual a una grilla temporal unificada de target_frames
    utilizando interpolación cúbica monotónica (PCHIP) para preservar velocidad natural.
    """
    orig_n = take_dict['n_frames']
    t_orig = np.linspace(0.0, 1.0, orig_n)
    t_target = np.linspace(0.0, 1.0, target_frames)

    def resample_array(arr):
        # arr shape: (orig_n, J, 3)
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

    resampled_torso = resample_array(take_dict['torso'])
    resampled_lh = resample_array(take_dict['lh'])
    resampled_rh = resample_array(take_dict['rh'])

    return {
        'file': take_dict['file'],
        'torso': resampled_torso,
        'lh': resampled_lh,
        'rh': resampled_rh
    }


def synthesize_master_sign(class_id):
    """
    Ejecuta el pipeline completo de síntesis para una seña:
    1. Carga y preprocesa todas las tomas disponibles.
    2. Remuestrea todas a 60 cuadros canónicos.
    3. Fusión por Trimmed Mean al 20% (elimina ruidos y singularidades individuales).
    4. Suavizado Savitzky-Golay.
    5. Inserción de fases de reposo neutral (12 cuadros inicio, 12 cuadros final).
    6. Exporta Master CSV de 310 columnas y metadatos de varianza.
    """
    sign_info = SIGN_CATALOG[class_id]
    pattern = os.path.join(CSV_DIR, f"{class_id}_*.csv")
    csv_files = sorted(glob.glob(pattern))

    if not csv_files:
        raise ValueError(f"No se encontraron archivos CSV para la clase {class_id}")

    print(f"\n[{class_id}] Sintetizando Master CSV para '{sign_info['display_name']}'...")
    print(f" -> Tomas encontradas: {len(csv_files)}")

    processed_takes = []
    for f in csv_files:
        t = process_single_take(f, sign_info)
        if t is not None:
            processed_takes.append(t)

    print(f" -> Tomas procesadas e infundidas: {len(processed_takes)}")

    # Remuestrear todas las tomas a grilla de 60 fotogramas
    TARGET_FRAMES = 60
    resampled_takes = [resample_take_to_grid(t, target_frames=TARGET_FRAMES) for t in processed_takes]

    # Matrices acumuladas: (K, 60, J, 3)
    K = len(resampled_takes)
    torso_stack = np.array([r['torso'] for r in resampled_takes])  # (K, 60, 7, 3)
    lh_stack = np.array([r['lh'] for r in resampled_takes])        # (K, 60, 21, 3)
    rh_stack = np.array([r['rh'] for r in resampled_takes])        # (K, 60, 21, 3)

    # Fusión multiseñante con Trimmed Mean (20% en cada extremo)
    master_torso = np.zeros((TARGET_FRAMES, 7, 3), dtype=np.float32)
    master_lh = np.zeros((TARGET_FRAMES, 21, 3), dtype=np.float32)
    master_rh = np.zeros((TARGET_FRAMES, 21, 3), dtype=np.float32)

    variance_map = {}

    for t in range(TARGET_FRAMES):
        for j in range(7):
            for c in range(3):
                vals = torso_stack[:, t, j, c]
                master_torso[t, j, c] = trim_mean(vals, 0.2)

        for j in range(21):
            for c in range(3):
                vals_l = lh_stack[:, t, j, c]
                master_lh[t, j, c] = trim_mean(vals_l, 0.2)
                vals_r = rh_stack[:, t, j, c]
                master_rh[t, j, c] = trim_mean(vals_r, 0.2)

    # Calcular varianza inter-señante media para la trayectoria de la mano dominante
    rh_variance = float(np.mean(np.var(rh_stack, axis=0)))
    print(f" -> Consenso completado. Varianza inter-señante residual: {rh_variance:.6f}")

    # Suavizado biomecánico Savitzky-Golay (ventana 7, orden 2)
    def apply_savgol(arr):
        res = np.zeros_like(arr)
        for j in range(arr.shape[1]):
            for c in range(arr.shape[2]):
                res[:, j, c] = savgol_filter(arr[:, j, c], window_length=7, polyorder=2)
        return res

    master_torso = apply_savgol(master_torso)
    master_lh = apply_savgol(master_lh)
    master_rh = apply_savgol(master_rh)

    # Localizar el Ápex (fotograma de máxima extensión/altura en el gesto activo)
    if sign_info['id'] in ['gracias', 'buenas_tardes']:
        # Ápex = mínima coordenada Y (punto más alto en pantalla)
        apex_idx = int(np.argmin(master_rh[:, 0, 1]))
    else:
        # Ápex = máxima velocidad o desplazamiento
        disp = np.linalg.norm(master_rh[:, 0, :2] - master_rh[0, 0, :2], axis=1)
        apex_idx = int(np.argmax(disp))

    # Construir la secuencia completa con fases de reposo neutral
    # 12 fotogramas de transición de entrada + 60 fotogramas activos + 12 fotogramas de salida = 84 fotogramas
    PAD_FRAMES = 12
    TOTAL_FRAMES = PAD_FRAMES + TARGET_FRAMES + PAD_FRAMES

    neutral_torso, neutral_lh, neutral_rh = get_neutral_pose()

    full_torso = np.zeros((TOTAL_FRAMES, 7, 3), dtype=np.float32)
    full_lh = np.zeros((TOTAL_FRAMES, 21, 3), dtype=np.float32)
    full_rh = np.zeros((TOTAL_FRAMES, 21, 3), dtype=np.float32)
    is_active_flags = np.zeros(TOTAL_FRAMES, dtype=np.int32)

    # Convertir neutral a arrays
    n_torso_arr = np.array([neutral_torso[p] for p in POSE_NAMES], dtype=np.float32)
    n_lh_arr = np.array(neutral_lh, dtype=np.float32)
    n_rh_arr = np.array(neutral_rh, dtype=np.float32)

    # Fusión suave de entrada (Cubic Hermite)
    for i in range(PAD_FRAMES):
        alpha = i / float(PAD_FRAMES)
        # Smoothstep: 3*a^2 - 2*a^3
        w = alpha * alpha * (3.0 - 2.0 * alpha)
        full_torso[i] = (1.0 - w) * n_torso_arr + w * master_torso[0]
        full_lh[i] = (1.0 - w) * n_lh_arr + w * master_lh[0]
        full_rh[i] = (1.0 - w) * n_rh_arr + w * master_rh[0]
        is_active_flags[i] = 0

    # Segmento activo canónico
    for i in range(TARGET_FRAMES):
        idx = PAD_FRAMES + i
        full_torso[idx] = master_torso[i]
        full_lh[idx] = master_lh[i]
        full_rh[idx] = master_rh[i]
        is_active_flags[idx] = 1

    # Fusión suave de salida (Retorno a reposo neutral)
    for i in range(PAD_FRAMES):
        alpha = (i + 1) / float(PAD_FRAMES)
        w = alpha * alpha * (3.0 - 2.0 * alpha)
        idx = PAD_FRAMES + TARGET_FRAMES + i
        full_torso[idx] = (1.0 - w) * master_torso[-1] + w * n_torso_arr
        full_lh[idx] = (1.0 - w) * master_lh[-1] + w * n_lh_arr
        full_rh[idx] = (1.0 - w) * master_rh[-1] + w * n_rh_arr
        is_active_flags[idx] = 0

    # Construir el DataFrame de 310 columnas
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

        # 1. Coordenadas de pantalla crudas
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

        # 2. Coordenadas normalizadas e invariantes
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

        # LH normalizado
        lw_pt = full_lh[i, 0]
        palm_l = float(np.linalg.norm(full_lh[i, 9] - lw_pt))
        palm_scale_l = palm_l if palm_l > 0.02 else 0.1
        for k in range(21):
            norm_k = (full_lh[i, k] - lw_pt) / palm_scale_l
            row[f'norm_lh_{k}_x'] = round(float(norm_k[0]), 4)
            row[f'norm_lh_{k}_y'] = round(float(norm_k[1]), 4)
            row[f'norm_lh_{k}_z'] = round(float(norm_k[2]), 4)

        # RH normalizado
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

    master_meta = {
        'class_id': class_id,
        'sign_name': sign_info['display_name'],
        'sign_id': sign_info['id'],
        'takes_fused': K,
        'canonical_frames': TOTAL_FRAMES,
        'active_segment': [PAD_FRAMES, PAD_FRAMES + TARGET_FRAMES - 1],
        'apex_frame': PAD_FRAMES + apex_idx,
        'fps': fps,
        'hand_presence_ratio': 1.0,
        'rh_variance_residual': round(rh_variance, 6),
        'methodology': 'Wrist-Anchored Infilling + PCHIP Resampling + 20% Trimmed Mean Consensus + Savitzky-Golay'
    }

    meta_path = os.path.join(MASTER_OUT_DIR, f"{class_id}_master_meta.json")
    with open(meta_path, 'w', encoding='utf-8') as f:
        json.dump(master_meta, f, indent=2, ensure_ascii=False)

    print(f" -> Master CSV guardado exitosamente: {master_csv_path}")
    print(f"    (84 fotogramas, 310 columnas, 100.0% presencia continua de manos)")

    # Retornar estructura de animación para el Motion Bank
    frames_avatar = []
    for i in range(TOTAL_FRAMES):
        f_data = {
            'frame_idx': i,
            'torso': {p_name: [round(float(full_torso[i, p_idx, c]), 4) for c in range(3)] for p_idx, p_name in enumerate(POSE_NAMES)},
            'left_hand': [[round(float(full_lh[i, k, c]), 4) for c in range(3)] for k in range(21)],
            'right_hand': [[round(float(full_rh[i, k, c]), 4) for c in range(3)] for k in range(21)]
        }
        frames_avatar.append(f_data)

    return sign_info['id'], {
        'id': sign_info['id'],
        'sign_id': sign_info['id'],
        'display_name': sign_info['display_name'],
        'class_code': class_id,
        'category': sign_info['category'],
        'type': sign_info['type'],
        'total_frames': TOTAL_FRAMES,
        'total_active_frames': TARGET_FRAMES,
        'fps': fps,
        'duration_seconds': round(TOTAL_FRAMES / fps, 2),
        'apex_frame': PAD_FRAMES + apex_idx,
        'pedagogical_metadata': {
            'instructions': sign_info['pedagogical_instructions'],
            'apex_description': sign_info['apex_description'],
            'key_hand': sign_info['key_hand'],
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


def synthesize_all_master_signs():
    print("=" * 70)
    print(" GENERACIÓN INTEGRAL DE MASTER CSVS PARA AVATAR LSC")
    print(" (Validación de Metodología de Consenso Multiseñante)")
    print("=" * 70)

    t0 = time.time()
    motion_bank = {}

    for class_id in sorted(SIGN_CATALOG.keys()):
        sign_id, sign_motion = synthesize_master_sign(class_id)
        motion_bank[sign_id] = sign_motion

    # Guardar Motion Bank actualizado
    motion_bank_path = os.path.join(AVATAR_OUT_DIR, 'lsc_motion_bank.json')
    with open(motion_bank_path, 'w', encoding='utf-8') as f:
        json.dump(motion_bank, f, indent=2, ensure_ascii=False)

    elapsed = time.time() - t0
    print("\n" + "=" * 70)
    print(f" BANCO DE MOVIMIENTO CANÓNICO ACTUALIZADO: {motion_bank_path}")
    print(f" - Señas consolidadas: {len(motion_bank)}")
    print(f" - Tiempo de cómputo total: {elapsed:.2f} s")
    print("=" * 70)


if __name__ == '__main__':
    synthesize_all_master_signs()
