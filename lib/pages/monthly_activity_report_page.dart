part of '../main.dart';

enum _MonthlyCategorySortMode {
  pnlOrder,
  grossDesc,
}

class MonthlyActivityReportPage extends StatefulWidget {
  final Project? project;

  const MonthlyActivityReportPage({super.key, this.project});

  @override
  State<MonthlyActivityReportPage> createState() =>
      _MonthlyActivityReportPageState();
}

class _MonthlyActivityReportPageState extends State<MonthlyActivityReportPage> {
  late int _fiscalStartYear;
  int _fiscalStartMonth = 4;
  DateBasis _dateBasis = DateBasis.invoiceDate;
  _MonthlyCategorySortMode _sortMode = _MonthlyCategorySortMode.pnlOrder;
  int? _selectedProjectId;
  List<Project> _projects = const [];
  late Future<MonthlyFiscalActivityReport> _reportFuture;
  bool _loadingCompanyProfile = true;
  String? _profileError;

  @override
  void initState() {
    super.initState();
    _selectedProjectId = widget.project?.id;
    _fiscalStartYear = _defaultFiscalStartYear(
      now: DateTime.now(),
      startMonth: _fiscalStartMonth,
    );
    _reload();
    _loadCompanyProfile();
    _loadProjectsForFilter();
  }

  int _defaultFiscalStartYear({
    required DateTime now,
    required int startMonth,
  }) {
    return now.month >= startMonth ? now.year : now.year - 1;
  }

  Future<void> _loadCompanyProfile() async {
    try {
      final profile = await DatabaseService.getCompanyProfile();
      if (!mounted) return;
      if (profile == null) {
        setState(() {
          _loadingCompanyProfile = false;
        });
        return;
      }
      final fyStartMonth = profile.financialYearStartMonth.clamp(1, 12).toInt();
      final fyStartYear = _defaultFiscalStartYear(
        now: DateTime.now(),
        startMonth: fyStartMonth,
      );
      setState(() {
        _fiscalStartMonth = fyStartMonth;
        _fiscalStartYear = fyStartYear;
        _loadingCompanyProfile = false;
        _profileError = null;
        _reload();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingCompanyProfile = false;
        _profileError = e.toString();
      });
    }
  }

  Future<void> _loadProjectsForFilter() async {
    try {
      final projects = await DatabaseService.getProjects();
      if (!mounted) return;
      setState(() => _projects = projects);
    } catch (_) {
      // Non-blocking for report screen.
    }
  }

  void _reload() {
    _reportFuture = DatabaseService.getMonthlyFiscalActivityReport(
      fiscalYearStartYear: _fiscalStartYear,
      fiscalYearStartMonth: _fiscalStartMonth,
      projectId: _selectedProjectId,
      useScanDate: _dateBasis == DateBasis.scanDate,
    );
  }

  void _shiftFiscalYear(int delta) {
    setState(() {
      _fiscalStartYear += delta;
      _reload();
    });
  }

  void _setDateBasis(DateBasis basis) {
    setState(() {
      _dateBasis = basis;
      _reload();
    });
  }

  void _setSortMode(_MonthlyCategorySortMode mode) {
    setState(() => _sortMode = mode);
  }

