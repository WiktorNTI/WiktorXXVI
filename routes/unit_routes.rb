helpers do
  def unit_training_cost(unit_data, kingdom = nil)
    food_cost = unit_data['food']
    gold_cost = unit_data['gold']
    return { 'food' => food_cost, 'gold' => gold_cost } unless kingdom && kingdom['tutorial_mode'].to_s == 'guided'

    {
      'food' => [(food_cost / 10.0).ceil, 1].max,
      'gold' => [(gold_cost / 10.0).ceil, 1].max
    }
  end
end

# @route POST /train/:unit_type
# @description Trains one unit of the given type if the kingdom has enough food and gold.
# @param unit_type [String] Unit type (must be a valid entry in UNIT_ORDER).
# @param return_to [String] Optional redirect path after the action.
# @requires_login true
post '/train/:unit_type' do
  require_login!
  redirect_to = safe_return_path(params[:return_to], '/kingdom')

  unit_type = params[:unit_type].to_s
  unless UNIT_ORDER.include?(unit_type)
    set_notice('Unknown unit type.')
    redirect redirect_to
  end

  kingdom  = require_kingdom!
  unit_row = Unit.find(db, kingdom['id'], unit_type)
  unless unit_row
    set_notice('Unit row not found.')
    redirect redirect_to
  end

  barracks       = Building.find(db, kingdom['id'], 'Barracks')
  barracks_level = barracks ? barracks['level'] : 0
  unit_data      = UNIT_DATA[unit_type]
  required       = unit_data['required_barracks']

  if barracks_level < required
    set_notice("#{unit_type} requires Barracks level #{required}.")
    redirect redirect_to
  end

  train_cost = unit_training_cost(unit_data, kingdom)
  food_cost  = train_cost['food']
  gold_cost  = train_cost['gold']

  if kingdom['food'] < food_cost || kingdom['gold'] < gold_cost
    set_notice('Not enough food or gold.')
    redirect redirect_to
  end

  Kingdom.spend_food_gold!(db, kingdom['id'], kingdom, food_cost, gold_cost)
  Unit.set_quantity!(db, unit_row['id'], unit_row['quantity'] + 1)

  set_notice("Trained 1 #{unit_type}.")
  redirect redirect_to
end
