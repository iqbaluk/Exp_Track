// ============================================================
// Export Service - CSV / zipped photo export
// ============================================================
// Workflow:
//   1. User picks date range (today / week / month / custom / all)
//   2. We query matching receipts
//   3. Generate CSV file (Category-first column order)
//   4. Open Android share sheet with reliable attachments:
//      CSV-only shares a CSV; photos are bundled in a ZIP.
//   5. User picks OneDrive / WhatsApp / etc.
// ============================================================

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'database_service.dart';

class ExportRange {
  final DateTime from;
  final DateTime to;
  final String label;
  ExportRange(this.from, this.to, this.label);

  static ExportRange today() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return ExportRange(start, start, 'today');
  }

  static ExportRange thisWeek() {
    final now = DateTime.now();
    final daysFromMonday = now.weekday - 1;
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: daysFromMonday));
    return ExportRange(
        start, DateTime(now.year, now.month, now.day), 'this_week');
  }

  static ExportRange thisMonth() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    return ExportRange(
        start, DateTime(now.year, now.month, now.day), 'this_month');
  }

  static ExportRange lastMonth() {
    final now = DateTime.now();
    final firstOfThisMonth = DateTime(now.year, now.month, 1);
    final lastOfLastMonth = firstOfThisMonth.subtract(const Duration(days: 1));
    final firstOfLastMonth =
        DateTime(lastOfLastMonth.year, lastOfLastMonth.month, 1);
    return ExportRange(firstOfLastMonth, lastOfLastMonth, 'last_month');
  }

  static ExportRange thisYear() {
    final now = DateTime.now();
    return ExportRange(DateTime(now.year, 1, 1), now, 'this_year_${now.year}');
  }

  static ExportRange allTime() {
    return ExportRange(
      DateTime(2000, 1, 1),
      DateTime(2100, 1, 1),
      'all_time',
    );
  }

  static ExportRange custom(DateTime from, DateTime to) {
    final label =
        '${DateFormat('yyyyMMdd').format(from)}_to_${DateFormat('yyyyMMdd').format(to)}';
    return ExportRange(from, to, label);
  }
}

enum ExportContent {
  /// Just the CSV table
  csvOnly,

  /// Just the photos (no CSV)
  photosOnly,

  /// CSV + photos (typical full export)
  both,
}

/// Which date to use when filtering the export range.
enum DateBasis {
  /// The invoice/transaction date (the date on the receipt itself).
  /// Best for accounting / VAT periods.
  invoiceDate,

  /// The scan date (when the receipt was added to the app).
  /// Best for catching backdated entries / "what did I scan this week".
  scanDate,
}

class ExportResult {
  final bool success;
  final int recordCount;
  final int photoCount;
  final String? errorMessage;
  ExportResult.success(this.recordCount, this.photoCount)
      : success = true,
        errorMessage = null;
  ExportResult.failure(this.errorMessage)
      : success = false,
        recordCount = 0,
        photoCount = 0;
}

