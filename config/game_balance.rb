BUILDING_ORDER = ['Town Hall', 'Farm', 'Barracks', 'Lumberyard', 'Quarry'].freeze


BUILDING_BASE_COSTS = {
  'Town Hall' => { 'wood' => 120, 'stone' => 120, 'food' => 60, 'gold' => 40 },
  'Farm' => { 'wood' => 80, 'stone' => 40, 'food' => 40, 'gold' => 25 },
  'Barracks' => { 'wood' => 100, 'stone' => 60, 'food' => 80, 'gold' => 45 },
  'Lumberyard' => { 'wood' => 90, 'stone' => 50, 'food' => 40, 'gold' => 30 },
  'Quarry' => { 'wood' => 90, 'stone' => 50, 'food' => 40, 'gold' => 30 }
}.freeze

UNIT_DATA = {
  'Spearman' => { 'food' => 25, 'gold' => 12, 'required_barracks' => 1 },
  'Archer' => { 'food' => 40, 'gold' => 20, 'required_barracks' => 2 },
  'Cavalry' => { 'food' => 70, 'gold' => 35, 'required_barracks' => 3 }
}.freeze

ECONOMY = {
  start_resources: { 'wood' => 180, 'stone' => 180, 'food' => 180, 'gold' => 120 },
  base_per_minute: { 'wood' => 1, 'stone' => 1, 'food' => 1, 'gold' => 1 },
  lumberyard_wood_bonus: 3,
  quarry_stone_bonus: 2,
  farm_food_bonus: 3,
  tax_divisor: 100
}.freeze
