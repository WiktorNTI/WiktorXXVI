BUILDING_ORDER = ['Town Hall', 'Farm', 'Barracks', 'Lumberyard', 'Quarry']

BUILDING_BASE_COSTS = {
  'Town Hall'  => { 'wood' => 70,  'stone' => 70,  'food' => 30, 'gold' => 20 },
  'Farm'       => { 'wood' => 45,  'stone' => 22,  'food' => 20, 'gold' => 12 },
  'Barracks'   => { 'wood' => 55,  'stone' => 32,  'food' => 40, 'gold' => 22 },
  'Lumberyard' => { 'wood' => 50,  'stone' => 28,  'food' => 18, 'gold' => 14 },
  'Quarry'     => { 'wood' => 50,  'stone' => 28,  'food' => 18, 'gold' => 14 }
}

UNIT_DATA = {
  'Spearman' => { 'food' => 14, 'gold' => 7,  'required_barracks' => 1 },
  'Archer'   => { 'food' => 22, 'gold' => 11, 'required_barracks' => 2 },
  'Cavalry'  => { 'food' => 38, 'gold' => 19, 'required_barracks' => 3 }
}

UNIT_ORDER = ['Spearman', 'Archer', 'Cavalry']

CAPITAL_BIOME_ORDER = ['grassland', 'forest', 'mountain', 'desert']

CAPITAL_BIOME_BONUSES = {
  'grassland' => { 'food' => 5 },
  'forest' => { 'wood' => 5 },
  'mountain' => { 'stone' => 5 },
  'desert' => { 'gold' => 5 }
}

UNIT_STRENGTH = { 'Spearman' => 1, 'Archer' => 2, 'Cavalry' => 4 }

TRAVEL_MINUTES_PER_TILE = 1

ECONOMY = {
  start_resources: { 'wood' => 250, 'stone' => 250, 'food' => 250, 'gold' => 160 },
  base_per_minute: { 'wood' => 2, 'stone' => 2, 'food' => 2, 'gold' => 1 },
  lumberyard_wood_bonus: 5,
  quarry_stone_bonus: 4,
  farm_food_bonus: 5,
  tax_divisor: 80
}
