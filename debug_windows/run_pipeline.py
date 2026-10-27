# -*- coding: utf-8 -*-
"""
run_pipeline.py

Orquestador del pipeline piloto para LSC (WindowsTest):
Procesa las 4 clases seleccionadas:
- 0000: "GRACIAS"
- 0001: "BUENOS DÍAS"
- 0002: "BUENAS TARDES"
- 0003: "BUENAS NOCHES"
A través de los 5 firmantes (0000 a 0004), repetición 0000 (20 videos en total).

Genera:
1. CSVs híbridos en debug_windows/output/csv/
2. Videos con overlay en debug_windows/output/overlays/
3. Capturas inicial, final y Side-by-Side en debug_windows/output/screenshots/
4. Reporte consolidado en debug_windows/output/pilot_summary.json
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
from render_video_overlay import render_overlay_and_screenshots

SIGN_CLASSES = {
    '0000': 'GRACIAS',
    '0001': 'BUENOS DÍAS',
    '0002': 'BUENAS TARDES',
    '0003': 'BUENAS NOCHES'
}


def run_pilot_batch():
    output_dir = os.path.join(os.path.dirname(__file__), 'output')
    os.makedirs(output_dir, exist_ok=True)
    video_dir = os.path.join(WORKSPACE_DIR, 'dataset', 'VIDEOS', 'COLOR_BODY')

    print("=" * 70)
    print(" INICIANDO PIPELINE PILOTO BIMANUAL (20 VIDEOS) - LSC50")
    print("=" * 70)

    summary_records = []
    total_start = time.time()

    item_idx = 1
    total_items = len(SIGN_CLASSES) * 5

    for class_id, sign_name in SIGN_CLASSES.items():
        for signer_num in range(5):
            signer_id = f'{signer_num:04d}'
            rep_id = '0000'
            video_basename = f'{class_id}_{signer_id}_{rep_id}'
            video_path = os.path.join(video_dir, f'{video_basename}.avi')

            if not os.path.exists(video_path):
                print(f"[{item_idx:02d}/{total_items:02d}] Video no encontrado: {video_path}")
                item_idx += 1
                continue

            print(f"\n[{item_idx:02d}/{total_items:02d}] Procesando: {video_basename} -> {sign_name} (Firmante {signer_num})")
            t_vid_start = time.time()

            # Instanciar detectores independientes por video para reiniciar estado temporal de MediaPipe
            p_detector, h_detector = create_landmarker_detectors()

            # A. Extracción de landmarks
            res = extract_video_landmarks(video_path, p_detector, h_detector)
            out_csv = os.path.join(output_dir, 'csv', f'{video_basename}.csv')
            build_hybrid_csv(res, out_csv)

            # Cerrar detectores al terminar la extracción del video
            p_detector.close()
            h_detector.close()

            # B. Renderizado de overlay y capturas
            render_res = render_overlay_and_screenshots(
                video_path=video_path,
                csv_path=out_csv,
                output_dir=output_dir,
                sign_label=f"{sign_name} (S{signer_num})"
            )

            elapsed = time.time() - t_vid_start

            lh_ratio = float(np.mean(res['mask'][:, 1])) * 100
            rh_ratio = float(np.mean(res['mask'][:, 2])) * 100
            pose_ratio = float(np.mean(res['mask'][:, 0])) * 100
            start_act, end_act = res['active_segment']
            act_len = end_act - start_act + 1

            record = {
                'class_id': class_id,
                'sign_name': sign_name,
                'signer_id': signer_id,
                'video_basename': video_basename,
                'total_frames': res['total_frames'],
                'fps': res['fps'],
                'active_segment': [int(start_act), int(end_act)],
                'active_frames_count': int(act_len),
                'pose_ratio_pct': round(pose_ratio, 1),
                'lh_ratio_pct': round(lh_ratio, 1),
                'rh_ratio_pct': round(rh_ratio, 1),
                'csv_path': os.path.abspath(out_csv),
                'overlay_video': os.path.abspath(render_res['video_overlay']),
                'side_by_side_img': os.path.abspath(render_res['side_by_side']),
                'elapsed_sec': round(elapsed, 2)
            }
            summary_records.append(record)

            print(f"   -> Frames: {res['total_frames']} | Activo: [{start_act}..{end_act}] ({act_len} frames)")
            print(f"   -> Deteccion: Pose {pose_ratio:.1f}% | Mano Izq: {lh_ratio:.1f}% | Mano Der: {rh_ratio:.1f}%")
            print(f"   -> Completado en {elapsed:.2f} s | Side-by-Side: {os.path.basename(render_res['side_by_side'])}")

            item_idx += 1

    total_time = time.time() - total_start
    summary_path = os.path.join(output_dir, 'pilot_summary.json')
    with open(summary_path, 'w', encoding='utf-8') as f:
        json.dump(summary_records, f, indent=2, ensure_ascii=False)

    print("\n" + "=" * 70)
    print(f" PIPELINE PILOTO FINALIZADO EN {total_time:.2f} s ({total_time/60.0:.2f} min)")
    print(f" Resumen guardado en: {summary_path}")
    print("=" * 70)

    # Mostrar tabla resumen
    df_sum = pd.DataFrame(summary_records)
    cols_display = ['video_basename', 'sign_name', 'total_frames', 'active_segment', 'pose_ratio_pct', 'lh_ratio_pct', 'rh_ratio_pct', 'elapsed_sec']
    print("\nResumen Cuantitativo:")
    print(df_sum[cols_display].to_string(index=False))

    return summary_records


if __name__ == '__main__':
    run_pilot_batch()
