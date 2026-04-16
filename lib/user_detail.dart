import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'pinterest_client.dart';
import 'board_detail.dart';

class UserDetailPage extends StatefulWidget {
  final Map<String, dynamic> user;

  const UserDetailPage({super.key, required this.user});

  @override
  State<UserDetailPage> createState() => _UserDetailPageState();
}

class _UserDetailPageState extends State<UserDetailPage> {
  final PinterestClient _client = PinterestClient();
  final ScrollController _scrollController = ScrollController();
  
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _boards = [];
  bool _isLoadingProfile = true;
  bool _isLoadingBoards = true;
  bool _isLoadingMore = false;
  String? _bookmark;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetchData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingBoards && !_isLoadingMore && _bookmark != null && _bookmark!.isNotEmpty) {
        _loadMore();
      }
    }
  }

  Future<void> _fetchData() async {
    final username = widget.user['username'];
    if (username == null) return;
    
    // 1. Fetch Profile Metadata
    final profile = await _client.getUser(username);
    if (mounted) {
      setState(() {
        _profile = profile;
        _isLoadingProfile = false;
      });
    }

    // 2. Fetch Boards
    final response = await _client.getBoards(username);
    if (mounted) {
      setState(() {
        _boards = response['results'];
        _bookmark = response['bookmark'];
        _isLoadingBoards = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final username = widget.user['username'];
    if (username == null || _isLoadingMore || _bookmark == null) return;
    
    setState(() {
      _isLoadingMore = true;
    });

    final response = await _client.getBoards(username, bookmark: _bookmark);
    
    if (mounted) {
      setState(() {
        _boards.addAll(response['results']);
        _bookmark = response['bookmark'];
        _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentProfile = _profile ?? widget.user;
    final name = currentProfile['full_name'] ?? currentProfile['username'] ?? 'User';
    final username = currentProfile['username'] ?? '';
    final avatar = currentProfile['image_xlarge_url'] ?? currentProfile['image_medium_url'] ?? '';
    final about = currentProfile['about'] ?? '';
    final followers = currentProfile['follower_count'] ?? 0;
    final following = currentProfile['following_count'] ?? 0;

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
                    child: avatar.isEmpty ? const Icon(Icons.person, size: 60) : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    name,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '@$username',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey),
                  ),
                  if (about.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      about,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildCount(context, 'Followers', followers),
                      const SizedBox(width: 32),
                      _buildCount(context, 'Following', following),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(
                'Boards',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          if (_isLoadingBoards && _boards.isEmpty)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else if (_boards.isEmpty)
            const SliverFillRemaining(child: Center(child: Text('No boards found.')))
          else
            SliverPadding(
              padding: const EdgeInsets.all(8.0),
              sliver: SliverMasonryGrid.count(
                crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childCount: _boards.length + (_bookmark != null ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _boards.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final board = _boards[index];
                  final imageUrl = board['image_cover_url'] ?? _client.extractImage(board['images']);
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => BoardDetailPage(board: board),
                          ),
                        );
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (imageUrl.isNotEmpty)
                            CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(height: 100, color: Colors.white10),
                            ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                              board['name'] ?? board['board_title'] ?? 'Untitled',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCount(BuildContext context, String label, dynamic count) {
    String countStr = count.toString();
    if (count is int) {
      if (count >= 1000000) {
        countStr = '${(count / 1000000).toStringAsFixed(1)}M';
      } else if (count >= 1000) {
        countStr = '${(count / 1000).toStringAsFixed(1)}K';
      }
    }
    return Column(
      children: [
        Text(countStr, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.grey)),
      ],
    );
  }
}
