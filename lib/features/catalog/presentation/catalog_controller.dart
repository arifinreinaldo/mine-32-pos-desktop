import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../data/catalog_repository.dart';
import '../domain/catalog_item.dart';

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  final services = ref.watch(appServicesProvider);
  return CatalogRepository(
    db: services.db,
    changeLog: services.changeLog,
    hlcService: services.hlc,
    clock: services.clock,
  );
});

/// Current search text for the catalog list.
class CatalogQuery extends Notifier<String> {
  @override
  String build() => '';
  void update(String value) => state = value;
}

final catalogQueryProvider = NotifierProvider<CatalogQuery, String>(
  CatalogQuery.new,
);

/// Reactive catalog list filtered by the current query.
final catalogItemsProvider = StreamProvider.autoDispose<List<CatalogItem>>((
  ref,
) {
  final repo = ref.watch(catalogRepositoryProvider);
  final query = ref.watch(catalogQueryProvider);
  return repo.watch(query: query);
});
