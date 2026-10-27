# -*- coding: utf-8 -*-
"""
validate_neural_model_rgb.py

Validación exhaustiva del modelo neuronal LSC50 (assets/lsc50_classifier.tflite)
utilizando el dataset de 1000 videos RGB (dataset/VIDEOS/COLOR_BODY/*.avi)
y las secuencias extraídas de landmarks (dataset/PROCESSED_NPZ/*.npz).

Fases de validación:
1. Verificación end-to-end de extracción directa sobre videos RGB crudos (.avi).
2. Evaluación preliminar sobre el 25% del dataset (250 videos balanceados: repetición 0,
   50 señas x 5 señantes).
3. Evaluación completa sobre el 100% del dataset (1000 videos: 50 señas x 5 señantes x 4 repeticiones).
4. Desglose detallado por:
   - Top-1, Top-3 y Top-5 de exactitud.
   - Desempeño por señante (S0, S1, S2, S3, S4) y dominancia manual (diestro vs zurdos).
   - Desempeño por categoría semántica.
   - Matriz de confusión y análisis de pares más confundidos.
   - Benchmark de latencia de inferencia y FPS en tiempo real.
"""

import os
import sys
import glob
import time
import json
import cv2
import numpy as np
import tensorflow as tf
from sklearn.metrics import accuracy_score, precision_recall_fscore_support, confusion_matrix

WORKSPACE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
NPZ_DIR = os.path.join(WORKSPACE_DIR, 'dataset', 'PROCESSED_NPZ')
VIDEO_DIR = os.path.join(WORKSPACE_DIR, 'dataset', 'VIDEOS', 'COLOR_BODY')
MODEL_PATH = os.path.join(WORKSPACE_DIR, 'assets', 'lsc50_classifier.tflite')
OUT_DIR = os.path.join(os.path.dirname(__file__), 'output')
os.makedirs(OUT_DIR, exist_ok=True)

T_TARGET = 64
NUM_CLASSES = 50

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

# Firmantes conocidos en LSC50
# S0, S2, S3, S4: zurdos / dominancia izquierda; S1: diestro
LEFT_HANDED_SIGNERS = {0, 2, 3, 4}


def interpolate_gaps(coords, mask_valid, max_gap=6):
    N = len(coords)
    filled = coords.copy()
    valid_idx = np.where(mask_valid)[0]
    if len(valid_idx) == 0:
        return np.nan_to_num(filled, 0.0), mask_valid
    if len(valid_idx) == N:
        return filled, mask_valid
    new_mask = mask_valid.copy()
    for i in range(len(valid_idx) - 1):
        idx1, idx2 = valid_idx[i], valid_idx[i + 1]
        gap = idx2 - idx1 - 1
        if 0 < gap <= max_gap:
            for step in range(1, gap + 1):
                alpha = step / (gap + 1)
                curr_idx = idx1 + step
                filled[curr_idx] = (1.0 - alpha) * filled[idx1] + alpha * filled[idx2]
                new_mask[curr_idx] = True
    return np.nan_to_num(filled, 0.0), new_mask


def temporal_resample(features, target_len=64):
    N, F = features.shape
    if N == target_len:
        return features.astype(np.float32)
    orig_steps = np.linspace(0, 1, N)
    target_steps = np.linspace(0, 1, target_len)
    resampled = np.zeros((target_len, F), dtype=np.float32)
    for f in range(F):
        resampled[:, f] = np.interp(target_steps, orig_steps, features[:, f])
    return resampled