class ExportService {
  /// Build the export and open the Android share sheet.
  static Future<ExportResult> exportAndShare(
    ExportRange range, {
    ExportContent content = ExportContent.both,
    DateBasis dateBasis = DateBasis.scanDate,
    int? projectId,
    String? projectName,
    List<Receipt>? explicitReceipts,
  }) async {
    try {
      final ownerName = await _reportOwnerName();
      final receipts = explicitReceipts ??
          (dateBasis == DateBasis.scanDate
              ? await DatabaseService.getByScanDateRange(
                  range.from,
                  range.to,
                  projectId: projectId,
                )
              : await DatabaseService.getByDateRange(
                  range.from,
                  range.to,
                  projectId: projectId,
                ));

      if (receipts.isEmpty) {
        return ExportResult.failure(
          'No receipts found in the selected range.',
        );
      }

      final filesToShare = <XFile>[];
      String? csvPath;
      var photoCount = 0;

      // ---- CSV ----
      if (content != ExportContent.photosOnly) {
        csvPath = await _buildCsv(
          receipts,
          range,
          dateBasis,
          ownerName: ownerName,
          projectName: projectName,
        );
      }

      if (content == ExportContent.csvOnly) {
        final csvFile = File(csvPath!);
        if (!await csvFile.exists()) {
          return ExportResult.failure('CSV file was not created.');
        }
        filesToShare.add(XFile(csvPath, mimeType: 'text/csv'));
      } else {
        final photoFiles = await _existingPhotoFiles(receipts);
        photoCount = photoFiles.length;
        if (csvPath != null) {
          final csvFile = File(csvPath);
          if (await csvFile.exists()) {
            filesToShare.add(XFile(csvPath, mimeType: 'text/csv'));
          }
        }
        if (photoFiles.isEmpty) {
          if (content == ExportContent.photosOnly) {
            return ExportResult.failure(
              'No saved receipt photos found in the selected range.',
            );
          }
        } else {
          final zipPath = await _buildZip(
            photoFiles,
            range,
            dateBasis,
            projectName: projectName,
          );
          final zipFile = File(zipPath);
          if (!await zipFile.exists()) {
            return ExportResult.failure('Photo ZIP file was not created.');
          }
          filesToShare.add(XFile(zipPath, mimeType: 'application/zip'));
        }
      }

      if (filesToShare.isEmpty) {
        return ExportResult.failure(
            'Nothing to export - no CSV or photos prepared.');
      }

      // ---- Open share sheet ----
      final result = await Share.shareXFiles(
        filesToShare,
        subject: 'Receipt export - ${_friendlyLabel(range)}',
      );

      if (result.status == ShareResultStatus.unavailable) {
        return ExportResult.failure('Sharing not available on this device.');
      }

      return ExportResult.success(receipts.length, photoCount);
    } catch (e) {
      return ExportResult.failure('Export failed: ${e.toString()}');
    }
  }

  /// Build a CSV file in the app's temp directory and return its path.
  /// Filename: receipts_<range_label>_<basis>_<timestamp>.csv
  static Future<String> _buildCsv(
    List<Receipt> receipts,
    ExportRange range,
    DateBasis basis, {
    required String ownerName,
    String? projectName,
  }) async {
    final csv = StringBuffer();
    csv.writeln('Client,${_csvEscape(ownerName)}');
    csv.writeln('Range,${_friendlyLabel(range)}');
    csv.writeln(
        'Date basis,${basis == DateBasis.scanDate ? "Scan date" : "Invoice date"}');
    if (projectName != null && projectName.trim().isNotEmpty) {
      csv.writeln('Report,${_csvEscape(projectName)}');
    }
    csv.writeln('');

    // Column order: Category before Supplier (for filtering),
    // BOTH dates included so accountant sees the full picture.
    csv.writeln(
      'ScanNo,InvoiceNo,ExpenseCategory,InvoiceDate,ScanDate,Supplier,Net,VAT,Gross,Notes,PhotoFile',
    );

    for (final r in receipts) {
      final photoFile = r.photoPath != null ? p.basename(r.photoPath!) : '';
      csv.writeln([
        (r.scanNo ?? 0).toString().padLeft(5, '0'),
        _csvEscape(r.invoiceNumber ?? ''),
        _csvEscape(r.category),
        Receipt.formatDate(r.date),
        Receipt.formatDate(r.createdAt),
        _csvEscape(r.supplier),
        r.net.toStringAsFixed(2),
        r.vat.toStringAsFixed(2),
        r.gross.toStringAsFixed(2),
        _csvEscape(r.notes ?? ''),
        _csvEscape(photoFile),
      ].join(','));
    }

    final exportDir = await _exportDir();
    final ts = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final basisTag = basis == DateBasis.scanDate ? 'byScan' : 'byInvoice';
    final projectTag = projectName == null ? null : _filenameTag(projectName);
    final filenameBase = [
      'receipts',
      if (projectTag != null) projectTag,
      range.label,
      basisTag,
      ts,
    ].join('_');
    final csvPath = p.join(
      exportDir.path,
      '$filenameBase.csv',
    );
    await File(csvPath).writeAsString(csv.toString());
    return csvPath;
  }

  static Future<List<File>> _existingPhotoFiles(List<Receipt> receipts) async {
    final files = <File>[];
    for (final r in receipts) {
      final photoPath = r.photoPath;
      if (photoPath == null || photoPath.trim().isEmpty) continue;
      final file = File(photoPath);
      if (await file.exists()) {
        files.add(file);
      }
    }
    return files;
  }

