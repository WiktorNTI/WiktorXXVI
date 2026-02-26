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

    new_wood = kingdom['wood'] + rates['wood'] * elapsed_minutes
    new_stone = kingdom['stone'] + rates['stone'] * elapsed_minutes
    new_food = kingdom['food'] + rates['food'] * elapsed_minutes
    new_gold = kingdom['gold'] + rates['gold'] * elapsed_minutes
    new_tick = last_tick + elapsed_minutes * 60

    db.execute(
      'UPDATE kingdoms SET wood = ?, stone = ?, food = ?, gold = ?, last_tick_at = ? WHERE id = ?',
      [new_wood, new_stone, new_food, new_gold, new_tick, kingdom_id]
    )
  end

  def production_rates(db, kingdom_id)
    kingdom = db.get_first_row(
      'SELECT population, tax_rate FROM kingdoms WHERE id = ?',
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

    {
      'wood' => wood_rate,
      'stone' => stone_rate,
      'food' => food_rate,
      'gold' => gold_rate
    }
  end
end
