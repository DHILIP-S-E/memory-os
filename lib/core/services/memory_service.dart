import 'package:personal_memory_os/core/models/memory_document.dart';

abstract class MemoryService {
  Future<List<MemoryDocument>> fetchMemoryDocuments();
  Future<List<MemoryDocument>> searchMemory(String query);
}
