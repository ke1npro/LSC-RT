# -*- coding: utf-8 -*-
"""
evaluate_mvp_models.py

Evaluación MVP de Modelos para las 4 Clases de LSC:
1. GRACIAS
2. BUENOS DÍAS
3. BUENAS TARDES
4. BUENAS NOCHES

Compara dos paradigmas:
A) kNN-DTW (Dynamic Time Warping cinemático sobre trayectorias de muñecas y manos)
B) Modelo Neuronal Ligero (1D-CNN + BiGRU temporal sobre 134 landmarks normalizados)

Metodología de validación rigurosa:
- Intra-Firmante (Stratified 5-Fold CV)
- Inter-Firmante / Generalización a firmantes no vistos (LOSO - Leave-One-Signer-Out)
- Efecto de canonicalización por dominancia manual (espejado zurdo -> diestro)
"""

import os
import sys
import glob
import json
import time
import numpy as np
import pandas as pd
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix
from sklearn.model_selection import StratifiedKFold
import torch
import torch.nn as nn
import torch.optim as optim

WORKSPACE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
CSV_DIR = os.path.join(os.path.dirname(__file__), 'output', 'csv')

CLASS_MAP = {
    0: 'GRACIAS',
    1: 'BUENOS DÍAS',
    2: 'BUENAS TARDES',
    3: 'BUENAS NOCHES'
}

# Firmantes conocidos en LSC50:
# Firmantes 0, 2, 3, 4 son dominantes zurdos; Firmante 1 es dominante diestro
LEFT_HANDED_SIGNERS = {0, 2, 3, 4}


def temporal_resample(sequence, target_len=32):
    """Remuestrea una secuencia temporal (N, D) a target_len de forma uniforme."""
    n_frames, n_dims = sequence.shape
    if n_frames == target_len:
        return sequence.astype(np.float32)
    orig_t = np.linspace(0.0, 1.0, n_frames)
    target_t = np.linspace(0.0, 1.0, target_len)
    resampled = np.zeros((target_len, n_dims), dtype=np.float32)
    for d in range(n_dims):
        resampled[:, d] = np.interp(target_t, orig_t, sequence[:, d])
    return resampled


def load_dataset_from_csvs(csv_folder=CSV_DIR, target_len=32):
    """
    Carga los 80 CSVs, filtra por segmento activo, extrae características
    normalizadas y construye los tensores de entrenamiento.
    """
    csv_files = sorted(glob.glob(os.path.join(csv_folder, '*.csv')))
    if len(csv_files) == 0:
        raise FileNotFoundError(f"No se encontraron CSVs en: {csv_folder}")

    X_dtw_list = []      # Trayectorias cinemáticas de muñecas (T, 6)
    X_nn_list = []       # Representación vectorial completa (T, D)
    y_list = []
    signer_list = []
    rep_list = []
    file_list = []

    # Columnas normalizadas para el modelo neuronal:
    # 1. Torso: nariz, hombros, codos, muñecas (7 x 3 = 21 valores)
    # 2. Mano izquierda (21 x 3 = 63 valores)
    # 3. Mano derecha (21 x 3 = 63 valores)
    # 4. Indicadores de presencia: has_lh, has_rh (2 valores)
    # Total D = 149 dimensiones por frame

    for fpath in csv_files:
        fname = os.path.basename(fpath)
        base = os.path.splitext(fname)[0]
        parts = base.split('_')
        if len(parts) < 3:
            continue
        c_id = int(parts[0])
        s_id = int(parts[1])
        r_id = int(parts[2])

        if c_id not in CLASS_MAP:
            continue

        df = pd.read_csv(fpath)

        # Filtrar por segmento activo si existe
        active_df = df[df['is_active'] == 1]
        if len(active_df) < 6:
            # Fallback a todo el video si el segmento activo es muy corto
            active_df = df

        # A. Características para DTW:
        # Muñeca izquierda y derecha normalizadas respecto a esternón (x, y, z)
        dtw_cols = [
            'norm_torso_left_wrist_x', 'norm_torso_left_wrist_y', 'norm_torso_left_wrist_z',
            'norm_torso_right_wrist_x', 'norm_torso_right_wrist_y', 'norm_torso_right_wrist_z'
        ]
        dtw_feats = active_df[dtw_cols].fillna(0.0).values
        dtw_resampled = temporal_resample(dtw_feats, target_len=16)

        # B. Características completas para Red Neuronal:
        torso_cols = [c for c in active_df.columns if c.startswith('norm_torso_') and not c.endswith('_vis')]
        lh_cols = [c for c in active_df.columns if c.startswith('norm_lh_')]
        rh_cols = [c for c in active_df.columns if c.startswith('norm_rh_')]
        mask_cols = ['has_lh', 'has_rh']

        nn_cols = torso_cols + lh_cols + rh_cols + mask_cols
        nn_feats = active_df[nn_cols].fillna(0.0).values
        nn_resampled = temporal_resample(nn_feats, target_len=target_len)

        X_dtw_list.append(dtw_resampled)
        X_nn_list.append(nn_resampled)
        y_list.append(c_id)
        signer_list.append(s_id)
        rep_list.append(r_id)
        file_list.append(fname)

    return {
        'X_dtw': np.array(X_dtw_list, dtype=np.float32),
        'X_nn': np.array(X_nn_list, dtype=np.float32),
        'y': np.array(y_list, dtype=np.int64),
        'signers': np.array(signer_list, dtype=np.int64),
        'reps': np.array(rep_list, dtype=np.int64),
        'files': file_list
    }


