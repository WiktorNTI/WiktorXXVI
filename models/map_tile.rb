module MapTile
  def self.in_viewport(db, min_x, max_x, min_y, max_y)
    db.execute(
      'SELECT x, y, biome FROM map_tiles WHERE x BETWEEN ? AND ? AND y BETWEEN ? AND ?',
      [min_x, max_x, min_y, max_y]
    )
  end

  def self.random_of_biome(db, biome)
    db.get_first_row(
      'SELECT x, y FROM map_tiles WHERE biome = ? ORDER BY RANDOM() LIMIT 1',
      [biome]
    )
  end
end

module ExploredTile
  def self.add!(db, kingdom_id, x, y)
    db.execute(
      'INSERT OR IGNORE INTO explored_tiles (kingdom_id, x, y) VALUES (?, ?, ?)',
      [kingdom_id, x, y]
    )
  end

  def self.in_viewport(db, kingdom_id, min_x, max_x, min_y, max_y)
    db.execute(
      'SELECT x, y FROM explored_tiles WHERE kingdom_id = ? AND x BETWEEN ? AND ? AND y BETWEEN ? AND ?',
      [kingdom_id, min_x, max_x, min_y, max_y]
    )
  end

  # Many-to-many JOIN: returns explored tiles with biome info from map_tiles.
  # explored_tiles is the junction table between kingdoms (many) and map_tiles (many).
  def self.in_viewport_with_biome(db, kingdom_id, min_x, max_x, min_y, max_y)
    db.execute(
      'SELECT et.x, et.y, mt.biome
       FROM explored_tiles et
       JOIN map_tiles mt ON mt.x = et.x AND mt.y = et.y
       WHERE et.kingdom_id = ? AND et.x BETWEEN ? AND ? AND et.y BETWEEN ? AND ?',
      [kingdom_id, min_x, max_x, min_y, max_y]
    )
  end
end
