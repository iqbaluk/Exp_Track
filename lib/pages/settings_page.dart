part of '../main.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Future<CompanyProfile?> _companyProfileFuture =
      DatabaseService.getCompanyProfile();
  PhotoSaveSizeMode _photoSaveSizeMode = PhotoSaveSizeMode.balanced;
  DocumentEdgeMode _documentEdgeMode = DocumentEdgeMode.auto;
  ActivationStatus? _activationStatus;
  static const List<String> _monthNames = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String _monthLabel(int monthNumber) {
    final safeMonth = monthNumber.clamp(1, 12);
    return _monthNames[safeMonth - 1];
  }

  @override
  void initState() {
    super.initState();
    _loadPhotoSaveMode();
    _loadDocumentEdgeMode();
    _loadActivationStatus();
  }

  Future<void> _loadPhotoSaveMode() async {
    final mode = await AppPhotoSaveSettings.getMode();
    if (!mounted) return;
    setState(() => _photoSaveSizeMode = mode);
  }

  Future<void> _loadDocumentEdgeMode() async {
    final mode = await AppDocumentCaptureSettings.getMode();
    if (!mounted) return;
    setState(() => _documentEdgeMode = mode);
  }

  Future<void> _loadActivationStatus() async {
    final status = await ActivationLicenseService.evaluate();
    if (!mounted) return;
    setState(() => _activationStatus = status);
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          buildPageTitleBanner(
            context,
            title: 'Management',
            icon: Icons.settings_outlined,
          ),
          const SizedBox(height: 12),
          const _SectionHeader(title: 'Company'),
          Card(
            child: FutureBuilder<CompanyProfile?>(
              future: _companyProfileFuture,
              builder: (context, snapshot) {
                final profile = snapshot.data;
                final subtitle = profile == null
                    ? 'Not set'
                    : '${profile.clientName} (${profile.companyCode})\n'
                        'Nature: ${profile.businessNature}\n'
                        'FY starts: ${_monthLabel(profile.financialYearStartMonth)}';
                return ListTile(
                  leading: Icon(Icons.person, color: colorScheme.primary),
                  title: const Text('Company info'),
                  subtitle: Text(subtitle),
                  isThreeLine: true,
                  trailing: const Icon(Icons.edit, size: 20),
                  onTap: () => _editCompanyInfo(context),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          const _SectionHeader(title: 'Data'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.backup, color: colorScheme.primary),
                  title: const Text('Backup database and images'),
                  subtitle: const Text(
                      'Saves ZIP on phone first, then you can upload/share'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => _runBackup(context),
                ),
                _SettingsDivider(),
                ListTile(
                  leading:
                      Icon(Icons.photo_library, color: colorScheme.primary),
                  title: const Text('Backup receipt images'),
                  subtitle:
                      const Text('Creates a ZIP of invoice/receipt photos'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => _runPhotoBackup(context),
                ),
                _SettingsDivider(),
                ListTile(
                  leading: Icon(Icons.restore, color: colorScheme.primary),
                  title: const Text('Restore backup'),
                  subtitle:
                      const Text('Restore from local backups saved on phone'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => _runRestore(context),
                ),
                _SettingsDivider(),
                ListTile(
                  leading: Icon(Icons.folder_open, color: colorScheme.primary),
                  title: const Text('Restore from file'),
                  subtitle: const Text(
                      'Pick ZIP from Files/Drive/OneDrive/USB (use system Back to cancel)'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => _runRestoreFromFile(context),
                ),
                _SettingsDivider(),
                ListTile(
                  leading: Icon(Icons.delete_forever, color: colorScheme.error),
                  title: Text('Reset database',
                      style: TextStyle(color: colorScheme.error)),
                  subtitle: const Text(
                      'Delete receipts and photos (operations are kept)'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => _confirmReset(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _SectionHeader(title: 'Operations'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.edit, color: colorScheme.primary),
                  title: const Text('Edit operation'),
                  subtitle:
                      const Text('Select an operation and edit its details'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => _editOperationFromManagement(context),
                ),
                _SettingsDivider(),
                ListTile(
                  leading: Icon(Icons.delete_outline, color: colorScheme.error),
                  title: Text('Delete operation',
                      style: TextStyle(color: colorScheme.error)),
                  subtitle: const Text(
                      'Select an operation and remove it if no receipts exist'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => _deleteOperationFromManagement(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _SectionHeader(title: 'App'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.auto_awesome, color: colorScheme.primary),
                  title: const Text('Gemini API Settings'),
                  subtitle: const Text('Configure API key and model'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const GeminiSettingsPage()),
                    );
                  },
                ),
                _SettingsDivider(),
                ListTile(
                  leading: Icon(Icons.photo_size_select_large,
                      color: colorScheme.primary),
                  title: const Text('Photo save size'),
                  subtitle: Text(
                    _photoSaveSizeMode == PhotoSaveSizeMode.compact
                        ? 'Compact (smaller file)'
                        : 'Balanced (default)',
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => _pickPhotoSaveSize(context),
                ),
                _SettingsDivider(),
                ListTile(
                  leading: Icon(Icons.crop_free, color: colorScheme.primary),
                  title: const Text('Document edge mode'),
                  subtitle: Text(
                    _documentEdgeMode == DocumentEdgeMode.auto
                        ? 'Auto (recommended)'
                        : 'Manual',
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => _pickDocumentEdgeMode(context),
                ),
                if (!ActivationLicenseService.developmentBypass) ...[
                  _SettingsDivider(),
                  ListTile(
                    leading: Icon(
                      (_activationStatus?.isActive ?? false)
                          ? Icons.verified_user
                          : Icons.key,
                      color: (_activationStatus?.isActive ?? false)
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    title: const Text('Activation'),
                    subtitle: Text(
                      _activationStatus?.message ?? 'Not activated',
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => _manageActivationKey(context),
                  ),
                ],
                _SettingsDivider(),
                ListTile(
                  leading: Icon(Icons.info_outline,
                      color: colorScheme.onSurfaceVariant),
                  title: const Text('About'),
                  subtitle: const Text('Exp_Track v0.9.0'),
                ),
                _SettingsDivider(),
                ListTile(
                  leading: Icon(Icons.exit_to_app, color: colorScheme.error),
                  title: Text('Exit app',
                      style: TextStyle(color: colorScheme.error)),
                  onTap: () => SystemNavigator.pop(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDocumentEdgeMode(BuildContext context) async {
    final selected = await showModalBottomSheet<DocumentEdgeMode>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Document edge mode',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Icon(
                  _documentEdgeMode == DocumentEdgeMode.auto
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                ),
                title: const Text('Auto'),
                subtitle: const Text('Auto-detect edges and correct angle'),
                onTap: () => Navigator.pop(ctx, DocumentEdgeMode.auto),
              ),
              ListTile(
                leading: Icon(
                  _documentEdgeMode == DocumentEdgeMode.manual
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                ),
                title: const Text('Manual'),
                subtitle:
                    const Text('Use normal camera/gallery without correction'),
                onTap: () => Navigator.pop(ctx, DocumentEdgeMode.manual),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || selected == _documentEdgeMode) return;
    await AppDocumentCaptureSettings.setMode(selected);
    if (!context.mounted) return;
    setState(() => _documentEdgeMode = selected);
    _showMessage(
      context,
      selected == DocumentEdgeMode.auto
          ? 'Document edge mode set to Auto.'
          : 'Document edge mode set to Manual.',
    );
  }

  Future<void> _pickPhotoSaveSize(BuildContext context) async {
    final selected = await showModalBottomSheet<PhotoSaveSizeMode>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Photo save size',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Icon(
                  _photoSaveSizeMode == PhotoSaveSizeMode.balanced
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                ),
                title: const Text('Balanced'),
                subtitle: const Text('Good readability with smaller size'),
                onTap: () => Navigator.pop(ctx, PhotoSaveSizeMode.balanced),
              ),
              ListTile(
                leading: Icon(
                  _photoSaveSizeMode == PhotoSaveSizeMode.compact
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                ),
                title: const Text('Compact'),
                subtitle: const Text('Smallest size, still readable'),
                onTap: () => Navigator.pop(ctx, PhotoSaveSizeMode.compact),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || selected == _photoSaveSizeMode) return;
    await AppPhotoSaveSettings.setMode(selected);
    if (!context.mounted) return;
    setState(() => _photoSaveSizeMode = selected);
    _showMessage(
      context,
      selected == PhotoSaveSizeMode.compact
          ? 'Photo save size set to Compact.'
          : 'Photo save size set to Balanced.',
    );
  }

  Future<CompanyProfile?> _companyProfile() async {
    return DatabaseService.getCompanyProfile();
  }

  Future<String> _clientName() async {
    final profile = await _companyProfile();
    final name = profile?.clientName.trim() ?? '';
    return name.isEmpty ? 'Client' : name;
  }

  Future<void> _editCompanyInfo(BuildContext context) async {
    final current = await _companyProfile();
    if (!context.mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _CompanyInfoEditPage(
          initial: current,
          monthNames: _monthNames,
        ),
      ),
    );
    if (saved != true || !context.mounted) return;
    _showMessage(context, 'Company info saved.');
    if (!context.mounted) return;
    setState(() {
      _companyProfileFuture = _companyProfile();
    });
    await _loadActivationStatus();
  }

  Future<void> _manageActivationKey(BuildContext context) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _ActivationKeyPage()),
    );
    if (!mounted || result == null || result == 'CANCEL') return;
    await _loadActivationStatus();
    if (!mounted) return;
    _showMessage(
      context,
      result == 'CLEARED'
          ? 'Activation cleared.'
          : (_activationStatus?.message ?? 'Activation updated.'),
    );
  }

  Future<void> _runBackup(BuildContext context) async {
    _showMessage(context, 'Building backup...');
    try {
      final backup = await _createFullBackupZip();
      if (!context.mounted) return;
      _showMessage(
        context,
        'Saved on phone: ${backup.path}',
      );
      await Share.shareXFiles(
        [XFile(backup.path, mimeType: 'application/zip')],
        subject: 'Exp_Track Backup',
        text:
            'Full backup ZIP. Keep this file to restore database and receipt images.',
      );
      if (!context.mounted) return;
      _showMessage(context, 'Backup ready: ${p.basename(backup.path)}');
    } catch (e) {
      if (!context.mounted) return;
      _showMessage(context, 'Backup failed: $e');
    }
  }

  Future<void> _runPhotoBackup(BuildContext context) async {
    _showMessage(context, 'Building image backup...');
    try {
      final backup = await _createPhotoBackupZip();
      if (!context.mounted) return;
      _showMessage(
        context,
        'Saved on phone: ${backup.path}',
      );
      await Share.shareXFiles(
        [XFile(backup.path, mimeType: 'application/zip')],
        subject: 'Receipt Image Backup',
        text: 'Receipt/invoice image ZIP backup.',
      );
      if (!context.mounted) return;
      _showMessage(context, 'Image backup ready: ${p.basename(backup.path)}');
    } catch (e) {
      if (!context.mounted) return;
      _showMessage(context, 'Image backup failed: $e');
    }
  }

  Future<void> _runRestore(BuildContext context) async {
    final backups = await _localFullBackups();
    if (!context.mounted) return;
    if (backups.isEmpty) {
      _showMessage(
          context, 'No local full backups found. Create a backup first.');
      return;
    }

    final selected = await _pickLocalBackupForRestore(context, backups);
    if (selected == null || !context.mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber, color: Colors.orange.shade700),
        title: const Text('Restore this backup?'),
        content: Text(
          'This will replace the current database and receipt images with:\n\n${p.basename(selected.path)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      await _restoreFullBackup(selected);
      if (!context.mounted) return;
      _showMessage(context, 'Restored. Close and reopen the app.');
      Navigator.of(context).pop();
    } catch (e) {
      if (!context.mounted) return;
      _showMessage(context, 'Restore failed: $e');
    }
  }

  Future<File?> _pickLocalBackupForRestore(
    BuildContext context,
    List<File> backups,
  ) async {
    final localBackups = List<File>.from(backups);
    return showDialog<File>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Restore backup'),
          content: SizedBox(
            width: double.maxFinite,
            child: localBackups.isEmpty
                ? const Text('No local backups available.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: localBackups.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 12, thickness: 0.8),
                    itemBuilder: (_, index) {
                      final backup = localBackups[index];
                      final modified = backup.existsSync()
                          ? DateFormat('dd/MM/yyyy HH:mm')
                              .format(backup.lastModifiedSync())
                          : 'Missing file';
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          p.basename(backup.path),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(modified),
                        onTap: () => Navigator.pop(dialogContext, backup),
                        trailing: IconButton(
                          tooltip: 'Delete backup',
                          icon: Icon(
                            Icons.delete_outline,
                            color: Theme.of(dialogContext).colorScheme.error,
                          ),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: dialogContext,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete backup file?'),
                                content: Text(
                                  'Delete ${p.basename(backup.path)} from local storage?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm != true) return;
                            try {
                              if (await backup.exists()) {
                                await backup.delete();
                              }
                              setDialogState(() {
                                localBackups.removeAt(index);
                              });
                              if (context.mounted) {
                                _showMessage(context, 'Backup deleted.');
                              }
                            } catch (e) {
                              if (context.mounted) {
                                _showMessage(
                                    context, 'Could not delete backup: $e');
                              }
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runRestoreFromFile(BuildContext context) async {
    final continueToPicker = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pick backup ZIP'),
        content: const Text(
          'You are opening the Android file picker.\n\n'
          '- Select a valid .zip backup file to continue.\n'
          '- To cancel, use the system Back gesture/button.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Open picker'),
          ),
        ],
      ),
    );
    if (continueToPicker != true || !context.mounted) return;

    File? selected;
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        withData: true,
      );
      if (!context.mounted) return;
      if (picked == null || picked.files.isEmpty) {
        _showMessage(context, 'Restore canceled.');
        return;
      }

      final file = picked.files.first;
      if (file.path != null && file.path!.isNotEmpty) {
        selected = File(file.path!);
      } else if (file.bytes != null) {
        final tempDir = await getTemporaryDirectory();
        final fallbackName =
            file.name.trim().isEmpty ? 'restore_backup.zip' : file.name.trim();
        final tempPath = p.join(
          tempDir.path,
          'picked_${DateTime.now().millisecondsSinceEpoch}_$fallbackName',
        );
        selected = File(tempPath);
        await selected.writeAsBytes(file.bytes!, flush: true);
      }
    } catch (e) {
      if (!context.mounted) return;
      _showMessage(context, 'Could not open file picker: $e');
      return;
    }

    final backupFile = selected;
    if (!context.mounted) return;
    if (backupFile == null) {
      _showMessage(context, 'No valid ZIP file selected.');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber, color: Colors.orange.shade700),
        title: const Text('Restore this backup file?'),
        content: Text(
          'This will replace the current database and receipt images with:\n\n${p.basename(backupFile.path)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      await _restoreFullBackup(backupFile);
      if (!context.mounted) return;
      _showMessage(context, 'Restored from file. Close and reopen the app.');
      Navigator.of(context).pop();
    } catch (e) {
      if (!context.mounted) return;
      _showMessage(context, 'Restore from file failed: $e');
    }
  }

  Future<void> _confirmReset(BuildContext context) async {
    final precheck = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber, color: Colors.orange.shade700),
        title: const Text('Backup recommended'),
        content: const Text(
          'Before reset, please create a backup. Reset will delete receipts and images only; operations will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, 'backup'),
            child: const Text('Backup now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'continue'),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (precheck == null || precheck == 'cancel' || !context.mounted) return;
    if (precheck == 'backup') {
      await _runBackup(context);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber, color: Colors.red.shade700),
        title: const Text('Final warning'),
        content: const Text(
          'All receipts and images will be removed from this system.\n'
          'Operations will be kept.\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (ok != true || !context.mounted) return;

    try {
      await DatabaseService.clearEverything();
      if (!context.mounted) return;
      _showMessage(context,
          'Reset complete. Receipts and images removed; operations kept.');
      Navigator.of(context).pop();
    } catch (e) {
      if (!context.mounted) return;
      _showMessage(context, 'Reset failed: $e');
    }
  }

  Future<Project?> _pickOperation(
    BuildContext context, {
    required String title,
  }) async {
    final projects = await DatabaseService.getProjects();
    if (!context.mounted) return null;
    if (projects.isEmpty) {
      _showMessage(context, 'No operations available.');
      return null;
    }
    return showDialog<Project>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          for (final project in projects)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, project),
              child: Text(project.name),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _editOperationFromManagement(BuildContext context) async {
    final project = await _pickOperation(
      context,
      title: 'Select operation to edit',
    );
    if (project == null || !context.mounted) return;

    final updated = await _showEditOperationDialog(context, project);
    if (updated == null || !context.mounted) return;

    try {
      await DatabaseService.updateProject(updated);
      if (!context.mounted) return;
      _showMessage(context, 'Operation updated.');
    } catch (e) {
      if (!context.mounted) return;
      _showMessage(context, 'Could not update operation: $e');
    }
  }

  Future<Project?> _showEditOperationDialog(
      BuildContext context, Project project) async {
    final name = TextEditingController(text: project.name);
    final address = TextEditingController(text: project.address ?? '');
    final budget = TextEditingController(
      text: project.budget == null ? '' : project.budget!.toStringAsFixed(2),
    );
    final notes = TextEditingController(text: project.notes ?? '');

    final result = await showDialog<Project>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit operation'),
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
                  id: project.id,
                  name: trimmedName,
                  address:
                      address.text.trim().isEmpty ? null : address.text.trim(),
                  budget: double.tryParse(budget.text),
                  notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
                  createdAt: project.createdAt,
                  updatedAt: project.updatedAt,
                ),
              );
            },
            child: const Text('Save'),
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

    return result;
  }

  Future<void> _deleteOperationFromManagement(BuildContext context) async {
    final project = await _pickOperation(
      context,
      title: 'Select operation to delete',
    );
    if (project == null || !context.mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete operation?'),
        content: Text(
          'Delete "${project.name}"?\n\nOperations with saved receipts cannot be deleted until their receipts are removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      await DatabaseService.deleteProject(project);
      if (!context.mounted) return;
      _showMessage(context, 'Operation deleted.');
    } catch (e) {
      if (!context.mounted) return;
      _showMessage(
        context,
        e.toString().replaceFirst('Bad state: ', ''),
      );
    }
  }

  Future<File> _createFullBackupZip() async {
    final backupsDir = await _backupsDir();
    final tempDir = await getTemporaryDirectory();
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final clientTag = _filenameTag(await _clientName());
    final backupName = [
      'receipt_scanner_backup',
      if (clientTag.isNotEmpty) clientTag,
      ts,
    ].join('_');
    final backupPath = p.join(
      backupsDir.path,
      '$backupName.zip',
    );

    await DatabaseService.closeConnection();
    final dbPath = await DatabaseService.getDatabasePath();
    final photosDir = await DatabaseService.getPhotosDir();
    final manifest =
        File(p.join(tempDir.path, 'receipt_backup_manifest_$ts.json'));
    await manifest.writeAsString(
      jsonEncode({
        'type': 'receipt_scanner_full_backup',
        'created_at': DateTime.now().toIso8601String(),
        'client_name': await _clientName(),
        'database': 'receipt_scanner.db',
        'photos_dir': 'receipts',
      }),
    );

    final encoder = ZipFileEncoder();
    encoder.create(backupPath);
    await encoder.addFile(File(dbPath), 'receipt_scanner.db');
    await encoder.addFile(manifest, 'manifest.json');
    if (await photosDir.exists()) {
      await encoder.addDirectory(photosDir, includeDirName: true);
    }
    await encoder.close();
    return File(backupPath);
  }

  Future<File> _createPhotoBackupZip() async {
    final photosDir = await DatabaseService.getPhotosDir();
    final photoCount = await _countFiles(photosDir);
    if (photoCount == 0) {
      throw StateError('No receipt images found.');
    }
    final backupsDir = await _backupsDir();
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final clientTag = _filenameTag(await _clientName());
    final backupName = [
      'receipt_images_backup',
      if (clientTag.isNotEmpty) clientTag,
      ts,
    ].join('_');
    final backupPath = p.join(
      backupsDir.path,
      '$backupName.zip',
    );
    final encoder = ZipFileEncoder();
    encoder.create(backupPath);
    await encoder.addDirectory(photosDir, includeDirName: true);
    await encoder.close();
    return File(backupPath);
  }

  Future<void> _restoreFullBackup(File backup) async {
    final tempDir = await getTemporaryDirectory();
    final restoreDir = Directory(
      p.join(tempDir.path,
          'receipt_restore_${DateTime.now().millisecondsSinceEpoch}'),
    );
    if (await restoreDir.exists()) {
      await restoreDir.delete(recursive: true);
    }
    await restoreDir.create(recursive: true);

    final archive = ZipDecoder().decodeBytes(await backup.readAsBytes());
    await extractArchiveToDisk(archive, restoreDir.path);

    await _validateRestoreBundle(restoreDir);

    final restoredDb = File(p.join(restoreDir.path, 'receipt_scanner.db'));
    if (!await restoredDb.exists()) {
      throw StateError('Backup does not contain receipt_scanner.db.');
    }

    await DatabaseService.closeConnection();
    final dbPath = await DatabaseService.getDatabasePath();
    await _validateDatabaseFile(restoredDb.path);
    await restoredDb.copy(dbPath);

    final restoredPhotos = Directory(p.join(restoreDir.path, 'receipts'));
    final photosDir = await DatabaseService.getPhotosDir();
    if (await photosDir.exists()) {
      await photosDir.delete(recursive: true);
    }
    await photosDir.create(recursive: true);
    if (await restoredPhotos.exists()) {
      await _copyDirectoryContents(restoredPhotos, photosDir);
    }
  }

  Future<void> _validateRestoreBundle(Directory restoreDir) async {
    final manifestFile = File(p.join(restoreDir.path, 'manifest.json'));
    if (!await manifestFile.exists()) {
      throw StateError('Backup is missing manifest.json.');
    }
    final decoded = jsonDecode(await manifestFile.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Backup manifest is invalid.');
    }
    if (decoded['type'] != 'receipt_scanner_full_backup') {
      throw StateError('Backup type is not supported.');
    }
    if ((decoded['database'] as String?) != 'receipt_scanner.db') {
      throw StateError('Backup manifest database target is invalid.');
    }
  }

  Future<void> _validateDatabaseFile(String dbPath) async {
    Database? probeDb;
    try {
      probeDb = await openDatabase(dbPath, readOnly: true);
      const requiredTables = <String>[
        'tbl_receipts',
        'tbl_projects',
      ];
      for (final table in requiredTables) {
        final tableRows = await probeDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
          [table],
        );
        if (tableRows.isEmpty) {
          throw StateError('Missing required table: $table');
        }
      }
      await probeDb.rawQuery('SELECT COUNT(*) FROM tbl_receipts');
      await probeDb.rawQuery('SELECT COUNT(*) FROM tbl_projects');
    } catch (_) {
      throw StateError('Backup database is corrupted or incompatible.');
    } finally {
      await probeDb?.close();
    }
  }

  Future<List<File>> _localFullBackups() async {
    final dir = await _backupsDir();
    final backups = dir
        .listSync()
        .whereType<File>()
        .where((file) =>
            p.basename(file.path).startsWith('receipt_scanner_backup_') &&
            p.extension(file.path).toLowerCase() == '.zip')
        .toList();
    backups
        .sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return backups;
  }

  Future<Directory> _backupsDir() async {
    final docDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docDir.path, 'backups'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> _copyDirectoryContents(
      Directory source, Directory target) async {
    await for (final entity in source.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: source.path);
      final destination = File(p.join(target.path, relative));
      await destination.parent.create(recursive: true);
      await entity.copy(destination.path);
    }
  }

  Future<int> _countFiles(Directory dir) async {
    if (!await dir.exists()) return 0;
    var count = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) count++;
    }
    return count;
  }

  String _filenameTag(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _CompanyInfoEditPage extends StatefulWidget {
  final CompanyProfile? initial;
  final List<String> monthNames;

  const _CompanyInfoEditPage({
    required this.initial,
    required this.monthNames,
  });

  @override
  State<_CompanyInfoEditPage> createState() => _CompanyInfoEditPageState();
}

class _ActivationKeyPage extends StatefulWidget {
  const _ActivationKeyPage();

  @override
  State<_ActivationKeyPage> createState() => _ActivationKeyPageState();
}

class _ActivationKeyPageState extends State<_ActivationKeyPage> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _scanOpen = false;
  ActivationStatus? _status;
  bool _showEditor = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final existing = await ActivationLicenseService.readActivationKey() ?? '';
    final status = await ActivationLicenseService.evaluate(
      keyOverride: existing,
    );
    if (!mounted) return;
    _controller.text = existing;
    setState(() {
      _status = status;
      _showEditor = !status.isActive;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _clear() async {
    if (_saving) return;
    setState(() => _saving = true);
    await ActivationLicenseService.clearActivationKey();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _status = const ActivationStatus(
        isActive: false,
        message: 'Not activated',
      );
      _showEditor = true;
      _controller.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Activation cleared.')),
    );
  }

  Future<void> _validateAndSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final raw = _controller.text.trim();
      final profile = await DatabaseService.getCompanyProfile();
      final companyCode = profile?.companyCode.trim() ?? '';
      final status = await ActivationLicenseService.evaluate(
        keyOverride: raw,
        companyCodeOverride: companyCode,
      );
      if (!mounted) return;
      if (!status.isActive) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(status.message)),
        );
        return;
      }
      await ActivationLicenseService.saveActivationKey(raw);
      if (!mounted) return;
      final refreshed = await ActivationLicenseService.evaluate();
      if (!mounted) return;
      setState(() {
        _status = refreshed;
        _saving = false;
        _showEditor = !refreshed.isActive;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(refreshed.message)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not validate activation key.')),
      );
    }
  }

  Future<void> _scanQr() async {
    if (_scanOpen || _saving) return;
    _scanOpen = true;
    try {
      final result = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const _ActivationQrScanPage()),
      );
      if (!mounted || result == null || result.trim().isEmpty) return;
      _controller.text = result.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('QR scanned. Review and tap Validate & Save.')),
      );
    } finally {
      _scanOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Activation')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if ((_status?.isActive ?? false) && !_showEditor)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Activation Active',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(_status?.message ?? 'Activated'),
                              if ((_status?.companyCode ?? '').isNotEmpty)
                                Text('Company: ${_status!.companyCode}'),
                              if (_status?.expiryDate != null)
                                Text(
                                  'Expiry: ${Receipt.formatDate(_status!.expiryDate!)}',
                                ),
                            ],
                          ),
                        ),
                      ),
                    if (_showEditor) ...[
                      TextField(
                        controller: _controller,
                        maxLines: 10,
                        minLines: 6,
                        decoration: const InputDecoration(
                          labelText: 'Activation key JSON',
                          hintText:
                              '{"payload_b64":"...","sig_b64":"...","alg":"Ed25519"}',
                        ),
                      ),
                      const SizedBox(height: 12),
                    ] else
                      const SizedBox(height: 12),
                    if (!_showEditor)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () => setState(() => _showEditor = true),
                          icon: const Icon(Icons.edit),
                          label: const Text('Replace activation'),
                        ),
                      ),
                    if (_showEditor)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _saving ? null : _clear,
                              child: const Text('Clear'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _saving ? null : _scanQr,
                              icon: const Icon(Icons.qr_code_scanner),
                              label: const Text('Scan QR'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: _saving ? null : _validateAndSave,
                              child: Text(
                                _saving ? 'Validating...' : 'Validate & Save',
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _saving ? null : _clear,
                          child: const Text('Clear activation'),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _CompanyInfoEditPageState extends State<_CompanyInfoEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _clientController;
  late final TextEditingController _companyCodeController;
  late final TextEditingController _natureController;
  late final TextEditingController _descriptionController;
  late int _fyStartMonth;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _clientController =
        TextEditingController(text: widget.initial?.clientName ?? '');
    _companyCodeController =
        TextEditingController(text: widget.initial?.companyCode ?? '');
    _natureController =
        TextEditingController(text: widget.initial?.businessNature ?? '');
    _descriptionController =
        TextEditingController(text: widget.initial?.businessDescription ?? '');
    _fyStartMonth =
        (widget.initial?.financialYearStartMonth ?? 4).clamp(1, 12).toInt();
  }

  @override
  void dispose() {
    _clientController.dispose();
    _companyCodeController.dispose();
    _natureController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await DatabaseService.saveCompanyProfile(
        clientName: _clientController.text,
        companyCode: _companyCodeController.text,
        businessNature: _natureController.text,
        businessDescription: _descriptionController.text,
        financialYearStartMonth: _fyStartMonth,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Company info'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _clientController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Client name *',
                        hintText: 'e.g. Iqbal Ahmed',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Client name is required'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _companyCodeController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Company code *',
                        hintText: 'e.g. YC001',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Company code is required'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _natureController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Nature of business *',
                        hintText:
                            'e.g. Restaurant, Garage, Builder, Trading services',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Nature of business is required'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _descriptionController,
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Business description / examples *',
                        hintText:
                            'Describe what counts as purchases, sundries, travel, etc.',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Business description is required'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: _fyStartMonth,
                      decoration: const InputDecoration(
                        labelText: 'Financial year start month *',
                      ),
                      items: List.generate(
                        12,
                        (index) => DropdownMenuItem<int>(
                          value: index + 1,
                          child: Text(widget.monthNames[index]),
                        ),
                      ),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _fyStartMonth = value);
                      },
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Save company info'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivationQrScanPage extends StatefulWidget {
  const _ActivationQrScanPage();

  @override
  State<_ActivationQrScanPage> createState() => _ActivationQrScanPageState();
}

class _ActivationQrScanPageState extends State<_ActivationQrScanPage> {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    if (capture.barcodes.isEmpty) return;
    final raw = (capture.barcodes.first.rawValue ?? '').trim();
    if (raw.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Activation QR')),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _onDetect,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              color: Colors.black54,
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              child: const Text(
                'Point camera at the activation QR code.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 56,
      endIndent: 16,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
