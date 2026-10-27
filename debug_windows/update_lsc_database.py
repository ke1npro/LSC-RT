# -*- coding: utf-8 -*-
"""
update_lsc_database.py

Descarga, normaliza y actualiza la base de datos completa del Alfabeto LSC
(Lengua de Señas Colombiana) en 'assets/lsc_database.json'.

Cubre las 27 letras oficiales (A - Z incluyendo la Ñ):
- Extrae las coordenadas de MediaPipe Hands de cada signo.
- Aplica exactamente la función 'preProcessLandmarks' de Flutter (PredictSignUseCase):
  1. Ancla en la muñeca (Landmark 0 -> 0.0, 0.0).
  2. Coordenadas relativas divididas por maxAbs en rango [-1.0, 1.0].
  3. Vector de exactamente 42 dimensiones (21 puntos x 2 coordenadas).
- Reemplaza/sobrescribe todas las letras garantizando homogeneidad y coherencia con MediaPipe.
- Ejecuta una validación de exactitud con k-NN sobre las 27 clases.
"""

import os
import sys
import json
import urllib.request
import io
import time
import numpy as np

WORKSPACE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
DB_PATH = os.path.join(WORKSPACE_DIR, 'assets', 'lsc_database.json')

ALPHABET_MAP = [
    ('A', 'A'), ('B', 'B'), ('C', 'C'), ('D', 'D'), ('E', 'E'),
    ('F', 'F'), ('G', 'G'), ('H', 'H'), ('I', 'I'), ('J', 'J'),
    ('K', 'K'), ('L', 'L'), ('M', 'M'), ('N', 'N'), ('Ñ', '%C3%91'),
    ('O', 'O'), ('P', 'P'), ('Q', 'Q'), ('R', 'R'), ('S', 'S'),
    ('T', 'T'), ('U', 'U'), ('V', 'V'), ('W', 'W'), ('X', 'X'),
    ('Y', 'Y'), ('Z', 'Z')
]

BASE_REPO_URL = "https://raw.githubusercontent.com/FerchoRV/LSTM-Reconocimiento-de-signos-colombianos/main/Datasets/LSC_Signos_Data"


def preprocess_landmarks_flutter_compatible(pts_21x3):
    """
    Replica de forma exacta la lógica de PredictSignUseCase.preProcessLandmarks de Flutter:
    - Base: landmarks[0].x, landmarks[0].y
    - rx = lm.x - baseX, ry = lm.y - baseY
    - Normalizado por maxAbs
    - Salida: lista de 42 doubles
    """
    base_x = pts_21x3[0, 0]
    base_y = pts_21x3[0, 1]

    rel_coords = []
    max_abs = 0.0

    for i in range(21):
        rx = float(pts_21x3[i, 0] - base_x)
        ry = float(pts_21x3[i, 1] - base_y)
        rel_coords.append(rx)
        rel_coords.append(ry)

        if abs(rx) > max_abs:
            max_abs = abs(rx)
        if abs(ry) > max_abs:
            max_abs = abs(ry)

    if max_abs == 0.0:
        max_abs = 1.0

    return [round(float(val / max_abs), 6) for val in rel_coords]


def fetch_letter_samples(letter_key, url_folder, target_samples=20):
    """
    Descarga secuencias para una letra y extrae hasta target_samples muestras válidas.
    """
    samples = []
    # Marcos clave en cada secuencia (el gesto es sostenido en el centro de la secuencia)
    key_frames = [15, 12, 18, 10, 20]

    for seq in range(30):
        if len(samples) >= target_samples:
            break

        for f_num in key_frames:
            url = f"{BASE_REPO_URL}/{url_folder}/{seq}/{f_num}.npy"
            try:
                req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
                with urllib.request.urlopen(req, timeout=4) as resp:
                    arr = np.load(io.BytesIO(resp.read()))

                    # El archivo contiene 126 valores: 63 mano izquierda + 63 mano derecha
                    lh_raw = arr[:63]
                    rh_raw = arr[63:]

                    active_hand = None
                    if np.count_nonzero(rh_raw) >= 42:
                        active_hand = rh_raw.reshape(21, 3)
                    elif np.count_nonzero(lh_raw) >= 42:
                        active_hand = lh_raw.reshape(21, 3)

                    if active_hand is not None:
                        # Verificar que no sean todos ceros o ruido plano
                        span = np.ptp(active_hand[:, :2], axis=0)
                        if span[0] > 0.02 and span[1] > 0.02:
                            norm_42 = preprocess_landmarks_flutter_compatible(active_hand)
                            samples.append(norm_42)
                            break  # Pasar a la siguiente secuencia para tener diversidad
            except Exception:
                continue

    return samples


