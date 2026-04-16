require 'sinatra'
require 'slim'
require 'sqlite3'
require 'sinatra/reloader'
require 'bcrypt'
require_relative './db/database'
require_relative './config/game_balance'
require_relative './models/user'
require_relative './models/kingdom'
require_relative './models/building'
require_relative './models/unit'
require_relative './models/expedition'
require_relative './models/world_city'
require_relative './models/map_tile'
require_relative './models/login_attempt'
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

    @current_user ||= User.find(db, user_id)
  end

  def require_login!
    redirect '/login' unless current_user
  end

  def require_admin!
    require_login!
    redirect '/kingdom' unless current_user['role'] == 'admin'
  end

  def require_kingdom!
    kingdom = Kingdom.find_by_user(db, current_user['id'])
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
    Kingdom.normalize_resources!(db, kingdom_id)
  end

  def ensure_capital_city!(kingdom)
    city = WorldCity.capital(db, kingdom['id'])
    return city if city

    capital_biome = kingdom['capital_biome'].to_s
    capital_biome = 'grassland' unless CAPITAL_BIOME_BONUSES.key?(capital_biome)

    spawn_tile = MapTile.random_of_biome(db, capital_biome)
    spawn_x = spawn_tile ? spawn_tile['x'] : 40
    spawn_y = spawn_tile ? spawn_tile['y'] : 40

    WorldCity.create!(db, kingdom['id'], "#{kingdom['name']} Capital", spawn_x, spawn_y, 3)
  end
end

before do
  next unless current_user

  kingdom = Kingdom.find_by_user(db, current_user['id'])
  next unless kingdom

  ResourceGeneration.sync!(db, kingdom['id'])
  normalize_kingdom_resources!(kingdom['id'])
  resolve_arrived_expeditions!(kingdom['id'])
end

after do
  Database.close_connection
end


# @route GET /
# @description Landing page. Shows login and register links.
get '/' do
  slim :home
end

# @route GET /register
# @description Displays the registration form.
get '/register' do
  slim :register
end

# @route POST /register
# @description Creates a new user account and kingdom.
# @param username [String] Minimum 3 characters, must be unique.
# @param kingdom_name [String] Minimum 3 characters.
# @param password [String] Minimum 5 characters, must include a letter and a number.
post '/register' do
  username     = params[:username].to_s.strip
  kingdom_name = params[:kingdom_name].to_s.strip
  password     = params[:password].to_s

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
  user_id = User.create!(db, username, password_hash)
  Kingdom.create!(db, user_id, kingdom_name)

  redirect '/login'
rescue SQLite3::ConstraintException
  @error = 'Username already exists.'
  slim :register
end

# @route GET /login
# @description Displays the login form.
get '/login' do
  slim :login
end

# @route POST /login
# @description Authenticates the user. Blocks after 5 failed attempts within 15 minutes.
# @param username [String]
# @param password [String]
post '/login' do
  username = params[:username].to_s.strip
  password = params[:password].to_s

  if LoginAttempt.locked_out?(db, username)
    secs = LoginAttempt.cooldown_seconds(db, username)
    mins = (secs / 60.0).ceil
    @error = "Too many failed attempts. Try again in #{mins} minute(s)."
    next slim :login
  end

  user = User.find_by_username(db, username)

  if user && BCrypt::Password.new(user['password_hash']) == password
    LoginAttempt.log!(db, username, true)
    session[:user_id] = user['id']

    kingdom = Kingdom.find_by_user(db, user['id'])
    if kingdom && kingdom['tutorial_mode'] == 'pending'
      redirect '/tutorial/start'
    else
      redirect '/kingdom'
    end
  else
    LoginAttempt.log!(db, username, false)
    @error = 'Invalid username or password.'
    slim :login
  end
end

# @route POST /logout
# @description Clears the session and redirects to home.
# @requires_login true
post '/logout' do
  reset_broken_session!
  redirect '/'
end

