import 'dart:convert';
import 'package:dio/dio.dart';

class PinterestClient {
  final Dio dio = Dio(BaseOptions(
    baseUrl: 'https://www.pinterest.com',
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',
    },
  ));

  String? _csrfToken;
  String? _appVersion;

  Future<void> fetchCsrfToken() async {
    try {
      final response = await dio.get('/');
      final cookies = response.headers['set-cookie'];
      if (cookies != null) {
        for (var cookie in cookies) {
          if (cookie.contains('csrftoken=')) {
            _csrfToken = cookie.split('csrftoken=')[1].split(';')[0];
            break;
          }
        }
      }
      final html = response.data.toString();
      final idx = html.indexOf('"app_version":"');
      if (idx != -1) {
        final start = idx + 15;
        final end = html.indexOf('"', start);
        if (end != -1) {
          _appVersion = html.substring(start, end);
        }
      }
    } catch (e) {
      print('Error fetching CSRF: $e');
    }
  }

  Future<dynamic> callResource(String resourceName, String action, Map<String, dynamic> options, String sourceUrl) async {
    if (_csrfToken == null || _appVersion == null) {
      await fetchCsrfToken();
    }
    
    final dataObj = {
      "options": options,
      "context": {},
    };

    final params = {
      "data": jsonEncode(dataObj),
      if (sourceUrl.isNotEmpty) "source_url": sourceUrl,
    };

    final headers = {
      "Accept": "application/json, text/javascript, */*, q=0.01",
      "X-Requested-With": "XMLHttpRequest",
      "Referer": "https://www.pinterest.com/",
      "X-Pinterest-AppState": "active",
      if (_appVersion != null) "X-App-Version": _appVersion!,
      if (_csrfToken != null) "X-CSRFToken": _csrfToken!,
      if (_csrfToken != null) "Cookie": "csrftoken=$_csrfToken",
      if (sourceUrl.isNotEmpty) "X-Pinterest-Source-Url": sourceUrl,
    };

    String handler = "";
    switch (resourceName) {
      case "BaseSearchResource":
        handler = "www/search/[scope].js";
        break;
      case "PinResource":
        handler = "www/pin/[id].js";
        break;
      case "UserResource":
        handler = "www/user/[username].js";
        break;
      case "BoardsFeedResource":
        handler = "www/user/[username].js";
        break;
      case "BoardResource":
        handler = "www/board/[owner]/[slug].js";
        break;
      case "BoardFeedResource":
        handler = "www/board/[owner]/[slug].js";
        break;
      case "UnifiedCommentsResource":
        handler = "www/pin/[id].js";
        break;
    }
    if (handler.isNotEmpty) headers["X-Pinterest-PWS-Handler"] = handler;

    final response = await dio.get('/resource/$resourceName/$action/', queryParameters: params, options: Options(headers: headers));
    return response.data;
  }

  Future<Map<String, dynamic>> search(String query, {String scope = 'pins', String? bookmark}) async {
    try {
      final options = {
        'query': query,
        'scope': scope,
        'no_fetch_context_on_resource': false,
      };
      if (bookmark != null && bookmark.isNotEmpty) {
        options['bookmarks'] = [bookmark];
      }

      final res = await callResource('BaseSearchResource', 'get', options, '/search/$scope/?q=${Uri.encodeComponent(query)}');

      final data = res['resource_response']['data'];
      final results = (data['results'] as List).cast<Map<String, dynamic>>();
      final nextBookmark = res['resource_response']['bookmark'] as String?;

      return {
        'results': results,
        'bookmark': nextBookmark,
      };
    } catch (e) {
      print('Search error: $e');
      return {'results': [], 'bookmark': null};
    }
  }

  Map<String, dynamic> extractStats(Map<String, dynamic> pin) {
    final stats = <String, dynamic>{
      'saves': 0,
      'comments': 0,
      'likes': 0,
      'repins': 0,
    };

    // Check various common field names for stats
    final agg = pin['aggregated_pin_data'] ?? pin['aggregatedPinData'];
    if (agg != null) {
      final s = agg['aggregated_stats'] ?? agg['aggregatedStats'] ?? agg['stats'] ?? agg;
      stats['saves'] = s['saves'] ?? s['save_count'] ?? stats['saves'];
      stats['comments'] = s['comments'] ?? s['comment_count'] ?? stats['comments'];
    }

    if (pin['comment_count'] != null && (pin['comment_count'] as int) > (stats['comments'] as int)) {
      stats['comments'] = pin['comment_count'];
    }

    if (pin['repin_count'] != null) {
      stats['repins'] = pin['repin_count'];
    } else if (pin['repinCount'] != null) {
      stats['repins'] = pin['repinCount'];
    }

    final reactions = pin['reaction_counts'] ?? pin['reactionCounts'];
    if (reactions is Map) {
      if (reactions.containsKey('1')) {
        stats['likes'] = reactions['1'];
      } else if (reactions.containsKey(1)) {
        stats['likes'] = reactions[1];
      }
    }

    return stats;
  }

  String extractImage(Map<String, dynamic>? images) {
    if (images == null) return '';
    if (images.containsKey('orig')) {
      return images['orig']['url'] ?? '';
    }
    final keys = images.keys.where((k) => k.contains('x')).toList();
    if (keys.isNotEmpty) {
      keys.sort((a, b) {
        final aVal = int.tryParse(a.split('x')[0]) ?? 0;
        final bVal = int.tryParse(b.split('x')[0]) ?? 0;
        return bVal.compareTo(aVal);
      });
      return images[keys.first]['url'] ?? '';
    }
    return '';
  }

  bool checkIsVideo(Map<String, dynamic> pin) {
    if (pin['videos'] != null || pin['video_list'] != null) return true;
    final story = pin['story_pin_data'];
    if (story != null && story['pages'] != null && (story['pages'] as List).isNotEmpty) {
      for (var page in story['pages']) {
        if (page['blocks'] != null) {
          for (var block in page['blocks']) {
            if (block['type'] == 'video' || block['video'] != null) return true;
          }
        }
      }
    }
    return false;
  }

  Map<String, dynamic>? extractVideo(Map<String, dynamic> pin) {
    // Check for story pins first
    final story = pin['story_pin_data'];
    if (story != null && story['pages'] != null) {
      for (var page in story['pages']) {
        if (page['blocks'] != null) {
          for (var block in page['blocks']) {
            if (block['video'] != null && block['video']['video_list'] != null) {
              return _processVideoList(block['video']['video_list']);
            }
          }
        }
      }
    }

    // Check for normal videos
    final videos = pin['videos'] ?? pin['video_list'];
    if (videos != null) {
      if (videos['video_list'] != null) {
        return _processVideoList(videos['video_list'].cast<String, dynamic>());
      } else if (videos is Map) {
        return _processVideoList(videos.cast<String, dynamic>());
      }
    }

    // Try finding video URLs in strings (heuristic)
    if (pin.containsKey('video_signature')) {
      // Logic for signature if needed
    }

    return null;
  }

  Map<String, dynamic>? _processVideoList(Map<String, dynamic> videoList) {
    final Map<String, dynamic> variants = videoList is Map ? videoList.cast<String, dynamic>() : {};
    
    // Pinterest keys: V_HLSV4 (HLS), V_720W (MP4), V_360W, etc.
    // Prefer HLS for adaptive bitrate and correct audio track support
    final keys = ['V_HLSV4', 'V_HLSV3_MOBILE', 'V_720W', 'V_360W', 'V_240W'];
    
    for (var key in keys) {
      if (variants.containsKey(key)) {
        final v = variants[key];
        if (v is Map && v['url'] != null) return v.cast<String, dynamic>();
      }
    }
    
    // Fallback to first available map with a url
    for (var v in variants.values) {
      if (v is Map && v['url'] != null) return v.cast<String, dynamic>();
    }
    
    return null;
  }

  Future<Map<String, dynamic>?> getPin(String pinId) async {
    try {
      final res = await callResource('PinResource', 'get', {
        'field_set_key': 'detailed',
        'id': pinId,
      }, '/pin/$pinId/');
      return res['resource_response']['data'];
    } catch (e) {
      print('GetPin error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> getBoardPins({String? username, String? slug, String? boardId, String? bookmark}) async {
    try {
      String? targetId = boardId;
      String sourceUrl = '';
      
      if (targetId == null && username != null && slug != null) {
        sourceUrl = '/$username/$slug/';
        final boardRes = await callResource('BoardResource', 'get', {
          'username': username,
          'slug': slug,
          'field_set_key': 'detailed',
        }, sourceUrl);
        targetId = boardRes['resource_response']?['data']?['id'];
      }

      if (targetId == null) {
        return {'results': [], 'bookmark': null};
      }

      final options = {
        'board_id': targetId,
        'field_set_key': 'react_grid_pin',
        'add_vase': true,
        'filter_section_pins': true,
        'is_react': true,
        'prepend': false,
        'page_size': 25,
        'redux_normalize_feed': true,
        'layout': 'default',
        'sort': 'default',
      };
      
      if (bookmark != null && bookmark.isNotEmpty) {
        options['bookmarks'] = [bookmark];
      }

      final res = await callResource('BoardFeedResource', 'get', options, sourceUrl);
      
      final data = res['resource_response']?['data'];
      List<Map<String, dynamic>> results = [];
      
      if (data is List) {
        results = data.cast<Map<String, dynamic>>();
      } else if (data is Map) {
        if (data.containsKey('results')) {
          results = (data['results'] as List).cast<Map<String, dynamic>>();
        } else {
          // Sometimes data itself is the map of results if redux_normalize_feed is used differently
        }
      }
      
      final nextBookmark = res['resource_response']?['bookmark'] as String?;
      return {
        'results': results,
        'bookmark': nextBookmark,
      };
    } catch (e) {
      print('BoardPins error: $e');
      return {'results': [], 'bookmark': null};
    }
  }

  Future<Map<String, dynamic>> getComments(String pinId, {String? bookmark}) async {
    try {
      final pin = await getPin(pinId);
      final aggregatedPinId = pin?['aggregated_pin_data']?['id'] ?? pinId;
      
      final options = {
        'aggregated_pin_id': aggregatedPinId,
        'page_size': 10,
        'redux_normalize_feed': true,
      };
      if (bookmark != null && bookmark.isNotEmpty) {
        options['bookmarks'] = [bookmark];
      }

      final res = await callResource('UnifiedCommentsResource', 'get', options, '/pin/$pinId/');
      
      final data = res['resource_response']['data'];
      List<Map<String, dynamic>> results = [];
      if (data is List) {
        results = data.cast<Map<String, dynamic>>();
      } else if (data is Map && data.containsKey('results')) {
        results = (data['results'] as List).cast<Map<String, dynamic>>();
      }

      final nextBookmark = res['resource_response']['bookmark'] as String?;
      return {
        'results': results,
        'bookmark': nextBookmark,
      };
    } catch (e) {
      print('GetComments error: $e');
      return {'results': [], 'bookmark': null};
    }
  }

  Future<Map<String, dynamic>?> getUser(String username) async {
    try {
      final res = await callResource('UserResource', 'get', {
        'username': username,
        'field_set_key': 'profile',
      }, '/$username/');
      return res['resource_response']['data'];
    } catch (e) {
      print('GetUser error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> getBoards(String username, {String? bookmark}) async {
    try {
      final options = {
        'username': username,
        'field_set_key': 'profile_grid_item',
        'page_size': 25,
      };
      if (bookmark != null && bookmark.isNotEmpty) {
        options['bookmarks'] = [bookmark];
      }

      final res = await callResource('BoardsFeedResource', 'get', options, '/$username/');
      
      final data = res['resource_response']?['data'];
      List<Map<String, dynamic>> results = [];
      if (data is List) {
        results = data.cast<Map<String, dynamic>>();
      } else if (data is Map && data.containsKey('results')) {
        results = (data['results'] as List).cast<Map<String, dynamic>>();
      }
      
      final nextBookmark = res['resource_response']?['bookmark'] as String?;
      return {
        'results': results,
        'bookmark': nextBookmark,
      };
    } catch (e) {
      print('GetBoards error: $e');
      return {'results': [], 'bookmark': null};
    }
  }
}
