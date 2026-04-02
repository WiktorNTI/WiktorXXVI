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
    Building.create_captured!(db, kingdom_id)
  end

  def resolve_pvp_attack!(attacker_exp, defender_city, attacker_kingdom_id)
    defender_kingdom_id = defender_city['kingdom_id']
    dest_x = attacker_exp['dest_x']
    dest_y  = attacker_exp['dest_y']

    atk_str = attacker_exp['spearman'] * UNIT_STRENGTH['Spearman'] +
              attacker_exp['archer']   * UNIT_STRENGTH['Archer'] +
              attacker_exp['cavalry']  * UNIT_STRENGTH['Cavalry']

    stationed_defenders = Expedition.stationed_at(db, defender_kingdom_id, dest_x, dest_y)

    def_army_str = stationed_defenders.sum do |d|
      d['spearman'] * UNIT_STRENGTH['Spearman'] +
      d['archer']   * UNIT_STRENGTH['Archer'] +
      d['cavalry']  * UNIT_STRENGTH['Cavalry']
    end
    def_garrison_str = defender_city['garrison'].to_i
    def_total_str    = def_army_str + def_garrison_str

    city_name = defender_city['name']

    if atk_str >= def_total_str
      survivor_ratio = def_total_str > 0 ? [[1.0 - (def_total_str.to_f / atk_str), 0.05].max, 1.0].min : 1.0
      new_s, new_a, new_c = apply_casualties(
        attacker_exp['spearman'], attacker_exp['archer'], attacker_exp['cavalry'], survivor_ratio
      )

      stationed_defenders.each { |d| Expedition.delete!(db, d['id']) }

      WorldCity.capture!(db, defender_city['id'], attacker_kingdom_id)
      initialize_captured_city!(attacker_kingdom_id, defender_city['id'])
      Expedition.set_stationed!(db, attacker_exp['id'], new_s, new_a, new_c)

      set_notice("Victory over #{city_name}! City captured. Survivors: #{new_s}S #{new_a}A #{new_c}C.")
    else
      Expedition.delete!(db, attacker_exp['id'])

      if def_army_str > 0
        survivor_ratio = [[1.0 - (atk_str.to_f / def_total_str), 0.05].max, 1.0].min
        stationed_defenders.each do |d|
          new_s, new_a, new_c = apply_casualties(d['spearman'], d['archer'], d['cavalry'], survivor_ratio)
          Expedition.update_casualties!(db, d['id'], new_s, new_a, new_c)
        end
      end

      set_notice("Defeat! Your army was destroyed attacking #{city_name}.")
    end
  end

  def resolve_arrived_expeditions!(kingdom_id)
    now     = Time.now.to_i
    arrived = Expedition.arrived(db, kingdom_id, now)

    arrived.each do |exp|
      if exp['status'] == 'recalling'
        Unit.add!(db, kingdom_id, 'Spearman', exp['spearman']) if exp['spearman'] > 0
        Unit.add!(db, kingdom_id, 'Archer',   exp['archer'])   if exp['archer']   > 0
        Unit.add!(db, kingdom_id, 'Cavalry',  exp['cavalry'])  if exp['cavalry']  > 0
        Expedition.delete!(db, exp['id'])
        set_notice('Army returned home. Troops restored.')

      else
        # Reveal tiles around destination (7x7)
        (-3..3).each do |dy|
          (-3..3).each do |dx|
            ExploredTile.add!(db, kingdom_id, exp['dest_x'] + dx, exp['dest_y'] + dy)
          end
        end

        strength = exp['spearman'] * UNIT_STRENGTH['Spearman'] +
                   exp['archer']   * UNIT_STRENGTH['Archer'] +
                   exp['cavalry']  * UNIT_STRENGTH['Cavalry']

        neutral_city = WorldCity.neutral_at(db, exp['dest_x'], exp['dest_y'])
        enemy_city   = WorldCity.enemy_at(db, exp['dest_x'], exp['dest_y'], kingdom_id)

        if neutral_city
          garrison = neutral_city['garrison'].to_i
          if strength == 0
            Expedition.set_stationed!(db, exp['id'])
            set_notice("Scout reached #{neutral_city['name']} (Garrison: #{garrison}). Area revealed.")
          elsif strength >= garrison
            WorldCity.capture!(db, neutral_city['id'], kingdom_id)
            initialize_captured_city!(kingdom_id, neutral_city['id'])
            Expedition.set_stationed!(db, exp['id'])
            set_notice("Victory! Captured #{neutral_city['name']} (#{strength} vs garrison #{garrison}). Army stationed.")
          else
            new_garrison = [garrison - strength, 0].max
            WorldCity.update_garrison!(db, neutral_city['id'], new_garrison)
            Expedition.delete!(db, exp['id'])
            set_notice("Defeat at #{neutral_city['name']} (#{strength} vs garrison #{garrison}). Garrison reduced to #{new_garrison}. Army lost.")
          end

        elsif enemy_city
          resolve_pvp_attack!(exp, enemy_city, kingdom_id)

        else
          Expedition.set_stationed!(db, exp['id'])
          set_notice("Army reached (#{exp['dest_x']}, #{exp['dest_y']}). Area explored. Army stationed.")
        end
      end
    end
  end
