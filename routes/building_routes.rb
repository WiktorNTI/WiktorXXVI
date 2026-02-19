helpers do
  def building_upgrade_cost(name, next_level)
    base = BUILDING_BASE_COSTS.fetch(name)
    base.transform_values { |amount| amount * next_level }
  end

  def can_afford?(kingdom, cost)
    cost.all? { |resource, amount| kingdom[resource] >= amount }
  end

  def spend_resources!(kingdom_id, kingdom, cost)
    new_wood = kingdom['wood'] - cost.fetch('wood', 0)
    new_stone = kingdom['stone'] - cost.fetch('stone', 0)
    new_food = kingdom['food'] - cost.fetch('food', 0)
    new_gold = kingdom['gold'] - cost.fetch('gold', 0)

    db.execute(
      'UPDATE kingdoms SET wood = ?, stone = ?, food = ?, gold = ? WHERE id = ?',
      [new_wood, new_stone, new_food, new_gold, kingdom_id]
    )
  end
end

post '/buildings/:name/upgrade' do
  require_login!

  name = params[:name].to_s
  unless BUILDING_ORDER.include?(name)
    set_notice('Unknown building.')
    redirect '/kingdom'
  end

  kingdom = require_kingdom!

  building = db.get_first_row(
    'SELECT id, level FROM buildings WHERE kingdom_id = ? AND name = ?',
    [kingdom['id'], name]
  )
  unless building
  set_notice('Building not found.')
  redirect '/kingdom'
  end

  next_level = building['level'] + 1

  if name != 'Town Hall'
    town_hall = db.get_first_row(
     'SELECT level FROM buildings WHERE kingdom_id = ? AND name = ?',
     [kingdom['id'], 'Town Hall']
      )
     town_hall_level = town_hall ? town_hall['level'] : 0

    if next_level > town_hall_level + 1
     set_notice('Upgrade Town Hall first.')
     redirect '/kingdom'
    end
  end

  cost = building_upgrade_cost(name, next_level)

  unless can_afford?(kingdom, cost)
    set_notice('Not enough resources.')
    redirect '/kingdom'
  end

  spend_resources!(kingdom['id'], kingdom, cost)

  db.execute(
    'UPDATE buildings SET level = ? WHERE id = ?',
    [next_level, building['id']]
  )

  
  set_notice("#{name} upgraded to level #{next_level}.")
  redirect '/kingdom'
end
