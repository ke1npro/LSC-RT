import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class CameraViewport extends StatelessWidget {
  final CameraController? controller;
  final bool isFrontCamera;
  final Widget? overlay;
  final Function(Size size)? onSizeChanged;
  final bool isSwitching;
  final bool isPermissionDenied;
  final String? errorMessage;
  final VoidCallback? onRetry;

  const CameraViewport({
    super.key,
    required this.controller,
    this.isFrontCamera = true,
    this.overlay,
    this.onSizeChanged,
    this.isSwitching = false,
    this.isPermissionDenied = false,
    this.errorMessage,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    // Verificación estricta de usabilidad para prevenir cualquier pantalla roja de aserción
    final bool isUsable = !isSwitching &&
        !isPermissionDenied &&
        controller != null &&
        controller!.value.isInitialized &&
        !controller!.value.hasError &&
        controller!.value.previewSize != null;

    if (!isUsable) {
      return Container(
        color: AppColors.background,
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Center(
          child: _buildFallbackContent(),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (onSizeChanged != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onSizeChanged!(size);
          });
        }

        Widget preview = CameraPreview(controller!);

        // En Web/PC, reflejar la cámara frontal horizontalmente como un espejo
        if (kIsWeb && isFrontCamera) {
          preview = Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationY(math.pi),
            child: preview,
          );
        }

        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Vista de cámara ajustada a pantalla sin deformar relación de aspecto
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: controller!.value.previewSize?.height ?? size.width,
                  height: controller!.value.previewSize?.width ?? size.height,
                  child: preview,
                ),
              ),

              // 2. Capa de overlay declarativo (esqueleto, visor facial o guía)
              ?overlay,
            ],
          ),
        );
      },
    );
  }

  Widget _buildFallbackContent() {
    if (isPermissionDenied) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.amberWarning.withValues(alpha: 0.12),
              border: Border.all(
                color: AppColors.amberWarning.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            child: const Icon(
              Icons.no_photography_outlined,
              color: AppColors.amberWarning,
              size: 42,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Permiso de Cámara Denegado',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'LSC RT requiere acceso a la cámara para detectar la postura de las manos y el rostro. Concede el permiso en los ajustes de tu dispositivo para continuar.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.cyanAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text(
                'Reintentar Conexión',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              onPressed: onRetry,
            ),
          ],
        ],
      );
    }

    if (isSwitching) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.cyanAccent),
            strokeWidth: 2.8,
          ),
          SizedBox(height: 20),
          Text(
            'Cambiando de cámara...',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Alineando nuevo sensor de video',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      );
    }

    if (errorMessage != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.redError.withValues(alpha: 0.12),
              border: Border.all(
                color: AppColors.redError.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            child: const Icon(
              Icons.videocam_off_outlined,
              color: AppColors.redError,
              size: 42,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Cámara no disponible',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.cyanAccent,
                side: const BorderSide(color: AppColors.cyanAccent),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reintentar'),
              onPressed: onRetry,
            ),
          ],
        ],
      );
    }

    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.cyanAccent),
          strokeWidth: 2.5,
        ),
        SizedBox(height: 16),
        Text(
          'Inicializando visor...',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
