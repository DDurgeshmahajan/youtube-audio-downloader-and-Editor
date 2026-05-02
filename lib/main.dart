import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Frictionless Media',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.transparent,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      home: const DownloadOverlay(),
    );
  }
}

class DownloadOverlay extends StatefulWidget {
  const DownloadOverlay({super.key});

  @override
  State<DownloadOverlay> createState() => _DownloadOverlayState();
}

class _DownloadOverlayState extends State<DownloadOverlay> with SingleTickerProviderStateMixin {
  late StreamSubscription _intentDataStreamSubscription;
  String? _sharedText;
  
  bool _isLoadingInfo = false;
  bool _isProcessing = false;
  String _statusMessage = "Waiting for URL...";
  
  String? _thumbnailUrl;
  String? _videoTitle;
  List<int> _availableVideoHeights = [];
  bool _hasAudio = false;

  late TabController _tabController;

  static const platform = MethodChannel('com.ytdownloader/ytdl');
  static const progressChannel = EventChannel('com.ytdownloader/progress');
  
  StreamSubscription? _progressSubscription;
  double _downloadProgress = 0.0;
  String _etaMessage = "";
  bool _hasCheckedForUpdates = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _requestPermissions();

    _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        _handleIncomingUrl(value.first.path);
      }
    }, onError: (err) {
      print("getLinkStream error: $err");
    });

    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        _handleIncomingUrl(value.first.path);
      }
    });

    _progressSubscription = progressChannel.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        setState(() {
          _downloadProgress = (event['progress'] as num?)?.toDouble() ?? 0.0;
          _etaMessage = event['eta']?.toString() ?? "";
          if (_downloadProgress > 0 && _statusMessage != "Saved to Downloads!") {
            _statusMessage = "Downloading... ${_downloadProgress.toStringAsFixed(1)}%";
          }
        });
      } else if (event is String) {
        setState(() {
          if (event.startsWith("Error")) {
            _statusMessage = event;
            _isProcessing = false;
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(event),
                  backgroundColor: Colors.redAccent,
                  duration: const Duration(seconds: 5),
                ),
              );
            }
          }
        });
      }
    });
  }

  final TextEditingController _urlController = TextEditingController();

  void _handleIncomingUrl(String url) {
    if (url.isEmpty) return;
    setState(() {
      _sharedText = url;
      _statusMessage = "Analyzing media...";
      _isLoadingInfo = true;
    });
    _fetchMediaInfo(url);
  }


  Future<void> _fetchMediaInfo(String url) async {
    try {
      final String jsonResponse = await platform.invokeMethod('getFormats', {'url': url});
      final Map<String, dynamic> data = jsonDecode(jsonResponse);
      
      final formats = data['formats'] as List<dynamic>? ?? [];
      final Set<int> heights = {};
      bool foundAudio = false;

      for (var format in formats) {
        if (format['vcodec'] != 'none' && format['height'] != null) {
          heights.add((format['height'] as num).toInt());
        }
        if (format['acodec'] != 'none') {
          foundAudio = true;
        }
      }

      final sortedHeights = heights.toList()..sort((a, b) => b.compareTo(a));

      setState(() {
        _thumbnailUrl = data['thumbnail'];
        _videoTitle = data['title'] ?? 'Unknown Media';
        _availableVideoHeights = sortedHeights;
        _hasAudio = foundAudio;
        _isLoadingInfo = false;
      });
    } catch (e) {
      setState(() {
        _statusMessage = "Analysis failed. You can still use quick download.";
        _isLoadingInfo = false;
        // Fallback options
        _availableVideoHeights = [1080, 720, 480, 360];
        _hasAudio = true; 
      });
    }
  }

  Future<void> _requestPermissions() async {
    await [Permission.storage, Permission.manageExternalStorage, Permission.notification].request();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _intentDataStreamSubscription.cancel();
    _progressSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _download(String formatCode, bool isAudio) async {
    if (_sharedText == null || _sharedText!.isEmpty) return;

    if (!_hasCheckedForUpdates) {
      setState(() {
        _isProcessing = true;
        _downloadProgress = 0.0;
        _etaMessage = "";
        _statusMessage = "Ensuring engine is up-to-date...";
      });
      try {
        await platform.invokeMethod('update');
      } catch (e) {
        // Ignore update failure, continue to download
      }
      _hasCheckedForUpdates = true;
    }

    setState(() {
      _isProcessing = true;
      _downloadProgress = 0.0;
      _etaMessage = "";
      _statusMessage = isAudio ? "Extracting Audio..." : "Downloading Media...";
    });

    try {
      final String cleanTitle = (_videoTitle ?? "Media").replaceAll(RegExp(r'[^\w\s]+'), '').trim().replaceAll(' ', '_');
      final String extension = isAudio ? 'mp3' : 'mp4';
      final String fallbackPath = "/storage/emulated/0/Download/${cleanTitle}_${DateTime.now().millisecondsSinceEpoch}.$extension";

      final String? savedPath = await platform.invokeMethod('download', {
        'url': _sharedText,
        'format': formatCode,
        'extractAudio': isAudio,
        'title': cleanTitle,
        'outputPath': fallbackPath,
      });

      setState(() {
        _isProcessing = false;
        _statusMessage = "Waiting for URL...";
        _sharedText = null;
        _urlController.clear();
      });

      if (mounted && savedPath != null) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E2C),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.elasticOut,
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      child: const Icon(Icons.check_circle, color: Colors.greenAccent, size: 36),
                    );
                  },
                ),
                const SizedBox(width: 12),
                const Text("Saved Successfully!", style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Your file has been saved to your gallery and downloads folder.",
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                const Text("Path:", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  width: double.maxFinite,
                  decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                  child: SelectableText(
                    savedPath,
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 13),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Awesome!", style: TextStyle(color: Colors.deepPurpleAccent, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: ${e.toString()}"),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  bool _isUpdating = false;

  Future<void> _updateEngine() async {
    setState(() {
      _isUpdating = true;
      _statusMessage = "Updating Download Engine...";
    });
    try {
      final status = await platform.invokeMethod('update');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Engine Updated: $status"), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Update Failed: ${e.toString()}"), backgroundColor: Colors.redAccent));
      }
    } finally {
      setState(() {
        _isUpdating = false;
        _statusMessage = "Waiting for URL...";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        title: const Text("Frictionless Media", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: [
          if (_isUpdating)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.system_update),
              tooltip: 'Update Download Engine',
              onPressed: _updateEngine,
            )
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              if (_isUpdating)
                _buildProcessing()
              else if (_sharedText == null)
                _buildManualInput()
              else if (_isLoadingInfo)
                _buildLoader()
              else if (_isProcessing)
                _buildProcessing()
              else
                _buildMediaUI(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoader() {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        children: [
          const CircularProgressIndicator(color: Colors.deepPurpleAccent, strokeWidth: 3),
          const SizedBox(height: 24),
          Text(
            _statusMessage,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 16,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessing() {
    return Expanded(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(
                      value: _downloadProgress > 0 ? _downloadProgress / 100 : null,
                      color: Colors.greenAccent,
                      strokeWidth: 4,
                    ),
                  ),
                  if (_downloadProgress > 0)
                    Text(
                      "${_downloadProgress.toInt()}%",
                      style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
                    )
                  else
                    Icon(Icons.download_rounded, color: Colors.greenAccent.withOpacity(0.8), size: 28),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                _statusMessage,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              if (_etaMessage.isNotEmpty && _etaMessage != "null" && _downloadProgress < 100)
                Text(
                  "ETA: $_etaMessage seconds",
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
                )
              else
                const Text(
                  "This may take a moment based on file size.",
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaUI() {
    return Flexible(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with Thumbnail and Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Row(
              children: [
                if (_thumbnailUrl != null)
                  Container(
                    width: 100,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: _thumbnailUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        errorWidget: (context, url, error) => const Icon(Icons.error),
                      ),
                    ),
                  ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    _videoTitle ?? "Ready to Download",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          
          // Tabs
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.deepPurpleAccent.withOpacity(0.3),
                border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.5)),
              ),
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: const [
                Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.videocam, size: 18), SizedBox(width: 8), Text("Video")])),
                Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.audiotrack, size: 18), SizedBox(width: 8), Text("Audio")])),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Tab Views
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildVideoOptions(),
                  _buildAudioOptions(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildManualInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
      child: Column(
        children: [
          const Icon(Icons.link, size: 48, color: Colors.deepPurpleAccent),
          const SizedBox(height: 16),
          const Text(
            "Paste a link to download",
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  style: const TextStyle(color: Colors.white),
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: "https://youtube.com/watch?v=...",
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.paste, color: Colors.deepPurpleAccent),
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data != null && data.text != null) {
                          _urlController.text = data.text!;
                        }
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              InkWell(
                onTap: () {
                  if (_urlController.text.trim().isNotEmpty) {
                    _handleIncomingUrl(_urlController.text.trim());
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.deepPurpleAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.5)),
                  ),
                  child: const Icon(Icons.arrow_forward_ios, color: Colors.deepPurpleAccent, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildVideoOptions() {
    if (_availableVideoHeights.isEmpty) {
      return const Center(child: Text("No video formats found", style: TextStyle(color: Colors.white54)));
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: _availableVideoHeights.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final height = _availableVideoHeights[index];
        final bool isHD = height >= 720;
        final formatCode = "bestvideo[height<=$height]+bestaudio/best[height<=$height]";
        
        return _OptionCard(
          title: "${height}p",
          subtitle: isHD ? "High Definition" : "Standard Quality",
          icon: isHD ? Icons.hd : Icons.sd,
          color: isHD ? Colors.blueAccent : Colors.white60,
          onTap: () => _download(formatCode, false),
        );
      },
    );
  }

  Widget _buildAudioOptions() {
    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: [
        _OptionCard(
          title: "Best Audio (MP3)",
          subtitle: "Highest available quality",
          icon: Icons.high_quality,
          color: Colors.pinkAccent,
          onTap: () => _download("bestaudio/best", true),
        ),
        const SizedBox(height: 10),
        _OptionCard(
          title: "Standard Audio (MP3)",
          subtitle: "Optimized file size",
          icon: Icons.music_note,
          color: Colors.purpleAccent,
          onTap: () => _download("bestaudio[abr<=128]/best", true),
        ),
      ],
    );
  }
}

class _OptionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _OptionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        highlightColor: color.withOpacity(0.2),
        splashColor: color.withOpacity(0.3),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            borderRadius: BorderRadius.circular(16),
            color: Colors.white.withOpacity(0.03),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: Colors.white.withOpacity(0.2), size: 14),
            ],
          ),
        ),
      ),
    );
  }
}
