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
  await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DatabaseService._categoriesTable} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE COLLATE NOCASE,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
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
  final now = DateTime.now().toIso8601String();
  for (final name in DatabaseService.defaultCategories) {
    await db.insert(
      DatabaseService._categoriesTable,
      {
        'name': name,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}

Future<void> _dbMigrateToBusinessExpenseCategories(DatabaseExecutor db) async {
  final now = DateTime.now().toIso8601String();
  const legacyToNew = <String, String>{
    'Material': 'Purchases',
    'Subcontractor': 'Subcontractor',
    'Utility Bills': 'Utility',
    'Travel': 'Travelling',
    'Insurance': 'Fees',
    'Other': 'Sundries',
  };

  for (final entry in legacyToNew.entries) {
    await db.rawUpdate(
      '''
        UPDATE ${DatabaseService._table}
        SET category = ?, updated_at = ?
        WHERE LOWER(TRIM(category)) = LOWER(?)
        ''',
      [entry.value, now, entry.key],
    );
  }

  const businessV9Categories = <String>[
    'Purchases',
    'Subcontractor',
    'Commissions',
    'Advertisement',
    'Salary',
    'Rent',
    'Rates',
    'Utility',
    'Travelling',
    'Subsistence',
    'Telephone',
    'Computer',
    'Fees',
    'Repair',
    'Sundries',
  ];

  for (final category in businessV9Categories) {
    await db.rawUpdate(
      '''
        UPDATE ${DatabaseService._table}
        SET category = ?, updated_at = ?
        WHERE LOWER(TRIM(category)) = LOWER(?)
        ''',
      [category, now, category],
    );
  }

  final normalizedDefaults =
      businessV9Categories.map((c) => c.toLowerCase()).toList();
  final placeholders = List.filled(normalizedDefaults.length, '?').join(',');
  await db.rawUpdate(
    '''
      UPDATE ${DatabaseService._table}
      SET category = ?, updated_at = ?
      WHERE TRIM(COALESCE(category, '')) = ''
         OR LOWER(TRIM(category)) NOT IN ($placeholders)
      ''',
    ['Sundries', now, ...normalizedDefaults],
  );

  await db.delete(DatabaseService._categoriesTable);
  final seedNow = DateTime.now().toIso8601String();
  for (final name in businessV9Categories) {
    await db.insert(
      DatabaseService._categoriesTable,
      {
        'name': name,
        'created_at': seedNow,
        'updated_at': seedNow,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}

Future<void> _dbMigrateToCondensedMainCategories(DatabaseExecutor db) async {
  final now = DateTime.now().toIso8601String();
  const oldToMain = <String, String>{
    'Purchases': 'Purchases',
    'Subcontractor': 'Staff & Contractors',
    'Commissions': 'Professional Fees',
    'Advertisement': 'Marketing',
    'Salary': 'Staff & Contractors',
    'Rent': 'Rent & Rates',
    'Rates': 'Rent & Rates',
    'Utility': 'Utilities',
    'Premises & Utilities': 'Rent & Rates',
    'Travelling': 'Travel',
    'Subsistence': 'Travel',
    'Telephone': 'Office Admin',
    'Computer': 'Office Admin',
    'Fees': 'Professional Fees',
    'Repair': 'Repair & Maintenance',
    'Sundries': 'Sundries',
    'Insurance': 'Insurance',
    'Charity': 'Donations & Charity',
    'Charity Donation': 'Donations & Charity',
    'Donations & Charity': 'Donations & Charity',
  };

  for (final entry in oldToMain.entries) {
    await db.rawUpdate(
      '''
      UPDATE ${DatabaseService._table}
      SET category = ?, updated_at = ?
      WHERE LOWER(TRIM(category)) = LOWER(?)
      ''',
      [entry.value, now, entry.key],
    );
  }

  final normalizedDefaults =
      DatabaseService.defaultCategories.map((c) => c.toLowerCase()).toList();
  final placeholders = List.filled(normalizedDefaults.length, '?').join(',');
  await db.rawUpdate(
    '''
      UPDATE ${DatabaseService._table}
      SET category = ?, updated_at = ?
      WHERE TRIM(COALESCE(category, '')) = ''
         OR LOWER(TRIM(category)) NOT IN ($placeholders)
      ''',
    ['Sundries', now, ...normalizedDefaults],
  );

  await db.delete(DatabaseService._categoriesTable);
  await _dbSeedDefaultCategories(db);
}

Future<void> _dbMigratePremisesUtilitiesSplit(DatabaseExecutor db) async {
  final now = DateTime.now().toIso8601String();
  await db.rawUpdate(
    '''
      UPDATE ${DatabaseService._table}
      SET category = ?, updated_at = ?
      WHERE LOWER(TRIM(category)) = LOWER(?)
      ''',
    ['Rent & Rates', now, 'Premises & Utilities'],
  );
  await db.rawUpdate(
    '''
      UPDATE ${DatabaseService._table}
      SET category = ?, updated_at = ?
      WHERE LOWER(TRIM(category)) = LOWER(?)
      ''',
    ['Utilities', now, 'Utility'],
  );
  await db.rawUpdate(
    '''
      UPDATE ${DatabaseService._table}
      SET category = ?, updated_at = ?
      WHERE LOWER(TRIM(category)) = LOWER(?)
      ''',
    ['Rent & Rates', now, 'Rent'],
  );
  await db.rawUpdate(
    '''
      UPDATE ${DatabaseService._table}
      SET category = ?, updated_at = ?
      WHERE LOWER(TRIM(category)) = LOWER(?)
      ''',
    ['Rent & Rates', now, 'Rates'],
  );

  await db.delete(
    DatabaseService._categoriesTable,
    where: 'LOWER(TRIM(name)) = LOWER(?)',
    whereArgs: ['Premises & Utilities'],
  );
  await _dbSeedDefaultCategories(db);
}

Future<void> _dbMigrateToPnlCategoriesV15(DatabaseExecutor db) async {
  await db.delete(DatabaseService._categoriesTable);
  await _dbSeedDefaultCategories(db);
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
  final now = DateTime.now().toIso8601String();

  await db.rawUpdate(
    '''
      UPDATE ${DatabaseService._table}
      SET category = ?, updated_at = ?
      WHERE LOWER(TRIM(category)) = LOWER(?)
    ''',
    ['Fee', now, 'Bank Charges and Interest'],
  );

  await db.rawUpdate(
    '''
      UPDATE ${DatabaseService._table}
      SET category = ?, updated_at = ?
      WHERE LOWER(TRIM(category)) IN (LOWER(?), LOWER(?))
    ''',
    ['General Expenses', now, 'Depreciation', 'Bad Debts'],
  );

  await db.delete(
    DatabaseService._categoriesTable,
    where: 'LOWER(TRIM(name)) IN (LOWER(?), LOWER(?), LOWER(?))',
    whereArgs: [
      'Bank Charges and Interest',
      'Depreciation',
      'Bad Debts',
    ],
  );

  await _dbSeedDefaultCategories(db);
}

Future<void> _dbMigrateCategoryPolicyV18(DatabaseExecutor db) async {
  final now = DateTime.now().toIso8601String();

  await db.rawUpdate(
    '''
      UPDATE ${DatabaseService._table}
      SET category = ?, updated_at = ?
      WHERE LOWER(TRIM(category)) IN (LOWER(?), LOWER(?), LOWER(?), LOWER(?))
    ''',
    [
      'Fee & Charges',
      now,
      'Fee',
      'Fees',
      'Professional Fees',
      'Bank Charges and Interest',
    ],
  );

  await db.rawUpdate(
    '''
      UPDATE ${DatabaseService._table}
      SET category = ?, updated_at = ?
      WHERE LOWER(TRIM(category)) IN (LOWER(?), LOWER(?), LOWER(?), LOWER(?))
    ''',
    [
      'Other Exp',
      now,
      'Maintenance',
      'General Expenses',
      'Depreciation',
      'Bad Debts',
    ],
  );

  await db.delete(
    DatabaseService._categoriesTable,
    where:
        'LOWER(TRIM(name)) IN (LOWER(?),LOWER(?),LOWER(?),LOWER(?),LOWER(?),LOWER(?),LOWER(?))',
    whereArgs: [
      'Fee',
      'Fees',
      'Professional Fees',
      'Maintenance',
      'General Expenses',
      'Depreciation',
      'Bad Debts',
    ],
  );

  await _dbSeedDefaultCategories(db);
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
  final now = DateTime.now().toIso8601String();

  await db.rawUpdate(
    '''
      UPDATE ${DatabaseService._table}
      SET category = ?, updated_at = ?
      WHERE LOWER(TRIM(category)) IN (LOWER(?), LOWER(?))
    ''',
    ['Material Purchase', now, 'Purchase', 'Purchases'],
  );

  await db.rawUpdate(
    '''
      UPDATE ${DatabaseService._categoriesTable}
      SET name = ?, updated_at = ?
      WHERE LOWER(TRIM(name)) IN (LOWER(?), LOWER(?))
    ''',
    ['Material Purchase', now, 'Purchase', 'Purchases'],
  );

  await _dbSeedDefaultCategories(db);
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
  final now = DateTime.now().toIso8601String();

  const rewrites = <String, String>{
    'Materials & Purchases - Miscellaneous Purchases':
        'Materials & Purchases - Materials Purchased',
    'Materials & Purchases - Carriage':
        'Materials & Purchases - Materials Purchased',
    'Materials & Purchases - Transport Insurance':
        'Materials & Purchases - Materials Imported',
    'Materials & Purchases - Closing Stock':
        'Materials & Purchases - Opening Stock',
    'Labour & Staffing - Cost of Sales Labour':
        'Labour & Staffing - Productive Labour',
    'Labour & Staffing - Staff Salaries': 'Labour & Staffing - Gross Wages',
    'Labour & Staffing - Wages Casual': 'Labour & Staffing - Wages Regular',
    'Labour & Staffing - Employers Pensions':
        'Labour & Staffing - Employers NI',
    'Premises & Utilities - Oil': 'Premises & Utilities - Other Heating Costs',
    'Motor, Travel & Subsistence - Vehicle Licences':
        'Motor, Travel & Subsistence - Vehicle Insurance',
    'Motor, Travel & Subsistence - Mileage Claims':
        'Motor, Travel & Subsistence - Travelling',
    'Motor, Travel & Subsistence - Overseas Travelling':
        'Motor, Travel & Subsistence - Travelling',
    'Professional & Financial Charges - Bank Interest Paid':
        'Professional & Financial Charges - Bank Charges',
    'Professional & Financial Charges - Currency Charges':
        'Professional & Financial Charges - Bank Charges',
    'Professional & Financial Charges - HP Interest':
        'Professional & Financial Charges - Loan Interest Paid',
    'Professional & Financial Charges - Exchange Rate Variance':
        'Professional & Financial Charges - Other Interest Charges',
    'Professional & Financial Charges - Factoring Charges':
        'Professional & Financial Charges - Credit Charges',
    'Other, Non-cash & Exceptional - Depreciation':
        'Other, Non-cash & Exceptional - Plant and Machinery Depreciation',
    'Other, Non-cash & Exceptional - Furniture and Fittings Depreciation':
        'Other, Non-cash & Exceptional - Plant and Machinery Depreciation',
    'Other, Non-cash & Exceptional - Office Equipment Depreciation':
        'Other, Non-cash & Exceptional - Plant and Machinery Depreciation',
    'Other, Non-cash & Exceptional - Bad Debt Provision':
        'Other, Non-cash & Exceptional - Bad Debt Write Off',
  };

  for (final entry in rewrites.entries) {
    await db.rawUpdate(
      '''
        UPDATE ${DatabaseService._table}
        SET category = ?, updated_at = ?
        WHERE LOWER(TRIM(category)) = LOWER(?)
      ''',
      [entry.value, now, entry.key],
    );
  }

  await db.delete(DatabaseService._categoriesTable);
  await _dbSeedDefaultCategories(db);
}

Future<void> _dbMigrateCategoryModelV25(DatabaseExecutor db) async {
  // Refresh category seed set to the new 8-main / subcategory taxonomy.
  // Receipt rows keep their saved main category values; this migration
  // updates the category catalog used by scan guidance and category manager.
  await db.delete(DatabaseService._categoriesTable);
  await _dbSeedDefaultCategories(db);
}

Future<void> _dbMigrateCategoryKeywordsV26(DatabaseExecutor db) async {
  // Deprecated in v30 (keywords column removed).
  return;
}

Future<void> _dbMigrateMainHeadOnlyV27(DatabaseExecutor db) async {
  final now = DateTime.now().toIso8601String();

  // Collapse any stored receipt category like "Main - Sub" -> "Main".
  final receiptRows = await db.query(
    DatabaseService._table,
    columns: ['id', 'category'],
  );
  for (final row in receiptRows) {
    final id = row['id'];
    final category = (row['category'] as String?)?.trim() ?? '';
    if (id == null || category.isEmpty) continue;
    final sep = category.indexOf(' - ');
    if (sep <= 0) continue;
    final main = category.substring(0, sep).trim();
    if (main.isEmpty) continue;
    await db.update(
      DatabaseService._table,
      {'category': main, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Rebuild category catalog with main heads only.
  await db.delete(DatabaseService._categoriesTable);
  await _dbSeedDefaultCategories(db);
}

Future<void> _dbMigrateRenameMiscellaneousV28(DatabaseExecutor db) async {
  final now = DateTime.now().toIso8601String();
  const oldName = 'Other, Non-cash & Exceptional';
  const newName = 'Miscellaneous';

  await db.rawUpdate(
    '''
      UPDATE ${DatabaseService._table}
      SET category = ?, updated_at = ?
      WHERE LOWER(TRIM(category)) = LOWER(?)
    ''',
    [newName, now, oldName],
  );

  await db.rawUpdate(
    '''
      UPDATE ${DatabaseService._categoriesTable}
      SET name = ?, updated_at = ?
      WHERE LOWER(TRIM(name)) = LOWER(?)
    ''',
    [newName, now, oldName],
  );

  // Ensure only expected main heads remain after rename.
  await db.delete(
    DatabaseService._categoriesTable,
    where:
        'LOWER(TRIM(name)) NOT IN (${List.filled(DatabaseService.mainCategories.length, '?').join(',')})',
    whereArgs:
        DatabaseService.mainCategories.map((e) => e.toLowerCase()).toList(),
  );

  await _dbSeedDefaultCategories(db);
}

Future<void> _dbMigrateClearMiscKeywordsV29(DatabaseExecutor db) async {
  // Deprecated in v30 (keywords column removed).
  return;
}

Future<void> _dbMigrateDropCategoryKeywordsV30(DatabaseExecutor db) async {
  final columns = await db
      .rawQuery('PRAGMA table_info(${DatabaseService._categoriesTable})');
  final hasKeywords = columns.any(
    (row) => (row['name'] as String?)?.toLowerCase() == 'keywords',
  );
  if (!hasKeywords) return;

  await db.execute('''
    CREATE TABLE ${DatabaseService._categoriesTable}_v30 (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE COLLATE NOCASE,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    INSERT OR IGNORE INTO ${DatabaseService._categoriesTable}_v30 (
      id, name, created_at, updated_at
    )
    SELECT id, name, created_at, updated_at
    FROM ${DatabaseService._categoriesTable}
  ''');
  await db.execute('DROP TABLE ${DatabaseService._categoriesTable}');
  await db.execute(
      'ALTER TABLE ${DatabaseService._categoriesTable}_v30 RENAME TO ${DatabaseService._categoriesTable}');
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
