part of '../main.dart';

class GeminiSettingsPage extends StatefulWidget {
  const GeminiSettingsPage({super.key});

  @override
  State<GeminiSettingsPage> createState() => _GeminiSettingsPageState();
}

class _GeminiSettingsPageState extends State<GeminiSettingsPage> {
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  late List<String> _modelOptions;
  String _scanMode = GeminiService.scanModeFast;
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  bool _obscureKey = true;
  bool _usingEnvFallback = false;
  String? _lastScanModel;

  @override
  void initState() {
    super.initState();
    _modelOptions = List<String>.from(GeminiService.selectableModels);
    _modelController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadSettings();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _loading = true);
    final settings = await GeminiService.loadSettings();
    final savedKey = await GeminiService.savedApiKey();
    final savedOptions = await GeminiService.savedModelOptions();
    final lastScanModel = await GeminiService.lastScanModel();
    if (!mounted) return;
    setState(() {
      _modelOptions = List<String>.from(savedOptions);
      _apiKeyController.text = savedKey ?? '';
      _modelController.text = settings.model;
      _scanMode = settings.scanMode;
      if (settings.model.trim().isNotEmpty &&
          !_modelOptions.contains(settings.model.trim())) {
        _modelOptions.add(settings.model.trim());
      }
      _usingEnvFallback = settings.usesEnvKey && !settings.hasSavedApiKey;
      _lastScanModel = lastScanModel;
      _loading = false;
    });
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    try {
      await GeminiService.saveSettings(
        apiKey: _apiKeyController.text,
        model: _modelController.text,
        scanMode: _scanMode,
      );
      await GeminiService.saveModelOptions(_modelOptions);
      if (!mounted) return;
      await _loadSettings();
      if (!mounted) return;
      _showMessage(
        _apiKeyController.text.trim().isEmpty
            ? 'Gemini settings saved. Using .env API key if available.'
            : 'Gemini settings saved.',
      );
    } catch (e) {
      if (!mounted) return;
      _showMessage(e.toString().replaceFirst('Invalid argument(s): ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testSettings() async {
    setState(() => _testing = true);
    final result = await GeminiService.checkSettings(
      apiKey: _apiKeyController.text,
      model: _modelController.text,
    );
    if (!mounted) return;
    setState(() => _testing = false);
    if (!result.success) {
      _showMessage(result.errorMessage ?? 'Gemini check failed.');
      return;
    }

    final workingModel = result.workingModel;
    if (workingModel == null) {
      _showMessage('Gemini connection works.');
      return;
    }

    if (result.usedFallback) {
      setState(() => _modelController.text = workingModel);
      _showMessage(
          'Selected model failed. $workingModel works and is ready to save.');
    } else {
      _showMessage('Gemini connection works with $workingModel.');
    }
  }

  Future<void> _resetToEnv() async {
    setState(() => _saving = true);
    try {
      await GeminiService.resetSettings();
      if (!mounted) return;
      await _loadSettings();
      if (!mounted) return;
      _showMessage('Gemini settings reset to .env fallback.');
    } catch (e) {
      if (!mounted) return;
      _showMessage('Could not reset Gemini settings: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _useModel(String model) {
    _modelController.text = model;
  }

  String _normalizeModelId(String value) => value.trim();

  void _addCurrentModelToList() {
    final model = _normalizeModelId(_modelController.text);
    if (model.isEmpty) {
      _showMessage('Enter a model ID first.');
      return;
    }
    if (_modelOptions.contains(model)) {
      _showMessage('Model already exists in list.');
      return;
    }
    setState(() => _modelOptions.add(model));
    unawaited(GeminiService.saveModelOptions(_modelOptions));
    _showMessage('Added $model to model list.');
  }

  Future<void> _editModelOption(String model) async {
    final controller = TextEditingController(text: model);
    final updated = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit model option'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Model ID',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (updated == null) return;
    final next = _normalizeModelId(updated);
    if (next.isEmpty) {
      _showMessage('Model ID cannot be empty.');
      return;
    }
    if (next != model && _modelOptions.contains(next)) {
      _showMessage('Model already exists in list.');
      return;
    }
    setState(() {
      final idx = _modelOptions.indexOf(model);
      if (idx >= 0) _modelOptions[idx] = next;
      if (_modelController.text.trim() == model) {
        _modelController.text = next;
      }
    });
    await GeminiService.saveModelOptions(_modelOptions);
  }

  void _removeModelOption(String model) {
    setState(() => _modelOptions.remove(model));
    unawaited(GeminiService.saveModelOptions(_modelOptions));
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
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
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  buildPageTitleBanner(
                    context,
                    title: 'Gemini settings',
                    icon: Icons.auto_awesome,
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Provider: Gemini',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: colorScheme.outlineVariant,
                              ),
                            ),
                            child: Text(
                              _lastScanModel == null
                                  ? 'Last scan model used: not available yet'
                                  : 'Last scan model used: $_lastScanModel',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _apiKeyController,
                            obscureText: _obscureKey,
                            keyboardType: TextInputType.visiblePassword,
                            decoration: InputDecoration(
                              labelText: 'Client Gemini API key',
                              helperText: _usingEnvFallback
                                  ? 'No client key saved. The app is using the .env key.'
                                  : 'Leave empty to use the .env key on this device.',
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                tooltip: _obscureKey ? 'Show key' : 'Hide key',
                                onPressed: () {
                                  setState(() => _obscureKey = !_obscureKey);
                                },
                                icon: Icon(
                                  _obscureKey
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _modelController,
                            decoration: const InputDecoration(
                              labelText: 'Custom Gemini model (optional)',
                              hintText: 'e.g. gemini-2.5-flash-lite',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: _addCurrentModelToList,
                              icon: const Icon(Icons.add),
                              label: const Text('Add current model to list'),
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (_modelOptions.isNotEmpty)
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: colorScheme.outlineVariant,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                children: [
                                  for (var i = 0; i < _modelOptions.length; i++)
                                    ListTile(
                                      dense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 8),
                                      title: Text(_modelOptions[i]),
                                      leading: Icon(
                                        _modelController.text.trim() ==
                                                _modelOptions[i]
                                            ? Icons.radio_button_checked
                                            : Icons.radio_button_off,
                                      ),
                                      onTap: () => _useModel(_modelOptions[i]),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            visualDensity:
                                                VisualDensity.compact,
                                            constraints: const BoxConstraints(
                                              minWidth: 32,
                                              minHeight: 32,
                                            ),
                                            padding: EdgeInsets.zero,
                                            tooltip: 'Edit',
                                            onPressed: () => _editModelOption(
                                              _modelOptions[i],
                                            ),
                                            icon: const Icon(Icons.edit,
                                                size: 20),
                                          ),
                                          IconButton(
                                            visualDensity:
                                                VisualDensity.compact,
                                            constraints: const BoxConstraints(
                                              minWidth: 32,
                                              minHeight: 32,
                                            ),
                                            padding: EdgeInsets.zero,
                                            tooltip: 'Delete',
                                            onPressed: () => _removeModelOption(
                                              _modelOptions[i],
                                            ),
                                            icon: const Icon(Icons.delete,
                                                size: 20),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saving ? null : _saveSettings,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: const Text('Save settings'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _testing ? null : _testSettings,
                    icon: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check),
                    label: const Text('Check Gemini settings'),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: _saving ? null : _resetToEnv,
                    icon: const Icon(Icons.restore),
                    label: const Text('Reset to .env'),
                  ),
                ],
              ),
      ),
    );
  }
}
