# -*- coding: utf-8 -*-
"""
benchmark_50_master.py

Evalúa la capacidad de generalización y reconocimiento de los 50 Master CSVs
frente a las tomas del dataset LSC50 (5 señantes x 4 repeticiones x 50 clases).

Utiliza alineación de trayectorias con normas L2 euclidianas continuas
sobre los 147 puntos anatómicos cinemáticos (7 torso x 3 + 21 mano izq x 3 + 21 mano der x 3).
"""

import os
import sys
import glob
import time
import json
import numpy as np
import pandas as pd

sys.path.insert(0, os.path.dirname(__file__))
from synthesize_all_50_master import process_npz_take, resample_take

MASTER_DIR = os.path.join(os.path.dirname(__file__), 'output', 'master_csv')
NPZ_DIR = os.path.abspath('dataset/PROCESSED_NPZ')

POSE_NAMES = ['nose', 'left_shoulder', 'right_shoulder', 'left_elbow', 'right_elbow', 'left_wrist', 'right_wrist']

# 1. Cargar los 50 Master Prototypes
print("Cargando los 50 Master Prototypes...")
master_templates = []

for c in range(50):
    class_id = f"{c:04d}"
    csv_path = os.path.join(MASTER_DIR, f"{class_id}_master.csv")
    df = pd.read_csv(csv_path)

    # Extraer los 60 cuadros activos [12:72]
    active_df = df[df['is_active'] == 1].reset_index(drop=True)

    cols = []
    for p in POSE_NAMES:
        cols.extend([f'torso_{p}_x', f'torso_{p}_y', f'torso_{p}_z'])
    for k in range(21):
        cols.extend([f'lh_{k}_x', f'lh_{k}_y', f'lh_{k}_z'])
    for k in range(21):
        cols.extend([f'rh_{k}_x', f'rh_{k}_y', f'rh_{k}_z'])

    mat = active_df[cols].values.astype(np.float32)
    master_templates.append((c, mat))

print(f"50 Master Templates cargados. Dimensionalidad por plantilla: {master_templates[0][1].shape}")

# 2. Seleccionar tomas de prueba: Repetición 0 de todos los señantes (5 señantes x 50 clases = 250 tomas)
test_files = sorted(glob.glob(os.path.join(NPZ_DIR, '*_0000.npz')))
print(f"Total tomas de prueba (repetición 0 de los 5 señantes): {len(test_files)}")

correct_top1 = 0
correct_top3 = 0
correct_top5 = 0
total = 0

signer_correct = {s: 0 for s in range(5)}
signer_total = {s: 0 for s in range(5)}

t0 = time.time()

for idx, f in enumerate(test_files):
    base = os.path.splitext(os.path.basename(f))[0]
    parts = base.split('_')
    true_class = int(parts[0])
    signer_id = int(parts[1])

    take_dict = process_npz_take(f)
    res = resample_take(take_dict, target_frames=60)

    test_feat = np.hstack([
        res['torso'].reshape(60, -1),
        res['lh'].reshape(60, -1),
        res['rh'].reshape(60, -1)
    ])

    # Comparar contra cada uno de los 50 Master Templates
    distances = []
    for c_id, master_mat in master_templates:
        # Distancia euclidiana media cuadro a cuadro a lo largo de los 60 frames
        dist = float(np.mean(np.linalg.norm(test_feat - master_mat, axis=1)))
        distances.append((c_id, dist))

    distances.sort(key=lambda x: x[1])
    ranked_classes = [d[0] for d in distances]

    is_top1 = (ranked_classes[0] == true_class)
    is_top3 = (true_class in ranked_classes[:3])
    is_top5 = (true_class in ranked_classes[:5])

    if is_top1:
        correct_top1 += 1
        signer_correct[signer_id] += 1
    if is_top3:
        correct_top3 += 1
    if is_top5:
        correct_top5 += 1

    total += 1
    signer_total[signer_id] += 1

    if (idx + 1) % 50 == 0:
        print(f"[{idx+1}/{len(test_files)}] Top-1: {correct_top1/total*100:.1f}%, Top-3: {correct_top3/total*100:.1f}%, Top-5: {correct_top5/total*100:.1f}%")

total_time = time.time() - t0
print("\n" + "=" * 65)
print(f"EVALUACIÓN DE LOS 50 MASTER PROTOTYPES COMPLETADA ({total_time:.2f} s)")
print("=" * 65)
print(f"Exactitud Global Top-1: {correct_top1/total*100:.2f}% ({correct_top1}/{total})")
print(f"Exactitud Global Top-3: {correct_top3/total*100:.2f}% ({correct_top3}/{total})")
print(f"Exactitud Global Top-5: {correct_top5/total*100:.2f}% ({correct_top5}/{total})")
print("\nDesglose de Exactitud Top-1 por Señante:")
for s in range(5):
    print(f"  Señante {s} (Signer {s}): {signer_correct[s]/signer_total[s]*100:.2f}% ({signer_correct[s]}/{signer_total[s]})")
print("=" * 65)
