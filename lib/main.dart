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
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _download(String formatCode, bool isAudio) async {
    if (_sharedText == null || _sharedText!.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = isAudio ? "Extracting Audio..." : "Downloading Media...";
    });

    try {
      final String extension = isAudio ? 'mp3' : 'mp4';
      Directory? downloadsDirectory;
      if (Platform.isAndroid) {
        downloadsDirectory = Directory('/storage/emulated/0/Download');
      } else {
        downloadsDirectory = await getDownloadsDirectory();
      }
      
      final String cleanTitle = (_videoTitle ?? "Media").replaceAll(RegExp(r'[^\w\s]+'), '').trim().replaceAll(' ', '_');
      final String fileName = "\${cleanTitle}_\${DateTime.now().millisecondsSinceEpoch}.$extension";
      final String outputPath = "\${downloadsDirectory!.path}/$fileName";

      await platform.invokeMethod('download', {
        'url': _sharedText,
        'format': formatCode,
        'extractAudio': isAudio,
        'outputPath': outputPath,
      });

      setState(() {
        _statusMessage = "Saved to Downloads!";
        _isProcessing = false;
      });
      
      Future.delayed(const Duration(seconds: 2), () {
        SystemNavigator.pop();
      });

    } catch (e) {
      setState(() {
        _statusMessage = "Error: \${e.toString()}";
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.4),
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          constraints: const BoxConstraints(maxHeight: 600),
          decoration: BoxDecoration(
            color: const Color(0xFF161621).withOpacity(0.95),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 20,
                spreadRadius: 5,
              )
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle Bar
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    if (_sharedText == null)
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
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              const SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(
                  color: Colors.greenAccent,
                  strokeWidth: 3,
                ),
              ),
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
          ),
          const SizedBox(height: 8),
          const Text(
            "This may take a moment based on file size.",
            style: TextStyle(color: Colors.white54, fontSize: 12),
          )
        ],
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
        final formatCode = "bestvideo[height<=\$height]+bestaudio/best[height<=\$height]";
        
        return _OptionCard(
          title: "\${height}p",
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
