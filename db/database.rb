require 'sqlite3'

module Database
  DB_PATH = File.join(__dir__, 'game.db')

  def self.connection
    Thread.current[:sqlite_connection] ||= SQLite3::Database.new(DB_PATH).tap do |db|
      db.results_as_hash = true
      db.busy_timeout = 5000
      db.execute('PRAGMA journal_mode = WAL;')
      db.execute('PRAGMA synchronous = NORMAL;')
    end
  end

  def self.close_connection
    conn = Thread.current[:sqlite_connection]
    return unless conn

    conn.close
    Thread.current[:sqlite_connection] = nil
  end

  def self.ensure_schema!
    db = connection
    columns = db.execute("PRAGMA table_info('kingdoms')")
    has_capital_biome = columns.any? { |row| row['name'] == 'capital_biome' }
    return if has_capital_biome

    db.execute('ALTER TABLE kingdoms ADD COLUMN capital_biome TEXT')
  end
end
