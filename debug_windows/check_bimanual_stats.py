# -*- coding: utf-8 -*-
"""
check_bimanual_stats.py
Analiza la cinemática de las 50 señas para determinar inequívocamente cuáles son unimanuales
y cuáles bimanuales a partir del desplazamiento de muñecas y manos de los señantes reales.
"""

import os
import glob
import numpy as np

WORKSPACE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
NPZ_DIR = os.path.join(WORKSPACE_DIR, 'dataset', 'PROCESSED_NPZ')

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
    "¿POR QUÉ?", "¿QUIÉN?", DIFERENTE := "DIFERENTE", "TODOS", "MUCHO"
]

def analyze_all():
    print(f"{'ID':<4} | {'Nombre':<16} | {'Displ Izq':<10} | {'Displ Der':<10} | {'Ratio':<7} | {'Tipo':<10}")
    print("-" * 65)

    results = {}
    for c_idx, sname in enumerate(CLASS_NAMES):
        class_id = f"{c_idx:04d}"
        files = glob.glob(os.path.join(NPZ_DIR, f"{class_id}_*.npz"))
        if not files:
            continue

        l_disps = []
        r_disps = []
        for f in files:
            d = np.load(f)
            p = d['pose']
            act = d['active_segment']
            s, e = int(act[0]), int(act[1])
            if e <= s + 4 or e >= len(p):
                s = int(len(p) * 0.15)
                e = int(len(p) * 0.85)

            # Muñeca izq (index 9 en raw mediapipe), muñeca der (index 10)
            lw = p[s:e+1, 9, :2]
            rw = p[s:e+1, 10, :2]

            disp_l = float(np.ptp(lw[:, 1])) if not np.isnan(lw).all() else 0.0
            disp_r = float(np.ptp(rw[:, 1])) if not np.isnan(rw).all() else 0.0

            l_disps.append(disp_l)
            r_disps.append(disp_r)

        med_l = float(np.median(l_disps))
        med_r = float(np.median(r_disps))
        
        # Consideramos bimanual si ambas manos se mueven significativamente (> 0.06 de pantalla)
        # y la mano secundaria tiene al menos el 40% del movimiento de la primaria
        min_disp = min(med_l, med_r)
        max_disp = max(med_l, med_r)
        ratio = (min_disp / max(max_disp, 1e-4))
        
        is_bim = (min_disp > 0.055 and ratio > 0.35)
        tipo = "BIMANUAL" if is_bim else "UNIMANUAL"
        results[class_id] = {'name': sname, 'is_bimanual': is_bim, 'ratio': ratio, 'med_l': med_l, 'med_r': med_r}
        print(f"{class_id} | {sname:<16} | {med_l:<10.4f} | {med_r:<10.4f} | {ratio:<7.2f} | {tipo}")

    return results

if __name__ == '__main__':
    analyze_all()
