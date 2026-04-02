module WorldCity
  def self.find(db, id, kingdom_id)
    db.get_first_row(
      'SELECT * FROM world_cities WHERE id = ? AND kingdom_id = ?',
      [id, kingdom_id]
    )
  end

  def self.find_by_id(db, id)
    db.get_first_row('SELECT * FROM world_cities WHERE id = ?', [id])
  end

  # Returns the first (capital) city for a kingdom.
  def self.capital(db, kingdom_id)
    db.get_first_row(
      'SELECT * FROM world_cities WHERE kingdom_id = ? ORDER BY id LIMIT 1',
      [kingdom_id]
    )
  end

  def self.all_for_kingdom(db, kingdom_id)
    db.execute(
      'SELECT id, name, tile_x, tile_y, vision_radius FROM world_cities WHERE kingdom_id = ?',
      [kingdom_id]
    )
  end

  def self.neutral_in_viewport(db, min_x, max_x, min_y, max_y)
    db.execute(
      'SELECT id, name, tile_x, tile_y, garrison FROM world_cities WHERE kingdom_id = 0 AND tile_x BETWEEN ? AND ? AND tile_y BETWEEN ? AND ?',
      [min_x, max_x, min_y, max_y]
    )
  end

  # Returns enemy player cities in viewport. Uses JOIN to include owner name.
  def self.enemy_in_viewport(db, kingdom_id, min_x, max_x, min_y, max_y)
    db.execute(
      'SELECT wc.id, wc.name, wc.tile_x, wc.tile_y, k.name AS owner_name
       FROM world_cities wc JOIN kingdoms k ON k.id = wc.kingdom_id
       WHERE wc.kingdom_id != 0 AND wc.kingdom_id != ?
         AND wc.tile_x BETWEEN ? AND ? AND wc.tile_y BETWEEN ? AND ?',
      [kingdom_id, min_x, max_x, min_y, max_y]
    )
  end

  def self.neutral_at(db, x, y)
    db.get_first_row(
      'SELECT * FROM world_cities WHERE tile_x = ? AND tile_y = ? AND kingdom_id = 0',
      [x, y]
    )
  end

  def self.enemy_at(db, x, y, kingdom_id)
    db.get_first_row(
      'SELECT * FROM world_cities WHERE tile_x = ? AND tile_y = ? AND kingdom_id != 0 AND kingdom_id != ?',
      [x, y, kingdom_id]
    )
  end

  def self.create!(db, kingdom_id, name, tile_x, tile_y, vision_radius = 3)
    db.execute(
      'INSERT INTO world_cities (kingdom_id, name, tile_x, tile_y, vision_radius) VALUES (?, ?, ?, ?, ?)',
      [kingdom_id, name, tile_x, tile_y, vision_radius]
    )
    db.get_first_row(
      'SELECT * FROM world_cities WHERE kingdom_id = ? ORDER BY id DESC LIMIT 1',
      [kingdom_id]
    )
  end

  def self.capture!(db, city_id, kingdom_id)
    db.execute('UPDATE world_cities SET kingdom_id = ? WHERE id = ?', [kingdom_id, city_id])
  end

  def self.update_garrison!(db, city_id, garrison)
    db.execute('UPDATE world_cities SET garrison = ? WHERE id = ?', [garrison, city_id])
  end
end
