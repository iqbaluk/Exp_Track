part of '../database_service.dart';

Future<void> _dbCreateProjectsTable(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DatabaseService._projectsTable} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
}

Future<void> _dbCreateDuplicateIntegrityTriggers(DatabaseExecutor db) async {
  final existingInvoiceSql =
      DatabaseService._normalizedInvoiceSql('r.normalized_invoice');
  final newInvoiceSql =
      DatabaseService._normalizedInvoiceSql('NEW.normalized_invoice');
  final existingSupplierSql =
      DatabaseService._normalizedSupplierSql('r.normalized_supplier');
  final newSupplierSql =
      DatabaseService._normalizedSupplierSql('NEW.normalized_supplier');

  await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_receipts_no_dup_invoice_signature_insert
      BEFORE INSERT ON ${DatabaseService._table}
      WHEN TRIM(COALESCE(NEW.invoice_number, '')) <> ''
      BEGIN
        SELECT RAISE(ABORT, 'DUPLICATE_INVOICE_SIGNATURE')
        WHERE EXISTS (
          SELECT 1
          FROM ${DatabaseService._table} r
          WHERE $existingInvoiceSql = $newInvoiceSql
            AND COALESCE(r.project_id, -1) = COALESCE(NEW.project_id, -1)
            AND (
              r.date = NEW.date
              OR $existingSupplierSql = $newSupplierSql
            )
        );
      END;
    ''');

  await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_receipts_no_dup_invoice_signature_update
      BEFORE UPDATE ON ${DatabaseService._table}
      WHEN TRIM(COALESCE(NEW.invoice_number, '')) <> ''
      BEGIN
        SELECT RAISE(ABORT, 'DUPLICATE_INVOICE_SIGNATURE')
        WHERE EXISTS (
          SELECT 1
          FROM ${DatabaseService._table} r
          WHERE r.id != NEW.id
            AND $existingInvoiceSql = $newInvoiceSql
            AND COALESCE(r.project_id, -1) = COALESCE(NEW.project_id, -1)
            AND (
              r.date = NEW.date
              OR $existingSupplierSql = $newSupplierSql
            )
        );
      END;
    ''');

  await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_receipts_no_dup_supplier_date_gross_insert
      BEFORE INSERT ON ${DatabaseService._table}
      BEGIN
        SELECT RAISE(ABORT, 'DUPLICATE_SUPPLIER_DATE_GROSS')
        WHERE EXISTS (
          SELECT 1
          FROM ${DatabaseService._table} r
          WHERE $existingSupplierSql = $newSupplierSql
            AND r.date = NEW.date
            AND ABS(r.gross - NEW.gross) < 0.005
        );
      END;
    ''');

  await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_receipts_no_dup_supplier_date_gross_update
      BEFORE UPDATE ON ${DatabaseService._table}
      BEGIN
        SELECT RAISE(ABORT, 'DUPLICATE_SUPPLIER_DATE_GROSS')
        WHERE EXISTS (
          SELECT 1
          FROM ${DatabaseService._table} r
          WHERE r.id != NEW.id
            AND $existingSupplierSql = $newSupplierSql
            AND r.date = NEW.date
            AND ABS(r.gross - NEW.gross) < 0.005
        );
      END;
    ''');
}

Future<void> _dbRefreshDuplicateIntegrityTriggers(DatabaseExecutor db) async {
  await db.execute(
    'DROP TRIGGER IF EXISTS trg_receipts_no_dup_invoice_signature_insert',
  );
  await db.execute(
    'DROP TRIGGER IF EXISTS trg_receipts_no_dup_invoice_signature_update',
  );
  await db.execute(
    'DROP TRIGGER IF EXISTS trg_receipts_no_dup_supplier_date_gross_insert',
  );
  await db.execute(
    'DROP TRIGGER IF EXISTS trg_receipts_no_dup_supplier_date_gross_update',
  );
  await _dbCreateDuplicateIntegrityTriggers(db);
}