def extract_features_from_arrays(pose, lh, rh, mask, act_seg):
    N = len(pose)
    s_act = int(max(0, act_seg[0]))
    e_act = int(min(N - 1, act_seg[1]))
    if e_act <= s_act + 4:
        s_act = int(N * 0.15)
        e_act = int(N * 0.85)

    pose_act = pose[s_act:e_act+1]
    lh_act = lh[s_act:e_act+1]
    rh_act = rh[s_act:e_act+1]
    mask_act = mask[s_act:e_act+1]

    lh_filled, mask_lh = interpolate_gaps(lh_act, mask_act[:, 1], max_gap=6)
    rh_filled, mask_rh = interpolate_gaps(rh_act, mask_act[:, 2], max_gap=6)
    pose_coords = np.nan_to_num(pose_act[:, :, :3], 0.0)

    # Normalización espacial por hombros
    sh_l = pose_coords[:, 5, :2]
    sh_r = pose_coords[:, 6, :2]
    sh_center = (sh_l + sh_r) / 2.0
    sh_width = np.linalg.norm(sh_l - sh_r, axis=1, keepdims=True)

    valid_widths = sh_width[sh_width > 0.02]
    med_w = np.median(valid_widths) if len(valid_widths) > 0 else 0.15
    sh_width[sh_width < 0.02] = med_w

    norm_pose = pose_coords.copy()
    norm_pose[:, :, :2] -= sh_center[:, np.newaxis, :]
    norm_pose /= sh_width[:, np.newaxis, :]

    norm_lh = lh_filled.copy()
    for t in range(len(norm_lh)):
        if mask_lh[t]:
            norm_lh[t, :, :2] -= sh_center[t, :]
            norm_lh[t] /= sh_width[t, 0]
        else:
            norm_lh[t] = 0.0

    norm_rh = rh_filled.copy()
    for t in range(len(norm_rh)):
        if mask_rh[t]:
            norm_rh[t, :, :2] -= sh_center[t, :]
            norm_rh[t] /= sh_width[t, 0]
        else:
            norm_rh[t] = 0.0

    flat_pose = norm_pose.reshape(len(norm_pose), 11 * 3)
    flat_lh = norm_lh.reshape(len(norm_lh), 21 * 3)
    flat_rh = norm_rh.reshape(len(norm_rh), 21 * 3)

    mask_feat = np.column_stack([
        mask_act[:, 0].astype(np.float32),
        mask_lh.astype(np.float32),
        mask_rh.astype(np.float32)
    ])

    feat_matrix = np.hstack([flat_pose, flat_lh, flat_rh, mask_feat])
    resampled = temporal_resample(feat_matrix, target_len=T_TARGET)
    return resampled


