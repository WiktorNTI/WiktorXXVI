helpers do
  def resolve_arrived_expeditions!(kingdom_id)
    now = Time.now.to_i
    arrived = db.execute(
      "SELECT * FROM expeditions WHERE kingdom_id = ? AND arrives_at <= ? AND status != 'stationed'",
      [kingdom_id, now]
    )

    arrived.each do |exp|
      if exp['status'] == 'recalling'
        # Return troops to the kingdom's unit counts
        db.execute('UPDATE units SET quantity = quantity + ? WHERE kingdom_id = ? AND unit_type = ?', [exp['spearman'], kingdom_id, 'Spearman']) if exp['spearman'] > 0
        db.execute('UPDATE units SET quantity = quantity + ? WHERE kingdom_id = ? AND unit_type = ?', [exp['archer'],   kingdom_id, 'Archer'])   if exp['archer']   > 0
        db.execute('UPDATE units SET quantity = quantity + ? WHERE kingdom_id = ? AND unit_type = ?', [exp['cavalry'],  kingdom_id, 'Cavalry'])  if exp['cavalry']  > 0
        db.execute('DELETE FROM expeditions WHERE id = ?', [exp['id']])
        set_notice("Army returned home. Troops restored.")

      else
        # Reveal tiles around destination (7x7 like a city)
        (-3..3).each do |dy|
          (-3..3).each do |dx|
            db.execute(
              'INSERT OR IGNORE INTO explored_tiles (kingdom_id, x, y) VALUES (?, ?, ?)',
              [kingdom_id, exp['dest_x'] + dx, exp['dest_y'] + dy]
            )
          end
        end

        # Check for a neutral city at the destination
        city = db.get_first_row(
          'SELECT * FROM world_cities WHERE tile_x = ? AND tile_y = ? AND kingdom_id = 0',
          [exp['dest_x'], exp['dest_y']]
        )

        if city
          strength = exp['spearman'] * UNIT_STRENGTH['Spearman'] +
                     exp['archer']   * UNIT_STRENGTH['Archer'] +
                     exp['cavalry']  * UNIT_STRENGTH['Cavalry']
          garrison = city['garrison'].to_i

          if strength >= garrison
            db.execute('UPDATE world_cities SET kingdom_id = ? WHERE id = ?', [kingdom_id, city['id']])
            set_notice("Victory! Captured #{city['name']} (strength: #{strength} vs garrison: #{garrison}). Army is stationed there.")
          else
            set_notice("Defeat at #{city['name']} (strength: #{strength} vs garrison: #{garrison}). Army is stationed there.")
          end
        else
          set_notice("Army reached (#{exp['dest_x']}, #{exp['dest_y']}). Area explored. Army is stationed.")
        end

        # Army stays — mark as stationed
        db.execute("UPDATE expeditions SET status = 'stationed' WHERE id = ?", [exp['id']])
      end
    end
  end
end

post '/expedition/send' do
  require_login!
  kingdom = require_kingdom!

  from_city_id = params[:from_city_id].to_i
  dest_x = params[:dest_x].to_i.clamp(0, 79)
  dest_y = params[:dest_y].to_i.clamp(0, 79)
  sent_spearman = [params[:spearman].to_i, 0].max
  sent_archer   = [params[:archer].to_i,   0].max
  sent_cavalry  = [params[:cavalry].to_i,  0].max

  source_city = db.get_first_row(
    'SELECT * FROM world_cities WHERE id = ? AND kingdom_id = ?',
    [from_city_id, kingdom['id']]
  )
  unless source_city
    set_notice('Invalid source city.')
    redirect '/map'
  end

  if sent_spearman + sent_archer + sent_cavalry < 1
    set_notice('You must send at least 1 unit.')
    redirect '/map'
  end

  if dest_x == source_city['tile_x'] && dest_y == source_city['tile_y']
    set_notice('Destination cannot be the same tile as the source city.')
    redirect '/map'
  end

  spearman_row = db.get_first_row('SELECT quantity FROM units WHERE kingdom_id = ? AND unit_type = ?', [kingdom['id'], 'Spearman'])
  archer_row   = db.get_first_row('SELECT quantity FROM units WHERE kingdom_id = ? AND unit_type = ?', [kingdom['id'], 'Archer'])
  cavalry_row  = db.get_first_row('SELECT quantity FROM units WHERE kingdom_id = ? AND unit_type = ?', [kingdom['id'], 'Cavalry'])

  spearman_have = spearman_row ? spearman_row['quantity'] : 0
  archer_have   = archer_row   ? archer_row['quantity']   : 0
  cavalry_have  = cavalry_row  ? cavalry_row['quantity']  : 0

  if sent_spearman > spearman_have || sent_archer > archer_have || sent_cavalry > cavalry_have
    set_notice('Not enough units.')
    redirect '/map'
  end

  db.execute('UPDATE units SET quantity = quantity - ? WHERE kingdom_id = ? AND unit_type = ?', [sent_spearman, kingdom['id'], 'Spearman']) if sent_spearman > 0
  db.execute('UPDATE units SET quantity = quantity - ? WHERE kingdom_id = ? AND unit_type = ?', [sent_archer,   kingdom['id'], 'Archer'])   if sent_archer   > 0
  db.execute('UPDATE units SET quantity = quantity - ? WHERE kingdom_id = ? AND unit_type = ?', [sent_cavalry,  kingdom['id'], 'Cavalry'])  if sent_cavalry  > 0

  from_x = source_city['tile_x']
  from_y = source_city['tile_y']
  dist = [(dest_x - from_x).abs, (dest_y - from_y).abs].max
  dist = [dist, 1].max
  now = Time.now.to_i

  db.execute(
    'INSERT INTO expeditions (kingdom_id, home_city_id, from_x, from_y, dest_x, dest_y, spearman, archer, cavalry, departed_at, arrives_at, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [kingdom['id'], from_city_id, from_x, from_y, dest_x, dest_y, sent_spearman, sent_archer, sent_cavalry, now, now + dist * TRAVEL_MINUTES_PER_TILE * 60, 'traveling']
  )

  set_notice("Expedition sent to (#{dest_x}, #{dest_y}). Arrives in #{dist * TRAVEL_MINUTES_PER_TILE} min.")
  redirect "/map?cx=#{from_x}&cy=#{from_y}"
