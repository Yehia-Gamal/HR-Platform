import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// قاعدة المعرفة على الموبايل (0352) — المنشور فقط، بحث + تصنيفات + قارئ.
class KnowledgePage extends ConsumerStatefulWidget {
  const KnowledgePage({super.key});

  @override
  ConsumerState<KnowledgePage> createState() => _KnowledgePageState();
}

class _KnowledgePageState extends ConsumerState<KnowledgePage> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _categoryId;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final catalog = ref.watch(knowledgeCatalogProvider(_query.trim()));

    return Scaffold(
      appBar: AppBar(title: const Text('قاعدة المعرفة')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'بحث في المقالات…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onSubmitted: (value) => setState(() => _query = value),
            ),
          ),
          catalog.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Text(humanizeError(error), textAlign: TextAlign.center),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(knowledgeCatalogProvider(_query.trim())),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
            data: (data) {
              final articles =
                  ((data['articles'] as List<dynamic>?) ?? const [])
                      .map(
                        (e) => KnowledgeArticle.fromJson(
                          Map<String, dynamic>.from(e as Map),
                        ),
                      )
                      .toList();
              final categories =
                  ((data['categories'] as List<dynamic>?) ?? const [])
                      .map(
                        (e) => KnowledgeCategory.fromJson(
                          Map<String, dynamic>.from(e as Map),
                        ),
                      )
                      .toList();

              final visible = _categoryId == null
                  ? articles
                  : articles
                        .where(
                          (a) =>
                              (a.categoryName) ==
                              categories
                                  .where((c) => c.id == _categoryId)
                                  .map((c) => c.name)
                                  .firstWhere(
                                    (_) => true,
                                    orElse: () => a.categoryName,
                                  ),
                        )
                        .toList();

              return Column(
                children: [
                  if (categories.isNotEmpty)
                    SizedBox(
                      height: 46,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                        children: [
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 8),
                            child: ChoiceChip(
                              label: const Text('الكل'),
                              selected: _categoryId == null,
                              onSelected: (_) =>
                                  setState(() => _categoryId = null),
                            ),
                          ),
                          for (final c in categories)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(end: 8),
                              child: ChoiceChip(
                                label: Text(c.name),
                                selected: _categoryId == c.id,
                                onSelected: (_) =>
                                    setState(() => _categoryId = c.id),
                              ),
                            ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: visible.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 120),
                              Icon(
                                Icons.menu_book_outlined,
                                size: 54,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 12),
                              Center(
                                child: Text(
                                  _query.isEmpty
                                      ? 'لا توجد مقالات منشورة بعد'
                                      : 'لا نتائج مطابقة للبحث',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                            itemCount: visible.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) => Card(
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                title: Text(
                                  visible[index].title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                subtitle: Text(
                                  visible[index].body,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Text(
                                  visible[index].updatedAt == null
                                      ? ''
                                      : DateFormat('d MMM', 'ar').format(
                                          visible[index].updatedAt!.toLocal(),
                                        ),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => KnowledgeReaderPage(
                                      article: visible[index],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// قارئ المقالة — عرض كامل للنص.
class KnowledgeReaderPage extends StatelessWidget {
  const KnowledgeReaderPage({required this.article, super.key});
  final KnowledgeArticle article;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          article.categoryName.isEmpty ? 'مقالة' : article.categoryName,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            article.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          if (article.updatedAt != null)
            Text(
              'آخر تحديث: ${DateFormat('d MMMM y', 'ar').format(article.updatedAt!.toLocal())}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          const Divider(height: 28),
          SelectableText(
            article.body,
            style: const TextStyle(fontSize: 15, height: 1.8),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
