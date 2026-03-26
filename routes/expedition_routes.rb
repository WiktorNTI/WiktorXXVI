helpers do
  def apply_casualties(spearman, archer, cavalry, survivor_ratio)
    new_s = (spearman * survivor_ratio).ceil
    new_a = (archer   * survivor_ratio).ceil
    new_c = (cavalry  * survivor_ratio).ceil
    if new_s + new_a + new_c == 0 && spearman + archer + cavalry > 0
      if cavalry > 0 then new_c = 1
      elsif archer > 0 then new_a = 1
      else new_s = 1
      end
    end
    [new_s, new_a, new_c]
  end

  def initialize_captured_city!(kingdom_id, _city_id)
    ['Farm', 'Barracks'].each do |b|
      db.execute('INSERT OR IGNORE INTO buildings (kingdom_id, name, level) VALUES (?, ?, 1)',
                 [kingdom_id, b])
    end
  end

  def resolve_pvp_attack!(attacker_exp, defender_city, attacker_kingdom_id)
    defender_kingdom_id = defender_city['kingdom_id']
    dest_x = attacker_exp['dest_x']
    dest_y  = attacker_exp['dest_y']

    atk_str = attacker_exp['spearman'] * UNIT_STRENGTH['Spearman'] +
              attacker_exp['archer']   * UNIT_STRENGTH['Archer'] +
              attacker_exp['cavalry']  * UNIT_STRENGTH['Cavalry']

    stationed_defenders = db.execute(
      "SELECT * FROM expeditions WHERE kingdom_id = ? AND dest_x = ? AND dest_y = ? AND status = 'stationed'",
      [defender_kingdom_id, dest_x, dest_y]
    )

    def_army_str = stationed_defenders.sum do |d|
      d['spearman'] * UNIT_STRENGTH['Spearman'] +
      d['archer']   * UNIT_STRENGTH['Archer'] +
      d['cavalry']  * UNIT_STRENGTH['Cavalry']
    end
    def_garrison_str = defender_city['garrison'].to_i
    def_total_str = def_army_str + def_garrison_str

    city_name = defender_city['name']

    if atk_str >= def_total_str
      survivor_ratio = def_total_str > 0 ? [[1.0 - (def_total_str.to_f / atk_str), 0.05].max, 1.0].min : 1.0
      new_s, new_a, new_c = apply_casualties(
        attacker_exp['spearman'], attacker_exp['archer'], attacker_exp['cavalry'], survivor_ratio
      )

      stationed_defenders.each { |d| db.execute('DELETE FROM expeditions WHERE id = ?', [d['id']]) }

      db.execute('UPDATE world_cities SET kingdom_id = ? WHERE id = ?', [attacker_kingdom_id, defender_city['id']])
      initialize_captured_city!(attacker_kingdom_id, defender_city['id'])

      db.execute(
        "UPDATE expeditions SET spearman = ?, archer = ?, cavalry = ?, status = 'stationed' WHERE id = ?",
        [new_s, new_a, new_c, attacker_exp['id']]
      )
      set_notice("Victory over #{city_name}! City captured. Survivors: #{new_s}S #{new_a}A #{new_c}C.")
    else
      db.execute('DELETE FROM expeditions WHERE id = ?', [attacker_exp['id']])

      if def_army_str > 0
        survivor_ratio = [[1.0 - (atk_str.to_f / def_total_str), 0.05].max, 1.0].min
        stationed_defenders.each do |d|
          new_s, new_a, new_c = apply_casualties(d['spearman'], d['archer'], d['cavalry'], survivor_ratio)
          db.execute('UPDATE expeditions SET spearman = ?, archer = ?, cavalry = ? WHERE id = ?',
                     [new_s, new_a, new_c, d['id']])
        end
      end

      set_notice("Defeat! Your army was destroyed attacking #{city_name}.")
    end
  end

  def resolve_arrived_expeditions!(kingdom_id)
    now = Time.now.to_i
    arrived = db.execute(
      "SELECT * FROM expeditions WHERE kingdom_id = ? AND arrives_at <= ? AND status != 'stationed'",
      [kingdom_id, now]
    )

    arrived.each do |exp|
      if exp['status'] == 'recalling'
        db.execute('UPDATE units SET quantity = quantity + ? WHERE kingdom_id = ? AND unit_type = ?', [exp['spearman'], kingdom_id, 'Spearman']) if exp['spearman'] > 0
        db.execute('UPDATE units SET quantity = quantity + ? WHERE kingdom_id = ? AND unit_type = ?', [exp['archer'],   kingdom_id, 'Archer'])   if exp['archer']   > 0
        db.execute('UPDATE units SET quantity = quantity + ? WHERE kingdom_id = ? AND unit_type = ?', [exp['cavalry'],  kingdom_id, 'Cavalry'])  if exp['cavalry']  > 0
        db.execute('DELETE FROM expeditions WHERE id = ?', [exp['id']])
        set_notice("Army returned home. Troops restored.")

      else
        # Reveal tiles around destination (7x7)
        (-3..3).each do |dy|
          (-3..3).each do |dx|
            db.execute(
              'INSERT OR IGNORE INTO explored_tiles (kingdom_id, x, y) VALUES (?, ?, ?)',
              [kingdom_id, exp['dest_x'] + dx, exp['dest_y'] + dy]
            )
          end
        end

        strength = exp['spearman'] * UNIT_STRENGTH['Spearman'] +
                   exp['archer']   * UNIT_STRENGTH['Archer'] +
                   exp['cavalry']  * UNIT_STRENGTH['Cavalry']

        neutral_city = db.get_first_row(
          'SELECT * FROM world_cities WHERE tile_x = ? AND tile_y = ? AND kingdom_id = 0',
          [exp['dest_x'], exp['dest_y']]
        )
        enemy_city = db.get_first_row(
          'SELECT * FROM world_cities WHERE tile_x = ? AND tile_y = ? AND kingdom_id != 0 AND kingdom_id != ?',
          [exp['dest_x'], exp['dest_y'], kingdom_id]
        )

        if neutral_city
          garrison = neutral_city['garrison'].to_i
          if strength == 0
            db.execute("UPDATE expeditions SET status = 'stationed' WHERE id = ?", [exp['id']])
            set_notice("Scout reached #{neutral_city['name']} (Garrison: #{garrison}). Area revealed.")
          elsif strength >= garrison
            db.execute('UPDATE world_cities SET kingdom_id = ? WHERE id = ?', [kingdom_id, neutral_city['id']])
            initialize_captured_city!(kingdom_id, neutral_city['id'])
            db.execute("UPDATE expeditions SET status = 'stationed' WHERE id = ?", [exp['id']])
            set_notice("Victory! Captured #{neutral_city['name']} (#{strength} vs garrison #{garrison}). Army stationed.")
          else
            new_garrison = [garrison - strength, 0].max
            db.execute('UPDATE world_cities SET garrison = ? WHERE id = ?', [new_garrison, neutral_city['id']])
            db.execute('DELETE FROM expeditions WHERE id = ?', [exp['id']])
            set_notice("Defeat at #{neutral_city['name']} (#{strength} vs garrison #{garrison}). Garrison reduced to #{new_garrison}. Army lost.")
          end

        elsif enemy_city
          resolve_pvp_attack!(exp, enemy_city, kingdom_id)

        else
          db.execute("UPDATE expeditions SET status = 'stationed' WHERE id = ?", [exp['id']])
          set_notice("Army reached (#{exp['dest_x']}, #{exp['dest_y']}). Area explored. Army stationed.")
        end
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

  is_scout = params[:scout].to_s == '1'
  if !is_scout && sent_spearman + sent_archer + sent_cavalry < 1
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

  label = is_scout ? "Scout sent to (#{dest_x}, #{dest_y})." : "Expedition sent to (#{dest_x}, #{dest_y})."
  set_notice("#{label} Arrives in #{dist * TRAVEL_MINUTES_PER_TILE} min.")
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
