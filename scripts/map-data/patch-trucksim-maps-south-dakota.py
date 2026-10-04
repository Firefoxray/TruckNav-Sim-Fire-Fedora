#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-trucksim-maps-south-dakota.py <trucksim-maps-dir>")

root = Path(sys.argv[1]).resolve()
constants = root / "packages" / "libs" / "map" / "constants.ts"
if not constants.is_file():
    raise SystemExit(f"missing expected file: {constants}")

text = constants.read_text(encoding="utf-8")

replacements = [
    (
        "export type AtsSelectableDlc = Exclude<AtsDlc, AtsDlc.SouthDakota>;",
        "export type AtsSelectableDlc = AtsDlc;",
    ),
    (
        "  AtsDlc.Illinois,\n]);",
        "  AtsDlc.Illinois,\n  AtsDlc.SouthDakota,\n]);",
    ),
    (
        "  [AtsDlc.Illinois]: 'Illinois',\n};",
        "  [AtsDlc.Illinois]: 'Illinois',\n  [AtsDlc.SouthDakota]: 'South Dakota',\n};",
    ),
    (
        "  'dlc_il.scs': 50,\n};",
        "  'dlc_il.scs': 50,\n  'dlc_sd.scs': 53,\n};",
    ),
    (
        "  Illinois = 14,\n}",
        "  Illinois = 14,\n  SouthDakota = 41,\n}",
    ),
    (
        "  [AtsCountryId.Illinois]: 50,\n};",
        "  [AtsCountryId.Illinois]: 50,\n  [AtsCountryId.SouthDakota]: 53,\n};",
    ),
]

changed = False
for old, new in replacements:
    if new in text:
        continue
    if old not in text:
        raise SystemExit(
            "truckermudgeon/maps changed unexpectedly; could not find:\n" + old
        )
    text = text.replace(old, new, 1)
    changed = True

constants.write_text(text, encoding="utf-8")

if changed:
    print("Patched truckermudgeon/maps for South Dakota.")
else:
    print("South Dakota patch already applied.")


# ATS 1.61 can contain speed-limit parallel arrays whose max/urban arrays
# are shorter than laneSpeedClass. TruckNav's routing currently uses only
# the normal "limit" value, so preserve that exactly and safely fall back
# for the unused max/urban values instead of aborting the entire parse.
def_parser = root / "packages" / "clis" / "parser" / "game-files" / "def-parser.ts"
if not def_parser.is_file():
    raise SystemExit(f"missing expected file: {def_parser}")

def_text = def_parser.read_text(encoding="utf-8")
old_speed_limit = """function processSpeedLimitJson(obj: SpeedLimitsSii) {
  const { laneSpeedClass, limit, maxLimit, urbanLimit } =
    obj.countrySpeedLimit['.speed_limit.truck'];

  // HACK: extra validation that isn't expressed in schema
  assert(
    [limit, maxLimit, urbanLimit].every(
      array => array.length === laneSpeedClass.length,
    ),
  );

  return laneSpeedClass.reduce((obj, className, index) => {
    obj[toLaneSpeedClass(className)] = {
      limit: limit[index],
      maxLimit: maxLimit[index],
      urbanLimit: urbanLimit[index],
    };
    return obj;
  }, {} as SpeedLimits);
}
"""
new_speed_limit = """function processSpeedLimitJson(obj: SpeedLimitsSii) {
  const { laneSpeedClass, limit, maxLimit, urbanLimit } =
    obj.countrySpeedLimit['.speed_limit.truck'];

  if (
    limit.length !== laneSpeedClass.length ||
    maxLimit.length !== laneSpeedClass.length ||
    urbanLimit.length !== laneSpeedClass.length
  ) {
    console.warn(
      '[TruckNav map build] ATS speed-limit arrays have different lengths; ' +
        `classes=${laneSpeedClass.length} limit=${limit.length} ` +
        `max=${maxLimit.length} urban=${urbanLimit.length}. ` +
        'Using normal limits as fallback for missing max/urban values.',
    );
  }

  return laneSpeedClass.reduce((obj, className, index) => {
    const normalLimit = limit[index];
    if (normalLimit === undefined) {
      return obj;
    }

    obj[toLaneSpeedClass(className)] = {
      limit: normalLimit,
      maxLimit: maxLimit[index] ?? normalLimit,
      urbanLimit: urbanLimit[index] ?? normalLimit,
    };
    return obj;
  }, {} as SpeedLimits);
}
"""

if new_speed_limit not in def_text:
    if old_speed_limit not in def_text:
        raise SystemExit(
            "truckermudgeon/maps changed unexpectedly; could not patch "
            "ATS 1.61 speed-limit parsing"
        )
    def_text = def_text.replace(old_speed_limit, new_speed_limit, 1)
    def_parser.write_text(def_text, encoding="utf-8")
    print("Patched ATS 1.61 speed-limit array compatibility.")
else:
    print("ATS 1.61 speed-limit compatibility patch already applied.")


# ATS 1.61 contains at least one composite roundabout candidate whose graph
# topology does not provide the entrance/exit neighbor assumptions expected by
# the pinned upstream roundabout detector. Roundabout metadata is supplemental;
# preserve all valid descriptions and skip/log only malformed candidates rather
# than aborting the full map build.
roundabouts = (
    root
    / "packages"
    / "clis"
    / "generator"
    / "roundabouts"
    / "composite-roundabouts.ts"
)
if not roundabouts.is_file():
    raise SystemExit(f"missing expected file: {roundabouts}")

round_text = roundabouts.read_text(encoding="utf-8")
old_roundabout_block = """  const res = roundaboutCycles.map(cycle => {
    bar.increment();
    return calculateRoundaboutLaneInfo(cycle, context);
  });
  logger.success(
    roundaboutCycles.length,
    'descriptions calculated in',
    Number(((Date.now() - startTime) / 1000).toFixed(1)),
    'seconds',
  );
"""
new_roundabout_block = """  const res: RoundaboutDesc[] = [];
  let skippedRoundabouts = 0;
  for (const cycle of roundaboutCycles) {
    bar.increment();
    try {
      res.push(calculateRoundaboutLaneInfo(cycle, context));
    } catch (error) {
      skippedRoundabouts++;
      logger.warn(
        'skipping an invalid composite roundabout cycle',
        cycle.map(key => keyToNodeUid(key).toString(16)),
        error instanceof Error ? error.message : error,
      );
    }
  }
  logger.success(
    res.length,
    'descriptions calculated in',
    Number(((Date.now() - startTime) / 1000).toFixed(1)),
    'seconds',
    skippedRoundabouts ? `(${skippedRoundabouts} skipped)` : '',
  );
"""

if new_roundabout_block not in round_text:
    if old_roundabout_block not in round_text:
        raise SystemExit(
            "truckermudgeon/maps changed unexpectedly; could not patch "
            "ATS 1.61 composite roundabout handling"
        )
    round_text = round_text.replace(
        old_roundabout_block, new_roundabout_block, 1
    )
    roundabouts.write_text(round_text, encoding="utf-8")
    print("Patched ATS 1.61 composite roundabout compatibility.")
else:
    print("ATS 1.61 composite roundabout compatibility patch already applied.")
