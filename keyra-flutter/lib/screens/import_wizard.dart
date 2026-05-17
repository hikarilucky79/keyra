import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:keyra_app/services/import_service.dart';
import 'package:keyra_app/theme/keyra_theme.dart';

class ImportWizardScreen extends StatefulWidget {
  const ImportWizardScreen({super.key});

  @override
  State<ImportWizardScreen> createState() => _ImportWizardScreenState();
}

class _ImportWizardScreenState extends State<ImportWizardScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _authorController = TextEditingController();
  int _currentStep = 0;

  @override
  Widget build(BuildContext context) {
    final importService = context.watch<ImportService>();
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: KeyraTheme.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _buildHeader(importService),
          const SizedBox(height: 24),
          Expanded(
            child: _buildCurrentStep(importService),
          ),
          const SizedBox(height: 24),
          _buildFooter(importService),
        ],
      ),
    );
  }

  Widget _buildHeader(ImportService importService) {
    String title = 'Import Sound Pack';
    String subtitle = 'Drag and drop or select a folder to begin';

    if (importService.isImporting) {
      if (_currentStep == 1) {
        title = 'Review Mappings';
        subtitle = "We've inferred these keys from filenames. Tap to edit.";
      } else if (_currentStep == 2) {
        title = 'Finalize Pack';
        subtitle = 'Give your creation a name and author';
      }
    }

    if (importService.isProcessing) {
      title = 'Processing Audio';
      subtitle = importService.progressMessage;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: KeyraTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: KeyraTheme.primary.withValues(alpha: 0.2)),
              ),
              child: const Icon(Icons.download_rounded, color: KeyraTheme.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: KeyraTheme.h2),
                Text(subtitle, style: KeyraTheme.bodyMuted),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCurrentStep(ImportService importService) {
    if (importService.isProcessing) {
      return _buildProcessingStep(importService);
    }

    if (!importService.isImporting) {
      return _buildDropZone(importService);
    }

    return switch (_currentStep) {
      0 => _buildFileReview(importService),
      1 => _buildPackInfo(importService),
      _ => _buildFileReview(importService),
    };
  }

  Widget _buildDropZone(ImportService importService) {
    return DropTarget(
      onDragDone: (detail) {
        if (detail.files.isNotEmpty) {
          importService.requestImport(detail.files.first.path);
        }
      },
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: KeyraTheme.surface.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: KeyraTheme.overlay0.withValues(alpha: 0.2), width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_upload_outlined, size: 64, color: KeyraTheme.primary)
                .animate(onPlay: (c) => c.repeat())
                .shimmer(duration: 2.seconds),
            const SizedBox(height: 24),
            Text('Drop ZIP or Folder here', style: KeyraTheme.h3),
            const SizedBox(height: 8),
            const Text('or click to browse', style: TextStyle(color: KeyraTheme.overlay1)),
          ],
        ),
      ),
    );
  }

  Widget _buildFileReview(ImportService importService) {
    return ListView.builder(
      itemCount: importService.files.length,
      itemBuilder: (context, index) {
        final file = importService.files[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: KeyraTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: KeyraTheme.overlay0.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.play_arrow_rounded, color: KeyraTheme.primary),
                onPressed: () => importService.previewSound(file.id),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(file.originalPath.split('/').last, style: const TextStyle(fontWeight: FontWeight.w500)),
                    Text(file.originalPath, style: KeyraTheme.bodyMuted.copyWith(fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 120,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: file.inferredKey,
                    isExpanded: true,
                    items: ['default', 'enter', 'space', 'shift', 'backspace', 'tab', 'escape', 'up', 'down', 'left', 'right']
                        .map((k) => DropdownMenuItem(value: k, child: Text(k, style: const TextStyle(fontSize: 12))))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) importService.updateMapping(file.id, val);
                    },
                  ),
                ),
              ),
            ],
          ),
        ).animate().fadeIn(delay: (index * 50).ms).slideX(begin: 0.1);
      },
    );
  }

  Widget _buildPackInfo(ImportService importService) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildTextField('Pack Name', _nameController, 'e.g. My Thocky Pack'),
        const SizedBox(height: 16),
        _buildTextField('Author', _authorController, 'e.g. Hikari'),
      ],
    ).animate().fadeIn();
  }

  Widget _buildTextField(String label, TextEditingController controller, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: KeyraTheme.overlay1)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: KeyraTheme.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildProcessingStep(ImportService importService) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 160,
              height: 160,
              child: CircularProgressIndicator(
                value: importService.progress,
                strokeWidth: 8,
                color: KeyraTheme.primary,
                backgroundColor: KeyraTheme.overlay0.withValues(alpha: 0.1),
              ),
            ),
            Text('${(importService.progress * 100).toInt()}%', style: KeyraTheme.h1),
          ],
        ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),
        const SizedBox(height: 32),
        Text(importService.progressMessage, style: KeyraTheme.bodyMuted),
      ],
    );
  }

  Widget _buildFooter(ImportService importService) {
    if (importService.isProcessing) return const SizedBox();

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (importService.isImporting)
          TextButton(
            onPressed: () => importService.cancelImport(),
            child: const Text('Cancel'),
          ),
        const SizedBox(width: 12),
        if (importService.isImporting)
          ElevatedButton(
            onPressed: () {
              if (_currentStep < 1) {
                setState(() => _currentStep++);
              } else {
                importService.finalizeImport(
                  _nameController.text.isEmpty ? 'Unnamed Pack' : _nameController.text,
                  _authorController.text.isEmpty ? 'Unknown' : _authorController.text,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: KeyraTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(_currentStep < 1 ? 'Next' : 'Install Pack'),
          ),
      ],
    );
  }
}