def compute_dtw_distance(s1, s2):
    """
    Calcula la distancia DTW euclidiana estándar entre dos secuencias (T, D)
    con ventana Sakoe-Chiba adaptativa.
    """
    n, d = s1.shape
    m, _ = s2.shape
    w = max(abs(n - m), 4)

    dtw_matrix = np.full((n + 1, m + 1), np.inf, dtype=np.float32)
    dtw_matrix[0, 0] = 0.0

    for i in range(1, n + 1):
        for j in range(max(1, i - w), min(m + 1, i + w + 1)):
            cost = np.linalg.norm(s1[i - 1] - s2[j - 1])
            dtw_matrix[i, j] = cost + min(
                dtw_matrix[i - 1, j],       # Inserción
                dtw_matrix[i, j - 1],       # Eliminación
                dtw_matrix[i - 1, j - 1]    # Coincidencia
            )

    return dtw_matrix[n, m] / float(n + m)


def evaluate_knn_dtw(X_dtw, y, signers, k=1, canonicalize=True):
    """
    Evalúa el clasificador kNN-DTW en dos regímenes:
    1. Stratified 5-Fold (Intra-Firmante)
    2. Leave-One-Signer-Out (LOSO)
    """
    N = len(X_dtw)

    # Espejado para canonicalizar firmantes zurdos -> diestros
    X_processed = X_dtw.copy()
    if canonicalize:
        for i in range(N):
            if signers[i] in LEFT_HANDED_SIGNERS:
                # Invertir eje X y alternar muñeca izquierda <-> muñeca derecha
                # Coords: [lx, ly, lz, rx, ry, rz]
                orig = X_processed[i].copy()
                X_processed[i, :, 0] = -orig[:, 3]
                X_processed[i, :, 1] = orig[:, 4]
                X_processed[i, :, 2] = orig[:, 5]
                X_processed[i, :, 3] = -orig[:, 0]
                X_processed[i, :, 4] = orig[:, 1]
                X_processed[i, :, 5] = orig[:, 2]

    # Precomputar matriz simétrica de distancias DTW
    print("Precomputando matriz de distancias DTW por pares...")
    dist_mat = np.zeros((N, N), dtype=np.float32)
    for i in range(N):
        for j in range(i + 1, N):
            d = compute_dtw_distance(X_processed[i], X_processed[j])
            dist_mat[i, j] = d
            dist_mat[j, i] = d

    # 1. Evaluación Intra-Firmante (Stratified 5-Fold CV)
    skf = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
    intra_preds = np.zeros(N, dtype=np.int64)

    for train_idx, test_idx in skf.split(X_processed, y):
        for te in test_idx:
            sub_dists = dist_mat[te, train_idx]
            nn_indices = np.argsort(sub_dists)[:k]
            nearest_classes = y[train_idx][nn_indices]
            # Voto mayoritario
            intra_preds[te] = np.bincount(nearest_classes).argmax()

    intra_acc = float(accuracy_score(y, intra_preds))

    # 2. Evaluación LOSO (Leave-One-Signer-Out)
    loso_preds = np.zeros(N, dtype=np.int64)
    unique_signers = np.unique(signers)
    loso_signer_accs = {}

    for s_test in unique_signers:
        test_mask = (signers == s_test)
        train_mask = ~test_mask
        train_indices = np.where(train_mask)[0]
        test_indices = np.where(test_mask)[0]

        for te in test_indices:
            sub_dists = dist_mat[te, train_indices]
            nn_indices = np.argsort(sub_dists)[:k]
            nearest_classes = y[train_indices][nn_indices]
            loso_preds[te] = np.bincount(nearest_classes).argmax()

        acc_s = float(accuracy_score(y[test_indices], loso_preds[test_indices]))
        loso_signer_accs[int(s_test)] = acc_s

    loso_acc = float(accuracy_score(y, loso_preds))

    return {
        'intra_acc': intra_acc,
        'loso_acc': loso_acc,
        'loso_per_signer': loso_signer_accs,
        'intra_preds': intra_preds.tolist(),
        'loso_preds': loso_preds.tolist()
    }