Future<void> _dbCreateCombinedReportView(DatabaseExecutor db) async {
  await db
      .execute('DROP VIEW IF EXISTS ${DatabaseService._combinedReportView}');
  await db.execute('''
      CREATE VIEW IF NOT EXISTS ${DatabaseService._combinedReportView} AS
      SELECT
        r.id AS receipt_id,
        r.project_id AS project_id,
        p.name AS project_name,
        COALESCE(p.name, 'Uncategorized') AS category,
        r.gross AS gross,
        r.date AS invoice_date,
        substr(r.created_at, 1, 10) AS scan_date
      FROM ${DatabaseService._table} r
      LEFT JOIN ${DatabaseService._projectsTable} p ON p.id = r.project_id
      WHERE r.project_id IS NOT NULL
    ''');
}

Future<void> _dbCreateCategoriesTable(Database db) async {
  // Categories are de-scoped from current schema.
  return;
}

Future<void> _dbCreateCompanyProfileTable(Database db) async {
  await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DatabaseService._companyTable} (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        client_name TEXT NOT NULL,
        company_code TEXT NOT NULL DEFAULT '',
        business_nature TEXT NOT NULL,
        business_description TEXT NOT NULL,
        financial_year_start_month INTEGER NOT NULL DEFAULT 4,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
}

Future<void> _dbSeedDefaultCategories(DatabaseExecutor db) async {
  // Categories are de-scoped from current schema.
  return;
}

Future<void> _dbMigrateToBusinessExpenseCategories(DatabaseExecutor db) async {
  // Legacy category migration is intentionally disabled.
  return;
}

Future<void> _dbMigrateToCondensedMainCategories(DatabaseExecutor db) async {
  // Legacy category migration is intentionally disabled.
  return;
}

Future<void> _dbMigratePremisesUtilitiesSplit(DatabaseExecutor db) async {
  // Legacy category migration is intentionally disabled.
  return;
}

Future<void> _dbMigrateToPnlCategoriesV15(DatabaseExecutor db) async {
  // Legacy category migration is intentionally disabled.
  return;
}

Future<void> _dbRenameDefaultProjectToOperation(DatabaseExecutor db) async {
  await db.rawUpdate(
    '''
      UPDATE ${DatabaseService._projectsTable}
      SET name = ?, updated_at = ?
      WHERE LOWER(TRIM(name)) = LOWER(?)
      ''',
    ['General Operation', DateTime.now().toIso8601String(), 'General'],
  );
}

Future<void> _dbMigrateCategoryPolicyV17(DatabaseExecutor db) async {
  // Legacy category migration is intentionally disabled.
  return;
}

Future<void> _dbMigrateCategoryPolicyV18(DatabaseExecutor db) async {
  // Legacy category migration is intentionally disabled.
  return;
}

Future<void> _dbMigrateCompanyNameToMicrofastV19(DatabaseExecutor db) async {
  final now = DateTime.now().toIso8601String();
  await db.rawUpdate(
    '''
      UPDATE ${DatabaseService._companyTable}
      SET client_name = ?, updated_at = ?
      WHERE LOWER(TRIM(client_name)) = LOWER(?)
    ''',
    ['Microfast Ltd', now, 'FastFLow AI Ltd'],
  );
}

Future<void> _dbMigratePurchaseCategoryRenameV21(DatabaseExecutor db) async {
  // Legacy category migration is intentionally disabled.
  return;
}

Future<void> _dbMigrateCompanyClassificationGuidanceV22(
  DatabaseExecutor db,
) async {
  try {
    await db.execute(
      'ALTER TABLE ${DatabaseService._companyTable} ADD COLUMN classification_guidance TEXT',
    );
  } catch (_) {
    // Column may already exist.
  }
}

Future<void> _dbMigrateSubcategoryPruneV24(DatabaseExecutor db) async {
  // Legacy category migration is intentionally disabled.
  return;
}

Future<void> _dbMigrateCategoryModelV25(DatabaseExecutor db) async {
  // Legacy category migration is intentionally disabled.
  return;
}

Future<void> _dbMigrateCategoryKeywordsV26(DatabaseExecutor db) async {
  // Deprecated in v30 (keywords column removed).
  return;
}

Future<void> _dbMigrateMainHeadOnlyV27(DatabaseExecutor db) async {
  // Legacy category migration is intentionally disabled.
  return;
}

Future<void> _dbMigrateRenameMiscellaneousV28(DatabaseExecutor db) async {
  // Legacy category migration is intentionally disabled.
  return;
}