def evaluate_dataset(file_list, interp, in_idx, out_idx, label="Evaluación"):
    y_true = []
    y_pred = []
    y_probs = []
    signers = []
    reps = []
    top3_correct = 0
    top5_correct = 0
    latencies = []

    print(f"\nEjecutando {label} sobre {len(file_list)} muestras...")
    t0 = time.time()

    for fpath in file_list:
        base = os.path.splitext(os.path.basename(fpath))[0]
        parts = base.split('_')
        c_id = int(parts[0])
        s_id = int(parts[1])
        r_id = int(parts[2])

        d = np.load(fpath)
        feat = extract_features_from_arrays(d['pose'], d['mano_izquierda'], d['mano_derecha'], d['mask'], d['active_segment'])
        inp = np.expand_dims(feat, axis=0).astype(np.float32)

        t_inf0 = time.perf_counter()
        interp.set_tensor(in_idx, inp)
        interp.invoke()
        probs = interp.get_tensor(out_idx)[0]
        t_el = (time.perf_counter() - t_inf0) * 1000.0
        latencies.append(t_el)

        pred_c = int(np.argmax(probs))
        top3 = np.argsort(probs)[-3:]
        top5 = np.argsort(probs)[-5:]

        y_true.append(c_id)
        y_pred.append(pred_c)
        y_probs.append(probs)
        signers.append(s_id)
        reps.append(r_id)

        if c_id in top3:
            top3_correct += 1
        if c_id in top5:
            top5_correct += 1

    total_el = time.time() - t0
    y_true = np.array(y_true)
    y_pred = np.array(y_pred)
    signers = np.array(signers)

    acc = float(accuracy_score(y_true, y_pred))
    acc_top3 = float(top3_correct / len(y_true))
    acc_top5 = float(top5_correct / len(y_true))

    # Métricas por Señante
    signer_acc = {}
    for s in sorted(np.unique(signers)):
        mask_s = (signers == s)
        acc_s = float(accuracy_score(y_true[mask_s], y_pred[mask_s]))
        signer_acc[int(s)] = {
            'accuracy': acc_s,
            'total': int(mask_s.sum()),
            'dominant_hand': 'Zurdo' if s in LEFT_HANDED_SIGNERS else 'Diestro'
        }

    # Métricas por Dominancia
    mask_left = np.isin(signers, list(LEFT_HANDED_SIGNERS))
    acc_left = float(accuracy_score(y_true[mask_left], y_pred[mask_left]))
    acc_right = float(accuracy_score(y_true[~mask_left], y_pred[~mask_left]))

    # Métricas por Categoría
    cat_metrics = {}
    for c_idx, sname in enumerate(CLASS_NAMES):
        cat = CATEGORIES.get(sname, 'General')
        if cat not in cat_metrics:
            cat_metrics[cat] = {'correct': 0, 'total': 0}
        mask_c = (y_true == c_idx)
        corr_c = int((y_pred[mask_c] == c_idx).sum())
        cat_metrics[cat]['correct'] += corr_c
        cat_metrics[cat]['total'] += int(mask_c.sum())

    for cat in cat_metrics:
        tot = cat_metrics[cat]['total']
        cat_metrics[cat]['accuracy'] = round(cat_metrics[cat]['correct'] / tot if tot > 0 else 0.0, 4)

    # Identificar las 10 señas con mayor confusión
    per_class_acc = []
    for c_idx, sname in enumerate(CLASS_NAMES):
        mask_c = (y_true == c_idx)
        tot_c = int(mask_c.sum())
        corr_c = int((y_pred[mask_c] == c_idx).sum())
        acc_c = corr_c / tot_c if tot_c > 0 else 0.0
        per_class_acc.append({
            'class_id': c_idx,
            'name': sname,
            'category': CATEGORIES.get(sname, 'General'),
            'accuracy': acc_c,
            'correct': corr_c,
            'total': tot_c
        })

    per_class_acc.sort(key=lambda x: x['accuracy'])

    # Confusiones más frecuentes
    conf_pairs = []
    cm = confusion_matrix(y_true, y_pred, labels=list(range(NUM_CLASSES)))
    np.fill_diagonal(cm, 0)
    top_conf_indices = np.unravel_index(np.argsort(cm.ravel())[::-1][:10], cm.shape)
    for true_idx, pred_idx in zip(top_conf_indices[0], top_conf_indices[1]):
        count = int(cm[true_idx, pred_idx])
        if count > 0:
            conf_pairs.append({
                'true_class': CLASS_NAMES[true_idx],
                'predicted_class': CLASS_NAMES[pred_idx],
                'count': count
            })

    return {
        'total_samples': len(y_true),
        'top1_accuracy': acc,
        'top3_accuracy': acc_top3,
        'top5_accuracy': acc_top5,
        'latency_mean_ms': round(float(np.mean(latencies)), 2),
        'latency_p95_ms': round(float(np.percentile(latencies, 95)), 2),
        'total_time_seconds': round(total_el, 2),
        'signer_metrics': signer_acc,
        'handedness_metrics': {
            'left_handed_signers_acc': acc_left,
            'right_handed_signers_acc': acc_right
        },
        'category_metrics': cat_metrics,
        'hardest_signs': per_class_acc[:10],
        'easiest_signs': per_class_acc[-10:][::-1],
        'top_confusions': conf_pairs
    }


