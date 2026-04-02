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
    Kingdom.set_resources!(db, kingdom_id, start['wood'], start['stone'], start['food'], start['gold'])
    Building.create_all!(db, kingdom_id, BUILDING_ORDER, 1)
    Unit.create_all!(db, kingdom_id, UNIT_ORDER)
  end

  def grant_guided_tutorial_setup!(kingdom_id)
    Kingdom.set_resources!(db, kingdom_id, 120, 120, 120, 120)
    Building.create_all!(db, kingdom_id, BUILDING_ORDER, 0)
    Building.set_all_level!(db, kingdom_id, 0)
    Unit.create_all!(db, kingdom_id, UNIT_ORDER)
    Unit.reset_all!(db, kingdom_id)
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
    rows   = Building.all_for_kingdom(db, kingdom_id)
    levels = {}
    rows.each { |row| levels[row['name']] = row['level'].to_i }

    spearman_row   = Unit.find(db, kingdom_id, 'Spearman')
    spearman_count = spearman_row ? spearman_row['quantity'].to_i : 0

    return 1 if levels.fetch('Town Hall', 0) < 1
    return 2 if levels.fetch('Farm', 0) < 1
    return 3 if levels.fetch('Lumberyard', 0) < 1
    return 4 if levels.fetch('Quarry', 0) < 1
    return 5 if levels.fetch('Barracks', 0) < 1
    return 6 if spearman_count < 1

    0
  end
end

# @route GET /tutorial/start
# @description Displays the tutorial start screen for biome and mode selection.
# @requires_login true
get '/tutorial/start' do
  require_login!
  slim :tutorial_start, locals: { notice: consume_notice }
end

# @route POST /tutorial/choice
# @description Saves the chosen capital biome and tutorial mode, then starts the game.
# @param choice [String] "yes" for guided tutorial, any other value for freeplay.
# @param biome [String] Capital biome (grassland, forest, mountain, or desert).
# @requires_login true
post '/tutorial/choice' do
  require_login!

  choice  = params[:choice].to_s
  biome   = params[:biome].to_s
  kingdom = require_kingdom!

  unless CAPITAL_BIOME_BONUSES.key?(biome)
    set_notice('Pick a capital biome before continuing.')
    redirect '/tutorial/start'
  end

  if choice == 'yes'
    grant_guided_tutorial_setup!(kingdom['id'])
    Kingdom.set_tutorial_with_biome!(db, kingdom['id'], 'guided', 1, biome)
    set_notice("Capital biome set to #{biome_label(biome)} (#{biome_bonus_text(biome)}).")
    city = ensure_capital_city!(kingdom)
    redirect "/city/#{city['id']}"
  else
    grant_starter_pack!(kingdom['id'])
    Kingdom.set_tutorial_with_biome!(db, kingdom['id'], 'done', 0, biome)
    set_notice("Capital biome set to #{biome_label(biome)} (#{biome_bonus_text(biome)}).")
    redirect '/kingdom'
  end
end

# @route GET /tutorial
# @description Redirects to the kingdom overview (tutorial is managed inline).
get '/tutorial' do
  redirect '/kingdom'
end

# @route POST /tutorial/next
# @description Redirects the player to their capital city to continue the guided tutorial.
# @requires_login true
post '/tutorial/next' do
  require_login!
  kingdom = require_kingdom!
  city    = ensure_capital_city!(kingdom)
  set_notice('Use the real building and unit buttons in the city page to progress tutorial steps.')
  redirect "/city/#{city['id']}"
end
