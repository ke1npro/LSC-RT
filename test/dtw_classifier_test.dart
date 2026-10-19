import 'package:flutter_test/flutter_test.dart';
import 'package:sign_language_app/domain/entities/dtw_gesture_sample.dart';
import 'package:sign_language_app/domain/entities/landmark_point.dart';
import 'package:sign_language_app/domain/services/chest_activity_detector.dart';
import 'package:sign_language_app/domain/services/dtw_classifier.dart';
import 'package:sign_language_app/domain/usecases/recognize_dynamic_gesture_usecase.dart';

void main() {
  group('DTW Classifier & Parity Tests', () {
    // Vectores generados determinísticamente para paridad con fast_dtw.c
    const double expectedDistance = 33.75493240356445;
    final List<List<double>> seqA = [
      [0.8592321872711182, -0.36724889278411865, -0.6321623921394348, -0.5908794403076172, 0.1354500651359558, 0.19108940660953522, 0.9290290474891663, 0.30635419487953186],
      [0.49781328439712524, 0.3071397542953491, 0.4954296052455902, 0.9226135015487671, -0.9832233786582947, -0.787111222743988, -0.40259256958961487, 0.3128223717212677],
      [0.6196250915527344, 0.7443518042564392, 0.9292951822280884, 0.447370707988739, 0.2849506437778473, 0.4349072277545929, -0.06480198353528976, -0.3488306403160095],
      [-0.12071079015731812, 0.4593781530857086, 0.9880291819572449, 0.3537474274635315, 0.5816450119018555, -0.6581714749336243, -0.9463014602661133, 0.6007404923439026],
      [0.8074450492858887, -0.9506475925445557, -0.01650536246597767, 0.0525103360414505, 0.19273202121257782, -0.8960849046707153, 0.7901790738105774, 0.45653235912323],
      [0.6367000341415405, 0.000445505662355572, 0.6203787922859192, -0.8080629706382751, -0.5620999336242676, -0.4825618863105774, -0.06378848850727081, -0.08125359565019608],
      [0.41901955008506775, -0.6438940167427063, 0.06289976835250854, -0.6645155549049377, 0.5376278162002563, 0.8563411235809326, 0.21898731589317322, -0.699633002281189],
      [-0.020746592432260513, -0.24531009793281555, 0.6972028017044067, 0.8221944570541382, -0.23230256140232086, -0.3690081834793091, 0.13678830862045288, -0.6243639588356018],
      [-0.7483168840408325, 0.3751915991306305, 0.5992134213447571, 0.14707313477993011, 0.946459949016571, 0.2681087553501129, 0.7768434286117554, -0.009170482866466045],
      [-0.2967669367790222, 0.4284607470035553, 0.007858232595026493, -0.5487247705459595, -0.5100511312484741, 0.5856013894081116, -0.009655171073973179, 0.8301873207092285],
      [0.8907436728477478, 0.06646446138620377, -0.49501481652259827, 0.44172412157058716, -0.2651224732398987, -0.002703114179894328, -0.5468499064445496, -0.2928687036037445],
      [0.3017035722732544, -0.37413421273231506, 0.5374708771705627, 0.5636742115020752, 0.7048189640045166, 0.8998115062713623, -0.7853541970252991, 0.8214507102966309],
      [-0.32788968086242676, 0.6527608633041382, 0.7962012887001038, -0.9145693778991699, -0.6084100008010864, -0.4109973609447479, 0.2539997696876526, -0.8275538086891174],
      [-0.7141099572181702, 0.031653039157390594, 0.3786826729774475, 0.7132516503334045, 0.29472336173057556, 0.16323734819889069, 0.42223191261291504, -0.49516627192497253],
      [0.8003193736076355, -0.11541261523962021, -0.9589583277702332, 0.9193220138549805, 0.3044508397579193, 0.02641250006854534, 0.36471277475357056, -0.02091921865940094],
      [0.8529803156852722, 0.03175954520702362, -0.8556802272796631, 0.13501659035682678, 0.23048636317253113, 0.8830925822257996, -0.1692732870578766, -0.47112005949020386]
    ];

    final List<List<double>> seqB = [
      [-0.8052136898040771, -0.028311556205153465, -0.07067427784204483, -0.9404813647270203, 0.3885549306869507, 0.43389421701431274, 0.459622859954834, -0.17129796743392944],
      [-0.9698023200035095, 0.8179503083229065, 0.5787574648857117, -0.6696016788482666, -0.37442806363105774, 0.2218906134366989, -0.27101942896842957, -0.6879228353500366],
      [-0.6453923583030701, 0.735779345035553, -0.4198106527328491, 0.17035923898220062, -0.0920102447271347, -0.17764373123645782, 0.765268862247467, 0.38541603088378906],
      [-0.4414532780647278, -0.8711195588111877, -0.6027527451515198, 0.8633654713630676, 0.7088271379470825, 0.909469485282898, -0.8954933285713196, 0.15894335508346558],
      [-0.03900746628642082, -0.9565820693969727, -0.25275906920433044, -0.1718163937330246, 0.20781446993350983, 0.34349745512008667, 0.6777313947677612, 0.5590524077415466],
      [-0.19859790802001953, 0.5890584588050842, 0.7862486243247986, -0.4750206172466278, 0.9783940315246582, 0.7066141963005066, 0.4629543125629425, -0.2888687551021576],
      [0.7665789723396301, 0.7359181642532349, 0.9115328788757324, -0.9997854828834534, -0.9669179320335388, -0.3718598783016205, 0.9906323552131653, -0.7023115754127502],
      [-0.665245771408081, 0.5171440839767456, -0.86094069480896, 0.41094687581062317, -0.06166943535208702, -0.979623556137085, 0.5496477484703064, 0.5884020328521729],
      [-0.7008610963821411, -0.9525927305221558, 0.5241275429725647, -0.5526596307754517, -0.47565120458602905, -0.08626099675893784, -0.5001461505889893, 0.1365671157836914],
      [0.6938859820365906, -0.24380092322826385, -0.13506977260112762, 0.6652383804321289, -0.25773611664772034, -0.9188934564590454, 0.10934296995401382, -0.09750751405954361],
      [0.4506019651889801, -0.24309895932674408, 0.6813250184059143, -0.0613706111907959, 0.12528686225414276, 0.32239869236946106, -0.07551626861095428, 0.24727389216423035],
      [-0.5562387108802795, 0.46572622656822205, -0.23663581907749176, -0.6103309392929077, -0.45767444372177124, -0.5015498995780945, -0.6957218647003174, 0.542747437953949],
      [-0.48917654156684875, -0.7449131608009338, 0.33033430576324463, -0.17439010739326477, 0.33553552627563477, 0.319627046585083, -0.3892446458339691, -0.5975515246391296],
      [-0.5559457540512085, -0.7600582838058472, -0.9257091283798218, -0.9317368268966675, -0.5390068888664246, -0.5432925820350647, 0.2498212456703186, 0.7851223945617676],
      [0.5594560503959656, 0.442902535200119, -0.37911567091941833, -0.27383315563201904, -0.6078364253044128, 0.8709836006164551, 0.12346799671649933, 0.634583055973053],
      [-0.3021720349788666, 0.5994285345077515, -0.7917910814285278, 0.4242403209209442, 0.834896981716156, 0.6071707606315613, -0.34577369689941406, -0.48978564143180847]
    ];

    test('Paridad matemática exacta de DTW Sakoe-Chiba con C/Python', () {
      final double calculated = DtwClassifier.calculateDistance(seqA, seqB, w: 3);
      expect(calculated, closeTo(expectedDistance, 1e-4));
    });

    test('Remuestreo temporal lineal exacto de N fotogramas a 16 fotogramas', () {
      // Secuencia lineal simple de 4 fotogramas en 8 dimensiones
      final List<List<double>> raw4 = [
        List<double>.filled(8, 0.0),
        List<double>.filled(8, 1.0),
        List<double>.filled(8, 2.0),
        List<double>.filled(8, 3.0),
      ];

      final resampled16 = DtwClassifier.resampleSequence(raw4, targetLen: 16);
      expect(resampled16.length, equals(16));
      expect(resampled16[0][0], equals(0.0));
      expect(resampled16[15][0], equals(3.0));
      // En la mitad (índice 7.5 aprox) debe ser 1.5
      expect(resampled16[5][0], closeTo(1.0, 0.01));
      expect(resampled16[10][0], closeTo(2.0, 0.01));
    });

    test('Clasificación kNN-DTW (1-NN) y umbral de rechazo', () {
      final classifier = const DtwClassifier(defaultRejectionThreshold: 11.32);
      final templateA = DtwGestureTemplate(
        classId: 0,
        name: 'GRACIAS',
        sequence: DtwSequence.fromMatrix(seqA),
      );
      final templateB = DtwGestureTemplate(
        classId: 30,
        name: 'HOLA',
        sequence: DtwSequence.fromMatrix(seqB),
      );

      // Una secuencia idéntica a seqA debe predecir GRACIAS con distancia 0.0 y alta confianza
      final resultExact = classifier.classify(DtwSequence.fromMatrix(seqA), [templateA, templateB]);
      expect(resultExact, isNotNull);
      expect(resultExact!.classId, equals(0));
      expect(resultExact.name, equals('GRACIAS'));
      expect(resultExact.distance, closeTo(0.0, 1e-5));
      expect(resultExact.confidence, closeTo(1.0, 1e-4));
      expect(resultExact.isAccepted, isTrue);

      // Una secuencia distante por encima del umbral (como seqB contra templateA con umbral 10.0) debe ser rechazada
      final resultFar = classifier.classify(DtwSequence.fromMatrix(seqB), [templateA], threshold: 10.0);
      expect(resultFar, isNotNull);
      expect(resultFar!.distance, closeTo(expectedDistance, 1e-4));
      expect(resultFar.isAccepted, isFalse);
    });

    test('Detector de actividad por línea de pecho transiciona correctamente', () {
      final detector = ChestActivityDetector(
        chestLineAlpha: 0.60,
        minActiveFrames: 8,
        restingHysteresisFrames: 4,
      );

      final shoulderL = const LandmarkPoint(x: 0.40, y: 0.30);
      final shoulderR = const LandmarkPoint(x: 0.60, y: 0.30);
      // Ancho hombros = 0.20, Centro = (0.50, 0.30)
      // Línea de pecho = 0.30 + 0.60 * 0.20 = 0.42

      final elbowRest = const LandmarkPoint(x: 0.45, y: 0.60);
      final wristRest = const LandmarkPoint(x: 0.50, y: 0.70); // 0.70 > 0.42 (Reposo)

      final elbowActive = const LandmarkPoint(x: 0.45, y: 0.35);
      final wristActive = const LandmarkPoint(x: 0.50, y: 0.25); // 0.25 < 0.42 (Activo, sobre el pecho)

      // 1. Estado inicial en reposo
      expect(detector.state, equals(GestureTrackingState.resting));
      detector.processFrame(
        shoulderLeft: shoulderL,
        shoulderRight: shoulderR,
        elbowLeft: elbowRest,
        elbowRight: elbowRest,
        wristLeft: wristRest,
        wristRight: wristRest,
      );
      expect(detector.state, equals(GestureTrackingState.resting));

      // 2. Transición a activo cuando la mano sube
      for (int i = 0; i < 3; i++) {
        detector.processFrame(
          shoulderLeft: shoulderL,
          shoulderRight: shoulderR,
          elbowLeft: elbowActive,
          elbowRight: elbowActive,
          wristLeft: wristActive,
          wristRight: wristRest,
        );
      }
      expect(detector.state, equals(GestureTrackingState.active));
      expect(detector.isRecording, isTrue);

      // 3. Mantener activo 10 frames
      for (int i = 0; i < 10; i++) {
        detector.processFrame(
          shoulderLeft: shoulderL,
          shoulderRight: shoulderR,
          elbowLeft: elbowActive,
          elbowRight: elbowActive,
          wristLeft: wristActive,
          wristRight: wristRest,
        );
      }

      // 4. Manos bajan al reposo durante la histéresis -> completa y emite el gesto
      List<List<double>>? emitted;
      for (int i = 0; i < 6; i++) {
        final frameResult = detector.processFrame(
          shoulderLeft: shoulderL,
          shoulderRight: shoulderR,
          elbowLeft: elbowRest,
          elbowRight: elbowRest,
          wristLeft: wristRest,
          wristRight: wristRest,
        );
        if (frameResult != null) {
          emitted = frameResult;
        }
      }

      expect(emitted, isNotNull);
      expect(emitted!.length, greaterThanOrEqualTo(8));
      expect(detector.state, equals(GestureTrackingState.resting));
    });

    test('Integración completa con RecognizeDynamicGestureUseCase', () {
      final useCase = RecognizeDynamicGestureUseCase();

      // Registrar plantilla para HOLA usando seqB
      useCase.registerTemplate(
        classId: 30,
        name: 'HOLA',
        rawSequence: seqB,
      );

      expect(useCase.templates.length, equals(1));

      // Clasificar una secuencia similar a seqB
      final result = useCase.classifySequence(seqB, threshold: 15.0);
      expect(result, isNotNull);
      expect(result!.classId, equals(30));
      expect(result.name, equals('HOLA'));
      expect(result.distance, closeTo(0.0, 1e-4));
      expect(result.isAccepted, isTrue);
    });
  });
}
