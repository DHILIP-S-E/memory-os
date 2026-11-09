import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:personal_memory_os/core/providers/memory_provider.dart';
import 'package:personal_memory_os/core/theme/app_theme.dart';
import 'package:personal_memory_os/core/utils/date_utils.dart';

class MemorySearchScreen extends StatefulWidget {
  const MemorySearchScreen({super.key});

  @override
  State<MemorySearchScreen> createState() => _MemorySearchScreenState();
}

class _MemorySearchScreenState extends State<MemorySearchScreen> {
  final _controller = TextEditingController();

  static const _suggestions = [
    'AI agents',
    'AI agents',
    'RAG',
    'what did I learn last month',
    'action items',
    'hackathon',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search(String query) {
    context.read<MemoryProvider>().search(query);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          style: AppTextStyles.bodyLarge,
          decoration: const InputDecoration(
            hintText: 'Search your memory…',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
          onSubmitted: _search,
          onChanged: (v) {
            if (v.isEmpty) context.read<MemoryProvider>().clearSearch();
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _search(_controller.text),
          ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Consumer<MemoryProvider>(
        builder: (context, provider, _) {
          if (provider.isSearching) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            );
          }

          if (!provider.hasSearchResults && provider.searchQuery.isEmpty) {
            return _buildSuggestions();
          }

          if (!provider.hasSearchResults) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.search_off,
                      size: 48, color: AppColors.textMuted),
                  const SizedBox(height: 16),
                  Text(
                    'No results for "${provider.searchQuery}"',
                    style: AppTextStyles.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.push('/memory/ai-chat'),
                    child: const Text('Try asking AI instead'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: provider.searchResults.length,
            itemBuilder: (_, i) {
              final doc = provider.searchResults[i];
              return _SearchResultCard(doc: doc);
            },
          );
        },
      ),
    );
  }

  Widget _buildSuggestions() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Try searching for',
            style: AppTextStyles.labelLarge
                .copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _suggestions
                .map(
                  (s) => GestureDetector(
                    onTap: () {
                      _controller.text = s;
                      _search(s);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Text(s, style: AppTextStyles.bodyMedium),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  final dynamic doc;

  const _SearchResultCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            doc.eventTitle ?? 'Memory',
            style: AppTextStyles.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            AppDateUtils.formatDateFull(doc.eventDate),
            style: AppTextStyles.caption,
          ),
          if (doc.overview != null) ...[
            const SizedBox(height: 8),
            Text(
              doc.overview!,
              style: AppTextStyles.bodyMedium,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (doc.keyTopics.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: (doc.keyTopics as List)
                  .take(4)
                  .map(
                    (t) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        t,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.accent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}