# @route GET /kingdom
# @description Kingdom overview — shows resources, production rates and cities.
# @requires_login true
get '/kingdom' do
  require_login!
  kingdom = require_kingdom!

  rates = ResourceGeneration.production_rates(db, kingdom['id'])

  rates_per_hour = {}
  rates.each do |resource, rate|
    rates_per_hour[resource] = rate * 60
  end

  rate_tooltips = {
    'wood'  => 'This city: Base 1 + Lumberyard bonus',
    'stone' => 'This city: Base 1 + Quarry bonus',
    'food'  => 'This city: Base 1 + Farm bonus',
    'gold'  => 'This city: Base 1 + Tax'
  }

  slim :kingdom, locals: {
    kingdom:       kingdom,
    user:          current_user,
    notice:        consume_notice,
    rates_per_hour: rates_per_hour,
    rate_tooltips: rate_tooltips,
    capital_biome: kingdom['capital_biome'].to_s
  }
end

# @route GET /map
# @description World map view — renders the visible tile grid, cities, and active expeditions.
# @param cx [Integer] Center X coordinate (optional, defaults to capital city X).
# @param cy [Integer] Center Y coordinate (optional, defaults to capital city Y).
# @requires_login true
get '/map' do
  require_login!
  kingdom = require_kingdom!

  city = ensure_capital_city!(kingdom)

  cx   = (params[:cx] || city['tile_x']).to_i
  cy   = (params[:cy] || city['tile_y']).to_i
  half = 10
  min_x, max_x = cx - half, cx + half
  min_y, max_y = cy - half, cy + half

  tiles    = MapTile.in_viewport(db, min_x, max_x, min_y, max_y)
  tile_map = {}
  tiles.each { |t| tile_map[[t['x'], t['y']]] = t }

  cities = WorldCity.all_for_kingdom(db, kingdom['id'])

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
    ExploredTile.add!(db, kingdom['id'], x, y)
  end

  # JOIN query: explored_tiles is a many-to-many junction between kingdoms and map_tiles.
  explored_rows = ExploredTile.in_viewport_with_biome(db, kingdom['id'], min_x, max_x, min_y, max_y)
  explored = {}
  explored_rows.each { |r| explored[[r['x'], r['y']]] = true }

  neutral_cities = WorldCity.neutral_in_viewport(db, min_x, max_x, min_y, max_y)
  enemy_cities   = WorldCity.enemy_in_viewport(db, kingdom['id'], min_x, max_x, min_y, max_y)

  raw_expeditions = Expedition.all_for_kingdom(db, kingdom['id'])

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
      total    = (exp['arrives_at'] - exp['departed_at']).to_f
      elapsed  = (now - exp['departed_at']).to_f
      progress = total > 0 ? (elapsed / total).clamp(0.0, 1.0) : 1.0

      cur_x = exp['from_x'] + ((exp['dest_x'] - exp['from_x']) * progress).round
      cur_y = exp['from_y'] + ((exp['dest_y'] - exp['from_y']) * progress).round

      (-1..1).each do |dy2|
        (-1..1).each do |dx2|
          ExploredTile.add!(db, kingdom['id'], cur_x + dx2, cur_y + dy2)
        end
      end

      dx    = exp['dest_x'] - exp['from_x']
      dy    = exp['dest_y'] - exp['from_y']
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

  units = Unit.all_for_kingdom(db, kingdom['id'])

  slim :map, locals: {
    kingdom: kingdom, cx: cx, cy: cy,
    min_x: min_x, max_x: max_x, min_y: min_y, max_y: max_y,
    tile_map: tile_map, visible: visible, explored: explored, cities: cities,
    capital_biome:      kingdom['capital_biome'].to_s,
    neutral_cities:     neutral_cities,
    enemy_cities:       enemy_cities,
    expedition_markers: expedition_markers,
    active_expeditions: active_expeditions,
    units:              units
  }
end

