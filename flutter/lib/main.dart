import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const VkAnalyticsApp());
}

class VkAnalyticsApp extends StatelessWidget {
  const VkAnalyticsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VK Analytics',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class ApiClient {
  ApiClient(this.baseUrl);

  final String baseUrl;

  Uri _u(String path) => Uri.parse('$baseUrl$path');

  Future<Map<String, dynamic>> createProject(String name) async {
    final r = await http.post(
      _u('/projects'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name}),
    );
    final data = jsonDecode(r.body);
    if (r.statusCode >= 300) throw Exception(data.toString());
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createRun(
      int projectId,
      String groupId,
      int count, {
        String? startDate,
        String? endDate,
        int? minLikes,
        int? minComments,
        int? minReposts,
        int? minViews,
        String? sortBy,
        String? sortOrder,
      }) async {
    final payload = <String, dynamic>{
      'group_id': groupId,
      'count': count,
      if (startDate != null && startDate.isNotEmpty) 'start_date': startDate,
      if (endDate != null && endDate.isNotEmpty) 'end_date': endDate,
      if (minLikes != null) 'min_likes': minLikes,
      if (minComments != null) 'min_comments': minComments,
      if (minReposts != null) 'min_reposts': minReposts,
      if (minViews != null) 'min_views': minViews,
      if (sortBy != null && sortBy.isNotEmpty) 'sort_by': sortBy,
      if (sortOrder != null && sortOrder.isNotEmpty) 'sort_order': sortOrder,
    };

    final r = await http.post(
      _u('/projects/$projectId/runs'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    final data = jsonDecode(r.body);
    if (r.statusCode >= 300) throw Exception(data.toString());
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getRun(int runId) async {
    final r = await http.get(_u('/runs/$runId'));
    final data = jsonDecode(r.body);
    if (r.statusCode >= 300) throw Exception(data.toString());
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getReport(int runId) async {
    final r = await http.get(_u('/runs/$runId/report'));
    final data = jsonDecode(r.body);
    if (r.statusCode >= 300) throw Exception(data.toString());
    return data as Map<String, dynamic>;
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Windows desktop: http://127.0.0.1:8000
  // Android emulator: http://10.0.2.2:8000 (host machine localhost)
  final _apiBaseController = TextEditingController(text: 'http://127.0.0.1:8000');

  final _projectName = TextEditingController(text: 'Анализ ВолгГТУ');
  final _projectId = TextEditingController(text: '1');

  // теперь groupId — строка
  final _groupId = TextEditingController(text: '1');

  final _count = TextEditingController(text: '50');

  final _startDate = TextEditingController(); // YYYY-MM-DD
  final _endDate = TextEditingController(); // YYYY-MM-DD
  final _minLikes = TextEditingController();
  final _minComments = TextEditingController();
  final _minReposts = TextEditingController();
  final _minViews = TextEditingController();
  String _sortBy = '';
  String _sortOrder = 'desc';

  String _statusText = 'Готово';
  bool _busy = false;

  int? _currentRunId;
  Timer? _timer;
  Map<String, dynamic>? _reportWrapper;

  ApiClient get _api => ApiClient(_apiBaseController.text.trim());

  @override
  void dispose() {
    _timer?.cancel();
    _apiBaseController.dispose();
    _projectName.dispose();
    _projectId.dispose();
    _groupId.dispose();
    _count.dispose();
    _startDate.dispose();
    _endDate.dispose();
    _minLikes.dispose();
    _minComments.dispose();
    _minReposts.dispose();
    _minViews.dispose();
    super.dispose();
  }

  int? _toInt(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showTextDialog(String title, String text) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: SelectableText(text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  void _showPhotosDialog(String postId, List<String> urls) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Фото поста $postId'),
        content: SizedBox(
          width: 460,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: urls.length,
            separatorBuilder: (_, __) => const Divider(height: 12),
            itemBuilder: (_, i) {
              final u = urls[i];
              return ListTile(
                title: Text('Фото ${i + 1}'),
                subtitle: Text(
                  u,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => _openUrl(u),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Widget _thumb(String url, {double size = 56}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image, size: 18),
        ),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            width: size,
            height: size,
            color: Colors.grey.shade100,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
      ),
    );
  }

  Future<void> _createProject() async {
    setState(() {
      _busy = true;
      _statusText = 'Создание проекта...';
    });
    try {
      final p = await _api.createProject(_projectName.text.trim());
      setState(() {
        _projectId.text = p['id'].toString();
        _statusText = 'Проект создан: id=${p['id']}';
      });
    } catch (e) {
      setState(() => _statusText = 'Ошибка: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _startRun() async {
    final projectId = int.tryParse(_projectId.text.trim());
    final groupId = _groupId.text.trim(); // <-- строка
    final count = int.tryParse(_count.text.trim());

    // Проверяем только "не пусто" для groupId
    if (projectId == null || groupId.isEmpty || count == null) {
      setState(() => _statusText = 'Заполни projectId/groupId/count');
      return;
    }

    setState(() {
      _busy = true;
      _reportWrapper = null;
      _statusText = 'Запуск run...';
    });

    try {
      final run = await _api.createRun(
        projectId,
        groupId, // <-- строка уходит на backend
        count,
        startDate: _startDate.text.trim(),
        endDate: _endDate.text.trim(),
        minLikes: _toInt(_minLikes.text),
        minComments: _toInt(_minComments.text),
        minReposts: _toInt(_minReposts.text),
        minViews: _toInt(_minViews.text),
        sortBy: _sortBy.isEmpty ? null : _sortBy,
        sortOrder: _sortOrder,
      );

      final runId = run['id'] as int;
      setState(() {
        _currentRunId = runId;
        _statusText = 'Run создан: id=$runId, status=${run['status']}';
      });

      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _pollRun());
      await _pollRun();
    } catch (e) {
      setState(() => _statusText = 'Ошибка запуска: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _pollRun() async {
    final runId = _currentRunId;
    if (runId == null) return;

    try {
      final st = await _api.getRun(runId);
      final status = (st['status'] ?? '').toString();
      final err = st['error_message'];

      setState(() {
        _statusText = 'Run $runId: $status${err != null ? '\n$err' : ''}';
      });

      if (status == 'done') {
        _timer?.cancel();
        final rep = await _api.getReport(runId);
        setState(() => _reportWrapper = rep);
      }

      if (status == 'error') {
        _timer?.cancel();
      }
    } catch (e) {
      setState(() => _statusText = 'Ошибка статуса: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _reportWrapper?['report'] ?? _reportWrapper;
    final basic = report is Map<String, dynamic> ? report['basic'] : null;
    final predict = report is Map<String, dynamic> ? report['predict'] : null;

    return Scaffold(
      appBar: AppBar(title: const Text('VK Analytics')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _card(
            title: 'Настройки API',
            child: Column(
              children: [
                TextField(
                  controller: _apiBaseController,
                  decoration: const InputDecoration(
                    labelText: 'API Base URL',
                    hintText: 'http://127.0.0.1:8000',
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Android эмулятор: http://10.0.2.2:8000  |  Windows: http://127.0.0.1:8000',
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
          _card(
            title: 'Проект',
            child: Column(
              children: [
                TextField(
                  controller: _projectName,
                  decoration: const InputDecoration(labelText: 'Название проекта'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _projectId,
                        decoration: const InputDecoration(labelText: 'Project ID'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _busy ? null : _createProject,
                      child: const Text('Создать'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _card(
            title: 'Запуск анализа',
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _groupId,
                        decoration: const InputDecoration(
                          labelText: 'Логин группы VK',
                          hintText: 'Напр.: 1, -1, club123, feivt, https://vk.com/feivt',
                        ),
                        keyboardType: TextInputType.text, // <-- важно [web:773]
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _count,
                        decoration: const InputDecoration(labelText: 'Count'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ExpansionTile(
                  title: const Text('Фильтры (опционально)'),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _startDate,
                            decoration: const InputDecoration(labelText: 'Start date (YYYY-MM-DD)'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _endDate,
                            decoration: const InputDecoration(labelText: 'End date (YYYY-MM-DD)'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _minLikes,
                            decoration: const InputDecoration(labelText: 'Min likes'),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _minComments,
                            decoration: const InputDecoration(labelText: 'Min comments'),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _minReposts,
                            decoration: const InputDecoration(labelText: 'Min reposts'),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _minViews,
                            decoration: const InputDecoration(labelText: 'Min views'),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _sortBy.isEmpty ? null : _sortBy,
                            items: const [
                              DropdownMenuItem(value: 'date', child: Text('sort_by: date')),
                              DropdownMenuItem(value: 'likes', child: Text('sort_by: likes')),
                              DropdownMenuItem(value: 'views', child: Text('sort_by: views')),
                              DropdownMenuItem(value: 'reposts', child: Text('sort_by: reposts')),
                              DropdownMenuItem(value: 'comments', child: Text('sort_by: comments')),
                            ],
                            onChanged: (v) => setState(() => _sortBy = v ?? ''),
                            decoration: const InputDecoration(labelText: 'Sort by'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _sortOrder,
                            items: const [
                              DropdownMenuItem(value: 'desc', child: Text('desc')),
                              DropdownMenuItem(value: 'asc', child: Text('asc')),
                            ],
                            onChanged: (v) => setState(() => _sortOrder = v ?? 'desc'),
                            decoration: const InputDecoration(labelText: 'Sort order'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: _busy ? null : _startRun,
                      child: const Text('Запустить'),
                    ),
                    const SizedBox(width: 12),
                    if (_currentRunId != null) Text('run_id=$_currentRunId'),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_statusText),
              ],
            ),
          ),
          if (basic is Map<String, dynamic>) _buildBasicCard(basic),
          if (basic is Map<String, dynamic>) _buildTopPostsCard(basic),
          if (predict is Map<String, dynamic>) _buildPredictCard(predict),
        ],
      ),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildBasicCard(Map<String, dynamic> basic) {
    Widget metric(String name, dynamic value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(name)),
          Text(value?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );

    return _card(
      title: 'Анализ постов',
      child: Column(
        children: [
          metric('dataset_id', basic['dataset_id']),
          metric('Общее количество постов', basic['total_posts']),
          metric('Общее количество лайков', basic['total_likes']),
          metric('Общее количество комментариев', basic['total_comments']),
          metric('Общее количество репостов', basic['total_reposts']),
          metric('Общее количество просмотров', basic['total_views']),
          const Divider(),
          metric('Среднее количество лайков на пост', basic['avg_likes']),
          metric('Среднее количество комментариев на пост', basic['avg_comments']),
          metric('Среднее количество репостов на пост', basic['avg_reposts']),
          metric('Среднее количество просмотров на пост', basic['avg_views']),
        ],
      ),
    );
  }

  Widget _buildTopPostsCard(Map<String, dynamic> basic) {
    final posts = (basic['top_posts_by_likes'] as List?) ?? const [];

    return _card(
      title: 'Топ постов по лайкам (тап по тексту открывает полный текст)',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 16,
          columns: const [
            DataColumn(label: Text('ID')),
            DataColumn(label: Text('Дата')),
            DataColumn(label: Text('Лайки')),
            DataColumn(label: Text('Комменты')),
            DataColumn(label: Text('Репосты')),
            DataColumn(label: Text('Просмотры')),
            DataColumn(label: Text('Текст')),
            DataColumn(label: Text('Фото')),
          ],
          rows: posts.take(20).map((p) {
            final m = (p as Map).cast<String, dynamic>();

            final id = m['id'];
            final date = (m['date'] ?? '').toString();
            final likes = m['likes_count'];
            final comments = m['comments_count'];
            final reposts = m['reposts_count'];
            final views = m['views_count'];

            final text = (m['text'] ?? '').toString();
            final oneLine = text.replaceAll('\n', ' ');
            final short = oneLine.length > 90 ? '${oneLine.substring(0, 90)}…' : oneLine;

            final photosRaw = (m['url_photos'] as List?) ?? const [];
            final photos = photosRaw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();

            return DataRow(cells: [
              DataCell(Text('$id')),
              DataCell(Text(date)),
              DataCell(Text('$likes')),
              DataCell(Text('$comments')),
              DataCell(Text('$reposts')),
              DataCell(Text('$views')),
              DataCell(
                SizedBox(
                  width: 420,
                  child: InkWell(
                    onTap: () => _showTextDialog('Пост $id', text),
                    child: Text(short, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
              DataCell(
                photos.isEmpty
                    ? const Text('—')
                    : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    InkWell(onTap: () => _openUrl(photos[0]), child: _thumb(photos[0])),
                    if (photos.length > 1) InkWell(onTap: () => _openUrl(photos[1]), child: _thumb(photos[1])),
                    if (photos.length > 2)
                      TextButton(
                        onPressed: () => _showPhotosDialog(id.toString(), photos),
                        child: Text('Ещё ${photos.length - 2}'),
                      ),
                  ],
                ),
              ),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPredictCard(Map<String, dynamic> predict) {
    final items = (predict['items'] as List?) ?? const [];

    return _card(
      title: 'ML‑скоринг',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 16,
          columns: const [
            DataColumn(label: Text('ID')),
            DataColumn(label: Text('Дата')),
            DataColumn(label: Text('Лайки')),
            DataColumn(label: Text('Комменты')),
            DataColumn(label: Text('Репосты')),
            DataColumn(label: Text('Просмотры')),
            DataColumn(label: Text('Score')),
            DataColumn(label: Text('Является популярным?')),
            DataColumn(label: Text('Текст')),
            DataColumn(label: Text('Фото')),
          ],
          rows: items.take(50).map((it) {
            final m = (it as Map).cast<String, dynamic>();
            final isTop = (m['predicted_top'] == true);

            final id = m['id'];
            final date = (m['date'] ?? '').toString();

            final text = (m['text'] ?? '').toString();
            final oneLine = text.replaceAll('\n', ' ');
            final short = oneLine.isEmpty ? '—' : (oneLine.length > 90 ? '${oneLine.substring(0, 90)}…' : oneLine);

            final photosRaw = (m['url_photos'] as List?) ?? const [];
            final photos = photosRaw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();

            return DataRow(cells: [
              DataCell(Text('$id')),
              DataCell(Text(date)),
              DataCell(Text('${m['likes_count']}')),
              DataCell(Text('${m['comments_count']}')),
              DataCell(Text('${m['reposts_count']}')),
              DataCell(Text('${m['views_count']}')),
              DataCell(Text('${m['score_top']}')),
              DataCell(Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isTop ? Colors.green.shade100 : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(isTop ? 'TOP' : '—'),
              )),
              DataCell(
                SizedBox(
                  width: 420,
                  child: text.isEmpty
                      ? const Text('—')
                      : InkWell(
                    onTap: () => _showTextDialog('Пост $id', text),
                    child: Text(short, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
              DataCell(
                photos.isEmpty
                    ? const Text('—')
                    : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    InkWell(onTap: () => _openUrl(photos[0]), child: _thumb(photos[0])),
                    if (photos.length > 1) InkWell(onTap: () => _openUrl(photos[1]), child: _thumb(photos[1])),
                    if (photos.length > 2)
                      TextButton(
                        onPressed: () => _showPhotosDialog(id.toString(), photos),
                        child: Text('Ещё ${photos.length - 2}'),
                      ),
                  ],
                ),
              ),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}
