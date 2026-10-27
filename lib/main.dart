import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IPTV Player',
      theme: ThemeData.dark(),
      home: const HomePage(),
    );
  }
}

// ---------- Модель канала ----------
class Channel {
  final String name;
  final String group;
  final String url;

  Channel({required this.name, required this.group, required this.url});
}

// ---------- Главный экран ----------
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _urlController = TextEditingController();
  List<Channel> _allChannels = [];
  List<String> _groups = [];
  String _selectedGroup = 'Все';
  bool _loading = false;
  String? _error;

  // Простейший парсер M3U
  List<Channel> _parseM3u(String content) {
    final List<Channel> result = [];
    final List<String> lines = content.split('\n');

    String? currentName;
    String? currentGroup;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF:')) {
        // group-title
        final groupMatch = RegExp(r'group-title="([^"]*)"').firstMatch(line);
        currentGroup = groupMatch != null ? groupMatch.group(1) : 'Без группы';

        // Имя после последней запятой
        final commaIndex = line.lastIndexOf(',');
        if (commaIndex >= 0 && commaIndex < line.length - 1) {
          currentName = line.substring(commaIndex + 1).trim();
        } else {
          currentName = 'Без имени';
        }
      } else if (!line.startsWith('#')) {
        // Это URL
        if (currentName != null) {
          result.add(Channel(
            name: currentName,
            group: (currentGroup == null || currentGroup.isEmpty) ? 'Без группы' : currentGroup,
            url: line,
          ));
          currentName = null;
          currentGroup = null;
        }
      }
    }
    return result;
  }

  Future<void> _loadPlaylist() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Введите URL плейлиста');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final channels = _parseM3u(response.body);
      if (channels.isEmpty) {
        throw Exception('Каналы не найдены в плейлисте');
      }

      final groups = <String>{'Все'};
      for (final c in channels) {
        groups.add(c.group);
      }

      setState(() {
        _allChannels = channels;
        _groups = groups.toList();
        _selectedGroup = 'Все';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Ошибка: $e';
      });
    }
  }

  List<Channel> get _filteredChannels {
    if (_selectedGroup == 'Все') return _allChannels;
    return _allChannels.where((c) => c.group == _selectedGroup).toList();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('IPTV Player')),
      body: Column(
        children: [
          // Панель ввода URL
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      hintText: 'URL плейлиста (m3u/m3u8)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _loading ? null : _loadPlaylist,
                  child: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Загрузить'),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          // Список групп и каналов
          Expanded(
            child: Row(
              children: [
                // Группы
                Container(
                  width: 160,
                  color: Colors.black26,
                  child: ListView.builder(
                    itemCount: _groups.length,
                    itemBuilder: (context, index) {
                      final group = _groups[index];
                      final selected = group == _selectedGroup;
                      return ListTile(
                        dense: true,
                        selected: selected,
                        title: Text(
                          group,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => setState(() => _selectedGroup = group),
                      );
                    },
                  ),
                ),
                // Каналы
                Expanded(
                  child: _filteredChannels.isEmpty
                      ? const Center(child: Text('Список пуст'))
                      : ListView.builder(
                          itemCount: _filteredChannels.length,
                          itemBuilder: (context, index) {
                            final channel = _filteredChannels[index];
                            return ListTile(
                              leading: const Icon(Icons.live_tv),
                              title: Text(channel.name),
                              subtitle: Text(
                                channel.group,
                                style: const TextStyle(fontSize: 11),
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PlayerPage(channel: channel),
                                  ),
                                );
                              },
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

// ---------- Экран плеера ----------
class PlayerPage extends StatefulWidget {
  final Channel channel;

  const PlayerPage({super.key, required this.channel});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.channel.url),
      );
      await controller.initialize();
      await controller.play();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initialized = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось воспроизвести: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.channel.name)),
      body: Center(
        child: _error != null
            ? Text(_error!, style: const TextStyle(color: Colors.red))
            : !_initialized
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: VideoPlayer(_controller!),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: Icon(
                              _controller!.value.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                            ),
                            onPressed: () {
                              setState(() {
                                if (_controller!.value.isPlaying) {
                                  _controller!.pause();
                                } else {
                                  _controller!.play();
                                }
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
      ),
    );
  }
}
