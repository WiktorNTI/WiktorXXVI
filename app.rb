require 'sinatra'
require 'slim'
require 'sqlite3'
require 'sinatra/reloader'
require 'bcrypt'
require_relative './db/database'
require_relative './routes/tutorial_routes'

configure do
    enable :sessions
    set :session_secret, ENV.fetch('SESSION_SECRET', 'Temporary')
end

helpers do
  def db
      Database.connection
  end

  def current_user
    return nil unless session[:user_id]
    @current_user ||= db.get_first_row('SELECT id, username FROM users WHERE id = ?', session[:user_id])
  end

  def create_default_kingdom_for(user_id, username)
    db.execute(
      'INSERT INTO kingdoms (user_id, name, wood, stone, food, gold, last_tick_at) VALUES(?, ?, 120, 120, 120, 120, ?)',
      user_id,
      "#{username}'s Kingdom",
      Time.now.to_i
    )

    kingdom_id = db.last_insert_row_id
  end

  def grant_starter_pack!(kingdom_id)
    db.execute(
      'UPDATE kingdoms SET wood = 120, stone = 120, food = 120, gold = 120 WHERE id = ?',
      kingdom_id
    )

    ['Town Hall', 'Farm', 'Barracks'].each do |name|
      db.execute(
        'INSERT OR IGNORE INTO buildings (kingdom_id, name, level) VALUES (?, ?, 1)',
        kingdom_id, name
      )
    end

     ['Spearman', 'Archer', 'Cavalry'].each do |unit|
    db.execute(
      'INSERT OR IGNORE INTO units (kingdom_id, unit_type, quantity) VALUES (?, ?, 0)',
      kingdom_id, unit
    )
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
    @error = 'Username must be at least 3 Characters.'
    return slim :register
  elsif kingdom_name.length < 3
    @error = 'Kingdom name must be at least 3 characters.'
    return slim :register
  elsif password.length < 5 || password !~ /\A(?=.*[A-Za-z])(?=.*\d).+\z/
    @error = 'Password must be atleast 5 Characters and must include at least one number and one letter'
    return slim :register
  end


  password_hash = BCrypt::Password.create(password).to_s
  db.execute(
    'INSERT INTO users (username, password_hash, created_at) VALUES (?, ?, ?)',
    username, password_hash, Time.now.to_i
  )

  user_id = db.last_insert_row_id

  db.execute(
    'INSERT INTO kingdoms (user_id, name, wood, stone, food, gold, last_tick_at, tutorial_mode, tutorial_step) VALUES (?, ?, 0, 0, 0, 0, ?, ?, ?)',
    user_id, kingdom_name, Time.now.to_i, 'pending', 0
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
    @error = '🥀?'
    slim :login
  end
end



post '/logout' do
  session.clear
  redirect '/'
end

get '/kingdom' do
  redirect '/login' unless current_user
  "Welcome back!, #{current_user['username']}! Kingdom page next."
end