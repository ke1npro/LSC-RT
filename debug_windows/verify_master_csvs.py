# -*- coding: utf-8 -*-
"""
verify_master_csvs.py
Verificación de calidad, integridad y consistencia de los Master CSVs generados.
"""

import os
import glob
import json
import pandas as pd

master_csvs = sorted(glob.glob(os.path.join(os.path.dirname(__file__), 'output', 'master_csv', '*_master.csv')))
print(f"Total Master CSVs: {len(master_csvs)}")

qa_results = []

for c in master_csvs:
    df = pd.read_csv(c)
    meta_path = c.replace('.csv', '_meta.json')
    meta = json.load(open(meta_path, 'r', encoding='utf-8'))

    total_nans = int(df.isna().sum().sum())
    rh_presence = float((df['has_rh'] == 1).mean() * 100)
    lh_presence = float((df['has_lh'] == 1).mean() * 100)

    qa = {
        'class_id': meta['class_id'],
        'sign_name': meta['sign_name'],
        'frames': len(df),
        'columns': len(df.columns),
        'total_nans': total_nans,
        'rh_presence_pct': rh_presence,
        'lh_presence_pct': lh_presence,
        'takes_fused': meta['takes_fused'],
        'apex_frame': meta['apex_frame'],
        'variance_residual': meta['rh_variance_residual']
    }
    qa_results.append(qa)

    print(f"[{qa['class_id']}] {qa['sign_name']}:")
    print(f"  Frames: {qa['frames']}, Columnas: {qa['columns']}, NaNs Totales: {qa['total_nans']}")
    print(f"  Presencia Manos: RH={qa['rh_presence_pct']:.1f}%, LH={qa['lh_presence_pct']:.1f}%")
    print(f"  Tomas Fusionadas: {qa['takes_fused']}, Cuadro Ápex: {qa['apex_frame']}")
    print(f"  Varianza Residual: {qa['variance_residual']:.6f}\n")

# Guardar reporte de QA
qa_file = os.path.join(os.path.dirname(__file__), 'output', 'master_csv', 'master_qa_summary.json')
with open(qa_file, 'w', encoding='utf-8') as f:
    json.dump(qa_results, f, indent=2, ensure_ascii=False)
print(f"Reporte de QA guardado en: {qa_file}")