# =========================================================================
# MODELO NEURONAL: 1D-CNN + BiGRU
# =========================================================================

class SignGestureBiGRU(nn.Module):
    """
    Arquitectura neuronal compacta optimizada para reconocimiento
    de señas temporalmente invariante.
    """
    def __init__(self, input_dim, hidden_dim=64, num_classes=4):
        super().__init__()
        # Extracción convolucional temporal local
        self.conv = nn.Sequential(
            nn.Conv1d(input_dim, 64, kernel_size=3, padding=1),
            nn.BatchNorm1d(64),
            nn.ReLU(),
            nn.Dropout(0.2)
        )
        # Modelado secuencial bidireccional
        self.gru = nn.GRU(64, hidden_dim, num_layers=2, batch_first=True, bidirectional=True, dropout=0.2)
        # Clasificador final
        self.fc = nn.Sequential(
            nn.Linear(hidden_dim * 2, 64),
            nn.ReLU(),
            nn.Dropout(0.3),
            nn.Linear(64, num_classes)
        )

    def forward(self, x):
        # x: (B, T, D) -> transponer a (B, D, T) para Conv1d
        x_conv = self.conv(x.transpose(1, 2)).transpose(1, 2)
        gru_out, _ = self.gru(x_conv)  # (B, T, hidden_dim * 2)
        # Global Average Pooling temporal
        pooled = torch.mean(gru_out, dim=1)
        logits = self.fc(pooled)
        return logits


def train_and_eval_neural_model(X_nn, y, signers, epochs=60, lr=1e-3):
    """
    Entrena y evalúa la red neuronal mediante validación LOSO completa (5 pliegues).
    """
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    input_dim = X_nn.shape[2]
    num_classes = len(CLASS_MAP)
    unique_signers = np.unique(signers)

    loso_preds = np.zeros(len(y), dtype=np.int64)
    loso_signer_accs = {}

    print(f"Iniciando evaluación neuronal LOSO sobre dispositivo: {device}")
    print(f"Dimensiones de entrada: {X_nn.shape} -> Features: {input_dim}")

    for s_test in unique_signers:
        test_mask = (signers == s_test)
        train_mask = ~test_mask

        X_train_t = torch.tensor(X_nn[train_mask], dtype=torch.float32).to(device)
        y_train_t = torch.tensor(y[train_mask], dtype=torch.long).to(device)
        X_test_t = torch.tensor(X_nn[test_mask], dtype=torch.float32).to(device)
        y_test_t = torch.tensor(y[test_mask], dtype=torch.long).to(device)

        model = SignGestureBiGRU(input_dim=input_dim, hidden_dim=64, num_classes=num_classes).to(device)
        optimizer = optim.Adam(model.parameters(), lr=lr, weight_decay=1e-4)
        criterion = nn.CrossEntropyLoss()

        model.train()
        for epoch in range(epochs):
            optimizer.zero_grad()
            outputs = model(X_train_t)
            loss = criterion(outputs, y_train_t)
            loss.backward()
            optimizer.step()

        model.eval()
        with torch.no_grad():
            test_logits = model(X_test_t)
            preds = torch.argmax(test_logits, dim=1).cpu().numpy()

        loso_preds[test_mask] = preds
        fold_acc = float(accuracy_score(y[test_mask], preds))
        loso_signer_accs[int(s_test)] = fold_acc
        print(f"   -> Firmante {s_test} test: Exactitud = {fold_acc * 100:.1f}%")

    overall_loso = float(accuracy_score(y, loso_preds))
    return {
        'loso_acc': overall_loso,
        'loso_per_signer': loso_signer_accs,
        'loso_preds': loso_preds.tolist()
    }


