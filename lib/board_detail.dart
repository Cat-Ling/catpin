import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'pinterest_client.dart';
import 'pin_detail.dart';

class BoardDetailPage extends StatefulWidget {
  final Map<String, dynamic> board;

  const BoardDetailPage({super.key, required this.board});

  @override
  State<BoardDetailPage> createState() => _BoardDetailPageState();
}

class _BoardDetailPageState extends State<BoardDetailPage> {
  final PinterestClient _client = PinterestClient();
  final ScrollController _scrollController = ScrollController();
  
  List<Map<String, dynamic>> _pins = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _bookmark;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetchPins();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && !_isLoadingMore && _bookmark != null && _bookmark!.isNotEmpty) {
        _loadMore();
      }
    }
  }

  Future<void> _fetchPins() async {
    final boardId = widget.board['id']?.toString();
    final url = widget.board['url'] ?? '';
    
    Map<String, dynamic> response;
    
    if (boardId != null && boardId.isNotEmpty) {
      response = await _client.getBoardPins(boardId: boardId);
    } else if (url.isNotEmpty) {
      final parts = url.split('/').where((s) => s.isNotEmpty).toList();
      if (parts.length >= 2) {
        final username = parts[parts.length - 2];
        final slug = parts[parts.length - 1];
        response = await _client.getBoardPins(username: username, slug: slug);
      } else {
        response = {'results': [], 'bookmark': null};
      }
    } else {
      response = {'results': [], 'bookmark': null};
    }

    setState(() {
      _pins = response['results'];
      _bookmark = response['bookmark'];
      _isLoading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || _bookmark == null) return;
    
    setState(() {
      _isLoadingMore = true;
    });

    final boardId = widget.board['id']?.toString();
    final url = widget.board['url'] ?? '';
    Map<String, dynamic> response;

    if (boardId != null && boardId.isNotEmpty) {
      response = await _client.getBoardPins(boardId: boardId, bookmark: _bookmark);
    } else {
      final parts = url.split('/').where((s) => s.isNotEmpty).toList();
      final username = parts[parts.length - 2];
      final slug = parts[parts.length - 1];
      response = await _client.getBoardPins(username: username, slug: slug, bookmark: _bookmark);
    }
    
    setState(() {
      _pins.addAll(response['results']);
      _bookmark = response['bookmark'];
      _isLoadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.board['name'] ?? widget.board['board_title'] ?? 'Board'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchPins,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: MasonryGridView.count(
                  controller: _scrollController,
                  crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  itemCount: _pins.length + (_bookmark != null ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _pins.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final pin = _pins[index];
                    final imageUrl = _client.extractImage(pin['images']);
                    if (imageUrl.isEmpty) return const SizedBox.shrink();

                    return Card(
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PinDetailPage(pin: pin),
                            ),
                          );
                        },
                        child: CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => AspectRatio(
                            aspectRatio: (pin['images']?['orig']?['width'] ?? 1) / (pin['images']?['orig']?['height'] ?? 1),
                            child: Container(color: Colors.white10),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }
}
