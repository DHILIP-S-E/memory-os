import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:personal_memory_os/core/models/ai_message.dart';
import 'package:personal_memory_os/core/providers/memory_provider.dart';
import 'package:personal_memory_os/core/theme/app_theme.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  static const _starterQuestions = [
    'What did I learn about AI agents?',
    'Which event mentioned RAG?',
    'What action items did I collect last month?',
    'Show everything I captured about AI agents.',
  ];

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    context.read<MemoryProvider>().askQuestion(text);
    Future.delayed(const Duration(milliseconds: 300), _scrollToBottom);
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.psychology_outlined, color: AppColors.accent, size: 20),
            SizedBox(width: 8),
            Text('Ask your memory'),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear conversation',
            onPressed: () => context.read<MemoryProvider>().clearChat(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessages()),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    return Consumer<MemoryProvider>(
      builder: (context, provider, _) {
        if (provider.chatHistory.isEmpty) {
          return _buildWelcome();
        }
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: provider.chatHistory.length +
              (provider.isAsking ? 1 : 0),
          itemBuilder: (_, i) {
            if (i == provider.chatHistory.length) {
              return const _TypingIndicator();
            }
            final msg = provider.chatHistory[i];
            return _MessageBubble(message: msg);
          },
        );
      },
    );
  }

  Widget _buildWelcome() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.accent.withValues(alpha: 0.12),
                  AppColors.primaryLight.withValues(alpha: 0.4),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_awesome,
                    color: AppColors.accent, size: 24),
                const SizedBox(height: 10),
                const Text(
                  'Ask anything about your memory',
                  style: AppTextStyles.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Powered by Gemini. Every answer is grounded in your own captured content.',
                  style: AppTextStyles.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Try asking',
            style: AppTextStyles.labelLarge
                .copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          ..._starterQuestions.map(
            (q) => GestureDetector(
              onTap: () {
                _controller.text = q;
                _send();
              },
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(q, style: AppTextStyles.bodyLarge),
                    ),
                    const Icon(Icons.arrow_forward_ios,
                        size: 14, color: AppColors.textMuted),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.cardBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                style: AppTextStyles.bodyLarge,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(
                  hintText: 'Ask about your memory…',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: (_) => _send(),
                textInputAction: TextInputAction.send,
              ),
            ),
            const SizedBox(width: 8),
            Consumer<MemoryProvider>(
              builder: (_, p, __) => GestureDetector(
                onTap: p.isAsking ? null : _send,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: p.isAsking
                        ? AppColors.textMuted
                        : AppColors.accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: p.isAsking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send, color: Colors.white, size: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final AiMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isUser
                    ? AppColors.accent
                    : message.isError
                        ? AppColors.urgent.withValues(alpha: 0.15)
                        : AppColors.surfaceElevated,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: isUser
                    ? null
                    : Border.all(color: AppColors.cardBorder),
              ),
              child: Text(
                message.content,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: isUser ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ),
            if (!isUser && message.sources.isNotEmpty) ...[
              const SizedBox(height: 6),
              _SourcesList(sources: message.sources),
            ],
          ],
        ),
      ),
    );
  }
}

class _SourcesList extends StatelessWidget {
  final List<dynamic> sources;

  const _SourcesList({required this.sources});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sources',
          style: AppTextStyles.caption
              .copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 4),
        ...sources.map(
          (s) => Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bookmark_outline,
                    size: 12, color: AppColors.accent),
                const SizedBox(width: 6),
                Text(
                  s.eventTitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.accent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (s.captureRef != null) ...[
                  Text(
                    ' · ${s.captureRef}',
                    style: AppTextStyles.caption,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome,
                size: 14, color: AppColors.accent),
            const SizedBox(width: 8),
            Text(
              'Searching your memory…',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.accent),
            ),
          ],
        ),
      ),
    );
  }
}
