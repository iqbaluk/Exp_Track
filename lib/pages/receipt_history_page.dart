part of '../main.dart';

class ReceiptHistoryPage extends StatefulWidget {
  final Project? project;

  const ReceiptHistoryPage({super.key, this.project});

  @override
  State<ReceiptHistoryPage> createState() => _ReceiptHistoryPageState();
}

class _ReceiptHistoryPageState extends State<ReceiptHistoryPage> {
  final _searchController = TextEditingController();
  List<Receipt> _receipts = [];
  List<Project> _projects = [];
  bool _loading = true;
  bool _tableView = true;
  ExportRange _range = ExportRange.allTime();
  DateBasis _dateBasis = DateBasis.invoiceDate;
  int? _selectedProjectId;
  final Set<int> _selectedReceiptIds = <int>{};

  @override
  void initState() {
    super.initState();
    _selectedProjectId = widget.project?.id;
    _loadProjects();
    _loadReceipts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    final projects = await DatabaseService.getProjects();
    if (!mounted) return;
    setState(() {
      _projects = projects;
      if (widget.project == null &&
          _selectedProjectId != null &&
          !_projects.any((project) => project.id == _selectedProjectId)) {
        _selectedProjectId = null;
      }
    });
  }

  Future<void> _loadReceipts({String? query}) async {
    setState(() => _loading = true);
    try {
      final searchText = query ?? _searchController.text;
      final rows = _dateBasis == DateBasis.scanDate
          ? await DatabaseService.getByScanDateRange(
              _range.from,
              _range.to,
              projectId: _selectedProjectId,
            )
          : await DatabaseService.getByDateRange(
              _range.from,
              _range.to,
              projectId: _selectedProjectId,
            );
      final filtered = rows
          .where((receipt) => _matchesSearchQuery(receipt, searchText))
          .toList();
      if (!mounted) return;
      setState(() {
        _receipts = filtered;
        final visibleIds =
            filtered.map((receipt) => receipt.id).whereType<int>().toSet();
        _selectedReceiptIds.removeWhere((id) => !visibleIds.contains(id));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invoice list failed: $e')),
      );
    }
  }

  bool _matchesSearchQuery(Receipt receipt, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final numericQuery =
        double.tryParse(q.replaceAll('Ã‚Â£', '').replaceAll(',', '').trim());
    final amountMatches = numericQuery != null &&
        ((receipt.gross - numericQuery).abs() < 0.005 ||
            (receipt.vat - numericQuery).abs() < 0.005 ||
            (receipt.net - numericQuery).abs() < 0.005);

    if (amountMatches) return true;

    final textFields = <String>[
      receipt.supplier,
      receipt.invoiceNumber ?? '',
      receipt.category,
      Receipt.formatDate(receipt.date),
      Receipt.formatDate(receipt.createdAt),
      DateFormat('dd/MM/yy').format(receipt.date),
      DateFormat('dd/MM/yyyy').format(receipt.createdAt),
      (receipt.scanNo ?? receipt.id ?? 0).toString(),
      receipt.gross.toStringAsFixed(2),
      receipt.vat.toStringAsFixed(2),
      receipt.net.toStringAsFixed(2),
    ];
    return textFields.any((value) => value.toLowerCase().contains(q));
  }

  Future<void> _openDetail(Receipt receipt) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReceiptDetailPage(receipt: receipt),
      ),
    );
    if (changed == true) {
      await _loadReceipts();
    }
  }

  Future<void> _openReportsFromInvoiceList() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReportsHubPage(
          initialProject: _selectedProject ?? widget.project,
        ),
      ),
    );
  }

  Future<void> _pickRange() async {
    final next = await _pickExportRange(
      context,
      title: 'Invoice list range',
    );
    if (next == null || !mounted) return;
    setState(() => _range = next);
    await _loadReceipts();
  }

  void _setDateBasis(DateBasis basis) {
    setState(() => _dateBasis = basis);
    _loadReceipts();
  }

  Future<void> _showInvoiceListExportMenu() async {
    final contentChoice = await showDialog<ExportContent>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Share invoice list'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ExportContent.csvOnly),
            child: const ListTile(
              leading: Icon(Icons.description),
              title: Text('CSV only'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ExportContent.both),
            child: const ListTile(
              leading: Icon(Icons.cloud_upload),
              title: Text('CSV + photos ZIP'),
              subtitle: Text('CSV attached separately, photos zipped'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ExportContent.photosOnly),
            child: const ListTile(
              leading: Icon(Icons.photo_library),
              title: Text('Photos only ZIP'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (contentChoice == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Building export...')),
    );
    final selectedReceipts = _selectedReceipts;
    final activeReceipts =
        selectedReceipts.isNotEmpty ? selectedReceipts : _receipts;

    final result = await ExportService.exportAndShare(
      _range,
      content: contentChoice,
      dateBasis: _dateBasis,
      projectId: _selectedProjectId,
      projectName: _selectedProjectName,
      explicitReceipts: activeReceipts,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.success
              ? 'Sharing ${result.recordCount} receipts${result.photoCount > 0 ? " + ${result.photoCount} photos" : ""}.'
              : result.errorMessage ?? 'Export failed',
        ),
        backgroundColor:
            result.success ? null : Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _printInvoiceList() async {
    final selectedReceipts = _selectedReceipts;
    final activeReceipts =
        selectedReceipts.isNotEmpty ? selectedReceipts : _receipts;
    if (activeReceipts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No receipts to print in this view.')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preparing invoice list for print...')),
    );
    try {
      final pdfBytes = await ExportService.buildInvoiceListPdfBytes(
        receipts: activeReceipts,
        range: _range,
        dateBasis: _dateBasis,
        projectName: _selectedProjectName,
      );
      if (!mounted) return;
      await openInAppPrintPreview(
        context,
        title: 'Print invoice list',
        fileName: 'invoice_list_${_range.label}.pdf',
        pdfBytes: pdfBytes,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print failed: $e')),
      );
    }
  }

  void _clearSearch() {
    _searchController.clear();
    _loadReceipts(query: '');
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _range = ExportRange.allTime();
      _dateBasis = DateBasis.invoiceDate;
      if (widget.project == null) {
        _selectedProjectId = null;
      }
    });
    _loadReceipts(query: '');
  }

  bool _isSelected(Receipt receipt) {
    final id = receipt.id;
    if (id == null) return false;
    return _selectedReceiptIds.contains(id);
  }

  void _toggleSelection(Receipt receipt, bool selected) {
    final id = receipt.id;
    if (id == null) return;
    setState(() {
      if (selected) {
        _selectedReceiptIds.add(id);
      } else {
        _selectedReceiptIds.remove(id);
      }
    });
  }

  void _selectAllVisible() {
    setState(() {
      for (final receipt in _receipts) {
        final id = receipt.id;
        if (id != null) _selectedReceiptIds.add(id);
      }
    });
  }

  void _clearAllSelected() {
    setState(() => _selectedReceiptIds.clear());
  }

  Project? get _selectedProject {
    final id = _selectedProjectId;
    if (id == null) return null;
    for (final project in _projects) {
      if (project.id == id) return project;
    }
    if (widget.project?.id == id) return widget.project;
    return null;
  }

  String? get _selectedProjectName => _selectedProject?.name;

  String _projectName(int? id) {
    if (id == null) return 'Unassigned';
    for (final project in _projects) {
      if (project.id == id) return project.name;
    }
    if (widget.project?.id == id) return widget.project!.name;
    return 'Operation $id';
  }

  double get _totalGross =>
      _receipts.fold<double>(0, (sum, receipt) => sum + receipt.gross);

  List<Receipt> get _selectedReceipts =>
      _receipts.where(_isSelected).toList(growable: false);

  String _money(double value) => formatAppMoney(value);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            onPressed: () => goToHomePage(context),
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
          ),
          IconButton(
            onPressed: _pickRange,
            icon: const Icon(Icons.date_range),
            tooltip: 'Period',
          ),
          IconButton(
            onPressed: _showInvoiceListExportMenu,
            icon: const Icon(Icons.cloud_upload_outlined),
            tooltip: 'Upload/share',
          ),
          IconButton(
            onPressed: _printInvoiceList,
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Print invoice list',
          ),
          PopupMenuButton<DateBasis>(
            tooltip: 'Date filter',
            icon: const Icon(Icons.filter_alt),
            onSelected: _setDateBasis,
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: DateBasis.invoiceDate,
                child: Text('Invoice date'),
              ),
              PopupMenuItem(
                value: DateBasis.scanDate,
                child: Text('Scan date'),
              ),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'reports':
                  _openReportsFromInvoiceList();
                  break;
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'reports',
                child: Text('Reports hub'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildHistoryBanner(colorScheme),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search invoice, supplier, category, amount',
                hintText: 'e.g. CESV218200, tesco, sundries, 31.60',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: _clearSearch,
                        icon: const Icon(Icons.close),
                        tooltip: 'Clear search',
                      ),
              ),
              textInputAction: TextInputAction.search,
              onChanged: (value) => _loadReceipts(query: value),
              onSubmitted: (value) => _loadReceipts(query: value),
            ),
            if (widget.project == null) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: _selectedProjectId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Operation filter',
                  prefixIcon: Icon(Icons.business_center_outlined),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('All operations'),
                  ),
                  ..._projects.map(
                    (project) => DropdownMenuItem<int?>(
                      value: project.id,
                      child: Text(project.name),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() => _selectedProjectId = value);
                  _loadReceipts(query: _searchController.text);
                },
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _resetFilters,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reset'),
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.table_rows),
                      label: Text('Table'),
                    ),
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.view_agenda),
                      label: Text('Cards'),
                    ),
                  ],
                  selected: {_tableView},
                  onSelectionChanged: (selection) {
                    setState(() => _tableView = selection.first);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: colorScheme.outlineVariant),
            const SizedBox(height: 12),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                Text(
                  '${_receipts.length} results',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  'Total gross: ${_money(_totalGross)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _receipts.isEmpty ? null : _selectAllVisible,
                  icon: const Icon(Icons.select_all),
                  label: const Text('Select all'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _selectedReceiptIds.isEmpty ? null : _clearAllSelected,
                  icon: const Icon(Icons.deselect),
                  label: const Text('Clear all'),
                ),
                if (_selectedReceiptIds.isNotEmpty)
                  Chip(label: Text('Selected: ${_selectedReceiptIds.length}')),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_receipts.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  border: Border.all(color: colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    'No matching invoices.',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            else if (_tableView)
              _InvoiceTable(
                receipts: _receipts,
                onOpen: _openDetail,
                isSelected: _isSelected,
                onSelectionChanged: _toggleSelection,
              )
            else
              for (final receipt in _receipts) ...[
                _HistoryReceiptTile(
                  receipt: receipt,
                  projectName: widget.project == null
                      ? _projectName(receipt.projectId)
                      : null,
                  onTap: () => _openDetail(receipt),
                  selected: _isSelected(receipt),
                  onSelectedChanged: (selected) =>
                      _toggleSelection(receipt, selected),
                ),
                const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryBanner(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: AppDecor.heroGradient(colorScheme),
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppDecor.softShadow(colorScheme),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colorScheme.onPrimary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _tableView ? Icons.table_rows : Icons.view_agenda,
              color: colorScheme.onPrimary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Invoice list and exports',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onPrimary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceTable extends StatelessWidget {
  final List<Receipt> receipts;
  final ValueChanged<Receipt> onOpen;
  final bool Function(Receipt receipt) isSelected;
  final void Function(Receipt receipt, bool selected) onSelectionChanged;

  const _InvoiceTable({
    required this.receipts,
    required this.onOpen,
    required this.isSelected,
    required this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final headerStyle = TextStyle(
      color: colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w800,
      fontSize: 12,
      letterSpacing: 0.3,
    );

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.3),
          1: FlexColumnWidth(2.8),
          2: FlexColumnWidth(4.0),
          3: FlexColumnWidth(3.2),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(color: colorScheme.surfaceContainerHigh),
            children: [
              _InvoiceTableCell('Sel', style: headerStyle),
              _InvoiceTableCell('Date', style: headerStyle),
              _InvoiceTableCell('Supplier', style: headerStyle),
              _InvoiceTableCell('Gross', style: headerStyle, alignRight: true),
            ],
          ),
          for (final receipt in receipts)
            TableRow(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Center(
                    child: Checkbox(
                      value: isSelected(receipt),
                      visualDensity: VisualDensity.compact,
                      onChanged: (value) =>
                          onSelectionChanged(receipt, value ?? false),
                    ),
                  ),
                ),
                _InvoiceTableCell(
                  DateFormat('dd/MM/yy').format(receipt.date),
                  fitText: true,
                  style: const TextStyle(fontSize: 12),
                  onTap: () => onOpen(receipt),
                ),
                _InvoiceTableCell(
                  receipt.supplier,
                  maxLines: 3,
                  onTap: () => onOpen(receipt),
                ),
                _InvoiceTableCell(
                  formatAppMoney(receipt.gross),
                  alignRight: true,
                  fitText: true,
                  onTap: () => onOpen(receipt),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _InvoiceTableCell extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final bool alignRight;
  final int maxLines;
  final bool fitText;
  final VoidCallback? onTap;

  const _InvoiceTableCell(
    this.text, {
    this.style,
    this.alignRight = false,
    this.maxLines = 1,
    this.fitText = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textWidget = Text(
      text,
      textAlign: alignRight ? TextAlign.right : TextAlign.left,
      maxLines: maxLines,
      overflow: fitText ? TextOverflow.visible : TextOverflow.ellipsis,
      softWrap: false,
      style: style,
    );

    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: fitText
          ? FittedBox(
              fit: BoxFit.scaleDown,
              alignment:
                  alignRight ? Alignment.centerRight : Alignment.centerLeft,
              child: textWidget,
            )
          : textWidget,
    );
    if (onTap == null) return child;
    return InkWell(onTap: onTap, child: child);
  }
}

class _HistoryReceiptTile extends StatelessWidget {
  final Receipt receipt;
  final String? projectName;
  final VoidCallback onTap;
  final bool selected;
  final ValueChanged<bool> onSelectedChanged;

  const _HistoryReceiptTile({
    required this.receipt,
    this.projectName,
    required this.onTap,
    required this.selected,
    required this.onSelectedChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subtitleParts = [
      '#${(receipt.scanNo ?? 0).toString().padLeft(5, '0')}',
      receipt.category,
      if (projectName != null) projectName!,
      'Invoice ${DateFormat('dd/MM/yy').format(receipt.date)}',
      'Scanned ${DateFormat('dd/MM/yyyy').format(receipt.createdAt)}',
    ];

    return ListTile(
      onTap: onTap,
      selected: selected,
      selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      leading: receipt.photoPath == null
          ? const Icon(Icons.receipt_long)
          : ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.file(
                File(receipt.photoPath!),
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
              ),
            ),
      title: Text(
        [
          receipt.supplier,
          if ((receipt.invoiceNumber ?? '').trim().isNotEmpty)
            'Inv ${receipt.invoiceNumber!.trim()}',
        ].join(' - '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitleParts.join(' Â· '),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: SizedBox(
        width: 128,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Checkbox(
              value: selected,
              visualDensity: VisualDensity.compact,
              onChanged: (value) => onSelectedChanged(value ?? false),
            ),
            Flexible(
              child: Text(
                formatAppMoney(receipt.gross),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}

