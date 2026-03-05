module ResourceGeneration
  module_function

  def sync!(db, kingdom_id)
    kingdom = db.get_first_row('SELECT * FROM kingdoms WHERE id = ?', kingdom_id)
    return unless kingdom

    now = Time.now.to_i
    last_tick = kingdom['last_tick_at'].to_i
    elapsed_minutes = (now - last_tick) / 60
    return if elapsed_minutes < 1

    rates = production_rates(db, kingdom_id)

    wood_now = normalize_amount(kingdom['wood'])
    stone_now = normalize_amount(kingdom['stone'])
    food_now = normalize_amount(kingdom['food'])
    gold_now = normalize_amount(kingdom['gold'])

    new_wood = wood_now + rates['wood'] * elapsed_minutes
    new_stone = stone_now + rates['stone'] * elapsed_minutes
    new_food = food_now + rates['food'] * elapsed_minutes
    new_gold = gold_now + rates['gold'] * elapsed_minutes
    new_tick = last_tick + elapsed_minutes * 60

    db.execute(
      'UPDATE kingdoms SET wood = ?, stone = ?, food = ?, gold = ?, last_tick_at = ? WHERE id = ?',
      [new_wood, new_stone, new_food, new_gold, new_tick, kingdom_id]
    )
  end

  def production_rates(db, kingdom_id)
    kingdom = db.get_first_row(
      'SELECT population, tax_rate, capital_biome FROM kingdoms WHERE id = ?',
      [kingdom_id]
    )

    rows = db.execute('SELECT name, level FROM buildings WHERE kingdom_id = ?', [kingdom_id])
    levels = rows.each_with_object({}) { |row, memo| memo[row['name']] = row['level'] }

    lumberyard = levels.fetch('Lumberyard', 0)
    quarry = levels.fetch('Quarry', 0)
    farm = levels.fetch('Farm', 0)

    base = ECONOMY[:base_per_minute]

    wood_rate = base['wood'] + (lumberyard * ECONOMY[:lumberyard_wood_bonus])
    stone_rate = base['stone'] + (quarry * ECONOMY[:quarry_stone_bonus])
    food_rate = base['food'] + (farm * ECONOMY[:farm_food_bonus])

    population = kingdom ? kingdom['population'].to_i : 0
    tax_rate = kingdom ? kingdom['tax_rate'].to_i : 0
    tax_gold_rate = (population * tax_rate) / ECONOMY[:tax_divisor]
    gold_rate = base['gold'] + tax_gold_rate

    biome = kingdom ? kingdom['capital_biome'].to_s : ''
    biome_bonus = CAPITAL_BIOME_BONUSES.fetch(biome, {})

    wood_rate = apply_bonus(wood_rate, biome_bonus['wood'])
    stone_rate = apply_bonus(stone_rate, biome_bonus['stone'])
    food_rate = apply_bonus(food_rate, biome_bonus['food'])
    gold_rate = apply_bonus(gold_rate, biome_bonus['gold'])

    {
      'wood' => wood_rate,
      'stone' => stone_rate,
      'food' => food_rate,
      'gold' => gold_rate
    }
  end

  def apply_bonus(rate, percent_bonus)
    return rate unless percent_bonus
    ((rate * (100 + percent_bonus)) / 100.0).round
  end

  def normalize_amount(value)
    value.to_f.round
  end
end