end

post '/expedition/:id/redeploy' do
  require_login!
  kingdom = require_kingdom!

  exp = db.get_first_row(
    "SELECT * FROM expeditions WHERE id = ? AND kingdom_id = ? AND status = 'stationed'",
    [params[:id].to_i, kingdom['id']]
  )
  unless exp
    set_notice('Army not found or not stationed.')
    redirect '/map'
  end

  new_dest_x = params[:dest_x].to_i.clamp(0, 79)
  new_dest_y = params[:dest_y].to_i.clamp(0, 79)

  if new_dest_x == exp['dest_x'] && new_dest_y == exp['dest_y']
    set_notice('Destination is the same as current position.')
    redirect '/map'
  end

  dist = [(new_dest_x - exp['dest_x']).abs, (new_dest_y - exp['dest_y']).abs].max
  dist = [dist, 1].max
  now = Time.now.to_i

  db.execute(
    "UPDATE expeditions SET from_x = ?, from_y = ?, dest_x = ?, dest_y = ?, departed_at = ?, arrives_at = ?, status = 'traveling' WHERE id = ?",
    [exp['dest_x'], exp['dest_y'], new_dest_x, new_dest_y, now, now + dist * TRAVEL_MINUTES_PER_TILE * 60, exp['id']]
  )

  set_notice("Army redeployed to (#{new_dest_x}, #{new_dest_y}). Arrives in #{dist * TRAVEL_MINUTES_PER_TILE} min.")
  redirect '/map'
end

post '/expedition/:id/recall' do
  require_login!
  kingdom = require_kingdom!

  exp = db.get_first_row(
    "SELECT * FROM expeditions WHERE id = ? AND kingdom_id = ? AND status = 'stationed'",
    [params[:id].to_i, kingdom['id']]
  )
  unless exp
    set_notice('Army not found or not stationed.')
    redirect '/map'
  end

  home_city = db.get_first_row(
    'SELECT tile_x, tile_y FROM world_cities WHERE id = ? AND kingdom_id = ?',
    [exp['home_city_id'], kingdom['id']]
  )
  unless home_city
    set_notice('Home city not found.')
    redirect '/map'
  end

  dist = [(home_city['tile_x'] - exp['dest_x']).abs, (home_city['tile_y'] - exp['dest_y']).abs].max
  dist = [dist, 1].max
  now = Time.now.to_i

  db.execute(
    "UPDATE expeditions SET from_x = ?, from_y = ?, dest_x = ?, dest_y = ?, departed_at = ?, arrives_at = ?, status = 'recalling' WHERE id = ?",
    [exp['dest_x'], exp['dest_y'], home_city['tile_x'], home_city['tile_y'], now, now + dist * TRAVEL_MINUTES_PER_TILE * 60, exp['id']]
  )

  set_notice("Army is returning home. Arrives in #{dist * TRAVEL_MINUTES_PER_TILE} min.")
  redirect '/map'
end
