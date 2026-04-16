import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'dart:io';
import 'pinterest_client.dart';
import 'pin_detail.dart';
import 'board_detail.dart';
import 'user_detail.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isLinux || Platform.isWindows) {
    fvp.registerWith();
  }
  runApp(const CatpinApp());
}

class CatpinApp extends StatelessWidget {
  const CatpinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Catpin',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE60023),
          secondary: Color(0xFFE60023),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final PinterestClient _client = PinterestClient();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<Map<String, dynamic>> _results = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String _currentScope = 'pins';
  bool _hasSearched = false;
  String? _bookmark;

  final List<Map<String, String>> _scopes = [
    {'id': 'pins', 'label': 'Pins'},
    {'id': 'videos', 'label': 'Videos'},
    {'id': 'boards', 'label': 'Boards'},
    {'id': 'users', 'label': 'Users'},
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && !_isLoadingMore && _bookmark != null && _bookmark!.isNotEmpty) {
        _loadMore();
      }
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) return;
    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _results = [];
      _bookmark = null;
    });
    
    final response = await _client.search(query, scope: _currentScope);
    
    setState(() {
      _results = response['results'];
      _bookmark = response['bookmark'];
      _isLoading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || _bookmark == null) return;
    
    setState(() {
      _isLoadingMore = true;
    });

    final response = await _client.search(_searchController.text, scope: _currentScope, bookmark: _bookmark);
    
    setState(() {
      _results.addAll(response['results']);
      _bookmark = response['bookmark'];
      _isLoadingMore = false;
    });
  }

  void _clearSearch() {
    setState(() {
      _hasSearched = false;
      _results = [];
      _bookmark = null;
      _searchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _hasSearched 
          ? AppBar(
              title: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search...',
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: _clearSearch,
                  ),
                ),
                onSubmitted: _performSearch,
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _scopes.map((scope) {
                      final isSelected = _currentScope == scope['id'];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: ChoiceChip(
                          label: Text(scope['label']!),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _currentScope = scope['id']!;
                              });
                              _performSearch(_searchController.text);
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            )
          : null,
      body: !_hasSearched 
          ? _buildHero()
          : _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildResults(),
    );
  }

  Widget _buildHero() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Binternet',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Color(0xFFE60023),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Your privacy, your search. Search Pinterest without tracking.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search anything...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
              ),
              onSubmitted: _performSearch,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_results.isEmpty && !_isLoading) {
      return const Center(child: Text('No results found.'));
    }

    Widget content;
    if (_currentScope == 'users') {
      content = ListView.builder(
        controller: _scrollController,
        itemCount: _results.length + (_bookmark != null ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _results.length) {
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final user = _results[index];
          final avatar = user['image_medium_url'] ?? '';
          final name = user['full_name'] ?? user['username'] ?? '';
          return ListTile(
            leading: CircleAvatar(
              backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
              child: avatar.isEmpty ? const Icon(Icons.person) : null,
            ),
            title: Text(name),
            subtitle: Text('@${user['username'] ?? ''}'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserDetailPage(user: user),
                ),
              );
            },
          );
        },
      );
    } else if (_currentScope == 'boards') {
      content = MasonryGridView.count(
        controller: _scrollController,
        crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        padding: const EdgeInsets.all(8),
        itemCount: _results.length + (_bookmark != null ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _results.length) {
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final board = _results[index];
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
                children: [
                  if (imageUrl.isNotEmpty)
                    CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      board['name'] ?? board['board_title'] ?? 'Untitled Board',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: MasonryGridView.count(
          controller: _scrollController,
          crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          itemCount: _results.length + (_bookmark != null ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == _results.length) {
              return const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final pin = _results[index];
            final imageUrl = _client.extractImage(pin['images']);
            if (imageUrl.isEmpty) return const SizedBox.shrink();

            dynamic rawTitle = pin['title'] ?? pin['grid_title'];
            String title = '';
            if (rawTitle is String) {
              title = rawTitle;
            } else if (rawTitle is Map) {
              title = rawTitle['text'] ?? rawTitle['format'] ?? '';
            }
            
            final isVideo = pin['videos'] != null || pin['story_pin_data'] != null;
            
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => AspectRatio(
                            aspectRatio: (pin['images']?['orig']?['width'] ?? 1) / (pin['images']?['orig']?['height'] ?? 1),
                            child: Container(color: Colors.white10),
                          ),
                          errorWidget: (context, url, error) => const Icon(Icons.error),
                        ),
                        if (isVideo)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.4),
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(8),
                            child: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
                          ),
                      ],
                    ),
                    if (title.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          title,
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
      );
    }

    return RefreshIndicator(
      onRefresh: () => _performSearch(_searchController.text),
      child: content,
    );
  }
}