Future<void> _dbMigrateClearMiscKeywordsV29(DatabaseExecutor db) async {
  // Deprecated in v30 (keywords column removed).
  return;
}

Future<void> _dbMigrateDropCategoryKeywordsV30(DatabaseExecutor db) async {
  // Legacy category migration is intentionally disabled.
  return;
}

Future<void> _dbMigrateDropCompanyClassificationGuidanceV31(
    DatabaseExecutor db) async {
  final columns =
      await db.rawQuery('PRAGMA table_info(${DatabaseService._companyTable})');
  final hasGuidance = columns.any(
    (row) =>
        (row['name'] as String?)?.toLowerCase() == 'classification_guidance',
  );
  if (!hasGuidance) return;

  await db.execute('''
    CREATE TABLE ${DatabaseService._companyTable}_v31 (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      client_name TEXT NOT NULL,
      company_code TEXT NOT NULL DEFAULT '',
      business_nature TEXT NOT NULL,
      business_description TEXT NOT NULL,
      financial_year_start_month INTEGER NOT NULL DEFAULT 4,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    INSERT OR REPLACE INTO ${DatabaseService._companyTable}_v31 (
      id, client_name, company_code, business_nature, business_description,
      financial_year_start_month, created_at, updated_at
    )
    SELECT
      id, client_name, company_code, business_nature, business_description,
      financial_year_start_month, created_at, updated_at
    FROM ${DatabaseService._companyTable}
  ''');
  await db.execute('DROP TABLE ${DatabaseService._companyTable}');
  await db.execute(
      'ALTER TABLE ${DatabaseService._companyTable}_v31 RENAME TO ${DatabaseService._companyTable}');
}

Future<void> _dbMigrateDropCategoriesTableV32(DatabaseExecutor db) async {
  await db.execute('DROP TABLE IF EXISTS ${DatabaseService._categoriesTable}');
}

Future<void> _dbMigrateDropProjectExtraColumnsV33(DatabaseExecutor db) async {
  await db.execute('PRAGMA foreign_keys=OFF');
  await db.execute('''
    CREATE TABLE ${DatabaseService._projectsTable}_v33 (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    INSERT INTO ${DatabaseService._projectsTable}_v33 (
      id, name, created_at, updated_at
    )
    SELECT id, name, created_at, updated_at
    FROM ${DatabaseService._projectsTable}
  ''');
  await db.execute('DROP TABLE ${DatabaseService._projectsTable}');
  await db.execute(
    'ALTER TABLE ${DatabaseService._projectsTable}_v33 RENAME TO ${DatabaseService._projectsTable}',
  );
  await db.execute('PRAGMA foreign_keys=ON');
}

Future<void> _dbMigrateDropReceiptCategoryV34(DatabaseExecutor db) async {
  await db.execute('PRAGMA foreign_keys=OFF');
  await db.execute('''
    CREATE TABLE ${DatabaseService._table}_v34 (
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
      FOREIGN KEY(project_id) REFERENCES ${DatabaseService._projectsTable}(id)
    )
  ''');
  await db.execute('''
    INSERT INTO ${DatabaseService._table}_v34 (
      id, project_id, scan_no, date, invoice_number, normalized_invoice,
      supplier, normalized_supplier, vat, gross, paid_amount, net, notes,
      photo_path, created_at, updated_at
    )
    SELECT
      id, project_id, scan_no, date, invoice_number, normalized_invoice,
      supplier, normalized_supplier, vat, gross, paid_amount, net, notes,
      photo_path, created_at, updated_at
    FROM ${DatabaseService._table}
  ''');
  await db.execute('DROP TABLE ${DatabaseService._table}');
  await db.execute(
    'ALTER TABLE ${DatabaseService._table}_v34 RENAME TO ${DatabaseService._table}',
  );
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${DatabaseService._table}_date ON ${DatabaseService._table}(date)');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${DatabaseService._table}_invoice_number ON ${DatabaseService._table}(invoice_number)');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${DatabaseService._table}_normalized_invoice ON ${DatabaseService._table}(normalized_invoice)');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${DatabaseService._table}_normalized_supplier ON ${DatabaseService._table}(normalized_supplier)');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${DatabaseService._table}_scan_no ON ${DatabaseService._table}(scan_no)');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${DatabaseService._table}_project_id ON ${DatabaseService._table}(project_id)');
  await db.execute('PRAGMA foreign_keys=ON');
}

