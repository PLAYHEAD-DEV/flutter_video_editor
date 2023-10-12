// ignore_for_file: unnecessary_string_escapes

import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:video_editor/src/controller.dart';
import 'package:video_editor/src/models/cover_data.dart';
import 'package:video_editor/src/models/file_format.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class FFmpegVideoEditorExecute {
  const FFmpegVideoEditorExecute({
    required this.command,
    required this.outputPath,
  });

  final String command;
  final String outputPath;

  toJson() {
    return {
      'command': command,
      'outputPath': outputPath,
    };
  }

  static FFmpegVideoEditorExecute fromJson(Map<String, dynamic> json) {
    return FFmpegVideoEditorExecute(
      command: json['command'],
      outputPath: json['outputPath'],
    );
  }
}

class FFmpegVideoEditorContext {
  final Offset minCrop;
  final Offset maxCrop;

  final double videoWidth;
  final double videoHeight;

  final int rotation;

  final Duration startTrim;
  final Duration endTrim;
  final Duration videoDuration;

  final File videoFile;

  CoverData? selectedCoverVal;

  Duration get trimmedDuration => endTrim - startTrim;

  FFmpegVideoEditorContext({
    required this.minCrop,
    required this.maxCrop,
    required this.videoWidth,
    required this.videoHeight,
    required this.rotation,
    required this.startTrim,
    required this.endTrim,
    required this.videoDuration,
    required this.videoFile,
    this.selectedCoverVal,
  });

  FFmpegVideoEditorContext.create(VideoEditorController controller)
      : minCrop = controller.minCrop,
        maxCrop = controller.maxCrop,
        videoWidth = controller.videoWidth,
        videoHeight = controller.videoHeight,
        rotation = controller.rotation,
        startTrim = controller.startTrim,
        endTrim = controller.endTrim,
        videoDuration = controller.videoDuration,
        videoFile = controller.file,
        selectedCoverVal = controller.selectedCoverVal;

  toJson() {
    return {
      'minCrop': offsetToJson(minCrop),
      'maxCrop': offsetToJson(maxCrop),
      'width': videoWidth,
      'height': videoHeight,
      'rotation': rotation,
      'startTrim': startTrim.inMilliseconds,
      'endTrim': endTrim.inMilliseconds,
      'videoDuration': videoDuration.inMilliseconds,
      'videoFile': videoFile.path,
    };
  }

  static offsetToJson(Offset offset) {
    return {
      'dx': offset.dx,
      'dy': offset.dy,
    };
  }

  static FFmpegVideoEditorContext fromJson(Map<String, dynamic> json) {
    return FFmpegVideoEditorContext(
      minCrop: Offset(json['minCrop']['dx'], json['minCrop']['dy']),
      maxCrop: Offset(json['maxCrop']['dx'], json['maxCrop']['dy']),
      videoWidth: json['width'],
      videoHeight: json['height'],
      rotation: json['rotation'],
      startTrim: Duration(milliseconds: json['startTrim']),
      endTrim: Duration(milliseconds: json['endTrim']),
      videoDuration: Duration(milliseconds: json['videoDuration']),
      videoFile: File(json['videoFile']),
    );
  }
}

abstract class FFmpegVideoEditorConfig {
  final FFmpegVideoEditorContext context;

  /// If the [name] is `null`, then it uses this video filename.
  final String? name;

  /// If the [outputDirectory] is `null`, then it uses `TemporaryDirectory`.
  final String? outputDirectory;

  /// The [scale] is `scale=width*scale:height*scale` and reduce or increase the file dimensions.
  /// Defaults to `1.0`.
  final double scale;

  /// Set [isFiltersEnabled] to `false` if you do not want to apply any changes.
  /// Defaults to `true`.
  final bool isFiltersEnabled;

  const FFmpegVideoEditorConfig(
    this.context, {
    this.name,
    @protected this.outputDirectory,
    this.scale = 1.0,
    this.isFiltersEnabled = true,
  });