  static Future<String> _buildZip(
    List<File> photoFiles,
    ExportRange range,
    DateBasis basis, {
    String? projectName,
  }) async {
    final exportDir = await _exportDir();
    final ts = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final basisTag = basis == DateBasis.scanDate ? 'byScan' : 'byInvoice';
    final projectTag = projectName == null ? null : _filenameTag(projectName);
    final filenameBase = [
      'receipt_export',
      if (projectTag != null) projectTag,
      range.label,
      basisTag,
      ts,
    ].join('_');
    final zipPath = p.join(exportDir.path, '$filenameBase.zip');

    final usedNames = <String>{};
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    try {
      for (final file in photoFiles) {
        await encoder.addFile(
          file,
          _uniqueZipEntryName('photos/${p.basename(file.path)}', usedNames),
        );
      }
    } finally {
      await encoder.close();
    }
    return zipPath;
  }

  static String _uniqueZipEntryName(String name, Set<String> usedNames) {
    final normalized = name.replaceAll('\\', '/');
    if (usedNames.add(normalized)) return normalized;

    final dir = p.posix.dirname(normalized);
    final basename = p.posix.basenameWithoutExtension(normalized);
    final extension = p.posix.extension(normalized);
    var counter = 2;
    while (true) {
      final nextBase = '$basename-$counter$extension';
      final next = dir == '.' ? nextBase : '$dir/$nextBase';
      if (usedNames.add(next)) return next;
      counter++;
    }
  }

  static Future<Directory> _exportDir() async {
    final tempDir = await getTemporaryDirectory();
    final exportDir = Directory(p.join(tempDir.path, 'exports'));
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    return exportDir;
  }

  static String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  static String _friendlyLabel(ExportRange r) {
    switch (r.label) {
      case 'today':
        return 'Today (${DateFormat('dd MMM yyyy').format(r.from)})';
      case 'this_week':
        return 'This week';
      case 'this_month':
        return DateFormat('MMMM yyyy').format(r.from);
      case 'last_month':
        return DateFormat('MMMM yyyy').format(r.from);
      case 'all_time':
        return 'All receipts';
      default:
        if (r.label.startsWith('this_year')) {
          return 'Year ${r.from.year}';
        }
        return '${DateFormat('dd/MM/yy').format(r.from)} - ${DateFormat('dd/MM/yy').format(r.to)}';
    }
  }

  static String _filenameTag(String value) {
    var tag = value.trim().replaceAll('&', 'and');
    tag = tag.replaceAll(RegExp(r'[<>:"/\\|?*]'), '');
    tag = tag.replaceAll(RegExp(r'\s+'), '');
    tag = tag.replaceAll(RegExp(r'[^A-Za-z0-9\-.]'), '');
    if (tag.isEmpty) return 'operation';
    if (tag.length > 30) return tag.substring(0, 30);
    return tag;
  }

  static Future<ExportResult> shareProjectReportSummary({
    required Project project,
    required ProjectReport report,
    required ExportRange range,
    required DateBasis dateBasis,
    bool summaryAsPdf = false,
    bool includeTransactions = false,
    bool includePhotos = false,
  }) async {
    try {
      final ownerName = await _reportOwnerName();
      final filesToShare = <XFile>[];
      final summaryPath = summaryAsPdf
          ? await _buildProjectSummaryPdf(
              ownerName: ownerName,
              project: project,
              report: report,
              range: range,
              basis: dateBasis,
            )
          : await _buildProjectSummaryCsv(
              ownerName: ownerName,
              project: project,
              report: report,
              range: range,
              basis: dateBasis,
            );
      filesToShare.add(
        XFile(
          summaryPath,
          mimeType: summaryAsPdf ? 'application/pdf' : 'text/csv',
        ),
      );

      var receiptCount = report.receiptCount;
      var photoCount = 0;
      if (includeTransactions || includePhotos) {
        final receipts = dateBasis == DateBasis.scanDate
            ? await DatabaseService.getByScanDateRange(
                range.from,
                range.to,
                projectId: project.id,
              )
            : await DatabaseService.getByDateRange(
                range.from,
                range.to,
                projectId: project.id,
              );
        receiptCount = receipts.length;
        if (includeTransactions && receipts.isNotEmpty) {
          final txCsv = await _buildCsv(
            receipts,
            range,
            dateBasis,
            ownerName: ownerName,
            projectName: project.name,
          );
          filesToShare.add(XFile(txCsv, mimeType: 'text/csv'));
        }
        if (includePhotos) {
          final photoFiles = await _existingPhotoFiles(receipts);
          photoCount = photoFiles.length;
          if (photoFiles.isNotEmpty) {
            final zipPath = await _buildZip(
              photoFiles,
              range,
              dateBasis,
              projectName: project.name,
            );
            filesToShare.add(XFile(zipPath, mimeType: 'application/zip'));
          }
        }
      }

      final result = await Share.shareXFiles(
        filesToShare,
        subject: 'Operation report - ${project.name}',
      );
      if (result.status == ShareResultStatus.unavailable) {
        return ExportResult.failure('Sharing not available on this device.');
      }
      return ExportResult.success(receiptCount, photoCount);
    } catch (e) {
      return ExportResult.failure('Export failed: ${e.toString()}');
    }
  }

