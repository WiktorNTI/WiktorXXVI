helpers do
  def current_kingdom
    return nil unless current_user

    db.get_first_row('SELECT * FROM kingdoms WHERE user_id = ?', current_user['id'])
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

  def apply_tutorial_step!(kingdom_id, step)
    case step
    when 1
      db.execute(
        'INSERT OR IGNORE INTO buildings (kingdom_id, name, level) VALUES (?, ?, 1)',
        [kingdom_id, 'Town Hall']
      )
    when 2
      db.execute(
        'INSERT OR IGNORE INTO buildings (kingdom_id, name, level) VALUES (?, ?, 1)',
        [kingdom_id, 'Farm']
      )
    when 3
      db.execute(
        'INSERT OR IGNORE INTO buildings (kingdom_id, name, level) VALUES (?, ?, 1)',
        [kingdom_id, 'Lumberyard']
      )
    when 4
      db.execute(
        'INSERT OR IGNORE INTO buildings (kingdom_id, name, level) VALUES (?, ?, 1)',
        [kingdom_id, 'Quarry']
      )
    when 5
      db.execute(
        'INSERT OR IGNORE INTO buildings (kingdom_id, name, level) VALUES (?, ?, 1)',
        [kingdom_id, 'Barracks']
      )
    when 6
      grant_starter_pack!(kingdom_id)
      db.execute(
        'UPDATE units SET quantity = quantity + 10 WHERE kingdom_id = ? AND unit_type = ?',
        [kingdom_id, 'Spearman']
      )
    end
  end
end

get '/tutorial/start' do
  require_login!
  slim :tutorial_start
end

post '/tutorial/choice' do
  require_login!

  choice = params[:choice].to_s
  kingdom = require_kingdom!

  if choice == 'yes'
    db.execute(
      'UPDATE kingdoms SET tutorial_mode = ?, tutorial_step = ? WHERE id = ?',
      ['guided', 1, kingdom['id']]
    )
    redirect '/tutorial'
  else
    grant_starter_pack!(kingdom['id'])
    db.execute(
      'UPDATE kingdoms SET tutorial_mode = ?, tutorial_step = ? WHERE id = ?',
      ['done', 0, kingdom['id']]
    )
    redirect '/kingdom'
  end
end

get '/tutorial' do
  require_login!
  kingdom = require_kingdom!
  redirect '/kingdom' unless kingdom['tutorial_mode'] == 'guided'

  step = kingdom['tutorial_step'].to_i

  tutorial_text = case step
                  when 1
                    'Welcome to the world of League of Kingdoms. Your journey begins now. First, choose a location for your new kingdom and claim this land as your capital.'
                  when 2
                    'Excellent choice. Every great city needs leadership. Build your Town Hall to establish control and begin developing your kingdom.'
                  when 3
                    'Your city needs wood production. Build a Lumberyard to improve wood income.'
                  when 4
                    'Now strengthen stone production. Build a Quarry to increase stone income.'
                  when 5
                    'Your city is taking shape. Build a Barracks to unlock military training.'
                  when 6
                    'Tutorial complete. Your City Level 1 foundation is ready. You now receive starter resources and beginner troops so you can begin expanding.'
                  else
                    "You are now the ruler of #{kingdom['name']}. Continue building, upgrading, and growing your empire."
                  end

  slim :tutorial, locals: { step: step, tutorial_text: tutorial_text }
end

post '/tutorial/next' do
  require_login!
  kingdom = require_kingdom!
  redirect '/kingdom' unless kingdom['tutorial_mode'] == 'guided'

  step = kingdom['tutorial_step'].to_i
  apply_tutorial_step!(kingdom['id'], step)

  if step >= 6
    db.execute(
      'UPDATE kingdoms SET tutorial_mode = ?, tutorial_step = ? WHERE id = ?',
      ['done', 0, kingdom['id']]
    )
    redirect '/kingdom'
  else
    db.execute(
      'UPDATE kingdoms SET tutorial_step = ? WHERE id = ?',
      [step + 1, kingdom['id']]
    )
    redirect '/tutorial'
  end
end
