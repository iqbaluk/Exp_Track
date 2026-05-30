part of '../main.dart';

class CategoryManagerPage extends StatefulWidget {
  const CategoryManagerPage({super.key});

  @override
  State<CategoryManagerPage> createState() => _CategoryManagerPageState();
}

class _CategoryManagerPageState extends State<CategoryManagerPage> {
  final _newCategoryController = TextEditingController();
  List<AppCategory> _heads = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _newCategoryController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() => _loading = true);
    try {
      final mains = await DatabaseService.getMainCategories();
      final categories = await DatabaseService.getCategories();
      final byName = {for (final c in categories) c.name.trim(): c};
      final merged = <AppCategory>[];
      for (final main in mains) {
        final existing = byName[main];
        if (existing != null) {
          merged.add(existing);
        } else {
          // Backfill missing main heads in app-level list.
          merged.add(
            await DatabaseService.createCategory(main),
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _heads = merged;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('Could not load heads of account: $e');
    }
  }

  Future<void> _addCategory() async {
    final name = _newCategoryController.text.trim();
    if (name.isEmpty) {
      _showMessage('Enter a head of account name first.');
      return;
    }
    try {
      await DatabaseService.createCategory(name);
      if (!mounted) return;
      _newCategoryController.clear();
      await _loadCategories();
    } catch (e) {
      _showMessage('Could not add head of account: ${_friendlyDbError(e)}');
    }
  }

  Future<void> _deleteSubcategory(AppCategory category) async {
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete subcategory?'),
        content: Text('Delete "${category.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await Future<void>.delayed(Duration.zero);
    try {
      await DatabaseService.deleteCategory(category);
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadCategories();
      });
    } catch (e) {
      _showMessage(_friendlyDbError(e));
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    });
  }

  String _friendlyDbError(Object error) {
    final text = error.toString().replaceFirst('Bad state: ', '');
    if (text.contains('UNIQUE constraint failed')) {
      return 'A head of account with that name already exists.';
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
            onPressed: () => goToHomePage(context),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            buildPageTitleBanner(
              context,
              title: 'Heads of Account',
              icon: Icons.category_outlined,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newCategoryController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'New head of account',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _addCategory(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _addCategory,
                    child: const Text('Add'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else ...[
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Main heads only.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              for (final head in _heads)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(head.name),
                    trailing: SizedBox(
                      width: 48,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Delete head',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _deleteSubcategory(head),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