  static Future<ExportResult> shareCombinedReportSummary({
    required CombinedProjectReport report,
    required ExportRange range,
    required DateBasis dateBasis,
    bool summaryAsPdf = false,
    bool includeTransactions = false,
    bool includePhotos = false,
  }) async {
    try {
      final ownerName = await _reportOwnerName();
      final filesToShare = <XFile>[];
      final summaryPath = summaryAsPdf
          ? await _buildCombinedSummaryPdf(
              ownerName: ownerName,
              report: report,
              range: range,
              basis: dateBasis,
            )
          : await _buildCombinedSummaryCsv(
              ownerName: ownerName,
              report: report,
              range: range,
              basis: dateBasis,
            );
      filesToShare.add(
        XFile(
          summaryPath,
          mimeType: summaryAsPdf ? 'application/pdf' : 'text/csv',
        ),
      );

      var receiptCount = report.invoiceCount;
      var photoCount = 0;
      if (includeTransactions || includePhotos) {
        final receipts = dateBasis == DateBasis.scanDate
            ? await DatabaseService.getByScanDateRange(range.from, range.to)
            : await DatabaseService.getByDateRange(range.from, range.to);
        receiptCount = receipts.length;
        if (includeTransactions && receipts.isNotEmpty) {
          final txCsv = await _buildCsv(
            receipts,
            range,
            dateBasis,
            ownerName: ownerName,
            projectName: 'Combined',
          );
          filesToShare.add(XFile(txCsv, mimeType: 'text/csv'));
        }
        if (includePhotos) {
          final photoFiles = await _existingPhotoFiles(receipts);
          photoCount = photoFiles.length;
          if (photoFiles.isNotEmpty) {
            final zipPath = await _buildZip(
              photoFiles,
              range,
              dateBasis,
              projectName: 'Combined',
            );
            filesToShare.add(XFile(zipPath, mimeType: 'application/zip'));
          }
        }
      }

      final result = await Share.shareXFiles(
        filesToShare,
        subject: 'Combined operations report - ${_friendlyLabel(range)}',
      );
      if (result.status == ShareResultStatus.unavailable) {
        return ExportResult.failure('Sharing not available on this device.');
      }
      return ExportResult.success(receiptCount, photoCount);
    } catch (e) {
      return ExportResult.failure('Export failed: ${e.toString()}');
    }
  }

  static Future<Uint8List> buildProjectSummaryPdfBytes({
    required Project project,
    required ProjectReport report,
    required ExportRange range,
    required DateBasis dateBasis,
  }) async {
    final ownerName = await _reportOwnerName();
    final path = await _buildProjectSummaryPdf(
      ownerName: ownerName,
      project: project,
      report: report,
      range: range,
      basis: dateBasis,
    );
    return File(path).readAsBytes();
  }

  static Future<Uint8List> buildCombinedSummaryPdfBytes({
    required CombinedProjectReport report,
    required ExportRange range,
    required DateBasis dateBasis,
  }) async {
    final ownerName = await _reportOwnerName();
    final path = await _buildCombinedSummaryPdf(
      ownerName: ownerName,
      report: report,
      range: range,
      basis: dateBasis,
    );
    return File(path).readAsBytes();
  }

