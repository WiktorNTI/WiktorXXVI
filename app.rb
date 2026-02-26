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
require_relative './services/resource_generation'

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

before do
  next unless current_user

  kingdom = db.get_first_row('SELECT id FROM kingdoms WHERE user_id = ?', current_user['id'])
  next unless kingdom

  ResourceGeneration.sync!(db, kingdom['id'])
end

after do
  Database.close_connection
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

  rates = ResourceGeneration.production_rates(db, kingdom['id'])

  rates_per_hour = rates.transform_values { |v| v * 60 }

  rate_tooltips = {
    'wood' => "This city: Base 1 + Town Hall bonus",
    'stone' => "This city: Base 1 + Town Hall bonus",
    'food' => "This city: Base 1 + Farm bonus",
    'gold' => "This city: Base 1 + Town Hall bonus"
  }




  slim :kingdom, locals: { 
   kingdom: kingdom, 
   user: current_user,
   buildings: buildings,
   units: units,
   notice: consume_notice,
   unit_data_map: UNIT_DATA,
   rates_per_hour: rates_per_hour,
   rate_tooltips: rate_tooltips
  }
end

get '/map' do
  require_login!
  kingdom = require_kingdom!

  city = db.get_first_row('SELECT * FROM world_cities WHERE kingdom_id = ? ORDER BY id LIMIT 1', [kingdom['id']])
  unless city
    db.execute(
      'INSERT INTO world_cities (kingdom_id, name, tile_x, tile_y, vision_radius) VALUES (?, ?, ?, ?, ?)',
      [kingdom['id'], "#{kingdom['name']} Capital", 40, 40, 3]
    )
    city = db.get_first_row('SELECT * FROM world_cities WHERE kingdom_id = ? ORDER BY id LIMIT 1', [kingdom['id']])
  end

  cx = (params[:cx] || city['tile_x']).to_i
  cy = (params[:cy] || city['tile_y']).to_i
  half = 10
  min_x, max_x = cx - half, cx + half
  min_y, max_y = cy - half, cy + half

  tiles = db.execute(
    'SELECT x, y, biome FROM map_tiles WHERE x BETWEEN ? AND ? AND y BETWEEN ? AND ?',
    [min_x, max_x, min_y, max_y]
  )
  tile_map = {}
  tiles.each { |t| tile_map[[t['x'], t['y']]] = t }

  cities = db.execute(
    'SELECT id, name, tile_x, tile_y, vision_radius FROM world_cities WHERE kingdom_id = ?',
    [kingdom['id']]
  )

  visible = {}
  (min_y..max_y).each do |y|
    (min_x..max_x).each do |x|
      visible[[x, y]] = cities.any? do |c|
        (x - c['tile_x']).abs <= c['vision_radius'] && (y - c['tile_y']).abs <= c['vision_radius']
      end
    end
  end

  visible.keys.each do |pos|
    x, y = pos
    next unless visible[[x, y]]

    db.execute(
      'INSERT OR IGNORE INTO explored_tiles (kingdom_id, x, y) VALUES (?, ?, ?)',
      [kingdom['id'], x, y]
    )
  end

  explored_rows = db.execute(
    'SELECT x, y FROM explored_tiles WHERE kingdom_id = ? AND x BETWEEN ? AND ? AND y BETWEEN ? AND ?',
    [kingdom['id'], min_x, max_x, min_y, max_y]
  )
  explored = {}
  explored_rows.each { |r| explored[[r['x'], r['y']]] = true }


  slim :map, locals: {
    kingdom: kingdom, cx: cx, cy: cy,
    min_x: min_x, max_x: max_x, min_y: min_y, max_y: max_y,
    tile_map: tile_map, visible: visible, explored: explored, cities: cities
  }
end

post '/map/center' do
  require_login!
  x = params[:x].to_i
  y = params[:y].to_i
  redirect "/map?cx=#{x}&cy=#{y}"
end

