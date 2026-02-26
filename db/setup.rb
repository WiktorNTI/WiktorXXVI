require_relative './database'

db = Database.connection

db.execute_batch <<~SQL
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT, 
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL, 
    created_at INT NOT NULL
  );

CREATE TABLE IF NOT EXISTS kingdoms (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER UNIQUE NOT NULL,
  name TEXT NOT NULL,
  population INTEGER NOT NULL DEFAULT 1,
  wood INTEGER NOT NULL DEFAULT 0,
  stone INTEGER NOT NULL DEFAULT 0,
  food INTEGER NOT NULL DEFAULT 0,
  gold INTEGER NOT NULL DEFAULT 0,
  tax_rate INTEGER NOT NULL DEFAULT 10,
  last_tick_at INTEGER NOT NULL,
  tutorial_mode TEXT NOT NULL DEFAULT 'pending',
  tutorial_step INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY(user_id) REFERENCES users(id)
);

  CREATE TABLE IF NOT EXISTS buildings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    kingdom_id INT NOT NULL,
    name TEXT NOT NULL,
    level INT NOT NULL DEFAULT 1,
    UNIQUE(kingdom_id, name),
    FOREIGN KEY(kingdom_id) REFERENCES kingdoms(id)
  );

  CREATE TABLE IF NOT EXISTS units (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    kingdom_id INT NOT NULL,
    unit_type TEXT NOT NULL,
    quantity INT NOT NULL DEFAULT 0,
    UNIQUE(kingdom_id, unit_type),
    FOREIGN KEY(kingdom_id) REFERENCES kingdoms(id)
  );
SQL

puts 'Database setup complete.'