  /// Convert the controller's [minCrop] and [maxCrop] params into a [String]
  /// used to provide crop values to FFmpeg ([see more](https://ffmpeg.org/ffmpeg-filters.html#crop))
  ///
  /// The result is in the format `crop=w:h:x:y`
  String get cropCmd {
    if (context.minCrop <= minOffset && context.maxCrop >= maxOffset) {
      return "";
    }

    final enddx = context.videoWidth * context.maxCrop.dx;
    final enddy = context.videoHeight * context.maxCrop.dy;
    final startdx = context.videoWidth * context.minCrop.dx;
    final startdy = context.videoHeight * context.minCrop.dy;

    return "crop=${enddx - startdx}:${enddy - startdy}:$startdx:$startdy";
  }

  /// Convert the context's [rotation] value into a [String]
  /// used to provide crop values to FFmpeg ([see more](https://ffmpeg.org/ffmpeg-filters.html#transpose-1))
  ///
  /// The result is in the format `transpose=2` (repeated for every 90 degrees rotations)
  String get rotationCmd {
    final count = context.rotation / 90;
    if (count <= 0 || count >= 4) return "";

    final List<String> transpose = [];
    for (int i = 0; i < context.rotation / 90; i++) {
      transpose.add("transpose=2");
    }
    return transpose.isNotEmpty ? transpose.join(',') : "";
  }

  /// [see FFmpeg doc](https://ffmpeg.org/ffmpeg-filters.html#scale)
  ///
  /// The result is in format `scale=width*scale:height*scale`
  String get scaleCmd => scale == 1.0 ? "" : "scale=iw*$scale:ih*$scale";

  /// Returns the list of all the active filters
  List<String> getExportFilters() {
    if (!isFiltersEnabled) return [];
    final List<String> filters = [cropCmd, rotationCmd, scaleCmd];
    filters.removeWhere((item) => item.isEmpty);
    return filters;
  }

  /// Returns the `-filter:v` (-vf alias) command to use in FFmpeg execution
  String filtersCmd(List<String> filters) {
    filters.removeWhere((item) => item.isEmpty);
    return filters.isNotEmpty ? "-vf '${filters.join(",")}'" : "";
  }

  /// Returns the output path of the exported file
  Future<String> getOutputPath({
    required String filePath,
    required FileFormat format,
  }) async {
    final String tempPath =
        outputDirectory ?? (await getTemporaryDirectory()).path;
    final String n = name ?? path.basenameWithoutExtension(filePath);
    final int epoch = DateTime.now().millisecondsSinceEpoch;
    return "$tempPath/${n}_$epoch.${format.extension}".replaceAll(' ', '');
  }

  /// Can be used from FFmpeg session callback, for example:
  /// ```dart
  /// FFmpegKitConfig.enableStatisticsCallback((stats) {
  ///   final progress = getFFmpegSessionProgress(stats.getTime());
  /// });
  /// ```
  /// Returns the [double] progress value between 0.0 and 1.0.
  double getFFmpegProgress(int time) {
    final double progressValue = time / context.trimmedDuration.inMilliseconds;
    return progressValue.clamp(0.0, 1.0);
  }

  /// Returns the [FFmpegVideoEditorExecute] that contains the param to provide to FFmpeg.
  Future<FFmpegVideoEditorExecute?> getExecuteConfig();
}

class VideoFFmpegVideoEditorConfig extends FFmpegVideoEditorConfig {
  const VideoFFmpegVideoEditorConfig(
    super.controller, {
    super.name,
    super.outputDirectory,
    super.scale,
    super.isFiltersEnabled,
    this.format = VideoExportFormat.mp4,
    this.commandBuilder,
  });

  /// The [format] of the video to be exported.
  /// You can export as a GIF file by using [VideoExportFormat.gif] or with
  /// [GifExportFormat()] which allows you to control the frame rate of the exported GIF file.
  ///
  /// Defaults to [VideoExportFormat.mp4].
  final VideoExportFormat format;

  /// The [commandBuilder] can be used to add additional filters or options to the generated command
  final String Function(
    FFmpegVideoEditorConfig config,
    String videoPath,
    String outputPath,
  )? commandBuilder;

  /// Returns the FFpeg command to apply the controller's trim start parameters
  /// [see FFmpeg doc](https://trac.ffmpeg.org/wiki/Seeking#Cuttingsmallsections)
  String get startTrimCmd => "-ss ${context.startTrim}";

