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
require_relative './routes/expedition_routes'
require_relative './services/resource_generation'

configure do
  enable :sessions
  set :session_secret, '67864546578877666777766677656787654567654567654323456789876543456789876543345676787654345678765434567876543456'
  Database.ensure_schema!
  Database.ensure_neutral_cities!
end

helpers do
  def reset_broken_session!
    begin
      session.clear
    rescue StandardError
      # Ignore - cookie may be unreadable.
    end
    response.delete_cookie('rack.session', path: '/')
  end

  def db
    Database.connection
  end

  def current_user
    user_id = begin
      session[:user_id]
    rescue TypeError, ArgumentError
      reset_broken_session!
      nil
    end
    return nil unless user_id

    @current_user ||= db.get_first_row('SELECT id, username FROM users WHERE id = ?', user_id)
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
    begin
      session[:notice] = message
    rescue TypeError, ArgumentError
      reset_broken_session!
    end
  end

  def consume_notice
    notice = begin
      session[:notice]
    rescue TypeError, ArgumentError
      reset_broken_session!
      nil
    end
    begin
      session[:notice] = nil
    rescue TypeError, ArgumentError
      reset_broken_session!
    end
    notice
  end

  def safe_return_path(raw_path, fallback = '/kingdom')
    path = raw_path.to_s
    return fallback if path.empty?
    return fallback unless path.start_with?('/')
    return fallback if path.start_with?('//')
    path
  end

  def normalize_kingdom_resources!(kingdom_id)
    db.execute(
      'UPDATE kingdoms SET wood = CAST(ROUND(wood) AS INTEGER), stone = CAST(ROUND(stone) AS INTEGER), food = CAST(ROUND(food) AS INTEGER), gold = CAST(ROUND(gold) AS INTEGER) WHERE id = ?',
      [kingdom_id]
    )
  end

  def ensure_capital_city!(kingdom)
    city = db.get_first_row('SELECT * FROM world_cities WHERE kingdom_id = ? ORDER BY id LIMIT 1', [kingdom['id']])
    return city if city

    capital_biome = kingdom['capital_biome'].to_s
    capital_biome = 'grassland' unless CAPITAL_BIOME_BONUSES.key?(capital_biome)

    spawn_tile = db.get_first_row(
      'SELECT x, y FROM map_tiles WHERE biome = ? ORDER BY RANDOM() LIMIT 1',
      [capital_biome]
    )
    spawn_x = spawn_tile ? spawn_tile['x'] : 40
    spawn_y = spawn_tile ? spawn_tile['y'] : 40

    db.execute(
      'INSERT INTO world_cities (kingdom_id, name, tile_x, tile_y, vision_radius) VALUES (?, ?, ?, ?, ?)',
      [kingdom['id'], "#{kingdom['name']} Capital", spawn_x, spawn_y, 3]
    )
    db.get_first_row('SELECT * FROM world_cities WHERE kingdom_id = ? ORDER BY id LIMIT 1', [kingdom['id']])
  end
end

before do
  next unless current_user

  kingdom = db.get_first_row('SELECT id FROM kingdoms WHERE user_id = ?', current_user['id'])
  next unless kingdom

  ResourceGeneration.sync!(db, kingdom['id'])
  normalize_kingdom_resources!(kingdom['id'])
  resolve_arrived_expeditions!(kingdom['id'])
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
  elsif password.length < 5 || !(password =~ /[A-Za-z]/) || !(password =~ /[0-9]/)
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
  reset_broken_session!
  redirect '/'
end

get '/kingdom' do
  require_login!
  kingdom = require_kingdom!

  rates = ResourceGeneration.production_rates(db, kingdom['id'])

  rates_per_hour = {}
  rates.each do |resource, rate|
    rates_per_hour[resource] = rate * 60
  end

  rate_tooltips = {
    'wood' => "This city: Base 1 + Lumberyard bonus",
    'stone' => "This city: Base 1 + Quarry bonus",
    'food' => "This city: Base 1 + Farm bonus",
    'gold' => "This city: Base 1 + Tax"
  }




  slim :kingdom, locals: { 
   kingdom: kingdom, 
   user: current_user,
   notice: consume_notice,
   rates_per_hour: rates_per_hour,
   rate_tooltips: rate_tooltips,
   capital_biome: kingdom['capital_biome'].to_s
  }
end

