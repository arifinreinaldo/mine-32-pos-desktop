import '../../../core/database/app_database.dart';
import '../../../core/database/sync_repository.dart';
import '../domain/settings_draft.dart';

/// Reads/writes the single company-settings row (id = 'default'). Master data,
/// so edits replicate via sync (LWW).
class SettingsRepository extends SyncRepository {
  static const String id = 'default';

  SettingsRepository({
    required super.db,
    required super.changeLog,
    required super.hlcService,
    required super.clock,
  });

  Stream<CompanySetting?> watch() {
    return (db.select(db.companySettings)
          ..where((t) => t.id.equals(id))
          ..limit(1))
        .watchSingleOrNull();
  }

  Future<CompanySetting?> get() {
    return (db.select(db.companySettings)
          ..where((t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> seedDefault() async {
    if (await get() != null) return;
    await save(const SettingsDraft(name: 'My Auto Parts'));
  }

  Future<void> save(SettingsDraft draft) async {
    final createdAt =
        await existingCreatedAt(db.companySettings, id) ?? clock.nowMillis();
    await writeSyncable<CompanySetting>(
      entityTable: 'company_settings',
      table: db.companySettings,
      rowId: id,
      build: (hlc, now) => CompanySetting(
        id: id,
        createdAt: createdAt,
        updatedAt: now,
        updatedHlc: hlc.pack(),
        name: draft.name,
        legalName: draft.legalName,
        address: draft.address,
        phone: draft.phone,
        email: draft.email,
        taxNumber: draft.npwp,
        isPkp: draft.isPkp,
        taxInclusive: draft.taxInclusive,
        currency: draft.currency,
        currencyScale: draft.currencyScale,
        receiptHeader: draft.receiptHeader,
        receiptFooter: draft.receiptFooter,
      ),
    );
  }
}