  static Future<ExportResult> shareMonthlyReportSummary({
    required MonthlyFiscalActivityReport report,
    required DateBasis dateBasis,
    required String scopeName,
    int? projectId,
    bool summaryAsPdf = false,
    bool includeTransactions = false,
    bool includePhotos = false,
  }) async {
    try {
      final ownerName = await _reportOwnerName();
      final filesToShare = <XFile>[];
      final range = ExportRange.custom(report.from, report.to);
      final summaryPath = summaryAsPdf
          ? await _buildMonthlySummaryPdf(
              ownerName: ownerName,
              report: report,
              dateBasis: dateBasis,
              scopeName: scopeName,
            )
          : await _buildMonthlySummaryCsv(
              ownerName: ownerName,
              report: report,
              dateBasis: dateBasis,
              scopeName: scopeName,
            );
      filesToShare.add(
        XFile(
          summaryPath,
          mimeType: summaryAsPdf ? 'application/pdf' : 'text/csv',
        ),
      );

      var receiptCount = report.invoiceCount;
      var photoCount = 0;
      if (includeTransactions || includePhotos) {
        final receipts = dateBasis == DateBasis.scanDate
            ? await DatabaseService.getByScanDateRange(
                report.from,
                report.to,
                projectId: projectId,
              )
            : await DatabaseService.getByDateRange(
                report.from,
                report.to,
                projectId: projectId,
              );
        receiptCount = receipts.length;
        if (includeTransactions && receipts.isNotEmpty) {
          final txCsv = await _buildCsv(
            receipts,
            range,
            dateBasis,
            ownerName: ownerName,
            projectName: scopeName,
          );
          filesToShare.add(XFile(txCsv, mimeType: 'text/csv'));
        }
        if (includePhotos) {
          final photoFiles = await _existingPhotoFiles(receipts);
          photoCount = photoFiles.length;
          if (photoFiles.isNotEmpty) {
            final zipPath = await _buildZip(
              photoFiles,
              range,
              dateBasis,
              projectName: scopeName,
            );
            filesToShare.add(XFile(zipPath, mimeType: 'application/zip'));
          }
        }
      }

      final result = await Share.shareXFiles(
        filesToShare,
        subject: 'Monthly activity report - $scopeName',
      );
      if (result.status == ShareResultStatus.unavailable) {
        return ExportResult.failure('Sharing not available on this device.');
      }
      return ExportResult.success(receiptCount, photoCount);
    } catch (e) {
      return ExportResult.failure('Export failed: ${e.toString()}');
    }
  }

  static Future<Uint8List> buildMonthlySummaryPdfBytes({
    required MonthlyFiscalActivityReport report,
    required DateBasis dateBasis,
    required String scopeName,
  }) async {
    final ownerName = await _reportOwnerName();
    final path = await _buildMonthlySummaryPdf(
      ownerName: ownerName,
      report: report,
      dateBasis: dateBasis,
      scopeName: scopeName,
    );
    return File(path).readAsBytes();
  }

