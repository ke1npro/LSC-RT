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

  const CameraViewport({
    super.key,
    required this.controller,
    this.isFrontCamera = true,
    this.overlay,
    this.onSizeChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return Container(
        color: AppColors.background,
        child: const Center(
          child: Column(
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
          ),
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
              // 1. Vista de cámara ajustada a pantalla
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
}
