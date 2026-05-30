part of '../main.dart';

class CombinedReportPage extends StatefulWidget {
  final ExportRange initialRange;
  final DateBasis initialDateBasis;

  const CombinedReportPage({
    super.key,
    required this.initialRange,
    required this.initialDateBasis,
  });

  @override
  State<CombinedReportPage> createState() => _CombinedReportPageState();
}

class _CombinedReportPageState extends State<CombinedReportPage> {
  late ExportRange _range;
  late DateBasis _dateBasis;
  late Future<CombinedProjectReport> _future;

  @override
  void initState() {
    super.initState();
    _range = widget.initialRange;
    _dateBasis = widget.initialDateBasis;
    _reload();
  }

  void _reload() {
    _future = DatabaseService.getCombinedProjectReport(
      from: _range.from,
      to: _range.to,
      useScanDate: _dateBasis == DateBasis.scanDate,
    );
  }

  Future<void> _pickRange() async {
    final next = await _pickExportRange(context,
        title: 'Combined operations report range');
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
            onPressed: _showCombinedExportMenu,
          ),
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Print report',
            onPressed: _printCombinedReport,
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
        ],
      ),
      body: FutureBuilder<CombinedProjectReport>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Report failed: ${snapshot.error}'));
          }
          final report = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              buildPageTitleBanner(
                context,
                title: 'Combined report and exports',
                icon: Icons.table_chart,
              ),
              const SizedBox(height: 12),
              if (report.projects.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Grand Total',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                formatAppMoney(report.grandTotal, decimals: 0),
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: colorScheme.outlineVariant,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Invoice Count',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                report.invoiceCount.toString(),
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              if (report.projects.isEmpty || report.categories.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No data in this range.'),
                  ),
                )
              else
                Card(
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(2.2),
                      1: FlexColumnWidth(1.2),
                      2: FlexColumnWidth(1.4),
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    border: TableBorder(
                      horizontalInside:
                          BorderSide(color: colorScheme.outlineVariant),
                    ),
                    children: [
                      TableRow(
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                        ),
                        children: [
                          _ReportCell(
                            'Head of Account',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                          _ReportCell(
                            'Invoice Count',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onPrimaryContainer,
                            ),
                            alignRight: true,
                          ),
                          _ReportCell(
                            'Amount',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onPrimaryContainer,
                            ),
                            alignRight: true,
                          ),
                        ],
                      ),
                      for (final category in report.categories)
                        TableRow(
                          children: [
                            _ReportCell(
                              category,
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontSize: 14,
                              ),
                            ),
                            _ReportCell(
                              (report.invoiceCountByCategory[category] ?? 0)
                                  .toString(),
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontSize: 14,
                              ),
                              alignRight: true,
                            ),
                            _ReportCell(
                              _money(
                                report.projects.fold<double>(
                                  0,
                                  (sum, p) =>
                                      sum +
                                      (report.grossByCategoryProject[category]
                                              ?[p.id] ??
                                          0),
                                ),
                              ),
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontSize: 14,
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
                          const _ReportCell(
                            'Total',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          _ReportCell(
                            report.invoiceCount.toString(),
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w800,
                            ),
                            alignRight: true,
                          ),
                          _ReportCell(
                            _money(report.grandTotal),
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w800,
                            ),
                            alignRight: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showCombinedExportMenu() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Share combined report'),
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
      const SnackBar(content: Text('Building combined export...')),
    );

    final report = await DatabaseService.getCombinedProjectReport(
      from: _range.from,
      to: _range.to,
      useScanDate: _dateBasis == DateBasis.scanDate,
    );
    final result = await ExportService.shareCombinedReportSummary(
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

  Future<void> _printCombinedReport() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preparing combined report for print...')),
    );
    try {
      final report = await _future;
      final pdfBytes = await ExportService.buildCombinedSummaryPdfBytes(
        report: report,
        range: _range,
        dateBasis: _dateBasis,
      );
      if (!mounted) return;
      await openInAppPrintPreview(
        context,
        title: 'Print combined report',
        fileName: 'combined_report_${_range.label}.pdf',
        pdfBytes: pdfBytes,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print failed: $e')),
      );
    }
  }

  String _money(double value) => formatAppMoney(value, decimals: 0);

  String _moneyOrDash(double value) {
    if (value.abs() < 0.005) return '-';
    return _money(value);
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
