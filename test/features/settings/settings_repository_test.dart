import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine32_pos/core/database/app_database.dart';
import 'package:mine32_pos/core/sync/change_log_writer.dart';
import 'package:mine32_pos/core/sync/hlc_service.dart';
import 'package:mine32_pos/core/time/clock.dart';
import 'package:mine32_pos/features/settings/data/settings_repository.dart';
import 'package:mine32_pos/features/settings/domain/settings_draft.dart';

SettingsRepository _repo(AppDatabase db) {
  final clock = MutableClock(1000);
  final hlc = HlcService(db, clock, 'dev');
  final changeLog = ChangeLogWriter(db, 'dev');
  return SettingsRepository(
    db: db,
    changeLog: changeLog,
    hlcService: hlc,
    clock: clock,
  );
}

void main() {
  test(
    'seedDefault creates a row; save updates it; seed is idempotent',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = _repo(db);
      await repo.hlcService.load();

      await repo.seedDefault();
      var s = await repo.get();
      expect(s!.name, 'My Auto Parts');
      expect(s.currency, 'USD');

      await repo.save(
        const SettingsDraft(
          name: 'Mine32 Auto',
          npwp: '01.234.567.8-901.000',
          isPkp: true,
          currency: 'IDR',
          currencyScale: 0,
        ),
      );
      s = await repo.get();
      expect(s!.name, 'Mine32 Auto');
      expect(s.currency, 'IDR');
      expect(s.currencyScale, 0);
      expect(s.isPkp, isTrue);
      expect(s.taxNumber, '01.234.567.8-901.000');

      await repo.seedDefault(); // must not overwrite existing
      expect((await repo.get())!.name, 'Mine32 Auto');

      await db.close();
    },
  );
}
