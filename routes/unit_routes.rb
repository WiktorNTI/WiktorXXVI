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

post '/train/:unit_type' do
  require_login!
  redirect_to = safe_return_path(params[:return_to], '/kingdom')

  unit_type = params[:unit_type].to_s
  unless UNIT_ORDER.include?(unit_type)
    set_notice('Unknown unit type.')
    redirect redirect_to
  end

  kingdom = require_kingdom!

  unit_row = db.get_first_row(
    'SELECT id, quantity FROM units WHERE kingdom_id = ? AND unit_type = ?',
    [kingdom['id'], unit_type]
  )
  unless unit_row
    set_notice('Unit row not found.')
    redirect redirect_to
  end

  barracks = db.get_first_row(
    'SELECT level FROM buildings WHERE kingdom_id = ? AND name = ?',
    [kingdom['id'], 'Barracks']
  )
  barracks_level = barracks ? barracks['level'] : 0

  unit_data = UNIT_DATA.fetch(unit_type)
  required = unit_data['required_barracks']

  if barracks_level < required
    set_notice("#{unit_type} requires Barracks level #{required}.")
    redirect redirect_to
  end

  train_cost = unit_training_cost(unit_data, kingdom)
  food_cost = train_cost['food']
  gold_cost = train_cost['gold']

  if kingdom['food'] < food_cost || kingdom['gold'] < gold_cost
    set_notice('Not enough food or gold.')
    redirect redirect_to
  end

  db.execute(
    'UPDATE kingdoms SET food = ?, gold = ? WHERE id = ?',
    [kingdom['food'] - food_cost, kingdom['gold'] - gold_cost, kingdom['id']]
  )

  db.execute(
    'UPDATE units SET quantity = ? WHERE id = ?',
    [unit_row['quantity'] + 1, unit_row['id']]
  )

  set_notice("Trained 1 #{unit_type}.")
  redirect redirect_to
end
