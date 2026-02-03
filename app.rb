require 'sinatra'
require 'slim'
require 'sqlite3'
require 'sinatra/reloader'
require 'bcrypt'

DB_PATH = Filr.join(_dir_, "db", "game.db")

def db
  @db ||=SQLite3::Database.new(DB_PATH)
  @db.results_as_hash = true
  @db
end

configure do
  database = SQLite3::Database.new(DB_PATH)
  database.execure <<~SQL

get "/" do
  slim :home
end