def build_and_save_alphabet_database():
    print("=" * 70)
    print(" ACTUALIZACIÓN INTEGRAL DEL ALFABETO LSC (27 LETRAS: A-Z + Ñ)")
    print("=" * 70)

    # Hacer backup preventivo del lsc_database.json actual
    if os.path.exists(DB_PATH):
        backup_path = DB_PATH.replace('.json', '_backup.json')
        with open(DB_PATH, 'r', encoding='utf-8') as f_in, open(backup_path, 'w', encoding='utf-8') as f_out:
            f_out.write(f_in.read())
        print(f"Copia de respaldo creada en: {backup_path}")

    new_database = {}
    t_start = time.time()

    for idx, (letter_name, folder_url) in enumerate(ALPHABET_MAP, 1):
        print(f"[{idx:02d}/27] Descargando y normalizando letra '{letter_name}'...", end='', flush=True)
        t0 = time.time()

        samples = fetch_letter_samples(letter_name, folder_url, target_samples=20)
        elapsed = time.time() - t0

        if len(samples) >= 15:
            new_database[letter_name] = samples
            print(f" Listo ({len(samples)} muestras en {elapsed:.2f}s)")
        else:
            print(f" Advertencia: Solo se obtuvieron {len(samples)} muestras")
            new_database[letter_name] = samples

    # Guardar la nueva base de datos JSON
    with open(DB_PATH, 'w', encoding='utf-8') as f:
        json.dump(new_database, f, indent=2, ensure_ascii=False)

    total_time = time.time() - t_start
    total_samples = sum(len(s) for s in new_database.values())

    print("\n" + "=" * 70)
    print(f" BASE DE DATOS LSC ACTUALIZADA EXITOSAMENTE EN: {DB_PATH}")
    print(f" - Letras totales: {len(new_database)} / 27")
    print(f" - Muestras totales: {total_samples}")
    print(f" - Tiempo de descarga y normalización: {total_time:.2f} s")
    print("=" * 70)

    # Validación cruzada 5-Fold sobre el alfabeto completo
    evaluate_alphabet_database(new_database)

    return new_database


def evaluate_alphabet_database(database):
    """Evalúa la precisión del clasificador k-NN (PredictSignUseCase) sobre las 27 letras."""
    print("\n--- VALIDACIÓN DEL CLASIFICADOR SOBRE LAS 27 LETRAS DEL ALFABETO ---")
    X = []
    y = []
    labels = sorted(list(database.keys()))
    label_to_id = {l: i for i, l in enumerate(labels)}

    for letter, samples in database.items():
        for s in samples:
            X.append(s)
            y.append(label_to_id[letter])

    X = np.array(X, dtype=np.float32)
    y = np.array(y, dtype=np.int32)

    # 1-NN Euclidean Leave-One-Out / 5-Fold
    from sklearn.model_selection import StratifiedKFold
    from sklearn.neighbors import KNeighborsClassifier
    from sklearn.metrics import accuracy_score

    skf = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
    preds = np.zeros(len(y), dtype=np.int32)

    for train_idx, test_idx in skf.split(X, y):
        knn = KNeighborsClassifier(n_neighbors=1, metric='euclidean')
        knn.fit(X[train_idx], y[train_idx])
        preds[test_idx] = knn.predict(X[test_idx])

    acc = accuracy_score(y, preds)
    print(f"Exactitud Global 1-NN (5-Fold CV) sobre las 27 Letras: {acc * 100:.2f}% ({np.sum(preds == y)} / {len(y)})")

    # Guardar métricas en un reporte JSON en debug_windows/output/
    eval_report = {
        'total_letters': len(labels),
        'letters': labels,
        'total_samples': len(y),
        'accuracy_pct': round(float(acc * 100), 2),
        'per_letter_count': {l: len(database[l]) for l in labels}
    }

    out_eval = os.path.join(os.path.dirname(__file__), 'output', 'alphabet_evaluation.json')
    with open(out_eval, 'w', encoding='utf-8') as f:
        json.dump(eval_report, f, indent=2, ensure_ascii=False)

    print(f"Reporte de evaluación guardado en: {out_eval}")


if __name__ == '__main__':
    build_and_save_alphabet_database()
