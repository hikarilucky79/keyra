
import 'package:flutter/foundation.dart';
import 'package:keyra_app/ipc/models.dart';
import 'package:keyra_app/ipc/ipc_client.dart';

class ImportFileInfo {
  final String id;
  final String originalPath;
  String inferredKey;
  final List<double> waveform;

  ImportFileInfo({
    required this.id,
    required this.originalPath,
    required this.inferredKey,
    required this.waveform,
  });

  factory ImportFileInfo.fromMap(Map<String, dynamic> map) {
    return ImportFileInfo(
      id: map['id'],
      originalPath: map['original_path'],
      inferredKey: map['inferred_key'],
      waveform: List<double>.from(map['waveform']),
    );
  }
}

class ImportService extends ChangeNotifier {
  final KeyraIpcClient _ipc;
  
  bool _isImporting = false;
  bool get isImporting => _isImporting;

  List<ImportFileInfo> _files = [];
  List<ImportFileInfo> get files => _files;

  double _progress = 0.0;
  double get progress => _progress;

  String _progressMessage = '';
  String get progressMessage => _progressMessage;

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  ImportService(this._ipc) {
    _ipc.events.listen(_handleEvent);
  }

  void _handleEvent(DaemonEvent event) {
    if (event is ImportSessionStartedEvent) {
      _files = event.files.map((f) => ImportFileInfo.fromMap(f)).toList();
      _isImporting = true;
      notifyListeners();
    } else if (event is ImportProgressEvent) {
      _progress = event.progress;
      _progressMessage = event.message;
      _isProcessing = true;
      notifyListeners();
    } else if (event is ImportFinishedEvent) {
      _isImporting = false;
      _isProcessing = false;
      _progress = 1.0;
      notifyListeners();
    } else if (event is ErrorEvent) {
      _isProcessing = false;
      notifyListeners();
    }
  }

  void requestImport(String path) {
    _files = [];
    _progress = 0.0;
    _isProcessing = false;
    _ipc.sendCommand(ImportRequestCommand(path));
  }

  void updateMapping(String fileId, String key) {
    final index = _files.indexWhere((f) => f.id == fileId);
    if (index != -1) {
      _files[index].inferredKey = key;
      notifyListeners();
      _ipc.sendCommand(ImportUpdateMappingCommand(fileId: fileId, key: key));
    }
  }

  void previewSound(String fileId) {
    _ipc.sendCommand(ImportPreviewCommand(fileId));
  }

  void finalizeImport(String name, String author) {
    _isProcessing = true;
    notifyListeners();
    _ipc.sendCommand(ImportProcessCommand(name: name, author: author));
  }

  void cancelImport() {
    _isImporting = false;
    _ipc.sendCommand(ImportCancelCommand());
    notifyListeners();
  }
}