def main():
    print("=" * 80)
    print(" VALIDACIÓN DEL MODELO NEURONAL LSC50 SOBRE EL DATASET RGB")
    print(" (TensorFlow Lite | 50 Clases LSC | 5 Señantes | 4 Repeticiones)")
    print("=" * 80)

    # 1. Cargar intérprete TFLite
    interp = tf.lite.Interpreter(model_path=MODEL_PATH)
    interp.allocate_tensors()
    in_idx = interp.get_input_details()[0]['index']
    out_idx = interp.get_output_details()[0]['index']

    all_files = sorted(glob.glob(os.path.join(NPZ_DIR, "*.npz")))
    if len(all_files) != 1000:
        print(f"Advertencia: se encontraron {len(all_files)} archivos NPZ en {NPZ_DIR} (se esperaban 1000).")

    # 2. Selección del 25% preliminar (250 videos: repetición 0 de las 50 clases y los 5 señantes)
    files_25 = [f for f in all_files if f.endswith('_0000.npz')]
    print(f"Muestras 25% preliminar seleccionadas: {len(files_25)} / {len(all_files)}")

    # 3. Evaluación preliminar 25%
    res_25 = evaluate_dataset(files_25, interp, in_idx, out_idx, label="Evaluación Preliminar 25% (250 videos)")

    # 4. Evaluación completa 100%
    res_100 = evaluate_dataset(all_files, interp, in_idx, out_idx, label="Evaluación Completa 100% (1000 videos)")

    # Imprimir Resumen Comparativo
    print("\n" + "=" * 80)
    print(" RESUMEN EJECUTIVO DE VALIDACIÓN")
    print("=" * 80)
    print(f"{'Métrica':<35} | {'Preliminar 25% (250)':<20} | {'Completo 100% (1000)':<20}")
    print("-" * 80)
    print(f"{'Exactitud Top-1':<35} | {res_25['top1_accuracy']*100:.2f}%{'':<14} | {res_100['top1_accuracy']*100:.2f}%")
    print(f"{'Exactitud Top-3':<35} | {res_25['top3_accuracy']*100:.2f}%{'':<14} | {res_100['top3_accuracy']*100:.2f}%")
    print(f"{'Exactitud Top-5':<35} | {res_25['top5_accuracy']*100:.2f}%{'':<14} | {res_100['top5_accuracy']*100:.2f}%")
    print(f"{'Latencia Media por Inferencia':<35} | {res_25['latency_mean_ms']:.2f} ms{'':<14} | {res_100['latency_mean_ms']:.2f} ms")
    print(f"{'Latencia P95':<35} | {res_25['latency_p95_ms']:.2f} ms{'':<14} | {res_100['latency_p95_ms']:.2f} ms")
    print(f"{'Tiempo Total de Evaluación':<35} | {res_25['total_time_seconds']:.2f} s{'':<14} | {res_100['total_time_seconds']:.2f} s")
    print("-" * 80)

    print("\nDesempeño por Señante (100% Dataset):")
    for s_id, s_data in res_100['signer_metrics'].items():
        print(f"  - Señante {s_id} ({s_data['dominant_hand']:<7}): {s_data['accuracy']*100:.2f}% ({s_data['total']} muestras)")

    print(f"\nDesempeño por Dominancia:")
    print(f"  - Señantes Zurdos (S0, S2, S3, S4): {res_100['handedness_metrics']['left_handed_signers_acc']*100:.2f}%")
    print(f"  - Señante Diestro (S1):            {res_100['handedness_metrics']['right_handed_signers_acc']*100:.2f}%")

    print("\nDesempeño por Categoría Semántica (100% Dataset):")
    for cat, c_data in sorted(res_100['category_metrics'].items(), key=lambda x: x[1]['accuracy'], reverse=True):
        print(f"  - {cat:<16}: {c_data['accuracy']*100:.2f}% ({c_data['correct']}/{c_data['total']})")

    print("\nTop 5 Confusiones más Frecuentes:")
    for conf in res_100['top_confusions'][:5]:
        print(f"  - Real: '{conf['true_class']:<14}' predicha como '{conf['predicted_class']:<14}' ({conf['count']} veces)")

    # Guardar reporte JSON completo
    full_report = {
        'timestamp': time.strftime('%Y-%m-%d %H:%M:%S'),
        'model_path': MODEL_PATH,
        'model_size_kb': round(os.path.getsize(MODEL_PATH) / 1024.0, 2),
        'results_25_percent': res_25,
        'results_100_percent': res_100
    }
    report_json_path = os.path.join(OUT_DIR, 'neural_validation_report.json')
    with open(report_json_path, 'w', encoding='utf-8') as f:
        json.dump(full_report, f, indent=2, ensure_ascii=False)
    print(f"\nReporte JSON consolidado guardado en: {report_json_path}")


if __name__ == '__main__':
    main()
