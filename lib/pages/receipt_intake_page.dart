part of '../main.dart';

class IntakeImageSelection {
  final Uint8List bytes;
  final Uint8List? fastScanBytes;
  final String name;
  final String path;
  final DateTime savedAt;
  final bool isTempIntake;

  const IntakeImageSelection({
    required this.bytes,
    this.fastScanBytes,
    required this.name,
    required this.path,
    required this.savedAt,
    required this.isTempIntake,
  });
}

class ReceiptIntakePage extends StatefulWidget {
  const ReceiptIntakePage({super.key});

  @override
  State<ReceiptIntakePage> createState() => _ReceiptIntakePageState();
}

class _ReceiptIntakePageState extends State<ReceiptIntakePage> {
  final List<IntakeImageSelection> _allItems = [];
  String? _selectedPath;
  bool _loading = false;
  String _filter = 'today'; // today | week | all

  @override
  void initState() {
    super.initState();
    _loadSavedItems();
  }

  Future<Directory> _ensureIntakeDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'intake_images'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> _saveIntoIntake({
    required Uint8List bytes,
    required String originalName,
  }) async {
    final dir = await _ensureIntakeDir();
    final ext = p.extension(originalName).toLowerCase();
    final safeExt = (ext == '.jpg' ||
            ext == '.jpeg' ||
            ext == '.png' ||
            ext == '.webp' ||
            ext == '.bmp')
        ? ext
        : '.jpg';
    final fileName = 'intake_${DateTime.now().millisecondsSinceEpoch}$safeExt';
    final path = p.join(dir.path, fileName);
    final out = File(path);
    await out.writeAsBytes(bytes, flush: true);
    return path;
  }

  List<IntakeImageSelection> get _visibleItems {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfWeek = startOfToday.subtract(Duration(days: now.weekday - 1));

    return _allItems.where((item) {
      if (_filter == 'all') return true;
      if (_filter == 'week') return !item.savedAt.isBefore(startOfWeek);
      return !item.savedAt.isBefore(startOfToday);
    }).toList();
  }