end

# @route POST /expedition/send
# @description Sends an army (or scout) from a city to a destination tile.
# @param from_city_id [Integer] Source city ID (must belong to the kingdom).
# @param dest_x [Integer] Destination X coordinate (0–79).
# @param dest_y [Integer] Destination Y coordinate (0–79).
# @param spearman [Integer] Number of spearmen to send.
# @param archer [Integer] Number of archers to send.
# @param cavalry [Integer] Number of cavalry to send.
# @param scout [String] Pass "1" to send a zero-unit scout expedition.
# @requires_login true
post '/expedition/send' do
  require_login!
  kingdom = require_kingdom!

  from_city_id  = params[:from_city_id].to_i
  dest_x        = params[:dest_x].to_i.clamp(0, 79)
  dest_y        = params[:dest_y].to_i.clamp(0, 79)
  sent_spearman = [params[:spearman].to_i, 0].max
  sent_archer   = [params[:archer].to_i,   0].max
  sent_cavalry  = [params[:cavalry].to_i,  0].max

  source_city = WorldCity.find(db, from_city_id, kingdom['id'])
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

  spearman_row = Unit.find(db, kingdom['id'], 'Spearman')
  archer_row   = Unit.find(db, kingdom['id'], 'Archer')
  cavalry_row  = Unit.find(db, kingdom['id'], 'Cavalry')

  spearman_have = spearman_row ? spearman_row['quantity'] : 0
  archer_have   = archer_row   ? archer_row['quantity']   : 0
  cavalry_have  = cavalry_row  ? cavalry_row['quantity']  : 0

  if sent_spearman > spearman_have || sent_archer > archer_have || sent_cavalry > cavalry_have
    set_notice('Not enough units.')
    redirect '/map'
  end

  Unit.remove!(db, kingdom['id'], 'Spearman', sent_spearman) if sent_spearman > 0
  Unit.remove!(db, kingdom['id'], 'Archer',   sent_archer)   if sent_archer   > 0
  Unit.remove!(db, kingdom['id'], 'Cavalry',  sent_cavalry)  if sent_cavalry  > 0

  from_x = source_city['tile_x']
  from_y = source_city['tile_y']
  dist   = [(dest_x - from_x).abs, (dest_y - from_y).abs].max
  dist   = [dist, 1].max
  now    = Time.now.to_i

  Expedition.create!(
    db, kingdom['id'], from_city_id,
    from_x, from_y, dest_x, dest_y,
    sent_spearman, sent_archer, sent_cavalry,
    now, now + dist * TRAVEL_MINUTES_PER_TILE * 60
  )

  label = is_scout ? "Scout sent to (#{dest_x}, #{dest_y})." : "Expedition sent to (#{dest_x}, #{dest_y})."
  set_notice("#{label} Arrives in #{dist * TRAVEL_MINUTES_PER_TILE} min.")
  redirect "/map?cx=#{from_x}&cy=#{from_y}"
end

# @route POST /expedition/:id/redeploy
# @description Moves a stationed army to a new destination tile.
# @param id [Integer] Expedition ID (must be stationed and belong to the kingdom).
# @param dest_x [Integer] New destination X coordinate (0–79).
# @param dest_y [Integer] New destination Y coordinate (0–79).
# @requires_login true
post '/expedition/:id/redeploy' do
  require_login!
  kingdom = require_kingdom!

  exp = Expedition.find_stationed(db, params[:id].to_i, kingdom['id'])
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
  now  = Time.now.to_i

  Expedition.redeploy!(
    db, exp['id'],
    exp['dest_x'], exp['dest_y'], new_dest_x, new_dest_y,
    now, now + dist * TRAVEL_MINUTES_PER_TILE * 60
  )

  set_notice("Army redeployed to (#{new_dest_x}, #{new_dest_y}). Arrives in #{dist * TRAVEL_MINUTES_PER_TILE} min.")
  redirect '/map'
end

# @route POST /expedition/:id/recall
# @description Recalls a stationed army back to its home city.
# @param id [Integer] Expedition ID (must be stationed and belong to the kingdom).
# @requires_login true
post '/expedition/:id/recall' do
  require_login!
  kingdom = require_kingdom!

  exp = Expedition.find_stationed(db, params[:id].to_i, kingdom['id'])
  unless exp
    set_notice('Army not found or not stationed.')
    redirect '/map'
  end

  home_city = WorldCity.find(db, exp['home_city_id'], kingdom['id'])
  unless home_city
    set_notice('Home city not found.')
    redirect '/map'
  end

  dist = [(home_city['tile_x'] - exp['dest_x']).abs, (home_city['tile_y'] - exp['dest_y']).abs].max
  dist = [dist, 1].max
  now  = Time.now.to_i

  Expedition.recall!(
    db, exp['id'],
    exp['dest_x'], exp['dest_y'], home_city['tile_x'], home_city['tile_y'],
    now, now + dist * TRAVEL_MINUTES_PER_TILE * 60
  )

  set_notice("Army is returning home. Arrives in #{dist * TRAVEL_MINUTES_PER_TILE} min.")
  redirect '/map'
end
