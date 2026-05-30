// ============================================================
// Database Service - SQLite + smart-named photos
// ============================================================
// Photos are saved with smart filenames at save time:
//   <scan_no>_<date>_<category>_<supplier>_<amount>.jpg
//   e.g. 00042_2026-04-30_Material_BandQ_127.50.jpg
//
// Schema:
//   tbl_receipts:
//     id              INTEGER PRIMARY KEY AUTOINCREMENT
//     project_id      INTEGER   (links to tbl_projects)
//     scan_no         INTEGER UNIQUE  (sequential, starts at 1)
//     date            TEXT      (YYYY-MM-DD)
//     invoice_number  TEXT
//     category        TEXT
//     supplier        TEXT
//     vat             REAL
//     gross           REAL
//     paid_amount     REAL
//     net             REAL
//     notes           TEXT
//     photo_path      TEXT      (full path to the smart-named jpg)
//     created_at      TEXT
//     updated_at      TEXT
// ============================================================

import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'utils/text_normalizers.dart';

part 'database/schema_migrations.dart';

class Operation {
  final int? id;
  final String name;
  final String? address;
  final DateTime? startDate;
  final double? budget;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int receiptCount;
  final double totalGross;

  Operation({
    this.id,
    required this.name,
    this.address,
    this.startDate,
    this.budget,
    this.notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.receiptCount = 0,
    this.totalGross = 0,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Operation.fromMap(Map<String, dynamic> map) {
    return Operation(
      id: map['id'] as int?,
      name: map['name'] as String,
      address: map['address'] as String?,
      startDate: map['start_date'] == null
          ? null
          : DateTime.parse(map['start_date'] as String),
      budget: (map['budget'] as num?)?.toDouble(),
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      receiptCount: (map['receipt_count'] as num?)?.toInt() ?? 0,
      totalGross: (map['total_gross'] as num?)?.toDouble() ?? 0,
    );
  }
}

class Project extends Operation {
  Project({
    super.id,
    required super.name,
    super.address,
    super.startDate,
    super.budget,
    super.notes,
    super.createdAt,
    super.updatedAt,
    super.receiptCount,
    super.totalGross,
  });

  factory Project.fromMap(Map<String, dynamic> map) {
    return Project(
      id: map['id'] as int?,
      name: map['name'] as String,
      address: map['address'] as String?,
      startDate: map['start_date'] == null
          ? null
          : DateTime.parse(map['start_date'] as String),
      budget: (map['budget'] as num?)?.toDouble(),
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      receiptCount: (map['receipt_count'] as num?)?.toInt() ?? 0,
      totalGross: (map['total_gross'] as num?)?.toDouble() ?? 0,
    );
  }
}

class AppCategory {
  final int? id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  AppCategory({
    this.id,
    required this.name,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory AppCategory.fromMap(Map<String, dynamic> map) {
    return AppCategory(
      id: map['id'] as int?,
      name: map['name'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}

class CompanyProfile {
  final int id;
  final String clientName;
  final String companyCode;
  final String businessNature;
  final String businessDescription;
  final int financialYearStartMonth;
  final DateTime createdAt;
  final DateTime updatedAt;

  CompanyProfile({
    this.id = 1,
    required this.clientName,
    required this.companyCode,
    required this.businessNature,
    required this.businessDescription,
    required this.financialYearStartMonth,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'client_name': clientName,
      'company_code': companyCode,
      'business_nature': businessNature,
      'business_description': businessDescription,
      'financial_year_start_month': financialYearStartMonth,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory CompanyProfile.fromMap(Map<String, dynamic> map) {
    return CompanyProfile(
      id: (map['id'] as num?)?.toInt() ?? 1,
      clientName: map['client_name'] as String? ?? '',
      companyCode: map['company_code'] as String? ?? '',
      businessNature: map['business_nature'] as String? ?? '',
      businessDescription: map['business_description'] as String? ?? '',
      financialYearStartMonth:
          (map['financial_year_start_month'] as num?)?.toInt() ?? 4,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class CategorySummary {
  final String category;
  final int receiptCount;
  final double totalNet;
  final double totalVat;
  final double totalGross;

  CategorySummary({
    required this.category,
    required this.receiptCount,
    required this.totalNet,
    required this.totalVat,
    required this.totalGross,
  });

  factory CategorySummary.fromMap(Map<String, dynamic> map) {
    return CategorySummary(
      category: map['category'] as String,
      receiptCount: (map['receipt_count'] as num?)?.toInt() ?? 0,
      totalNet: (map['total_net'] as num?)?.toDouble() ?? 0,
      totalVat: (map['total_vat'] as num?)?.toDouble() ?? 0,
      totalGross: (map['total_gross'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ProjectReport {
  final int receiptCount;
  final double totalNet;
  final double totalVat;
  final double totalGross;
  final List<CategorySummary> categories;

  ProjectReport({
    required this.receiptCount,
    required this.totalNet,
    required this.totalVat,
    required this.totalGross,
    required this.categories,
  });
}

class CombinedProjectReport {
  final List<Project> projects;
  final List<String> categories;
  final Map<String, Map<int, double>> grossByCategoryProject;
  final Map<String, int> invoiceCountByCategory;
  final Map<int, double> projectTotals;
  final double grandTotal;
  final int invoiceCount;

  CombinedProjectReport({
    required this.projects,
    required this.categories,
    required this.grossByCategoryProject,
    required this.invoiceCountByCategory,
    required this.projectTotals,
    required this.grandTotal,
    required this.invoiceCount,
  });
}

class MonthlyFiscalActivityReport {
  final DateTime from;
  final DateTime to;
  final List<DateTime> months;
  final List<String> categories;
  final Map<String, List<double>> categoryMonthGross;
  final List<double> monthTotals;
  final Map<String, double> categoryTotals;
  final double grandTotal;
  final int invoiceCount;

  MonthlyFiscalActivityReport({
    required this.from,
    required this.to,
    required this.months,
    required this.categories,
    required this.categoryMonthGross,
    required this.monthTotals,
    required this.categoryTotals,
    required this.grandTotal,
    required this.invoiceCount,
  });
}

class Receipt {
  final int? id;
  final int? operationId;
  final int? scanNo;
  final DateTime date;
  final String? invoiceNumber;
  final String category;
  final String supplier;
  final double vat;
  final double gross;
  final double paidAmount;
  final double net;
  final String? notes;
  final String? photoPath;
  final DateTime createdAt;
  final DateTime updatedAt;

  Receipt({
    this.id,
    int? operationId,
    int? projectId,
    this.scanNo,
    required this.date,
    this.invoiceNumber,
    required this.category,
    required this.supplier,
    required this.vat,
    required this.gross,
    required this.paidAmount,
    required this.net,
    this.notes,
    this.photoPath,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : operationId = operationId ?? projectId,
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  @Deprecated('Use operationId')
  int? get projectId => operationId;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (operationId != null) 'project_id': operationId,
      if (scanNo != null) 'scan_no': scanNo,
      'date': formatDate(date),
      'invoice_number': invoiceNumber,
      'normalized_invoice': normalizeInvoiceNumber(invoiceNumber),
      'supplier': supplier,
      'normalized_supplier': normalizeSupplier(supplier),
      'vat': vat,
      'gross': gross,
      'paid_amount': paidAmount,
      'net': net,
      'notes': notes,
      'photo_path': photoPath,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Receipt.fromMap(Map<String, dynamic> map) {
    final mappedCategory = (map['category'] as String?)?.trim();
    return Receipt(
      id: map['id'] as int?,
      operationId: map['project_id'] as int?,
      scanNo: map['scan_no'] as int?,
      date: DateTime.parse(map['date'] as String),
      invoiceNumber: map['invoice_number'] as String?,
      category: (mappedCategory == null || mappedCategory.isEmpty)
          ? 'Uncategorized'
          : mappedCategory,
      supplier: map['supplier'] as String,
      vat: (map['vat'] as num).toDouble(),
      gross: (map['gross'] as num).toDouble(),
      paidAmount: (map['paid_amount'] as num?)?.toDouble() ??
          (map['gross'] as num).toDouble(),
      net: (map['net'] as num).toDouble(),
      notes: map['notes'] as String?,
      photoPath: map['photo_path'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Receipt copyWith({
    int? id,
    int? operationId,
    int? projectId,
    int? scanNo,
    DateTime? date,
    String? invoiceNumber,
    String? category,
    String? supplier,
    double? vat,
    double? gross,
    double? paidAmount,
    double? net,
    String? notes,
    String? photoPath,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Receipt(
      id: id ?? this.id,
      operationId: operationId ?? projectId ?? this.operationId,
      scanNo: scanNo ?? this.scanNo,
      date: date ?? this.date,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      category: category ?? this.category,
      supplier: supplier ?? this.supplier,
      vat: vat ?? this.vat,
      gross: gross ?? this.gross,
      paidAmount: paidAmount ?? this.paidAmount,
      net: net ?? this.net,
      notes: notes ?? this.notes,
      photoPath: photoPath ?? this.photoPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String formatDate(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  double get savingsAmount => gross - paidAmount;

  /// Build the smart filename for this receipt.
  /// Pattern: NNNNN_YYYY-MM-DD_Category_Supplier_AMOUNT.jpg
  String buildSmartFilename({String ext = 'jpg'}) {
    final scan = (scanNo ?? 0).toString().padLeft(5, '0');
    final dateStr = formatDate(date);
    final cat = _sanitizeForFilename(category);
    final sup = _sanitizeForFilename(supplier);
    final amt = gross.toStringAsFixed(2);
    return '${scan}_${dateStr}_${cat}_${sup}_$amt.$ext';
  }

  /// Sanitise a string for use in a filename:
  /// - Replace & with "and"
  /// - Remove characters that are invalid in filenames
  /// - Trim and replace spaces with nothing (keep readable but compact)
  static String _sanitizeForFilename(String input) {
    var s = input.trim();
    s = s.replaceAll('&', 'and');
    // Remove invalid filename characters: < > : " / \ | ? *
    s = s.replaceAll(RegExp(r'[<>:"/\\|?*]'), '');
    // Replace spaces with nothing for compact names (BandQ, TravisPerkins)
    s = s.replaceAll(' ', '');
    // Strip non-alphanumeric (allow hyphen and dot)
    s = s.replaceAll(RegExp(r'[^A-Za-z0-9\-.]'), '');
    if (s.isEmpty) s = 'unknown';
    // Cap length so filenames don't get silly
    if (s.length > 30) s = s.substring(0, 30);
    return s;
  }
}

class DatabaseService {
  static const String _dbName = 'receipt_scanner.db';
  static const String _table = 'tbl_receipts';
  static const String _projectsTable = 'tbl_projects';
  static const String _categoriesTable = 'tbl_categories';
  static const String _companyTable = 'tbl_company_profile';
  static const int _dbVersion = 35;
  static const String _combinedReportView = 'vw_receipt_project_matrix';
  static const List<String> fixedOperationHeads = <String>[
    'Purchases',
    'labour / Sub_Contractor',
    'Rent & Bills',
    'Travel & Food',
    'Office Exp',
    'Professional Fee',
    'Miscellaneous',
  ];

  static final List<String> defaultCategories =
      List<String>.from(mainCategories);

  static final List<String> categoryPnlOrder = defaultCategories;

  static String _normalizeCategoryKey(String category) {
    final key = category.trim().toLowerCase();
    switch (key) {
      case 'purchase':
      case 'purchases':
      case 'material':
      case 'material purchase':
      case 'material purchases':
        return 'purchases';
      case 'labour':
      case 'labor':
      case 'gross wages':
      case 'labour / subcontractor':
      case 'labour/subcontractor':
      case 'staff and contractors':
      case 'staff & contractors':
      case 'subcontractor':
      case 'salary':
        return 'labour / sub_contractor';
      case 'rent & rates':
      case 'rent and rates':
      case 'rent & rate':
      case 'rates and rent':
      case 'rent':
      case 'rates':
      case 'rent and rates':
      case 'rent & rates':
        return 'rent & bills';
      case 'utilities':
      case 'utility bills':
      case 'utility':
        return 'rent & bills';
      case 'travel':
      case 'travelling':
      case 'travel and hotel':
      case 'subsistence':
        return 'travel & food';
      case 'food & subsistence':
      case 'food and subsistence':
      case 'food':
        return 'travel & food';
      case 'office admin':
      case 'telephone':
      case 'computer':
        return 'office exp';
      case 'repair':
      case 'repair & maintenance':
      case 'repair and maintenance':
      case 'maintenance':
      case 'general expenses':
        return 'miscellaneous';
      case 'marketing':
      case 'advertisement':
        return 'miscellaneous';
      case 'bank charges and interest':
      case 'bank charges':
      case 'interest':
      case 'fee':
      case 'fees':
      case 'professional fees':
        return 'professional fee';
      case 'depreciation':
      case 'bad debts':
      case 'bad debt':
        return 'miscellaneous';
      case 'sundries':
        return 'miscellaneous';
      case 'donations & charity':
      case 'charity':
      case 'charity donation':
        return 'miscellaneous';
      default:
        return key;
    }
  }

  static int _categoryRank(String category) {
    final key = _normalizeCategoryKey(category);
    for (var i = 0; i < categoryPnlOrder.length; i++) {
      if (_normalizeCategoryKey(categoryPnlOrder[i]) == key) {
        return i;
      }
    }
    return categoryPnlOrder.length + 100;
  }

  static int compareCategoryNames(String a, String b) {
    final byRank = _categoryRank(a).compareTo(_categoryRank(b));
    if (byRank != 0) return byRank;
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  static List<String> sortCategoryNames(
    Iterable<String> categories, {
    Map<String, double>? grossTotals,
    bool byGrossDesc = false,
  }) {
    final names = categories
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
    names.sort((a, b) {
      if (byGrossDesc) {
        final aGross = grossTotals?[a] ?? 0;
        final bGross = grossTotals?[b] ?? 0;
        final grossCmp = bGross.compareTo(aGross);
        if (grossCmp != 0) return grossCmp;
      }
      return compareCategoryNames(a, b);
    });
    return names;
  }

  static Database? _db;

  static Future<String> getDatabasePath() async {
    final docDir = await getApplicationDocumentsDirectory();
    return p.join(docDir.path, _dbName);
  }

  static Future<Database> _open() async {
    if (_db != null) return _db!;

    final path = await getDatabasePath();

    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _createProjectsTable(db);
        await _createCompanyProfileTable(db);
        await db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_id INTEGER,
            scan_no INTEGER UNIQUE,
            date TEXT NOT NULL,
            invoice_number TEXT,
            normalized_invoice TEXT NOT NULL DEFAULT '',
            supplier TEXT NOT NULL,
            normalized_supplier TEXT NOT NULL DEFAULT '',
            vat REAL NOT NULL DEFAULT 0,
            gross REAL NOT NULL DEFAULT 0,
            paid_amount REAL NOT NULL DEFAULT 0,
            net REAL NOT NULL DEFAULT 0,
            notes TEXT,
            photo_path TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY(project_id) REFERENCES $_projectsTable(id)
          )
        ''');
        final defaultProjectId = await _insertDefaultProject(db);
        await db.execute('CREATE INDEX idx_${_table}_date ON $_table(date)');
        await db.execute(
            'CREATE INDEX idx_${_table}_invoice_number ON $_table(invoice_number)');
        await db.execute(
            'CREATE INDEX idx_${_table}_normalized_invoice ON $_table(normalized_invoice)');
        await db.execute(
            'CREATE INDEX idx_${_table}_normalized_supplier ON $_table(normalized_supplier)');
        await db
            .execute('CREATE INDEX idx_${_table}_scan_no ON $_table(scan_no)');
        await db.execute(
            'CREATE INDEX idx_${_table}_project_id ON $_table(project_id)');
        await _createDuplicateIntegrityTriggers(db);
        await _createCombinedReportView(db);
        await db.update(
          _table,
          {'project_id': defaultProjectId},
          where: 'project_id IS NULL',
        );
      },
      onUpgrade: (db, oldV, newV) async {
        // Future migrations go here
        if (oldV < 2) {
          // V1 -> V2 added scan_no column. Backfill existing rows.
          try {
            await db.execute('ALTER TABLE $_table ADD COLUMN scan_no INTEGER');
            await db.execute(
                'CREATE INDEX idx_${_table}_scan_no ON $_table(scan_no)');
            // Assign sequential scan_no by id
            final rows = await db.query(_table, orderBy: 'id ASC');
            for (var i = 0; i < rows.length; i++) {
              await db.update(
                _table,
                {'scan_no': i + 1},
                where: 'id = ?',
                whereArgs: [rows[i]['id']],
              );
            }
          } catch (e) {
            // Column may already exist if user did a clean install
          }
        }
        if (oldV < 3) {
          await _createProjectsTable(db);
          final defaultProjectId = await _insertDefaultProject(db);
          try {
            await db
                .execute('ALTER TABLE $_table ADD COLUMN project_id INTEGER');
          } catch (_) {
            // Column may already exist if a previous migration was interrupted
          }
          await db.update(
            _table,
            {'project_id': defaultProjectId},
            where: 'project_id IS NULL',
          );
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_${_table}_project_id ON $_table(project_id)');
        }
        if (oldV < 4) {
          await _createCategoriesTable(db);
          await _seedDefaultCategories(db);
        }
        if (oldV < 5) {
          try {
            await db
                .execute('ALTER TABLE $_table ADD COLUMN invoice_number TEXT');
          } catch (_) {
            // Column may already exist if a previous migration was interrupted
          }
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_${_table}_invoice_number ON $_table(invoice_number)');
        }
        if (oldV < 6) {
          await _createDuplicateIntegrityTriggers(db);
        }
        if (oldV < 7) {
          await _refreshDuplicateIntegrityTriggers(db);
        }
        if (oldV < 8) {
          await _createCombinedReportView(db);
        }
        if (oldV < 9) {
          await _migrateToBusinessExpenseCategories(db);
          await _renameDefaultProjectToOperation(db);
        }
        if (oldV < 10) {
          await _seedDefaultCategories(db);
        }
        if (oldV < 11) {
          await _migrateToCondensedMainCategories(db);
        }
        if (oldV < 12) {
          await _createCompanyProfileTable(db);
        }
        if (oldV < 13) {
          try {
            await db.execute(
              'ALTER TABLE $_companyTable ADD COLUMN company_code TEXT NOT NULL DEFAULT \'\'',
            );
          } catch (_) {
            // Column may already exist.
          }
          try {
            await db.execute(
              'ALTER TABLE $_companyTable ADD COLUMN financial_year_start_month INTEGER NOT NULL DEFAULT 4',
            );
          } catch (_) {
            // Column may already exist.
          }
        }
        if (oldV < 14) {
          await _migratePremisesUtilitiesSplit(db);
        }
        if (oldV < 15) {
          await _migrateToPnlCategoriesV15(db);
        }
        if (oldV < 16) {
          try {
            await db.execute(
              'ALTER TABLE $_table ADD COLUMN paid_amount REAL NOT NULL DEFAULT 0',
            );
          } catch (_) {
            // Column may already exist.
          }
          await db.execute('''
            UPDATE $_table
            SET paid_amount = gross
            WHERE paid_amount IS NULL OR ABS(paid_amount) < 0.00001
          ''');
        }
        if (oldV < 17) {
          await _migrateCategoryPolicyV17(db);
        }
        if (oldV < 18) {
          await _migrateCategoryPolicyV18(db);
        }
        if (oldV < 19) {
          await _migrateCompanyNameToMicrofastV19(db);
        }
        if (oldV < 20) {
          try {
            await db.execute(
              'ALTER TABLE $_table ADD COLUMN normalized_invoice TEXT NOT NULL DEFAULT \'\'',
            );
          } catch (_) {}
          try {
            await db.execute(
              'ALTER TABLE $_table ADD COLUMN normalized_supplier TEXT NOT NULL DEFAULT \'\'',
            );
          } catch (_) {}
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_${_table}_normalized_invoice ON $_table(normalized_invoice)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_${_table}_normalized_supplier ON $_table(normalized_supplier)',
          );
          final rows = await db.query(
            _table,
            columns: ['id', 'invoice_number', 'supplier'],
          );
          for (final row in rows) {
            final id = row['id'];
            if (id == null) continue;
            await db.update(
              _table,
              {
                'normalized_invoice':
                    normalizeInvoiceNumber(row['invoice_number'] as String?),
                'normalized_supplier':
                    normalizeSupplier(row['supplier'] as String?),
              },
              where: 'id = ?',
              whereArgs: [id],
            );
          }
          await _refreshDuplicateIntegrityTriggers(db);
        }
        if (oldV < 21) {
          await _migratePurchaseCategoryRenameV21(db);
        }
        if (oldV < 22) {
          await _migrateCompanyClassificationGuidanceV22(db);
        }
        if (oldV < 23) {
          await _seedDefaultCategories(db);
        }
        if (oldV < 24) {
          await _migrateSubcategoryPruneV24(db);
        }
        if (oldV < 25) {
          await _migrateCategoryModelV25(db);
        }
        if (oldV < 26) {
          await _migrateCategoryKeywordsV26(db);
        }
        if (oldV < 27) {
          await _migrateMainHeadOnlyV27(db);
        }
        if (oldV < 28) {
          await _migrateRenameMiscellaneousV28(db);
        }
        if (oldV < 29) {
          await _migrateClearMiscKeywordsV29(db);
        }
        if (oldV < 30) {
          await _migrateDropCategoryKeywordsV30(db);
        }
        if (oldV < 31) {
          await _migrateDropCompanyClassificationGuidanceV31(db);
        }
        if (oldV < 32) {
          await _migrateDropCategoriesTableV32(db);
        }
        if (oldV < 33) {
          await _migrateDropProjectExtraColumnsV33(db);
        }
        if (oldV < 34) {
          await _migrateDropReceiptCategoryV34(db);
        }
        if (oldV < 35) {
          await _migrateOperationHeadsV35(db);
        }
      },
    );

    await _refreshDuplicateIntegrityTriggers(_db!);
    await _createCombinedReportView(_db!);
    await _ensureFixedOperationHeads(_db!);

    return _db!;
  }

  static Future<void> closeConnection() async {
    final db = _db;
    _db = null;
    await db?.close();
  }

  static Future<void> clearEverything() async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.delete(_table);
    });

    final photosDir = await getPhotosDir();
    if (await photosDir.exists()) {
      await for (final entry in photosDir.list()) {
        if (entry is File) {
          try {
            await entry.delete();
          } catch (_) {
            // Ignore files that cannot be removed; database reset still stands.
          }
        }
      }
    }
  }

  static Future<void> _createProjectsTable(Database db) async =>
      _dbCreateProjectsTable(db);

  static Future<void> _createDuplicateIntegrityTriggers(
    DatabaseExecutor db,
  ) async =>
      _dbCreateDuplicateIntegrityTriggers(db);

  static Future<void> _refreshDuplicateIntegrityTriggers(
    DatabaseExecutor db,
  ) async =>
      _dbRefreshDuplicateIntegrityTriggers(db);

  static Future<void> _createCombinedReportView(DatabaseExecutor db) async =>
      _dbCreateCombinedReportView(db);

  static Future<void> _createCategoriesTable(Database db) async =>
      _dbCreateCategoriesTable(db);

  static Future<void> _createCompanyProfileTable(Database db) async =>
      _dbCreateCompanyProfileTable(db);

  static Future<void> _seedDefaultCategories(DatabaseExecutor db) async =>
      _dbSeedDefaultCategories(db);

  static Future<void> _migrateToBusinessExpenseCategories(
    DatabaseExecutor db,
  ) async =>
      _dbMigrateToBusinessExpenseCategories(db);

  static Future<void> _migrateToCondensedMainCategories(
    DatabaseExecutor db,
  ) async =>
      _dbMigrateToCondensedMainCategories(db);

  static Future<void> _migratePremisesUtilitiesSplit(
    DatabaseExecutor db,
  ) async =>
      _dbMigratePremisesUtilitiesSplit(db);

  static Future<void> _migrateToPnlCategoriesV15(DatabaseExecutor db) async =>
      _dbMigrateToPnlCategoriesV15(db);

  static Future<void> _renameDefaultProjectToOperation(
    DatabaseExecutor db,
  ) async =>
      _dbRenameDefaultProjectToOperation(db);

  static Future<void> _migrateCategoryPolicyV17(DatabaseExecutor db) async =>
      _dbMigrateCategoryPolicyV17(db);
  static Future<void> _migrateCategoryPolicyV18(DatabaseExecutor db) async =>
      _dbMigrateCategoryPolicyV18(db);
  static Future<void> _migrateCompanyNameToMicrofastV19(
          DatabaseExecutor db) async =>
      _dbMigrateCompanyNameToMicrofastV19(db);
  static Future<void> _migratePurchaseCategoryRenameV21(
          DatabaseExecutor db) async =>
      _dbMigratePurchaseCategoryRenameV21(db);
  static Future<void> _migrateCompanyClassificationGuidanceV22(
          DatabaseExecutor db) async =>
      _dbMigrateCompanyClassificationGuidanceV22(db);
  static Future<void> _migrateSubcategoryPruneV24(DatabaseExecutor db) async =>
      _dbMigrateSubcategoryPruneV24(db);
  static Future<void> _migrateCategoryModelV25(DatabaseExecutor db) async =>
      _dbMigrateCategoryModelV25(db);
  static Future<void> _migrateCategoryKeywordsV26(DatabaseExecutor db) async =>
      _dbMigrateCategoryKeywordsV26(db);
  static Future<void> _migrateMainHeadOnlyV27(DatabaseExecutor db) async =>
      _dbMigrateMainHeadOnlyV27(db);
  static Future<void> _migrateRenameMiscellaneousV28(
          DatabaseExecutor db) async =>
      _dbMigrateRenameMiscellaneousV28(db);
  static Future<void> _migrateClearMiscKeywordsV29(DatabaseExecutor db) async =>
      _dbMigrateClearMiscKeywordsV29(db);
  static Future<void> _migrateDropCategoryKeywordsV30(
          DatabaseExecutor db) async =>
      _dbMigrateDropCategoryKeywordsV30(db);
  static Future<void> _migrateDropCompanyClassificationGuidanceV31(
          DatabaseExecutor db) async =>
      _dbMigrateDropCompanyClassificationGuidanceV31(db);
  static Future<void> _migrateDropCategoriesTableV32(
          DatabaseExecutor db) async =>
      _dbMigrateDropCategoriesTableV32(db);
  static Future<void> _migrateDropProjectExtraColumnsV33(
          DatabaseExecutor db) async =>
      _dbMigrateDropProjectExtraColumnsV33(db);
  static Future<void> _migrateDropReceiptCategoryV34(
          DatabaseExecutor db) async =>
      _dbMigrateDropReceiptCategoryV34(db);
  static Future<void> _migrateOperationHeadsV35(DatabaseExecutor db) async =>
      _dbMigrateOperationHeadsV35(db);

  static Future<int> _insertDefaultProject(Database db) async =>
      _dbInsertDefaultProject(db);

  static Future<int> _defaultProjectId(Database db) async =>
      _dbDefaultProjectId(db);

  static Future<List<Operation>> getOperations() async {
    final db = await _open();
    final rows = await db.rawQuery('''
      SELECT p.*,
             COUNT(r.id) AS receipt_count,
             COALESCE(SUM(r.gross), 0) AS total_gross
      FROM $_projectsTable p
      LEFT JOIN $_table r ON r.project_id = p.id
      GROUP BY p.id
      ORDER BY p.created_at DESC, p.id DESC
    ''');
    final projects = rows.map((r) => Operation.fromMap(r)).toList();
    final order = <String, int>{
      for (var i = 0; i < fixedOperationHeads.length; i++)
        fixedOperationHeads[i].toLowerCase(): i,
    };
    projects.sort((a, b) {
      final ai = order[a.name.toLowerCase()] ?? 999;
      final bi = order[b.name.toLowerCase()] ?? 999;
      if (ai != bi) return ai.compareTo(bi);
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return projects;
  }

  @Deprecated('Use getOperations()')
  static Future<List<Project>> getProjects() async {
    final operations = await getOperations();
    return operations
        .map(
          (o) => Project(
            id: o.id,
            name: o.name,
            address: o.address,
            startDate: o.startDate,
            budget: o.budget,
            notes: o.notes,
            createdAt: o.createdAt,
            updatedAt: o.updatedAt,
            receiptCount: o.receiptCount,
            totalGross: o.totalGross,
          ),
        )
        .toList();
  }

  static Future<ProjectReport> getOperationReport({
    int? operationId,
    int? projectId,
    DateTime? from,
    DateTime? to,
    bool useScanDate = false,
  }) async {
    final db = await _open();
    final filters = <String>[];
    final args = <dynamic>[];
    final effectiveOperationId = operationId ?? projectId;

    if (effectiveOperationId != null) {
      filters.add('r.project_id = ?');
      args.add(effectiveOperationId);
    }

    if (from != null && to != null) {
      final dateExpr = useScanDate ? 'substr(r.created_at, 1, 10)' : 'r.date';
      filters.add('$dateExpr >= ? AND $dateExpr <= ?');
      args
        ..add(Receipt.formatDate(from))
        ..add(Receipt.formatDate(to));
    }

    final where = filters.isEmpty ? '' : 'WHERE ${filters.join(' AND ')}';
    final totals = await db.rawQuery('''
      SELECT COUNT(*) AS receipt_count,
             COALESCE(SUM(r.net), 0) AS total_net,
             COALESCE(SUM(r.vat), 0) AS total_vat,
             COALESCE(SUM(r.gross), 0) AS total_gross
      FROM $_table r
      $where
    ''', args);

    final categoryRows = await db.rawQuery('''
      SELECT COALESCE(p.name, 'Uncategorized') AS category,
             COUNT(*) AS receipt_count,
             COALESCE(SUM(r.net), 0) AS total_net,
             COALESCE(SUM(r.vat), 0) AS total_vat,
             COALESCE(SUM(r.gross), 0) AS total_gross
      FROM $_table r
      LEFT JOIN $_projectsTable p ON p.id = r.project_id
      $where
      GROUP BY COALESCE(p.name, 'Uncategorized')
      ORDER BY COALESCE(p.name, 'Uncategorized') COLLATE NOCASE ASC
    ''', args);

    final total = totals.first;
    final categories = categoryRows
        .map((r) => CategorySummary.fromMap(r))
        .toList()
      ..sort((a, b) => compareCategoryNames(a.category, b.category));
    return ProjectReport(
      receiptCount: (total['receipt_count'] as num?)?.toInt() ?? 0,
      totalNet: (total['total_net'] as num?)?.toDouble() ?? 0,
      totalVat: (total['total_vat'] as num?)?.toDouble() ?? 0,
      totalGross: (total['total_gross'] as num?)?.toDouble() ?? 0,
      categories: categories,
    );
  }

  @Deprecated('Use getOperationReport()')
  static Future<ProjectReport> getProjectReport({
    int? projectId,
    DateTime? from,
    DateTime? to,
    bool useScanDate = false,
  }) =>
      getOperationReport(
        projectId: projectId,
        from: from,
        to: to,
        useScanDate: useScanDate,
      );

  static Future<CombinedProjectReport> getCombinedOperationReport({
    required DateTime from,
    required DateTime to,
    bool useScanDate = false,
  }) async {
    final db = await _open();
    final projects = await getProjects();
    if (projects.isEmpty) {
      return CombinedProjectReport(
        projects: const [],
        categories: const [],
        grossByCategoryProject: const {},
        invoiceCountByCategory: const {},
        projectTotals: const {},
        grandTotal: 0,
        invoiceCount: 0,
      );
    }

    final dateColumn = useScanDate ? 'scan_date' : 'invoice_date';
    final fromStr = Receipt.formatDate(from);
    final toStr = Receipt.formatDate(to);
    final rows = await db.rawQuery('''
      SELECT category, project_id, COALESCE(SUM(gross), 0) AS total_gross
      FROM $_combinedReportView
      WHERE $dateColumn >= ? AND $dateColumn <= ?
      GROUP BY category, project_id
      ORDER BY category COLLATE NOCASE ASC
    ''', [fromStr, toStr]);
    final countRows = await db.rawQuery('''
      SELECT COUNT(*) AS invoice_count
      FROM $_combinedReportView
      WHERE $dateColumn >= ? AND $dateColumn <= ?
    ''', [fromStr, toStr]);
    final categoryCountRows = await db.rawQuery('''
      SELECT category, COUNT(*) AS invoice_count
      FROM $_combinedReportView
      WHERE $dateColumn >= ? AND $dateColumn <= ?
      GROUP BY category
      ORDER BY category COLLATE NOCASE ASC
    ''', [fromStr, toStr]);

    final categoriesSet = <String>{};
    final grossByCategoryProject = <String, Map<int, double>>{};
    final invoiceCountByCategory = <String, int>{};
    final projectTotals = <int, double>{
      for (final p in projects)
        if (p.id != null) p.id!: 0
    };
    double grandTotal = 0;

    for (final row in rows) {
      final category = (row['category'] as String?)?.trim() ?? '';
      final projectId = (row['project_id'] as num?)?.toInt();
      final gross = (row['total_gross'] as num?)?.toDouble() ?? 0;
      if (category.isEmpty || projectId == null) continue;
      categoriesSet.add(category);
      final byProject =
          grossByCategoryProject.putIfAbsent(category, () => <int, double>{});
      byProject[projectId] = gross;
      projectTotals[projectId] = (projectTotals[projectId] ?? 0) + gross;
      grandTotal += gross;
    }
    for (final row in categoryCountRows) {
      final category = (row['category'] as String?)?.trim() ?? '';
      final count = (row['invoice_count'] as num?)?.toInt() ?? 0;
      if (category.isEmpty) continue;
      categoriesSet.add(category);
      invoiceCountByCategory[category] = count;
    }

    final categories = sortCategoryNames(categoriesSet);

    return CombinedProjectReport(
      projects: projects,
      categories: categories,
      grossByCategoryProject: grossByCategoryProject,
      invoiceCountByCategory: invoiceCountByCategory,
      projectTotals: projectTotals,
      grandTotal: grandTotal,
      invoiceCount: (countRows.first['invoice_count'] as num?)?.toInt() ?? 0,
    );
  }

  @Deprecated('Use getCombinedOperationReport()')
  static Future<CombinedProjectReport> getCombinedProjectReport({
    required DateTime from,
    required DateTime to,
    bool useScanDate = false,
  }) =>
      getCombinedOperationReport(
        from: from,
        to: to,
        useScanDate: useScanDate,
      );

  static Future<MonthlyFiscalActivityReport> getMonthlyFiscalActivityReport({
    required int fiscalYearStartYear,
    required int fiscalYearStartMonth,
    int? operationId,
    int? projectId,
    bool useScanDate = false,
  }) async {
    final db = await _open();
    final safeStartMonth = fiscalYearStartMonth.clamp(1, 12);
    final from = DateTime(fiscalYearStartYear, safeStartMonth, 1);
    final to = DateTime(from.year + 1, from.month, from.day)
        .subtract(const Duration(days: 1));
    final fromStr = Receipt.formatDate(from);
    final toStr = Receipt.formatDate(to);
    final dateExpr = useScanDate ? 'substr(r.created_at, 1, 10)' : 'r.date';
    final selectDateExpr =
        useScanDate ? 'substr(r.created_at, 1, 10)' : 'r.date';

    final whereParts = <String>[
      '$dateExpr >= ?',
      '$dateExpr <= ?',
    ];
    final args = <dynamic>[fromStr, toStr];
    final effectiveOperationId = operationId ?? projectId;
    if (effectiveOperationId != null) {
      whereParts.add('r.project_id = ?');
      args.add(effectiveOperationId);
    }

    final where = whereParts.join(' AND ');
    final rows = await db.rawQuery('''
      SELECT COALESCE(p.name, 'Uncategorized') AS category,
             $selectDateExpr AS row_date,
             COALESCE(SUM(r.gross), 0) AS total_gross
      FROM $_table r
      LEFT JOIN $_projectsTable p ON p.id = r.project_id
      WHERE $where
      GROUP BY COALESCE(p.name, 'Uncategorized'), row_date
      ORDER BY row_date ASC, COALESCE(p.name, 'Uncategorized') COLLATE NOCASE ASC
    ''', args);

    final countRows = await db.rawQuery('''
      SELECT COUNT(*) AS invoice_count
      FROM $_table r
      LEFT JOIN $_projectsTable p ON p.id = r.project_id
      WHERE $where
    ''', args);

    final monthStarts = List<DateTime>.generate(
      12,
      (index) => DateTime(from.year, from.month + index, 1),
    );

    final categories = List<String>.from(fixedOperationHeads);

    final categoryMonthGross = <String, List<double>>{
      for (final category in categories) category: List.filled(12, 0),
    };
    final monthTotals = List<double>.filled(12, 0);
    final categoryTotals = <String, double>{
      for (final category in categories) category: 0,
    };
    double grandTotal = 0;

    for (final row in rows) {
      final category = (row['category'] as String?)?.trim() ?? '';
      final rowDateText = (row['row_date'] as String?)?.trim() ?? '';
      final gross = (row['total_gross'] as num?)?.toDouble() ?? 0;
      if (category.isEmpty || rowDateText.isEmpty) continue;
      final parsed = DateTime.tryParse(rowDateText);
      if (parsed == null) continue;
      final monthIndex =
          (parsed.year - from.year) * 12 + parsed.month - from.month;
      if (monthIndex < 0 || monthIndex >= 12) continue;

      categoryMonthGross.putIfAbsent(category, () => List.filled(12, 0));
      categoryTotals.putIfAbsent(category, () => 0);
      categoryMonthGross[category]![monthIndex] += gross;
      categoryTotals[category] = (categoryTotals[category] ?? 0) + gross;
      monthTotals[monthIndex] += gross;
      grandTotal += gross;
    }

    final sortedCategories = sortCategoryNames(categoryMonthGross.keys);

    return MonthlyFiscalActivityReport(
      from: from,
      to: to,
      months: monthStarts,
      categories: sortedCategories,
      categoryMonthGross: categoryMonthGross,
      monthTotals: monthTotals,
      categoryTotals: categoryTotals,
      grandTotal: grandTotal,
      invoiceCount: (countRows.first['invoice_count'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<Operation> createOperation(Operation draft) async {
    final db = await _open();
    final now = DateTime.now();
    final toSave = Operation(
      name: draft.name.trim(),
      address: draft.address?.trim().isEmpty == true ? null : draft.address,
      startDate: draft.startDate,
      budget: draft.budget,
      notes: draft.notes?.trim().isEmpty == true ? null : draft.notes,
      createdAt: now,
      updatedAt: now,
    );
    final id = await db.insert(_projectsTable, toSave.toMap());
    return Operation(
      id: id,
      name: toSave.name,
      address: toSave.address,
      startDate: toSave.startDate,
      budget: toSave.budget,
      notes: toSave.notes,
      createdAt: toSave.createdAt,
      updatedAt: toSave.updatedAt,
    );
  }

  @Deprecated('Use createOperation()')
  static Future<Project> createProject(Project draft) async {
    final operation = await createOperation(draft);
    return Project(
      id: operation.id,
      name: operation.name,
      address: operation.address,
      startDate: operation.startDate,
      budget: operation.budget,
      notes: operation.notes,
      createdAt: operation.createdAt,
      updatedAt: operation.updatedAt,
      receiptCount: operation.receiptCount,
      totalGross: operation.totalGross,
    );
  }

  static Future<List<AppCategory>> getCategories() async {
    final now = DateTime.now();
    return fixedOperationHeads
        .map((name) => AppCategory(name: name, createdAt: now, updatedAt: now))
        .toList();
  }

  static const List<String> mainCategories = fixedOperationHeads;

  static Future<List<String>> getMainCategories() async {
    return List<String>.from(mainCategories);
  }

  static Future<void> _ensureFixedOperationHeads(DatabaseExecutor db) async {
    final now = DateTime.now().toIso8601String();
    for (final head in fixedOperationHeads) {
      final existing = await db.query(
        _projectsTable,
        columns: ['id'],
        where: 'LOWER(TRIM(name)) = LOWER(?)',
        whereArgs: [head],
        limit: 1,
      );
      if (existing.isNotEmpty) continue;
      await db.insert(_projectsTable, {
        'name': head,
        'created_at': now,
        'updated_at': now,
      });
    }
  }

  static Future<CompanyProfile?> getCompanyProfile() async {
    final db = await _open();
    final rows = await db.query(_companyTable, limit: 1);
    if (rows.isEmpty) return null;
    return CompanyProfile.fromMap(rows.first);
  }

  static Future<CompanyProfile> saveCompanyProfile({
    required String clientName,
    required String companyCode,
    required String businessNature,
    required String businessDescription,
    required int financialYearStartMonth,
  }) async {
    final trimmedClient = clientName.trim();
    final trimmedCode = companyCode.trim().toUpperCase();
    final trimmedNature = businessNature.trim();
    final trimmedDescription = businessDescription.trim();
    if (trimmedClient.isEmpty ||
        trimmedCode.isEmpty ||
        trimmedNature.isEmpty ||
        trimmedDescription.isEmpty) {
      throw ArgumentError(
        'Client name, company code, business nature, and business description are required.',
      );
    }
    if (financialYearStartMonth < 1 || financialYearStartMonth > 12) {
      throw ArgumentError('Financial year start month must be from 1 to 12.');
    }

    final db = await _open();
    final existing = await getCompanyProfile();
    final now = DateTime.now();
    final profile = CompanyProfile(
      id: 1,
      clientName: trimmedClient,
      companyCode: trimmedCode,
      businessNature: trimmedNature,
      businessDescription: trimmedDescription,
      financialYearStartMonth: financialYearStartMonth,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    await db.insert(
      _companyTable,
      profile.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return profile;
  }

  static Future<AppCategory> createCategory(String name) async {
    throw StateError('Categories table has been removed.');
  }

  static Future<int> updateCategory(
      AppCategory category, String newName) async {
    throw StateError('Categories table has been removed.');
  }

  static Future<int> deleteCategory(AppCategory category) async {
    throw StateError('Categories table has been removed.');
  }

  static Future<int> updateOperation(Operation project) async {
    if (project.id == null) {
      throw ArgumentError('Cannot update an operation without an id');
    }
    final db = await _open();
    final updated = Operation(
      id: project.id,
      name: project.name.trim(),
      address: project.address?.trim().isEmpty == true
          ? null
          : project.address?.trim(),
      startDate: project.startDate,
      budget: project.budget,
      notes:
          project.notes?.trim().isEmpty == true ? null : project.notes?.trim(),
      createdAt: project.createdAt,
      updatedAt: DateTime.now(),
    );
    return db.update(
      _projectsTable,
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [project.id],
    );
  }

  @Deprecated('Use updateOperation()')
  static Future<int> updateProject(Project project) async =>
      updateOperation(project);

  static Future<int> deleteOperation(Operation project) async {
    if (project.id == null) {
      throw ArgumentError('Cannot delete an operation without an id');
    }
    final db = await _open();
    final receiptCount = await count(operationId: project.id);
    if (receiptCount > 0) {
      throw StateError(
          'Move or delete receipts before deleting this operation.');
    }
    return db.delete(
      _projectsTable,
      where: 'id = ?',
      whereArgs: [project.id],
    );
  }

  @Deprecated('Use deleteOperation()')
  static Future<int> deleteProject(Project project) async =>
      deleteOperation(project);

  /// Get the next scan_no (highest + 1, starting from 1).
  static Future<int> _nextScanNo(Database db) async {
    final result =
        await db.rawQuery('SELECT MAX(scan_no) as max_no FROM $_table');
    final maxNo = result.first['max_no'] as int?;
    return (maxNo ?? 0) + 1;
  }

  /// Photos directory on phone: <docs>/receipts/
  static Future<Directory> getPhotosDir() async {
    final docDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(docDir.path, 'receipts'));
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }
    return photosDir;
  }

  /// Save photo bytes to a temporary location BEFORE we know the smart name.
  /// Returns the temp path. Used during the scan phase, before save.
  static Future<String> savePhotoTemp(Uint8List bytes,
      {String ext = 'jpg'}) async {
    final tempDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final filePath = p.join(tempDir.path, 'pending_$ts.$ext');
    final file = File(filePath);
    await file.writeAsBytes(bytes);
    return filePath;
  }

  /// Save a receipt with photo. Generates scan_no, smart filename, and
  /// moves the temp photo to its final smart-named location.
  /// Returns the saved Receipt with id, scanNo, and final photoPath populated.
  static Future<Receipt> saveReceipt({
    required Receipt draft,
    Uint8List? photoBytes,
  }) async {
    final db = await _open();
    final projectId = draft.projectId ?? await _defaultProjectId(db);
    final scanNo = await _nextScanNo(db);

    String? finalPhotoPath;
    if (photoBytes != null) {
      // Build the smart filename now that we have scan_no
      final receiptForName = draft.copyWith(
        projectId: projectId,
        scanNo: scanNo,
      );
      final filename = receiptForName.buildSmartFilename();
      final photosDir = await getPhotosDir();
      final filePath = p.join(photosDir.path, filename);
      await File(filePath).writeAsBytes(photoBytes);
      finalPhotoPath = filePath;
    }

    final toSave = draft.copyWith(
      projectId: projectId,
      scanNo: scanNo,
      photoPath: finalPhotoPath,
    );

    final id = await db.insert(_table, toSave.toMap());
    return toSave.copyWith(id: id);
  }

  /// Update an existing receipt. If category/supplier/date/amount changed,
  /// the photo file is renamed to match the new smart filename.
  static Future<int> updateReceipt(Receipt r) async {
    if (r.id == null) {
      throw ArgumentError('Cannot update a receipt without an id');
    }
    final db = await _open();

    String? newPhotoPath = r.photoPath;
    if (r.photoPath != null && r.scanNo != null) {
      final expectedName = r.buildSmartFilename();
      final currentName = p.basename(r.photoPath!);
      if (expectedName != currentName) {
        // Rename the file to match the new data
        final photosDir = await getPhotosDir();
        final newPath = p.join(photosDir.path, expectedName);
        try {
          final f = File(r.photoPath!);
          if (await f.exists()) {
            await f.rename(newPath);
            newPhotoPath = newPath;
          }
        } catch (_) {/* keep old path on failure */}
      }
    }

    final updated = r.copyWith(
      photoPath: newPhotoPath,
      updatedAt: DateTime.now(),
    );
    return db.update(
      _table,
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [r.id],
    );
  }

  static Future<int> deleteReceipt(Receipt r) async {
    final db = await _open();
    if (r.photoPath != null) {
      try {
        final f = File(r.photoPath!);
        if (await f.exists()) await f.delete();
      } catch (_) {/* ignore */}
    }
    return db.delete(_table, where: 'id = ?', whereArgs: [r.id]);
  }

  static Future<List<Receipt>> getRecent(
      {int limit = 10, int? operationId, int? projectId}) async {
    final db = await _open();
    final effectiveOperationId = operationId ?? projectId;
    final rows = await db.rawQuery(
      '''
      SELECT r.*, COALESCE(p.name, 'Uncategorized') AS category
      FROM $_table r
      LEFT JOIN $_projectsTable p ON p.id = r.project_id
      ${effectiveOperationId == null ? '' : 'WHERE r.project_id = ?'}
      ORDER BY r.scan_no DESC, r.id DESC
      LIMIT ?
      ''',
      effectiveOperationId == null ? [limit] : [effectiveOperationId, limit],
    );
    return rows.map((r) => Receipt.fromMap(r)).toList();
  }

  static Future<List<Receipt>> searchReceipts({
    String query = '',
    int? operationId,
    int? projectId,
    int limit = 50,
  }) async {
    final trimmed = query.trim();
    final effectiveOperationId = operationId ?? projectId;
    if (trimmed.isEmpty) {
      return getRecent(limit: limit, operationId: effectiveOperationId);
    }

    final db = await _open();
    final searchTerms = <String>{trimmed, _normalizeDateQuery(trimmed)}
        .where((term) => term.isNotEmpty)
        .toList();
    final filters = <String>[];
    final args = <dynamic>[];

    if (effectiveOperationId != null) {
      filters.add('r.project_id = ?');
      args.add(effectiveOperationId);
    }

    final searchParts = <String>[];
    for (final term in searchTerms) {
      final like = '%$term%';
      searchParts.add('''
        LOWER(r.supplier) LIKE LOWER(?)
        OR LOWER(r.invoice_number) LIKE LOWER(?)
        OR LOWER(COALESCE(p.name, '')) LIKE LOWER(?)
        OR r.date LIKE ?
        OR substr(r.created_at, 1, 10) LIKE ?
        OR CAST(r.scan_no AS TEXT) LIKE ?
        OR printf('%.2f', r.gross) LIKE ?
        OR printf('%.2f', r.vat) LIKE ?
        OR printf('%.2f', r.net) LIKE ?
      ''');
      args
        ..add(like)
        ..add(like)
        ..add(like)
        ..add(like)
        ..add(like)
        ..add(like)
        ..add(like)
        ..add(like)
        ..add(like);
    }
    filters.add('(${searchParts.join(' OR ')})');

    final where = filters.isEmpty ? '' : 'WHERE ${filters.join(' AND ')}';
    final rows = await db.rawQuery(
      '''
      SELECT r.*, COALESCE(p.name, 'Uncategorized') AS category
      FROM $_table r
      LEFT JOIN $_projectsTable p ON p.id = r.project_id
      $where
      ORDER BY r.scan_no DESC, r.id DESC
      LIMIT ?
      ''',
      [...args, limit],
    );
    return rows.map((r) => Receipt.fromMap(r)).toList();
  }

  static Future<List<Receipt>> filterReceipts({
    int? operationId,
    int? projectId,
    String? supplier,
    String? category,
    double? exactGross,
    double? minGross,
    double? maxGross,
    DateTime? invoiceFrom,
    DateTime? invoiceTo,
    DateTime? scanFrom,
    DateTime? scanTo,
    int limit = 500,
  }) async {
    final db = await _open();
    final filters = <String>[];
    final args = <dynamic>[];
    final effectiveOperationId = operationId ?? projectId;

    if (effectiveOperationId != null) {
      filters.add('r.project_id = ?');
      args.add(effectiveOperationId);
    }

    final supplierText = supplier?.trim() ?? '';
    if (supplierText.isNotEmpty) {
      filters.add('LOWER(r.supplier) LIKE LOWER(?)');
      args.add('%$supplierText%');
    }

    final categoryText = category?.trim() ?? '';
    if (categoryText.isNotEmpty && categoryText != 'All') {
      filters.add('LOWER(COALESCE(p.name, \'\')) = LOWER(?)');
      args.add(categoryText);
    }

    if (exactGross != null) {
      filters.add('ABS(r.gross - ?) < 0.005');
      args.add(exactGross);
    } else {
      if (minGross != null) {
        filters.add('r.gross >= ?');
        args.add(minGross);
      }
      if (maxGross != null) {
        filters.add('r.gross <= ?');
        args.add(maxGross);
      }
    }

    if (invoiceFrom != null) {
      filters.add('r.date >= ?');
      args.add(Receipt.formatDate(invoiceFrom));
    }
    if (invoiceTo != null) {
      filters.add('r.date <= ?');
      args.add(Receipt.formatDate(invoiceTo));
    }

    if (scanFrom != null) {
      filters.add('substr(r.created_at, 1, 10) >= ?');
      args.add(Receipt.formatDate(scanFrom));
    }
    if (scanTo != null) {
      filters.add('substr(r.created_at, 1, 10) <= ?');
      args.add(Receipt.formatDate(scanTo));
    }

    final where = filters.isEmpty ? '' : 'WHERE ${filters.join(' AND ')}';
    final rows = await db.rawQuery(
      '''
      SELECT r.*, COALESCE(p.name, 'Uncategorized') AS category
      FROM $_table r
      LEFT JOIN $_projectsTable p ON p.id = r.project_id
      $where
      ORDER BY r.scan_no DESC, r.id DESC
      LIMIT ?
      ''',
      [...args, limit],
    );
    return rows.map((r) => Receipt.fromMap(r)).toList();
  }

  static String _normalizeDateQuery(String value) {
    final match = RegExp(r'^(\d{1,2})[\/\-](\d{1,2})(?:[\/\-](\d{2,4}))?$')
        .firstMatch(value.trim());
    if (match == null) return '';
    final day = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    var yearText = match.group(3);
    if (day == null || month == null || day < 1 || month < 1 || month > 12) {
      return '';
    }
    if (yearText == null) {
      return '-${month.toString().padLeft(2, '0')}-'
          '${day.toString().padLeft(2, '0')}';
    }
    if (yearText.length == 2) yearText = '20$yearText';
    final year = int.tryParse(yearText);
    if (year == null) return '';
    return '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }

  /// Check if a receipt likely already exists.
  /// If invoice number exists, match on:
  /// - invoice+date within same operation, OR
  /// - invoice+supplier within same operation.
  /// If invoice number is empty, fallback to supplier+date+gross.
  /// Used to warn about likely duplicates at save time.
  /// Returns the matching existing receipt(s), or empty list if none.
  /// Optionally exclude a specific id (used when editing Â£ exclude self).
  static Future<List<Receipt>> findPossibleDuplicates({
    String? invoiceNumber,
    required String supplier,
    required DateTime date,
    required double gross,
    int? operationId,
    int? projectId,
    int? excludeId,
  }) async {
    final db = await _open();
    final effectiveOperationId = operationId ?? projectId;
    final args = <dynamic>[];
    final duplicateParts = <String>[];
    final supplierSql = _normalizedSupplierSql('normalized_supplier');
    final normalizedInvoice = normalizeInvoiceNumber(invoiceNumber);
    if (normalizedInvoice.isNotEmpty) {
      final invoiceSql = _normalizedInvoiceSql('normalized_invoice');
      duplicateParts.add(
        "($invoiceSql = ? AND date = ? "
        "${effectiveOperationId != null ? 'AND COALESCE(project_id, -1) = ? ' : ''})",
      );
      duplicateParts.add(
        "($invoiceSql = ? AND $supplierSql = ? "
        "${effectiveOperationId != null ? 'AND COALESCE(project_id, -1) = ? ' : ''})",
      );
      args
        ..add(normalizedInvoice)
        ..add(Receipt.formatDate(date));
      if (effectiveOperationId != null) args.add(effectiveOperationId);
      args
        ..add(normalizedInvoice)
        ..add(normalizeSupplier(supplier));
      if (effectiveOperationId != null) args.add(effectiveOperationId);
    } else {
      duplicateParts.add(
        '($supplierSql = ? AND date = ? '
        '${effectiveOperationId != null ? 'AND COALESCE(project_id, -1) = ? ' : ''}'
        'AND ABS(gross - ?) < 0.005)',
      );
      args
        ..add(normalizeSupplier(supplier))
        ..add(Receipt.formatDate(date));
      if (effectiveOperationId != null) args.add(effectiveOperationId);
      args.add(gross);
    }

    var where = '(${duplicateParts.join(' OR ')})';
    if (excludeId != null) {
      where += ' AND id != ?';
      args.add(excludeId);
    }
    final rows = await db.query(
      _table,
      where: where,
      whereArgs: args,
      orderBy: 'id ASC',
    );
    return rows.map((r) => Receipt.fromMap(r)).toList();
  }

  static String _normalizedInvoiceSql(String expr) {
    return expr;
  }

  static String _normalizedSupplierSql(String expr) {
    return expr;
  }

  static Future<Receipt?> findByInvoiceNumber({
    required String invoiceNumber,
    int? operationId,
    int? projectId,
    int? excludeId,
  }) async {
    final normalizedInvoice = normalizeInvoiceNumber(invoiceNumber);
    if (normalizedInvoice.isEmpty) return null;
    final db = await _open();
    final invoiceSql = _normalizedInvoiceSql('normalized_invoice');
    final whereParts = <String>["$invoiceSql = ?"];
    final args = <dynamic>[normalizedInvoice];
    final effectiveOperationId = operationId ?? projectId;
    if (effectiveOperationId != null) {
      whereParts.add('project_id = ?');
      args.add(effectiveOperationId);
    }
    if (excludeId != null) {
      whereParts.add('id != ?');
      args.add(excludeId);
    }
    final rows = await db.query(
      _table,
      where: whereParts.join(' AND '),
      whereArgs: args,
      orderBy: 'id ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Receipt.fromMap(rows.first);
  }

  static Future<Receipt?> findByInvoiceSignature({
    required String invoiceNumber,
    required DateTime date,
    int? operationId,
    int? projectId,
    int? excludeId,
  }) async {
    final normalizedInvoice = normalizeInvoiceNumber(invoiceNumber);
    if (normalizedInvoice.isEmpty) return null;
    final db = await _open();
    final invoiceSql = _normalizedInvoiceSql('normalized_invoice');
    final whereParts = <String>[
      "$invoiceSql = ?",
      'date = ?',
    ];
    final args = <dynamic>[
      normalizedInvoice,
      Receipt.formatDate(date),
    ];
    final effectiveOperationId = operationId ?? projectId;
    if (effectiveOperationId != null) {
      whereParts.add('COALESCE(project_id, -1) = ?');
      args.add(effectiveOperationId);
    }
    if (excludeId != null) {
      whereParts.add('id != ?');
      args.add(excludeId);
    }
    final rows = await db.query(
      _table,
      where: whereParts.join(' AND '),
      whereArgs: args,
      orderBy: 'id ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Receipt.fromMap(rows.first);
  }

  static Future<Receipt?> findByInvoiceSupplier({
    required String invoiceNumber,
    required String supplier,
    int? operationId,
    int? projectId,
    int? excludeId,
  }) async {
    final normalizedInvoice = normalizeInvoiceNumber(invoiceNumber);
    if (normalizedInvoice.isEmpty) return null;
    final db = await _open();
    final invoiceSql = _normalizedInvoiceSql('normalized_invoice');
    final supplierSql = _normalizedSupplierSql('normalized_supplier');
    final whereParts = <String>[
      "$invoiceSql = ?",
      "$supplierSql = ?",
    ];
    final args = <dynamic>[
      normalizedInvoice,
      normalizeSupplier(supplier),
    ];
    final effectiveOperationId = operationId ?? projectId;
    if (effectiveOperationId != null) {
      whereParts.add('COALESCE(project_id, -1) = ?');
      args.add(effectiveOperationId);
    }
    if (excludeId != null) {
      whereParts.add('id != ?');
      args.add(excludeId);
    }
    final rows = await db.query(
      _table,
      where: whereParts.join(' AND '),
      whereArgs: args,
      orderBy: 'id ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Receipt.fromMap(rows.first);
  }

  /// Get receipts within a SCAN DATE range (uses created_at, not invoice date).
  static Future<List<Receipt>> getByScanDateRange(
    DateTime from,
    DateTime to, {
    int? operationId,
    int? projectId,
  }) async {
    final db = await _open();
    // created_at is ISO timestamp; we need to compare just the date portion.
    // SQLite has substr() which works fine for ISO dates.
    final fromStr = Receipt.formatDate(from);
    final toStr = Receipt.formatDate(to);
    final args = <dynamic>[fromStr, toStr];
    var where =
        'substr(r.created_at, 1, 10) >= ? AND substr(r.created_at, 1, 10) <= ?';
    final effectiveOperationId = operationId ?? projectId;
    if (effectiveOperationId != null) {
      where += ' AND r.project_id = ?';
      args.add(effectiveOperationId);
    }
    final rows = await db.rawQuery(
      '''
      SELECT r.*, COALESCE(p.name, 'Uncategorized') AS category
      FROM $_table r
      LEFT JOIN $_projectsTable p ON p.id = r.project_id
      WHERE $where
      ORDER BY r.created_at DESC, r.id DESC
      ''',
      args,
    );
    return rows.map((r) => Receipt.fromMap(r)).toList();
  }

  static Future<List<Receipt>> getByDateRange(
    DateTime from,
    DateTime to, {
    int? operationId,
    int? projectId,
  }) async {
    final db = await _open();
    final args = <dynamic>[Receipt.formatDate(from), Receipt.formatDate(to)];
    var where = 'r.date >= ? AND r.date <= ?';
    final effectiveOperationId = operationId ?? projectId;
    if (effectiveOperationId != null) {
      where += ' AND r.project_id = ?';
      args.add(effectiveOperationId);
    }
    final rows = await db.rawQuery(
      '''
      SELECT r.*, COALESCE(p.name, 'Uncategorized') AS category
      FROM $_table r
      LEFT JOIN $_projectsTable p ON p.id = r.project_id
      WHERE $where
      ORDER BY r.date DESC, r.id DESC
      ''',
      args,
    );
    return rows.map((r) => Receipt.fromMap(r)).toList();
  }

  static Future<Receipt?> getById(int id) async {
    final db = await _open();
    final rows = await db.rawQuery(
      '''
      SELECT r.*, COALESCE(p.name, 'Uncategorized') AS category
      FROM $_table r
      LEFT JOIN $_projectsTable p ON p.id = r.project_id
      WHERE r.id = ?
      LIMIT 1
      ''',
      [id],
    );
    if (rows.isEmpty) return null;
    return Receipt.fromMap(rows.first);
  }

  static Future<int> count({int? operationId, int? projectId}) async {
    final db = await _open();
    final effectiveOperationId = operationId ?? projectId;
    final result = effectiveOperationId == null
        ? await db.rawQuery('SELECT COUNT(*) as c FROM $_table')
        : await db.rawQuery(
            'SELECT COUNT(*) as c FROM $_table WHERE project_id = ?',
            [effectiveOperationId],
          );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
