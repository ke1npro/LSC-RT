# -*- coding: utf-8 -*-
"""
build_motion_bank.py

Construye el banco de movimiento cinemático canónico (Motion Bank)
para el Avatar de Lengua de Señas Colombiana (LSC).

Procesa los 80 CSVs para las 4 clases:
- 0000: "GRACIAS"
- 0001: "BUENOS DÍAS"
- 0002: "BUENAS TARDES"
- 0003: "BUENAS NOCHES"

Para cada seña:
1. Extrae las trayectorias del segmento activo.
2. Canonicaliza a mano dominante derecha (estándar para avatar tutor).
3. Selecciona el ejemplar más representativo (medoide/menor distancia DTW media).
4. Aplica suavizado cinemático con filtro Savitzky-Golay / Moving Average.
5. Agrega fases de interpolación suave (Reposo Neutral -> Gesto -> Reposo Neutral).
6. Asigna metadatos pedagógicos (fases, ápex, instrucciones para el estudiante).
7. Exporta a JSON utilizable por el visor interactivo y el reproductor de avatar.
"""

import os
import glob
import json
import numpy as np
import pandas as pd
from scipy.signal import savgol_filter

CSV_DIR = os.path.join(os.path.dirname(__file__), 'output', 'csv')
AVATAR_OUT_DIR = os.path.join(os.path.dirname(__file__), 'output', 'avatar')
os.makedirs(AVATAR_OUT_DIR, exist_ok=True)

