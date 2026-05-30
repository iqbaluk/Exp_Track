part of '../main.dart';

class ProjectListPage extends StatefulWidget {
  const ProjectListPage({super.key});

  @override
  State<ProjectListPage> createState() => _ProjectListPageState();
}

class _ProjectListPageState extends State<ProjectListPage> {
  List<Project> _projects = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    setState(() => _loading = true);
    try {
      final projects = await DatabaseService.getProjects();
      final byName = <String, Project>{
        for (final project in projects) project.name.toLowerCase(): project,
      };
      final fixed = <Project>[
        for (final head in DatabaseService.fixedOperationHeads)
          if (byName.containsKey(head.toLowerCase()))
            byName[head.toLowerCase()]!,
      ];
      if (!mounted) return;
      setState(() {
        _projects = fixed;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load operations: $e')),
      );
    }
  }

  Future<void> _openProject(Project project) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiptEntryPage(project: project),
      ),
    );
    await _loadProjects();
  }

  Future<void> _openReportsHub({Project? initialProject}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReportsHubPage(initialProject: initialProject),
      ),
    );
    await _loadProjects();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SettingsPage(),
      ),
    );
    await _loadProjects();
  }

  Future<void> _openIntake() async {
    final selected = await Navigator.of(context).push<IntakeImageSelection>(
      MaterialPageRoute(
        builder: (_) => const ReceiptIntakePage(),
      ),
    );
    if (!mounted || selected == null) return;
    if (_projects.isEmpty) {
      _showProjectMessage('No operation heads found. Reopen app to re-seed.');
      return;
    }

    Project? targetProject;
    if (_projects.length == 1) {
      targetProject = _projects.first;
    } else {
      targetProject = await showDialog<Project>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Select operation'),
          children: _projects
              .map(
                (project) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, project),
                  child: Text(project.name),
                ),
              )
              .toList(),
        ),
      );
    }

    if (!mounted || targetProject == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiptEntryPage(
          project: targetProject!,
          initialImageBytes: selected.bytes,
          initialImageName: selected.name,
          initialImagePath: selected.path,
          initialFastScanBytes: selected.fastScanBytes,
        ),
      ),
    );
    await _loadProjects();
  }

  Future<void> _createProjectFromDialog() async {
    final name = TextEditingController();
    final address = TextEditingController();
    final budget = TextEditingController();
    final notes = TextEditingController();

    final draft = await showDialog<Project>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create operation'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration:
                    const InputDecoration(labelText: 'Operation name *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: address,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: budget,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Budget',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final trimmedName = name.text.trim();
              if (trimmedName.isEmpty) return;
              Navigator.pop(
                ctx,
                Project(
                  name: trimmedName,
                  address:
                      address.text.trim().isEmpty ? null : address.text.trim(),
                  budget: double.tryParse(budget.text),
                  notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
                ),
              );
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      name.dispose();
      address.dispose();
      budget.dispose();
      notes.dispose();
    });

    if (draft == null) return;
    try {
      final created = await DatabaseService.createProject(draft);
      if (!mounted) return;
      await _loadProjects();
      if (!mounted) return;
      await _openProject(created);
    } catch (e) {
      _showProjectMessage('Could not create operation: $e');
    }
  }

  void _showProjectMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    IconButton topAction({
      required IconData icon,
      required String tooltip,
      required VoidCallback onPressed,
      Color? color,
    }) {
      return IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        icon: Icon(icon, color: color),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLow,
      appBar: AppBar(
        actions: [
          topAction(
            onPressed: _openIntake,
            icon: Icons.camera_alt_outlined,
            tooltip: 'Intake',
          ),
          topAction(
            onPressed: _openReportsHub,
            icon: Icons.insights_outlined,
            tooltip: 'Reports hub',
          ),
          topAction(
            onPressed: _openSettings,
            icon: Icons.settings,
            tooltip: 'Management',
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                children: [
                  buildPageTitleBanner(
                    context,
                    title: 'Operations',
                    icon: Icons.business_center_outlined,
                  ),
                  const SizedBox(height: 12),
                  _buildHeroHeader(),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(
                        Icons.camera_alt_outlined,
                        size: 22,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Select an operation to begin scanning',
                          style: TextStyle(
                            fontSize: 18,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_projects.isEmpty)
                    _buildEmptyState()
                  else
                    for (final project in _projects) ...[
                      _ProjectCard(
                        project: project,
                        onTap: () => _openProject(project),
                      ),
                      const SizedBox(height: 12),
                    ],
                ],
              ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            border: Border(
              top: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: SystemNavigator.pop,
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.error,
                    foregroundColor: colorScheme.onError,
                  ),
                  icon: const Icon(Icons.exit_to_app),
                  label: const Text('Close App'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroHeader() {
    final colorScheme = Theme.of(context).colorScheme;
    final totalReceipts = _projects.fold<int>(
      0,
      (sum, project) => sum + project.receiptCount,
    );
    final totalGross = _projects.fold<double>(
      0,
      (sum, project) => sum + project.totalGross,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        gradient: AppDecor.heroGradient(colorScheme),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppDecor.softShadow(colorScheme),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Text(
              'Summary Total',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: colorScheme.onPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildStatBlock('Receipts', '$totalReceipts'),
              ),
              _buildStatDivider(colorScheme),
              Expanded(
                child: _buildStatBlock('Gross', formatAppMoney(totalGross)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatBlock(String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colorScheme.onPrimary.withValues(alpha: 0.92),
            fontSize: 13.5,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colorScheme.onPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 16.5,
          ),
        ),
      ],
    );
  }

  Widget _buildStatDivider(ColorScheme colorScheme) {
    return Container(
      width: 1,
      height: 54,
      color: colorScheme.onPrimary.withValues(alpha: 0.2),
    );
  }

  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.folder_open_rounded,
              size: 38,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No operation heads found',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please restart the app to re-seed the 10 fixed operation heads.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final Project project;
  final VoidCallback onTap;

  const _ProjectCard({
    required this.project,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accents = [
      colorScheme.primary,
      colorScheme.secondary,
      colorScheme.tertiary,
      const Color(0xFF0E7490),
      const Color(0xFF1D4ED8),
    ];
    final accent =
        accents[(project.id ?? project.name.length) % accents.length];
    final budget = project.budget;
    final total = project.totalGross;
    final totalText = NumberFormat('#,##0.00').format(total);
    final subtitle = [
      if (project.address != null) project.address!,
      if (budget != null) '${budget.toStringAsFixed(2)} budget',
    ].join(' • ');

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border(
              left: BorderSide(color: accent, width: 3),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    height: 6,
                    width: 52,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [accent, accent.withValues(alpha: 0.45)],
                      ),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${project.receiptCount} receipts',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: project.name,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          TextSpan(
                            text: ' : $totalText',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: colorScheme.outline),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