  Future<void> _loadSavedItems() async {
    try {
      setState(() => _loading = true);
      final dir = await _ensureIntakeDir();
      final files = dir.listSync().whereType<File>().where((f) {
        final lower = f.path.toLowerCase();
        return lower.endsWith('.jpg') ||
            lower.endsWith('.jpeg') ||
            lower.endsWith('.png') ||
            lower.endsWith('.webp') ||
            lower.endsWith('.bmp');
      }).toList()
        ..sort(
            (a, b) => b.statSync().modified.compareTo(a.statSync().modified));

      final seenPaths = <String>{};
      final loaded = <IntakeImageSelection>[];

      for (final f in files) {
        if (!seenPaths.add(f.path)) continue;
        final bytes = await f.readAsBytes();
        if (bytes.isEmpty) continue;
        final stat = await f.stat();
        loaded.add(
          IntakeImageSelection(
            bytes: bytes,
            fastScanBytes: null,
            name: p.basename(f.path),
            path: f.path,
            savedAt: stat.modified,
            isTempIntake: true,
          ),
        );
      }

      loaded.sort((a, b) => b.savedAt.compareTo(a.savedAt));

      if (!mounted) return;
      setState(() {
        _allItems
          ..clear()
          ..addAll(loaded);
        _selectedPath = loaded.isEmpty ? null : loaded.first.path;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _capture() async {
    try {
      setState(() => _loading = true);
      final photo = await DocumentCaptureService.captureCorrected(
        allowGalleryImport: false,
      );
      if (photo == null) return;
      final bytes = await photo.readAsBytes();
      final savedPath = await _saveIntoIntake(
        bytes: bytes,
        originalName: photo.name,
      );
      if (!mounted) return;
      setState(() {
        _allItems.insert(
          0,
          IntakeImageSelection(
            bytes: bytes,
            fastScanBytes: null,
            name: p.basename(savedPath),
            path: savedPath,
            savedAt: DateTime.now(),
            isTempIntake: true,
          ),
        );
        _selectedPath = savedPath;
      });
    } catch (_) {
      _show(
        'Could not detect document clearly. Retake in better light and keep full page in frame.',
        true,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _import() async {
    try {
      setState(() => _loading = true);
      final picked = await DocumentCaptureService.captureCorrected(
        allowGalleryImport: true,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final savedPath = await _saveIntoIntake(
        bytes: bytes,
        originalName: picked.name,
      );
      if (!mounted) return;
      setState(() {
        _allItems.insert(
          0,
          IntakeImageSelection(
            bytes: bytes,
            fastScanBytes: null,
            name: p.basename(savedPath),
            path: savedPath,
            savedAt: DateTime.now(),
            isTempIntake: true,
          ),
        );
        _selectedPath = savedPath;
      });
    } catch (_) {
      _show(
        'Could not prepare document image. Try another image with visible edges.',
        true,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _show(String message, bool isError) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  Future<void> _deleteTempItem(IntakeImageSelection item) async {
    if (!item.isTempIntake) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete temp image?'),
            content: Text(
              'Remove "${item.name}" from intake temp storage?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    try {
      final file = File(item.path);
      if (await file.exists()) {
        await file.delete();
      }
      if (!mounted) return;
      setState(() {
        _allItems.removeWhere((x) => x.path == item.path);
        final currentVisible = _visibleItems;
        if (currentVisible.isEmpty) {
          _selectedPath = null;
        } else if (!currentVisible.any((x) => x.path == _selectedPath)) {
          _selectedPath = currentVisible.first.path;
        }
      });
      _show('Temp image deleted.', false);
    } catch (_) {
      _show('Could not delete temp image.', true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final visibleItems = _visibleItems;
    final visibleTempItems = visibleItems.where((x) => x.isTempIntake).toList();
    if (visibleTempItems.isNotEmpty &&
        (_selectedPath == null ||
            !visibleTempItems.any((item) => item.path == _selectedPath))) {
      _selectedPath = visibleTempItems.first.path;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice Intake'),
        actions: [
          IconButton(
            tooltip: 'Saved invoices',
            icon: const Icon(Icons.receipt_long),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ReceiptHistoryPage(),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _loading ? null : _capture,
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Take'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _loading ? null : _import,
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Import'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Today'),
                    selected: _filter == 'today',
                    onSelected: (_) => setState(() => _filter = 'today'),
                  ),
                  ChoiceChip(
                    label: const Text('Week'),
                    selected: _filter == 'week',
                    onSelected: (_) => setState(() => _filter = 'week'),
                  ),
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _filter == 'all',
                    onSelected: (_) => setState(() => _filter = 'all'),
                  ),
                ],
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            Expanded(
              child: visibleTempItems.isEmpty
                  ? Center(
                      child: Text(
                        'No intake temp images for selected filter.',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      itemCount: visibleTempItems.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: colorScheme.outlineVariant,
                      ),
                      itemBuilder: (context, index) {
                        final item = visibleTempItems[index];
                        return _buildIntakeItemTile(
                          context: context,
                          colorScheme: colorScheme,
                          item: item,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: SizedBox(
            height: 56,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.0),
              ),
              child: FilledButton.icon(
                onPressed: visibleTempItems.isEmpty || _selectedPath == null
                    ? null
                    : () {
                        final selected = visibleTempItems.firstWhere(
                          (item) => item.path == _selectedPath,
                          orElse: () => visibleTempItems.first,
                        );
                        Navigator.of(context).pop(selected);
                      },
                icon: const Icon(Icons.check),
                label: const Text('Use Selected Image'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIntakeItemTile({
    required BuildContext context,
    required ColorScheme colorScheme,
    required IntakeImageSelection item,
  }) {
    final selected = item.path == _selectedPath;
    return ListTile(
      onTap: () => setState(() => _selectedPath = item.path),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(
          item.bytes,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
        ),
      ),
      title: Text(
        item.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${(item.bytes.length / 1024).toStringAsFixed(0)} KB | ${DateFormat('dd/MM/yyyy HH:mm').format(item.savedAt)}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            selected ? Icons.check_circle : Icons.radio_button_unchecked,
            color: selected ? colorScheme.primary : colorScheme.outline,
          ),
          const SizedBox(width: 4),
          if (item.isTempIntake)
            IconButton(
              tooltip: 'Delete temp image',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _deleteTempItem(item),
            ),
        ],
      ),
      selected: selected,
    );
  }
}
