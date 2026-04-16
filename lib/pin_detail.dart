import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:gal/gal.dart';
import 'package:permission_handler/permission_handler.dart';
import 'pinterest_client.dart';
import 'user_detail.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'dart:io';

class PinDetailPage extends StatefulWidget {
  final Map<String, dynamic> pin;

  const PinDetailPage({super.key, required this.pin});

  @override
  State<PinDetailPage> createState() => _PinDetailPageState();
}

class _PinDetailPageState extends State<PinDetailPage> {
  final PinterestClient _client = PinterestClient();
  final ScrollController _scrollController = ScrollController();
  
  Map<String, dynamic>? _detailedPin;
  List<Map<String, dynamic>> _comments = [];
  bool _isLoadingDetailed = true;
  bool _isLoadingComments = true;
  bool _isLoadingMoreComments = false;
  String? _bookmark;

  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isVideoInitialized = false;
  bool _isDownloading = false;
  double _downloadProgress = 0;

  @override
  void initState() {
    super.initState();
    _detailedPin = widget.pin;
    _scrollController.addListener(_onScroll);
    _fetchData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingComments && !_isLoadingMoreComments && _bookmark != null && _bookmark!.isNotEmpty) {
        _loadMoreComments();
      }
    }
  }

  Future<void> _fetchData() async {
    final pinId = widget.pin['id'] ?? widget.pin['entity_id'];
    if (pinId == null) return;
    
    // Fetch detailed pin metadata for full stats
    final detail = await _client.getPin(pinId);
    if (detail != null) {
      setState(() {
        _detailedPin = detail;
        _isLoadingDetailed = false;
      });
      _initVideoIfNeeded(detail);
    } else {
      _initVideoIfNeeded(widget.pin);
    }

    final response = await _client.getComments(pinId);
    setState(() {
      _comments = response['results'];
      _bookmark = response['bookmark'];
      _isLoadingComments = false;
    });
  }

  Future<void> _initVideoIfNeeded(Map<String, dynamic> pin) async {
    final videoData = _client.extractVideo(pin);
    if (videoData != null && videoData['url'] != null) {
      String videoUrl = videoData['url'] as String;
      File? localM3u8File;

      if (videoUrl.contains('.m3u8')) {
        try {
          final dio = Dio();
          dio.options.headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36';
          final playlistResponse = await dio.get(videoUrl);
          String playlistData = playlistResponse.data.toString();
          
          // Only process if it's the concatenated format without a master playlist
          if (!playlistData.contains('#EXT-X-STREAM-INF') && playlistData.contains('#EXTM3U') && playlistData.split('#EXTM3U').length > 2) {
            final blocks = playlistData.split('#EXT-X-ENDLIST');
            int maxWidth = 0;
            String targetBlock = blocks.first;
            for (var block in blocks) {
              final wMatch = RegExp(r'_(\d+)w\.cmfv').firstMatch(block);
              if (wMatch != null) {
                final w = int.parse(wMatch.group(1)!);
                if (w > maxWidth) {
                  maxWidth = w;
                  targetBlock = block;
                }
              }
            }
            
            final baseUrl = videoUrl.substring(0, videoUrl.lastIndexOf('/') + 1);
            final lines = targetBlock.split('\n');
            for (int i = 0; i < lines.length; i++) {
              if (lines[i].startsWith('#EXT-X-MAP:')) {
                final uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(lines[i]);
                if (uriMatch != null && !uriMatch.group(1)!.startsWith('http')) {
                  lines[i] = lines[i].replaceAll(uriMatch.group(1)!, baseUrl + uriMatch.group(1)!);
                }
              } else if (lines[i].isNotEmpty && !lines[i].startsWith('#')) {
                if (!lines[i].startsWith('http')) {
                  lines[i] = baseUrl + lines[i];
                }
              }
            }
            
            final dir = await getTemporaryDirectory();
            localM3u8File = File(p.join(dir.path, 'temp_${DateTime.now().millisecondsSinceEpoch}.m3u8'));
            await localM3u8File.writeAsString(lines.join('\n') + '\n#EXT-X-ENDLIST\n');
          }
        } catch (e) {
          print('Error parsing playlist: $e');
        }
      }

      if (!mounted) return;

      if (localM3u8File != null) {
        _videoPlayerController = VideoPlayerController.file(localM3u8File);
      } else {
        _videoPlayerController = VideoPlayerController.networkUrl(
          Uri.parse(videoUrl),
          httpHeaders: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',
          },
        );
      }
      
      _videoPlayerController!.initialize().then((_) {
        if (!mounted) return;
        setState(() {
          _chewieController = ChewieController(
            videoPlayerController: _videoPlayerController!,
            autoPlay: true,
            looping: false,
            aspectRatio: _videoPlayerController!.value.aspectRatio,
            errorBuilder: (context, errorMessage) {
              return Center(
                child: Text(
                  errorMessage,
                  style: const TextStyle(color: Colors.white),
                ),
              );
            },
          );
          _isVideoInitialized = true;
        });
      }).catchError((e) {
        print('Video init error: $e');
      });
    }
  }

  Future<bool> _requestPhotoPermission() async {
    if (Platform.isIOS) {
      final status = await Permission.photos.status;
      final addOnlyStatus = await Permission.photosAddOnly.status;
      if (status.isGranted || addOnlyStatus.isGranted || status.isLimited) {
        return true;
      }
      final result = await Permission.photosAddOnly.request();
      if (result.isGranted || result.isLimited) {
        return true;
      }
      final fullResult = await Permission.photos.request();
      return fullResult.isGranted || fullResult.isLimited;
    } else if (Platform.isAndroid) {
      final status = await Permission.photos.status;
      if (status.isGranted) return true;
      final result = await Permission.photos.request();
      return result.isGranted;
    }
    return true;
  }

  Future<void> _downloadMedia() async {
    final hasPermission = await _requestPhotoPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permission denied. Cannot save media.')),
        );
      }
      return;
    }

    final currentPin = _detailedPin ?? widget.pin;
    final videoData = _client.extractVideo(currentPin);
    String? mediaUrl;
    bool isHls = false;

    if (videoData != null) {
      // For downloads, try to find a direct MP4 first to ensure audio+video is combined
      final videoList = currentPin['videos']?['video_list'] ?? currentPin['video_list'];
      if (videoList is Map) {
        final variants = videoList.cast<String, dynamic>();
        final mp4Keys = ['V_720W', 'V_360W', 'V_240W'];
        for (var key in mp4Keys) {
          if (variants.containsKey(key) && variants[key]['url'] != null) {
            mediaUrl = variants[key]['url'];
            isHls = false;
            break;
          }
        }
      }
      
      // Fallback to original selection if no direct MP4 found
      if (mediaUrl == null && videoData['url'] != null) {
        mediaUrl = videoData['url'];
        isHls = mediaUrl!.contains('.m3u8');
      }
    } else {
      mediaUrl = _client.extractImage(currentPin['images']);
    }

    if (mediaUrl == null || mediaUrl.isEmpty) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    try {
      final pinId = currentPin['id'] ?? currentPin['entity_id'] ?? 'pin';
      final dio = Dio();
      dio.options.headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36';

      final tempDir = await getTemporaryDirectory();
      String filePath;

      if (isHls) {
        final fileName = 'catpin_$pinId.mp4';
        filePath = p.join(tempDir.path, fileName);
        
        // 1. Fetch Playlist
        final playlistResponse = await dio.get(mediaUrl);
        final playlistData = playlistResponse.data.toString();
        
        String targetBlock = playlistData;
        
        // If Pinterest's concatenated format
        if (playlistData.contains('#EXTM3U') && playlistData.split('#EXTM3U').length > 2) {
          final blocks = playlistData.split('#EXT-X-ENDLIST');
          int maxWidth = 0;
          for (var block in blocks) {
            final wMatch = RegExp(r'_(\d+)w\.cmfv').firstMatch(block);
            if (wMatch != null) {
              final w = int.parse(wMatch.group(1)!);
              if (w > maxWidth) {
                maxWidth = w;
                targetBlock = block;
              }
            }
          }
          if (maxWidth == 0 && blocks.isNotEmpty) {
            targetBlock = blocks.first; // fallback
          }
        }
        
        final blockLines = targetBlock.split('\n');
        String? mapUri;
        String? mapByteRange;
        List<Map<String, String>> segments = [];
        String? currentByteRange;

        for (String line in blockLines) {
          if (line.startsWith('#EXT-X-MAP:')) {
            final uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(line);
            final rangeMatch = RegExp(r'BYTERANGE="([^"]+)"').firstMatch(line);
            if (uriMatch != null) mapUri = uriMatch.group(1);
            if (rangeMatch != null) mapByteRange = rangeMatch.group(1);
          } else if (line.startsWith('#EXT-X-BYTERANGE:')) {
            currentByteRange = line.substring('#EXT-X-BYTERANGE:'.length).trim();
          } else if (line.isNotEmpty && !line.startsWith('#')) {
            segments.add({
              'uri': line.trim(),
              'byteRange': currentByteRange ?? '',
            });
            currentByteRange = null;
          }
        }

        if (segments.isEmpty) throw Exception('No segments found in HLS playlist');

        final baseUrl = mediaUrl.substring(0, mediaUrl.lastIndexOf('/') + 1);
        final file = File(filePath);
        final sink = file.openWrite();
        
        int totalRequests = (mapUri != null ? 1 : 0) + segments.length;
        int completedRequests = 0;

        Future<void> downloadChunk(String uri, String byteRange) async {
          final segmentUrl = uri.startsWith('http') ? uri : baseUrl + uri;
          final headers = <String, dynamic>{};
          if (byteRange.isNotEmpty) {
            final parts = byteRange.split('@');
            if (parts.length == 2) {
              final length = int.parse(parts[0]);
              final offset = int.parse(parts[1]);
              headers['Range'] = 'bytes=$offset-${offset + length - 1}';
            }
          }
          final segmentResp = await dio.get<List<int>>(
            segmentUrl, 
            options: Options(
              responseType: ResponseType.bytes,
              headers: headers.isNotEmpty ? headers : null,
            ),
          );
          if (segmentResp.data != null) {
            sink.add(segmentResp.data!);
          }
          completedRequests++;
          if (mounted) {
            setState(() {
              _downloadProgress = completedRequests / totalRequests;
            });
          }
        }

        if (mapUri != null) {
          await downloadChunk(mapUri, mapByteRange ?? '');
        }

        for (var segment in segments) {
          await downloadChunk(segment['uri']!, segment['byteRange']!);
        }
        
        await sink.close();

      } else {
        final extension = mediaUrl.contains('.mp4') ? '.mp4' : '.jpg';
        final fileName = 'catpin_$pinId$extension';
        filePath = p.join(tempDir.path, fileName);

        await dio.download(
          mediaUrl,
          filePath,
          onReceiveProgress: (count, total) {
            if (total != -1) {
              setState(() {
                _downloadProgress = count / total;
              });
            }
          },
        );
      }

      // Save to gallery using gal
      if (Platform.isAndroid || Platform.isIOS) {
        try {
          if (mediaUrl.contains('.mp4') || isHls) {
            await Gal.putVideo(filePath);
          } else {
            await Gal.putImage(filePath);
          }
        } catch (e) {
          throw Exception('Failed to save to gallery: $e');
        }
      } else {
        final downloadsDir = await getDownloadsDirectory();
        if (downloadsDir != null) {
          final finalPath = p.join(downloadsDir.path, p.basename(filePath));
          await File(filePath).copy(finalPath);
          filePath = finalPath;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Media saved successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  Future<void> _loadMoreComments() async {
    if (_isLoadingMoreComments || _bookmark == null) return;
    
    setState(() {
      _isLoadingMoreComments = true;
    });

    final pinId = widget.pin['id'] ?? widget.pin['entity_id'];
    final response = await _client.getComments(pinId, bookmark: _bookmark);
    
    setState(() {
      _comments.addAll(response['results']);
      _bookmark = response['bookmark'];
      _isLoadingMoreComments = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentPin = _detailedPin ?? widget.pin;
    final imageUrl = _client.extractImage(currentPin['images']);
    final rawTitle = currentPin['title'] ?? currentPin['grid_title'];
    String title = '';
    if (rawTitle is String) {
      title = rawTitle;
    } else if (rawTitle is Map) {
      title = rawTitle['text'] ?? rawTitle['format'] ?? '';
    }
    final description = currentPin['description'] ?? '';
    final pinner = currentPin['pinner'] ?? currentPin['closeup_attribution'] ?? {};
    final authorName = pinner['full_name'] ?? pinner['username'] ?? '';
    final authorUsername = pinner['username'] ?? '';
    final authorAvatar = pinner['image_medium_url'] ?? '';

    final stats = _client.extractStats(currentPin);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pin Detail'),
        actions: [
          if (_isDownloading)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  value: _downloadProgress > 0 ? _downloadProgress : null,
                  strokeWidth: 2,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: _downloadMedia,
              tooltip: 'Download',
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 900) {
            // Desktop Sidebar Layout
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Center(
                    child: _buildMediaViewer(imageUrl),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _buildSidebar(context, title, authorName, authorUsername, authorAvatar, description, stats),
                ),
              ],
            );
          } else {
            // Mobile Stack Layout
            return _buildMobileLayout(context, imageUrl, title, authorName, authorUsername, authorAvatar, description, stats);
          }
        },
      ),
    );
  }

  Widget _buildMediaViewer(String imageUrl) {
    final currentPin = _detailedPin ?? widget.pin;
    final isVideo = _client.extractVideo(currentPin) != null;

    if (_isVideoInitialized && _chewieController != null) {
      return AspectRatio(
        aspectRatio: _videoPlayerController!.value.aspectRatio,
        child: Chewie(controller: _chewieController!),
      );
    }
    
    if (imageUrl.isNotEmpty) {
      // Set scaleEnabled: false to prevent accidental zooming during page scroll on desktop
      return InteractiveViewer(
        scaleEnabled: false, 
        child: Stack(
          alignment: Alignment.center,
          children: [
            CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.contain,
              placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
            ),
            if (isVideo)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const CircularProgressIndicator(
                  color: Colors.white,
                ),
              ),
          ],
        ),
      );
    }
    
    return const SizedBox.shrink();
  }

  Widget _buildSidebar(BuildContext context, String title, String authorName, String authorUsername, String authorAvatar, String description, Map<String, dynamic> stats) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Colors.white10)),
      ),
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(24.0),
        children: [
          _buildInfo(context, title, authorName, authorUsername, authorAvatar, description, stats),
          const Divider(height: 48),
          _buildComments(context, stats['comments']),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context, String imageUrl, String title, String authorName, String authorUsername, String authorAvatar, String description, Map<String, dynamic> stats) {
    return SingleChildScrollView(
      controller: _scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMediaViewer(imageUrl),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfo(context, title, authorName, authorUsername, authorAvatar, description, stats),
                const Divider(height: 32),
                _buildComments(context, stats['comments']),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfo(BuildContext context, String title, String authorName, String authorUsername, String authorAvatar, String description, Map<String, dynamic> stats) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty)
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            InkWell(
              onTap: () {
                if (authorUsername.isNotEmpty) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => UserDetailPage(user: {'username': authorUsername}),
                    ),
                  );
                }
              },
              child: CircleAvatar(
                backgroundImage: authorAvatar.isNotEmpty ? CachedNetworkImageProvider(authorAvatar) : null,
                child: authorAvatar.isEmpty ? const Icon(Icons.person) : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () {
                  if (authorUsername.isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => UserDetailPage(user: {'username': authorUsername}),
                      ),
                    );
                  }
                },
                child: Text(
                  authorName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
            _buildStat(Icons.save_alt, stats['saves']),
            const SizedBox(width: 8),
            _buildStat(Icons.favorite_border, stats['likes']),
          ],
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            description,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ],
    );
  }

  Widget _buildComments(BuildContext context, dynamic totalCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Comments',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        if (_isLoadingComments)
          const Center(child: CircularProgressIndicator())
        else if (_comments.isEmpty)
          const Text('No comments yet.')
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _comments.length + (_bookmark != null ? 1 : 0),
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == _comments.length) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final comment = _comments[index];
              final user = comment['user'] ?? {};
              final text = comment['text'] ?? comment['details'] ?? '';
              final userName = user['full_name'] ?? user['username'] ?? 'Anonymous';
              final authorUsername = user['username'] ?? '';
              final avatar = user['image_medium_url'] ?? '';

              List<String> commentImages = [];
              if (comment['images'] != null && comment['images'] is List) {
                for (var img in comment['images']) {
                  if (img is Map && img['originals'] != null && img['originals']['url'] != null) {
                    commentImages.add(img['originals']['url']);
                  }
                }
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () {
                      if (authorUsername.isNotEmpty) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => UserDetailPage(user: {'username': authorUsername}),
                          ),
                        );
                      }
                    },
                    child: CircleAvatar(
                      backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
                      child: avatar.isEmpty ? const Icon(Icons.person) : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () {
                            if (authorUsername.isNotEmpty) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => UserDetailPage(user: {'username': authorUsername}),
                                ),
                              );
                            }
                          },
                          child: Text(
                            userName,
                            style: const TextStyle(fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(text),
                        if (commentImages.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: commentImages.map((imgUrl) {
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: imgUrl,
                                  width: 200,
                                  fit: BoxFit.contain,
                                  placeholder: (context, url) => const SizedBox(
                                    width: 200,
                                    height: 200,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ]
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _buildStat(IconData icon, dynamic count) {
    String label = count.toString();
    if (count is int) {
      if (count >= 1000000) {
        label = '${(count / 1000000).toStringAsFixed(1)}M';
      } else if (count >= 1000) {
        label = '${(count / 1000).toStringAsFixed(1)}K';
      }
    }
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.grey)),
      ],
    );
  }
}
