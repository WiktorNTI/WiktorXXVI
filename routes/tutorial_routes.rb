helpers do
  def biome_bonus_text(biome)
    bonus = CAPITAL_BIOME_BONUSES[biome]
    return 'No bonus' unless bonus

    resource, percent = bonus.first
    "+#{percent}% #{resource}"
  end

  def biome_label(biome)
    biome.to_s.split('_').map(&:capitalize).join(' ')
  end

  def grant_starter_pack!(kingdom_id)
    start = ECONOMY[:start_resources]
    db.execute(
      'UPDATE kingdoms SET wood = ?, stone = ?, food = ?, gold = ? WHERE id = ?',
      [start['wood'], start['stone'], start['food'], start['gold'], kingdom_id]
    )

    BUILDING_ORDER.each do |name|
      db.execute(
        'INSERT OR IGNORE INTO buildings (kingdom_id, name, level) VALUES (?, ?, 1)',
        [kingdom_id, name]
      )
    end

    ['Spearman', 'Archer', 'Cavalry'].each do |unit|
      db.execute(
        'INSERT OR IGNORE INTO units (kingdom_id, unit_type, quantity) VALUES (?, ?, 0)',
        [kingdom_id, unit]
      )
    end
  end

  def grant_guided_tutorial_setup!(kingdom_id)
    db.execute(
      'UPDATE kingdoms SET wood = ?, stone = ?, food = ?, gold = ? WHERE id = ?',
      [120, 120, 120, 120, kingdom_id]
    )

    BUILDING_ORDER.each do |name|
      db.execute(
        'INSERT OR IGNORE INTO buildings (kingdom_id, name, level) VALUES (?, ?, 0)',
        [kingdom_id, name]
      )
    end
    db.execute('UPDATE buildings SET level = 0 WHERE kingdom_id = ?', [kingdom_id])

    UNIT_ORDER.each do |unit|
      db.execute(
        'INSERT OR IGNORE INTO units (kingdom_id, unit_type, quantity) VALUES (?, ?, 0)',
        [kingdom_id, unit]
      )
    end
    db.execute('UPDATE units SET quantity = 0 WHERE kingdom_id = ?', [kingdom_id])
  end

  def tutorial_step_text(kingdom_name, step)
    case step
    when 1
      "Step 1: Welcome to #{kingdom_name}. You are in your capital city view. Upgrade Town Hall to Level 1."
    when 2
      'Step 2: In your city page, upgrade Farm to Level 1 and watch food income in Resources.'
    when 3
      'Step 3: In your city page, upgrade Lumberyard to Level 1 and check wood income.'
    when 4
      'Step 4: In your city page, upgrade Quarry to Level 1. Stone income will increase.'
    when 5
      'Step 5: In your city page, upgrade Barracks to Level 1.'
    when 6
      'Step 6: Train 1 Spearman in this city.'
    else
      'Tutorial complete. Keep upgrading buildings, training units, and expanding through the map.'
    end
  end

  def guided_step_from_state(kingdom_id)
    rows = db.execute('SELECT name, level FROM buildings WHERE kingdom_id = ?', [kingdom_id])
    levels = rows.each_with_object({}) { |row, memo| memo[row['name']] = row['level'].to_i }
    units = db.get_first_row(
      'SELECT quantity FROM units WHERE kingdom_id = ? AND unit_type = ?',
      [kingdom_id, 'Spearman']
    )
    spearman_count = units ? units['quantity'].to_i : 0

    return 1 if levels.fetch('Town Hall', 0) < 1
    return 2 if levels.fetch('Farm', 0) < 1
    return 3 if levels.fetch('Lumberyard', 0) < 1
    return 4 if levels.fetch('Quarry', 0) < 1
    return 5 if levels.fetch('Barracks', 0) < 1
    return 6 if spearman_count < 1

    0
  end
end

get '/tutorial/start' do
  require_login!
  slim :tutorial_start, locals: { notice: consume_notice }
end

post '/tutorial/choice' do
  require_login!

  choice = params[:choice].to_s
  biome = params[:biome].to_s
  kingdom = require_kingdom!
  unless CAPITAL_BIOME_BONUSES.key?(biome)
    set_notice('Pick a capital biome before continuing.')
    redirect '/tutorial/start'
  end

  if choice == 'yes'
    grant_guided_tutorial_setup!(kingdom['id'])
    db.execute(
      'UPDATE kingdoms SET tutorial_mode = ?, tutorial_step = ?, capital_biome = ? WHERE id = ?',
      ['guided', 1, biome, kingdom['id']]
    )
    set_notice("Capital biome set to #{biome_label(biome)} (#{biome_bonus_text(biome)}).")
    city = ensure_capital_city!(kingdom)
    redirect "/city/#{city['id']}"
  else
    grant_starter_pack!(kingdom['id'])
    db.execute(
      'UPDATE kingdoms SET tutorial_mode = ?, tutorial_step = ?, capital_biome = ? WHERE id = ?',
      ['done', 0, biome, kingdom['id']]
    )
    set_notice("Capital biome set to #{biome_label(biome)} (#{biome_bonus_text(biome)}).")
    redirect '/kingdom'
  end
end

get '/tutorial' do
  redirect '/kingdom'
end

post '/tutorial/next' do
  require_login!
  kingdom = require_kingdom!
  city = ensure_capital_city!(kingdom)
  set_notice('Use the real building and unit buttons in the city page to progress tutorial steps.')
  redirect "/city/#{city['id']}"
end
