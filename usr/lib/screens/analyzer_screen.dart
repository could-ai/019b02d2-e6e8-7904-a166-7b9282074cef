import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';

class AnalyzerScreen extends StatefulWidget {
  const AnalyzerScreen({super.key});

  @override
  State<AnalyzerScreen> createState() => _AnalyzerScreenState();
}

class _AnalyzerScreenState extends State<AnalyzerScreen> {
  final List<VideoControllerWrapper> _videos = [];
  final List<Map<String, dynamic>> _markedFrames = [];

  // Global controls
  void _playAll() {
    for (var v in _videos) {
      v.controller.play();
    }
  }

  void _pauseAll() {
    for (var v in _videos) {
      v.controller.pause();
    }
  }

  Future<void> _pickVideos() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
      withData: kIsWeb, // Needed for web to get bytes/blob access if needed
    );

    if (result != null) {
      for (var file in result.files) {
        VideoPlayerController? controller;
        if (kIsWeb) {
          if (file.bytes != null) {
            // On web, we might need to create a blob URL or use bytes
            // video_player web supports network URLs. 
            // For local files on web, we often use XFile.path which is a blob url
            final xfile = XFile.fromData(file.bytes!, name: file.name);
            controller = VideoPlayerController.networkUrl(Uri.parse(xfile.path));
          }
        } else {
          if (file.path != null) {
            controller = VideoPlayerController.file(File(file.path!));
          }
        }

        if (controller != null) {
          await controller.initialize();
          setState(() {
            _videos.add(VideoControllerWrapper(
              controller: controller!,
              name: file.name,
              index: _videos.length + 1,
              onMarkFrame: _addMarkedFrame,
            ));
          });
        }
      }
    }
  }

  void _addMarkedFrame(int videoIndex, double time, String annotationData) {
    setState(() {
      _markedFrames.add({
        "video": videoIndex,
        "time": time,
        "annotations": annotationData,
      });
    });
  }

  Future<void> _exportCsv() async {
    if (_markedFrames.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No frames marked to export.")),
      );
      return;
    }

    // Build CSV Content
    StringBuffer csvBuffer = StringBuffer();
    csvBuffer.writeln("Video,Time (sec),Annotations");
    for (var frame in _markedFrames) {
      csvBuffer.writeln("${frame['video']},${frame['time'].toStringAsFixed(2)},\"${frame['annotations']}\"");
    }

    // Save and Share
    try {
      final box = context.findRenderObject() as RenderBox?;
      
      if (kIsWeb) {
        // Web export logic (simplified for this demo, usually involves creating a blob anchor)
        // For now, we'll just show a dialog with the content on web or print to console
        print(csvBuffer.toString());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("CSV Export downloaded (simulated on web)")),
        );
        // In a real web app, we'd use dart:html or package:web to trigger download
      } else {
        final directory = await getTemporaryDirectory();
        final path = '${directory.path}/frames_export.csv';
        final file = File(path);
        await file.writeAsString(csvBuffer.toString());
        
        await Share.shareXFiles(
          [XFile(path)],
          text: 'Exported Frames',
          sharePositionOrigin: box!.localToGlobal(Offset.zero) & box.size,
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error exporting: $e")),
      );
    }
  }

  @override
  void dispose() {
    for (var v in _videos) {
      v.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Dartfish-like Analyzer"),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _pickVideos,
            tooltip: "Add Videos",
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportCsv,
            tooltip: "Export CSV",
          ),
        ],
      ),
      body: Column(
        children: [
          // Global Controls
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _playAll,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text("Play All"),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _pauseAll,
                  icon: const Icon(Icons.pause),
                  label: const Text("Pause All"),
                ),
              ],
            ),
          ),
          
          // Video Grid
          Expanded(
            child: _videos.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.video_library, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text("No videos loaded."),
                        TextButton(
                          onPressed: _pickVideos,
                          child: const Text("Upload Videos"),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, // 2 videos per row
                      childAspectRatio: 1.2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: _videos.length,
                    itemBuilder: (context, index) {
                      return _videos[index];
                    },
                  ),
          ),

          // Marked Frames List
          Container(
            height: 150,
            color: Colors.grey[100],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text("Marked Frames:", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _markedFrames.length,
                    itemBuilder: (context, index) {
                      final frame = _markedFrames[index];
                      return ListTile(
                        dense: true,
                        title: Text("Video ${frame['video']} @ ${frame['time'].toStringAsFixed(2)}s"),
                        subtitle: Text("Annotations: ${frame['annotations'].length > 20 ? 'Yes' : 'None'}"),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VideoControllerWrapper extends StatefulWidget {
  final VideoPlayerController controller;
  final String name;
  final int index;
  final Function(int, double, String) onMarkFrame;

  const VideoControllerWrapper({
    super.key,
    required this.controller,
    required this.name,
    required this.index,
    required this.onMarkFrame,
  });

  @override
  State<VideoControllerWrapper> createState() => _VideoControllerWrapperState();
}

class _VideoControllerWrapperState extends State<VideoControllerWrapper> {
  List<Offset?> _points = [];
  bool _isDrawing = false;
  double _playbackSpeed = 1.0;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Video + Canvas Area
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: widget.controller.value.aspectRatio,
                  child: VideoPlayer(widget.controller),
                ),
                // Drawing Layer
                Positioned.fill(
                  child: GestureDetector(
                    onPanStart: (details) {
                      setState(() {
                        _isDrawing = true;
                        _points = [details.localPosition];
                      });
                    },
                    onPanUpdate: (details) {
                      setState(() {
                        _points.add(details.localPosition);
                      });
                    },
                    onPanEnd: (details) {
                      setState(() {
                        _isDrawing = false;
                        _points.add(null); // End of line
                      });
                    },
                    child: CustomPaint(
                      painter: DrawingPainter(_points),
                      size: Size.infinite,
                    ),
                  ),
                ),
                // Clear Button (Top Right)
                Positioned(
                  top: 5,
                  right: 5,
                  child: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.white, shadows: [Shadow(blurRadius: 2, color: Colors.black)]),
                    onPressed: () {
                      setState(() {
                        _points.clear();
                      });
                    },
                    tooltip: "Clear Drawing",
                  ),
                ),
              ],
            ),
          ),
          
          // Controls
          Container(
            color: Colors.black12,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(widget.controller.value.isPlaying ? Icons.pause : Icons.play_arrow, size: 20),
                      onPressed: () {
                        setState(() {
                          widget.controller.value.isPlaying
                              ? widget.controller.pause()
                              : widget.controller.play();
                        });
                      },
                    ),
                    Expanded(
                      child: VideoProgressIndicator(
                        widget.controller,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(playedColor: Colors.red),
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Speed Control
                    Row(
                      children: [
                        const Text("Speed:", style: TextStyle(fontSize: 10)),
                        SizedBox(
                          width: 80,
                          child: Slider(
                            value: _playbackSpeed,
                            min: 0.1,
                            max: 2.0,
                            divisions: 19,
                            label: _playbackSpeed.toStringAsFixed(1),
                            onChanged: (val) {
                              setState(() {
                                _playbackSpeed = val;
                                widget.controller.setPlaybackSpeed(val);
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    // Mark Frame
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                        minimumSize: const Size(60, 24),
                      ),
                      onPressed: () {
                        final time = widget.controller.value.position.inMilliseconds / 1000.0;
                        // Serialize points for export
                        final pointsJson = jsonEncode(_points.map((p) => p == null ? null : {'x': p.dx, 'y': p.dy}).toList());
                        widget.onMarkFrame(widget.index, time, pointsJson);
                      },
                      child: const Text("Mark", style: TextStyle(fontSize: 10)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DrawingPainter extends CustomPainter {
  final List<Offset?> points;

  DrawingPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = Colors.red
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.0;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(DrawingPainter oldDelegate) => true;
}