# @route POST /map/center
# @description Redirects the map view to center on given coordinates.
# @param x [Integer] Target X coordinate.
# @param y [Integer] Target Y coordinate.
# @requires_login true
post '/map/center' do
  require_login!
  x = params[:x].to_i
  y = params[:y].to_i
  redirect "/map?cx=#{x}&cy=#{y}"
end

# @route GET /city/:id
# @description City management view — shows buildings, units and tutorial progress.
# @param id [Integer] The city ID. Must belong to the current user's kingdom.
# @requires_login true
get '/city/:id' do
  require_login!
  kingdom = require_kingdom!
  tutorial_completed_now = false

  city = WorldCity.find(db, params[:id].to_i, kingdom['id'])
  redirect '/map' unless city

  buildings = Building.all_for_kingdom(db, kingdom['id'])
  units     = Unit.all_for_kingdom(db, kingdom['id'])

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
      Kingdom.set_tutorial!(db, kingdom['id'], 'done', 0)
      tutorial_mode          = 'done'
      tutorial_completed_now = true
    else
      Kingdom.set_tutorial_step!(db, kingdom['id'], tutorial_step)
      tutorial_text = tutorial_step_text(kingdom['name'], tutorial_step)
    end
  end

  rate_tooltips = {
    'wood'  => 'City production: Base 1 + Lumberyard bonus',
    'stone' => 'City production: Base 1 + Quarry bonus',
    'food'  => 'City production: Base 1 + Farm bonus',
    'gold'  => 'City production: Base 1 + Tax'
  }

  slim :city, locals: {
    kingdom:               kingdom,
    city:                  city,
    user:                  current_user,
    buildings:             buildings,
    units:                 units,
    notice:                consume_notice,
    unit_data_map:         UNIT_DATA,
    rates_per_hour:        rates_per_hour,
    rate_tooltips:         rate_tooltips,
    tutorial_mode:         tutorial_mode,
    tutorial_step:         tutorial_step,
    tutorial_text:         tutorial_text,
    tutorial_completed_now: tutorial_completed_now
  }
end

# @route GET /admin
# @description Admin dashboard — lists all users and their kingdoms.
# @requires_role admin
get '/admin' do
  require_admin!
  users = User.all_with_kingdoms(db)
  slim :admin, locals: { users: users, notice: consume_notice }
end

# @route POST /admin/promote/:id
# @description Promotes a user to admin role.
# @requires_role admin
post '/admin/promote/:id' do
  require_admin!
  User.set_role!(db, params[:id].to_i, 'admin')
  set_notice('User promoted to admin.')
  redirect '/admin'
end

# @route POST /admin/demote/:id
# @description Demotes an admin to standard user role.
# @requires_role admin
post '/admin/demote/:id' do
  require_admin!
  redirect '/admin' if params[:id].to_i == current_user['id']
  User.set_role!(db, params[:id].to_i, 'user')
  set_notice('User demoted to standard user.')
  redirect '/admin'
end

# @route POST /admin/delete/:id
# @description Deletes a user account and all associated data.
# @requires_role admin
post '/admin/delete/:id' do
  require_admin!
  target_id = params[:id].to_i
  redirect '/admin' if target_id == current_user['id']
  target = User.find(db, target_id)
  redirect '/admin' unless target
  redirect '/admin' if target['role'] == 'admin'
  User.delete!(db, target_id)
  set_notice("Account '#{target['username']}' deleted.")
  redirect '/admin'
end

# @route POST /admin/kingdom/:id/resources
# @description Sets a kingdom's resources directly.
# @requires_role admin
post '/admin/kingdom/:id/resources' do
  require_admin!
  kingdom_id = params[:id].to_i
  wood  = params[:wood].to_i
  stone = params[:stone].to_i
  food  = params[:food].to_i
  gold  = params[:gold].to_i
  Kingdom.set_resources!(db, kingdom_id, wood, stone, food, gold)
  set_notice('Kingdom resources updated.')
  redirect '/admin'
end
