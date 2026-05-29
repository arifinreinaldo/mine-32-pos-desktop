# Tax — Indonesia (CoreTax) readiness

Mine32 POS models the data needed to operate as an Indonesian VAT (PPN)
taxpayer and to feed the DJP **CoreTax** system (faktur pajak / e-Faktur).

## Concepts captured

| Concept | Where |
|---|---|
| Company NPWP (tax id) | `company_settings.taxNumber` |
| PKP status (VAT-registered) | `company_settings.isPkp` |
| Tax-inclusive pricing (common in ID retail) | `company_settings.taxInclusive` |
| PPN rate (11% / 12%) | `tax_rates` (`basisPoints`, `inclusive`, `taxType='PPN'`) |
| **DPP** (Dasar Pengenaan Pajak / tax base) | `sales.subtotalMinor`, `sale_lines` base |
| **PPN** (output tax) | `sales.taxTotalMinor`, `sale_lines.taxMinor` |
| Grand total (incl. PPN) | `sales.totalMinor` |
| Buyer identity (for B2B faktur) | `sales.buyerName`, `sales.buyerNpwp` |
| Faktur serial (NSFP) | `sales.fakturNumber` |

## How PPN is computed

`lib/features/accounting/domain/tax_math.dart` splits each line, using exact
integer math (half-up rounding):

- **Inclusive** (default): the listed price already contains PPN, so
  `DPP = price × 10000 / (10000 + rate_bp)` and `PPN = price − DPP`.
- **Exclusive**: `PPN = base × rate_bp / 10000`, added on top.

At checkout the default tax rate (seeded **PPN 11%**, inclusive) is applied per
line; the sale stores DPP, PPN and the grand total, and a balanced journal is
posted: `Dr Cash/Bank · Cr Sales Revenue (DPP) · Cr PPN Output (PPN)` plus
`Dr COGS · Cr Inventory`.

## Reporting

The **Reports** screen shows, for a chosen period, sales count, revenue, **DPP**
and **PPN (output tax)** — the figures a PKP needs for the monthly SPT Masa PPN.
`AccountingRepository.salesForTaxPeriod()` returns the per-sale rows (number,
date, buyer NPWP, faktur number, DPP, PPN) that a future CoreTax CSV/XML export
will serialise.

## Not yet done

- CoreTax CSV/XML faktur export file (data is ready; serialiser pending).
- Faktur serial-number (NSFP) management/sequence.
- PPnBM / multiple simultaneous tax components.
