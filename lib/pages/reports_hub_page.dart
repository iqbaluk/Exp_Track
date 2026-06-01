part of '../main.dart';

class ReportsHubPage extends StatefulWidget {
  final Project? initialProject;

  const ReportsHubPage({super.key, this.initialProject});

  @override
  State<ReportsHubPage> createState() => _ReportsHubPageState();
}

class _ReportsHubPageState extends State<ReportsHubPage> {
  List<Project> _projects = [];
  int? _selectedProjectId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selectedProjectId = widget.initialProject?.id;
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    setState(() => _loading = true);
    try {
      final projects = await DatabaseService.getProjects();
      if (!mounted) return;
      setState(() {
        _projects = projects;
        if (_selectedProjectId != null &&
            !_projects.any((project) => project.id == _selectedProjectId)) {
          _selectedProjectId = null;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load accounts: $e')),
      );
    }
  }

  Project? get _selectedProject {
    final id = _selectedProjectId;
    if (id == null) return null;
    for (final project in _projects) {
      if (project.id == id) return project;
    }
    return null;
  }

  Future<void> _openInvoiceList() async {
    final selected = _selectedProject;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => selected == null
            ? const ReceiptHistoryPage()
            : ReceiptHistoryPage(project: selected),
      ),
    );
  }

  Future<void> _openCombinedReport() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CombinedReportPage(
          initialRange: ExportRange.allTime(),
          initialDateBasis: DateBasis.invoiceDate,
        ),
      ),
    );
  }

  Future<void> _openMonthlyActivityReport() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MonthlyActivityReportPage(project: _selectedProject),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
              title: 'Reports hub',
              icon: Icons.insights_outlined,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: _selectedProjectId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Account scope',
                prefixIcon: Icon(Icons.business_center_outlined),
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('All accounts'),
                ),
                ..._projects.map(
                  (project) => DropdownMenuItem<int?>(
                    value: project.id,
                    child: Text(project.name),
                  ),
                ),
              ],
              onChanged: _loading
                  ? null
                  : (value) => setState(() => _selectedProjectId = value),
            ),
            const SizedBox(height: 12),
            _ReportHubTile(
              title: 'Invoice list and exports',
              subtitle:
                  'Search receipts, apply filters, export/share, and print.',
              icon: Icons.receipt_long,
              onTap: _loading ? null : _openInvoiceList,
            ),
            const SizedBox(height: 10),
            _ReportHubTile(
              title: 'Combined report',
              subtitle:
                  'Head of Account summary with invoice count, amount, and exports.',
              icon: Icons.insert_chart_outlined,
              onTap: _loading ? null : _openCombinedReport,
            ),
            const SizedBox(height: 10),
            _ReportHubTile(
              title: 'Monthly activity report',
              subtitle:
                  '12-month category matrix from financial year start month.',
              icon: Icons.calendar_view_month,
              onTap: _loading ? null : _openMonthlyActivityReport,
            ),
            if (_loading) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
            if (!_loading && _projects.isEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Text(
                  'No accounts found. Create accounts first, then open reports.',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReportHubTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  const _ReportHubTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: colorScheme.primary),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}
