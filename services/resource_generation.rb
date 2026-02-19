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
    rows = db.execute('SELECT name, level FROM buildings WHERE kingdom_id = ?', [kingdom_id])
    levels = rows.each_with_object({}) { |row, memo| memo[row['name']] = row['level'] }

    town_hall = levels.fetch('Town Hall', 0)
    farm = levels.fetch('Farm', 0)

    {
      'wood' => 1 + town_hall,
      'stone' => 1 + town_hall,
      'food' => 1 + (farm * 2),
      'gold' => 1 + (town_hall / 2)
    }
  end
end
