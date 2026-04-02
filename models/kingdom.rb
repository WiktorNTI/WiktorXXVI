module Kingdom
  def self.find(db, id)
    db.get_first_row('SELECT * FROM kingdoms WHERE id = ?', [id])
  end

  def self.find_by_user(db, user_id)
    db.get_first_row('SELECT * FROM kingdoms WHERE user_id = ?', [user_id])
  end

  def self.create!(db, user_id, name)
    db.execute(
      'INSERT INTO kingdoms (user_id, name, wood, stone, food, gold, last_tick_at, tutorial_mode, tutorial_step) VALUES (?, ?, 0, 0, 0, 0, ?, ?, ?)',
      [user_id, name, Time.now.to_i, 'pending', 0]
    )
  end

  def self.normalize_resources!(db, id)
    db.execute(
      'UPDATE kingdoms SET wood = CAST(ROUND(wood) AS INTEGER), stone = CAST(ROUND(stone) AS INTEGER), food = CAST(ROUND(food) AS INTEGER), gold = CAST(ROUND(gold) AS INTEGER) WHERE id = ?',
      [id]
    )
  end

  def self.spend_resources!(db, id, kingdom, cost)
    db.execute(
      'UPDATE kingdoms SET wood = ?, stone = ?, food = ?, gold = ? WHERE id = ?',
      [
        kingdom['wood']  - cost.fetch('wood',  0),
        kingdom['stone'] - cost.fetch('stone', 0),
        kingdom['food']  - cost.fetch('food',  0),
        kingdom['gold']  - cost.fetch('gold',  0),
        id
      ]
    )
  end

  def self.spend_food_gold!(db, id, kingdom, food_cost, gold_cost)
    db.execute(
      'UPDATE kingdoms SET food = ?, gold = ? WHERE id = ?',
      [kingdom['food'] - food_cost, kingdom['gold'] - gold_cost, id]
    )
  end

  def self.set_resources!(db, id, wood, stone, food, gold)
    db.execute(
      'UPDATE kingdoms SET wood = ?, stone = ?, food = ?, gold = ? WHERE id = ?',
      [wood, stone, food, gold, id]
    )
  end

  def self.set_tutorial!(db, id, mode, step)
    db.execute(
      'UPDATE kingdoms SET tutorial_mode = ?, tutorial_step = ? WHERE id = ?',
      [mode, step, id]
    )
  end

  def self.set_tutorial_with_biome!(db, id, mode, step, biome)
    db.execute(
      'UPDATE kingdoms SET tutorial_mode = ?, tutorial_step = ?, capital_biome = ? WHERE id = ?',
      [mode, step, biome, id]
    )
  end

  def self.set_tutorial_step!(db, id, step)
    db.execute('UPDATE kingdoms SET tutorial_step = ? WHERE id = ?', [step, id])
  end
end
