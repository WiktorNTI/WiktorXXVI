post '/train/:unit_type' do
  require_login!

  unit_type = params[:unit_type].to_s
  unless UNIT_ORDER.include?(unit_type)
    set_notice('Unknown unit type.')
    redirect '/kingdom'
  end

  kingdom = require_kingdom!

  unit_row = db.get_first_row(
    'SELECT id, quantity FROM units WHERE kingdom_id = ? AND unit_type = ?',
    [kingdom['id'], unit_type]
  )
  unless unit_row
    set_notice('Unit row not found.')
    redirect '/kingdom'
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
    redirect '/kingdom'
  end

  food_cost = unit_data['food']
  gold_cost = unit_data['gold']

  if kingdom['food'] < food_cost || kingdom['gold'] < gold_cost
    set_notice('Not enough food or gold.')
    redirect '/kingdom'
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
  redirect '/kingdom'
end
