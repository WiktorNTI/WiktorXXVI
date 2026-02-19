require 'sinatra'
require 'slim'
require 'sqlite3'
require 'sinatra/reloader'
require 'bcrypt'
require_relative './db/database'
require_relative './config/game_balance'
require_relative './routes/tutorial_routes'
require_relative './routes/building_routes'
require_relative './routes/unit_routes'

configure do
  enable :sessions
  set :session_secret, ENV.fetch('SESSION_SECRET', '68764546578877666777766677656787654567654567654323456789876543456789876543345676787654345678765434567876543456')
end

helpers do
  def db
    Database.connection
  end

  def current_user
    return nil unless session[:user_id]

    @current_user ||= db.get_first_row('SELECT id, username FROM users WHERE id = ?', session[:user_id])
  end

  def require_login!
    redirect '/login' unless current_user
  end

  def require_kingdom!
    kingdom = db.get_first_row('SELECT * FROM kingdoms WHERE user_id = ?', current_user['id'])
    redirect '/login' unless kingdom
    kingdom
  end 

  def set_notice(message)
    session[:notice] = message
  end

  def consume_notice
    notice = session[:notice]
    session[:notice] = nil
    notice
  end
end

get '/' do
  slim :home
end

get '/register' do
  slim :register
end

post '/register' do
  username = params[:username].to_s.strip
  kingdom_name = params[:kingdom_name].to_s.strip
  password = params[:password].to_s

  if username.length < 3
    @error = 'Username must be at least 3 characters.'
    return slim :register
  elsif kingdom_name.length < 3
    @error = 'Kingdom name must be at least 3 characters.'
    return slim :register
  elsif password.length < 5 || password !~ /\A(?=.*[A-Za-z])(?=.*\d).+\z/
    @error = 'Password must be at least 5 characters and include at least one number and one letter.'
    return slim :register
  end

  password_hash = BCrypt::Password.create(password).to_s
  db.execute(
    'INSERT INTO users (username, password_hash, created_at) VALUES (?, ?, ?)',
    [username, password_hash, Time.now.to_i]
  )

  user_id = db.last_insert_row_id

  db.execute(
    'INSERT INTO kingdoms (user_id, name, wood, stone, food, gold, last_tick_at, tutorial_mode, tutorial_step) VALUES (?, ?, 0, 0, 0, 0, ?, ?, ?)',
    [user_id, kingdom_name, Time.now.to_i, 'pending', 0]
  )

  redirect '/login'
rescue SQLite3::ConstraintException
  @error = 'Username already exists.'
  slim :register
end

get '/login' do
  slim :login
end

post '/login' do
  username = params[:username].to_s.strip
  password = params[:password].to_s
  user = db.get_first_row('SELECT * FROM users WHERE username = ?', username)

  if user && BCrypt::Password.new(user['password_hash']) == password
    session[:user_id] = user['id']

    kingdom = db.get_first_row('SELECT tutorial_mode FROM kingdoms WHERE user_id = ?', user['id'])
    if kingdom && kingdom['tutorial_mode'] == 'pending'
      redirect '/tutorial/start'
    else
      redirect '/kingdom'
    end
  else
    @error = 'Invalid username or password.'
    slim :login
  end
end

post '/logout' do
  session.clear
  redirect '/'
end

get '/kingdom' do
  require_login!
  kingdom = require_kingdom!

  buildings = db.execute(
    'SELECT name, level FROM buildings WHERE kingdom_id = ? ORDER BY name ASC',
    [kingdom['id']]
  )

  units = db.execute(
    'SELECT unit_type, quantity FROM units WHERE kingdom_id = ? ORDER BY unit_type ASC', 
    [kingdom['id']]
  )


  slim :kingdom, locals: { 
   kingdom: kingdom, 
   user: current_user,
   buildings: buildings,
   units: units,
   notice: consume_notice
  }
end
