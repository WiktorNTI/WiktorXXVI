BUILDING_ORDER = ['Town Hall', 'Farm', 'Barracks', 'Lumberyard', 'Quarry'].freeze


BUILDING_BASE_COSTS = {
  'Town Hall' => { 'wood' => 60, 'stone' => 60, 'food' => 30, 'gold' => 20 },
  'Farm' => { 'wood' => 40, 'stone' => 20, 'food' => 20, 'gold' => 10 },
  'Barracks' => { 'wood' => 50, 'stone' => 30, 'food' => 40, 'gold' => 20 },
  'Lumberyard' = { 'wood' => 45, 'stone' => 25, 'food' => 20, 'gold' => 15 },
  'Quarry' = { 'wood' => 45, 'stone' => 25, 'food' => 20, 'gold' => 15 }
}.freeze

UNIT_ORDER = ['Spearman', 'Archer', 'Cavalry'].freeze

UNIT_DATA = {
  'Spearman' => { 'food' => 20, 'gold' => 10, 'required_barracks' => 1 },
  'Archer' => { 'food' => 30, 'gold' => 15, 'required_barracks' => 2 },
  'Cavalry' => { 'food' => 50, 'gold' => 30, 'required_barracks' => 3 }
}.freeze

ECONOMY = {
  start_resources: { 'wood' => 120, 'stone' => 120, 'food' => 120, 'gold' => 120 },
  base_per_minute: { 'wood' => 1, 'stone' => 1, 'food' => 1, 'gold' => 1 },
  town_hall_bonus: { 'wood' => 1, 'stone' => 1, 'gold' => 1 },
  farm_food_bonus: 2
}.freeze