get '/map' do
  require_login!
  kingdom = require_kingdom!

  city = ensure_capital_city!(kingdom)

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

  # Neutral cities in viewport
  neutral_cities = db.execute(
    'SELECT id, name, tile_x, tile_y, garrison FROM world_cities WHERE kingdom_id = 0 AND tile_x BETWEEN ? AND ? AND tile_y BETWEEN ? AND ?',
    [min_x, max_x, min_y, max_y]
  )

  # Active expeditions — from_x/from_y are stored directly on the row
  raw_expeditions = db.execute(
    'SELECT * FROM expeditions WHERE kingdom_id = ?',
    [kingdom['id']]
  )

  now = Time.now.to_i

  expedition_markers = {}
  active_expeditions = []

  raw_expeditions.each do |exp|
    status = exp['status'].to_s

    if status == 'stationed'
      cur_x = exp['dest_x']
      cur_y  = exp['dest_y']
      arrow  = '⚑'
    else
      total   = (exp['arrives_at'] - exp['departed_at']).to_f
      elapsed = (now - exp['departed_at']).to_f
      progress = total > 0 ? (elapsed / total).clamp(0.0, 1.0) : 1.0

      cur_x = exp['from_x'] + ((exp['dest_x'] - exp['from_x']) * progress).round
      cur_y = exp['from_y'] + ((exp['dest_y'] - exp['from_y']) * progress).round

      # Reveal a small area around the army as it moves (3x3)
      (-1..1).each do |dy2|
        (-1..1).each do |dx2|
          db.execute(
            'INSERT OR IGNORE INTO explored_tiles (kingdom_id, x, y) VALUES (?, ?, ?)',
            [kingdom['id'], cur_x + dx2, cur_y + dy2]
          )
        end
      end

      dx = exp['dest_x'] - exp['from_x']
      dy = exp['dest_y'] - exp['from_y']
      arrow = if dx > 0 && dy < 0 then '↗'
              elsif dx > 0 && dy > 0 then '↘'
              elsif dx < 0 && dy > 0 then '↙'
              elsif dx < 0 && dy < 0 then '↖'
              elsif dx > 0 then '→'
              elsif dx < 0 then '←'
              elsif dy < 0 then '↑'
              else '↓'
              end
    end

    eta_seconds = status == 'stationed' ? 0 : [exp['arrives_at'] - now, 0].max
    eta_minutes = (eta_seconds / 60.0).ceil

    expedition_markers[[cur_x, cur_y]] ||= []
    expedition_markers[[cur_x, cur_y]] << {
      id: exp['id'], arrow: arrow, status: status,
      dest_x: exp['dest_x'], dest_y: exp['dest_y']
    }

    active_expeditions << {
      'id'          => exp['id'],
      'cur_x'       => cur_x,   'cur_y'    => cur_y,
      'dest_x'      => exp['dest_x'], 'dest_y' => exp['dest_y'],
      'eta_minutes' => eta_minutes,
      'spearman'    => exp['spearman'], 'archer' => exp['archer'], 'cavalry' => exp['cavalry'],
      'status'      => status
    }
  end

  units = db.execute(
    'SELECT unit_type, quantity FROM units WHERE kingdom_id = ? ORDER BY unit_type ASC',
    [kingdom['id']]
  )

  slim :map, locals: {
    kingdom: kingdom, cx: cx, cy: cy,
    min_x: min_x, max_x: max_x, min_y: min_y, max_y: max_y,
    tile_map: tile_map, visible: visible, explored: explored, cities: cities,
    capital_biome: kingdom['capital_biome'].to_s,
    neutral_cities: neutral_cities,
    expedition_markers: expedition_markers,
    active_expeditions: active_expeditions,
    units: units
  }
end

post '/map/center' do
  require_login!
  x = params[:x].to_i
  y = params[:y].to_i
  redirect "/map?cx=#{x}&cy=#{y}"
end

get '/city/:id' do
  require_login!
  kingdom = require_kingdom!
  tutorial_completed_now = false

  city = db.get_first_row(
    'SELECT * FROM world_cities WHERE id = ? AND kingdom_id = ?',
    [params[:id].to_i, kingdom['id']]
  )
  redirect '/map' unless city

  buildings = db.execute(
    'SELECT name, level FROM buildings WHERE kingdom_id = ? ORDER BY name ASC',
    [kingdom['id']]
  )

  units = db.execute(
    'SELECT unit_type, quantity FROM units WHERE kingdom_id = ? ORDER BY unit_type ASC',
    [kingdom['id']]
  )

  rates = ResourceGeneration.production_rates(db, kingdom['id'])
  rates_per_hour = {}
  rates.each do |resource, rate|
    rates_per_hour[resource] = rate * 60
  end
  tutorial_mode = kingdom['tutorial_mode'].to_s
  tutorial_step = kingdom['tutorial_step'].to_i
  tutorial_text = nil

  if tutorial_mode == 'guided'
    tutorial_step = guided_step_from_state(kingdom['id'])
    if tutorial_step == 0
      db.execute(
        'UPDATE kingdoms SET tutorial_mode = ?, tutorial_step = ? WHERE id = ?',
        ['done', 0, kingdom['id']]
      )
      tutorial_mode = 'done'
      tutorial_completed_now = true
    else
      db.execute(
        'UPDATE kingdoms SET tutorial_step = ? WHERE id = ?',
        [tutorial_step, kingdom['id']]
      )
      tutorial_text = tutorial_step_text(kingdom['name'], tutorial_step)
    end
  end

  rate_tooltips = {
    'wood' => 'City production: Base 1 + Lumberyard bonus',
    'stone' => 'City production: Base 1 + Quarry bonus',
    'food' => 'City production: Base 1 + Farm bonus',
    'gold' => 'City production: Base 1 + Tax'
  }

  slim :city, locals: {
    kingdom: kingdom,
    city: city,
    user: current_user,
    buildings: buildings,
    units: units,
    notice: consume_notice,
    unit_data_map: UNIT_DATA,
    rates_per_hour: rates_per_hour,
    rate_tooltips: rate_tooltips,
    tutorial_mode: tutorial_mode,
    tutorial_step: tutorial_step,
    tutorial_text: tutorial_text,
    tutorial_completed_now: tutorial_completed_now
  }
end
