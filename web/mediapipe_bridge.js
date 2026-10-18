let handsDetector = null;
let faceDetector = null;
let isBridgeInitialized = false;

function initMediaPipe() {
  if (isBridgeInitialized) return;
  try {
    if (typeof Hands !== 'undefined') {
      handsDetector = new Hands({
        locateFile: (file) => `https://cdn.jsdelivr.net/npm/@mediapipe/hands/${file}`
      });
      handsDetector.setOptions({
        maxNumHands: 1,
        modelComplexity: 1,
        minDetectionConfidence: 0.5,
        minTrackingConfidence: 0.5
      });
      handsDetector.onResults(onHandResults);
    }

    if (typeof FaceDetection !== 'undefined') {
      faceDetector = new FaceDetection({
        locateFile: (file) => `https://cdn.jsdelivr.net/npm/@mediapipe/face_detection/${file}`
      });
      faceDetector.setOptions({
        model: 'short',
        minDetectionConfidence: 0.5
      });
      faceDetector.onResults(onFaceResults);
    }

    isBridgeInitialized = true;
    console.log("MediaPipe Web Bridge initialized successfully.");
    startVideoProcessingLoop();
  } catch (e) {
    console.warn("MediaPipe init warning:", e);
  }
}

function onHandResults(results) {
  if (!results.multiHandLandmarks || results.multiHandLandmarks.length === 0) {
    window.dispatchEvent(new CustomEvent('flutter_hand_landmarks', { detail: '[]' }));
    return;
  }
  const handsData = results.multiHandLandmarks.map(landmarks => {
    return landmarks.map(lm => ({ x: lm.x, y: lm.y, z: lm.z || 0 }));
  });
  window.dispatchEvent(new CustomEvent('flutter_hand_landmarks', {
    detail: JSON.stringify(handsData)
  }));
}

function onFaceResults(results) {
  if (!results.detections || results.detections.length === 0) {
    window.dispatchEvent(new CustomEvent('flutter_face_boxes', { detail: '[]' }));
    return;
  }
  const boxes = results.detections.map(det => {
    const box = det.boundingBox;
    return {
      x: box.xCenter - box.width / 2,
      y: box.yCenter - box.height / 2,
      width: box.width,
      height: box.height
    };
  });
  window.dispatchEvent(new CustomEvent('flutter_face_boxes', {
    detail: JSON.stringify(boxes)
  }));
}

let isProcessing = false;
function startVideoProcessingLoop() {
  setInterval(async () => {
    if (isProcessing) return;
    const video = document.querySelector('video');
    if (!video || video.readyState < 2 || video.paused || video.ended) {
      return;
    }
    isProcessing = true;
    try {
      if (handsDetector) {
        await handsDetector.send({ image: video });
      }
      if (faceDetector) {
        await faceDetector.send({ image: video });
      }
    } catch (e) {
      // Ignorar cuadros transitorios
    } finally {
      isProcessing = false;
    }
  }, 66); // ~15-20 FPS óptimo para CPU/GPU en web
}

window.addEventListener('DOMContentLoaded', () => {
  setTimeout(initMediaPipe, 1200);
});

if (document.readyState === 'complete' || document.readyState === 'interactive') {
  setTimeout(initMediaPipe, 1200);
}
