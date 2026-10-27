import urllib.request
import io
import numpy as np

LETTERS = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
    '%C3%91'  # Ñ
]

BASE_URL = "https://raw.githubusercontent.com/FerchoRV/LSTM-Reconocimiento-de-signos-colombianos/main/Datasets/LSC_Signos_Data"

print("Comprobando disponibilidad de muestras por letra...")
for let in LETTERS:
    name = "Ñ" if let == "%C3%91" else let
    valid_count = 0
    # Probar las primeras 5 secuencias en el frame 15
    for seq in range(5):
        url = f"{BASE_URL}/{let}/{seq}/15.npy"
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, timeout=3) as resp:
                data = np.load(io.BytesIO(resp.read()))
                if np.count_nonzero(data) > 0:
                    valid_count += 1
        except Exception:
            pass
    print(f"Letra {name}: {valid_count}/5 secuencias probadas tienen datos validos")
