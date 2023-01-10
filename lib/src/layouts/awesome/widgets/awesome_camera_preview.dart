import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:camerawesome/pigeon.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

enum CameraPreviewFit {
  fitWidth,
  fitHeight,
  contain,
  cover,
}

/// This is a fullscreen camera preview
/// some part of the preview are cropped so we have a full sized camera preview
class AwesomeCameraPreview extends StatefulWidget {
  const AwesomeCameraPreview({
    super.key,
    this.loadingWidget,
    required this.state,
    this.onPreviewTap,
    this.onPreviewScale,
    this.previewFit = CameraPreviewFit.cover,
    required this.interfaceBuilder,
    this.previewDecoratorBuilder,
  });
  final CameraPreviewFit previewFit;
  final Widget? loadingWidget;
  final CameraState state;
  final OnPreviewTap? onPreviewTap;
  final OnPreviewScale? onPreviewScale;
  final CameraLayoutBuilder interfaceBuilder;
  final CameraLayoutBuilder? previewDecoratorBuilder;

  @override
  State<StatefulWidget> createState() {
    return AwesomeCameraPreviewState();
  }
}

class AwesomeCameraPreviewState extends State<AwesomeCameraPreview> {
  PreviewSize? _previewSize;
  PreviewSize? _flutterPreviewSize;
  int? _textureId;

  PreviewSize? get pixelPreviewSize => _previewSize;

  PreviewSize? get flutterPreviewSize => _flutterPreviewSize;
  StreamSubscription? _sensorConfigSubscription;
  StreamSubscription? _aspectRatioSubscription;
  CameraAspectRatios? _aspectRatio;