  /// Returns the FFpeg command to apply the controller's trim end parameters
  /// [see FFmpeg doc](https://trac.ffmpeg.org/wiki/Seeking#Cuttingsmallsections)
  String get toTrimCmd => "-t ${context.trimmedDuration}";

  /// Returns the FFmpeg command to make the generated GIF to loop infinitely
  /// [see FFmpeg doc](https://ffmpeg.org/ffmpeg-formats.html#gif-2)
  String get gifCmd =>
      format.extension == VideoExportFormat.gif.extension ? "-loop 0" : "";

  /// Returns the list of all the active filters, including the GIF filter
  @override
  List<String> getExportFilters() {
    final List<String> filters = super.getExportFilters();
    final bool isGif = format.extension == VideoExportFormat.gif.extension;
    if (isGif) {
      filters.add(
          'fps=${format is GifExportFormat ? (format as GifExportFormat).fps : VideoExportFormat.gif.fps}');
    }
    return filters;
  }

  /// Returns a [FFmpegVideoEditorExecute] command to be executed with FFmpeg to export
  /// the video applying the editing parameters.
  @override
  Future<FFmpegVideoEditorExecute> getExecuteConfig() async {
    final String videoPath = context.videoFile.path;
    final String outputPath =
        await getOutputPath(filePath: videoPath, format: format);
    final List<String> filters = getExportFilters();

    return FFmpegVideoEditorExecute(
      command: commandBuilder != null
          ? commandBuilder!(this, "\'$videoPath\'", "\'$outputPath\'")
          // use -y option to overwrite the output
          // use -c copy if there is not filters to avoid re-encoding the video and speedup the process
          : "$startTrimCmd -i \'$videoPath\' $toTrimCmd ${filtersCmd(filters)} $gifCmd ${filters.isEmpty ? '-c copy' : ''} -preset ultrafast -y \'$outputPath\'",
      outputPath: outputPath,
    );
  }
}

class CoverFFmpegVideoEditorConfig extends FFmpegVideoEditorConfig {
  const CoverFFmpegVideoEditorConfig(
    super.controller, {
    super.name,
    super.outputDirectory,
    super.scale,
    super.isFiltersEnabled,
    this.format = CoverExportFormat.jpg,
    this.quality = 100,
    this.commandBuilder,
  });

  /// The [format] of the cover image to be exported.
  ///
  /// Defaults to [CoverExportFormat.jpg].
  final CoverExportFormat format;

  /// The [quality] of the exported image (from 0 to 100 ([more info](https://pub.dev/packages/video_thumbnail)))
  ///
  /// Defaults to `100`.
  final int quality;

  /// The [commandBuilder] can be used to add additional filters or options to the generated command
  final String Function(
    CoverFFmpegVideoEditorConfig config,
    String coverPath,
    String outputPath,
  )? commandBuilder;

  /// Generate this selected cover image as a JPEG [File]
  ///
  /// If this controller's [selectedCoverVal] is `null`, then it return the first frame of this video.
  Future<String?> _generateCoverFile() async => VideoThumbnail.thumbnailFile(
        imageFormat: ImageFormat.JPEG,
        thumbnailPath: (await getTemporaryDirectory()).path,
        video: context.videoFile.path,
        timeMs: context.selectedCoverVal?.timeMs ??
            context.startTrim.inMilliseconds,
        quality: quality,
      );

  /// Returns a [FFmpegVideoEditorExecute] command to be executed with FFmpeg to export
  /// the cover image applying the editing parameters.
  @override
  Future<FFmpegVideoEditorExecute?> getExecuteConfig() async {
    // file generated from the thumbnail library or video source
    final String? coverPath = await _generateCoverFile();
    if (coverPath == null) {
      debugPrint('VideoThumbnail library error while exporting the cover');
      return null;
    }
    final String outputPath =
        await getOutputPath(filePath: coverPath, format: format);
    final List<String> filters = getExportFilters();

    return FFmpegVideoEditorExecute(
      command: commandBuilder != null
          ? commandBuilder!(this, "\'$coverPath\'", "\'$outputPath\'")
          // use -y option to overwrite the output
          : "-i \'$coverPath\' ${filtersCmd(filters)} -y \'$outputPath\'",
      outputPath: outputPath,
    );
  }
}
