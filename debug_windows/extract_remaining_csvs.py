# -*- coding: utf-8 -*-
"""
extract_remaining_csvs.py

Procesa las repeticiones restantes (0001, 0002, 0003) para las 4 clases:
- 0000: "GRACIAS"
- 0001: "BUENOS DÍAS"
- 0002: "BUENAS TARDES"
- 0003: "BUENAS NOCHES"
A través de los 5 firmantes (0000 a 0004), completando los 80 CSVs.

Optimizado: Solo extracción y generación de CSV (sin renderizado de video),
garantizando máxima velocidad y preservando la integridad de los videos base.
"""

import os
import sys
import time
import json
import numpy as np
import pandas as pd

from extract_bimanual_csv import (
    create_landmarker_detectors,
    extract_video_landmarks,
    build_hybrid_csv,
    WORKSPACE_DIR
)

SIGN_CLASSES = {
    '0000': 'GRACIAS',
    '0001': 'BUENOS DÍAS',
    '0002': 'BUENAS TARDES',
    '0003': 'BUENAS NOCHES'
}


def process_all_80_csvs():
    output_dir = os.path.join(os.path.dirname(__file__), 'output')
    csv_dir = os.path.join(output_dir, 'csv')
    os.makedirs(csv_dir, exist_ok=True)
    video_dir = os.path.join(WORKSPACE_DIR, 'dataset', 'VIDEOS', 'COLOR_BODY')

    print("=" * 70)
    print(" EXTRACCIÓN MASIVA DE CSVs PARA LAS 4 CLASES (80 VIDEOS EN TOTAL)")
    print("=" * 70)

    # Identificar videos a procesar
    tasks = []
    for class_id, sign_name in SIGN_CLASSES.items():
        for signer_num in range(5):
            for rep_num in range(4):
                s_id = f'{signer_num:04d}'
                r_id = f'{rep_num:04d}'
                base_name = f'{class_id}_{s_id}_{r_id}'
                v_path = os.path.join(video_dir, f'{base_name}.avi')
                out_csv = os.path.join(csv_dir, f'{base_name}.csv')
                tasks.append({
                    'class_id': class_id,
                    'sign_name': sign_name,
                    'signer_id': s_id,
                    'rep_id': r_id,
                    'base_name': base_name,
                    'video_path': v_path,
                    'csv_path': out_csv,
                    'already_exists': os.path.exists(out_csv)
                })

    pending = [t for t in tasks if not t['already_exists']]
    print(f"Total videos configurados: {len(tasks)}")
    print(f"CSVs ya existentes: {len(tasks) - len(pending)}")
    print(f"CSVs pendientes por procesar: {len(pending)}")

    t_start_all = time.time()
    processed_count = 0

    for idx, t in enumerate(pending, 1):
        bname = t['base_name']
        print(f"[{idx:02d}/{len(pending):02d}] Extrayendo CSV: {bname} -> {t['sign_name']} (S{t['signer_id']} R{t['rep_id']})...", end='', flush=True)
        t0 = time.time()

        # Detector con estado aislado por video
        p_detector, h_detector = create_landmarker_detectors()

        res = extract_video_landmarks(t['video_path'], p_detector, h_detector)
        build_hybrid_csv(res, t['csv_path'])

        p_detector.close()
        h_detector.close()

        # Guardar metadatos individuales
        out_meta = os.path.join(csv_dir, f"{bname}_meta.json")
        meta = {
            'video_file': os.path.abspath(t['video_path']),
            'base_name': bname,
            'fps': res['fps'],
            'total_frames': res['total_frames'],
            'active_segment': [int(res['active_segment'][0]), int(res['active_segment'][1])],
            'lh_detection_ratio': float(np.mean(res['mask'][:, 1])),
            'rh_detection_ratio': float(np.mean(res['mask'][:, 2])),
            'pose_detection_ratio': float(np.mean(res['mask'][:, 0]))
        }
        with open(out_meta, 'w', encoding='utf-8') as f:
            json.dump(meta, f, indent=2, ensure_ascii=False)

        elapsed = time.time() - t0
        lh_pct = meta['lh_detection_ratio'] * 100
        rh_pct = meta['rh_detection_ratio'] * 100
        print(f" Listo ({elapsed:.2f}s | {res['total_frames']} fr | LH: {lh_pct:.1f}% | RH: {rh_pct:.1f}%)")
        processed_count += 1

    total_time = time.time() - t_start_all
    print("=" * 70)
    print(f" EXTRACCIÓN COMPLETADA: {processed_count} CSVs generados en {total_time:.2f} s ({total_time/60.0:.2f} min)")
    print(f" Total CSVs disponibles en dataset: {len(tasks)}")
    print("=" * 70)


if __name__ == '__main__':
    process_all_80_csvs()
