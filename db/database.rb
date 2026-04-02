require 'sqlite3'

module Database
  DB_PATH = File.join(File.dirname(__FILE__), 'game.db')

  def self.connection
    if @db.nil?
      @db = SQLite3::Database.new(DB_PATH)
      @db.results_as_hash = true
      @db.execute('PRAGMA foreign_keys = ON')
    end
    @db
  end

  def self.close_connection
    return if @db.nil?
    @db.close
    @db = nil
  end

  def self.ensure_schema!
    db = connection

    # --- Column migrations (idempotent) ---
    [
      'ALTER TABLE kingdoms    ADD COLUMN capital_biome TEXT',
      'ALTER TABLE world_cities ADD COLUMN garrison INTEGER NOT NULL DEFAULT 0',
      "ALTER TABLE users        ADD COLUMN role TEXT NOT NULL DEFAULT 'user'"
    ].each do |sql|
      begin
        db.execute(sql)
      rescue SQLite3::Exception
        # Column already exists — safe to ignore.
      end
    end

    # --- Table migrations ---

    # Recreate expeditions if it is missing required columns from an older schema.
    begin
      db.execute('SELECT home_city_id, from_x, from_y, status FROM expeditions LIMIT 0')
    rescue SQLite3::Exception
      db.execute('DROP TABLE IF EXISTS expeditions')
    end

    db.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS expeditions (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        kingdom_id   INTEGER NOT NULL,
        home_city_id INTEGER NOT NULL,
        from_x       INTEGER NOT NULL DEFAULT 0,
        from_y       INTEGER NOT NULL DEFAULT 0,
        dest_x       INTEGER NOT NULL,
        dest_y       INTEGER NOT NULL,
        spearman     INTEGER NOT NULL DEFAULT 0,
        archer       INTEGER NOT NULL DEFAULT 0,
        cavalry      INTEGER NOT NULL DEFAULT 0,
        departed_at  INTEGER NOT NULL,
        arrives_at   INTEGER NOT NULL,
        status       TEXT    NOT NULL DEFAULT 'traveling'
      )
    SQL

    # Tracks login attempts for rate limiting and security auditing.
    db.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS login_attempts (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        username     TEXT    NOT NULL,
        attempted_at INTEGER NOT NULL,
        success      INTEGER NOT NULL DEFAULT 0
      )
    SQL
  end

  def self.ensure_neutral_cities!
    db = connection

    tile_count = db.get_first_value('SELECT COUNT(*) FROM map_tiles').to_i
    return if tile_count == 0

    neutral_count = db.get_first_value('SELECT COUNT(*) FROM world_cities WHERE kingdom_id = 0').to_i
    return if neutral_count > 0

    # Neutral cities use kingdom_id = 0 (no real kingdom owner).
    # Disable FK enforcement temporarily so the sentinel value is accepted
    # regardless of whether the existing schema has a FK on this column.
    db.execute('PRAGMA foreign_keys = OFF')

    names = [
      'Abandoned Fort', 'Ruined Village', 'Forgotten Keep', 'Old Watchtower',
      'Crumbled Outpost', 'Ancient Ruins', 'Deserted Settlement', 'Fallen Stronghold',
      'Overgrown Hamlet', 'Lost Colony', 'Derelict Camp', 'Ghost Town',
      'Forsaken Post', 'Weathered Citadel', 'Cracked Bastion', 'Wrecked Harbor',
      'Ravaged Town', 'Silent Monastery', 'Broken Ramparts', 'Mossy Keep'
    ]

    20.times do |i|
      tile = db.get_first_row(
        'SELECT m.x, m.y FROM map_tiles m LEFT JOIN world_cities wc ON m.x = wc.tile_x AND m.y = wc.tile_y WHERE wc.id IS NULL ORDER BY RANDOM() LIMIT 1'
      )
      next unless tile

      garrison  = 5 + rand(16)
      city_name = names[i] || "Neutral Settlement #{i + 1}"
      db.execute(
        'INSERT INTO world_cities (kingdom_id, name, tile_x, tile_y, vision_radius, garrison) VALUES (0, ?, ?, ?, 3, ?)',
        [city_name, tile['x'], tile['y'], garrison]
      )
    end
  ensure
    db.execute('PRAGMA foreign_keys = ON')
  end
end