def run_mvp_benchmark():
    output_dir = os.path.join(os.path.dirname(__file__), 'output')
    print("=" * 70)
    print(" BENCHMARK MVP: kNN-DTW vs. RED NEURONAL (4 CLASES LSC50 - 80 VIDEOS)")
    print("=" * 70)

    t0_load = time.time()
    data = load_dataset_from_csvs()
    print(f"Dataset cargado en {time.time() - t0_load:.2f} s:")
    print(f" - Total muestras: {len(data['y'])} CSVs")
    print(f" - Clases: {[f'{c}: {CLASS_MAP[c]}' for c in np.unique(data['y'])]}")
    print(f" - Firmantes: {np.unique(data['signers'])} (16 repeticiones por firmante)")

    # 1. Benchmark kNN-DTW
    print("\n--- 1. EVALUANDO MODELO kNN-DTW (1-NN Y 3-NN) ---")
    t0_dtw = time.time()
    dtw_1nn_raw = evaluate_knn_dtw(data['X_dtw'], data['y'], data['signers'], k=1, canonicalize=False)
    dtw_1nn_canon = evaluate_knn_dtw(data['X_dtw'], data['y'], data['signers'], k=1, canonicalize=True)
    dtw_3nn_canon = evaluate_knn_dtw(data['X_dtw'], data['y'], data['signers'], k=3, canonicalize=True)
    dtw_elapsed = time.time() - t0_dtw
    print(f"DTW completado en {dtw_elapsed:.2f} s")

    # 2. Benchmark Red Neuronal (1D-CNN + BiGRU)
    print("\n--- 2. EVALUANDO MODELO NEURONAL (1D-CNN + BiGRU) ---")
    t0_nn = time.time()
    nn_results = train_and_eval_neural_model(data['X_nn'], data['y'], data['signers'], epochs=70, lr=1.5e-3)
    nn_elapsed = time.time() - t0_nn
    print(f"Red Neuronal completada en {nn_elapsed:.2f} s")

    # Consolidar resultados
    report = {
        'total_samples': len(data['y']),
        'classes': CLASS_MAP,
        'knn_dtw_1nn_raw': {
            'intra_acc': dtw_1nn_raw['intra_acc'],
            'loso_acc': dtw_1nn_raw['loso_acc']
        },
        'knn_dtw_1nn_canonicalized': {
            'intra_acc': dtw_1nn_canon['intra_acc'],
            'loso_acc': dtw_1nn_canon['loso_acc'],
            'loso_per_signer': dtw_1nn_canon['loso_per_signer']
        },
        'knn_dtw_3nn_canonicalized': {
            'intra_acc': dtw_3nn_canon['intra_acc'],
            'loso_acc': dtw_3nn_canon['loso_acc'],
            'loso_per_signer': dtw_3nn_canon['loso_per_signer']
        },
        'neural_cnn_bigru': {
            'loso_acc': nn_results['loso_acc'],
            'loso_per_signer': nn_results['loso_per_signer']
        }
    }

    report_path = os.path.join(output_dir, 'mvp_benchmark_results.json')
    with open(report_path, 'w', encoding='utf-8') as f:
        json.dump(report, f, indent=2, ensure_ascii=False)

    print("\n" + "=" * 70)
    print(" RESUMEN COMPARATIVO DEL BENCHMARK MVP")
    print("=" * 70)
    print(f"{'Modelo':<35} | {'Intra-Firmante (CV)':<20} | {'LOSO Inter-Firmante':<20}")
    print("-" * 79)
    print(f"{'1-NN DTW (Sin canonicalizar)':<35} | {dtw_1nn_raw['intra_acc']*100:<19.2f}% | {dtw_1nn_raw['loso_acc']*100:<19.2f}%")
    print(f"{'1-NN DTW (Canonicalizado)':<35} | {dtw_1nn_canon['intra_acc']*100:<19.2f}% | {dtw_1nn_canon['loso_acc']*100:<19.2f}%")
    print(f"{'3-NN DTW (Canonicalizado)':<35} | {dtw_3nn_canon['intra_acc']*100:<19.2f}% | {dtw_3nn_canon['loso_acc']*100:<19.2f}%")
    print(f"{'Red Neuronal (1D-CNN + BiGRU)':<35} | {'--':<20} | {nn_results['loso_acc']*100:<19.2f}%")
    print("=" * 70)

    # Matriz de confusión para el mejor modelo LOSO
    y_true = data['y']
    y_pred_dtw = np.array(dtw_1nn_canon['loso_preds'])
    y_pred_nn = np.array(nn_results['loso_preds'])

    print("\nMatriz de Confusión LOSO - Red Neuronal:")
    target_names = [CLASS_MAP[i] for i in range(4)]
    cm_nn = confusion_matrix(y_true, y_pred_nn)
    print(pd.DataFrame(cm_nn, index=target_names, columns=target_names))

    print("\nReporte de Clasificación Detallado (Red Neuronal LOSO):")
    print(classification_report(y_true, y_pred_nn, target_names=target_names))

    return report


if __name__ == '__main__':
    run_mvp_benchmark()
