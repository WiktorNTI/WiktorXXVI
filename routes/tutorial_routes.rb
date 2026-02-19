helpers do
  def current_kingdom
    return nil unless current_user

    db.get_first_row('SELECT * FROM kingdoms WHERE user_id = ?', current_user['id'])
  end

  def grant_starter_pack!(kingdom_id)
    db.execute(
      'UPDATE kingdoms SET wood = 120, stone = 120, food = 120, gold = 120 WHERE id = ?',
      [kingdom_id]
    )

    ['Town Hall', 'Farm', 'Barracks'].each do |name|
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
        [kingdom_id, 'Barracks']
      )
    when 4
      grant_starter_pack!(kingdom_id)
      db.execute(
        'UPDATE units SET quantity = quantity + 10 WHERE kingdom_id = ? AND unit_type = ?',
        [kingdom_id, 'Spearman']
      )
    end
  end
end

get '/tutorial/start' do
  redirect '/login' unless current_user
  slim :tutorial_start
end

post '/tutorial/choice' do
  redirect '/login' unless current_user

  choice = params[:choice].to_s
  kingdom = db.get_first_row('SELECT id FROM kingdoms WHERE user_id = ?', current_user['id'])
  redirect '/login' unless kingdom

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
  redirect '/login' unless current_user

  kingdom = db.get_first_row('SELECT id, name, tutorial_mode, tutorial_step FROM kingdoms WHERE user_id = ?', current_user['id'])
  redirect '/kingdom' unless kingdom
  redirect '/kingdom' unless kingdom['tutorial_mode'] == 'guided'

  step = kingdom['tutorial_step'].to_i

  tutorial_text = case step
                  when 1
                    'Welcome to the world of League of Kingdoms. Your journey begins now. First, choose a location for your new kingdom and claim this land as your capital.'
                  when 2
                    'Excellent choice. Every great city needs leadership. Build your Town Hall to establish control and begin developing your kingdom.'
                  when 3
                    'Your people are gathering. To feed them, you need production. Build a Farm so your city can generate food for growth and future troops.'
                  when 4
                    'Your city is taking shape. Now build a Barracks to train soldiers and protect your lands from future threats.'
                  when 5
                    'Tutorial complete. Your City Level 1 foundation is ready. You now receive starter resources and beginner troops so you can begin expanding.'
                  else
                    "You are now the ruler of #{kingdom['name']}. Continue building, upgrading, and growing your empire."
                  end

  slim :tutorial, locals: { step: step, tutorial_text: tutorial_text }
end

post '/tutorial/next' do
  redirect '/login' unless current_user

  kingdom = db.get_first_row('SELECT id, tutorial_mode, tutorial_step FROM kingdoms WHERE user_id = ?', current_user['id'])
  redirect '/kingdom' unless kingdom
  redirect '/kingdom' unless kingdom['tutorial_mode'] == 'guided'

  step = kingdom['tutorial_step'].to_i
  apply_tutorial_step!(kingdom['id'], step)

  if step >= 5
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
