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
end