Future<void> _dbMigrateOperationHeadsV35(DatabaseExecutor db) async {
  final now = DateTime.now().toIso8601String();
  const targetHeads = <String>[
    'Purchases',
    'labour / Sub_Contractor',
    'Rent & Bills',
    'Travel & Food',
    'Office Exp',
    'Professional Fee',
    'Miscellaneous',
  ];

  final targetIdByName = <String, int>{};
  for (final head in targetHeads) {
    final existing = await db.query(
      DatabaseService._projectsTable,
      columns: ['id'],
      where: 'LOWER(TRIM(name)) = LOWER(?)',
      whereArgs: [head],
      limit: 1,
    );
    int id;
    if (existing.isNotEmpty) {
      id = existing.first['id'] as int;
      await db.update(
        DatabaseService._projectsTable,
        {'name': head, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      id = await db.insert(DatabaseService._projectsTable, {
        'name': head,
        'created_at': now,
        'updated_at': now,
      });
    }
    targetIdByName[head.toLowerCase()] = id;
  }

  String mapHead(String name) {
    final key = name.trim().toLowerCase();
    switch (key) {
      case 'purchases':
        return 'Purchases';
      case 'labour / sub_contractor':
        return 'labour / Sub_Contractor';
      case 'professional fee':
        return 'Professional Fee';
      case 'miscellaneous':
        return 'Miscellaneous';
      case 'rent & bills':
        return 'Rent & Bills';
      case 'travel & food':
        return 'Travel & Food';
      case 'office exp':
        return 'Office Exp';
      case 'marketing':
      case 'general operation':
      case 'general':
        return 'Miscellaneous';
      case 'rant and rates':
      case 'rent and rates':
      case 'rent & rates':
      case 'utility bills':
        return 'Rent & Bills';
      case 'travel & hotel':
      case 'food & subsistence':
        return 'Travel & Food';
      case 'office & admin':
        return 'Office Exp';
      default:
        return 'Miscellaneous';
    }
  }

  final rows = await db.query(
    DatabaseService._projectsTable,
    columns: ['id', 'name'],
  );
  for (final row in rows) {
    final id = row['id'] as int?;
    final name = (row['name'] as String?)?.trim() ?? '';
    if (id == null || name.isEmpty) continue;
    final mappedName = mapHead(name);
    final targetId = targetIdByName[mappedName.toLowerCase()];
    if (targetId == null) continue;
    if (id == targetId) {
      await db.update(
        DatabaseService._projectsTable,
        {'name': mappedName, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
      continue;
    }
    await db.update(
      DatabaseService._table,
      {'project_id': targetId, 'updated_at': now},
      where: 'project_id = ?',
      whereArgs: [id],
    );
    await db.delete(
      DatabaseService._projectsTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

Future<int> _dbInsertDefaultProject(Database db) async {
  await DatabaseService._ensureFixedOperationHeads(db);
  final firstName = DatabaseService.fixedOperationHeads.first;
  final existing = await db.query(
    DatabaseService._projectsTable,
    columns: ['id'],
    where: 'LOWER(TRIM(name)) = LOWER(?)',
    whereArgs: [firstName],
    limit: 1,
  );
  if (existing.isNotEmpty) return existing.first['id'] as int;
  throw StateError('Could not initialize fixed operation heads.');
}

Future<int> _dbDefaultProjectId(Database db) async {
  return _dbInsertDefaultProject(db);
}

Future<void> _dbMigrateProjectsTableToAccountsV37(DatabaseExecutor db) async {
  const oldTable = 'tbl_projects';
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name IN (?, ?)",
    [oldTable, DatabaseService._projectsTable],
  );
  final names = rows
      .map((r) => (r['name'] as String?)?.trim().toLowerCase() ?? '')
      .toSet();
  if (names.contains(DatabaseService._projectsTable.toLowerCase())) return;
  if (!names.contains(oldTable)) return;
  await db.execute(
    'ALTER TABLE $oldTable RENAME TO ${DatabaseService._projectsTable}',
  );
}