  static Future<Uint8List> buildInvoiceListPdfBytes({
    required List<Receipt> receipts,
    required ExportRange range,
    required DateBasis dateBasis,
    String? projectName,
  }) async {
    final ownerName = await _reportOwnerName();
    final pdf = pw.Document();
    final headers = ['Date', 'Supplier', 'Category', 'Gross'];
    final rows = <List<String>>[
      for (final r in receipts)
        [
          DateFormat('dd/MM/yy').format(
            dateBasis == DateBasis.scanDate ? r.createdAt : r.date,
          ),
          r.supplier,
          r.category,
          NumberFormat('#,##0.##').format(r.gross),
        ],
      [
        'Total',
        '',
        '',
        NumberFormat('#,##0.##')
            .format(receipts.fold<double>(0, (sum, r) => sum + r.gross)),
      ],
    ];
    final colWidths = _contentFlexColumnWidths(headers, rows);
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          pw.Text(
            'Invoice List',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Client: $ownerName',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          if (projectName != null && projectName.trim().isNotEmpty)
            pw.Text('Operation: $projectName'),
          pw.Text('Range: ${_friendlyLabel(range)}'),
          pw.Text(
            'Basis: ${dateBasis == DateBasis.scanDate ? "Scan date" : "Invoice date"}',
          ),
          pw.SizedBox(height: 10),
          _buildStyledPdfTable(
            headers: headers,
            rows: rows,
            rightAlignedColumns: const {3},
            totalRowIndex: rows.length - 1,
            columnWidths: colWidths,
          ),
        ],
      ),
    );
    return pdf.save();
  }

  static Future<String> _buildMonthlySummaryCsv({
    required String ownerName,
    required MonthlyFiscalActivityReport report,
    required DateBasis dateBasis,
    required String scopeName,
  }) async {
    final csv = StringBuffer();
    csv.writeln('Client,${_csvEscape(ownerName)}');
    csv.writeln('Report,Monthly activity');
    csv.writeln('Scope,${_csvEscape(scopeName)}');
    csv.writeln(
      'Financial year,${DateFormat('dd MMM yyyy').format(report.from)} - ${DateFormat('dd MMM yyyy').format(report.to)}',
    );
    csv.writeln(
        'Date basis,${dateBasis == DateBasis.scanDate ? "Scan date" : "Invoice date"}');
    csv.writeln('');

    final visibleMonthIndexes = <int>[
      for (var i = 0; i < report.monthTotals.length; i++)
        if (report.monthTotals[i] > 0) i
    ];
    final visibleCategories = DatabaseService.sortCategoryNames(
      report.categories.where((c) => (report.categoryTotals[c] ?? 0) > 0),
    );
    final monthLabels = [
      for (final idx in visibleMonthIndexes)
        DateFormat('MMM-yy').format(report.months[idx]),
    ];
    final headers = <String>['Details', ...monthLabels, 'Total'];
    csv.writeln(headers.map(_csvEscape).join(','));

    for (final category in visibleCategories) {
      final row = <String>[category];
      for (final monthIndex in visibleMonthIndexes) {
        row.add(
          (report.categoryMonthGross[category]?[monthIndex] ?? 0)
              .toStringAsFixed(2),
        );
      }
      row.add((report.categoryTotals[category] ?? 0).toStringAsFixed(2));
      csv.writeln(row.map(_csvEscape).join(','));
    }

    final totalRow = <String>['Total'];
    for (final monthIndex in visibleMonthIndexes) {
      totalRow.add(report.monthTotals[monthIndex].toStringAsFixed(2));
    }
    totalRow.add(report.grandTotal.toStringAsFixed(2));
    csv.writeln(totalRow.map(_csvEscape).join(','));

    final exportDir = await _exportDir();
    final ts = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final basisTag = dateBasis == DateBasis.scanDate ? 'byScan' : 'byInvoice';
    final scopeTag = _filenameTag(scopeName);
    final path = p.join(
      exportDir.path,
      'monthly_summary_${scopeTag}_${basisTag}_$ts.csv',
    );
    await File(path).writeAsString(csv.toString());
    return path;
  }

  static Future<String> _buildMonthlySummaryPdf({
    required String ownerName,
    required MonthlyFiscalActivityReport report,
    required DateBasis dateBasis,
    required String scopeName,
  }) async {
    final pdf = pw.Document();
    final money = NumberFormat('#,##0.##');
    final visibleMonthIndexes = <int>[
      for (var i = 0; i < report.monthTotals.length; i++)
        if (report.monthTotals[i] > 0) i
    ];
    final visibleCategories = DatabaseService.sortCategoryNames(
      report.categories.where((c) => (report.categoryTotals[c] ?? 0) > 0),
    );

    final headers = <String>[
      'Details',
      for (final idx in visibleMonthIndexes)
        DateFormat('MMM-yy').format(report.months[idx]),
      'Total',
    ];
    final rows = <List<String>>[
      for (final category in visibleCategories)
        [
          category,
          for (final monthIndex in visibleMonthIndexes)
            money.format(report.categoryMonthGross[category]?[monthIndex] ?? 0),
          money.format(report.categoryTotals[category] ?? 0),
        ],
      [
        'Total',
        for (final monthIndex in visibleMonthIndexes)
          money.format(report.monthTotals[monthIndex]),
        money.format(report.grandTotal),
      ],
    ];
    final colWidths = _contentFlexColumnWidths(headers, rows);
    final rightAligned = <int>{for (var i = 1; i < headers.length; i++) i};

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => [
          pw.Text(
            'Monthly Activity Report',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Client: $ownerName',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Scope: $scopeName'),
          pw.Text(
            'Financial year: ${DateFormat('dd MMM yyyy').format(report.from)} - ${DateFormat('dd MMM yyyy').format(report.to)}',
          ),
          pw.Text(
              'Basis: ${dateBasis == DateBasis.scanDate ? "Scan date" : "Invoice date"}'),
          pw.SizedBox(height: 12),
          _buildStyledPdfTable(
            headers: headers,
            rows: rows,
            rightAlignedColumns: rightAligned,
            totalRowIndex: rows.length - 1,
            columnWidths: colWidths,
          ),
        ],
      ),
    );
    final exportDir = await _exportDir();
    final ts = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final basisTag = dateBasis == DateBasis.scanDate ? 'byScan' : 'byInvoice';
    final scopeTag = _filenameTag(scopeName);
    final path = p.join(
      exportDir.path,
      'monthly_summary_${scopeTag}_${basisTag}_$ts.pdf',
    );
    await File(path).writeAsBytes(await pdf.save());
    return path;
  }

  static Future<String> _buildProjectSummaryCsv({
    required String ownerName,
    required Project project,
    required ProjectReport report,
    required ExportRange range,
    required DateBasis basis,
  }) async {
    final csv = StringBuffer();
    csv.writeln('Client,${_csvEscape(ownerName)}');
    csv.writeln('Operation,${_csvEscape(project.name)}');
    csv.writeln('Range,${_friendlyLabel(range)}');
    csv.writeln(
        'Date basis,${basis == DateBasis.scanDate ? "Scan date" : "Invoice date"}');
    csv.writeln('');
    csv.writeln('Expense Category,Inv count,Gross');
    for (final c in report.categories) {
      csv.writeln(
        '${_csvEscape(c.category)},${c.receiptCount},${c.totalGross.toStringAsFixed(2)}',
      );
    }
    csv.writeln(
        'Total,${report.receiptCount},${report.totalGross.toStringAsFixed(2)}');
    final exportDir = await _exportDir();
    final ts = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final basisTag = basis == DateBasis.scanDate ? 'byScan' : 'byInvoice';
    final projectTag = _filenameTag(project.name);
    final path = p.join(
      exportDir.path,
      'operation_summary_${projectTag}_${range.label}_${basisTag}_$ts.csv',
    );
    await File(path).writeAsString(csv.toString());
    return path;
  }

  static Future<String> _buildCombinedSummaryCsv({
    required String ownerName,
    required CombinedProjectReport report,
    required ExportRange range,
    required DateBasis basis,
  }) async {
    final csv = StringBuffer();
    csv.writeln('Client,${_csvEscape(ownerName)}');
    csv.writeln('Report,Combined Summary');
    csv.writeln('Range,${_friendlyLabel(range)}');
    csv.writeln(
        'Date basis,${basis == DateBasis.scanDate ? "Scan date" : "Invoice date"}');
    csv.writeln('');
    csv.writeln('Head of Account,Invoice Count,Amount');
    for (final category in report.categories) {
      final amount = report.projects.fold<double>(
        0,
        (sum, p) => sum + (report.grossByCategoryProject[category]?[p.id] ?? 0),
      );
      final count = report.invoiceCountByCategory[category] ?? 0;
      csv.writeln(
        '${_csvEscape(category)},$count,${amount.toStringAsFixed(2)}',
      );
    }
    csv.writeln(
        'Total,${report.invoiceCount},${report.grandTotal.toStringAsFixed(2)}');

    final exportDir = await _exportDir();
    final ts = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final basisTag = basis == DateBasis.scanDate ? 'byScan' : 'byInvoice';
    final path = p.join(
      exportDir.path,
      'combined_summary_${range.label}_${basisTag}_$ts.csv',
    );
    await File(path).writeAsString(csv.toString());
    return path;
  }

  static Future<String> _buildProjectSummaryPdf({
    required String ownerName,
    required Project project,
    required ProjectReport report,
    required ExportRange range,
    required DateBasis basis,
  }) async {
    final pdf = pw.Document();
    final money = NumberFormat('#,##0.##');
    final headers = ['Expense Category', 'Inv count', 'Gross'];
    final rows = <List<String>>[
      ...report.categories.map((c) => [
            c.category,
            money.format(c.receiptCount),
            money.format(c.totalGross),
          ]),
      [
        'Total',
        money.format(report.receiptCount),
        money.format(report.totalGross)
      ],
    ];
    final colWidths = _contentFlexColumnWidths(headers, rows);
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text('Operation Summary Report',
              style:
                  pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('Client: $ownerName',
              style:
                  pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text('Operation: ${project.name}'),
          pw.Text('Range: ${_friendlyLabel(range)}'),
          pw.Text(
              'Basis: ${basis == DateBasis.scanDate ? "Scan date" : "Invoice date"}'),
          pw.SizedBox(height: 12),
          _buildStyledPdfTable(
            headers: headers,
            rows: rows,
            rightAlignedColumns: const {1, 2},
            totalRowIndex: rows.length - 1,
            columnWidths: colWidths,
          ),
        ],
      ),
    );
    final exportDir = await _exportDir();
    final ts = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final basisTag = basis == DateBasis.scanDate ? 'byScan' : 'byInvoice';
    final projectTag = _filenameTag(project.name);
    final path = p.join(
      exportDir.path,
      'operation_summary_${projectTag}_${range.label}_${basisTag}_$ts.pdf',
    );
    await File(path).writeAsBytes(await pdf.save());
    return path;
  }

  static Future<String> _buildCombinedSummaryPdf({
    required String ownerName,
    required CombinedProjectReport report,
    required ExportRange range,
    required DateBasis basis,
  }) async {
    final pdf = pw.Document();
    final money = NumberFormat('#,##0.##');
    final headers = <String>['Head of Account', 'Invoice Count', 'Amount'];
    final rows = <List<String>>[];
    for (final category in report.categories) {
      final amount = report.projects.fold<double>(
        0,
        (sum, p) => sum + (report.grossByCategoryProject[category]?[p.id] ?? 0),
      );
      rows.add([
        category,
        money.format(report.invoiceCountByCategory[category] ?? 0),
        money.format(amount),
      ]);
    }
    rows.add([
      'Total',
      money.format(report.invoiceCount),
      money.format(report.grandTotal),
    ]);
    final colWidths = _contentFlexColumnWidths(headers, rows);
    final rightAligned = <int>{1, 2};

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text('Combined Summary Report',
              style:
                  pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('Client: $ownerName',
              style:
                  pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text('Range: ${_friendlyLabel(range)}'),
          pw.Text(
              'Basis: ${basis == DateBasis.scanDate ? "Scan date" : "Invoice date"}'),
          pw.SizedBox(height: 12),
          _buildStyledPdfTable(
            headers: headers,
            rows: rows,
            rightAlignedColumns: rightAligned,
            totalRowIndex: rows.length - 1,
            columnWidths: colWidths,
          ),
        ],
      ),
    );
    final exportDir = await _exportDir();
    final ts = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final basisTag = basis == DateBasis.scanDate ? 'byScan' : 'byInvoice';
    final path = p.join(
      exportDir.path,
      'combined_summary_${range.label}_${basisTag}_$ts.pdf',
    );
    await File(path).writeAsBytes(await pdf.save());
    return path;
  }

  static Map<int, pw.TableColumnWidth> _contentFlexColumnWidths(
    List<String> headers,
    List<List<String>> rows,
  ) {
    final weights = <double>[];
    for (var c = 0; c < headers.length; c++) {
      var maxLen = headers[c].length.toDouble();
      for (final row in rows) {
        if (c < row.length) {
          maxLen = math.max(maxLen, row[c].length.toDouble());
        }
      }
      // Keep sane bounds so one long value does not dominate.
      weights.add(maxLen.clamp(6, 24));
    }
    return {
      for (var i = 0; i < weights.length; i++)
        i: pw.FlexColumnWidth(weights[i]),
    };
  }

  static pw.Widget _buildStyledPdfTable({
    required List<String> headers,
    required List<List<String>> rows,
    required Set<int> rightAlignedColumns,
    required int totalRowIndex,
    required Map<int, pw.TableColumnWidth> columnWidths,
  }) {
    final tableRows = <pw.TableRow>[];

    tableRows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.cyan100),
        children: [
          for (var c = 0; c < headers.length; c++)
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                headers[c],
                textAlign: rightAlignedColumns.contains(c)
                    ? pw.TextAlign.right
                    : pw.TextAlign.left,
                style:
                    pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              ),
            ),
        ],
      ),
    );

    for (var r = 0; r < rows.length; r++) {
      final isTotal = r == totalRowIndex;
      tableRows.add(
        pw.TableRow(
          decoration:
              isTotal ? const pw.BoxDecoration(color: PdfColors.grey200) : null,
          children: [
            for (var c = 0; c < headers.length; c++)
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(
                  c < rows[r].length ? rows[r][c] : '',
                  textAlign: rightAlignedColumns.contains(c)
                      ? pw.TextAlign.right
                      : pw.TextAlign.left,
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight:
                        isTotal ? pw.FontWeight.bold : pw.FontWeight.normal,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.6),
      columnWidths: columnWidths,
      children: tableRows,
    );
  }

  static Future<String> _reportOwnerName() async {
    final profile = await DatabaseService.getCompanyProfile();
    final name = profile?.clientName.trim() ?? '';
    return name.isEmpty ? 'Client' : name;
  }
}
