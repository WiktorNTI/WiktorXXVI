module User
  def self.find(db, id)
    db.get_first_row('SELECT id, username, role FROM users WHERE id = ?', [id])
  end

  def self.find_by_username(db, username)
    db.get_first_row('SELECT * FROM users WHERE username = ?', [username])
  end

  def self.create!(db, username, password_hash)
    db.execute(
      'INSERT INTO users (username, password_hash, created_at, role) VALUES (?, ?, ?, ?)',
      [username, password_hash, Time.now.to_i, 'user']
    )
    db.last_insert_row_id
  end

  # Returns all users joined with their kingdom name (for admin view).
  def self.all_with_kingdoms(db)
    db.execute(
      'SELECT u.id, u.username, u.role, u.created_at, k.name AS kingdom_name
       FROM users u LEFT JOIN kingdoms k ON k.user_id = u.id
       ORDER BY u.created_at DESC'
    )
  end

  def self.set_role!(db, id, role)
    db.execute('UPDATE users SET role = ? WHERE id = ?', [role, id])
  end
end
