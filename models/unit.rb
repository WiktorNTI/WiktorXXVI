module Unit
  def self.all_for_kingdom(db, kingdom_id)
    db.execute(
      'SELECT unit_type, quantity FROM units WHERE kingdom_id = ? ORDER BY unit_type ASC',
      [kingdom_id]
    )
  end

  def self.find(db, kingdom_id, unit_type)
    db.get_first_row(
      'SELECT id, quantity FROM units WHERE kingdom_id = ? AND unit_type = ?',
      [kingdom_id, unit_type]
    )
  end

  def self.add!(db, kingdom_id, unit_type, qty)
    db.execute(
      'UPDATE units SET quantity = quantity + ? WHERE kingdom_id = ? AND unit_type = ?',
      [qty, kingdom_id, unit_type]
    )
  end

  def self.remove!(db, kingdom_id, unit_type, qty)
    db.execute(
      'UPDATE units SET quantity = quantity - ? WHERE kingdom_id = ? AND unit_type = ?',
      [qty, kingdom_id, unit_type]
    )
  end

  def self.set_quantity!(db, unit_id, qty)
    db.execute('UPDATE units SET quantity = ? WHERE id = ?', [qty, unit_id])
  end

  # Creates default unit rows for the given unit types.
  def self.create_all!(db, kingdom_id, unit_types)
    unit_types.each do |unit_type|
      db.execute(
        'INSERT OR IGNORE INTO units (kingdom_id, unit_type, quantity) VALUES (?, ?, 0)',
        [kingdom_id, unit_type]
      )
    end
  end

  def self.reset_all!(db, kingdom_id)
    db.execute('UPDATE units SET quantity = 0 WHERE kingdom_id = ?', [kingdom_id])
  end
end
