import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/database_service.dart';
import '../utils/theme.dart';
import '../widgets/ui_elements.dart';
import 'report_history.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _dbService = DatabaseService();
  final _picker = ImagePicker();
  final _issueController = TextEditingController();
  final _sensorIdController = TextEditingController();
  final _notesController = TextEditingController();
  final List<XFile> _images = [];
  bool _isSending = false;

  @override
  void dispose() {
    _issueController.dispose();
    _sensorIdController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
      );
      if (photo != null && mounted) {
        setState(() => _images.add(photo));
      }
    } catch (e) {
      if (mounted) _showSnack('Camera unavailable: $e');
    }
  }

  Future<void> _uploadFromGallery() async {
    try {
      final picked = await _picker.pickMultiImage(imageQuality: 70);
      if (picked.isNotEmpty && mounted) {
        setState(() => _images.addAll(picked));
      }
    } catch (e) {
      if (mounted) _showSnack('Gallery unavailable: $e');
    }
  }

  void _removeImage(int index) {
    setState(() => _images.removeAt(index));
  }

  Future<void> _sendReport() async {
    final issue = _issueController.text.trim();
    final sensorId = _sensorIdController.text.trim();
    final notes = _notesController.text.trim();

    if (issue.isEmpty) {
      _showSnack('Please describe the main issue.');
      return;
    }

    setState(() => _isSending = true);
    try {
      // Upload images first (if any), then save the report with their URLs.
      final reportId = DateTime.now().millisecondsSinceEpoch.toString();
      final urls = _images.isNotEmpty
          ? await _dbService.uploadReportImages(
              reportId: reportId,
              images: _images.map((x) => File(x.path)).toList(),
            )
          : <String>[];

      await _dbService.saveReport(
        issue: issue,
        sensorId: sensorId.isEmpty ? 'Unknown' : sensorId,
        notes: notes,
        imageUrls: urls,
      );

      if (!mounted) return;
      _issueController.clear();
      _sensorIdController.clear();
      _notesController.clear();
      setState(() => _images.clear());
      _showSnack(
        urls.isEmpty
            ? 'Report sent to admin.'
            : 'Report sent to admin with ${urls.length} image(s).',
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to send: $e');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Remark Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: AppColors.googleBlue),
            tooltip: 'Report History',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReportHistoryScreen()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Incident Source'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextField(
                        controller: _issueController,
                        decoration: const InputDecoration(
                          labelText: 'MAIN ISSUE',
                          hintText: 'e.g. Low Water Level - Tank 3',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.lightGrey,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'TIMESTAMP',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1,
                                      color: AppColors.greyText,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatTimestamp(DateTime.now()),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.darkText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _sensorIdController,
                              decoration: const InputDecoration(
                                labelText: 'SENSOR ID',
                                hintText: 'e.g. WL-01',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              const SectionLabel('Operator Notes'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _notesController,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'NOTES',
                      hintText: 'Describe what happened, readings observed, '
                          'and any action taken...',
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              const SectionLabel('Incident Visuals'),
              Row(
                children: [
                  Expanded(
                    child: DashedBox(
                      child: InkWell(
                        onTap: _takePhoto,
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.photo_camera_outlined,
                                color: AppColors.googleBlue, size: 26),
                            SizedBox(height: 6),
                            Text(
                              'USE CAMERA',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                                color: AppColors.greyText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DashedBox(
                      child: InkWell(
                        onTap: _uploadFromGallery,
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.photo_library_outlined,
                                color: AppColors.googleBlue, size: 26),
                            SizedBox(height: 6),
                            Text(
                              'UPLOAD MEDIA',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                                color: AppColors.greyText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // ── Picked image previews ──────────────────────────
              if (_images.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _images.length; i++)
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(_images[i].path),
                              width: 88,
                              height: 88,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: GestureDetector(
                              onTap: () => _removeImage(i),
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: AppColors.googleRed,
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(2),
                                child: const Icon(
                                  Icons.close,
                                  size: 14,
                                  color: AppColors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 28),

              _isSending
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: _sendReport,
                      icon: const Icon(Icons.send, size: 18),
                      label: Text(
                        _images.isEmpty
                            ? 'SEND TO ADMIN'
                            : 'SEND ${_images.length} IMAGE(S) TO ADMIN',
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime t) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${t.day} ${months[t.month - 1]} ${t.year} · '
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }
}
