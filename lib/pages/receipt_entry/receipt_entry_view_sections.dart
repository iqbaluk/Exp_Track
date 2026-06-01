part of '../../main.dart';

extension _ReceiptEntryViewSections on _ReceiptEntryPageState {
  Widget _buildScanDebugBadge() {
    final colorScheme = Theme.of(context).colorScheme;
    final telemetry = _lastScanTelemetry!;
    final modeLabel = telemetry.mode == GeminiService.scanModeFast
        ? 'Fast'
        : telemetry.mode == GeminiService.scanModeHandwritten
            ? 'Handwritten'
            : 'Quality';
    final statusLabel = telemetry.success ? 'ok' : 'failed';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.bug_report_outlined,
              size: 16, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Scan debug: $modeLabel | ${telemetry.model} | API ${telemetry.apiCalls} | $statusLabel',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentEntries() {
    final colorScheme = Theme.of(context).colorScheme;
    final headerText =
        '3. Recent Entries (Today)${_totalReceiptCount > 0 ? "  (Total: $_totalReceiptCount)" : ""}';

    if (_recentReceipts.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader(headerText),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(10),
              color: colorScheme.surfaceContainerLowest,
            ),
            child: Center(
              child: Text(
                'No scans saved today yet.',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(headerText),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(10),
            color: colorScheme.surfaceContainerLowest,
          ),
          child: Column(
            children: [
              for (var i = 0; i < _recentReceipts.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, color: colorScheme.outlineVariant),
                _buildReceiptRow(_recentReceipts[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReceiptRow(Receipt r) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _openDetail(r),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: r.photoPath != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Image.file(
                        File(r.photoPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (ignored, __, ___) => Icon(
                          Icons.broken_image,
                          size: 20,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.receipt_long,
                      size: 24,
                      color: colorScheme.onSurfaceVariant,
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (r.scanNo != null) ...[
                        Text(
                          '#${r.scanNo!.toString().padLeft(5, '0')}',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          r.category,
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        DateFormat('dd/MM/yy').format(r.date),
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      r.supplier,
                      if ((r.invoiceNumber ?? '').trim().isNotEmpty)
                        'Inv ${r.invoiceNumber!.trim()}',
                    ].join(' - '),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatAppMoney(r.gross),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _statusIsError
            ? colorScheme.errorContainer
            : colorScheme.primaryContainer,
        border: Border.all(
          color: _statusIsError
              ? colorScheme.error.withValues(alpha: 0.42)
              : colorScheme.primary.withValues(alpha: 0.34),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            _statusIsError ? Icons.error_outline : Icons.info_outline,
            size: 18,
            color: _statusIsError
                ? colorScheme.onErrorContainer
                : colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(_statusMessage!)),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => _mutateEntryState(() => _statusMessage = null),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    final colorScheme = Theme.of(context).colorScheme;
    if (_imageBytes == null) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
          color: colorScheme.surfaceContainerLowest,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.image_outlined,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 4),
              Text(
                'No photo selected',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
            child: InkWell(
              onTap: _openScanImageViewer,
              child: Image.memory(
                _imageBytes!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Icon(
                  Icons.image,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${_imageFileName ?? 'image'}  -  tap to zoom',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: _isScanning ? null : _takePhoto,
                  icon: const Icon(Icons.camera_alt, size: 14),
                  label: const Text('Retake', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                  ),
                ),
                TextButton.icon(
                  onPressed: _removeImage,
                  icon: const Icon(Icons.close, size: 14),
                  label: const Text('Remove', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 20,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