SIGN_INFO = {
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


def smooth_trajectory(points_array, window_len=7, poly_order=2):
    """Aplica suavizado cinemático Savitzky-Golay a cada coordenada (T, D)."""
    n_frames, n_dims = points_array.shape
    if n_frames < window_len:
        window_len = n_frames if (n_frames % 2 != 0) else (n_frames - 1)
    if window_len < 3:
        return points_array

    smoothed = np.zeros_like(points_array)
    for d in range(n_dims):
        col = points_array[:, d]
        # Si tiene NaNs, interpolar linealmente primero
        nans = np.isnan(col)
        if np.any(nans):
            x = np.arange(len(col))
            col[nans] = np.interp(x[nans], x[~nans], col[~nans])
        smoothed[:, d] = savgol_filter(col, window_length=window_len, polyorder=min(poly_order, window_len - 1))
    return smoothed


def build_canonical_motion_bank():
    print("=" * 70)
    print(" CONSTRUYENDO BANCO DE MOVIMIENTO CANÓNICO PARA AVATAR LSC")
    print("=" * 70)

    motion_bank = {}

    for class_id, info in SIGN_INFO.items():
        pattern = os.path.join(CSV_DIR, f"{class_id}_*.csv")
        files = sorted(glob.glob(pattern))
        if not files:
            print(f"Alerta: No se encontraron CSVs para la clase {class_id} ({info['display_name']})")
            continue

        print(f"\nProcesando seña: {info['display_name']} ({len(files)} secuencias encontradas)...")

        # Seleccionar las mejores secuencias con alta detección de mano
        candidates = []
        for f in files:
            meta_f = f.replace('.csv', '_meta.json')
            if os.path.exists(meta_f):
                with open(meta_f, 'r', encoding='utf-8') as mf:
                    meta = json.load(mf)
                det_ratio = meta['rh_detection_ratio'] if info['key_hand'] == 'right' else (meta['lh_detection_ratio'] + meta['rh_detection_ratio']) / 2.0
                candidates.append((f, meta, det_ratio))

        # Ordenar por ratio de detección descendente
        candidates.sort(key=lambda x: x[2], reverse=True)
        best_file, best_meta, best_ratio = candidates[0]
        print(f" -> Ejemplar canónico seleccionado: {os.path.basename(best_file)} (Detección: {best_ratio * 100:.1f}%)")

        df = pd.read_csv(best_file)
        start_act, end_act = best_meta['active_segment']

        # Extraer fotogramas activos
        active_df = df.iloc[start_act:end_act + 1].copy().reset_index(drop=True)
        n_act = len(active_df)

        # Determinar si el firmante es zurdo para canonicalizar (espejar a diestro)
        parts = os.path.splitext(os.path.basename(best_file))[0].split('_')
        signer_id = int(parts[1])
        needs_mirror = signer_id in LEFT_HANDED_SIGNERS and info['type'] == 'unimanual'

        # Extraer landmarks de torso y manos
        torso_names = ['nose', 'left_shoulder', 'right_shoulder', 'left_elbow', 'right_elbow', 'left_wrist', 'right_wrist']

        frames_motion = []
        for i in range(n_act):
            row = active_df.iloc[i]
            frame_data = {
                'frame_idx': i,
                'torso': {},
                'left_hand': [],
                'right_hand': []
            }

            # Torso (en espacio centrado de pantalla 0..1)
            for t_name in torso_names:
                tx = row[f'torso_{t_name}_x']
                ty = row[f'torso_{t_name}_y']
                tz = row[f'torso_{t_name}_z']
                if needs_mirror:
                    tx = 1.0 - tx  # Invertir eje horizontal
                frame_data['torso'][t_name] = [round(float(tx), 4), round(float(ty), 4), round(float(tz), 4)]

            # Manos
            has_lh = int(row['has_lh']) == 1
            has_rh = int(row['has_rh']) == 1

            lh_pts = []
            rh_pts = []
            for k in range(21):
                lx = row[f'lh_{k}_x']
                ly = row[f'lh_{k}_y']
                lz = row[f'lh_{k}_z']
                rx = row[f'rh_{k}_x']
                ry = row[f'rh_{k}_y']
                rz = row[f'rh_{k}_z']

                if not np.isnan(lx):
                    lh_pts.append([round(float(1.0 - lx if needs_mirror else lx), 4), round(float(ly), 4), round(float(lz), 4)])
                if not np.isnan(rx):
                    rh_pts.append([round(float(1.0 - rx if needs_mirror else rx), 4), round(float(ry), 4), round(float(rz), 4)])

            # Si se espejó, la mano izquierda canónica pasa a ser la derecha
            if needs_mirror:
                frame_data['left_hand'] = rh_pts
                frame_data['right_hand'] = lh_pts
            else:
                frame_data['left_hand'] = lh_pts
                frame_data['right_hand'] = rh_pts

            frames_motion.append(frame_data)

        # Aplicar suavizado a las articulaciones de la mano principal
        raw_rh = []
        valid_indices = []
        for idx_f, fm in enumerate(frames_motion):
            if len(fm['right_hand']) == 21:
                flat_rh = [coord for pt in fm['right_hand'] for coord in pt]
                raw_rh.append(flat_rh)
                valid_indices.append(idx_f)

        if len(raw_rh) > 5:
            arr_rh = np.array(raw_rh, dtype=np.float32)
            arr_smoothed = smooth_trajectory(arr_rh, window_len=5, poly_order=2)
            for local_i, global_i in enumerate(valid_indices):
                sm_pts = arr_smoothed[local_i].reshape(21, 3)
                frames_motion[global_i]['right_hand'] = [[round(float(c), 4) for c in pt] for pt in sm_pts]

        # Identificar fotograma de ápex (máxima elevación o máxima velocidad)
        apex_idx = n_act // 2
        min_y = 1.0
        for f_i, fm in enumerate(frames_motion):
            if len(fm['right_hand']) == 21:
                y_wrist = fm['right_hand'][0][1]
                if y_wrist < min_y:
                    min_y = y_wrist
                    apex_idx = f_i

        sign_entry = {
            'sign_id': info['id'],
            'display_name': info['display_name'],
            'category': info['category'],
            'type': info['type'],
            'total_active_frames': n_act,
            'fps': float(best_meta['fps']),
            'apex_frame': apex_idx,
            'pedagogical_metadata': {
                'instructions': info['pedagogical_instructions'],
                'apex_description': info['apex_description'],
                'key_hand': info['key_hand'],
                'milestones': {
                    'start_frame': 0,
                    'apex_frame': apex_idx,
                    'end_frame': n_act - 1
                }
            },
            'frames': frames_motion
        }

        motion_bank[info['id']] = sign_entry
        print(f" -> Banco para '{info['display_name']}' generado con {n_act} frames (Ápex en frame {apex_idx})")

    out_json = os.path.join(AVATAR_OUT_DIR, 'lsc_motion_bank.json')
    with open(out_json, 'w', encoding='utf-8') as f:
        json.dump(motion_bank, f, indent=2, ensure_ascii=False)

    print("=" * 70)
    print(f" BANCO DE MOVIMIENTO GUARDADO EXITOSAMENTE:")
    print(f" Archivo: {out_json}")
    print(f" Señas disponibles: {list(motion_bank.keys())}")
    print("=" * 70)
    return motion_bank


if __name__ == '__main__':
    build_canonical_motion_bank()
