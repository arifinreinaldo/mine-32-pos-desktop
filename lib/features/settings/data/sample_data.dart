import '../../../core/money/money.dart';
import '../../catalog/data/auto_parts_repository.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/domain/auto_parts_models.dart';
import '../../catalog/domain/part_draft.dart';
import '../../customers/data/customers_repository.dart';
import '../../customers/domain/customer_draft.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/domain/movement_reason.dart';
import '../../purchasing/data/purchasing_repository.dart';
import '../../purchasing/domain/purchasing_models.dart';

/// Seeds a realistic demo dataset (auto parts + stock + supplier + customer +
/// fitment) so the app is immediately usable. No-op if the catalog already has
/// parts. Returns the number of parts created.
class SampleData {
  static Future<int> load({
    required CatalogRepository catalog,
    required InventoryRepository inventory,
    required AutoPartsRepository autoParts,
    required PurchasingRepository purchasing,
    required CustomersRepository customers,
  }) async {
    final existing = await catalog.watch().first;
    if (existing.isNotEmpty) return 0;

    final locationId = await inventory.ensureDefaultLocation();

    // (name, sku, brand, price, cost, stock qty)
    const parts = <(String, String, String, int, int, int)>[
      ('Brake Pad Set Front', 'BP-1001', 'Bosch', 250000, 150000, 12),
      ('Oil Filter', 'OF-2002', 'Denso', 45000, 25000, 40),
      ('Air Filter', 'AF-3003', 'Mann', 80000, 45000, 25),
      ('Spark Plug Iridium', 'SP-4004', 'NGK', 35000, 18000, 100),
      ('Clutch Kit', 'CK-5005', 'Exedy', 1500000, 950000, 5),
      ('Timing Belt', 'TB-6006', 'Gates', 320000, 180000, 8),
      ('Wiper Blade 22"', 'WB-7007', 'Bosch', 90000, 40000, 30),
      ('Engine Oil 5W-30 4L', 'EO-8008', 'Shell', 280000, 200000, 50),
      ('Radiator Coolant 1L', 'RC-9009', 'Prestone', 55000, 30000, 60),
      ('Brake Fluid DOT4', 'BF-1010', 'Bosch', 60000, 32000, 45),
    ];

    final variantBySku = <String, String>{};
    for (final (name, sku, brand, price, cost, qty) in parts) {
      final variantId = await catalog.savePart(
        PartDraft(
          name: name,
          sku: sku,
          brandName: brand,
          price: Money(price),
          cost: Money(cost),
          coreCharge: const Money(0),
        ),
      );
      variantBySku[sku] = variantId;
      await inventory.addMovement(
        variantId: variantId,
        locationId: locationId,
        qty: qty,
        reason: MovementReason.purchase,
      );
    }

    // A vehicle + fitment + a cross-reference.
    final vehicleId = await autoParts.upsertVehicle(
      const VehicleDraft(
        make: 'Toyota',
        model: 'Avanza',
        yearFrom: 2015,
        yearTo: 2021,
        engine: '1.3L',
      ),
    );
    await autoParts.addFitment(
      variantId: variantBySku['BP-1001']!,
      vehicleId: vehicleId,
    );
    await autoParts.addCrossReference(
      variantId: variantBySku['OF-2002']!,
      otherNumber: '90915-YZZE1',
      otherBrand: 'Toyota',
      refType: 'oem',
    );

    // A supplier and a customer with a vehicle.
    await purchasing.saveSupplier(
      const SupplierDraft(name: 'PT Sumber Parts Jaya', phone: '021-555-1234'),
    );
    final customerId = await customers.saveCustomer(
      const CustomerDraft(name: 'Bengkel Maju', phone: '0812-3456-7890'),
    );
    await customers.addVehicle(
      customerId: customerId,
      plate: 'B 1234 ABC',
      description: 'Toyota Avanza 2018',
    );

    return parts.length;
  }
}
