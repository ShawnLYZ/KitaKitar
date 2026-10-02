// Canonical points formula for QR redemption. smart_bin/config.h.example
// mirrors these constants only for the estimate it shows on the OLED.

/** One material line stored on a transaction. */
export type MaterialEntry = {
  type: string;
  weight: number;
  pricePerKg: number;
  isFree: boolean;
  co2?: number;
};

export type Redemption = {
  materials: MaterialEntry[];
  totalWeight: number;
  pointsUser: number;
  co2Saved: number;
  /** Weight per material type, added to the user's `stats`. */
  stats: Record<string, number>;
};

const BASE_MULTIPLIER = 100;
const FREE_BONUS = 1.5;
const CO2_POINTS_MULTIPLIER = 100;
const DEFAULT_CO2_PER_KG = 0.5;

/**
 * CO₂ saved per kg of each material type, keyed by material slug
 * (the canonical `type` string stored on QR/transaction materials).
 */
export const CO2_MULTIPLIERS: Readonly<Record<string, number>> = {
  paper: 0.65,
  plastic: 0.75,
  glass: 0.30,
  aluminum: 0.95,
  batteries: 0.80,
  electronics: 0.80,
  food: 0.50,
  lawn: 0.40,
  used_oil: 0.70,
  hazardous_waste: 0.90,
  tires: 0.60,
  metal: 0.85,
};

/** Thrown when a QR's transactionDraft can't be redeemed. */
export class InvalidDraftError extends Error {}

/**
 * CO₂ saved (kg) for one material entry: the stored AI estimate when
 * present (bin-created docs), otherwise weight × slug multiplier.
 */
export function materialCo2(
  type: string,
  weightKg: number,
  storedCo2: number | undefined,
): number {
  if (storedCo2 !== undefined) return storedCo2;
  return weightKg * (CO2_MULTIPLIERS[type] ?? DEFAULT_CO2_PER_KG);
}

function optionalNumber(value: unknown): number | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    throw new InvalidDraftError("Invalid QR code data");
  }
  return value;
}

/**
 * Computes the reward for a QR doc's `transactionDraft`:
 * points = round( Σ [ weight × 100 × (isFree ? 1.5 : 1) + co2 × 100 ] )
 * where co2 = stored value ?? weight × slug multiplier (0.5 default).
 */
export function computeRedemption(draft: unknown): Redemption {
  if (typeof draft !== "object" || draft === null) {
    throw new InvalidDraftError("Invalid QR code data");
  }
  const {materials, totalWeight} = draft as Record<string, unknown>;
  const total = optionalNumber(totalWeight) ?? 0;
  if (!Array.isArray(materials) || materials.length === 0 || total <= 0) {
    throw new InvalidDraftError("Invalid QR code data");
  }

  let pointsRaw = 0;
  let co2Saved = 0;
  const lines: MaterialEntry[] = [];
  const stats: Record<string, number> = {};
  for (const raw of materials) {
    if (typeof raw !== "object" || raw === null) {
      throw new InvalidDraftError("Invalid QR code data");
    }
    const m = raw as Record<string, unknown>;
    if (typeof m.type !== "string" || m.type === "") {
      throw new InvalidDraftError("Invalid QR code data");
    }
    const type = m.type;
    const weight = optionalNumber(m.weight) ?? 0;
    const pricePerKg = optionalNumber(m.pricePerKg) ?? 0;
    const isFree = typeof m.isFree === "boolean" ? m.isFree : true;
    const storedCo2 = optionalNumber(m.co2);
    const co2 = materialCo2(type, weight, storedCo2);

    pointsRaw += weight * BASE_MULTIPLIER * (isFree ? FREE_BONUS : 1) +
      co2 * CO2_POINTS_MULTIPLIER;
    co2Saved += co2;
    stats[type] = (stats[type] ?? 0) + weight;
    lines.push({
      type,
      weight,
      pricePerKg,
      isFree,
      ...(storedCo2 !== undefined ? {co2: storedCo2} : {}),
    });
  }

  return {
    materials: lines,
    totalWeight: total,
    pointsUser: Math.round(pointsRaw),
    co2Saved,
    stats,
  };
}