  @override
  void initState() {
    super.initState();
    Future.wait([
      widget.state.previewSize(),
      widget.state.textureId(),
    ]).then((data) {
      if (mounted) {
        setState(() {
          _previewSize = data[0] as PreviewSize;
          _textureId = data[1] as int;
        });
      }
    });

    _sensorConfigSubscription =
        widget.state.sensorConfig$.listen((sensorConfig) {
      _aspectRatioSubscription?.cancel();
      _aspectRatioSubscription =
          sensorConfig.aspectRatio$.listen((event) async {
        final previewSize = await widget.state.previewSize();
        if ((_previewSize != previewSize || _aspectRatio != event) && mounted) {
          setState(() {
            _aspectRatio = event;
            _previewSize = previewSize;
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _sensorConfigSubscription?.cancel();
    _aspectRatioSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_textureId == null || _previewSize == null || _aspectRatio == null) {
      return widget.loadingWidget ??
          Center(
            child: Platform.isIOS
                ? const CupertinoActivityIndicator()
                : const CircularProgressIndicator(),
          );
    }
    return OrientationBuilder(
      builder: (context, orientation) {
        return LayoutBuilder(
          builder: (_, constraints) {
            final size = Size(_previewSize!.width, _previewSize!.height);

            final ratioW = constraints.maxWidth / size.width;
            final ratioH = constraints.maxHeight / size.height;
            Size maxSize;
            switch (widget.previewFit) {
              case CameraPreviewFit.fitWidth:
                maxSize = Size(constraints.maxWidth, size.height * ratioW);
                break;
              case CameraPreviewFit.fitHeight:
                maxSize = Size(size.width * ratioH, constraints.maxHeight);
                break;
              case CameraPreviewFit.cover:
                final previewRatio = _previewSize!.width / _previewSize!.height;
                maxSize = Size(
                  previewRatio > 1
                      ? constraints.maxHeight / previewRatio
                      : constraints.maxHeight * previewRatio,
                  constraints.maxHeight,
                );

                break;
              case CameraPreviewFit.contain:
                final ratio = min(ratioW, ratioH);
                maxSize = Size(size.width * ratio, size.height * ratio);
                break;
            }

            final center = Size(constraints.maxWidth, constraints.maxHeight)
                .center(Offset.zero);
            _flutterPreviewSize =
                PreviewSize(width: maxSize.width, height: maxSize.height);
            PreviewSize croppedPreviewSize = _flutterPreviewSize!;
            if (_aspectRatio == CameraAspectRatios.ratio_1_1) {
              croppedPreviewSize = PreviewSize(
                width: maxSize.shortestSide,
                height: maxSize.shortestSide,
              );
            }
            final preview = SizedBox(
              width: _flutterPreviewSize?.width,
              height: _flutterPreviewSize?.height,
              child: Center(
                child: SizedBox(
                  width: _flutterPreviewSize?.width,
                  height: _flutterPreviewSize?.height,
                  child: AwesomeCameraGestureDetector(
                    onPreviewTapBuilder: widget.onPreviewTap != null &&
                            _previewSize != null &&
                            _flutterPreviewSize != null
                        ? OnPreviewTapBuilder(
                            pixelPreviewSizeGetter: () => _previewSize!,
                            flutterPreviewSizeGetter: () =>
                                _flutterPreviewSize!,
                            onPreviewTap: widget.onPreviewTap!,
                          )
                        : null,
                    onPreviewScale: widget.onPreviewScale,
                    initialZoom: widget.state.sensorConfig.zoom,
                    child: Texture(textureId: _textureId!),
                  ),
                ),
              ),
            );

            if (_aspectRatio == CameraAspectRatios.ratio_1_1 &&
                [
                  CameraPreviewFit.fitHeight,
                  CameraPreviewFit.fitWidth,
                  CameraPreviewFit.contain
                ].contains(widget.previewFit)) {
              return Stack(
                children: [
                  Positioned.fill(
                    child: ClipPath(
                      clipper: CenterCropClipper(
                        isWidthLarger:
                            constraints.maxWidth > constraints.maxHeight,
                      ),
                      child: preview,
                    ),
                  ),
                  if (widget.previewDecoratorBuilder != null)
                    Positioned.fill(
                      child: widget.previewDecoratorBuilder!(
                        widget.state,
                        _flutterPreviewSize!,
                        Rect.fromCenter(
                          center: center,
                          width: croppedPreviewSize.width,
                          height: croppedPreviewSize.height,
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: widget.interfaceBuilder(
                      widget.state,
                      _flutterPreviewSize!,
                      Rect.fromCenter(
                        center: center,
                        width: croppedPreviewSize.width,
                        height: croppedPreviewSize.height,
                      ),
                    ),
                  ),
                ],
              );
            } else {
              return preview;
              return Stack(
                children: [
                  Positioned.fill(child: preview),
                  if (widget.previewDecoratorBuilder != null)
                    Positioned.fill(
                      child: widget.previewDecoratorBuilder!(
                        widget.state,
                        _flutterPreviewSize!,
                        Rect.fromCenter(
                          center: center,
                          width: croppedPreviewSize.width,
                          height: croppedPreviewSize.height,
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: widget.interfaceBuilder(
                      widget.state,
                      _flutterPreviewSize!,
                      Rect.fromCenter(
                        center: center,
                        width: croppedPreviewSize.width,
                        height: croppedPreviewSize.height,
                      ),
                    ),
                  ),
                ],
              );
            }
          },
        );
      },
    );
  }
}

class CenterCropClipper extends CustomClipper<Path> {
  const CenterCropClipper({required this.isWidthLarger});
  final bool isWidthLarger;

  @override
  Path getClip(Size size) {
    final center = size.center(Offset.zero);
    final side = min(size.width, size.height);
    if (isWidthLarger) {
      return Path()
        ..moveTo(center.dx, 0)
        ..lineTo(center.dx - side / 2.0, 0)
        ..lineTo(center.dx - side / 2.0, side)
        ..lineTo(center.dx + side / 2.0, side)
        ..lineTo(center.dx + side / 2.0, 0)
        ..lineTo(center.dx, 0);
    } else {
      return Path()
        ..moveTo(0, center.dy)
        ..lineTo(0, center.dy - side / 2.0)
        ..lineTo(side, center.dy - side / 2.0)
        ..lineTo(side, center.dy + side / 2.0)
        ..lineTo(0, center.dy + side / 2.0)
        ..lineTo(0, center.dy);
    }
  }

  @override
  bool shouldReclip(covariant CenterCropClipper oldClipper) {
    return isWidthLarger != oldClipper.isWidthLarger;
  }
}
