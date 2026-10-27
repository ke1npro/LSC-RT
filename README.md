# LSC-RT: Sistema de Reconocimiento y Síntesis de Lengua de Señas Colombiana en Tiempo Real

Aplicación multiplataforma en Flutter para la traducción bidireccional y enseñanza interactiva de la Lengua de Señas Colombiana (LSC). El sistema integra visión artificial en el dispositivo, clasificación espacio-temporal mediante Dynamic Time Warping (DTW) y redes neuronales, un motor cinemático para avatar ilustrado a 60 FPS y un módulo didáctico de evaluación postural.

---

## Modulos Principales

### 1. Traduccion en Tiempo Real
- **Captura e Inferencia Nativa**: Detección de puntos anatómicos corporales y manuales (21 landmarks por mano) mediante MediaPipe y Google ML Kit.
- **Clasificación Espacio-Temporal**: Pipeline de reconocimiento dinámico apoyado en DTW (ventana Sakoe-Chiba) y modelos neuronales sobre un banco canónico de 50 señas base.
- **Historial Reactivo**: Buffer visual con las últimas 5 palabras reconocidas en pantalla con transiciones suaves.
- **Sintesis de Voz (TTS)**: Servicio de audio asíncrono no bloqueante con control de redundancia (debounce de 2.5 s) para verbalizar las señas detectadas.
- **Placeholder de Calibración**: Control estructurado y listo para futuras rutinas de calibración personalizada por usuario.

### 2. Avatar Bidireccional (Texto a Señas)
- **Generador de Frases**: Selector interactivo de vocabulario y chips para componer secuencias de señas.
- **Motor Cinemático Suave**: Interpolación cúbica Hermite (Smoothstep) a 60 FPS que fusiona fotogramas adyacentes eliminando saltos bruscos entre palabras.
- **Renderizado Ilustrado**: Representación con volumen (cabeza, cabello con parpadeo periódico, torso, mangas, puños y siluetas de manos con diferenciación de dedos).
- **Encuadre Dinamico**: Centrado y escalado automático con base en la distancia de los hombros en cada fotograma.
- **Diferenciación Didáctica**: Halos de color y estelas de movimiento independientes para mano izquierda (ámbar) y mano derecha (turquesa).
- **Tematización Modular**: Capa estética desacoplada mediante `AvatarTheme` (estilos Personaje, Alto Contraste y Esmeralda).

### 3. Modulo Didactico de Enseñanza
- **Catálogo de Señas**: Exploración de señas por categorías con metadatos pedagógicos (configuración de la mano, movimiento y punto de articulación).
- **Demostración en Bucle**: Visualizador del avatar repitiendo la seña seleccionada de forma continua para aprendizaje visual.
- **Modo ¡Inténtalo tú!**: Vista dividida con cámara en vivo y retroalimentación en tiempo real.
- **Evaluación Morfológica**: Cálculo de coincidencia anatómica sobre los 21 puntos normalizados mediante `EvaluatePostureUseCase`, proporcionando un porcentaje de precisión al usuario.

### 4. Configuración y Gestion de Datasets
- **Separación de Datos**: Aislamiento estricto entre el dataset de fábrica canónico (50 señas base inmutables) y los overrides locales del usuario.
- **Restauración de Fábrica**: Opción para restablecer la configuración y limpiar calibraciones locales sin comprometer los datos de referencia del sistema.

---

## Arquitectura de Software

El proyecto sigue los principios de **Clean Architecture**, asegurando que las reglas de negocio sean independientes de frameworks visuales y fuentes de datos externas:

```
lib/
├── core/
│   ├── constants/             # Constantes del abecedario y configuraciones LSC
│   ├── di/                    # Configuración de inyección de dependencias (Provider)
│   ├── services/              # Servicios de infraestructura (TtsService)
│   └── theme/                 # Estilos globales (AppColors, AppTheme, AvatarTheme)
├── data/
│   ├── datasources/           # Fuentes de datos (cámara nativa, JSON de cinemática, storage)
│   ├── models/                # Modelos de serialización de datos
│   └── repositories/          # Implementación de repositorios de dominio
├── domain/
│   ├── entities/              # Entidades puras en Dart (AvatarSignData, HandPose, BodyPose)
│   ├── repositories/          # Interfaces y contratos de repositorios
│   ├── services/              # Algoritmos puros (DTWClassifier, ChestActivityDetector)
│   └── usecases/              # Casos de uso (EvaluatePostureUseCase, PredictSignUseCase, etc.)
└── presentation/
    ├── screens/               # Pantallas (Traducción, Avatar, Enseñanza, Configuración)
    ├── viewmodels/            # Gestores de estado reactivos (ChangeNotifier)
    └── widgets/               # Componentes reutilizables y Painters (AvatarPosePainter)
```

---

## Requisitos del Entorno

1. **Flutter SDK**: 3.24 o superior.
2. **Android SDK**:
   - `platform-tools` (con `adb`).
   - `build-tools` y `platforms` para API 34 o 35.
3. **Dispositivo Físico Android**:
   - Recomendado para pruebas completas de cámara e inferencia en tiempo real.
   - Debe tener la **Depuración por USB** activada en las Opciones de Desarrollador.
4. **Windows Desktop**:
   - Soporte nativo habilitado para depuración de interfaces gráficas, avatar y lógica sin cámara.
   - Requiere `nuget.exe` en el PATH para compilar dependencias C++/WinRT de TTS.

---

## Instalación y Ejecución

### 1. Clonar el repositorio
```bash
git clone https://github.com/ke1npro/LSC-RT.git
cd LSC-RT
```

### 2. Instalar dependencias
```bash
flutter pub get
```

### 3. Ejecutar en Dispositivo Físico Android (Recomendado)
Conecta tu teléfono por USB y valida la conexión:
```bash
adb devices
flutter run
```

### 4. Ejecutar en Windows Desktop (UI y Avatar)
```bash
flutter run -d windows
```

### 5. Compilar Instalador Android (.APK)
```bash
flutter build apk --debug
```
El archivo resultante se generará en `build/app/outputs/flutter-apk/app-debug.apk`.

---

## Pruebas y Calidad de Código

El repositorio cuenta con una suite completa de pruebas unitarias y de widgets que validan la cinemática, el cálculo DTW y la estabilidad de la interfaz:

- **Ejecutar análisis estático**:
  ```bash
  flutter analyze
  ```
- **Ejecutar suite de pruebas**:
  ```bash
  flutter test
  ```
