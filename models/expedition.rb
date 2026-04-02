module Expedition
  def self.all_for_kingdom(db, kingdom_id)
    db.execute('SELECT * FROM expeditions WHERE kingdom_id = ?', [kingdom_id])
  end

  def self.find_stationed(db, exp_id, kingdom_id)
    db.get_first_row(
      "SELECT * FROM expeditions WHERE id = ? AND kingdom_id = ? AND status = 'stationed'",
      [exp_id, kingdom_id]
    )
  end

  # Returns expeditions that have arrived but are not yet stationed.
  def self.arrived(db, kingdom_id, now)
    db.execute(
      "SELECT * FROM expeditions WHERE kingdom_id = ? AND arrives_at <= ? AND status != 'stationed'",
      [kingdom_id, now]
    )
  end

  # Returns stationed armies at a specific tile belonging to a kingdom.
  def self.stationed_at(db, kingdom_id, x, y)
    db.execute(
      "SELECT * FROM expeditions WHERE kingdom_id = ? AND dest_x = ? AND dest_y = ? AND status = 'stationed'",
      [kingdom_id, x, y]
    )
  end

  def self.create!(db, kingdom_id, home_city_id, from_x, from_y, dest_x, dest_y, spearman, archer, cavalry, departed_at, arrives_at)
    db.execute(
      'INSERT INTO expeditions (kingdom_id, home_city_id, from_x, from_y, dest_x, dest_y, spearman, archer, cavalry, departed_at, arrives_at, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [kingdom_id, home_city_id, from_x, from_y, dest_x, dest_y, spearman, archer, cavalry, departed_at, arrives_at, 'traveling']
    )
  end

  def self.set_stationed!(db, exp_id, spearman = nil, archer = nil, cavalry = nil)
    if spearman
      db.execute(
        "UPDATE expeditions SET spearman = ?, archer = ?, cavalry = ?, status = 'stationed' WHERE id = ?",
        [spearman, archer, cavalry, exp_id]
      )
    else
      db.execute("UPDATE expeditions SET status = 'stationed' WHERE id = ?", [exp_id])
    end
  end

  def self.update_casualties!(db, exp_id, spearman, archer, cavalry)
    db.execute(
      'UPDATE expeditions SET spearman = ?, archer = ?, cavalry = ? WHERE id = ?',
      [spearman, archer, cavalry, exp_id]
    )
  end

  def self.redeploy!(db, exp_id, from_x, from_y, dest_x, dest_y, departed_at, arrives_at)
    db.execute(
      "UPDATE expeditions SET from_x = ?, from_y = ?, dest_x = ?, dest_y = ?, departed_at = ?, arrives_at = ?, status = 'traveling' WHERE id = ?",
      [from_x, from_y, dest_x, dest_y, departed_at, arrives_at, exp_id]
    )
  end

  def self.recall!(db, exp_id, from_x, from_y, dest_x, dest_y, departed_at, arrives_at)
    db.execute(
      "UPDATE expeditions SET from_x = ?, from_y = ?, dest_x = ?, dest_y = ?, departed_at = ?, arrives_at = ?, status = 'recalling' WHERE id = ?",
      [from_x, from_y, dest_x, dest_y, departed_at, arrives_at, exp_id]
    )
  end

  def self.delete!(db, exp_id)
    db.execute('DELETE FROM expeditions WHERE id = ?', [exp_id])
  end
end
