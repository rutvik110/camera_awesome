// ignore_for_file: close_sinks

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:camerawesome/pigeon.dart';
import 'package:camerawesome/src/orchestrator/models/sensor_type.dart';
import 'package:rxdart/rxdart.dart';

import 'analysis/analysis_controller.dart';

/// This class handle the current state of the camera
/// - [PhotoCameraState]
/// - [VideoCameraState]
class CameraContext {
  /// Listen current state from child widgets
  late final BehaviorSubject<CameraState> stateController;

  late final Stream<CameraState> state$;

  CameraState get state => stateController.value;

  /// on media capturing stream controller
  late final BehaviorSubject<MediaCapture?> mediaCaptureController;

  late final Stream<MediaCapture?> captureState$;

  /// The config associated with a [Sensors].
  /// [back] sensor frequently has flash while [front] does not for instance.
  Stream<SensorConfig> sensorConfig$;

  BehaviorSubject<SensorConfig> sensorConfigController;

  /// implement this to have a callback after CameraAwesome asked for permissions
  final OnPermissionsResult? onPermissionsResult;

  final CaptureMode initialCaptureMode;

  /// this is where we are going to store any photo
  final SaveConfig saveConfig;

  /// allows to create dynamic analysis using the current preview
  final AnalysisController? analysisController;

  /// Preferences concerning Exif (photos metadata)
  final ExifPreferences exifPreferences;

  CameraContext._({
    required this.initialCaptureMode,
    required this.sensorConfigController,
    required this.analysisController,
    required this.saveConfig,
    this.onPermissionsResult,
    required this.exifPreferences,
  }) : sensorConfig$ = sensorConfigController.stream {
    var preparingState = PreparingCameraState(
      this,
      initialCaptureMode,
    );
    stateController = BehaviorSubject.seeded(preparingState);
    mediaCaptureController = BehaviorSubject.seeded(null);
    state$ = stateController.stream;
    captureState$ = mediaCaptureController.stream;
  }

  CameraContext.create(
    SensorConfig sensorConfig, {
    required CaptureMode initialCaptureMode,
    OnPermissionsResult? onPermissionsResult,
    required SaveConfig saveConfig,
    OnImageForAnalysis? onImageForAnalysis,
    AnalysisConfig? analysisConfig,
    required ExifPreferences exifPreferences,
  }) : this._(
          initialCaptureMode: initialCaptureMode,
          sensorConfigController: BehaviorSubject.seeded(sensorConfig),
          onPermissionsResult: onPermissionsResult,
          saveConfig: saveConfig,
          analysisController: onImageForAnalysis != null
              ? AnalysisController.fromPlugin(
                  onImageListener: onImageForAnalysis,
                  conf: analysisConfig,
                )
              : null,
          exifPreferences: exifPreferences,
        );

  changeState(CameraState newState) async {
    state.dispose();
    if (state.captureMode != newState.captureMode) {
      // This should not be done multiple times for the same CaptureMode or it
      // generates problems (especially when recording a video)
      await CamerawesomePlugin.setCaptureMode(newState.captureMode!);
    }
    if (!stateController.isClosed) {
      stateController.add(newState);
    }
  }

  Future<void> setSensorConfig(SensorConfig newConfig) async {
    sensorConfigController.sink.add(newConfig);
    if (sensorConfigController.hasValue &&
        !identical(newConfig, sensorConfigController.value)) {
      sensorConfigController.value.dispose();
    }
    await CamerawesomePlugin.setSensor(newConfig.sensor,
        deviceId: newConfig.captureDeviceId);
  }

  SensorConfig get sensorConfig {
    return sensorConfigController.value;
  }

  bool get imageAnalysisEnabled => analysisController != null;

  dispose() {
    sensorConfig.dispose();
    sensorConfigController.close();
    mediaCaptureController.close();
    stateController.close();
    analysisController?.close();
    state.dispose();
    CamerawesomePlugin.stop();
  }

  /// Global focus
  void focus() {
    CamerawesomePlugin.startAutoFocus();
  }

  Future<void> focusOnPoint({
    required Offset flutterPosition,
    required PreviewSize pixelPreviewSize,
    required PreviewSize flutterPreviewSize,
  }) async {
    if (Platform.isIOS) {
      final xPercentage = flutterPosition.dx / flutterPreviewSize.width;
      final yPercentage = flutterPosition.dy / flutterPreviewSize.height;

      return CamerawesomePlugin.focusOnPoint(
        position: Offset(xPercentage, yPercentage),
        previewSize: pixelPreviewSize,
      );
    } else {
      final ratio = pixelPreviewSize.height / flutterPreviewSize.height;
      // Transform flutter position to pixel position
      Offset pixelPosition = flutterPosition.scale(ratio, ratio);
      return CamerawesomePlugin.focusOnPoint(
          position: pixelPosition, previewSize: pixelPreviewSize);
    }
  }

  Future<PreviewSize> previewSize() {
    return CamerawesomePlugin.getEffectivPreviewSize();
  }

  Future<SensorDeviceData> getSensors() {
    return CamerawesomePlugin.getSensors();
  }

  Future<int?> textureId() {
    return CamerawesomePlugin.getPreviewTexture()
        .then(((value) => value?.toInt()));
  }
}
