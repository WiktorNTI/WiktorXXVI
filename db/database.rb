require 'sqlite3'

module Database
  DB_PATH = File.join(__dir__, 'game.db')

  def self.connection
    @connection ||=SQLite3::Database.new(DB_PATH).tap do |db|
      db.results_as_hash = true
    end
  end
end
