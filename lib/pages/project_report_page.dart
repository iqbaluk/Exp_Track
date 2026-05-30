part of '../main.dart';

class ProjectReportPage extends StatefulWidget {
  final Project project;

  const ProjectReportPage({super.key, required this.project});

  @override
  State<ProjectReportPage> createState() => _ProjectReportPageState();
}

class _ProjectReportPageState extends State<ProjectReportPage> {
  ExportRange _range = ExportRange.allTime();
  DateBasis _dateBasis = DateBasis.invoiceDate;
  late Future<ProjectReport> _reportFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _reportFuture = DatabaseService.getProjectReport(
      projectId: widget.project.id,
      from: _range.from,
      to: _range.to,
      useScanDate: _dateBasis == DateBasis.scanDate,
    );
  }

  Future<void> _pickRange() async {
    final next = await _pickExportRange(
      context,
      title: 'Operation report range',
    );
    if (next == null || !mounted) return;
    setState(() {
      _range = next;
      _reload();
    });
  }

  void _setDateBasis(DateBasis basis) {
    setState(() {
      _dateBasis = basis;
      _reload();
    });
  }

  Future<void> _openInvoiceList() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiptHistoryPage(project: widget.project),
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

  Future<void> _showReportExportMenu() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Share report'),
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
      const SnackBar(content: Text('Building report export...')),
    );

    final report = await _reportFuture;
    final result = await ExportService.shareProjectReportSummary(
      project: widget.project,
      report: report,
      range: _range,
      dateBasis: _dateBasis,
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

  Future<void> _printReport() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preparing report for print...')),
    );
    try {
      final report = await _reportFuture;
      final pdfBytes = await ExportService.buildProjectSummaryPdfBytes(
        project: widget.project,
        report: report,
        range: _range,
        dateBasis: _dateBasis,
      );
      if (!mounted) return;
      await openInAppPrintPreview(
        context,
        title: 'Print report',
        fileName: 'operation_report_${widget.project.name}.pdf',
        pdfBytes: pdfBytes,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print failed: $e')),
      );
    }
  }

  String _rangeLabel() {
    switch (_range.label) {
      case 'all_time':
        return 'All receipts';
      case 'this_month':
        return DateFormat('MMMM yyyy').format(_range.from);
      case 'last_month':
        return DateFormat('MMMM yyyy').format(_range.from);
      default:
        if (_range.label.startsWith('this_year')) {
          return 'Year ${_range.from.year}';
        }
        return '${DateFormat('dd/MM/yy').format(_range.from)} - ${DateFormat('dd/MM/yy').format(_range.to)}';
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
            onPressed: _pickRange,
          ),
          IconButton(
            icon: const Icon(Icons.cloud_upload_outlined),
            tooltip: 'Upload/share',
            onPressed: _showReportExportMenu,
          ),
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Print report',
            onPressed: _printReport,
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
                case 'combined_report':
                  _openCombinedReport();
                  break;
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'invoice_list',
                child: Text('Invoice list'),
              ),
              PopupMenuItem(
                value: 'combined_report',
                child: Text('Combined report'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<ProjectReport>(
          future: _reportFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Report failed: ${snapshot.error}'));
            }
            final report = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                buildPageTitleBanner(
                  context,
                  title: 'Operation report and exports',
                  icon: Icons.bar_chart,
                ),
                const SizedBox(height: 14),
                _buildReportHeader(colorScheme),
                if (report.categories.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  SummaryReportTable(report: report),
                ],
                if (widget.project.budget != null) ...[
                  const SizedBox(height: 16),
                  _BudgetProgress(
                    budget: widget.project.budget!,
                    spent: report.totalGross,
                  ),
                ],
                if (report.categories.isEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      border: Border.all(color: colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.inbox,
                              size: 48, color: colorScheme.outline),
                          const SizedBox(height: 12),
                          Text(
                            'No receipts in this range.',
                            style: TextStyle(color: colorScheme.outline),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildReportHeader(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.project.name,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${_rangeLabel()} | ${_dateBasis == DateBasis.scanDate ? "Scan date" : "Invoice date"}',
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class SummaryReportTable extends StatelessWidget {
  final ProjectReport report;

  const SummaryReportTable({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final headerStyle = TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 13,
      color: colorScheme.onPrimaryContainer,
      letterSpacing: 0.5,
    );
    const totalStyle = TextStyle(
      fontWeight: FontWeight.w800,
      fontSize: 15,
      color: Colors.red,
    );
    final cellStyle = TextStyle(fontSize: 14, color: colorScheme.onSurface);

    return Card(
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.45),
          1: FlexColumnWidth(0.95),
          2: FlexColumnWidth(1.05),
        },
        border: TableBorder(
          horizontalInside: BorderSide(color: colorScheme.outlineVariant),
        ),
        children: [
          TableRow(
            decoration: BoxDecoration(color: colorScheme.primaryContainer),
            children: [
              _ReportCell('Head of Account', style: headerStyle),
              _ReportCell('Inv count', style: headerStyle, alignRight: true),
              _ReportCell('Gross', style: headerStyle, alignRight: true),
            ],
          ),
          for (final summary in report.categories)
            TableRow(
              children: [
                _ReportCell(summary.category, style: cellStyle),
                _ReportCell(
                  summary.receiptCount.toString(),
                  style: cellStyle,
                  alignRight: true,
                ),
                _ReportCell(
                  summary.totalGross.toStringAsFixed(2),
                  style: cellStyle,
                  alignRight: true,
                ),
              ],
            ),
          TableRow(
            decoration: BoxDecoration(color: colorScheme.surfaceContainerLow),
            children: [
              const _ReportCell('Total', style: totalStyle),
              _ReportCell(
                report.receiptCount.toString(),
                style: totalStyle,
                alignRight: true,
              ),
              _ReportCell(
                report.totalGross.toStringAsFixed(2),
                style: totalStyle,
                alignRight: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReportCell extends StatelessWidget {
  final String text;
  final TextStyle style;
  final bool alignRight;

  const _ReportCell(
    this.text, {
    required this.style,
    this.alignRight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Text(
        text,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

class _BudgetProgress extends StatelessWidget {
  final double budget;
  final double spent;

  const _BudgetProgress({
    required this.budget,
    required this.spent,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ratio = budget <= 0 ? 0.0 : (spent / budget).clamp(0.0, 1.0);
    final remaining = budget - spent;
    final overBudget = remaining < 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: overBudget
                        ? colorScheme.error.withValues(alpha: 0.12)
                        : colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    overBudget ? Icons.warning : Icons.account_balance,
                    size: 18,
                    color: overBudget ? colorScheme.error : colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Budget',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        '${formatAppMoney(spent)} / ${formatAppMoney(budget)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: overBudget
                        ? colorScheme.error.withValues(alpha: 0.1)
                        : colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${(ratio * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color:
                          overBudget ? colorScheme.error : colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 8,
                backgroundColor: colorScheme.surfaceContainerLow,
                color: overBudget ? colorScheme.error : colorScheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  overBudget
                      ? '${formatAppMoney(remaining.abs())} over budget'
                      : '${formatAppMoney(remaining)} remaining',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: overBudget ? colorScheme.error : colorScheme.primary,
                  ),
                ),
                const Spacer(),
                Text(
                  'Budget: ${formatAppMoney(budget)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

