helpers do
  def building_upgrade_cost(name, next_level, kingdom = nil)
    base = BUILDING_BASE_COSTS[name]
    cost = {}
    base.each do |resource, amount|
      cost[resource] = amount * next_level
    end
    return cost unless kingdom && kingdom['tutorial_mode'].to_s == 'guided'
    return cost unless next_level == 1

    discounted = {}
    cost.each do |resource, amount|
      discounted[resource] = [(amount / 20.0).ceil, 1].max
    end
    discounted
  end

  def can_afford?(kingdom, cost)
    cost.all? { |resource, amount| kingdom[resource] >= amount }
  end
end

# @route POST /buildings/:name/upgrade
# @description Upgrades a building by one level if the kingdom can afford the cost.
# @param name [String] Building name (must be a valid entry in BUILDING_ORDER).
# @param return_to [String] Optional redirect path after the action.
# @requires_login true
post '/buildings/:name/upgrade' do
  require_login!
  redirect_to = safe_return_path(params[:return_to], '/kingdom')

  name = params[:name].to_s
  unless BUILDING_ORDER.include?(name)
    set_notice('Unknown building.')
    redirect redirect_to
  end

  kingdom  = require_kingdom!
  building = Building.find(db, kingdom['id'], name)
  unless building
    set_notice('Building not found.')
    redirect redirect_to
  end

  next_level = building['level'] + 1

  if name != 'Town Hall'
    town_hall       = Building.find(db, kingdom['id'], 'Town Hall')
    town_hall_level = town_hall ? town_hall['level'] : 0
    if next_level > town_hall_level + 1
      set_notice('Upgrade Town Hall first.')
      redirect redirect_to
    end
  end

  cost = building_upgrade_cost(name, next_level, kingdom)
  unless can_afford?(kingdom, cost)
    set_notice('Not enough resources.')
    redirect redirect_to
  end

  Kingdom.spend_resources!(db, kingdom['id'], kingdom, cost)
  Building.upgrade!(db, building['id'], next_level)

  set_notice("#{name} upgraded to level #{next_level}.")
  redirect redirect_to
end
