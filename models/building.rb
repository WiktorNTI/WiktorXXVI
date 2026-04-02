module Building
  def self.all_for_kingdom(db, kingdom_id)
    db.execute(
      'SELECT name, level FROM buildings WHERE kingdom_id = ? ORDER BY name ASC',
      [kingdom_id]
    )
  end

  def self.find(db, kingdom_id, name)
    db.get_first_row(
      'SELECT id, level FROM buildings WHERE kingdom_id = ? AND name = ?',
      [kingdom_id, name]
    )
  end

  def self.upgrade!(db, building_id, new_level)
    db.execute('UPDATE buildings SET level = ? WHERE id = ?', [new_level, building_id])
  end

  # Creates default building rows for all buildings in the given list at a given level.
  def self.create_all!(db, kingdom_id, building_names, level = 1)
    building_names.each do |name|
      db.execute(
        'INSERT OR IGNORE INTO buildings (kingdom_id, name, level) VALUES (?, ?, ?)',
        [kingdom_id, name, level]
      )
    end
  end

  def self.set_all_level!(db, kingdom_id, level)
    db.execute('UPDATE buildings SET level = ? WHERE kingdom_id = ?', [level, kingdom_id])
  end

  # Creates starter buildings when a city is captured (Farm + Barracks at level 1).
  def self.create_captured!(db, kingdom_id)
    ['Farm', 'Barracks'].each do |name|
      db.execute(
        'INSERT OR IGNORE INTO buildings (kingdom_id, name, level) VALUES (?, ?, 1)',
        [kingdom_id, name]
      )
    end
  end
end
