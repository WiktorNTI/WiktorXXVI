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

db.execute_batch <<~SQL
  CREATE TABLE IF NOT EXISTS map_tiles (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    x INTEGER NOT NULL,
    y INTEGER NOT NULL,
    biome TEXT NOT NULL,
    UNIQUE(x, y)
  );

  CREATE TABLE IF NOT EXISTS world_cities (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    kingdom_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    tile_x INTEGER NOT NULL,
    tile_y INTEGER NOT NULL,
    vision_radius INTEGER NOT NULL DEFAULT 3,
    FOREIGN KEY(kingdom_id) REFERENCES kingdoms(id)
  );

  CREATE TABLE IF NOT EXISTS explored_tiles (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    kingdom_id INTEGER NOT NULL,
    x INTEGER NOT NULL,
    y INTEGER NOT NULL,
    UNIQUE(kingdom_id, x, y),
    FOREIGN KEY(kingdom_id) REFERENCES kingdoms(id)
  );
SQL

count = db.get_first_value('SELECT COUNT(*) FROM map_tiles').to_i
if count == 0
  biomes = %w[grassland forest mountain desert]
  80.times do |y|
    80.times do |x|
      biome = biomes.sample
      db.execute('INSERT INTO map_tiles (x, y, biome) VALUES (?, ?, ?)', [x, y, biome])
    end
  end
end


puts 'Database setup complete.'