  Future<void> _pickFiscalYear() async {
    final now = DateTime.now();
    final years = List<int>.generate(11, (i) => now.year - 6 + i);
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Select financial year start'),
        children: [
          for (final year in years)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, year),
              child: Text(year.toString()),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _fiscalStartYear = selected;
      _reload();
    });
  }

  Future<void> _openInvoiceList() async {
    Project? selectedProject;
    if (widget.project != null) {
      selectedProject = widget.project;
    } else if (_selectedProjectId != null) {
      for (final p in _projects) {
        if (p.id == _selectedProjectId) {
          selectedProject = p;
          break;
        }
      }
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => selectedProject == null
            ? const ReceiptHistoryPage()
            : ReceiptHistoryPage(project: selectedProject),
      ),
    );
  }

  String _monthLabel(DateTime monthStart) {
    return DateFormat('MMM-yy').format(monthStart);
  }

  String _money(double value) => formatAppMoney(value);

  String _fiscalYearLabel(DateTime from, DateTime to) {
    return '${DateFormat('dd MMM yyyy').format(from)} - ${DateFormat('dd MMM yyyy').format(to)}';
  }

  String get _scopeName {
    if (widget.project != null) return widget.project!.name;
    if (_selectedProjectId == null) return 'All operations';
    for (final project in _projects) {
      if (project.id == _selectedProjectId) return project.name;
    }
    return 'All operations';
  }

  Future<void> _showMonthlyExportMenu() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Share monthly report'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'summary_pdf'),
            child: const ListTile(
              leading: Icon(Icons.description),
              title: Text('Summary PDF (Recommended)'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'summary_csv'),
            child: const ListTile(
              leading: Icon(Icons.table_view),
              title: Text('Summary CSV'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'summary_tx'),
            child: const ListTile(
              leading: Icon(Icons.table_view),
              title: Text('Summary + transactions CSV'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'tx_photos'),
            child: const ListTile(
              leading: Icon(Icons.cloud_upload),
              title: Text('Transactions + photos'),
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

    if (choice == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Building monthly export...')),
    );

    final report = await _reportFuture;
    final result = await ExportService.shareMonthlyReportSummary(
      report: report,
      dateBasis: _dateBasis,
      scopeName: _scopeName,
      projectId: _selectedProjectId,
      summaryAsPdf: choice == 'summary_pdf',
      includeTransactions: choice == 'summary_tx' || choice == 'tx_photos',
      includePhotos: choice == 'tx_photos',
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

  Future<void> _printMonthlyReport() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preparing monthly report for print...')),
    );
    try {
      final report = await _reportFuture;
      final pdfBytes = await ExportService.buildMonthlySummaryPdfBytes(
        report: report,
        dateBasis: _dateBasis,
        scopeName: _scopeName,
      );
      if (!mounted) return;
      await openInAppPrintPreview(
        context,
        title: 'Print monthly report',
        fileName:
            'monthly_report_${_scopeName.replaceAll(' ', '_')}$_fiscalStartYear.pdf',
        pdfBytes: pdfBytes,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print failed: $e')),
      );
    }
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
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: 'Period',
            onPressed: _pickFiscalYear,
          ),
          IconButton(
            icon: const Icon(Icons.cloud_upload_outlined),
            tooltip: 'Upload/share',
            onPressed: _showMonthlyExportMenu,
          ),
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Print report',
            onPressed: _printMonthlyReport,
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
                case 'invoice_list':
                  _openInvoiceList();
                  break;
                case 'pnl_order':
                  _setSortMode(_MonthlyCategorySortMode.pnlOrder);
                  break;
                case 'gross_order':
                  _setSortMode(_MonthlyCategorySortMode.grossDesc);
                  break;
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'invoice_list',
                child: Text('Invoice list'),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'pnl_order',
                child: Text('Head of Account order: P&L'),
              ),
              PopupMenuItem(
                value: 'gross_order',
                child: Text('Head of Account order: Gross high to low'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<MonthlyFiscalActivityReport>(
          future: _reportFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Report failed: ${snapshot.error}'));
            }
            final report = snapshot.data!;
            final nonZeroCategories = report.categories
                .where((category) => (report.categoryTotals[category] ?? 0) > 0)
                .toList();
            final displayCategories = DatabaseService.sortCategoryNames(
              nonZeroCategories,
              grossTotals: report.categoryTotals,
              byGrossDesc: _sortMode == _MonthlyCategorySortMode.grossDesc,
            );
            final visibleMonthIndexes = <int>[];
            for (var i = 0; i < report.monthTotals.length; i++) {
              if (report.monthTotals[i] > 0) {
                visibleMonthIndexes.add(i);
              }
            }
            final hasData = report.invoiceCount > 0 &&
                displayCategories.isNotEmpty &&
                visibleMonthIndexes.isNotEmpty;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                buildPageTitleBanner(
                  context,
                  title: 'Monthly activity report',
                  icon: Icons.calendar_view_month,
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (widget.project == null)
                              Expanded(
                                child: DropdownButtonFormField<int?>(
                                  initialValue: _selectedProjectId,
                                  isExpanded: true,
                                  isDense: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Operation',
                                  ),
                                  items: [
                                    const DropdownMenuItem<int?>(
                                      value: null,
                                      child: Text('All operations'),
                                    ),
                                    ..._projects.where((p) => p.id != null).map(
                                          (p) => DropdownMenuItem<int?>(
                                            value: p.id,
                                            child: Text(
                                              p.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                  ],
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedProjectId = value;
                                      _reload();
                                    });
                                  },
                                ),
                              )
                            else
                              Expanded(
                                child: Text(
                                  widget.project!.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            IconButton(
                              onPressed: () => _shiftFiscalYear(-1),
                              icon: const Icon(Icons.chevron_left),
                              tooltip: 'Previous financial year',
                            ),
                            Text(
                              _fiscalStartYear.toString(),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            IconButton(
                              onPressed: () => _shiftFiscalYear(1),
                              icon: const Icon(Icons.chevron_right),
                              tooltip: 'Next financial year',
                            ),
                          ],
                        ),
                        Text(
                          'Financial year: ${_fiscalYearLabel(report.from, report.to)}',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _MonthlyInfoChip(
                              label: 'Invoices',
                              value: report.invoiceCount.toString(),
                            ),
                            _MonthlyInfoChip(
                              label: 'Gross',
                              value: _money(report.grandTotal),
                            ),
                          ],
                        ),
                        if (_loadingCompanyProfile) ...[
                          const SizedBox(height: 10),
                          const LinearProgressIndicator(minHeight: 2),
                        ],
                        if (_profileError != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Company info load warning: $_profileError',
                            style: TextStyle(
                              color: colorScheme.error,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (!hasData)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('No activity in this financial year range.'),
                    ),
                  )
                else
                  Card(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Table(
                        defaultVerticalAlignment:
                            TableCellVerticalAlignment.middle,
                        border: TableBorder(
                          horizontalInside:
                              BorderSide(color: colorScheme.outlineVariant),
                          verticalInside:
                              BorderSide(color: colorScheme.outlineVariant),
                        ),
                        columnWidths: {
                          0: const FixedColumnWidth(170),
                          for (int i = 0; i < visibleMonthIndexes.length; i++)
                            i + 1: const FixedColumnWidth(94),
                          visibleMonthIndexes.length + 1:
                              const FixedColumnWidth(110),
                        },
                        children: [
                          TableRow(
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                            ),
                            children: [
                              _MonthlyCell(
                                'Details',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                              for (final monthIndex in visibleMonthIndexes)
                                _MonthlyCell(
                                  _monthLabel(report.months[monthIndex]),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                  alignRight: true,
                                ),
                              _MonthlyCell(
                                'Total',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                                alignRight: true,
                              ),
                            ],
                          ),
                          for (final category in displayCategories)
                            TableRow(
                              children: [
                                _MonthlyCell(
                                  category,
                                  style: TextStyle(
                                    color: colorScheme.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                for (final monthIndex in visibleMonthIndexes)
                                  _MonthlyCell(
                                    _money(
                                      report.categoryMonthGross[category]
                                              ?[monthIndex] ??
                                          0,
                                    ),
                                    style: TextStyle(
                                      color: colorScheme.onSurface,
                                    ),
                                    alignRight: true,
                                  ),
                                _MonthlyCell(
                                  _money(report.categoryTotals[category] ?? 0),
                                  style: TextStyle(
                                    color: colorScheme.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  alignRight: true,
                                ),
                              ],
                            ),
                          TableRow(
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLow,
                            ),
                            children: [
                              _MonthlyCell(
                                'Total',
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              for (final monthIndex in visibleMonthIndexes)
                                _MonthlyCell(
                                  _money(report.monthTotals[monthIndex]),
                                  style: TextStyle(
                                    color: colorScheme.onSurface,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  alignRight: true,
                                ),
                              _MonthlyCell(
                                _money(report.grandTotal),
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                                alignRight: true,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MonthlyInfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _MonthlyInfoChip({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthlyCell extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final bool alignRight;

  const _MonthlyCell(
    this.text, {
    this.style,
    this.alignRight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Text(
        text,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        style: style ?? const TextStyle(fontSize: 13),
      ),
    );
  }
}



